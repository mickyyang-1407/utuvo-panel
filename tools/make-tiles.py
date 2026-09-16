#!/usr/bin/env python3
"""Render every launcher tile as a miniature Liquid Glass app icon with Apple's own renderer (ictool).
   Reads Launcher.presets from Shared/Logic.swift, writes Shared/Tiles.xcassets/tile-<id>.imageset (3x)."""
import json, os, re, shutil, subprocess, sys, tempfile
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICTOOL="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
SYM2PNG="/tmp/symbol2png"
if not os.path.exists(SYM2PNG):
    subprocess.check_call(["swiftc","-O",f"{ROOT}/tools/symbol2png.swift","-o",SYM2PNG])
logic=open(f"{ROOT}/ios/Shared/Logic.swift").read()
presets=re.findall(r'Launcher\(id: "([^"]+)",\s*name: "[^"]*",\s*symbol: "([^"]+)",\s*colorHex: 0x([0-9A-Fa-f]{6}),', logic)
extra=[("note","leaf.fill","2E7D32"),("gear","gearshape.fill","8E8E93"),
       # settings-screen row icons
       ("activity","figure.run","FF375F"),("timer","timer","FF9F0A"),("grid","square.grid.2x2.fill","5856D6"),
       ("location","location.fill","007AFF"),("health","heart.fill","FF2D55"),("wallpaper","photo.fill","30B0C7"),
       ("seconds","clock.fill","1C1C1E"),("text","text.quote","FF9500"),("modules","slider.horizontal.3","8E8E93"),("home","apps.iphone","34C759")]
tiles=[(i,s,c) for i,s,c in presets]+extra
POINTS=52; SCALE=3
out=f"{ROOT}/ios/Shared/Tiles.xcassets"; shutil.rmtree(out,ignore_errors=True); os.makedirs(out)
json.dump({"info":{"author":"xcode","version":1}},open(f"{out}/Contents.json","w"))
tmp=tempfile.mkdtemp()
for id_,symbol,hexc in tiles:
    r,g,b=[int(hexc[i:i+2],16)/255 for i in (0,2,4)]
    pkg=f"{tmp}/{id_}.icon"; os.makedirs(f"{pkg}/Assets")
    subprocess.check_output([SYM2PNG,symbol,f"{pkg}/Assets/glyph.png","560","medium"])
    doc={"fill-specializations":[{"value":{"automatic-gradient":f"extended-srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"}}],
         "groups":[{"layers":[{"glass":True,"image-name":"glyph.png","name":"glyph",
                               "position":{"scale":1.0,"translation-in-points":[0,0]}}],
                    "lighting":"individual","shadow":{"kind":"neutral","opacity":0.5},
                    "translucency":{"enabled":True,"value":0.5}}],
         "supported-platforms":{"squares":"shared"}}
    json.dump(doc,open(f"{pkg}/icon.json","w"))
    d=f"{out}/tile-{id_}.imageset"; os.makedirs(d)
    png=f"{d}/tile-{id_}@3x.png"
    subprocess.check_call([ICTOOL,pkg,"--export-image","--output-file",png,"--platform","iOS","--rendition","Default",
                           "--width",str(POINTS),"--height",str(POINTS),"--scale",str(SCALE),"--design-generation","27"],
                          stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    json.dump({"images":[{"filename":f"tile-{id_}@3x.png","idiom":"universal","scale":"3x"}],
               "info":{"author":"xcode","version":1}},open(f"{d}/Contents.json","w"),indent=2)
    print("tile",id_,symbol,hexc, os.path.getsize(png))
print("done", len(tiles))
