//
//  make-readme-art.swift
//  Q2-Sync › Scripts
//
//  PURPOSE
//  Draws the artwork used on the GitHub page:
//    docs/images/logo-light.png      wordmark (app icon + "Q2 Sync") for light mode
//    docs/images/logo-dark.png       the same for dark mode
//    docs/images/hero.png            README banner with the app window
//    docs/branding/social-preview.png  1280×640 image for GitHub's
//                                      Settings → Social preview (upload by hand)
//
//  It uses the app icon and the screenshots already in docs/images, so
//  re-run it after replacing a screenshot.
//
//  USAGE (from the repository root)
//      swift Scripts/make-readme-art.swift
//

import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let images = root.appendingPathComponent("docs/images")
let branding = root.appendingPathComponent("docs/branding")
let icon = NSImage(contentsOf: root.appendingPathComponent("Q2-Sync/Assets.xcassets/AppIcon.appiconset/icon-1024.png"))!
let window = NSImage(contentsOf: images.appendingPathComponent("device-music.png"))!
let sheet = NSImage(contentsOf: images.appendingPathComponent("sync-preview.png"))!

let blue = NSColor(srgbRed: 0.04, green: 0.33, blue: 0.86, alpha: 1)
let ink = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
let subInk = NSColor(srgbRed: 0.43, green: 0.43, blue: 0.45, alpha: 1)

func font(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: weight)
}

/// Draws `text` horizontally centred on `midX` with its baseline at `y`.
func drawCentered(_ text: String, font: NSFont, color: NSColor, midX: CGFloat, y: CGFloat, kern: CGFloat = 0) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern]
    let s = NSAttributedString(string: text, attributes: attrs)
    s.draw(at: NSPoint(x: midX - s.size().width / 2, y: y))
}

/// Draws "Q2 Sync" with "Sync" in the icon's blue gradient look.
func wordmark(at origin: NSPoint, size: CGFloat, color: NSColor) -> CGFloat {
    let f = font(size, .bold)
    let q2 = NSAttributedString(string: "Q2 ", attributes: [.font: f, .foregroundColor: color, .kern: -size * 0.02])
    let sync = NSAttributedString(string: "Sync", attributes: [.font: f, .foregroundColor: NSColor(srgbRed: 0.16, green: 0.47, blue: 1.0, alpha: 1), .kern: -size * 0.02])
    q2.draw(at: origin)
    sync.draw(at: NSPoint(x: origin.x + q2.size().width, y: origin.y))
    return q2.size().width + sync.size().width
}

func render(_ name: String, width: CGFloat, height: CGFloat, _ draw: @escaping (NSRect) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    let folder = name.hasPrefix("social-preview") ? branding : images
    let url = folder.appendingPathComponent(name)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("Wrote docs/\(folder.lastPathComponent)/\(name)")
}

/// Soft light backdrop: white fading to a pale blue, with a blue glow.
func backdrop(_ r: NSRect, glowAt glow: NSPoint, radius: CGFloat) {
    NSGradient(starting: NSColor(srgbRed: 0.97, green: 0.98, blue: 1.0, alpha: 1),
               ending: NSColor(srgbRed: 0.86, green: 0.91, blue: 0.99, alpha: 1))!.draw(in: r, angle: -90)
    NSGradient(colors: [NSColor(srgbRed: 0.33, green: 0.62, blue: 1.0, alpha: 0.35),
                        NSColor(srgbRed: 0.33, green: 0.62, blue: 1.0, alpha: 0.0)])!
        .draw(fromCenter: glow, radius: 0, toCenter: glow, radius: radius, options: [])
}

// MARK: - Wordmarks

for (name, color) in [("logo-light.png", ink), ("logo-dark.png", NSColor.white)] {
    render(name, width: 1090, height: 360) { r in
        icon.draw(in: NSRect(x: 0, y: 0, width: 360, height: 360))
        _ = wordmark(at: NSPoint(x: 360, y: 100), size: 190, color: color)
    }
}

// MARK: - Hero banner

render("hero.png", width: 2400, height: 1500) { r in
    backdrop(r, glowAt: NSPoint(x: r.midX, y: 420), radius: 1100)

    let iconSize: CGFloat = 220
    icon.draw(in: NSRect(x: r.midX - iconSize / 2, y: r.maxY - 60 - iconSize, width: iconSize, height: iconSize))
    drawCentered("Your music. Your Q2. In sync.", font: font(104, .bold), color: ink,
                 midX: r.midX, y: r.maxY - 420, kern: -2)
    drawCentered("Your own music files from the Music app, on your Shanling Q2. Tick, click Sync, done.",
                 font: font(44, .regular), color: subInk, midX: r.midX, y: r.maxY - 510)

    // The app window, bleeding off the bottom edge, with the sync sheet
    // floating in front of it on the right.
    let winW: CGFloat = 1700
    let winH = winW * window.size.height / window.size.width
    window.draw(in: NSRect(x: r.midX - winW / 2 - 140, y: -winH * 0.30, width: winW, height: winH))
    let shW: CGFloat = 1150
    let shH = shW * sheet.size.height / sheet.size.width
    // Crop the sheet screenshot to just the dialog (drop the dimmed window).
    let src = sheet.size
    // Keep the top of the dialog only; the rest bleeds off the bottom edge.
    let crop = NSRect(x: src.width * 0.165, y: src.height * 0.35, width: src.width * 0.67, height: src.height * 0.54)
    let dest = NSRect(x: r.maxX - shW * 0.67 - 120, y: -60, width: shW * 0.67, height: shH * 0.54)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.shadowBlurRadius = 60
    shadow.shadowOffset = NSSize(width: 0, height: -24)
    shadow.set()
    let clip = NSBezierPath(roundedRect: dest, xRadius: 26, yRadius: 26)
    NSColor.white.setFill()
    clip.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    clip.addClip()
    sheet.draw(in: dest, from: crop, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Social preview (GitHub: Settings → General → Social preview)

render("social-preview.png", width: 1280, height: 640) { r in
    backdrop(r, glowAt: NSPoint(x: 1000, y: 200), radius: 700)
    icon.draw(in: NSRect(x: 70, y: 330, width: 210, height: 210))
    _ = wordmark(at: NSPoint(x: 90, y: 200), size: 112, color: ink)
    let tag = NSAttributedString(string: "Sync your Mac’s music files\nto a Shanling Q2, the way\nFinder syncs an iPod.",
                                 attributes: [.font: font(34, .medium), .foregroundColor: subInk])
    tag.draw(in: NSRect(x: 96, y: 40, width: 560, height: 150))
    let winW: CGFloat = 820
    let winH = winW * window.size.height / window.size.width
    window.draw(in: NSRect(x: 600, y: -winH * 0.22, width: winW, height: winH))
}
