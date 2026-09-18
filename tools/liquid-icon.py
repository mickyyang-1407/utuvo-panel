#!/usr/bin/env python3
"""Turn a mark + one product colour into an Apple-quality Icon Composer .icon (calibrated 2026-09-18
against Apple's macOS 27 icons; see tools/make-tiles.py for the measurements).

usage: liquid-icon.py <mark.svg|png> <#RRGGBB> <out.icon> [--glyph #FFFFFF] [--scale 1.15] [--preview out.png]

  background : two-stop linear gradient, top = product colour lifted 22 % toward white, bottom = product colour
               (Apple's own icons: Messages, Mail, Music, Books all follow this shape)
  mark       : one glass layer, translucency 0.5, neutral shadow 0.5, lighting individual
  size       : layer scale 1.15 — the UTUVO family standard (same extents as every UTUVO .icon since 08-2026)
"""
import argparse, json, os, shutil, subprocess, tempfile, io
from PIL import Image, ImageCms

ICTOOL = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"


def rgb(h):
    h = h.lstrip("#"); return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def c(v):
    return "extended-srgb:%.5f,%.5f,%.5f,1.0" % tuple(x / 255 for x in v)


def lift(v, t=0.22):
    return tuple(round(x + (255 - x) * t) for x in v)


def write(pkg, mark, colour, glyph, scale, mark_name="mark"):
    shutil.rmtree(pkg, ignore_errors=True); os.makedirs(f"{pkg}/Assets")
    ext = os.path.splitext(mark)[1]; shutil.copy(mark, f"{pkg}/Assets/{mark_name}{ext}")
    doc = {"fill": {"linear-gradient": [c(lift(colour)), c(colour)]},
           "groups": [{"layers": [{"glass": True, "image-name": f"{mark_name}{ext}", "name": mark_name, "fill": {"solid": c(glyph)},
                                   "position": {"scale": scale, "translation-in-points": [0, 0]}}],
                       "lighting": "individual", "shadow": {"kind": "neutral", "opacity": 0.5},
                       "translucency": {"enabled": True, "value": 0.5}}],
           "supported-platforms": {"circles": ["watchOS"], "squares": "shared"}}
    json.dump(doc, open(f"{pkg}/icon.json", "w"), indent=2)


def render(pkg, out, px=512):
    subprocess.run([ICTOOL, pkg, "--export-image", "--output-file", out, "--platform", "iOS", "--rendition", "Default",
                    "--width", str(px // 2), "--height", str(px // 2), "--scale", "2", "--design-generation", "27"],
                   check=True, capture_output=True)


def mark_height(png, bg_top):
    im = Image.open(png); icc = im.info.get("icc_profile"); im = im.convert("RGBA")
    if icc:
        s = ImageCms.profileToProfile(im.convert("RGB"), ImageCms.ImageCmsProfile(io.BytesIO(icc)), ImageCms.createProfile("sRGB"), outputMode="RGB")
        s.putalpha(im.split()[3]); im = s
    W, H = im.size; p = im.load()
    ys = [y for y in range(H) for x in range(0, W, 3) if p[x, y][3] > 200]; y0, y1 = min(ys), max(ys)
    top = p[W // 2, y0 + int((y1 - y0) * .05)][:3]
    gy = [y for y in range(y0 + 8, y1 - 8) for x in range(0, W, 3) if p[x, y][3] > 200 and sum(abs(a - b) for a, b in zip(p[x, y][:3], top)) > 90]
    return (max(gy) - min(gy)) / (y1 - y0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mark"); ap.add_argument("colour"); ap.add_argument("out")
    ap.add_argument("--glyph", default="#FFFFFF"); ap.add_argument("--scale", type=float, default=1.15)
    ap.add_argument("--preview")
    a = ap.parse_args()
    colour, glyph = rgb(a.colour), rgb(a.glyph)
    write(a.out, a.mark, colour, glyph, a.scale)
    prev = a.preview or f"{tempfile.mkdtemp()}/final.png"
    render(a.out, prev)
    # the render is Display P3; store an sRGB copy so previews don't look washed out in viewers that ignore ICC
    im = Image.open(prev); icc = im.info.get("icc_profile")
    if icc:
        rgba = im.convert("RGBA")
        s = ImageCms.profileToProfile(rgba.convert("RGB"), ImageCms.ImageCmsProfile(io.BytesIO(icc)), ImageCms.createProfile("sRGB"), outputMode="RGB")
        s.putalpha(rgba.split()[3]); s.save(prev)
    print(f"{a.out}  scale {a.scale}  preview (sRGB) {prev}")


if __name__ == "__main__":
    main()
