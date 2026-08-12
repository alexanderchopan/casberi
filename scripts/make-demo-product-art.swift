#!/usr/bin/env swift
// make-demo-product-art.swift — the demo's product stills (2026-08-11).
//
// WHY THIS EXISTS. The demo's Shopify and Deals rows are `.product` things,
// and `ThingContent`'s `.product` case leads with `previewImageURL` — the
// image is "doing the work of not leaving the sheet blank" in that file's own
// words. They were seeded with `art(i)`, which resolves to the four bundled
// sample PHOTOS, so opening a linen apron showed a stock shot of a person in
// a luchador mask. Reported from the room itself: "the seeded material was
// photos not store items."
//
// Removing the image left the sheet honest and blank, which is worse for a
// demo whose job is to show the app full. So: real bundled art, generated
// here rather than fetched (the demo reaches nothing) or hand-drawn once and
// left as an unexplained binary.
//
// These are STILLS, not fake photographs — a symbol on a tinted ground, which
// is what a placeholder should look like when the honest alternative is a
// photograph nobody took. Nothing here claims to be a photo of the product.
//
// Usage:  swift scripts/make-demo-product-art.swift
// Writes: Casberi/Casberi/Assets.xcassets/sample-product-N.imageset/art.jpg
//
// JPEG, not PNG, and matching the bundled screenshot beside it: a smooth
// gradient is the worst case for PNG (3.1MB across eight at 900px, all of it
// shipped to every user for a demo), and the worst case for JPEG artefacts is
// a hard edge, which a symbol on a soft ground does not have.
//
// Re-run after editing `products` below; it rewrites the imagesets in place.

import AppKit

struct Still {
    let symbols: [String]      // candidates, first that resolves wins
    let top: NSColor           // ground, top
    let bottom: NSColor        // ground, bottom
    let ink: NSColor           // the symbol
    let note: String           // which seeded row this is for
}

func rgb(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

// Order is the seeding order — `DemoSeedAll.productArt(_:)` indexes into it.
let products: [Still] = [
    // Shopify — the four arrivals
    .init(symbols: ["tshirt.fill", "tshirt"], top: rgb(0xEDE7DC), bottom: rgb(0xD8CFBE),
          ink: rgb(0x4A4238), note: "Linen apron"),
    .init(symbols: ["frying.pan.fill", "frying.pan", "circle.fill"], top: rgb(0xDFE4E7),
          bottom: rgb(0xC5CCD1), ink: rgb(0x2F3437), note: "Cast iron pan"),
    .init(symbols: ["cup.and.saucer.fill", "cup.and.saucer"], top: rgb(0xF1E5DE),
          bottom: rgb(0xDCC9BF), ink: rgb(0x5A3F36), note: "Ceramic mug"),
    .init(symbols: ["fork.knife", "square.grid.2x2.fill"], top: rgb(0xEFE6D4),
          bottom: rgb(0xDACEB6), ink: rgb(0x574B33), note: "Oak chopping board"),
    // Deals — the four offers
    .init(symbols: ["bolt.fill"], top: rgb(0xDEEAE4), bottom: rgb(0xC4DAD0),
          ink: rgb(0x24443A), note: "Power bank"),
    .init(symbols: ["book.closed.fill", "book.fill"], top: rgb(0xEAE8E2),
          bottom: rgb(0xD4D1C8), ink: rgb(0x3A3A38), note: "Kindle"),
    .init(symbols: ["mug.fill", "cup.and.saucer.fill"], top: rgb(0xE6DBD3),
          bottom: rgb(0xCEC0B4), ink: rgb(0x4A3A2E), note: "Coffee grinder"),
    .init(symbols: ["airpodspro", "headphones"], top: rgb(0xE6E9EE),
          bottom: rgb(0xCCD3DB), ink: rgb(0x303640), note: "AirPods Pro"),
]

let side: CGFloat = 640
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Casberi/Casberi/Assets.xcassets")

func symbol(_ names: [String], size: CGFloat, color: NSColor) -> NSImage? {
    for name in names {
        guard let raw = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { continue }
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        guard let sized = raw.withSymbolConfiguration(config) else { continue }
        // Tint by compositing the colour through the glyph's own alpha —
        // a template image drawn plain would come out system-black.
        let out = NSImage(size: sized.size)
        out.lockFocus()
        sized.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        color.set()
        NSRect(origin: .zero, size: sized.size).fill(using: .sourceAtop)
        out.unlockFocus()
        return out
    }
    return nil
}

var wrote = 0
for (i, p) in products.enumerated() {
    let canvas = NSImage(size: NSSize(width: side, height: side))
    canvas.lockFocus()

    NSGradient(starting: p.top, ending: p.bottom)?
        .draw(in: NSRect(x: 0, y: 0, width: side, height: side), angle: -90)

    // A soft contact shadow under the object, so the still reads as a thing
    // standing on a surface rather than a sticker on a swatch.
    let shadow = NSBezierPath(ovalIn: NSRect(x: side * 0.26, y: side * 0.20,
                                             width: side * 0.48, height: side * 0.075))
    p.ink.withAlphaComponent(0.10).setFill()
    shadow.fill()

    if let glyph = symbol(p.symbols, size: side * 0.40, color: p.ink) {
        let s = glyph.size
        glyph.draw(in: NSRect(x: (side - s.width) / 2, y: (side - s.height) / 2 + side * 0.045,
                              width: s.width, height: s.height))
    } else {
        FileHandle.standardError.write("no symbol resolved for \(p.note)\n".data(using: .utf8)!)
    }
    canvas.unlockFocus()

    guard let tiff = canvas.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .jpeg,
                                       properties: [.compressionFactor: 0.86]) else {
        FileHandle.standardError.write("encode failed for \(p.note)\n".data(using: .utf8)!)
        continue
    }

    let dir = root.appendingPathComponent("sample-product-\(i + 1).imageset")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? png.write(to: dir.appendingPathComponent("art.jpg"))
    let contents = """
    {
      "images" : [
        {
          "filename" : "art.jpg",
          "idiom" : "universal"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """
    try? contents.write(to: dir.appendingPathComponent("Contents.json"),
                        atomically: true, encoding: .utf8)
    wrote += 1
    print("sample-product-\(i + 1)  \(p.note)")
}
print("wrote \(wrote) product stills")
