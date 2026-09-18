// Render an SF Symbol (or one of its palette layers) as a white glyph on transparent 1024×1024 —
// an image layer for Icon Composer. Every layer of a symbol is scaled from the full symbol's bounds,
// so layers rendered separately line up exactly.
// usage: symbol2png <symbol> <out.png> <box 0..1> <weight> [layer index | all]
import AppKit
let a = CommandLine.arguments
guard a.count >= 5 else { print("usage: symbol2png <symbol> <out.png> <box> <weight> [layer|all]"); exit(2) }
let name = a[1], out = a[2], box = Double(a[3])!, layer = a.count > 5 ? a[5] : "all"
let weights: [String: NSFont.Weight] = ["regular": .regular, "medium": .medium, "semibold": .semibold, "bold": .bold, "heavy": .heavy, "black": .black]
let weight = weights[a[4]] ?? .bold
guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { print("no symbol \(name)"); exit(1) }
let sizing = NSImage.SymbolConfiguration(pointSize: 512, weight: weight)
var colors = [NSColor](repeating: layer == "all" ? .white : .clear, count: 4)
if let k = Int(layer) { colors[k] = .white }
let img = base.withSymbolConfiguration(sizing.applying(.init(paletteColors: colors)))!
let full = base.withSymbolConfiguration(sizing)!.size
let s = min(1024 * box / full.width, 1024 * box / full.height)
let w = full.width * s, h = full.height * s
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: 1024, height: 1024)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
img.draw(in: NSRect(x: (1024 - w) / 2, y: (1024 - h) / 2, width: w, height: h))
NSGraphicsContext.restoreGraphicsState()
var any = false
for y in stride(from: 0, to: 1024, by: 4) { for x in stride(from: 0, to: 1024, by: 4) where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 { any = true; break }; if any { break } }
if !any { print("empty \(name) layer \(layer)"); exit(3) }
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("ok \(name) layer \(layer) \(Int(w))x\(Int(h))")
