#!/usr/bin/env python3
"""Exercise a running isolated Cicada dev instance without printing pairing credentials."""
import http.client
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
CHANNEL = os.environ.get("CICADA_DEBUG_CHANNEL", "")
if not CHANNEL:
    raise SystemExit("Set CICADA_DEBUG_CHANNEL to an isolated running dev instance.")
LOG = Path(f"/tmp/livesubs-dev-debug-{CHANNEL}.log")
APP = Path(os.environ.get("CICADA_WATCH_APP", str(ROOT / "build/Cicada.app")))
PAIR = json.loads((APP / "Contents/Resources/LocalPairing.json").read_text())


def command(value):
    subprocess.run([str(ROOT / "tools/lsctl"), value], check=True, stdout=subprocess.DEVNULL)


def request(path, body=b"", token=None):
    connection = http.client.HTTPConnection("127.0.0.1", int(PAIR.get("port", "8765")), timeout=3)
    try:
        connection.request("POST", path, body, {"X-WatchControl-Token": PAIR["token"] if token is None else token})
        response = connection.getresponse()
        response.read()
        return response.status
    finally:
        connection.close()


def state():
    command("assistantFloatState")
    lines = LOG.read_text().splitlines()
    line = next(line for line in reversed(lines) if "assistant float:" in line)
    frame = re.search(r"frame=(.*?) key=", line)
    if not frame:
        raise AssertionError("No floating answer frame")
    values = tuple(float(value) for value in re.findall(r"-?\d+(?:\.\d+)?", frame[1]))
    return values, "visible=true" in line, "key=false sharing=0" in line


sequence = 0
session = int(time.time()) & 0xFFFFFFFF


def send(kind, gesture, x=0.0, y=0.0):
    global sequence
    sequence += 1
    body = struct.pack("<BIIHff", kind, session, sequence, gesture, x, y)
    assert request("/control", body) == 204


assert request("/connect", token="wrong-token") == 403
assert request("/connect") == 204
command("assistantFloat:on")
command("watchState")
before, visible, safe = state()
assert visible and safe, "Float must remain nonactivating and excluded from capture"
send(0x20, 1)
send(0x23, 1, x=0.05)
moved, _, safe = state()
assert abs(moved[0] - before[0] - 45) < 1 and safe, "LAN packets must move the actual owned float"
# Deliberately include drift on first hold, heartbeat, move and lift packets.
send(0x20, 4)
send(0x22, 4, x=0.02)
time.sleep(0.1)
send(0x22, 4, x=0.2)
send(0x21, 4, x=-0.1)
time.sleep(0.1)
held, _, safe = state()
assert held == moved and safe, "Holding must freeze the actual floating answer"
send(0x23, 4, x=0.3)
released, _, safe = state()
assert released == moved and safe, "Releasing a hold must not apply final displacement"
command("assistantFloat:off")
send(0x20, 2)
send(0x23, 2, x=0.2)
hidden, visible, _ = state()
assert not visible and hidden == moved, "Hidden float must ignore movement"
command("assistantFloat:on")
send(0x23, 2, x=0.3)
reopened, visible, _ = state()
assert visible and reopened == moved, "Reopening must not revive an old gesture"
send(0x20, 3)
send(0x23, 3, x=-0.05)
restored, _, safe = state()
assert abs(restored[0] - before[0]) < 1 and safe, "Fresh touch resumes movement"
command("watchState")
command("assistantFloat:off")
assert "watch: floating answer ready" in LOG.read_text()
print("PASS: live Cicada LAN authentication, direct floating answer movement, hold/lift movement isolation, hidden-target rejection, fresh-touch reconnect, nonactivating/capture-excluded window; original position restored.")
