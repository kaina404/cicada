"""Validate Codex benchmark counts visible answer events and rejects tool turns."""
import importlib.util
from pathlib import Path
import queue
import unittest

spec = importlib.util.spec_from_file_location('model_latency_probe', Path(__file__).resolve().parents[1] / 'tools/test_model_latency.py')
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class CodexLatencyTests(unittest.TestCase):
    def server(self, events):
        server = probe.CodexServer.__new__(probe.CodexServer)
        server.home = Path('/tmp/benchmark-test')
        server.seq = 1
        server.rpc = lambda *_: dict(model='gpt-5.6-sol', reasoningEffort='none', thread=dict(id='test'))
        server.sent = []
        server.send = server.sent.append
        server.events = queue.Queue()
        for event in events:
            server.events.put(event)
        return server

    def test_visible_text_only_and_identical_inputs(self):
        events = [
            dict(method='item/reasoning/summaryTextDelta', params=dict(threadId='test', delta='Hidden.')),
            dict(method='item/agentMessage/delta', params=dict(threadId='other', delta='Ignore.')),
            dict(method='item/agentMessage/delta', params=dict(threadId='test', delta='Use Room')),
            dict(method='item/agentMessage/delta', params=dict(threadId='test', delta='. Then retry.')),
            dict(method='thread/tokenUsage/updated', params=dict(threadId='test', tokenUsage=dict(total=dict(reasoningOutputTokens=0)))),
            dict(method='turn/completed', params=dict(threadId='test', turn=dict(status='completed'))),
        ]
        server = self.server(events)
        row = server.measure('gpt-5.6-sol', 'short_images', 'none')
        self.assertEqual(row['output'], 'Use Room. Then retry.')
        self.assertEqual(row['first_token_seconds'], row['stream'][0]['seconds'])
        self.assertEqual(row['first_sentence_seconds'], row['stream'][1]['seconds'])
        inputs = server.sent[0]['params']['input']
        expected = probe.baseline.messages('short_images')[1]['content']
        self.assertEqual([p['url'] for p in inputs if p['type'] == 'image'],
                         [p['image_url']['url'] for p in expected if p['type'] == 'image_url'])
        self.assertEqual([p['text'] for p in inputs if p['type'] == 'text'],
                         [p['text'] for p in expected if p['type'] == 'text'])

    def test_tool_turn_is_not_a_latency_success(self):
        server = self.server([
            dict(method='item/started', params=dict(item=dict(type='commandExecution'))),
            dict(method='item/agentMessage/delta', params=dict(delta='Answer.')),
            dict(method='turn/completed', params=dict(turn=dict(status='completed'))),
        ])
        with self.assertRaises(RuntimeError):
            server.measure('gpt-5.6-sol', 'short_text', 'none')

    def test_failed_turn_is_not_a_latency_success(self):
        server = self.server([dict(method='turn/completed', params=dict(turn=dict(status='failed')))])
        with self.assertRaises(RuntimeError):
            server.measure('gpt-5.6-sol', 'short_text', 'none')


if __name__ == '__main__':
    unittest.main()
