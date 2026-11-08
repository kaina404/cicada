"""Offline checks for the standalone Phase 0 probe; never reads a real key or opens a socket."""
import json
import pathlib
import struct
import subprocess
import tempfile
import unittest
import wave

ROOT = pathlib.Path(__file__).resolve().parents[1]
PROBE = ROOT / "tools/qwen-realtime-probe.swift"


class RealtimeProbeTests(unittest.TestCase):
    def run_probe(self, file, report, *args):
        return subprocess.run(
            ["swift", str(PROBE), str(file), "--dry-run", "--report", str(report), *args],
            cwd=ROOT, capture_output=True, text=True, timeout=90,
        )

    def test_stereo_resampling_and_partial_packet(self):
        with tempfile.TemporaryDirectory() as directory:
            audio = pathlib.Path(directory) / "stereo.wav"
            report = pathlib.Path(directory) / "report.json"
            with wave.open(str(audio), "wb") as out:
                out.setparams((2, 2, 48000, 0, "NONE", "not compressed"))
                out.writeframes(struct.pack("<hh", 1000, -500) * 48000)
            result = self.run_probe(audio, report, "--seconds", "0.35")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            data = json.loads(report.read_text())
            self.assertEqual(data["status"], "offline_decode_only")
            self.assertEqual(data["packets"], 4)  # Three 3200-byte packets, one 1600-byte tail.
            self.assertEqual(data["input_audio_seconds"], 0.35)
            self.assertFalse(data["session_updated"])
            self.assertEqual(data["responses"], [])
            self.assertIsNone(data["p50_ms"])
            self.assertEqual(len(data["pending"]), 7)
            self.assertEqual(data["events"][0]["pcm_bytes"], 11200)

    def test_invalid_audio_fails_with_report(self):
        with tempfile.TemporaryDirectory() as directory:
            audio = pathlib.Path(directory) / "invalid.wav"
            audio.write_text("not audio")
            report = pathlib.Path(directory) / "report.json"
            result = self.run_probe(audio, report)
            self.assertNotEqual(result.returncode, 0)
            data = json.loads(report.read_text())
            self.assertTrue(data["failure"])
            self.assertEqual(data["packets"], 0)
            self.assertEqual(data["text_deltas"], 0)

    def test_invalid_region_and_nonfinite_duration_rejected(self):
        for args in [("--region", "invalid"), ("--seconds", "nan"), ("--seconds", "0")]:
            with self.subTest(args=args), tempfile.TemporaryDirectory() as directory:
                report = pathlib.Path(directory) / "report.json"
                result = self.run_probe(pathlib.Path(directory) / "unused.wav", report, *args)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Invalid region or seconds", result.stdout)
                self.assertFalse(report.exists())


if __name__ == "__main__":
    unittest.main()
