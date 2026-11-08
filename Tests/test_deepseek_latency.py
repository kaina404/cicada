"""Offline checks: latency must measure answer text, never SSE metadata or reasoning."""

import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location(
    "deepseek_latency", Path(__file__).resolve().parents[1] / "tools/test_deepseek_latency.py")
assert SPEC is not None and SPEC.loader is not None
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class StreamResponse:
    def __init__(self, events: list[dict], done: bool = True) -> None:
        self.lines = [b"data: " + json.dumps(event).encode() + b"\n" for event in events]
        if done:
            self.lines.append(b"data: [DONE]\n")

    def __enter__(self) -> "StreamResponse":
        return self

    def __exit__(self, *_args: object) -> None:
        pass

    def __iter__(self):
        return iter(self.lines)


class DeepSeekLatencyTests(unittest.TestCase):
    def test_answer_timing_excludes_metadata_and_reasoning(self) -> None:
        response = StreamResponse([
            {"choices": [{"delta": {"role": "assistant", "content": ""}}]},
            {"choices": [{"delta": {"reasoning_content": "hidden"}}]},
            {"model": "deepseek-flash", "choices": [{"delta": {"content": "Use Room"}}]},
            {"choices": [{"delta": {"content": "."}}]},
            {"choices": [{"delta": {}, "finish_reason": "stop"}]},
            {"choices": [], "usage": {"completion_tokens": 3}},
        ])
        with patch.object(probe.urllib.request, "urlopen", return_value=response) as opened, patch.object(
            probe.time, "perf_counter", side_effect=[0, .1, .2, .5, .8, 1.2]
        ):
            row = probe.measure("https://example.test/chat/completions", "fake-secret", "deepseek-flash", "short_text", 10)
        self.assertEqual(row["first_event_seconds"], .2)
        self.assertEqual(row["first_token_seconds"], .5)
        self.assertEqual(row["first_sentence_seconds"], .8)
        self.assertEqual(row["total_seconds"], 1.2)
        self.assertEqual(row["reasoning_chars"], 6)
        self.assertEqual(row["output"], "Use Room.")
        self.assertEqual(row["usage"]["completion_tokens"], 3)
        self.assertNotIn("fake-secret", json.dumps(row))
        payload = json.loads(opened.call_args.args[0].data)
        self.assertEqual(payload["thinking"], {"type": "disabled"})

    def test_incomplete_stream_is_not_a_success(self) -> None:
        response = StreamResponse([{"choices": [{"delta": {"content": "partial"}}]}], done=False)
        with patch.object(probe.urllib.request, "urlopen", return_value=response):
            with self.assertRaisesRegex(ValueError, "without DONE"):
                probe.measure("https://example.test/chat/completions", "fake", "deepseek-flash", "short_text", 10)

    def test_local_uses_same_inputs_without_cloud_credentials(self) -> None:
        response = StreamResponse([{"choices": [{"delta": {"content": "Use Room."}, "finish_reason": "stop"}]}])
        with patch.object(probe.urllib.request, "urlopen", return_value=response) as opened:
            probe.measure("http://127.0.0.1:18765/v1/chat/completions", "", "gemma", "long_images", 10, "local")
        request = opened.call_args.args[0]
        payload = json.loads(request.data)
        self.assertIsNone(request.get_header("Authorization"))
        self.assertFalse(payload["enable_thinking"])
        self.assertNotIn("thinking", payload)
        self.assertEqual(payload["messages"], probe.messages("long_images"))
        self.assertEqual(payload["max_tokens"], 800)

    def test_summary_excludes_errors_and_keeps_first_sample(self) -> None:
        rows = [dict(case="short_text", first_token_seconds=value, first_sentence_seconds=value + 1,
                     total_seconds=value + 2) for value in (1, 2, 6)]
        rows.append(dict(case="short_text", error="HTTP 429"))
        summary = probe.summarize(rows)["short_text"]
        self.assertEqual(summary["successes"], 3)
        self.assertEqual(summary["errors"], 1)
        self.assertEqual(summary["metrics"]["first_token_seconds"]["median"], 2)
        self.assertEqual(summary["metrics"]["first_token_seconds"]["maximum"], 6)


if __name__ == "__main__":
    unittest.main()
