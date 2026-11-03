"""Original station printwork and wall wear, rendered once into reusable textures."""
from pathlib import Path
import random
from PIL import Image, ImageDraw, ImageFont, ImageFilter
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/station_detail'
rng=random.Random(701)
font=ROOT/'ui/fonts/SpecialElite.ttf'
def f(size):return ImageFont.truetype(str(font),size)
def paper():
 im=Image.new('RGB',(768,1024),(197,185,151)); pix=im.load()
 for y in range(1024):
  for x in range(768):
   n=rng.randrange(-10,11); edge=min(x,767-x,y,1023-y); dark=max(0,12-edge)//2
   pix[x,y]=(197+n-dark,185+n-dark,151+n-dark)
 d=ImageDraw.Draw(im);d.rectangle((30,30,738,994),outline=(67,72,59),width=4)
 for _ in range(80):
  x=rng.randrange(25,740); y=rng.randrange(25,1000);d.line((x,y,x+rng.randrange(2,12),y),fill=(156,145,116),width=1)
 d.rectangle((62,18,200,55),fill=(168,151,108));d.rectangle((550,970,700,1007),fill=(168,151,108))
 return im,d
def centered(d,y,text,size=45):
 d.text((384,y),text,font=f(size),fill=(36,53,46),anchor='mt')
im,d=paper();centered(d,95,'STATION SEVEN',55);centered(d,180,'NIGHT SERVICE',36)
d.line((85,260,683,260),fill=(36,53,46),width=7)
centered(d,305,'NORTH TERMINAL',51);centered(d,405,'PLATFORM 7',68)
for i,t in enumerate(['Follow the live platform signal.','Wait behind the yellow line.','Keep the exit route clear.']):centered(d,565+i*80,t,28)
centered(d,885,'SERVICE CONTINUES UNTIL DAWN',27);im.save(OUT/'night-service.png')
im,d=paper();centered(d,95,'STAFF NOTICE',59);centered(d,205,'CIRCULAR 17 / NIGHT CREW',29)
for i,t in enumerate(['A voice is not a service order.','','Check the official indicator','before cancelling a departure.','','Confirm any fault in person.','Report missing passengers.','','Sign your own name.']):centered(d,335+i*56,t,31)
centered(d,900,'KEEP THIS NOTICE POSTED',26);im.save(OUT/'staff-notice.png')
im,d=paper();centered(d,100,'MIND THE GAP',62)
d.polygon([(384,250),(145,650),(623,650)],outline=(49,57,42),width=10)
d.line((384,345,384,495),fill=(49,57,42),width=22);d.ellipse((371,538,397,564),fill=(49,57,42))
for i,t in enumerate(['Let passengers leave first.','Hold the handrail.','Keep tactile paving clear.']):centered(d,720+i*65,t,31)
im.save(OUT/'platform-safety.png')
im=Image.new('RGBA',(256,512),(0,0,0,0));d=ImageDraw.Draw(im)
for _ in range(130):
 x=rng.randrange(256);y=rng.randrange(512);r=rng.randrange(3,36)
 d.ellipse((x-r,y-r*2,x+r,y+r*2),fill=(38,33,25,rng.randrange(4,32)))
for _ in range(50):
 x=rng.randrange(256);y=rng.randrange(512);d.line((x,y,x+rng.randrange(-15,15),min(511,y+rng.randrange(20,120))),fill=(44,39,30,rng.randrange(15,60)),width=rng.randrange(1,4))
im=im.filter(ImageFilter.GaussianBlur(2));im.save(OUT/'wall-wear.png')
