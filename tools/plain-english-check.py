#!/usr/bin/env python3
"""Score Assistant answers against the plain-English rules in CoachPrompt.plainEnglish.

Input: a JSON list of {"id", "answer"} (the HR end-to-end results.json) or plain text files.
Prints words, sentence length, sentences over 12 words and hard-word hits per answer and overall.
"""
import json, re, sys

HARD = ["itinerary", "generate", "arrange", "integrate", "scenario", "leverage", "utilize",
        "facilitate", "comprehensive", "robust", "seamless", "furthermore", "moreover",
        "nevertheless", "subsequently", "whereas", ", which", ", who", "whom", "whose"]

def score(text):
    sentences = [s for s in re.split(r"(?<=[.!?])\s+", text.strip()) if re.search(r"\w", s)]
    lengths = [len(re.findall(r"[\w'’,.-]+", s)) for s in sentences]
    lower = text.lower()
    hits = [w.strip(", ") for w in HARD if (w in lower if w.startswith(",") else re.search(rf"\b{w}\w*", lower))]
    return {"words": sum(lengths), "sentences": len(lengths), "long": sum(n > 12 for n in lengths),
            "avg": sum(lengths) / max(1, len(lengths)), "hard": hits}

def main(paths):
    rows = []
    for p in paths:
        data = json.load(open(p)) if p.endswith(".json") else [{"id": p, "answer": open(p).read()}]
        rows += [(str(r.get("n", r.get("id"))), score(r["answer"])) for r in data if r.get("answer")]
    for key, s in rows:
        print(f"{key:>6}  {s['words']:4d} words  avg {s['avg']:4.1f}  long {s['long']}/{s['sentences']}  {' '.join(s['hard'])}")
    total = sum(s["sentences"] for _, s in rows)
    print(f"\n{len(rows)} answers  avg sentence {sum(s['words'] for _, s in rows) / max(1, total):.1f} words  "
          f"over 12 words {sum(s['long'] for _, s in rows) / max(1, total):.0%}  "
          f"answers with hard words {sum(bool(s['hard']) for _, s in rows)}")

if __name__ == "__main__":
    main(sys.argv[1:] or sys.exit("usage: plain-english-check.py results.json|answer.txt ..."))
