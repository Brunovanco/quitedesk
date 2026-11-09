import sys
from PIL import Image, ImageChops
import numpy as np
src = sys.argv[1]; out = sys.argv[2]
im = Image.open(src).convert("RGB")
a = np.asarray(im).astype(int)
# alpha from distance to white (anti-aliased edges)
dist = (255*3 - a.sum(axis=2)) / 3.0
alpha = np.clip(dist*2.2, 0, 255)
# un-premultiply colour against white
al = np.maximum(alpha/255.0, 1e-3)[...,None]
rgb = np.clip((a - 255*(1-al))/al, 0, 255)
rgba = np.dstack([rgb, alpha]).astype(np.uint8)
full = Image.fromarray(rgba, "RGBA")
bbox = full.getbbox(); print("bbox", bbox)
word = full.crop(bbox)
def fit(img, W, H, pad=0):
    img = img.copy(); img.thumbnail((W-2*pad, H-2*pad), Image.LANCZOS)
    c = Image.new("RGBA", (W, H), (0,0,0,0)); c.paste(img, ((W-img.width)//2, (H-img.height)//2), img); return c
# logo 600x120 (displayed at max 300x60)
fit(word, 600, 120).save(f"{out}/logo_light.png")
fit(word, 600, 120).save(f"{out}/logo.png")
# dark variant: blue -> near white, green kept
d = np.asarray(word).copy()
blue = (d[...,2] > d[...,1]+30) & (d[...,3] > 0)
d[blue,0:3] = [235,240,255]
fit(Image.fromarray(d,"RGBA"), 600, 120).save(f"{out}/logo_dark.png")
# icon: the Q + check (left part of word mark). find gap column after Q
w = np.asarray(word)[...,3]
cols = (w>40).sum(axis=0)
x=0
# skip Q: find first empty column after content > 15% width
start = int(word.width*0.12)
for i in range(start, word.width):
    if cols[i]==0: x=i; break
q = word.crop((0,0,x,word.height)); q = q.crop(q.getbbox()); print("Q size", q.size)
side = max(q.size)
def square(img, S, padfrac=0.08, bg=None):
    c = Image.new("RGBA",(S,S),(0,0,0,0) if bg is None else bg)
    inner = int(S*(1-2*padfrac)); r=inner/max(img.size); t = img.resize((max(1,int(img.width*r)),max(1,int(img.height*r))), Image.LANCZOS)
    c.paste(t,((S-t.width)//2,(S-t.height)//2),t); return c
icon1024 = square(q, 1024, 0.06)
icon1024.save(f"{out}/icon.png")
# app icon with white rounded tile (better on dark taskbars / macOS dock)
from PIL import ImageDraw
tile = Image.new("RGBA",(1024,1024),(0,0,0,0)); dr = ImageDraw.Draw(tile)
dr.rounded_rectangle((100,100,924,924), radius=185, fill=(255,255,255,255))
r=640/max(q.size); qi = q.resize((int(q.width*r),int(q.height*r)), Image.LANCZOS)
tile.paste(qi,((1024-qi.width)//2,(1024-qi.height)//2),qi)
tile.save(f"{out}/app_icon_1024.png")
sizes=[16,24,32,48,64,128,256]
tile.save(f"{out}/icon.ico", sizes=[(s,s) for s in sizes])
icon1024.save(f"{out}/tray-icon.ico", sizes=[(s,s) for s in [16,24,32,48,64]])
for s,n in [(32,"32x32"),(64,"64x64"),(128,"128x128"),(256,"128x128@2x")]:
    tile.resize((s,s), Image.LANCZOS).save(f"{out}/{n}.png")
tile.resize((512,512), Image.LANCZOS).save(f"{out}/mac-icon.png")
# mac tray template: black silhouette with alpha
m = np.asarray(square(q, 44, 0.04)).copy(); m[...,0:3]=0
Image.fromarray(m,"RGBA").save(f"{out}/mac-tray-dark-x2.png")
Image.fromarray(m,"RGBA").save(f"{out}/mac-tray-light-x2.png")
# iconset for icns
import os
os.makedirs(f"{out}/AppIcon.iconset", exist_ok=True)
for s in [16,32,128,256,512]:
    tile.resize((s,s),Image.LANCZOS).save(f"{out}/AppIcon.iconset/icon_{s}x{s}.png")
    tile.resize((2*s,2*s),Image.LANCZOS).save(f"{out}/AppIcon.iconset/icon_{s}x{s}@2x.png")
