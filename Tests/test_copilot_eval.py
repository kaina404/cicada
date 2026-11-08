"""Offline checks for the interview evaluator's source context and report provenance."""
import io
import json
from pathlib import Path
import runpy
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


class InterviewEvaluationTests(unittest.TestCase):
    def test_default_background_reaches_model_and_report(self):
        requests = []

        def local_response(request, timeout):
            self.assertEqual(request.full_url, 'http://127.0.0.1:18765/v1/chat/completions')
            requests.append(json.loads(request.data))
            return io.BytesIO(b'data: {"choices":[{"delta":{"content":"Q: Practice\\n- Resume evidence only."}}]}\n\ndata: [DONE]\n')

        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder) / 'report.json'
            args = ['copilot-eval.py', '--model', 'offline-test', '--limit', '1', '--output', str(out)]
            with patch('sys.argv', args), patch('urllib.request.urlopen', side_effect=local_response):
                runpy.run_path(str(ROOT / 'tools/copilot-eval.py'), run_name='__main__')
            report = json.loads(out.read_text())
        content = requests[0]['messages'][1]['content']
        self.assertIn('KKday', content)
        self.assertIn('not independently verified', content)
        self.assertIn('NOT this candidate', content)
        self.assertIn('Actual reasons for leaving', content)
        self.assertIn('Bad news', content)
        self.assertEqual(report['background'], json.loads((ROOT / 'tools/copilot-interview-background.json').read_text()))
        self.assertEqual(report['results'][0]['human_score'], None)
        self.assertEqual(report['results'][0]['error'], None)
        self.assertEqual(len(requests), 1)
        # The evaluator sends the app's own prompt, not a separate one.
        prompt = json.loads((ROOT / 'tools/copilot-prompt.json').read_text())
        self.assertEqual(requests[0]['messages'][0]['content'], prompt['system'])
        self.assertIn('<task>', content)
        self.assertTrue(report['results'][0]['follows_format'])

    def test_partial_failure_preserves_answer_and_remains_unscored(self):
        class BrokenStream(io.BytesIO):
            def __iter__(self):
                yield b'data: {"choices":[{"delta":{"content":"partial"}}]}\n'
                raise OSError('synthetic disconnect')

        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder) / 'report.json'
            args = ['copilot-eval.py', '--model', 'offline-test', '--limit', '1', '--output', str(out)]
            with patch('sys.argv', args), patch('urllib.request.urlopen', return_value=BrokenStream()):
                runpy.run_path(str(ROOT / 'tools/copilot-eval.py'), run_name='__main__')
            result = json.loads(out.read_text())['results'][0]
        self.assertEqual(result['answer'], 'partial')
        self.assertIn('synthetic disconnect', result['error'])
        self.assertIsNone(result['human_score'])

    def test_cases_cover_hr_and_source_conflicts(self):
        cases = json.loads((ROOT / 'tools/copilot-questions.json').read_text())
        ids = {case['id'] for case in cases}
        self.assertEqual(len(ids), len(cases))
        self.assertTrue({'hr-last-three', 'hr-hustle', 'hr-remote-scoreboard', 'hr-bad-news-unknown',
                         'resume-crash', 'source-biography-conflict', 'source-draft-instructions'} <= ids)
        self.assertTrue(all(case['question'] and case['expected_points'] for case in cases))


if __name__ == '__main__':
    unittest.main()
