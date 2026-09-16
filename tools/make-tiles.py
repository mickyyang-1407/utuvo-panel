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
# round glass buttons (rendered on the watchOS "circles" platform) — gear, play, pause, stop
circles=[("btn-gear","gearshape.fill","8E8E93"),("btn-play","play.fill","FF9F0A"),("btn-pause","pause.fill","FF9F0A"),("btn-stop","xmark","8E8E93")]
# weather condition tiles: one per SF symbol used by WeatherSnapshot.description, day = sky blue, night = navy
day="3A8DFF"; night="1C2A4A"
weather=[("wx-sun","sun.max.fill",day),("wx-moon-stars","moon.stars.fill",night),("wx-moon","moon.fill",night),
         ("wx-cloud-sun","cloud.sun.fill",day),("wx-cloud-moon","cloud.moon.fill",night),("wx-cloud","cloud.fill","6E7A8A"),
         ("wx-fog","cloud.fog.fill","6E7A8A"),("wx-drizzle","cloud.drizzle.fill","4A7BB5"),("wx-sleet","cloud.sleet.fill","4A7BB5"),
         ("wx-rain","cloud.rain.fill","2F6BB0"),("wx-snow","cloud.snow.fill","7FA6D9"),("wx-heavyrain","cloud.heavyrain.fill","24528C"),
         ("wx-bolt","cloud.bolt.fill","3D3F8F"),("wx-bolt-rain","cloud.bolt.rain.fill","3D3F8F"),("wx-unknown","questionmark","6E7A8A")]
POINTS=52; SCALE=3
out=f"{ROOT}/ios/Shared/Tiles.xcassets"; shutil.rmtree(out,ignore_errors=True); os.makedirs(out)
json.dump({"info":{"author":"xcode","version":1}},open(f"{out}/Contents.json","w"))
tmp=tempfile.mkdtemp()
def render(id_,symbol,hexc,platform,points):
    r,g,b=[int(hexc[i:i+2],16)/255 for i in (0,2,4)]
    pkg=f"{tmp}/{id_}.icon"; shutil.rmtree(pkg,ignore_errors=True); os.makedirs(f"{pkg}/Assets")
    subprocess.check_output([SYM2PNG,symbol,f"{pkg}/Assets/glyph.png","560","medium"])
    doc={"fill-specializations":[{"value":{"automatic-gradient":f"extended-srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"}}],
         "groups":[{"layers":[{"glass":True,"image-name":"glyph.png","name":"glyph",
                               "position":{"scale":1.0,"translation-in-points":[0,0]}}],
                    "lighting":"individual","shadow":{"kind":"neutral","opacity":0.5},
                    "translucency":{"enabled":True,"value":0.5}}],
         "supported-platforms":{"squares":"shared","circles":["watchOS"]}}
    json.dump(doc,open(f"{pkg}/icon.json","w"))
    name=id_ if id_.startswith(("btn-","wx-")) else f"tile-{id_}"
    d=f"{out}/{name}.imageset"; os.makedirs(d)
    png=f"{d}/{name}@3x.png"
    subprocess.check_call([ICTOOL,pkg,"--export-image","--output-file",png,"--platform",platform,"--rendition","Default",
                           "--width",str(points),"--height",str(points),"--scale",str(SCALE),"--design-generation","27"],
                          stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    json.dump({"images":[{"filename":f"{name}@3x.png","idiom":"universal","scale":"3x"}],
               "info":{"author":"xcode","version":1}},open(f"{d}/Contents.json","w"),indent=2)
    print(name,symbol,hexc, os.path.getsize(png))
for id_,symbol,hexc in tiles: render(id_,symbol,hexc,"iOS",POINTS)
for id_,symbol,hexc in circles: render(id_,symbol,hexc,"watchOS",48)
for id_,symbol,hexc in weather: render(id_,symbol,hexc,"iOS",44)
print("done", len(tiles)+len(circles)+len(weather))
