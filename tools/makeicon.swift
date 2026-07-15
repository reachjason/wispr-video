import AppKit

// Renders a 1024×1024 app icon PNG: purple→pink gradient rounded square
// with a white video-camera glyph. Output path is argv[1].

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "icon_1024.png"

let px = 1024

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: px, pixelsHigh: px,
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
let gctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gctx
let ctx = gctx.cgContext

let size = CGFloat(px)
let rect = NSRect(x: 0, y: 0, width: size, height: size)
let radius = size * 0.2237

let clip = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
clip.addClip()

let colors = [
    NSColor(srgbRed: 0.42, green: 0.28, blue: 0.96, alpha: 1).cgColor,
    NSColor(srgbRed: 0.93, green: 0.30, blue: 0.60, alpha: 1).cgColor,
]
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: colors as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 0, y: size),
                       end: CGPoint(x: size, y: 0),
                       options: [])

// White video-camera glyph, centered.
let config = NSImage.SymbolConfiguration(pointSize: size * 0.44, weight: .semibold)
if let symbol = NSImage(systemSymbolName: "video.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {

    let s = symbol.size
    let white = NSImage(size: s)
    white.lockFocus()
    symbol.draw(in: NSRect(origin: .zero, size: s))
    NSColor.white.set()
    NSRect(origin: .zero, size: s).fill(using: .sourceAtop)
    white.unlockFocus()

    let r = NSRect(x: (size - s.width) / 2,
                   y: (size - s.height) / 2,
                   width: s.width, height: s.height)
    white.draw(in: r)
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("Failed to encode PNG\n".data(using: .utf8)!)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("Wrote \(outPath)")
