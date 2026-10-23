#!/usr/bin/env swift
//
// Scripts/make-icon.swift — reproducible App Store icon generator for Pulse.
//
// Produces the iOS 18/27 single-size 1024x1024 icon plus the dark and tinted
// appearance variants. Flat, opaque, full-bleed: no alpha, no rounded corners,
// no gradient, no text (docs/DESIGN.md §1-2: urgency is position, not colour;
// HorizonNow is the accent). The mark is a single bold pulse glyph so it still
// reads at 40 pt.
//
// Run:  swift Scripts/make-icon.swift
// Out:  Pulse/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
//       Pulse/Assets.xcassets/AppIcon.appiconset/AppIcon-1024-dark.png
//       Pulse/Assets.xcassets/AppIcon.appiconset/AppIcon-1024-tinted.png
//
// Token source of truth: docs/DESIGN.md §2 and Assets.xcassets.
//   HorizonNow light #D70015   HorizonNow dark #FF453A
//   SurfaceCanvas dark #000000

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let outDir = URL(fileURLWithPath: "Pulse/Assets.xcassets/AppIcon.appiconset")

struct Variant {
    let file: String
    let background: (CGFloat, CGFloat, CGFloat)
    let glyph: (CGFloat, CGFloat, CGFloat)
}

// sRGB components, 0...1. Values are the literal hex from docs/DESIGN.md §2.
func rgb(_ hex: UInt32) -> (CGFloat, CGFloat, CGFloat) {
    (
        CGFloat((hex >> 16) & 0xFF) / 255,
        CGFloat((hex >> 8) & 0xFF) / 255,
        CGFloat(hex & 0xFF) / 255
    )
}

let variants: [Variant] = [
    // Light/universal: HorizonNow red field, white mark.
    Variant(file: "AppIcon-1024.png", background: rgb(0xD70015), glyph: rgb(0xFFFFFF)),
    // Dark appearance: SurfaceCanvas black field, HorizonNow.dark mark (iOS 27
    // dark icons sit on a dark field rather than inverting to a light one).
    Variant(file: "AppIcon-1024-dark.png", background: rgb(0x000000), glyph: rgb(0xFF453A)),
    // Tinted appearance: the system derives the tint from luminance, so ship a
    // neutral grayscale version - white mark on black.
    Variant(file: "AppIcon-1024-tinted.png", background: rgb(0x000000), glyph: rgb(0xFFFFFF)),
]

func makeContext() -> CGContext {
    // No alpha channel at all (noneSkipLast): Apple rejects alpha in store icons.
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        fatalError("could not create \(size)x\(size) sRGB context")
    }
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    // Flip so y grows downward, so the glyph coordinates read top-to-bottom.
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: 1, y: -1)
    return ctx
}

/// The mark: one board-wide pulse. It bleeds off both edges rather than sitting
/// centred, which keeps the "full-bleed, no margin" contract and reads as a line
/// drawn under the board rather than a medical squiggle. A single filled dot at
/// the apex is the "one thing that needs you now" (docs/DESIGN.md §1: one numeric
/// emphasis per screen). Two shapes only, so it survives 40 pt.
func pulsePath() -> CGPath {
    let points: [CGPoint] = [
        CGPoint(x: -40, y: 560),
        CGPoint(x: 214, y: 560),
        CGPoint(x: 296, y: 646),
        CGPoint(x: 392, y: 560),
        CGPoint(x: 468, y: 560),
        CGPoint(x: 566, y: 380),   // apex of the spike
        CGPoint(x: 668, y: 706),   // the trough
        CGPoint(x: 756, y: 468),
        CGPoint(x: 820, y: 560),
        CGPoint(x: 1064, y: 560),  // bleeds off the right edge
    ]
    let path = CGMutablePath()
    path.addLines(between: points)
    return path
}

func render(_ variant: Variant) -> CGImage {
    let ctx = makeContext()

    // Full bleed: no corner rounding, no margin. The OS masks the icon itself.
    ctx.setFillColor(CGColor(srgbRed: variant.background.0,
                             green: variant.background.1,
                             blue: variant.background.2,
                             alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

    let ink = CGColor(srgbRed: variant.glyph.0,
                      green: variant.glyph.1,
                      blue: variant.glyph.2,
                      alpha: 1)
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(72)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(pulsePath())
    ctx.strokePath()

    // The attention point: a filled disc floating above the apex of the spike,
    // clear of the stroke so the mark reads as "one thing flagged", not a
    // lollipop. 96 pt across reads at 40 pt display.
    ctx.setFillColor(ink)
    ctx.fillEllipse(in: CGRect(x: 566 - 50, y: 312 - 50, width: 100, height: 100))

    guard let image = ctx.makeImage() else { fatalError("no image") }
    return image
}

func write(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else {
        fatalError("could not create PNG destination at \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        fatalError("could not write \(url.path)")
    }
}

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for variant in variants {
    let url = outDir.appendingPathComponent(variant.file)
    try write(render(variant), to: url)
    print("wrote \(url.path)")
}
