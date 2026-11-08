#!/usr/bin/env python3
"""Prepare synthetic, file-only Mac voices for the opt-in local Gemma reading test."""
import subprocess
from pathlib import Path

SENTENCE = "I would keep Room as the single source of truth."
LATER = "Each message gets a stable client ID, so retries do not send it twice."
CASES = {
    "standard": ("Samantha", SENTENCE + " " + LATER),
    "accented": ("Tingting", SENTENCE + " " + LATER),
    "misread": ("Tingting", "I would keep room, um, as the single source of true."),
    "repeated": ("Tingting", "I would, I would keep room, um, as the single source of truth."),
    "later": ("Tingting", LATER),
    "photo": ("Samantha", "A key consideration here is the scalability of the theta."),
    "photo-accented": ("Tingting", "A key consideration here is the scalability of the theta."),
    "unrelated": ("Tingting", "Can you hear me? I need a glass of water."),
}
for name, (voice, text) in CASES.items():
    source = Path(f"/tmp/cicada-reading-{name}.aiff")
    subprocess.run(["say", "-v", voice, "-o", str(source), text], check=True)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(source), "-ar", "16000", "-ac", "1",
                    f"/tmp/cicada-reading-{name}.wav"], check=True)
for name, generator in {"silence": "anullsrc=r=16000:cl=mono", "tone": "sine=frequency=300:sample_rate=16000"}.items():
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i", generator,
                    "-t", "3", f"/tmp/cicada-reading-{name}.wav"], check=True)
print("Prepared ten synthetic WAV files in /tmp; no room audio was played.")
