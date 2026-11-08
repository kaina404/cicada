#!/usr/bin/env python3
"""Manual, local-only knowledge evaluation. Human reviewers score expected_points; no auto grade."""
import argparse
import json
import re
from pathlib import Path
import subprocess
import time
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
# The app's own prompt for a 问 answer, pinned by CopilotTests.evaluatorUsesTheProductPrompt.
PROMPT = json.loads((ROOT / 'tools/copilot-prompt.json').read_text())
SYSTEM = PROMPT['system']


def user_message(background, question):
    # The app names the language it detects; the practice questions are English or Chinese.
    language = 'Chinese' if re.search(r'[\u4e00-\u9fff]', question) else 'English'
    return (PROMPT['user'].replace('{{BACKGROUND}}', background).replace('{{QUESTION}}', question)
            .replace('{{LANGUAGE}}', language))


def follows_format(answer):
    """The app reads 'Q:' then '- ' lines; anything else shows as a stray line."""
    lines = [l.replace('**', '').strip() for l in answer.splitlines() if l.strip()]
    return bool(lines) and lines[0].startswith(('Q:', 'Q：')) and any(l.startswith('- ') for l in lines[1:])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', help='Defaults to the dev app’s screenModel setting')
    parser.add_argument('--questions', type=Path, default=ROOT / 'tools/copilot-questions.json')
    parser.add_argument('--background', type=Path, default=ROOT / 'tools/copilot-interview-background.json',
                        help='Source-labelled candidate and company context, sent only to the local model')
    parser.add_argument('--output', type=Path, default=Path('/tmp/cicada-copilot-eval.json'))
    parser.add_argument('--limit', type=int)
    args = parser.parse_args()
    if not args.model:
        result = subprocess.run(['defaults', 'read', 'com.wquguru.cicada.dev', 'screenModel'], capture_output=True, text=True)
        args.model = result.stdout.strip()
    if not args.model:
        parser.error('Supply --model, or configure the dev app’s local model first.')
    questions = json.loads(args.questions.read_text())[:args.limit]
    background = json.loads(args.background.read_text())
    background_text = json.dumps(background, ensure_ascii=False)
    reports = []
    for q in questions:
        body = {'model': args.model, 'stream': True, 'temperature': 0, 'max_tokens': 400, 'enable_thinking': False,
                'messages': [{'role': 'system', 'content': SYSTEM}, {'role': 'user', 'content':
                    user_message(background_text + '\n' + q.get('context', ''), q['question'])}]}
        req = urllib.request.Request('http://127.0.0.1:18765/v1/chat/completions',
                                     data=json.dumps(body).encode(), headers={'Content-Type': 'application/json'})
        started = time.monotonic()
        first = None
        answer = ''
        error = None
        try:
            with urllib.request.urlopen(req, timeout=90) as response:
                for raw in response:
                    if not raw.startswith(b'data:'):
                        continue
                    data = raw[5:].strip()
                    if data == b'[DONE]':
                        break
                    event = json.loads(data)
                    piece = event.get('choices', [{}])[0].get('delta', {}).get('content', '')
                    if piece:
                        if first is None:
                            first = time.monotonic() - started
                        answer += piece
        except Exception as exc:
            error = str(exc)
        reports.append(dict(q, model=args.model, first_seconds=first, total_seconds=time.monotonic() - started,
                            answer=answer, error=error, follows_format=follows_format(answer),
                            human_score=None, reviewer_notes=''))
        args.output.write_text(json.dumps({'system': SYSTEM, 'background': background, 'results': reports}, ensure_ascii=False, indent=2))
        print(f"{q['id']}: first={first if first is not None else 'n/a'} total={reports[-1]['total_seconds']:.2f}s", flush=True)
    compliant = sum(r['follows_format'] for r in reports)
    print(f'Format (Q: then - lines): {compliant}/{len(reports)}')
    print(f'Human scoring required: {args.output}')


if __name__ == '__main__':
    main()
