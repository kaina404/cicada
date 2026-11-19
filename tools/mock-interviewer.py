#!/usr/bin/env python3
"""Mock interviewer for walkthrough cards (P4): drives the running dev build through lsctl.

Each scenario opens a fresh meeting, plays interviewer and candidate lines, board text or board images,
and checks the card the app shows: structural checks from `coachCardState`, semantic ones judged by
DeepSeek. Text injection is repeatable but skips ASR, endpointing by sound and real screens.

  scripts/build.sh && open build/Cicada.app          # dev build with debug control
  python3 -I tools/mock-interviewer.py [AC-05 ...]   # all scenarios, or the named ones
  FRAMES=<dir of P0 frames> for AC-08.  Writes docs/evaluations/walkthrough-acceptance-<date>.json
  Injected lines count as heard speech, so long runs no longer end themselves after 10 silent minutes.
  `render: <name>` saves the notes panel to <run dir>/<id>-<name>.png (diagram cards).
  PACE=1 plays at speaking speed (interviewer lines and `me_card` read at ~150 words a minute); default 0.
"""
import datetime, json, os, re, subprocess, sys, time, urllib.request
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
LSCTL = os.path.join(HERE, "lsctl")
KEY_FILE = os.path.expanduser("~/Library/Application Support/LiveSubs Dev/ai-key-deepseek")
# Founder lines and the judge: DeepSeek, or the local Codex login (GPT-6.1 Terra, reasoning off) with
# MOCK_LLM=codex (each codex exec call carries about 18,000 tokens of its own instructions).
MOCK_LLM = os.environ.get("MOCK_LLM", "deepseek")
PACE = float(os.environ.get("PACE", "0"))
RUN_DIR = os.path.join(HERE, "..", "docs", "evaluations", "runs", datetime.datetime.now().strftime("%Y%m%d-%H%M%S"))


def speak_time(text):
    """Seconds a person needs to say `text` at ~150 words a minute, scaled by PACE."""
    return PACE * len(text.split()) / 2.5


def type_code(card):
    """The code of the card's TYPE edit, lines joined by a literal \\n as coachOCR takes them; '' when none."""
    t = card.get("type", "none")
    return "" if t == "none" or ": " not in t else t.split(": ", 1)[1].replace(" ⏎ ", "\\n")


def lsctl(command, timeout=5):
    r = subprocess.run([LSCTL, "--json", "--timeout", str(timeout), command], capture_output=True, text=True)
    try:
        return json.loads(r.stdout or "{}")
    except json.JSONDecodeError:
        return {"ok": False, "raw": r.stdout + r.stderr}


FIELDS = ["mode", "busy", "failed", "phase", "requests", "keeps", "first_ms", "problem", "adopted", "constraints",
          "abandoned", "asides", "problems", "written", "heard", "say", "type", "then", "fix", "past", "prepared"]


def card_state():
    reply = lsctl("coachCardState")
    log = "\n".join(reply.get("log") or [])
    m = re.search(r"coach card: (.*)", log)
    if not m:
        return None
    line = m.group(1)
    # Split on the known keys, in order, so values may contain spaces.
    out, pattern = {}, r"(\b(?:" + "|".join(FIELDS) + r")=)"
    parts = re.split(pattern, line)
    for i in range(1, len(parts) - 1, 2):
        out[parts[i][:-1]] = parts[i + 1].strip()
    return out


def settle(before_requests, timeout=40):
    """Wait until a request newer than `before_requests` finished, or nothing started and things are quiet."""
    deadline = time.time() + timeout
    started = False
    while time.time() < deadline:
        s = card_state()
        if s:
            req = int(s.get("requests", 0) or 0)
            if req > before_requests:
                started = True
            if started and s.get("busy") == "false":
                time.sleep(1.0)  # let a queued follow-up start
                s2 = card_state()
                if s2 and s2.get("busy") == "false":
                    return s2
        time.sleep(0.5)
    return card_state()


def llm(prompt, max_tokens=200, temperature=0.4):
    """One reply to `prompt` from the model named by MOCK_LLM."""
    if MOCK_LLM == "deepseek":
        body = {"model": "deepseek-flash", "temperature": temperature, "max_tokens": max_tokens,
                "thinking": {"type": "disabled"}, "messages": [{"role": "user", "content": prompt}]}
        req = urllib.request.Request("https://api.deepseek.com/chat/completions", data=json.dumps(body).encode(),
                                     headers={"Authorization": "Bearer " + open(KEY_FILE).read().strip(),
                                              "Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r)["choices"][0]["message"]["content"].strip()
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "reply.txt")
        cmd = ["codex", "exec", "-m", "gpt-6.1-terra", "-c", 'model_reasoning_effort="none"', "-c", "mcp_servers={}",
               "-c", 'web_search="disabled"', "--disable", "shell_tool", "--disable", "unified_exec", "--disable", "plugins",
               "--disable", "memories", "--ephemeral", "--skip-git-repo-check", "-s", "read-only", "-C", tmp, "-o", out, "-"]
        for attempt in range(3):
            done = subprocess.run(cmd, input=prompt, capture_output=True, text=True, timeout=180)
            if done.returncode == 0 and os.path.exists(out) and open(out).read().strip():
                return open(out).read().strip()
            time.sleep(2)
        raise RuntimeError("codex exec failed: " + done.stderr[-300:])


def judge(transcript, card, criterion, more=(), strict=False):
    shown = "HEARD: {heard}\nSAY: {say}\nTYPE: {type}\nTHEN: {then}".format(**card)
    # The candidate pages on with "next": the follow-up cards are part of the same answer (R-01 was graded
    # on its first card only).
    for i, say in enumerate(more):
        shown += f"\n\nNext card {i + 1} (read right after):\nSAY: {say}"
    if strict:
        # The wallet runs passed W7 with half its release checklist: "at least two" let one point stand for a list.
        rule = ("First list every required point of the criterion, one line each, naming the point in a few "
                "words and then yes or no (for example `- final balances: no`); at most 12 lines. Points after \"such as\", \"for example\" or \"e.g.\" are examples: one correct example "
                "covers that point. Every other point is required, each part of a list included (\"A, B and C\" "
                "is three points). \"Either A or B\" is one point, covered by either. The same amount in other units counts (2000 cents is 20 dollars). Then reply on the last line with PASS or FAIL, a colon, and the missing "
                "points. PASS only when every required point is yes and the answer says nothing wrong. Every "
                "\"does not\" condition must hold. Count a point only when the answer states it plainly.")
    else:
        rule = ("Reply with PASS or FAIL, a colon, and a short reason. The answer is spoken in a few short "
                "sentences, so a list of points in the criterion gives examples: PASS when the answer covers at "
                "least two of them correctly (all of them if fewer than two are listed) and says nothing wrong. "
                "Every \"does not\" condition must hold.")
    if strict:
        # The candidate's real resume: "about 1 s" and Bugly come from it, and were failed as invented without it.
        resume = json.load(open(Path(__file__).with_name("copilot-interview-background.json"))).get("candidate_resume")
        rule += "\n\nThe candidate's real background (facts from it are not invented):\n" + json.dumps(resume, ensure_ascii=False)
        # The user allows plausible stories (a bug, a risk, a disagreement) that the background doesn't record;
        # the Codex judge failed run 2052's P3 for exactly that. Only hard facts must come from it.
        rule += ("\n\nA story or detail the background doesn't record is fine when it is plausible for that employer "
                 "and project. Count as wrong only hard facts that conflict with the background or are missing from "
                 "it: numbers, dates, employers, titles, team sizes, salaries, or work moved to another employer.")
        # The dev build's knowledge (profile, past companies, projects) holds facts the candidate approved, such as
        # "about 300,000 trip planning requests a day", which the resume alone doesn't have.
        folder = Path.home() / "Library/Application Support/LiveSubs Dev/knowledge"
        approved = [(folder / n).read_text() for n in ("00_profile.md", "02_companies_past.md", "03_projects.md") if (folder / n).exists()]
        if approved:
            rule += "\n\nFacts the candidate approved (not invented either):\n" + "\n\n".join(approved)
    prompt = ("You grade an interview-coaching answer against one criterion. " + rule +
              "\n\nConversation so far:\n" + "\n".join(transcript) +
              "\n\nCard shown to the candidate:\n" + shown + "\n\nCriterion: " + criterion)
    text = llm(prompt, max_tokens=500 if strict else 120, temperature=0)
    if strict:
        verdict = next((l.strip() for l in reversed(text.splitlines()) if re.match(r"\W*(PASS|FAIL)\b", l.strip(), re.I)), "FAIL: no verdict")
        # The verdict line once read "PASS: FAIL: …" over a point marked no: a point marked no always fails.
        missing = [l.strip() for l in text.splitlines() if re.match(r"\s*-\s.*:\s*no\b", l, re.I)]
        ok = re.match(r"\W*PASS(?!\W*FAIL)", verdict, re.I) is not None and not missing
        return ok, ("PASS" if ok else "FAIL") + ": " + verdict + "\n" + text
    return text.upper().startswith("PASS"), text


def check(spec, card, transcript, marks):
    results = []
    def add(name, ok, detail=""):
        results.append({"check": name, "pass": bool(ok), "detail": detail})
    t = card.get("type", "none")
    if "type" in spec: add("type", (t != "none") == spec["type"], t[:120])
    if spec.get("type_not_code"): add("type_not_code", t == "none" or t.startswith("draw@"), t[:120])
    if "type_contains" in spec: add("type_contains", spec["type_contains"].lower() in t.lower(), t[:120])
    if "adopted_contains" in spec: add("adopted_contains", spec["adopted_contains"].lower() in card.get("adopted", "").lower(), card.get("adopted"))
    if "adopted_not_contains" in spec: add("adopted_not_contains", spec["adopted_not_contains"].lower() not in card.get("adopted", "").lower(), card.get("adopted"))
    if "constraint_contains" in spec: add("constraint_contains", spec["constraint_contains"].lower() in card.get("constraints", "").lower(), card.get("constraints"))
    if "problems_min" in spec: add("problems_min", int(card.get("problems", 0)) >= spec["problems_min"], card.get("problems"))
    if "problems_max" in spec: add("problems_max", int(card.get("problems", 0)) <= spec["problems_max"], card.get("problems"))
    if spec.get("requests_unchanged"): add("requests_unchanged", card.get("requests") == marks.get("requests"), f'{marks.get("requests")} -> {card.get("requests")}')
    if spec.get("has_card"): add("has_card", bool(card.get("say")), card.get("say", "")[:80])
    if "type_not_contains" in spec: add("type_not_contains", spec["type_not_contains"].lower() not in t.lower(), t[:120])
    if "constraint_not_contains" in spec: add("constraint_not_contains", spec["constraint_not_contains"].lower() not in card.get("constraints", "").lower(), card.get("constraints"))
    if "say_max_sentences" in spec:
        n = len([x for x in re.split(r"(?<=[.!?])\s+", card.get("say", "").strip()) if x])
        add("say_max_sentences", 0 < n <= spec["say_max_sentences"], f"{n} sentences")
    if "say_not_contains" in spec: add("say_not_contains", spec["say_not_contains"].lower() not in card.get("say", "").lower(), card.get("say", "")[:120])
    return results


def run(scenario):
    lsctl("stop"); time.sleep(1.5)
    for c in ["coachLanguage:english", "coachCards:on", "assistant:on", "start:user"]:
        lsctl(c)
    time.sleep(3)
    transcript, marks, steps, board, t0, segment = [], {}, [], [], time.time(), ""
    pending = None  # (check step, spec, card, transcript): judged once the candidate has read the card(s)
    def grade(more=()):
        nonlocal pending
        if not pending: return
        st, spec, card, said = pending; pending = None
        ok, why = judge(said, card, spec["judge"], more)
        st["results"].append({"check": "judge", "pass": ok, "detail": why})
        print(f'  {"PASS" if ok else "FAIL"} judge: {why}')
    for step in scenario["steps"]:
        if pending and "me_card" not in step: grade()
        s = card_state() or {}
        before = int(s.get("requests", 0) or 0)
        if "segment" in step:
            segment, board = step["segment"], []  # a new segment starts on a clean board
            print(f'  -- {segment} @ {int(time.time() - t0)}s'); continue
        if "them" in step:
            time.sleep(speak_time(step["them"]))
            # Count again after the pause: real system audio during it ("how") had started a card,
            # and that stray card was taken as the answer.
            before = int((card_state() or {}).get("requests", 0) or 0)
            transcript.append("Interviewer: " + step["them"]); lsctl("themSaid:" + step["them"]); asked = time.time()
            s = settle(before)
            steps.append({"segment": segment, "at": int(asked - t0), "them": step["them"],
                          "settle_s": round(time.time() - asked, 1), "first_ms": (s or {}).get("first_ms")})
            # A settled state is not proof of a new answer: the request count must have moved and not failed.
            fresh = bool(s) and int(s.get("requests", 0) or 0) > before and s.get("busy") == "false" and s.get("failed") == "false"
            steps[-1].update({"card": s or {}, "results": [{"check": "answered", "pass": fresh,
                          "detail": "no state" if not s else f'requests {before}->{s.get("requests")} busy={s.get("busy")} failed={s.get("failed")}'}]})
            if not fresh: print(f'  FAIL answered: {steps[-1]["results"][0]["detail"]}')
        elif "them_nowait" in step:
            transcript.append("Interviewer: " + step["them_nowait"]); lsctl("themSaid:" + step["them_nowait"]); time.sleep(step.get("gap", 0.3))
        elif "me_card" in step:
            # The candidate reads the card aloud sentence by sentence, as with read-along; `next` follows THEN.
            more = []
            for k in range(1 + step.get("next", 0)):
                if k:
                    b = int((card_state() or {}).get("requests", 0) or 0); lsctl("coachCardNext"); settle(b)
                say = (card_state() or {}).get("say", "")
                if k: more.append(say)
                for sentence in [x for x in re.split(r"(?<=[.!?])\s+", say.strip()) if x]:
                    time.sleep(speak_time(sentence)); transcript.append("Candidate: " + sentence); lsctl("meSaid:" + sentence)
                time.sleep(0.4)
            grade(more)
        elif "ocr_card" in step:
            # The candidate writes the card's TYPE on the board: the board text grows by that code.
            code = type_code(card_state() or {})
            if code:
                board.append(code); time.sleep(speak_time(code))
            text = "\\n".join(board) if board else step["ocr_card"]
            transcript.append("[board] " + text.replace("\\n", " | ")); lsctl("coachOCR:" + text)
        elif "me" in step:
            transcript.append("Candidate: " + step["me"]); lsctl("meSaid:" + step["me"]); time.sleep(0.4)
        elif "ocr" in step:
            transcript.append("[board] " + step["ocr"].replace("\\n", " | ")); lsctl("coachOCR:" + step["ocr"])
        elif "board" in step:
            path = step["board"].replace("$FRAMES", os.environ.get("FRAMES", ""))
            transcript.append("[board image] " + os.path.basename(path)); lsctl("coachBoard:" + path); time.sleep(2)
        elif "render" in step:
            # Saves the notes panel as it looks now (a diagram card renders as a picture) next to the results.
            os.makedirs(RUN_DIR, exist_ok=True)
            png = os.path.join(RUN_DIR, f'{scenario["id"]}-{step["render"]}.png')
            lsctl("assistantRender:" + png, timeout=15); steps.append({"segment": segment, "render": os.path.basename(png), "results": []})
        elif "wait" in step:
            time.sleep(step["wait"])
        elif "next" in step:
            lsctl("coachCardNext"); s = settle(before)
        elif "mark" in step:
            marks[step["mark"]] = (card_state() or {}).get(step["mark"])
        elif "check" in step:
            card = card_state()
            res = check(step["check"], card, transcript, marks) if card else [{"check": "state", "pass": False, "detail": "coachCardState unreadable"}]
            card = card or {}
            steps.append({"segment": segment, "at": int(time.time() - t0), "card": card, "results": res})
            for r in res:
                print(f'  {"PASS" if r["pass"] else "FAIL"} {r["check"]}: {r["detail"]}')
            if "judge" in step["check"] and card: pending = (steps[-1], step["check"], card, list(transcript))
    grade()
    checks = [r for st in steps for r in st["results"]]
    ok = bool(checks) and all(r["pass"] for r in checks)
    return {"id": scenario["id"], "name": scenario["name"], "pass": ok, "minutes": round((time.time() - t0) / 60, 1),
            "checks": steps, "transcript": transcript}


def main():
    # SCENARIOS=<file in tools/> runs another script, e.g. walkthrough-newsfeed.json (a full interview).
    name = os.environ.get("SCENARIOS", "walkthrough-scenarios.json")
    data = json.load(open(os.path.join(HERE, name)))
    wanted = set(sys.argv[1:])
    results = []
    for sc in data["scenarios"]:
        if wanted and sc["id"] not in wanted:
            continue
        print(f'{sc["id"]} {sc["name"]}')
        results.append(run(sc))
        print(f'  => {"PASS" if results[-1]["pass"] else "FAIL"}')
    lsctl("stop")
    # basename: an absolute SCENARIOS path made the results overwrite the script itself.
    stem = "walkthrough-acceptance" if name == "walkthrough-scenarios.json" else os.path.splitext(os.path.basename(name))[0]
    run_dir = RUN_DIR
    os.makedirs(run_dir, exist_ok=True)
    out = os.path.join(run_dir, f"{stem}.json")
    json.dump({"date": str(datetime.date.today()), "method": "lsctl text injection into the dev build; DeepSeek judge",
               "passed": sum(r["pass"] for r in results), "total": len(results), "scenarios": results},
              open(out, "w"), indent=1, ensure_ascii=False)
    print(f'{sum(r["pass"] for r in results)}/{len(results)} scenarios passed -> {os.path.relpath(out)}')


if __name__ == "__main__":
    main()
