#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS_DIR="$ROOT_DIR/assets"
ICONSET_DIR="$ASSETS_DIR/AppIcon.iconset"
MASTER_PNG="$ASSETS_DIR/AppIcon-1024.png"
ICNS_FILE="$ASSETS_DIR/AppIcon.icns"
SVG_FILE="$ASSETS_DIR/AppIcon.svg"

mkdir -p "$ASSETS_DIR"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

SWIFT_FILE="$(mktemp /tmp/dubbingeditor-icon.XXXXXX)"
trap 'rm -f "$SWIFT_FILE"' EXIT

cat > "$SWIFT_FILE" <<'SWIFT'
import AppKit
import Foundation

extension NSColor {
    convenience init(hex: Int, alpha: CGFloat = 1.0) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        self.init(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}

func savePNG(size: Int, to outputPath: String) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "IconBuild", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create bitmap"])
    }

    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        NSGraphicsContext.restoreGraphicsState()
        throw NSError(domain: "IconBuild", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot create graphics context"])
    }
    NSGraphicsContext.current = ctx

    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    canvas.fill()

    let scale = CGFloat(size) / 1024.0
    let inset = 56.0 * scale
    let bgRect = NSRect(
        x: inset,
        y: inset,
        width: CGFloat(size) - (inset * 2),
        height: CGFloat(size) - (inset * 2)
    )

    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 210.0 * scale, yRadius: 210.0 * scale)
    let gradient = NSGradient(colors: [NSColor(hex: 0x111318), NSColor(hex: 0x1A1E26)])
    gradient?.draw(in: bgPath, angle: -90)

    let cardRect = NSRect(
        x: CGFloat(size) * 0.17,
        y: CGFloat(size) * 0.42,
        width: CGFloat(size) * 0.66,
        height: CGFloat(size) * 0.30
    )
    let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: 92.0 * scale, yRadius: 92.0 * scale)
    NSColor.white.withAlphaComponent(0.97).setFill()
    cardPath.fill()

    let cardShadow = NSShadow()
    cardShadow.shadowBlurRadius = 18 * scale
    cardShadow.shadowOffset = NSSize(width: 0, height: -5 * scale)
    cardShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    NSGraphicsContext.saveGraphicsState()
    cardShadow.set()
    cardPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    let lineColor = NSColor(hex: 0x202532)
    let textLine1 = NSBezierPath(roundedRect: NSRect(
        x: cardRect.minX + 55 * scale,
        y: cardRect.midY + 24 * scale,
        width: 260 * scale,
        height: 28 * scale
    ), xRadius: 12 * scale, yRadius: 12 * scale)
    lineColor.setFill()
    textLine1.fill()

    let textLine2 = NSBezierPath(roundedRect: NSRect(
        x: cardRect.minX + 55 * scale,
        y: cardRect.midY - 24 * scale,
        width: 195 * scale,
        height: 28 * scale
    ), xRadius: 12 * scale, yRadius: 12 * scale)
    lineColor.setFill()
    textLine2.fill()

    let playCircleRect = NSRect(
        x: cardRect.maxX - 170 * scale,
        y: cardRect.midY - 60 * scale,
        width: 120 * scale,
        height: 120 * scale
    )
    let playCircle = NSBezierPath(ovalIn: playCircleRect)
    NSColor(hex: 0x242A37).setFill()
    playCircle.fill()

    let tri = NSBezierPath()
    tri.move(to: NSPoint(x: playCircleRect.minX + 46 * scale, y: playCircleRect.minY + 34 * scale))
    tri.line(to: NSPoint(x: playCircleRect.maxX - 38 * scale, y: playCircleRect.midY))
    tri.line(to: NSPoint(x: playCircleRect.minX + 46 * scale, y: playCircleRect.maxY - 34 * scale))
    tri.close()
    NSColor.white.setFill()
    tri.fill()

    let wave = NSBezierPath()
    wave.lineWidth = 24 * scale
    wave.lineCapStyle = .round
    wave.lineJoinStyle = .round
    wave.move(to: NSPoint(x: CGFloat(size) * 0.20, y: CGFloat(size) * 0.30))
    wave.line(to: NSPoint(x: CGFloat(size) * 0.30, y: CGFloat(size) * 0.30))
    wave.line(to: NSPoint(x: CGFloat(size) * 0.35, y: CGFloat(size) * 0.36))
    wave.line(to: NSPoint(x: CGFloat(size) * 0.42, y: CGFloat(size) * 0.23))
    wave.line(to: NSPoint(x: CGFloat(size) * 0.49, y: CGFloat(size) * 0.37))
    wave.line(to: NSPoint(x: CGFloat(size) * 0.56, y: CGFloat(size) * 0.24))
    wave.line(to: NSPoint(x: CGFloat(size) * 0.63, y: CGFloat(size) * 0.34))
    wave.line(to: NSPoint(x: CGFloat(size) * 0.72, y: CGFloat(size) * 0.30))
    NSColor(hex: 0xFF8A3D).setStroke()
    wave.stroke()

    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconBuild", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot encode PNG"])
    }
    try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Missing output path\n", stderr)
    exit(2)
}

do {
    try savePNG(size: 1024, to: args[1])
} catch {
    fputs("Icon generation failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
SWIFT

swift "$SWIFT_FILE" "$MASTER_PNG"

while read -r size name; do
    sips -s format png -z "$size" "$size" "$MASTER_PNG" --out "$ICONSET_DIR/$name" >/dev/null
done <<'SIZES'
16 icon_16x16.png
32 icon_16x16@2x.png
32 icon_32x32.png
64 icon_32x32@2x.png
128 icon_128x128.png
256 icon_128x128@2x.png
256 icon_256x256.png
512 icon_256x256@2x.png
512 icon_512x512.png
1024 icon_512x512@2x.png
SIZES

iconutil -c icns "$ICONSET_DIR" -o "$ICNS_FILE"

cat > "$SVG_FILE" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#111318"/>
      <stop offset="100%" stop-color="#1A1E26"/>
    </linearGradient>
  </defs>
  <rect x="56" y="56" width="912" height="912" rx="190" fill="url(#bg)"/>
  <rect x="174" y="430" width="676" height="306" rx="92" fill="#FFFFFF" fill-opacity="0.97"/>
  <rect x="230" y="524" width="260" height="28" rx="12" fill="#202532"/>
  <rect x="230" y="468" width="195" height="28" rx="12" fill="#202532"/>
  <circle cx="740" cy="583" r="60" fill="#242A37"/>
  <path d="M716 549 L766 583 L716 617 Z" fill="#FFFFFF"/>
  <path d="M205 308 L307 308 L358 366 L432 240 L503 378 L574 246 L645 340 L736 308"
        fill="none" stroke="#FF8A3D" stroke-width="24" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
SVG

echo "Built icon assets:"
echo "  $MASTER_PNG"
echo "  $SVG_FILE"
echo "  $ICONSET_DIR"
echo "  $ICNS_FILE"
