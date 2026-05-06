#!/usr/bin/env swift

// Renders the Jubako app icon at every size required for the macOS
// AppIcon asset catalog. Run with:
//
//   swift Tools/generate-icon.swift
//
// Outputs PNG files and Contents.json to
// Resources/Assets.xcassets/AppIcon.appiconset/.

import AppKit
import Foundation

let outputDir = "Resources/Assets.xcassets/AppIcon.appiconset"

// All unique pixel sizes the AppIcon set references.
let sizes: [Int] = [16, 32, 64, 128, 256, 512, 1024]

try? FileManager.default.createDirectory(
    atPath: outputDir,
    withIntermediateDirectories: true
)

// MARK: - Colors

struct RGB { let r: CGFloat; let g: CGFloat; let b: CGFloat }
extension RGB {
    var cg: CGColor { CGColor(red: r, green: g, blue: b, alpha: 1.0) }
}

// Lacquer red background (top-left → bottom-right gradient)
let bgTop    = RGB(r: 0.62, g: 0.10, b: 0.12)
let bgBottom = RGB(r: 0.32, g: 0.05, b: 0.08)

// Gold compartments (top → bottom gradient)
let compTop    = RGB(r: 0.97, g: 0.83, b: 0.42)
let compBottom = RGB(r: 0.78, g: 0.56, b: 0.18)

// MARK: - Drawing

func drawIcon(into ctx: CGContext, size: CGFloat) {
    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    // Apple's Big Sur+ corner radius ratio.
    let cornerRadius = size * 0.225

    // Background: rounded square clipped + lacquer-red diagonal gradient.
    ctx.saveGState()
    let bgPath = CGPath(
        roundedRect: rect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )
    ctx.addPath(bgPath)
    ctx.clip()

    let cs = CGColorSpaceCreateDeviceRGB()
    let bgGradient = CGGradient(
        colorsSpace: cs,
        colors: [bgTop.cg, bgBottom.cg] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        bgGradient,
        start: CGPoint(x: 0, y: size),       // top-left
        end:   CGPoint(x: size, y: 0),       // bottom-right
        options: []
    )
    ctx.restoreGState()

    // Inner Bento layout
    let inset = size * 0.13
    let innerRect = rect.insetBy(dx: inset, dy: inset)
    let gap = size * 0.04
    let compRadius = size * 0.06

    // Hero: left ~58% wide, full inner height
    let heroWidth = innerRect.width * 0.58
    let heroRect = CGRect(
        x: innerRect.minX,
        y: innerRect.minY,
        width: heroWidth,
        height: innerRect.height
    )
    drawCompartment(into: ctx, rect: heroRect, cornerRadius: compRadius)

    // 3 secondary compartments stacked on the right
    let rightX = innerRect.minX + heroWidth + gap
    let rightWidth = innerRect.maxX - rightX
    let secHeight = (innerRect.height - 2 * gap) / 3

    for i in 0..<3 {
        // y is bottom-up. We want top-most secondary first.
        let topY = innerRect.maxY - CGFloat(i + 1) * secHeight - CGFloat(i) * gap
        let secRect = CGRect(
            x: rightX,
            y: topY,
            width: rightWidth,
            height: secHeight
        )
        drawCompartment(into: ctx, rect: secRect, cornerRadius: compRadius)
    }
}

func drawCompartment(into ctx: CGContext, rect: CGRect, cornerRadius: CGFloat) {
    ctx.saveGState()
    defer { ctx.restoreGState() }

    let path = CGPath(
        roundedRect: rect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )
    ctx.addPath(path)
    ctx.clip()

    let cs = CGColorSpaceCreateDeviceRGB()

    // Vertical gold gradient (top brighter, bottom darker)
    let gradient = CGGradient(
        colorsSpace: cs,
        colors: [compTop.cg, compBottom.cg] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end:   CGPoint(x: rect.minX, y: rect.minY),
        options: []
    )

    // Subtle highlight at the top edge to give it polished lacquer feel.
    let highlightHeight = rect.height * 0.30
    let highlightStart = CGPoint(x: rect.minX, y: rect.maxY)
    let highlightEnd   = CGPoint(x: rect.minX, y: rect.maxY - highlightHeight)
    let highlightGradient = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        highlightGradient,
        start: highlightStart,
        end:   highlightEnd,
        options: []
    )
}

// MARK: - Render to PNG at exact pixel size

func renderPNGData(size: Int) -> Data? {
    guard let bitmap = NSBitmapImageRep(
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
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }

    guard let nsCtx = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
    NSGraphicsContext.current = nsCtx
    drawIcon(into: nsCtx.cgContext, size: CGFloat(size))

    return bitmap.representation(using: .png, properties: [:])
}

// MARK: - Output

for size in sizes {
    guard let data = renderPNGData(size: size) else {
        FileHandle.standardError.write(Data("failed to render \(size)\n".utf8))
        exit(1)
    }
    let path = "\(outputDir)/icon_\(size).png"
    try data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(data.count) bytes)")
}

let contentsJSON = """
{
  "images" : [
    { "filename" : "icon_16.png",   "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_32.png",   "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32.png",   "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_64.png",   "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128.png",  "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_256.png",  "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256.png",  "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_512.png",  "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512.png",  "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_1024.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}

"""
try contentsJSON.write(
    to: URL(fileURLWithPath: "\(outputDir)/Contents.json"),
    atomically: true,
    encoding: .utf8
)
print("wrote \(outputDir)/Contents.json")
