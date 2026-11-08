#!/usr/bin/env python3
"""Make a five-minute synthetic ActAI Android practice interview with macOS say; does not play or upload it."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import wave

TURNS = [
    (5, 'statement', 'Welcome to this practice interview for the Android Software Engineer role at ActAI. We will discuss an agent-first mobile communication app.'),
    (20, 'question', 'How would you design a Kotlin chat client that shows streaming AI responses and allows the user to cancel?'),
    (47, 'statement', 'For this practice scenario only, our first visible token target is 850 milliseconds. This is a target, not a measured result.'),
    (65, 'question', 'How would you use StateFlow and Jetpack Compose without redrawing the whole chat list for every token?'),
    (94, 'concern', 'I am concerned that collecting a Flow after the screen closes could leak an Activity and leave the network request running.'),
    (125, 'statement', 'Next topic is Binder. The practice app also processes voice and images. We need to measure frame time and memory on a midrange Android phone.'),
    (150, 'question', 'Why can a synchronous Binder call on the main thread cause an application not responding error?'),
    (184, 'statement', 'Next topic is TensorFlow Lite. On-device classification must be evaluated for quality, latency, memory, and battery before choosing a backend fallback.'),
    (210, 'concern', 'We are worried about duplicate messages after a stream reconnects. Retrying must not silently send the same agent action twice.'),
    (245, 'question', 'What first visible token target did we agree earlier, and how would you measure it and monitor failures without logging private messages?'),
    (275, 'statement', 'That concludes the practice interview. We have not provided candidate work history, Play Store releases, or measured performance results.'),
]

HR_TURNS = [
    (5, 'statement', 'Welcome to this ActAI HR practice interview. Your resume lists ten years of software engineering, most recently KKday, Kezhi and Debon Securities.'),
    (20, 'question', 'Why are you exploring new opportunities, and why this proactive voice and text communication product specifically?'),
    (47, 'statement', 'At KKday, your resume describes leading a five person AI itinerary team and streaming partial results to Android with SSE.'),
    (65, 'question', 'Tell me why you left your last three companies. The resume provides dates but does not provide your reasons.'),
    (94, 'concern', 'I am concerned that your motivation is only a general interest in AI. We need product judgment about low prompting and reliable communication.'),
    (125, 'statement', 'Next topic is remote accountability. Our briefing describes global collaboration and a small founding team. Personal work habits have not been confirmed.'),
    (150, 'question', 'How would you stay accountable daily and weekly, and what outcomes would be on your personal scoreboard?'),
    (184, 'statement', 'A useful proposed scoreboard tracks delivery reliability, quality and performance, and unblocking teammates. These are suggestions, not proven personal habits.'),
    (210, 'concern', 'We are worried about adapting to rapid pivots. Please explain your approach and honest boundaries without inventing a past sprint story.'),
    (245, 'question', 'Would you report bad news early if the root cause is still unknown, and what would your first update contain?'),
    (275, 'statement', 'The HR draft biography is only an example. It does not establish OKX employment or a salary for this candidate. We still need real departure reasons and a concrete bad news story.'),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scenario', choices=['technical', 'hr'], default='technical')
    args = parser.parse_args()
    turns = HR_TURNS if args.scenario == 'hr' else TURNS
    out = Path('/tmp/cicada-copilot-hr.wav' if args.scenario == 'hr' else '/tmp/cicada-copilot-discussion.wav')
    rate = 24000
    audio = bytearray(rate * 2 * 300)
    manifest = []
    with tempfile.TemporaryDirectory(prefix='cicada-say-') as tmp:
        for i, (at, kind, text) in enumerate(turns):
            clip = Path(tmp) / f'{i}.wav'
            subprocess.run(['say', '-v', 'Samantha', '-r', '175', '--file-format=WAVE',
                            '--data-format=LEI16@24000', '-o', str(clip), text], check=True)
            with wave.open(str(clip)) as f:
                assert f.getnchannels() == 1 and f.getsampwidth() == 2 and f.getframerate() == rate
                data = f.readframes(f.getnframes())
            start = at * rate * 2
            audio[start:start + len(data)] = data
            manifest.append(dict(start=at, end=at + len(data) / (rate * 2), kind=kind, text=text))
    with wave.open(str(out), 'wb') as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(rate); f.writeframes(audio)
    out.with_suffix('.json').write_text(json.dumps(manifest, indent=2))
    print(out)


if __name__ == '__main__':
    main()
