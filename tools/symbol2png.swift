// Render an SF Symbol as a white glyph on transparent, 1024×1024, centred — a layer for Icon Composer.
// usage: swift symbol2png.swift <symbol.name> <out.png> [pointSize=560] [weight=semibold]
import AppKit
let a = CommandLine.arguments
guard a.count >= 3 else { print("usage: symbol2png <symbol> <out.png> [size] [weight]"); exit(2) }
let size = a.count > 3 ? Double(a[3])! : 560
let weights: [String: NSFont.Weight] = ["regular": .regular, "medium": .medium, "semibold": .semibold, "bold": .bold]
let weight = a.count > 4 ? weights[a[4]] ?? .semibold : .semibold
guard let base = NSImage(systemSymbolName: a[1], accessibilityDescription: nil) else { print("no symbol \(a[1])"); exit(1) }
let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: weight).applying(.init(paletteColors: [.white]))
let img = base.withSymbolConfiguration(cfg)!
let canvas = NSImage(size: NSSize(width: 1024, height: 1024))
canvas.lockFocus()
let r = img.size
let scale = min(600 / r.width, 600 / r.height)   // glyph ≈ 49% of the canvas, like Apple's own icons
let w = r.width * scale, h = r.height * scale
img.draw(in: NSRect(x: (1024 - w) / 2, y: (1024 - h) / 2, width: w, height: h), from: .zero, operation: .sourceOver, fraction: 1)
canvas.unlockFocus()
let tiff = canvas.tiffRepresentation!, rep = NSBitmapImageRep(data: tiff)!
rep.size = NSSize(width: 1024, height: 1024)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
print("ok \(a[1]) \(Int(w))x\(Int(h))")
