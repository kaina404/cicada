from pathlib import Path
import json,wave
import numpy as np

root=Path(__file__).resolve().parent
scores=np.genfromtxt(root/'voice-scores-fine.csv',delimiter=',',names=True)
# Voice identity, rather than pitch or transcript semantics, determines the mask.
keep=(scores['male']>scores['female']+.035)&(scores['male']>.16)
# Remove isolated 100 ms decisions, keeping real short acknowledgements.
padded=np.pad(keep.astype(int),(1,1),mode='edge')
keep=(padded[:-2]+padded[1:-1]+padded[2:])>=2

def runs(mask):
 edges=np.diff(np.r_[False,mask,False].astype(int))
 return list(zip(np.flatnonzero(edges==1),np.flatnonzero(edges==-1)))

for s,e in runs(keep):
 if e-s<2:keep[s:e]=False
for s,e in runs(~keep):
 if s>0 and e<len(keep) and e-s<=1 and scores['female'][s:e].max()<.25:
  keep[s:e]=True
intervals=[]
for s,e in runs(keep):
 start=max(0,float(scores['center'][s])-.05)
 end=float(scores['center'][e-1])+.05
 # A small inward guard silences mixed windows at changes of speaker.
 if start>.1:start+=.06
 end-=.06
 if end>start:intervals.append((start,end))
with wave.open(str(root/'original.wav'),'rb') as w:
 params=w.getparams();sr=w.getframerate();ch=w.getnchannels()
 audio=np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').reshape(-1,ch)
assert params.sampwidth==2
result=np.zeros_like(audio)
fade=max(1,int(sr*.005))
for start,end in intervals:
 s=max(0,int(start*sr));e=min(len(audio),int(end*sr))
 if e<=s:continue
 chunk=audio[s:e].copy();n=min(fade,len(chunk)//2)
 if n:
  chunk[:n]=(chunk[:n].astype(float)*np.linspace(0,1,n)[:,None]).astype('<i2')
  chunk[-n:]=(chunk[-n:].astype(float)*np.linspace(1,0,n)[:,None]).astype('<i2')
 result[s:e]=chunk
with wave.open(str(root/'male-only.wav'),'wb') as w:
 w.setparams(params);w.writeframes(result.tobytes())
# Check actual PCM: outside retained spans must contain digital silence.
active=np.zeros(len(audio),dtype=bool)
for start,end in intervals:active[max(0,int(start*sr)):min(len(audio),int(end*sr))]=True
assert not np.any(result[~active])
report={'source':'/Users/xiaohui/Project/CicadaProject/AndroidEngineerMockInterview.mp4','method':'Local Core ML WeSpeaker voiceprint matching; 0.7 second windows every 0.1 second; silent outside male spans; 5ms fades','audio_sample_rate':sr,'audio_channels':ch,'duration_seconds':len(audio)/sr,'male_retained_seconds':sum(e-s for s,e in intervals),'male_intervals':intervals,'validation':{'muted_pcm_is_exactly_zero':True},'limitations':'Automatic speaker masking. Overlapping speech cannot be separated by a time mask; full human listening review has not been performed.'}
(root/'processing-report.json').write_text(json.dumps(report,indent=2))
print(json.dumps({k:v for k,v in report.items() if k!='male_intervals'},indent=2))
