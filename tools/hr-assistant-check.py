#!/usr/bin/env python3
"""Ask the ActAI HR question bank through a running dev build's Interview Coach and check the answers.

Start an isolated copy first: open -n --env CICADA_DEBUG_CHANNEL=hrtest build/Cicada.app
Then: CICADA_DEBUG_CHANNEL=hrtest python3 tools/hr-assistant-check.py [--only N01,B03] [--out docs/evaluations/x]
Each batch of questions is its own meeting, so the conversation stays as long as a real interview.
After every answer, `meSaid` marks it as spoken; otherwise the coach thinks earlier questions are unanswered.
"""
import argparse, difflib, glob, json, os, re, subprocess, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LSCTL = os.path.join(ROOT, "tools", "lsctl")
SESSIONS = os.path.expanduser("~/Library/Application Support/LiveSubs Dev/Sessions")
# Hard facts that must never appear: another candidate's résumé, retired claims, private project names.
FORBIDDEN = ["shopee", "okx", "singapore", "17 years", "16 years", "huawei", "sony", "faraday", "bisoft", "sgd",
             "120,000", "bankrupt", "not my choice", "didn't choose to leave", "all three were company",
             "later moved", "cicada", "i wrote the ios", "three layoffs"]
SKU = re.compile(r"300 ?(ms|milliseconds)", re.I)
CRASH = re.compile(r"crash rate|one tenth|0\.1%", re.I)


def lsctl(cmd):
    subprocess.run([LSCTL, cmd], check=True)


def references():
    """`### N. title` sections of the finalized answers; the first quoted block is the reference."""
    text = open(os.path.join(ROOT, "docs", "actai-hr-followup-answers.md"), encoding="utf-8").read()
    refs = {}
    for m in re.finditer(r"(?m)^### (\d+)\..*\n((?:\n|> .*\n|>\n)+)", text):
        refs[m.group(1)] = " ".join(l[2:] for l in m.group(2).splitlines() if l.startswith("> ")).strip()
    return refs


def new_meeting():
    """Start a meeting and return its journal; waits for the new session folder so the first question isn't read from the last one."""
    before = set(glob.glob(SESSIONS + "/*/"))
    lsctl("stop"); time.sleep(2); lsctl("start:user"); lsctl("assistant:on")
    for _ in range(20):
        time.sleep(0.5)
        fresh = set(glob.glob(SESSIONS + "/*/")) - before
        if fresh:
            time.sleep(3)
            return max(fresh, key=os.path.getmtime) + "coach.jsonl"
    raise SystemExit("no new meeting started")


def ask(question, path):
    start = len(open(path).readlines()) if os.path.exists(path) else 0
    lsctl("assistantSay:" + question)
    began, seen, quiet, events = time.time(), -1, 0, []
    while time.time() - began < 90:
        time.sleep(1)
        lines = open(path).readlines()[start:] if os.path.exists(path) else []
        events = [json.loads(l) for l in lines]
        quiet = quiet + 1 if len(lines) == seen else 0
        seen = len(lines)
        if any(e.get("kind") == "latency" for e in events) and quiet >= 6:
            break
    answer = " ".join(e["text"] for e in events if e.get("kind") == "answer" and e.get("text"))
    first = next((e.get("firstSentence") for e in events if e.get("kind") == "latency"), None)
    return re.sub(r" /[^/]+/", "", answer).strip(), first


def check(item, answer, refs):
    low, problems = answer.lower(), []
    if not answer:
        problems.append("没有回答")
    problems += [f"出现禁用说法「{w}」" for w in FORBIDDEN if w in low]
    if item.get("must_any") and not any(m.lower() in low for m in item["must_any"]):
        problems.append("缺少要点：" + " / ".join(item["must_any"]))
    if "[fill in" in low:
        problems.append("资料不足，留了 [fill in]")
    tags = item.get("tags", [])
    warnings = []
    if SKU.search(answer) and "sku" not in tags:
        warnings.append("SKU 例子串到了这题")
    if CRASH.search(answer) and "crash" not in tags:
        warnings.append("主动提了崩溃率")
    ref = refs.get((item.get("ref") or "").split(":")[-1])
    ratio = round(difflib.SequenceMatcher(None, ref.lower(), low).ratio(), 2) if ref else None
    if ratio is not None and ratio < 0.6:
        warnings.append(f"和定稿差异较大（相似度 {ratio}）")
    return problems, warnings, ratio, ref


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bank", default=os.path.join(ROOT, "tools", "actai-hr-question-bank.json"))
    ap.add_argument("--only", default="")
    ap.add_argument("--batch", type=int, default=12)
    ap.add_argument("--out", default=os.path.join(ROOT, "docs", "evaluations", "actai-hr-assistant"))
    args = ap.parse_args()
    bank = json.load(open(args.bank, encoding="utf-8"))
    if args.only:
        keep = set(args.only.split(","))
        bank = [b for b in bank if b["id"] in keep]
    refs, results = references(), []
    for i in range(0, len(bank), args.batch):
        path = new_meeting()
        for item in bank[i:i + args.batch]:
            answer, first = ask(item["question"], path)
            problems, warnings, ratio, ref = check(item, answer, refs)
            if answer:
                lsctl("meSaid:" + answer); time.sleep(4)
            results.append({**item, "answer": answer, "first_sentence_s": first, "problems": problems,
                            "warnings": warnings, "similarity": ratio, "reference": ref})
            mark = "FAIL" if problems else ("WARN" if warnings else "ok")
            print(f"{item['id']} {mark} {'; '.join(problems + warnings)}", flush=True)
    lsctl("stop")
    json.dump(results, open(args.out + ".json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    failed = [r for r in results if r["problems"]]
    warned = [r for r in results if r["warnings"] and not r["problems"]]
    with open(args.out + ".md", "w", encoding="utf-8") as f:
        f.write(f"# ActAI HR 问题 Assistant 验证\n\n共 {len(results)} 题：通过 {len(results) - len(failed) - len(warned)}，"
                f"提醒 {len(warned)}，失败 {len(failed)}。\n\n")
        for r in results:
            mark = "❌" if r["problems"] else ("⚠️" if r["warnings"] else "✅")
            f.write(f"## {mark} {r['id']} · {r['group']} · {r['source']}\n\n**Q:** {r['question']}\n\n**A:** {r['answer']}\n\n")
            if r["problems"] or r["warnings"]:
                f.write("- " + "\n- ".join(r["problems"] + r["warnings"]) + "\n\n")
    print(f"done: {len(results)} asked, {len(failed)} failed, {len(warned)} warned → {args.out}.md")


if __name__ == "__main__":
    main()
