"""Real CPU model checks; run with ~/.cicada-mlx/bin/python -m pytest Tests/test_coach_audio.py."""

from __future__ import annotations

import importlib.util
import subprocess
import wave
from pathlib import Path

import pytest

pytest.importorskip("onnxruntime")
pytest.importorskip("transformers")
spec = importlib.util.spec_from_file_location(
    "coach_audio", Path(__file__).parents[1] / "Resources/coach/audio_worker.py"
)
assert spec is not None and spec.loader is not None
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


@pytest.fixture(scope="module")
def detector():
    return worker.Detector()


def test_silence_is_not_a_question(detector):
    events = detector.feed("interviewer", bytes(8000), 0.25)
    assert not any(event.get("voiced") for event in events)
    assert not any(event["kind"] == "endpoint" for event in events)


def test_rejects_malformed_audio(detector):
    with pytest.raises(ValueError, match="channel"):
        detector.feed("unknown", bytes(512), 0)
    with pytest.raises(ValueError, match="length"):
        detector.feed("candidate", b"x", 0)
    with pytest.raises(ValueError, match="two seconds"):
        detector.feed("candidate", bytes(64002), 0)


def test_real_synthetic_voice_has_independent_turns_and_bounded_state(tmp_path):
    audio = tmp_path / "question.aiff"
    wav = tmp_path / "question.wav"
    subprocess.run(
        [
            "say",
            "-v",
            "Samantha",
            "-o",
            str(audio),
            "How would you design reliable offline messaging on Android?",
        ],
        check=True,
    )
    subprocess.run(
        [
            "afconvert",
            "-f",
            "WAVE",
            "-d",
            "LEI16@16000",
            "-c",
            "1",
            str(audio),
            str(wav),
        ],
        check=True,
    )
    with wave.open(str(wav)) as file:
        pcm = file.readframes(file.getnframes()) + bytes(64000)
    detector = worker.Detector()
    all_events = []
    for role in ["interviewer", "candidate"]:
        for offset in range(0, len(pcm), 8000):
            packet = pcm[offset : offset + 8000]
            all_events.extend(
                detector.feed(role, packet, (offset + len(packet)) / 32000)
            )
    for role in ["interviewer", "candidate"]:
        assert any(
            event.get("voiced") and event["role"] == role for event in all_events
        )
        endpoints = [
            event
            for event in all_events
            if event["kind"] == "endpoint" and event["role"] == role
        ]
        assert endpoints
        assert endpoints[-1]["complete"]
        assert detector.channels[role].history.size <= 128000
        assert detector.channels[role].pending.size < 512
    assert (
        detector.channels["candidate"].state
        is not detector.channels["interviewer"].state
    )
