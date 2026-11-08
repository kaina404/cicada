import base64,json,time,urllib.request,re,pathlib
root=pathlib.Path('/Users/xiaohui/Project/CicadaProject')
src=(root/'Sources/Cicada/InterviewCoachLogic.swift').read_text()
system=re.search(r'enum CoachPrompt.*?static let system = """\n(.*?)\n    """',src,re.S).group(1)
system='\n'.join(l[4:] if l.startswith('    ') else l for l in system.splitlines())
image=base64.b64encode(pathlib.Path('/tmp/cicada-coach-slide.jpg').read_bytes()).decode()
rows=[]
for name,n,images in [('short_text',1,0),('short_3_images',1,3),('long_3_images',35,3),('long_text',35,0)]:
 turns=[]
 for i in range(n-1):
  turns.append(dict(id=str(i),seconds=i*5,role='candidate' if i%2 else 'interviewer',text=('I would use Room as the source of truth, a persistent outbox, WorkManager retries with backoff, and a stable per-message idempotency key. ' if i%2 else 'How do you handle offline writes, process death, ordering, authentication, and duplicates in an Android messaging application? ')*3))
 turns.append(dict(id='q',seconds=n*5,role='interviewer',text='How would you make offline message retries safe after process death?'))
 content=[dict(type='text',text='Reference background:\nSynthetic ActAI Android interview.\nActual speech (JSON; seconds from meeting start):\n'+json.dumps(turns,separators=(',',':')))]
 for i in range(images):content.extend([dict(type='text',text=f'Screen keyframe at {i} seconds:'),dict(type='image_url',image_url=dict(url='data:image/jpeg;base64,'+image))])
 content.append(dict(type='text',text='Immutable committed user speech (reference only):\n\nWrite the COMPLETE remaining English answer now. Start with a useful spoken sentence, with no labels.'))
 body=json.dumps(dict(model='mlx-community/gemma-4-E4B-it-qat-4bit',messages=[dict(role='system',content=system),dict(role='user',content=content)],stream=True,temperature=0,max_tokens=65,enable_thinking=False)).encode()
 start=time.monotonic();first=None;sentence=None;answer=''
 req=urllib.request.Request('http://127.0.0.1:18765/v1/chat/completions',data=body,headers={'Content-Type':'application/json'})
 with urllib.request.urlopen(req,timeout=120) as response:
  for line in response:
   if not line.startswith(b'data:'):continue
   data=line[5:].strip()
   if data==b'[DONE]':break
   obj=json.loads(data);piece=obj.get('choices',[{}])[0].get('delta',{}).get('content') or ''
   if not piece:continue
   elapsed=time.monotonic()-start
   if first is None:first=elapsed
   answer+=piece
   if sentence is None and re.search(r'[.!?](?:\s|$)',answer):sentence=elapsed
 row=dict(case=name,turns=n,images=images,request_bytes=len(body),first_token=first,first_sentence=sentence,total=time.monotonic()-start)
 rows.append(row);print(json.dumps(row),flush=True)
 (root/'outputs/coach-latency-analysis/probe.json').write_text(json.dumps(rows,indent=2))
