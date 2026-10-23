#!/usr/bin/env bash
# Draws the 1024px app icon used to build AppIcon.icns.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/Resources/AppIcon-1024.png}"

cat > "${TMPDIR:-/tmp}/dexmac-icon.swift" <<'SWIFT'
import AppKit

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

let S: CGFloat = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(S),
    pixelsHigh: Int(S),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Could not allocate bitmap")
}
rep.size = NSSize(width: S, height: S)
guard let graphics = NSGraphicsContext(bitmapImageRep: rep) else {
    fatalError("No graphics context")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
let ctx = graphics.cgContext
ctx.setShouldAntialias(true)

// Rounded body with a soft shadow, inset like a standard macOS icon.
let inset: CGFloat = 84
let bodyRect = NSRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
let body = NSBezierPath(roundedRect: bodyRect, xRadius: 196, yRadius: 196)

ctx.saveGState()
ctx.setShadow(
    offset: CGSize(width: 0, height: -16),
    blur: 36,
    color: NSColor.black.withAlphaComponent(0.32).cgColor
)
let background = NSGradient(
    colors: [color(0.15, 0.20, 0.66), color(0.20, 0.45, 0.95), color(0.34, 0.74, 0.99)],
    atLocations: [0.0, 0.55, 1.0],
    colorSpace: .sRGB
)!
background.draw(in: body, angle: -58)
ctx.restoreGState()

color(1, 1, 1, 0.16).setStroke()
body.lineWidth = 3
body.stroke()

// Monitor bezel
let bezelRect = NSRect(x: 214, y: 344, width: 566, height: 372)
let bezel = NSBezierPath(roundedRect: bezelRect, xRadius: 34, yRadius: 34)
ctx.saveGState()
ctx.setShadow(
    offset: CGSize(width: 0, height: -10),
    blur: 24,
    color: NSColor.black.withAlphaComponent(0.28).cgColor
)
color(1, 1, 1, 0.97).setFill()
bezel.fill()
ctx.restoreGState()

// Screen
let screenRect = NSRect(x: 234, y: 363, width: 526, height: 334)
let screen = NSBezierPath(roundedRect: screenRect, xRadius: 22, yRadius: 22)
let screenGradient = NSGradient(colors: [color(0.05, 0.07, 0.18), color(0.10, 0.16, 0.38)])!
screenGradient.draw(in: screen, angle: -90)

// Desktop windows
func window(_ rect: NSRect, alpha: CGFloat, radius: CGFloat) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    color(1, 1, 1, alpha).setFill()
    path.fill()
}

window(NSRect(x: 262, y: 462, width: 258, height: 170), alpha: 0.20, radius: 14)
window(NSRect(x: 432, y: 408, width: 204, height: 132), alpha: 0.13, radius: 12)

// Window title dots
for (index, x) in [280.0, 298.0, 316.0].enumerated() {
    let dot = NSBezierPath(ovalIn: NSRect(x: x, y: 604, width: 10, height: 10))
    color(1, 1, 1, index == 0 ? 0.75 : 0.5).setFill()
    dot.fill()
}

// Taskbar
let taskbar = NSBezierPath(
    roundedRect: NSRect(x: 250, y: 378, width: 494, height: 34),
    xRadius: 12,
    yRadius: 12
)
color(1, 1, 1, 0.20).setFill()
taskbar.fill()

for x in stride(from: 268.0, through: 340.0, by: 24.0) {
    let icon = NSBezierPath(roundedRect: NSRect(x: x, y: 388, width: 14, height: 14), xRadius: 4, yRadius: 4)
    color(0.55, 0.80, 1.0, 0.9).setFill()
    icon.fill()
}

// Phone in front, bottom right
let phoneRect = NSRect(x: 690, y: 196, width: 152, height: 306)
let phone = NSBezierPath(roundedRect: phoneRect, xRadius: 38, yRadius: 38)
ctx.saveGState()
ctx.setShadow(
    offset: CGSize(width: 0, height: -8),
    blur: 26,
    color: NSColor.black.withAlphaComponent(0.35).cgColor
)
color(1, 1, 1, 0.98).setFill()
phone.fill()
ctx.restoreGState()

let phoneScreen = NSBezierPath(
    roundedRect: phoneRect.insetBy(dx: 9, dy: 9),
    xRadius: 31,
    yRadius: 31
)
let phoneGradient = NSGradient(colors: [color(0.07, 0.10, 0.24), color(0.13, 0.27, 0.60)])!
phoneGradient.draw(in: phoneScreen, angle: -90)

// Glowing desktop glyph on the phone
let glow = NSBezierPath(ovalIn: NSRect(x: phoneRect.midX - 32, y: phoneRect.midY - 24, width: 64, height: 64))
color(0.35, 0.72, 1.0, 0.20).setFill()
glow.fill()

let glyph = NSBezierPath(
    roundedRect: NSRect(x: phoneRect.midX - 21, y: phoneRect.midY - 14, width: 42, height: 28),
    xRadius: 6,
    yRadius: 6
)
color(0.55, 0.84, 1.0, 1.0).setFill()
glyph.fill()

let homeBar = NSBezierPath(
    roundedRect: NSRect(x: phoneRect.midX - 26, y: phoneRect.minY + 22, width: 52, height: 6),
    xRadius: 3,
    yRadius: 3
)
color(1, 1, 1, 0.75).setFill()
homeBar.fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode icon")
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
try png.write(to: url)
print("Wrote \(url.path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
SWIFT

swift "${TMPDIR:-/tmp}/dexmac-icon.swift" "$OUT"
