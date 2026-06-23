// One-off placeholder icon generator for Copera Currency (Phase 0).
// Renders a 1024x1024 rounded-square terracotta (#D97757) background with a
// centered white "$". Run: `xcrun swift scripts/generate_icon.swift <out.png>`
//
// This is a throwaway placeholder; the real Copera icon replaces it later.

import AppKit
import CoreGraphics
import Foundation

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "icon_1024.png"

let size = 1024
let scale = CGFloat(size)

guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(
          data: nil,
          width: size,
          height: size,
          bitsPerComponent: 8,
          bytesPerRow: 0,
          space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
else {
    FileHandle.standardError.write(Data("Failed to create CGContext\n".utf8))
    exit(1)
}

// Transparent background.
ctx.clear(CGRect(x: 0, y: 0, width: scale, height: scale))

// Rounded-square terracotta tile. macOS app icons typically inset slightly and
// round corners ~18% of the side for a modern squircle-ish look.
let inset: CGFloat = scale * 0.06
let tileRect = CGRect(x: inset, y: inset, width: scale - inset * 2, height: scale - inset * 2)
let corner = tileRect.width * 0.225
let tilePath = CGPath(roundedRect: tileRect, cornerWidth: corner, cornerHeight: corner, transform: nil)

// #D97757
let terracotta = CGColor(srgbRed: 0xD9 / 255.0, green: 0x77 / 255.0, blue: 0x57 / 255.0, alpha: 1.0)
ctx.addPath(tilePath)
ctx.setFillColor(terracotta)
ctx.fillPath()

// Centered white "$".
let nsContext = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.current = nsContext

let glyph = "$"
let font = NSFont.systemFont(ofSize: scale * 0.62, weight: .bold)
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
]
let attributed = NSAttributedString(string: glyph, attributes: attrs)
let textSize = attributed.size()
let textRect = CGRect(
    x: (scale - textSize.width) / 2,
    y: (scale - textSize.height) / 2,
    width: textSize.width,
    height: textSize.height
)
attributed.draw(in: textRect)
NSGraphicsContext.current = nil

guard let image = ctx.makeImage() else {
    FileHandle.standardError.write(Data("Failed to make image\n".utf8))
    exit(1)
}

let rep = NSBitmapImageRep(cgImage: image)
guard let pngData = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("Failed to encode PNG\n".utf8))
    exit(1)
}

do {
    try pngData.write(to: URL(fileURLWithPath: outPath))
    print("Wrote \(outPath) (\(size)x\(size))")
} catch {
    FileHandle.standardError.write(Data("Write failed: \(error)\n".utf8))
    exit(1)
}
