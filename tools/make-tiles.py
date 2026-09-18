#!/usr/bin/env python3
"""Render every icon asset the app uses with Apple's own renderer (Icon Composer's `ictool`).

Parameters are calibrated against Apple's macOS 27 icons (2026-09-18, Messages as the reference,
all colours compared in sRGB): glyph width 0.732 vs 0.73, background within 2 units, glyph colour
within 5 units.

  • background = two-stop linear gradient, top → bottom, sRGB values sampled from Apple's icons
  • glyph      = glass layer, translucency 0.5, neutral shadow 0.5, lighting individual
  • every layer is scaled 1.152: Icon Composer insets its canvas, so a glyph drawn at fraction f of
    the 1024 canvas only lands at fraction f of the icon after this scale

usage: python3 tools/make-tiles.py [asset-name ...]     (no names = everything)
Writes ios/Shared/Tiles.xcassets/<name>.imageset/<name>@3x.png and prunes image sets nobody renders.
"""
import json, os, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICTOOL = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
SYM = "/tmp/symbol2png"
OUT = f"{ROOT}/ios/Shared/Tiles.xcassets"
SVG = f"{ROOT}/tools/tiles"
SCALE = 1.152
if not os.path.exists(SYM):
    subprocess.check_call(["swiftc", "-O", f"{ROOT}/tools/symbol2png.swift", "-o", SYM])


def c(rgb):
    return "extended-srgb:%.5f,%.5f,%.5f,1.0" % tuple(v / 255 for v in rgb)


WHITE = (255, 255, 255)
YELLOW = (255, 214, 10)
MOON = (255, 238, 170)
DROP = (140, 215, 255)

# Backgrounds, sampled (sRGB) from Apple's own macOS 27 icons unless marked "derived".
BG = {
    "green":  ((82, 235, 106), (30, 203, 60)),     # Messages / Phone / FaceTime
    "blue":   ((0, 151, 253), (0, 118, 255)),      # Mail
    "sky":    ((51, 154, 255), (27, 112, 213)),    # Weather
    "red":    ((249, 52, 91), (249, 0, 47)),       # Music
    "orange": ((248, 135, 9), (249, 112, 0)),      # Books
    "purple": ((158, 70, 205), (120, 47, 159)),    # Podcasts
    "yellow": ((255, 196, 20), (248, 166, 0)),     # Tips
    "indigo": ((69, 26, 145), (45, 20, 126)),      # Shortcuts
    "black":  ((44, 44, 46), (15, 16, 16)),        # Stocks / Passwords
    "grey":   ((151, 151, 154), (121, 122, 126)),  # System Settings
    "ember":  ((236, 47, 36), (213, 43, 33)),      # Photo Booth
    "navy":   ((46, 51, 79), (20, 24, 44)),        # Journal, deepened for night skies
    "white":  ((250, 250, 250), (236, 236, 240)),  # Notes / Calendar / Clock bodies
    "teal":   ((0, 170, 200), (0, 110, 150)),      # derived (Freeform, lifted)
    "violet": ((110, 108, 245), (70, 66, 200)),    # derived (system indigo)
    "mint":   ((0, 205, 195), (0, 160, 150)),      # derived
    "pink":   ((255, 94, 128), (233, 38, 86)),     # derived
    "cloud":  ((142, 154, 172), (96, 108, 126)),   # derived — overcast
    "rain":   ((74, 118, 178), (38, 70, 122)),     # derived
    "snow":   ((128, 168, 218), (84, 124, 180)),   # derived
    "storm":  ((78, 66, 150), (38, 30, 92)),       # derived
}


def sf(name, box=0.70, color=WHITE, layer=None, weight="bold", glass=True, transl=0.5, dx=0, dy=0, shadow=True):
    return dict(kind="sf", name=name, box=box, color=color, layer=layer, weight=weight,
                glass=glass, transl=transl, shadow=shadow, dx=dx, dy=dy)


def inked(name, box, color, layer):
    """A symbol's inner detail printed onto its body in the background colour (the "A" in a bubble)."""
    return sf(name, box, color, layer=layer, glass=False, transl=0.0, shadow=False)


def art(file, color=WHITE, glass=True, transl=0.5, shadow=True):
    return dict(kind="svg", name=file, color=color, glass=glass, transl=transl, shadow=shadow, dx=0, dy=0)


def flat(file, color):
    """Printed marks on white bodies (Notes rules, Calendar dots): no glass, no shadow."""
    return art(file, color, glass=False, transl=0.0, shadow=False)


def tile(bg, *layers, pt=52, shape="squircle"):
    """Layers are listed top first — Icon Composer draws the first group on top."""
    return dict(bg=bg, layers=list(layers), pt=pt, shape=shape)


def weather(symbol, bg, *colors, box=0.68):
    """SF palette layer 0 is the body (cloud / moon / sun), layer 1 the accent (sun, rain, stars, bolt)."""
    return tile(bg, *[sf(symbol, box, col, layer=i) for i, col in reversed(list(enumerate(colors)))], pt=44)


RINGS = (art("ring-stand.svg", (30, 234, 239), transl=0.1), art("ring-exercise.svg", (146, 232, 42), transl=0.1),
         art("ring-move.svg", (250, 17, 79), transl=0.1), flat("ring-tracks.svg", (40, 40, 44)))

TILES = {
    # ── launchers (52 pt) ─────────────────────────────────────────────────────────────
    "tile-music":     tile("red", art("music-notes.svg")),
    "tile-messages":  tile("green", sf("message.fill", 0.73)),
    "tile-phone":     tile("green", sf("phone.fill", 0.69)),
    "tile-mail":      tile("blue", sf("envelope.fill", 0.78, transl=0.2)),
    "tile-books":     tile("orange", sf("book.fill", 0.70, transl=0.3)),
    "tile-maps":      tile("teal", art("maps-pin.svg", (255, 59, 48), transl=0.0), art("maps-fold.svg")),
    "tile-camera":    tile("grey", art("camera-lens-inner.svg", (143, 201, 255), transl=0.2),
                           art("camera-lens.svg", (58, 58, 63), glass=False, transl=0.0), art("camera-body.svg")),
    "tile-notes":     tile("white", flat("notes-lines.svg", (199, 199, 204)), flat("notes-band.svg", (249, 207, 33))),
    "tile-calendar":  tile("white", flat("cal-dot-red.svg", (255, 59, 48)), flat("cal-dots.svg", (58, 58, 63)),
                           flat("cal-band.svg", (255, 60, 69))),
    "tile-photos":    tile("pink", sf("photo.on.rectangle.angled", 0.72)),
    "tile-shortcuts": tile("indigo", art("sc-front.svg", (255, 95, 165), transl=0.35), art("sc-back.svg", (80, 170, 255))),
    "tile-weather":   tile("sky", sf("cloud.fill", 0.66, WHITE, dx=-40, dy=60), art("sun-disc.svg", YELLOW, transl=0.2)),
    "tile-clock":     tile("black", art("clock-second.svg", (255, 149, 0), transl=0.0),
                           art("clock-hands.svg", (28, 28, 30), transl=0.0),
                           flat("clock-ticks.svg", (60, 60, 67)), art("clock-face.svg", transl=0.15)),
    "tile-translate": tile("sky", inked("character.bubble.fill", 0.70, (27, 112, 213), 0),
                           sf("character.bubble.fill", 0.70, WHITE, layer=2)),
    "tile-fitness":   tile("black", *RINGS),
    # ── settings rows (shown at 29 pt) ────────────────────────────────────────────────
    "tile-activity":  tile("black", *RINGS),
    "tile-timer":     tile("orange", sf("timer", 0.66)),
    "tile-grid":      tile("indigo", sf("square.grid.2x2.fill", 0.62)),
    "tile-wallpaper": tile("teal", sf("photo.fill", 0.68)),
    "tile-home":      tile("green", sf("apps.iphone", 0.62)),
    "tile-seconds":   tile("orange", inked("stopwatch.fill", 0.64, (249, 112, 0), 0),
                           sf("stopwatch.fill", 0.64, WHITE, layer=2)),
    "tile-text":      tile("yellow", sf("textformat", 0.68)),
    "tile-location":  tile("blue", sf("location.fill", 0.56)),
    "tile-health":    tile("white", sf("heart.fill", 0.62, (255, 45, 85), transl=0.15)),
    # ── system row (shown at 26 pt) ───────────────────────────────────────────────────
    "tile-cpu":       tile("violet", sf("cpu.fill", 0.68)),
    "tile-memory":    tile("purple", sf("memorychip.fill", 0.72)),
    "tile-memfree":   tile("mint", sf("memorychip.fill", 0.72)),
    "tile-storage":   tile("grey", sf("internaldrive.fill", 0.72)),
    "tile-wifi":      tile("blue", sf("wifi", 0.66)),
    "tile-cellular":  tile("green", sf("antenna.radiowaves.left.and.right", 0.72)),
    "tile-offline":   tile("grey", sf("wifi.slash", 0.66)),
    "tile-battery":   tile("green", sf("battery.75percent", 0.72, WHITE, layer=0),
                           sf("battery.75percent", 0.72, WHITE, layer=1, transl=0.25)),
    "tile-lowpower":  tile("yellow", sf("bolt.fill", 0.56)),
    "tile-thermal":   tile("ember", sf("thermometer.medium", 0.64)),
    "tile-ip":        tile("sky", sf("globe", 0.68)),
    # ── round buttons (48 pt circles) ─────────────────────────────────────────────────
    "btn-gear":  tile("grey", sf("gearshape.fill", 0.62), pt=48, shape="circle"),
    "btn-play":  tile("orange", sf("play.fill", 0.46, dx=22), pt=48, shape="circle"),
    "btn-pause": tile("orange", sf("pause.fill", 0.42), pt=48, shape="circle"),
    "btn-stop":  tile("grey", sf("xmark", 0.40, weight="heavy"), pt=48, shape="circle"),
    # ── weather (44 pt) ──────────────────────────────────────────────────────────────
    "wx-sun":        weather("sun.max.fill", "sky", YELLOW, box=0.66),
    "wx-moon-stars": weather("moon.stars.fill", "navy", MOON, WHITE),
    "wx-moon":       weather("moon.fill", "navy", MOON, box=0.56),
    "wx-cloud-sun":  weather("cloud.sun.fill", "sky", WHITE, YELLOW),
    "wx-cloud-moon": weather("cloud.moon.fill", "navy", WHITE, MOON),
    "wx-cloud":      weather("cloud.fill", "cloud", WHITE, box=0.70),
    "wx-fog":        weather("cloud.fog.fill", "cloud", WHITE, WHITE),
    "wx-drizzle":    weather("cloud.drizzle.fill", "rain", WHITE, DROP),
    "wx-sleet":      weather("cloud.sleet.fill", "rain", WHITE, DROP),
    "wx-rain":       weather("cloud.rain.fill", "rain", WHITE, DROP),
    "wx-snow":       weather("cloud.snow.fill", "snow", WHITE, WHITE),
    "wx-heavyrain":  weather("cloud.heavyrain.fill", "storm", WHITE, DROP),
    "wx-bolt":       weather("cloud.bolt.fill", "storm", WHITE, YELLOW),
    "wx-bolt-rain":  weather("cloud.bolt.rain.fill", "storm", WHITE, DROP),
    "wx-unknown":    weather("questionmark", "cloud", WHITE, box=0.50),
}


def build(name, spec, tmp):
    pkg = f"{tmp}/{name}.icon"
    shutil.rmtree(pkg, ignore_errors=True)
    os.makedirs(f"{pkg}/Assets")
    groups = []
    for i, L in enumerate(spec["layers"]):
        if L["kind"] == "sf":
            fn = f"l{i}.png"
            args = [SYM, L["name"], f"{pkg}/Assets/{fn}", str(L["box"]), L["weight"]]
            if L["layer"] is not None:
                args.append(str(L["layer"]))
            r = subprocess.run(args, capture_output=True, text=True)
            if r.returncode != 0:
                raise SystemExit(f"{name}: {r.stdout.strip()} {r.stderr.strip()}")
        else:
            fn = f"l{i}.svg"
            shutil.copy(f"{SVG}/{L['name']}", f"{pkg}/Assets/{fn}")
        groups.append({
            "layers": [{"glass": L["glass"], "image-name": fn, "name": f"l{i}", "fill": {"solid": c(L["color"])},
                        "position": {"scale": SCALE, "translation-in-points": [L["dx"], L["dy"]]}}],
            "lighting": "individual",
            "shadow": {"kind": "neutral", "opacity": 0.5} if L["shadow"] else {"kind": "none", "opacity": 0.0},
            "translucency": {"enabled": L["transl"] > 0, "value": L["transl"]},
        })
    top, bottom = BG[spec["bg"]]
    doc = {"fill": {"linear-gradient": [c(top), c(bottom)]}, "groups": groups,
           "supported-platforms": {"squares": "shared", "circles": ["watchOS"]}}
    json.dump(doc, open(f"{pkg}/icon.json", "w"), indent=1)
    d = f"{OUT}/{name}.imageset"
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    png = f"{d}/{name}@3x.png"
    r = subprocess.run([ICTOOL, pkg, "--export-image", "--output-file", png,
                        "--platform", "watchOS" if spec["shape"] == "circle" else "iOS", "--rendition", "Default",
                        "--width", str(spec["pt"]), "--height", str(spec["pt"]), "--scale", "3", "--design-generation", "27"],
                       capture_output=True, text=True)
    if r.returncode != 0 or not os.path.exists(png):
        raise SystemExit(f"{name}: ictool failed {r.stdout.strip()} {r.stderr.strip()}")
    json.dump({"images": [{"filename": f"{name}@3x.png", "idiom": "universal", "scale": "3x"}],
               "info": {"author": "xcode", "version": 1}}, open(f"{d}/Contents.json", "w"), indent=2)


def main():
    os.makedirs(OUT, exist_ok=True)
    json.dump({"info": {"author": "xcode", "version": 1}}, open(f"{OUT}/Contents.json", "w"))
    wanted = sys.argv[1:] or list(TILES)
    unknown = [n for n in wanted if n not in TILES]
    if unknown:
        raise SystemExit(f"unknown assets: {unknown}")
    tmp = tempfile.mkdtemp()
    for n in wanted:
        build(n, TILES[n], tmp)
        print("rendered", n)
    if not sys.argv[1:]:
        for d in sorted(os.listdir(OUT)):
            if d.endswith(".imageset") and d[:-9] not in TILES:
                shutil.rmtree(f"{OUT}/{d}")
                print("pruned", d[:-9])
    print("done", len(wanted))


if __name__ == "__main__":
    main()
