#!/usr/bin/env python3
"""Generate the plan's first 36 synthetic questions with macOS system tools."""
import argparse
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, default=Path("/tmp/cicada-qwen-questions"))
args = parser.parse_args()
repo = Path(__file__).resolve().parent.parent
args.output.mkdir(parents=True, exist_ok=True)
questions = json.loads((repo / "tools/copilot-questions.json").read_text())[:36]
fixtures = []
for question in questions:
    aiff = args.output / (question["id"] + ".aiff")
    wav = args.output / (question["id"] + ".wav")
    subprocess.run(["say", "-v", "Samantha", "-r", "180", "-o", str(aiff), question["question"]], check=True)
    subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", str(aiff), str(wav)], check=True)
    fixtures.append(dict(id=question["id"], question=question["question"], audio=str(wav.resolve()), context=question.get("context")))
(args.output / "fixtures.json").write_text(json.dumps(fixtures, indent=2) + "\n")
print(f"Generated {len(fixtures)} synthetic interview questions in {args.output}")
