import numpy as np, sys
from PIL import Image as I, ImageFilter
src = I.open(sys.argv[1]).convert("RGB")
a = np.asarray(src).astype(np.float32)
r,g,b = a[...,0],a[...,1],a[...,2]
mn = a.min(-1); mx = a.max(-1)
seed_white = (mn > 175) & (mx - mn < 70)
light = (mn > 120) & (mx - mn < 90) & ~((b > r + 60) & (b > 150))  # pale, not shoe-blue
blue = (b>140)&(b>r+50)&(b>g+15)
bf = np.asarray(I.fromarray((blue*255).astype(np.uint8)).filter(ImageFilter.BoxBlur(10))).astype(np.float32)/255
mask = seed_white & (bf > 0.35)
for _ in range(40):
    d = np.asarray(I.fromarray((mask*255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3)))>0
    # grow only through pale pixels that still sit in a mostly-blue neighbourhood
    nm = d & light & (bf > 0.12)
    nm |= mask
    if (nm == mask).all(): break
    mask = nm
mask = np.asarray(I.fromarray((mask*255).astype(np.uint8)).filter(ImageFilter.MaxFilter(7)))>0
out = a.copy(); known = ~mask
for _ in range(200):
    if known.all(): break
    acc = np.zeros_like(out); cnt = np.zeros(out.shape[:2])
    for dy,dx in [(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(1,1),(-1,1),(1,-1)]:
        sh = np.roll(np.roll(out,dy,0),dx,1); k = np.roll(np.roll(known,dy,0),dx,1)
        acc += sh*k[...,None]; cnt += k
    fill = (~known)&(cnt>0)
    out[fill] = acc[fill]/cnt[fill][:,None]; known = known|fill
res = I.fromarray(out.clip(0,255).astype(np.uint8)); res.save(sys.argv[2])
boxes=[(270,110,370,210),(840,110,960,220),(560,200,660,310),(880,690,980,820)]
sheet=I.new("RGB",(4*240,2*240),"white")
for i,bx in enumerate(boxes):
    sheet.paste(src.crop(bx).resize((240,240)),(i*240,0)); sheet.paste(res.crop(bx).resize((240,240)),(i*240,240))
sheet.save("swoosh_check.png"); I.fromarray((mask*255).astype(np.uint8)).save("swoosh_mask.png")
print("masked", mask.sum())
