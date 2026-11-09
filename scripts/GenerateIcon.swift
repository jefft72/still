import AppKit
import Foundation

// The icon is drawn from geometry so every packaged size is rendered crisply.
let arguments = CommandLine.arguments
guard arguments.count == 2 else {
  fputs("Usage: swift scripts/GenerateIcon.swift <output.iconset>\n", stderr)
  exit(1)
}

let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
  NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

func circle(_ center: CGPoint, radius: CGFloat) -> NSBezierPath {
  NSBezierPath(
    ovalIn: CGRect(
      x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
}

func drawIcon(pixels: Int) throws -> Data {
  guard
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: pixels,
      pixelsHigh: pixels,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap)
  else {
    throw CocoaError(.fileWriteUnknown)
  }

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = graphics
  defer { NSGraphicsContext.restoreGraphicsState() }
  let context = graphics.cgContext
  let scale = CGFloat(pixels) / 1024
  context.scaleBy(x: scale, y: scale)
  context.setAllowsAntialiasing(true)

  let body = NSBezierPath(
    roundedRect: CGRect(x: 96, y: 96, width: 832, height: 832),
    xRadius: 188,
    yRadius: 188
  )
  color(0.965, 0.953, 0.925).setFill()
  body.fill()

  // Two quiet strokes and one active point. No texture, lighting, or ornament.
  color(0.145, 0.149, 0.141).setFill()
  for x: CGFloat in [360, 552] {
    NSBezierPath(
      roundedRect: CGRect(x: x, y: 282, width: 112, height: 380),
      xRadius: 17,
      yRadius: 17
    ).fill()
  }
  color(0.89, 0.33, 0.16).setFill()
  circle(CGPoint(x: 608, y: 740), radius: 30).fill()

  guard let png = bitmap.representation(using: .png, properties: [:]) else {
    throw CocoaError(.fileWriteUnknown)
  }
  return png
}

for size in [16, 32, 128, 256, 512] {
  for multiplier in [1, 2] {
    let suffix = multiplier == 2 ? "@2x" : ""
    let filename = "icon_\(size)x\(size)\(suffix).png"
    try drawIcon(pixels: size * multiplier).write(to: output.appendingPathComponent(filename))
  }
}
