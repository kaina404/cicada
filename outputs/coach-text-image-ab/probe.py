import base64,json,time,urllib.request,re,pathlib,statistics
root=pathlib.Path('/Users/xiaohui/Project/CicadaProject')
src=(root/'Sources/Cicada/InterviewCoachLogic.swift').read_text()
system=re.search(r'enum CoachPrompt.*?static let system = """\n(.*?)\n    """',src,re.S).group(1)
system='\n'.join(line[4:] if line.startswith('    ') else line for line in system.splitlines())
image=base64.b64encode(pathlib.Path('/tmp/cicada-coach-slide.jpg').read_bytes()).decode()
audio=base64.b64encode(pathlib.Path('/tmp/cicada-coach-question-ab.wav').read_bytes()).decode()
turn=[dict(id='q',seconds=20,role='interviewer',text='How would you keep messages reliable offline, and what is the first visible token target on the slide?')]
base=[{'type':'text','text':'Reference background:\nThis is a synthetic Android interview. Do not invent work experience.\nActual speech (JSON; seconds from meeting start):\n'+json.dumps(turn,separators=(',',':'))},{'type':'text','text':'Screen keyframe at 18.0 seconds:'},{'type':'text','text':'Screen OCR (reference): First visible token target: 850 ms'},{'type':'image_url','image_url':{'url':'data:image/jpeg;base64,'+image}}]
tail={'type':'text','text':'Immutable committed user speech (reference only):\n\nWrite the COMPLETE remaining English answer now. Start with a useful spoken sentence, with no labels.'}
reports=[]
# Alternate order to expose warm-cache/order effects; no competing requests in this probe.
for index,with_audio in enumerate([True,False,False,True,True,False]):
    content=base.copy()
    if with_audio: content += [{'type':'text','text':'Original system audio, interviewer, ending at 20.0 seconds (not the candidate):'},{'type':'input_audio','input_audio':{'data':audio,'format':'wav'}}]
    content.append(tail)
    body=json.dumps(dict(model='mlx-community/gemma-4-E4B-it-qat-4bit',messages=[dict(role='system',content=system),dict(role='user',content=content)],stream=True,temperature=0,max_tokens=1600,enable_thinking=False)).encode()
    req=urllib.request.Request('http://127.0.0.1:18765/v1/chat/completions',data=body,headers={'Content-Type':'application/json'})
    start=time.monotonic();first=None;sentence=None;text=''
    with urllib.request.urlopen(req,timeout=120) as response:
        for line in response:
            if not line.startswith(b'data:'):continue
            data=line[5:].strip()
            if data==b'[DONE]':break
            obj=json.loads(data);piece=obj.get('choices',[{}])[0].get('delta',{}).get('content') or ''
            if not piece:continue
            elapsed=time.monotonic()-start
            if first is None:first=elapsed
            text+=piece
            if sentence is None and re.search(r'[.!?](?:\s|$)',text):sentence=elapsed
    row=dict(run=index+1,audio=with_audio,request_bytes=len(body),first=first,first_sentence=sentence,total=time.monotonic()-start,mentions_850='850' in text,mentions_room='room' in text.lower(),output=text)
    reports.append(row)
    (root/'outputs/coach-text-image-ab/report.json').write_text(json.dumps(reports,indent=2))
    print(json.dumps({k:v for k,v in row.items() if k!='output'}),flush=True)
for mode in [True,False]:
    rows=[r for r in reports if r['audio']==mode]
    print(json.dumps(dict(audio=mode,median={key:statistics.median(r[key] for r in rows) for key in ['first','first_sentence','total']})),flush=True)
