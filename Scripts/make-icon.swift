#!/usr/bin/env swift
//
// Scripts/make-icon.swift — reproducible App Store icon generator for Pulse.
//
// Produces the iOS 18/27 single-size 1024x1024 icon plus the dark and tinted
// appearance variants. Flat, opaque, full-bleed: no alpha, no rounded corners,
// no gradient, no text (docs/DESIGN.md §1-2: urgency is position, not colour;
// HorizonNow is the accent).
//
// The mark: one pulse waveform carrying three beats — calendar, mail, reminders —
// with the centre beat dominant. Keeping the pulse on three things at once, all
// on one line, resolving to one answer. The dominant centre beat is the one thing
// that needs you; the smaller outer beats are the sources that are quiet but
// still watched.
//
// What earlier attempts got wrong, recorded because each is a tempting idea that
// does not survive 40 pt:
//
//   * **Three ribbons converging.** Literal and legible at 1024, but at 40 pt the
//     three hairlines fuse into a wedge and the convergence reads as a printing
//     defect. One line with three beats says "three" using amplitude instead of
//     count, which is what survives downscaling.
//   * **A detachable attention dot.** Shipped for two iterations: a disc floating
//     over the peak. It cannot win — small enough not to crowd the beat, it
//     rasterises to a speck at 40 pt; large enough to read, it collides with the
//     beat and looks like an exclamation mark. The dominant beat carries the
//     emphasis instead.
//   * **Edge-bleeding strokes.** A line that runs off both edges reads as a
//     banner, not an icon: it has no silhouette and looks cropped in a rounded
//     mask. The mark is fully contained now, with margins the OS mask cannot eat.
//   * **Thin strokes.** Anything under ~110 pt at 1024 disappears at 40 pt.
//
// Run:  swift Scripts/make-icon.swift
// Out:  ThirdHand/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
//       ThirdHand/Assets.xcassets/AppIcon.appiconset/AppIcon-1024-dark.png
//       ThirdHand/Assets.xcassets/AppIcon.appiconset/AppIcon-1024-tinted.png
//
// Token source of truth: docs/DESIGN.md §2 and Assets.xcassets.
//   HorizonNow light #D70015   HorizonNow dark #FF453A
//   SurfaceCanvas dark #000000

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let outDir = URL(fileURLWithPath: "ThirdHand/Assets.xcassets/AppIcon.appiconset")

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

// MARK: - Geometry

/// The centreline the waveform rides on.
///
/// Above the geometric centre (512) because the beats' troughs reach further down
/// than their peaks reach up — the large centre beat's peak is 236 above the line
/// and its trough 148 below. Sitting on 506 balances that visual mass; on 512 the
/// mark looks like it has slid down the icon.
let centreline: CGFloat = 506

/// Every mark coordinate is an offset from the canvas centre, so the geometry is
/// independent of where the centreline sits.
let mid: CGFloat = 512

/// The three beats: a small one for the first source, the dominant centre one,
/// and a slightly larger small one for the third.
///
/// `halfWidth` and `up`/`down` are what make the difference between "a heartbeat
/// monitor" and "one thing needs you": two of these are quiet, one is not. Three
/// equal beats reads as decoration; three beats with a clear centre reads as a
/// priority.
struct Beat {
    /// Horizontal offset from the canvas centre. Symmetric, so the dominant beat
    /// is optically centred while the outer two balance it.
    let dx: CGFloat
    /// How far the peak rises above the centreline.
    let up: CGFloat
    /// How far the trough drops below the centreline.
    let down: CGFloat
    /// Half the width of this beat's span.
    let halfWidth: CGFloat
}

let beats: [Beat] = [
    Beat(dx: -252, up: 96, down: 66, halfWidth: 92),
    Beat(dx: 0, up: 236, down: 148, halfWidth: 104),
    Beat(dx: 252, up: 118, down: 80, halfWidth: 96),
]

/// Where the flat run enters and leaves the mark.
///
/// Not touching the canvas edges: an edge-bleeding line has no silhouette and
/// looks cropped once the OS applies its rounded mask.
let markInset: CGFloat = 158

/// Stroke weight. 124 at 1024 is the thinnest weight that still renders as a
/// continuous line at the 40 pt size iOS asks for.
let strokeWeight: CGFloat = 124

/// The mark: a flat run in, three beats, a flat run out.
func markPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: markInset, y: centreline))
    for beat in beats {
        path.addLine(to: CGPoint(x: mid + beat.dx - beat.halfWidth, y: centreline))
        path.addLine(to: CGPoint(x: mid + beat.dx, y: centreline - beat.up))
        path.addLine(to: CGPoint(x: mid + beat.dx + beat.halfWidth, y: centreline + beat.down))
    }
    path.addLine(to: CGPoint(x: CGFloat(size) - markInset, y: centreline))
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

    ctx.setStrokeColor(CGColor(srgbRed: variant.glyph.0,
                               green: variant.glyph.1,
                               blue: variant.glyph.2,
                               alpha: 1))
    ctx.setLineWidth(strokeWeight)
    // Round caps and joins: the beats are sharp changes of direction, and a miter
    // join spikes out at the peaks — visible as little horns at small sizes.
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    ctx.addPath(markPath())
    ctx.strokePath()

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
