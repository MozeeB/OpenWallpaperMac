#!/usr/bin/env swift
// Generates App/Assets.xcassets/AppIcon.appiconset from code (original artwork, MIT).
// Usage: swift scripts/make-icon.swift
import AppKit
import CoreGraphics

let output = URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func drawIcon(size: Int) -> Data {
    let s = CGFloat(size)
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let inset = s * 0.09
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = CGPath(roundedRect: rect, cornerWidth: s * 0.19, cornerHeight: s * 0.19, transform: nil)
    context.addPath(path)
    context.clip()
    let sky = CGGradient(colorsSpace: nil, colors: [
        CGColor(red: 0.10, green: 0.07, blue: 0.30, alpha: 1), CGColor(red: 0.55, green: 0.20, blue: 0.75, alpha: 1),
        CGColor(red: 1.00, green: 0.55, blue: 0.45, alpha: 1),
    ] as CFArray, locations: [0, 0.6, 1])!
    context.drawLinearGradient(sky, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
    // Sun
    context.setFillColor(CGColor(red: 1, green: 0.85, blue: 0.55, alpha: 0.95))
    let sun = s * 0.16
    context.fillEllipse(in: CGRect(x: s * 0.5 - sun, y: s * 0.42, width: sun * 2, height: sun * 2))
    // Waves (three layered sine bands)
    let colors = [(0.20, 0.30, 0.80), (0.12, 0.20, 0.60), (0.06, 0.10, 0.35)]
    for (index, color) in colors.enumerated() {
        let base = rect.minY + rect.height * (0.42 - CGFloat(index) * 0.12)
        let wave = CGMutablePath()
        wave.move(to: CGPoint(x: rect.minX, y: rect.minY))
        for step in 0 ... 60 {
            let x = rect.minX + rect.width * CGFloat(step) / 60
            let y = base + sin(CGFloat(step) / 60 * .pi * 2 + CGFloat(index)) * s * 0.03
            wave.addLine(to: CGPoint(x: x, y: y))
        }
        wave.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        wave.closeSubpath()
        context.addPath(wave)
        context.setFillColor(CGColor(red: color.0, green: color.1, blue: color.2, alpha: 1))
        context.fillPath()
    }
    let image = context.makeImage()!
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try drawIcon(size: pixels).write(to: output.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(base)x\(base)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
try Data(#"{"info":{"version":1,"author":"xcode"}}"#.utf8)
    .write(to: output.deletingLastPathComponent().appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icon images to \(output.path)")
