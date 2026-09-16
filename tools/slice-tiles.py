#!/usr/bin/env python3
"""Slice ChatGPT-rendered icon rows (pure black background) into Tiles.xcassets.
   usage: slice-tiles.py <image> <shape: squircle|circle> <points> <id,id,...>
   Icons are found as runs of non-black columns; each is cropped to its bounding box, resized, masked, saved @3x."""
import sys, os, json
from PIL import Image, ImageDraw
img_path, shape, points, ids = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4].split(",")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = f"{ROOT}/ios/Shared/Tiles.xcassets"
im = Image.open(img_path).convert("RGBA")
W, H = im.size
px = im.load()
def lit(x, y):
    r, g, b, a = px[x, y]
    return a > 10 and (r + g + b) > 60
def runs_of(flags, minlen):
    out, start = [], None
    for i, c in enumerate(list(flags) + [False]):
        if c and start is None: start = i
        if not c and start is not None:
            if i - start > minlen: out.append((start, i))
            start = None
    return out
# grid: split into rows of icons first, then columns within each row (row-major ids)
row_runs = runs_of([any(lit(x, y) for x in range(0, W, 2)) for y in range(H)], H * 0.03)
cells = []
for (ry0, ry1) in row_runs:
    col_runs = runs_of([any(lit(x, y) for y in range(ry0, ry1, 2)) for x in range(W)], W * 0.03)
    for (cx0, cx1) in col_runs: cells.append((cx0, cx1, ry0, ry1))
assert len(cells) == len(ids), f"found {len(cells)} icons, expected {len(ids)}: {cells}"
runs = cells
def squircle_mask(n, radius_frac=0.2237, k=5.0):
    m = Image.new("L", (n, n), 0); d = ImageDraw.Draw(m)
    # superellipse approximated by a polygon
    import math
    r = n / 2; pts = []
    for i in range(720):
        t = 2 * math.pi * i / 720
        c, s = math.cos(t), math.sin(t)
        x = r * (abs(c) ** (2 / k)) * (1 if c >= 0 else -1)
        y = r * (abs(s) ** (2 / k)) * (1 if s >= 0 else -1)
        pts.append((r + x, r + y))
    d.polygon(pts, fill=255); return m
def circle_mask(n):
    m = Image.new("L", (n, n), 0); ImageDraw.Draw(m).ellipse((0, 0, n - 1, n - 1), fill=255); return m
for (x0, x1, ry0, ry1), id_ in zip(runs, ids):
    rows = [y >= ry0 and y < ry1 and any(lit(x, y) for x in range(x0, x1, 2)) for y in range(H)]
    y0 = rows.index(True); y1 = H - rows[::-1].index(True)
    # square the box on the larger side, centred
    side = max(x1 - x0, y1 - y0); cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    box = (int(cx - side / 2), int(cy - side / 2), int(cx + side / 2), int(cy + side / 2))
    crop = im.crop(box)
    n = 1024
    crop = crop.resize((n, n), Image.LANCZOS)
    # the rendered squircle sits slightly inside the bbox (soft edge); mask a hair inside to kill black fringe
    mask = squircle_mask(n) if shape == "squircle" else circle_mask(n)
    inset = int(n * 0.012)
    mask = mask.resize((n - 2 * inset, n - 2 * inset), Image.LANCZOS)
    full = Image.new("L", (n, n), 0); full.paste(mask, (inset, inset))
    crop.putalpha(full)
    size = points * 3
    out = crop.resize((size, size), Image.LANCZOS)
    d = f"{OUT}/{id_}.imageset"; os.makedirs(d, exist_ok=True)
    for f in os.listdir(d):
        if f.endswith(".png"): os.remove(f"{d}/{f}")
    out.save(f"{d}/{id_}@3x.png")
    json.dump({"images": [{"filename": f"{id_}@3x.png", "idiom": "universal", "scale": "3x"}],
               "info": {"author": "xcode", "version": 1}}, open(f"{d}/Contents.json", "w"), indent=2)
    print(id_, box, "->", size)
