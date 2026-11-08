#!/usr/bin/env python3
"""Measure streamed interview answers using synthetic inputs and no dependencies.

Run: python3 tools/test_deepseek_latency.py --repeats 3
Local: python3 tools/test_deepseek_latency.py --provider local --repeats 3
Reads DEEPSEEK_API_KEY, optionally DEEPSEEK_API_BASE_URL. Never saves credentials.
"""

from __future__ import annotations

import argparse
import base64
from datetime import datetime
import json
import math
import os
from pathlib import Path
import re
import statistics
import struct
import time
from typing import Any
import urllib.error
import urllib.parse
import urllib.request
import zlib


ROOT = Path(__file__).resolve().parents[1]
QUESTION = "How would you make offline message retries safe after process death in an Android chat app?"


def synthetic_image() -> bytes:
    """Encode a deliberately simple synthetic UI diagram, never a desktop capture."""
    width, height = 640, 360
    pixels = bytearray(bytes((243, 244, 246)) * width * height)

    def rectangle(x0: int, y0: int, x1: int, y1: int, color: tuple[int, int, int]) -> None:
        for y in range(y0, y1):
            start = (y * width + x0) * 3
            pixels[start:start + (x1 - x0) * 3] = bytes(color) * (x1 - x0)

    rectangle(25, 25, 615, 60, (21, 23, 28))
    for y in (100, 180, 260):
        rectangle(30, y, 175, y + 45, (255, 255, 255))
        rectangle(240, y, 385, y + 45, (232, 85, 43))
        rectangle(450, y, 595, y + 45, (90, 95, 107))
        rectangle(175, y + 20, 240, y + 25, (90, 95, 107))
        rectangle(385, y + 20, 450, y + 25, (90, 95, 107))

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack("!I", len(data)) + kind + data + struct.pack("!I", zlib.crc32(kind + data))

    scanlines = b"".join(b"\0" + pixels[y * width * 3:(y + 1) * width * 3] for y in range(height))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack("!2I5B", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(scanlines)) + chunk(b"IEND", b""))


def messages(case: str) -> list[dict[str, Any]]:
    """Use the app's current system prompt with synthetic interview evidence only."""
    source = (ROOT / "Sources/Cicada/InterviewCoachLogic.swift").read_text()
    match = re.search(r'enum CoachPrompt.*?static let system = """\n(.*?)\n    """', source, re.S)
    if match is None:
        raise ValueError("Could not find CoachPrompt.system in the Swift source")
    system = "\n".join(line[4:] if line.startswith("    ") else line for line in match[1].splitlines())
    turns: list[dict[str, Any]] = []
    if case.startswith("long"):
        for index in range(34):
            text = ("I would use Room as the source of truth, a persistent outbox, WorkManager retries "
                    "with backoff, and a stable per-message idempotency key. " if index % 2 else
                    "How do you handle offline writes, process death, ordering, authentication, "
                    "and duplicates in an Android messaging application? ")
            turns.append(dict(id=str(index), seconds=index * 5,
                              role="candidate" if index % 2 else "interviewer", text=text * 3))
    turns.append(dict(id="question", seconds=180, role="interviewer", text=QUESTION))
    content: list[dict[str, Any]] = [dict(type="text", text=(
        "Reference background:\nSynthetic ActAI Android interview; no personal work history.\n"
        "Actual speech (JSON; seconds from meeting start):\n" + json.dumps(turns, separators=(",", ":"))))]
    if case.endswith("images"):
        image = base64.b64encode(synthetic_image()).decode()
        for index in range(3):
            content.extend([
                dict(type="text", text=f"Synthetic screen keyframe at {index} seconds. Diagram reference: "
                     "local database, persistent outbox, sync worker, server; deduplicate by message ID."),
                dict(type="image_url", image_url=dict(url="data:image/png;base64," + image)),
            ])
    content.append(dict(type="text", text="Immutable committed user speech (reference only):\n\n"
                        "Write the COMPLETE remaining English answer now. Start with a useful spoken sentence, with no labels."))
    return [dict(role="system", content=system), dict(role="user", content=content)]


def measure(url: str, key: str, model: str, case: str, timeout: float,
            provider: str = "deepseek") -> dict[str, Any]:
    payload = dict(model=model, messages=messages(case), stream=True, temperature=0,
                   max_tokens=800, stream_options=dict(include_usage=True))
    if provider == "local":
        payload["enable_thinking"] = False
    else:
        payload["thinking"] = dict(type="disabled")
    body = json.dumps(payload).encode()
    headers = {"Content-Type": "application/json", "Accept": "text/event-stream"}
    if key:
        headers["Authorization"] = "Bearer " + key
    request = urllib.request.Request(url, data=body, headers=headers)
    first: float | None = None
    sentence: float | None = None
    first_event: float | None = None
    text = ""
    reasoning_chars = 0
    returned_model: str | None = None
    finish_reason: str | None = None
    usage: dict[str, Any] = {}
    done = False
    started = time.perf_counter()
    with urllib.request.urlopen(request, timeout=timeout) as response:
        headers_at = time.perf_counter() - started
        for line in response:
            if not line.startswith(b"data:"):
                continue
            if first_event is None:
                first_event = time.perf_counter() - started
            data = line[5:].strip()
            if data == b"[DONE]":
                done = True
                break
            event = json.loads(data)
            if event.get("error"):
                raise ValueError("Provider returned an error inside the stream")
            returned_model = event.get("model", returned_model)
            usage = event.get("usage") or usage
            for choice in event.get("choices", []):
                finish_reason = choice.get("finish_reason") or finish_reason
                delta = choice.get("delta") or {}
                reasoning_chars += len(delta.get("reasoning_content") or "")
                piece = delta.get("content") or ""
                if not piece.strip() and first is None:
                    continue
                if not piece:
                    continue
                elapsed = time.perf_counter() - started
                if first is None:
                    first = elapsed
                text += piece
                if sentence is None and re.search(r"[.!?](?:\s|$)", text):
                    sentence = elapsed
    if not done or first is None:
        raise ValueError("Stream ended without DONE or visible answer content")
    return dict(case=case, request_bytes=len(body), requested_model=model, returned_model=returned_model,
                headers_seconds=headers_at, first_event_seconds=first_event,
                first_token_seconds=first, first_sentence_seconds=sentence,
                total_seconds=time.perf_counter() - started, finish_reason=finish_reason,
                reasoning_chars=reasoning_chars, usage=usage, output=text)


def summarize(rows: list[dict[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for case in dict.fromkeys(row["case"] for row in rows):
        samples = [row for row in rows if row["case"] == case and "error" not in row]
        metrics: dict[str, Any] = {}
        for field in ("first_token_seconds", "first_sentence_seconds", "total_seconds"):
            values = sorted(row[field] for row in samples if row.get(field) is not None)
            if values:
                metrics[field] = dict(median=statistics.median(values), minimum=min(values),
                                      maximum=max(values), p95_nearest_rank=values[math.ceil(len(values) * .95) - 1])
        result[case] = dict(successes=len(samples), errors=sum("error" in row for row in rows if row["case"] == case), metrics=metrics)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--provider", choices=["deepseek", "local"], default="deepseek")
    parser.add_argument("--model")
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=90)
    parser.add_argument("--cases", nargs="+", choices=["short_text", "short_images", "long_text", "long_images"],
                        default=["short_text", "short_images", "long_text", "long_images"])
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    local = args.provider == "local"
    args.model = args.model or ("mlx-community/gemma-4-E4B-it-qat-4bit" if local else "deepseek-flash")
    args.output = args.output or ROOT / f"outputs/{'gemma' if local else 'deepseek'}-latency/report.json"
    key = "" if local else os.environ.get("DEEPSEEK_API_KEY", "").strip()
    if not local and not key:
        parser.error("Set DEEPSEEK_API_KEY in the environment; credentials are never saved")
    if args.repeats < 1:
        parser.error("--repeats must be positive")
    base = ("http://127.0.0.1:18765/v1" if local else
            os.environ.get("DEEPSEEK_API_BASE_URL", "https://api.deepseek.com").rstrip("/"))
    parsed = urllib.parse.urlsplit(base)
    if (not local and parsed.scheme != "https") or parsed.username or parsed.password or parsed.query or parsed.fragment:
        parser.error("API base must be an HTTPS URL without credentials, query or fragment")
    url = base + ("" if base.endswith("/chat/completions") else "/chat/completions")
    rows: list[dict[str, Any]] = []
    args.output.parent.mkdir(parents=True, exist_ok=True)
    report: dict[str, Any] = dict(started_at=datetime.now().astimezone().isoformat(), endpoint=url,
                                 provider=args.provider, thinking="disabled", max_tokens=800, synthetic_only=True, rows=rows)
    print(json.dumps(dict(endpoint=url, model=args.model, thinking="disabled", calls=args.repeats * len(args.cases))), flush=True)
    for repeat in range(args.repeats):
        # Rotate order to spread repeat/cache and order effects across cases.
        cases = args.cases[repeat % len(args.cases):] + args.cases[:repeat % len(args.cases)]
        for case in cases:
            try:
                row = measure(url, key, args.model, case, args.timeout, args.provider)
            except urllib.error.HTTPError as error:
                row = dict(case=case, error=f"HTTP {error.code}")
            except (urllib.error.URLError, TimeoutError, OSError, ValueError) as error:
                # Do not log provider bodies or exception messages that might include credentials.
                row = dict(case=case, error=type(error).__name__)
            row["repeat"] = repeat + 1
            rows.append(row)
            report["summary"] = summarize(rows)
            args.output.write_text(json.dumps(report, indent=2) + "\n")
            print(json.dumps({k: v for k, v in row.items() if k not in {"output", "usage"}}), flush=True)
            if "error" in row:
                # A rejected request is not a latency result. Avoid repeating billing/auth errors.
                return 1
    print(json.dumps(report["summary"], indent=2), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
