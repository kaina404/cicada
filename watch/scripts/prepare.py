#!/usr/bin/env python3
"""Prepare personal pairing and the shared repository version without exposing credentials."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[2]
WATCH = ROOT / "watch"
PAIR = WATCH / "App/LocalPairing.json"


def main():
    existing = json.loads(PAIR.read_text()) if PAIR.exists() else {}
    host = subprocess.check_output(["scutil", "--get", "LocalHostName"], text=True).strip() + ".local"
    pairing = {
        "host": host,
        "bluetoothService": existing.get("bluetoothService", str(uuid.uuid4())),
        "token": existing.get("token", uuid.uuid4().hex + uuid.uuid4().hex),
    }
    port = os.environ.get("CICADA_WATCH_PORT", existing.get("port", "8765"))
    if not str(port).isdigit() or not 1 <= int(port) <= 65535:
        raise ValueError("Invalid local pairing port")
    pairing["port"] = str(port)
    if not isinstance(pairing["token"], str) or not pairing["token"]:
        raise ValueError("Invalid local pairing token")
    uuid.UUID(pairing["bluetoothService"])
    with tempfile.NamedTemporaryFile(mode="w", dir=PAIR.parent, delete=False) as handle:
        json.dump(pairing, handle)
    os.chmod(handle.name, 0o600)
    os.replace(handle.name, PAIR)
    version = (ROOT / "VERSION").read_text().strip()
    if not version or not all(part.isdigit() for part in version.split(".")):
        raise ValueError("Invalid repository VERSION")
    (WATCH / "Config/Version.xcconfig").write_text(f"CICADA_VERSION = {version}\n")
    print("Prepared local watch pairing and repository version (credentials not printed).")


if __name__ == "__main__":
    main()
