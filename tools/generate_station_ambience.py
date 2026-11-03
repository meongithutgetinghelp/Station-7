"""Reproducible original station sound textures; no external recordings."""
import math, random, struct, wave
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]/'audio/ambience'
def render(name, seconds, kind, loop=False):
 r=random.Random(71+kind); rate=22050; data=bytearray(); low=0.; slower=0.
 for i in range(int(seconds*rate)):
  t=i/rate; noise=r.uniform(-1,1); low+=.045*(noise-low); slower+=.005*(noise-slower)
  envelope=1 if loop else math.sin(math.pi*t/seconds)**2
  if kind==0: sample=.12*low+.025*math.sin(2*math.pi*50*t)+.008*math.sin(2*math.pi*100*t)
  elif kind==1: sample=.22*slower+.028*math.sin(2*math.pi*35*t)*( .65+.35*math.sin(2*math.pi*t/seconds))
  elif kind==2: sample=.24*low+.035*math.sin(2*math.pi*(48*t+2*math.sin(t)))
  elif kind==3: sample=sum(.15*math.sin(2*math.pi*f*t)*math.exp(-max(0,t-start)*9) if t>=start else 0 for f,start in [(173,0),(311,.19),(127,.44)])+.025*low
  else: sample=.07*math.sin(2*math.pi*(150*t+12*t*t))+.045*low
  fade=min(1,t/.02,(seconds-t)/.04) if not loop else min(1,t/.08,(seconds-t)/.08)
  data.extend(struct.pack('<h',int(max(-.8,min(.8,sample*envelope*fade))*32767)))
 with wave.open(str(ROOT/(name+'.wav')),'wb') as w:w.setparams((1,2,rate,0,'NONE','not compressed'));w.writeframes(data)
for args in [('fluorescent',4,0,True),('tunnel-air',8,1,True),('distant-rail',7,2),('pipe-settle',2,3),('kiosk-servo',.65,4)]:render(*args)
