// Generates the Frantics app icon (original art, drawn in code):
// dark night gradient, soft neon glows, confetti dots, and a big
// pink-to-cyan gradient "F" in SF Rounded Black.
//
//   swift scripts/make-icon.swift ios/Frantics/Assets.xcassets/AppIcon.appiconset/icon-1024.png
//
// Output is opaque RGB (no alpha) — App Store marketing icons reject alpha.

import AppKit
import CoreText

let size = 1024
let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "icon-1024.png"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(
    data: nil, width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fatalError("could not create bitmap context")
}

let s = CGFloat(size)

// Night gradient background.
let bg = CGGradient(
    colorsSpace: space,
    colors: [color(0x1B1040), color(0x0B0B1F)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: s), end: .zero, options: [])

// Soft neon glows in opposite corners.
func glow(_ center: CGPoint, _ radius: CGFloat, _ c: UInt32, _ alpha: CGFloat) {
    let g = CGGradient(
        colorsSpace: space,
        colors: [color(c, alpha), color(c, 0)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: radius, options: [])
}
glow(CGPoint(x: s * 0.2, y: s * 0.85), s * 0.55, 0xFF2E88, 0.34)
glow(CGPoint(x: s * 0.85, y: s * 0.18), s * 0.6, 0x00F5D4, 0.26)

// Confetti dots.
let confetti: [(CGFloat, CGFloat, CGFloat, UInt32)] = [
    (0.16, 0.22, 26, 0xFEE440), (0.84, 0.78, 30, 0xFF2E88),
    (0.78, 0.62, 18, 0x00F5D4), (0.22, 0.70, 20, 0x9B5DE5),
    (0.66, 0.16, 22, 0xFEE440), (0.34, 0.12, 16, 0x00BBF9),
]
for (x, y, r, c) in confetti {
    ctx.setFillColor(color(c, 0.9))
    ctx.fillEllipse(in: CGRect(x: s * x - r, y: s * y - r, width: r * 2, height: r * 2))
}

// The big gradient "F".
let baseFont = NSFont.systemFont(ofSize: 720, weight: .black)
let rounded = NSFont(
    descriptor: baseFont.fontDescriptor.withDesign(.rounded) ?? baseFont.fontDescriptor,
    size: 720
) ?? baseFont
let line = CTLineCreateWithAttributedString(
    NSAttributedString(string: "F", attributes: [.font: rounded, .foregroundColor: NSColor.white])
)
let bounds = CTLineGetImageBounds(line, ctx)

// Soft drop shadow pass for depth.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 60, color: color(0x000000, 0.55))
ctx.textPosition = CGPoint(
    x: (s - bounds.width) / 2 - bounds.minX,
    y: (s - bounds.height) / 2 - bounds.minY
)
CTLineDraw(line, ctx)
ctx.restoreGState()

// Gradient fill pass: clip to the glyph, pour the gradient through it.
ctx.saveGState()
ctx.textPosition = CGPoint(
    x: (s - bounds.width) / 2 - bounds.minX,
    y: (s - bounds.height) / 2 - bounds.minY
)
ctx.setTextDrawingMode(.clip)
CTLineDraw(line, ctx)
let f = CGGradient(
    colorsSpace: space,
    colors: [color(0xFF2E88), color(0x9B5DE5), color(0x00F5D4)] as CFArray,
    locations: [0, 0.5, 1]
)!
ctx.drawLinearGradient(
    f,
    start: CGPoint(x: s * 0.25, y: s * 0.85),
    end: CGPoint(x: s * 0.8, y: s * 0.15),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)
ctx.restoreGState()

let image = ctx.makeImage()!
let url = URL(fileURLWithPath: outPath) as CFURL
guard let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else {
    fatalError("could not create image destination")
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("could not write png") }
print("wrote \(outPath)")
