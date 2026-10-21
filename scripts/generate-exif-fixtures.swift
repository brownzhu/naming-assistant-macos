#!/usr/bin/env swift
// Generates tiny JPEG fixtures with known EXIF/TIFF metadata for CLI integration
// tests. Run via `swift scripts/generate-exif-fixtures.swift Tests/Fixtures/images`.
// Fixtures are committed — re-run only when intentionally changing metadata.

import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

func makeJPEG(
    at url: URL,
    make: String,
    model: String,
    iso: Int,
    dateOriginal: String
) throws {
    let w = 4, h = 4
    let pixels = [UInt8](repeating: 180, count: w * h * 4)
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    let cs = CGColorSpaceCreateDeviceRGB()
    let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard let img = CGImage(
        width: w, height: h,
        bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: w * 4, space: cs, bitmapInfo: info,
        provider: provider, decode: nil,
        shouldInterpolate: false, intent: .defaultIntent
    ) else { throw NSError(domain: "fixtures", code: 1) }

    let tiff: [String: Any] = [
        kCGImagePropertyTIFFMake as String: make,
        kCGImagePropertyTIFFModel as String: model,
    ]
    let exif: [String: Any] = [
        kCGImagePropertyExifISOSpeedRatings as String: [iso],
        kCGImagePropertyExifDateTimeOriginal as String: dateOriginal,
    ]
    let metadata: [String: Any] = [
        kCGImagePropertyTIFFDictionary as String: tiff,
        kCGImagePropertyExifDictionary as String: exif,
    ]

    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
    ) else { throw NSError(domain: "fixtures", code: 2) }
    CGImageDestinationAddImage(dest, img, metadata as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "fixtures", code: 3)
    }
}

guard CommandLine.arguments.count > 1 else {
    print("usage: generate-exif-fixtures.swift <output-dir>")
    exit(2)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

try makeJPEG(
    at: outDir.appendingPathComponent("IMG_0001.jpg"),
    make: "Canon", model: "EOS 5D", iso: 400,
    dateOriginal: "2024:03:15 10:30:00"
)
try makeJPEG(
    at: outDir.appendingPathComponent("IMG_0002.jpg"),
    make: "Nikon", model: "D850", iso: 800,
    dateOriginal: "2023:11:22 14:45:20"
)
print("Wrote EXIF fixtures to \(outDir.path)")
