"""Live ActAI wallet interview (90-minute handbook order) against the running dev build.

The candidate reads each coach card aloud (meSaid, sentence by sentence) and writes its TYPE on the board.
The interviewer is DeepSeek playing the founder: fixed handbook questions, plus follow-ups and two plan
changes generated from what the candidate actually said. Every card is graded by a separate DeepSeek judge,
strictly: every required point of the criterion must be covered.
Run from the repo root:  PACE=1 [AUDIO=1] python3 -I -u <this file>
"""
import datetime, importlib.util, json, os, re, subprocess, sys, time, urllib.request
from pathlib import Path

root = Path.cwd()
spec = importlib.util.spec_from_file_location("interviewer", root / "tools/mock-interviewer.py")
qa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qa)
out = root / "docs/evaluations/runs" / ("wallet-live-" + datetime.datetime.now().strftime("%Y%m%d-%H%M"))
out.mkdir(parents=True, exist_ok=True)
(out / "driver.py").write_text(Path(__file__).read_text())
KEY = open(qa.KEY_FILE).read().strip()

SETTING = ("Fictional wallet business rules (only the interviewer may state them): signed-in users, centralized "
           "balance accounts, single currency USD, internal peer-to-peer transfers, zero fees. Balance, transfer, "
           "history and details are in scope. Cached reads work offline; submitting money needs the network. The "
           "server owns the authoritative ledger and limits. Top-up, withdrawal and multi-currency are out of scope.")

transcript, turns, board = [], [], []


def deepseek(prompt, max_tokens=200, temperature=0.4):
    body = {"model": "deepseek-flash", "temperature": temperature, "max_tokens": max_tokens,
            "thinking": {"type": "disabled"}, "messages": [{"role": "user", "content": prompt}]}
    req = urllib.request.Request("https://api.deepseek.com/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)["choices"][0]["message"]["content"].strip()


def founder(task):
    """The founder's next spoken line, written from the conversation so far."""
    asked = [t["question"] for t in turns]
    prompt = ("You are the founder of ActAI (an agent-first mobile communication app) interviewing an Android "
              "engineer, live, in English. " + SETTING + "\n\nConversation so far (last 40 lines):\n" +
              "\n".join(transcript[-40:]) + "\n\nQuestions you already asked:\n- " + "\n- ".join(asked[-12:]) +
              "\n\nTask: " + task + "\nRules: speak naturally, at most three short sentences, one question only, "
              "quote or name a concrete thing the candidate just said, do not repeat an earlier question, do not "
              "give away the answer. Reply with the spoken line only, no quotes or labels.")
    return deepseek(prompt).strip('"')


def say(lines):
    """The candidate reads `lines` aloud, sentence by sentence, at PACE."""
    for sentence in [x for x in re.split(r"(?<=[.!?])\s+", lines.strip()) if x]:
        time.sleep(qa.speak_time(sentence)); transcript.append("Candidate: " + sentence); qa.lsctl("meSaid:" + sentence)
    time.sleep(0.4)


def sentences(text):
    return [x for x in re.split(r"(?<=[.!?])\s+", (text or "").strip()) if x]


def read(card, step):
    """Read the card aloud; when the coach updates it mid-reading (the 1101 blind spot: W1 got its MVP only at
    28 s), go on with the updated card's sentences not read yet. Returns the last card shown."""
    req, shown, done = int(card.get("requests", 0) or 0), card.get("say", ""), set()
    queue = sentences(shown)
    while True:
        while queue:
            s = queue.pop(0)
            time.sleep(qa.speak_time(s)); transcript.append("Candidate: " + s); qa.lsctl("meSaid:" + s); done.add(s)
            st = qa.card_state() or {}
            if (int(st.get("requests", 0) or 0) > req and st.get("busy") == "false" and st.get("say")
                    and st.get("say") != shown):
                req, shown, card = int(st["requests"]), st["say"], st
                step["updates"].append(shown); print(f"  UPDATE: {shown[:200]}", flush=True)
                queue = [x for x in sentences(shown) if x not in done]
        # One last look: an update that lands right after the last sentence is still read.
        time.sleep(2.0)
        st = qa.card_state() or {}
        if (int(st.get("requests", 0) or 0) > req and st.get("busy") == "false" and st.get("say")
                and st.get("say") != shown):
            req, shown, card = int(st["requests"]), st["say"], st
            step["updates"].append(shown); print(f"  UPDATE: {shown[:200]}", flush=True)
            queue = [x for x in sentences(shown) if x not in done]
            if queue:
                continue
        return card


def quiet(still=4.0, cap=30.0):
    """Let updates of the previous answer finish before the interviewer speaks (1139: one finished mid-question)."""
    end, last, since = time.monotonic() + cap, None, time.monotonic()
    while time.monotonic() < end:
        st = qa.card_state() or {}
        key = (st.get("requests"), st.get("busy"))
        if key != last:
            last, since = key, time.monotonic()
        elif st.get("busy") == "false" and time.monotonic() - since >= still:
            return
        time.sleep(0.5)


def turn(name, question, criterion, kind="handbook", draw=None):
    print(f"\n[{name}] ({kind}) {question}", flush=True)
    quiet(); before = int((qa.card_state() or {}).get("requests", 0) or 0)
    transcript.append("Interviewer: " + question); interviewer(question); clock = time.monotonic()
    card = qa.settle(before, timeout=45) or {}
    # 1139: an in-reading update of the previous answer finished while the interviewer was still speaking, and
    # W2-seq and W4 were graded on it. A card that still answers the previous question is not this turn's.
    for _ in range(2):
        if not (turns and card.get("heard") and card.get("heard") == turns[-1].get("last_heard")):
            break
        card = qa.settle(int(card.get("requests", 0) or 0), timeout=45) or card
    fresh = (int(card.get("requests", 0) or 0) > before and card.get("busy") == "false"
             and card.get("failed") == "false" and bool(card.get("say")))
    step = dict(name=name, kind=kind, question=question, fresh=fresh, seconds=round(time.monotonic() - clock, 1),
                first_ms=card.get("first_ms"), card=card, more=[], updates=[])
    print(f"  fresh={fresh} {step['seconds']}s first_ms={card.get('first_ms')} type={card.get('type', 'none')[:70]}", flush=True)
    print(f"  SAY: {card.get('say', '')[:300]}", flush=True)
    if card.get("type", "none") != "none":
        png = out / f"{name}.png"; qa.lsctl(f"assistantRender:{png}", timeout=15)
        step["snapshot"] = png.name if png.exists() else None
    said = list(transcript)
    last = read(card, step)
    code = qa.type_code(last)
    if code:
        board.append(code); time.sleep(qa.speak_time(code))
        transcript.append("[board] " + code.replace("\\n", " | ")); qa.lsctl("coachOCR:" + "\\n".join(board))
    # A candidate who has more to say ("Next, I'll cover …") goes on once before the interviewer speaks.
    then = last.get("then", "")
    if then and not then.lower().startswith("wait"):
        b = int((qa.card_state() or {}).get("requests", 0) or 0); qa.lsctl("coachCardNext")
        nxt = qa.settle(b, timeout=45) or {}
        if nxt.get("say") and nxt.get("say") != last.get("say"):
            step["more"].append(nxt.get("say")); print(f"  NEXT: {nxt.get('say', '')[:200]}", flush=True); say(nxt["say"])
            c2 = qa.type_code(nxt)
            if c2:
                board.append(c2); qa.lsctl("coachOCR:" + "\\n".join(board))
    if draw:
        t = card.get("type", "none")
        step["diagram"] = {"want": draw, "pass": t.split("@", 1)[0] in ("draw", "replace", "add") and (draw == "draw" or draw.lower() in t.lower()), "type": t[:80]}
        print(f"  {'PASS' if step['diagram']['pass'] else 'FAIL'} diagram {draw}: {t[:60]}", flush=True)
    ok, why = qa.judge(said, card, criterion, step["more"], strict=True)
    step["judge"] = {"pass": ok, "detail": why, "criterion": criterion}
    print(f"  {'PASS' if ok else 'FAIL'} judge (first card): {why.splitlines()[0]}", flush=True)
    # Same strict judge over everything the candidate actually read: in-reading updates plus "next".
    if step["updates"]:
        ok2, why2 = qa.judge(said, card, criterion, step["updates"] + step["more"], strict=True)
    else:
        ok2, why2 = ok, why
    step["judge_read"] = {"pass": ok2, "detail": why2}
    print(f"  {'PASS' if ok2 else 'FAIL'} judge (as read): {why2.splitlines()[0]}", flush=True)
    step["last_heard"] = (qa.card_state() or {}).get("heard", "")
    turns.append(step)
    (out / "interview.json").write_text(json.dumps({"turns": turns, "transcript": transcript}, ensure_ascii=False, indent=1))
    return card


AUDIO = os.environ.get("AUDIO") == "1"


def interviewer(text):
    """AUDIO=1: spoken by Samantha into BlackHole 2ch (silent for the person at the Mac), so it reaches the coach
    through system audio capture and recognition like a real call. Otherwise injected as finished text."""
    if AUDIO:
        subprocess.run(["say", "-a", "BlackHole 2ch", "-v", "Samantha", "-r", "175", text], check=True)
    else:
        time.sleep(qa.speak_time(text)); qa.lsctl("themSaid:" + text)


def plan_of(card):
    return (card.get("say", "") + " " + qa.type_code(card).replace("\\n", " ; "))[:1500]


DYN = ("The answer follows from what the candidate said, adds something specific rather than repeating the "
       "previous answer, stays consistent with the candidate's earlier answers and background, is technically "
       "correct, and invents no employer, title, metric or wallet rule the interviewer did not give.")


def main():
    for c in ("stop", "coachLanguage:english", "coachCards:on", "assistant:on", "shadowReading:off", "start:user"):
        r = qa.lsctl(c)
        if c != "stop" and not r.get("ok"):
            raise RuntimeError(f"{c}: {r}")
    time.sleep(3)
    opening = ("Hi, I'm the founder of ActAI. We're building an agent-first mobile communication app, focused on "
               "how people talk, coordinate and work together every day. Today we'll start with a project you "
               "really owned, then design a fictional mobile wallet together. I'll add a few new conditions along "
               "the way, and leave time for your questions at the end.")
    transcript.append("Interviewer: " + opening); interviewer(opening)
    time.sleep(6)

    # 05–10 self introduction
    turn("P1-intro", "Pick the one project that best shows your mobile skills. Who used it, what problem did it "
         "solve, and where did your responsibility start and end?",
         "SAY introduces one real Android project from the candidate's background with its users, the problem and "
         "the candidate's own scope; no invented employers, titles or numbers.")
    p1 = turns[-1]["card"].get("problem", "")
    turns[-1]["problem_check"] = {"pass": "wallet" not in p1.lower(), "problem": p1}
    print(f"  {'PASS' if 'wallet' not in p1.lower() else 'FAIL'} first problem: {p1}", flush=True)
    turn("P1-dyn", founder("Dig into the project the candidate just named: ask which exact part they built "
         "themselves versus the team, naming that project."), DYN, kind="dynamic")
    # 10–27 one real implementation
    turn("P2-change", "Pick a change you personally made. Walk me from one user action through the UI, data or "
         "network path. Which logic did you actually change?",
         "SAY traces one user action through concrete layers (UI, state, data or network) and says which logic the "
         "candidate changed; separates own work from the team's; no invented numbers.")
    turn("P2-bug", "What was the hardest bug to reproduce there? What did you suspect first, and which log, "
         "experiment or repro proved you wrong?",
         "SAY gives a timeline: first suspicion, the evidence (log, experiment or repro) that overturned it, and the "
         "root cause, distinguishing observation from conclusion.")
    turn("P2-dyn", founder("Probe a weak or vague spot in the bug story the candidate just told (for example how "
         "they confirmed the root cause, or how they knew the fix worked in production)."), DYN, kind="dynamic")
    turn("P2-alt", "What other options did you have, why didn't you pick them, and after release how did you know "
         "the change worked?",
         "SAY names a real alternative and the constraint that ruled it out, and the source of the result (metric, "
         "test, ticket or feedback) with its limits.")
    # 27–35 ownership
    turn("P3-risk", "Tell me about a time you saw a delivery risk or a likely delay and the team disagreed. When "
         "did you tell whom, how many options did you give, who decided, and what did you finish yourself?",
         "SAY describes one concrete case: when and whom the candidate told, the options offered, who had the "
         "decision, and what the candidate personally did; attributes the case to the right company.")
    turn("P3-dyn", founder("Ask what risk the candidate was willing to accept before that release, who watched the "
         "data afterwards, and what signal would have made them pause or roll back, tied to the case they told."),
         DYN, kind="dynamic")

    # 35–80 wallet design
    turn("W1-scope", "Let's switch to the design exercise. Design a mobile wallet from scratch: the core mobile "
         "experience, the system behind it, and how it handles failures. Start by clarifying the requirements. "
         "Which user path would you define as the MVP?",
         "SAY asks clarifying questions about scope (stored balance vs external rail, currency, offline behaviour, "
         "authority of the ledger) and proposes one MVP path such as send money to a contact.")
    w2 = turn("W2-design", SETTING.replace("Fictional wallet business rules (only the interviewer may state them): ",
              "Here are the rules: ") + " A has 100 dollars and B has zero. Draw the client, the server and local "
              "storage as a flowchart, and tell me what each part owns.",
              "TYPE is a mermaid flowchart of the Android client (UI, ViewModel, repository, local database), the "
              "server and its ledger; SAY says what each part owns and that the server ledger is the authority.",
              draw="flowchart")
    w2 = turn("W2-seq", "Now draw a sequence diagram of A sending B 80 dollars: confirmation, request, ledger and "
              "the result screen.",
              "TYPE is a mermaid sequenceDiagram covering confirm, submit with a client transfer ID, an atomic server "
              "debit and credit, the response and the result; SAY covers amounts in cents and the final balances (A "
              "20 dollars, B 80) and the result states.", draw="sequenceDiagram")
    turn("W2-dyn", founder("Pick one concrete box or step in the candidate's diagram or answer and ask how it "
         "works on Android or on the server (for example what is stored locally before the request, how the "
         "amount is represented, or what the result screen shows while waiting)."), DYN, kind="dynamic")
    # Plan change 1: the candidate's result path.
    turn("W3-change1", founder("Change the candidate's plan. Name the specific part of their current flow that "
         "assumes the response comes back (their plan: " + plan_of(w2) + "). New fact: the server commits the "
         "transfer but the response is lost, and then Android kills the process. A reopens the app. Ask what "
         "changes.") + " Please update your sequence diagram.",
         "SAY and TYPE treat the outcome as unknown (not failed), persist the transfer intent ID before sending, "
         "query the server by account and that ID after restart, and replay the same intent only if the server's "
         "idempotency contract allows; the server returns the original transfer's status for a repeat of the same ID; "
         "never a new ID; ledger has one transfer.", kind="plan-change", draw="sequenceDiagram")
    turn("W3-dyn", founder("Challenge the recovery the candidate just proposed with one counter-example from this "
         "list that fits their answer best: the lookup returns not found, the user taps send again, the "
         "idempotency record has expired, or the same ID arrives with a different amount."), DYN, kind="dynamic")
    turn("W4-concurrency", "Separate scenario. A still has 100 dollars. On two phones A approves two independent 80 "
         "dollar transfers to B at almost the same time. What happens to each one and what do the phones show?",
         "SAY treats them as two intents with separate IDs, checks and debits the balance in one transaction (row "
         "lock or conditional update), one succeeds and one fails for insufficient funds, A ends at 20 dollars.")
    turn("W5-account", "Back to the first transfer. While A's request is in flight the user switches to account C, "
         "and then A's old response arrives. What could go wrong on Android and how do you prevent it?",
         "SAY scopes cache writes and UI to account and session, drops callbacks from a stale session, C never sees "
         "A's data, and A's committed transfer is recovered from A's history after A signs in again.")
    # Plan change 2: the entry point.
    turn("W6-change2", founder("Change the candidate's plan again. Their flow so far starts on the wallet screen. "
         "New fact: the pilot must also start from a group chat, where someone writes 'pay Alex for last night's "
         "dinner'. There are two contacts called Alex, no reliable amount in the chat, and after the user confirms "
         "the chat stream disconnects. Ask what they change and what happens.") + " And right after the user confirms, the chat stream disconnects. Draw the new entry flow as a flowchart.",
         "SAY asks the user which Alex and what amount, shows a trusted native confirmation with recipient and "
         "amount, binds authorization to those parameters server-side, ties a repeated tool call to the original "
         "intent, and recovers status from the payment service when the chat drops; the model never authorizes. "
         "TYPE is a mermaid flowchart of that entry flow.", kind="plan-change", draw="flowchart")
    turn("W6-dyn", founder("Probe the authorization boundary in the candidate's chat flow with one twist that fits "
         "their answer: a group message claims transfers to Alex need no confirmation, or the recipient changes "
         "after confirmation, or the model already told the chat it succeeded."), DYN, kind="dynamic")
    turn("W7-release", "You have two weeks, and login plus a usable ledger already exist. What's in the first "
         "version, who signs off, and if transfers awaiting confirmation suddenly spike during the rollout, what "
         "do you do in the next half hour?",
         "SAY cuts scope to balance, internal transfer, history, confirmation and recoverable states; lists "
         "pre-release checks (lost response plus kill, replay, concurrency, account switch); on a spike pauses new "
         "submissions while keeping reads and status, owners reconcile, then resume.")
    turn("W7-dyn", founder("Ask the candidate what they would personally own in that rollout, who they need, and "
         "when they would escalate to you, the founder, referring to their answer."), DYN, kind="dynamic")
    turn("Q-close", "That's it from me. What questions do you have for me about the team or the role?",
         "SAY is one acceptable closing (a single point): an invitation to see the one-minute Cabinet AI demo, which is "
         "the candidate's approved closing, counts; so do one or two sensible questions to a founder that were not "
         "already answered in this conversation.")

    # The founder fills the handbook rubric from the transcript.
    rubric = deepseek("You interviewed this candidate. Score them with this rubric. Dimensions and weights: past work "
        "20, current ability 30, handling unknowns 25, shipping product 25. Levels 0-4 (0 no evidence or a dangerous "
        "plan, 1 needs guidance with key gaps, 2 core workable, 3 covers main cases independently and explains "
        "trade-offs, 4 backed by counter-examples, tests or production evidence). Score = weight*level/4. Thresholds: "
        "85+ strong yes, 75-84.99 yes, 60-74.99 review, below 60 no. Reply as JSON {dimensions:[{name,level,score,"
        "evidence}], total, decision, strongest, risks}.\n\nTranscript:\n" + "\n".join(transcript),
        max_tokens=1600, temperature=0)
    (out / "rubric.json").write_text(rubric)
    print("\nRUBRIC:", rubric, flush=True)


try:
    main()
finally:
    qa.lsctl("stop")
    n = len(turns)
    d = [t["diagram"]["pass"] for t in turns if "diagram" in t]
    print(f"diagrams {sum(d)}/{len(d)}", flush=True)
    print("first problem", "PASS" if turns[0].get("problem_check", {}).get("pass") else "FAIL", flush=True)
    print(f"\nfresh {sum(t['fresh'] for t in turns)}/{n}  judge first-card {sum(t.get('judge', {}).get('pass', False) for t in turns)}/{n}"
          f"  as-read {sum(t.get('judge_read', {}).get('pass', False) for t in turns)}/{n}  -> {out}", flush=True)
