#!/usr/bin/env swift
//
// Renders Hearby's app icon and writes AppIcon.icns.
//
// The icon is drawn in code rather than kept as a binary asset so it stays
// diffable and tweakable without a design tool:
//
//   ./Scripts/make-icon.swift
//
// Mark: a text-selection block (the thing you highlight) with sound waves
// coming off it — "select, then speak" in one glyph.

import AppKit
import CoreGraphics
import Foundation

// macOS icons are drawn inside a rounded "squircle" that occupies ~80% of the
// canvas; the surrounding margin is where the system drops its shadow.
let inset: CGFloat = 0.094
let cornerRatio: CGFloat = 0.185

func draw(size: CGFloat) -> CGImage {
    let w = Int(size)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: w, height: w, bitsPerComponent: 8, bytesPerRow: 0,
        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let m = size * inset
    let box = CGRect(x: m, y: m, width: size - 2 * m, height: size - 2 * m)
    let radius = box.width * cornerRatio

    // ── Background: deep indigo -> violet, lit from the top-left ──────────
    let plate = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(plate)
    ctx.clip()
    let bg = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(srgbRed: 0.353, green: 0.310, blue: 0.914, alpha: 1), // #5A4FE9
            CGColor(srgbRed: 0.475, green: 0.243, blue: 0.851, alpha: 1), // #793Ed9
            CGColor(srgbRed: 0.318, green: 0.169, blue: 0.639, alpha: 1), // #512BA3
        ] as CFArray,
        locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(
        bg, start: CGPoint(x: box.minX, y: box.maxY),
        end: CGPoint(x: box.maxX, y: box.minY), options: [])

    // Soft highlight so the plate reads as convex, not flat.
    let gloss = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22),
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0),
        ] as CFArray,
        locations: [0, 1])!
    ctx.drawRadialGradient(
        gloss,
        startCenter: CGPoint(x: box.midX - box.width * 0.18, y: box.maxY - box.height * 0.05),
        startRadius: 0,
        endCenter: CGPoint(x: box.midX - box.width * 0.18, y: box.maxY - box.height * 0.05),
        endRadius: box.width * 0.72, options: [])
    ctx.restoreGState()

    // ── Selected text: three "lines" of text, the middle one highlighted ──
    let u = box.width           // work in fractions of the plate
    let lineH = u * 0.077
    let lineR = lineH / 2
    let leftX = box.minX + u * 0.185
    let centerY = box.midY

    func bar(y: CGFloat, width: CGFloat, color: CGColor, alpha: CGFloat = 1) {
        let r = CGRect(x: leftX, y: y - lineH / 2, width: width, height: lineH)
        ctx.setFillColor(color.copy(alpha: alpha)!)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: lineR, cornerHeight: lineR, transform: nil))
        ctx.fillPath()
    }

    let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    let gap = u * 0.145

    // Dimmed lines above and below imply a page of text.
    bar(y: centerY + gap, width: u * 0.40, color: white, alpha: 0.38)
    bar(y: centerY - gap, width: u * 0.30, color: white, alpha: 0.38)

    // The highlighted selection: a bright accent block with the text knocked out.
    let selRect = CGRect(
        x: leftX - u * 0.035, y: centerY - lineH * 1.05,
        width: u * 0.475, height: lineH * 2.1)
    ctx.setFillColor(CGColor(srgbRed: 0.404, green: 0.965, blue: 0.788, alpha: 1)) // #67F6C9
    ctx.addPath(CGPath(
        roundedRect: selRect, cornerWidth: u * 0.022, cornerHeight: u * 0.022, transform: nil))
    ctx.fillPath()

    ctx.setBlendMode(.destinationOut)
    bar(y: centerY, width: u * 0.40, color: white)
    ctx.setBlendMode(.normal)

    // ── Sound waves radiating from the selection ─────────────────────────
    let waveCenter = CGPoint(x: box.minX + u * 0.715, y: centerY)
    ctx.setLineCap(.round)
    let arcs: [(r: CGFloat, alpha: CGFloat, lw: CGFloat)] = [
        (u * 0.085, 1.00, u * 0.058),
        (u * 0.165, 0.72, u * 0.054),
        (u * 0.245, 0.42, u * 0.050),
    ]
    for arc in arcs {
        ctx.setStrokeColor(white.copy(alpha: arc.alpha)!)
        ctx.setLineWidth(arc.lw)
        ctx.addArc(
            center: waveCenter, radius: arc.r,
            startAngle: -.pi / 3.4, endAngle: .pi / 3.4, clockwise: false)
        ctx.strokePath()
    }

    return ctx.makeImage()!
}

// ── Emit the .iconset and convert ────────────────────────────────────────
let root = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// Apple requires each size at 1x and 2x.
let sizes = [16, 32, 128, 256, 512]
for s in sizes {
    for scale in [1, 2] {
        let px = s * scale
        let image = draw(size: CGFloat(px))
        let name = scale == 1 ? "icon_\(s)x\(s).png" : "icon_\(s)x\(s)@2x.png"
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: px, height: px)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fatalError("PNG encoding failed for \(name)")
        }
        try png.write(to: iconset.appendingPathComponent(name))
    }
}

let out = root.appendingPathComponent("Hearby/Resources/AppIcon.icns")
try FileManager.default.createDirectory(
    at: out.deletingLastPathComponent(), withIntermediateDirectories: true)

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try p.run()
p.waitUntilExit()
guard p.terminationStatus == 0 else { exit(p.terminationStatus) }

print("Wrote \(out.path)")
