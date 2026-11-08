"""Local CPU Silero + Smart Turn worker. JSON-lines stdin/stdout, 16kHz mono PCM16.

No audio is written to disk. Model downloads contain no meeting data. Each channel owns
independent recurrent VAD state. GPU inference stays in the existing MLX process.
"""

from __future__ import annotations

import base64
import hashlib
import json
import sys
import urllib.request
from pathlib import Path
from typing import Any

SILERO_URL = "https://raw.githubusercontent.com/snakers4/silero-vad/v6.2/src/silero_vad/data/silero_vad.onnx"
SILERO_SHA = "1a153a22f4509e292a94e67d6f9b85e8deb25b4988682b7e174c65279d8788e3"
TURN_REVISION = "f766f81d3cfdf7737ac64aad813d91bbfd56bf93"


def model_paths() -> tuple[Path, str]:
    """Fetch pinned open model weights, verifying Silero before loading executable graphs."""
    from huggingface_hub import hf_hub_download

    folder = Path.home() / ".cicada-mlx" / "models"
    folder.mkdir(parents=True, exist_ok=True)
    vad = folder / "silero-v6.2.onnx"
    if not vad.exists() or hashlib.sha256(vad.read_bytes()).hexdigest() != SILERO_SHA:
        with urllib.request.urlopen(SILERO_URL, timeout=60) as response:
            data = response.read(10_000_000)
        if hashlib.sha256(data).hexdigest() != SILERO_SHA:
            raise ValueError("Silero model checksum mismatch")
        temporary = vad.with_suffix(".download")
        temporary.write_bytes(data)
        temporary.replace(vad)
    turn = hf_hub_download(
        "pipecat-ai/smart-turn-v3", "smart-turn-v3.2-cpu.onnx", revision=TURN_REVISION
    )
    return vad, turn


class Channel:
    def __init__(self) -> None:
        import numpy as np

        self.state = np.zeros((2, 1, 128), dtype=np.float32)
        self.context = np.zeros((1, 64), dtype=np.float32)
        self.pending = np.empty(0, dtype=np.float32)
        self.history = np.empty(0, dtype=np.float32)
        self.last_voice = -1e10
        self.had_voice = False
        self.checked = False
        self.last_time = -1e10


class Detector:
    def __init__(self) -> None:
        import onnxruntime as ort
        from transformers import WhisperFeatureExtractor

        vad, turn = model_paths()
        options = ort.SessionOptions()
        options.inter_op_num_threads = 1
        options.intra_op_num_threads = 2
        self.vad = ort.InferenceSession(
            str(vad), sess_options=options, providers=["CPUExecutionProvider"]
        )
        self.turn = ort.InferenceSession(
            turn, sess_options=options, providers=["CPUExecutionProvider"]
        )
        # Transformers does not type this constructor; inference output is checked by ONNX.
        self.extractor = WhisperFeatureExtractor(chunk_length=8)  # type: ignore[no-untyped-call]
        self.channels: dict[str, Channel] = {}

    def feed(self, role: str, pcm: bytes, now: float) -> list[dict[str, Any]]:
        """Run 32ms VAD windows; classify a turn once per pause after 320ms silence."""
        import numpy as np

        if role not in {"interviewer", "candidate"} or len(pcm) % 2:
            raise ValueError("Invalid audio channel or PCM length")
        if len(pcm) > 64000:
            raise ValueError("Audio packet exceeds two seconds")
        channel = self.channels.setdefault(role, Channel())
        samples = np.frombuffer(pcm, dtype="<i2").astype(np.float32) / 32768.0
        # Process taps can stop in silence. Preserve a bounded silence gap for the endpoint model.
        gap = now - samples.size / 16000 - channel.last_time
        if 0.1 < gap < 60:
            samples = np.concatenate(
                (np.zeros(min(int(gap * 16000), 128000), dtype=np.float32), samples)
            )
        channel.last_time = now
        channel.pending = np.concatenate((channel.pending, samples))
        channel.history = np.concatenate((channel.history, samples))[-128000:]
        peak = 0.0
        while channel.pending.size >= 512:
            block = channel.pending[:512].reshape(1, 512)
            channel.pending = channel.pending[512:]
            inputs = np.concatenate((channel.context, block), axis=1)
            probability, channel.state = self.vad.run(
                None,
                {
                    "input": inputs,
                    "state": channel.state,
                    "sr": np.array(16000, dtype=np.int64),
                },
            )
            channel.context = inputs[:, -64:]
            value = float(probability.flat[0])
            peak = max(peak, value)
            if value >= 0.5:
                channel.last_voice = now - channel.pending.size / 16000
                channel.had_voice = True
                channel.checked = False
        events: list[dict[str, Any]] = [
            {
                "kind": "vad",
                "role": role,
                "now": now,
                "voiced": now - channel.last_voice < 0.16,
                "probability": peak,
            }
        ]
        if (
            channel.had_voice
            and not channel.checked
            and now - channel.last_voice >= 0.32
        ):
            features = self.extractor(
                channel.history,
                sampling_rate=16000,
                return_tensors="np",
                padding="max_length",
                max_length=128000,
                truncation=True,
                do_normalize=True,
            )
            probability = float(
                self.turn.run(
                    None, {"input_features": features.input_features.astype(np.float32)}
                )[0].flat[0]
            )
            channel.checked = True
            events.append(
                {
                    "kind": "endpoint",
                    "role": role,
                    "now": now,
                    "complete": probability > 0.5,
                    "probability": probability,
                }
            )
        return events


def emit(value: dict[str, Any]) -> None:
    print(json.dumps(value, separators=(",", ":")), flush=True)


def main() -> None:
    if "--prepare" in sys.argv:
        import subprocess

        subprocess.run(
            [sys.executable, "-m", "pip", "install", "onnxruntime==1.24.1"],
            check=True,
            stdout=sys.stderr,
        )
    detector = Detector()
    emit({"kind": "ready"})
    if "--prepare" in sys.argv:
        return
    for line in sys.stdin:
        try:
            packet = json.loads(line)
            if packet.get("kind") == "reset":
                detector.channels.clear()
                continue
            for event in detector.feed(
                packet["role"],
                base64.b64decode(packet["pcm"], validate=True),
                float(packet["now"]),
            ):
                emit(event)
        except (ValueError, KeyError, TypeError) as error:
            emit({"kind": "error", "message": type(error).__name__})


if __name__ == "__main__":
    main()
