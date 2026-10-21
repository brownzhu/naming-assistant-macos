#!/usr/bin/env swift
// Draws Quick Rename's app icon programmatically (squircle + gradient + "Aa"
// with a curved arrow) and emits an AppIcon.icns at the requested path.
// Run via: swift scripts/generate-icon.swift Resources/AppIcon.icns

import Foundation
import AppKit
import CoreText

func drawIcon(size: CGFloat) -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil, width: Int(size), height: Int(size),
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    // Apple-style squircle (continuous corner rounding approximation).
    let inset = size * 0.07
    let corner = size * 0.225
    let squircle = CGPath(
        roundedRect: rect.insetBy(dx: inset, dy: inset),
        cornerWidth: corner, cornerHeight: corner, transform: nil
    )

    // Background gradient: deep indigo → violet, top-left to bottom-right.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let colors = [
        CGColor(red: 0.27, green: 0.33, blue: 0.90, alpha: 1), // #4553E6
        CGColor(red: 0.62, green: 0.28, blue: 0.86, alpha: 1), // #9E47DB
    ] as CFArray
    let gradient = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: size, y: 0),
        options: []
    )
    ctx.restoreGState()

    // Inner highlight ring for depth.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
    ctx.setLineWidth(size * 0.01)
    ctx.strokePath()
    ctx.restoreGState()

    // "Aa" glyph, large and centered, white with a slight shadow.
    let text = "Ab"
    let fontSize = size * 0.52
    let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
    ]
    let attr = NSAttributedString(string: text, attributes: attrs)
    let line = CTLineCreateWithAttributedString(attr)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    let tx = (size - bounds.width) / 2 - bounds.minX
    let ty = (size - bounds.height) / 2 - bounds.minY + size * 0.06

    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -size * 0.01),
        blur: size * 0.02,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35)
    )
    ctx.textPosition = CGPoint(x: tx, y: ty)
    CTLineDraw(line, ctx)
    ctx.restoreGState()

    // Curved transformation arrow underneath the glyph. Pushed further down so
    // the arrowhead doesn't collide with descenders/baseline of "Ab".
    ctx.saveGState()
    let arrowY = ty - size * 0.09
    let arrowLeft = size * 0.30
    let arrowRight = size * 0.70
    let arrowDip = size * 0.07
    let path = CGMutablePath()
    path.move(to: CGPoint(x: arrowLeft, y: arrowY))
    path.addQuadCurve(
        to: CGPoint(x: arrowRight, y: arrowY),
        control: CGPoint(x: size / 2, y: arrowY - arrowDip)
    )
    ctx.addPath(path)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.setLineWidth(size * 0.035)
    ctx.setLineCap(.round)
    ctx.strokePath()

    // Arrowhead aligned with the curve tangent at its right endpoint.
    // Tangent of a quadratic Bézier at t=1 is (P2 − P1), so the angle the
    // curve is heading at this point is atan2(arrowDip, arrowRight − size/2).
    let hx = arrowRight, hy = arrowY
    let hs = size * 0.05
    let tangentAngle = atan2(arrowDip, arrowRight - size / 2)
    ctx.translateBy(x: hx, y: hy)
    ctx.rotate(by: tangentAngle)
    let head = CGMutablePath()
    head.move(to: .zero)
    head.addLine(to: CGPoint(x: -hs, y: hs * 0.7))
    head.move(to: .zero)
    head.addLine(to: CGPoint(x: -hs, y: -hs * 0.7))
    ctx.addPath(head)
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 1)
    }
    try data.write(to: url)
}

// MARK: - Entry

guard CommandLine.arguments.count > 1 else {
    print("usage: generate-icon.swift <output.icns>")
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(
    at: output.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

let work = FileManager.default.temporaryDirectory
    .appendingPathComponent("macrename-icon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: work) }

// macOS expects these exact iconset filenames.
let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),     ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),     ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),  ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),  ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),  ("icon_512x512@2x.png", 1024),
]

for entry in sizes {
    let img = drawIcon(size: CGFloat(entry.pixels))
    try writePNG(img, to: work.appendingPathComponent(entry.name))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", work.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    throw NSError(domain: "icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
}
print("Wrote \(output.path)")
