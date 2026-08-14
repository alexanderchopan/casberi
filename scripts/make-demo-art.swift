#!/usr/bin/env swift
// make-demo-art.swift — the demo's own bundled art (2026-08-11).
//
// Two families: product stills, and the faces of the demo's cast. Both exist
// for the same reason — the demo's job is to show what the app REALLY looks
// like to someone seeing it for the first time, and a room drawing brand
// glyphs where the real one draws photographs is not that.
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
// Usage:  swift scripts/make-demo-art.swift
// Writes: Casberi/Casberi/Assets.xcassets/sample-product-N.imageset/art.jpg
//     and Casberi/Casberi/Assets.xcassets/sample-avatar-<handle>.imageset/art.jpg
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


// MARK: - Faces
//
// The demo's cast, as profile pictures. Farcaster and Bluesky both hydrate a
// real `avatarURL` from their APIs, so a real person's social rooms are full
// of faces — the rail under the room strip is literally called a face rail.
// Seeded without them, every account and every row fell back to the source's
// brand glyph: three identical purple Farcaster marks where a real account
// list shows three different people.
//
// A monogram on a coloured ground rather than an invented portrait: it is
// what a real account without a photo actually looks like, it is obviously
// not a photograph of a person who doesn't exist, and it stays legible at the
// 28pt the rail draws it.

struct Face {
    let handle: String
    let initial: String
    let top: NSColor
    let bottom: NSColor
}

// PUBLICATION MARKS ONLY. The demo's PEOPLE moved to
// `scripts/make-demo-avatars.swift` (2026-08-12) — illustrated faces, because
// a real social roster is a column of faces and a column of initials is what
// an empty one looks like. They are listed there and NOT here on purpose: two
// generators writing the same imageset means whichever ran last wins, and this
// one would silently put the letters back.
//
// These stay monograms because `RSSIngest` stamps a site's FAVICON here — The
// Verge is a mark, not a person, and giving it a face would say somebody wrote
// for us.
let faces: [Face] = [
    // Stocktwits' traders. Three "T"s in three hues rather than three
    // initials: the handles really are @trader0/1/2, and inventing distinct
    // names to get prettier monograms would put words on screen the rows
    // don't say.
    // Publication marks. `RSSIngest` stamps the site's own favicon onto
    // `authorAvatarURL`, so every article row in a real reading room carries
    // its publisher beside the byline. These are monograms, not anybody's
    // logo — a stand-in for a favicon, which is what the field holds.
    .init(handle: "hackernews",  initial: "Y", top: rgb(0xFF7B4D), bottom: rgb(0xD1521F)),
    .init(handle: "theverge",    initial: "V", top: rgb(0xE0447C), bottom: rgb(0xA31C51)),
    .init(handle: "techcrunch",  initial: "T", top: rgb(0x3ECf7C), bottom: rgb(0x1B8B4C)),
    .init(handle: "smallthings", initial: "S", top: rgb(0x6F8BA8), bottom: rgb(0x445A72)),
    .init(handle: "latencyclub", initial: "L", top: rgb(0xB07BD8), bottom: rgb(0x7448A0)),
    // Hugging Face's owners (2026-08-14). `HuggingFaceBridge` reads each
    // org's own avatar off the hub's overview endpoint, so a real hub room
    // leads every model row with the lab's logo. Monograms for the same
    // reason the publications above are: an org is not a person, and these
    // stand in for a logo we have no right to draw.
    .init(handle: "kyutai",      initial: "K", top: rgb(0x6FA8DC), bottom: rgb(0x3D6FA0)),
    .init(handle: "espresso-lab", initial: "E", top: rgb(0xC98B5E), bottom: rgb(0x8A5630)),
]

let faceSide: CGFloat = 320
var faceCount = 0
for f in faces {
    let canvas = NSImage(size: NSSize(width: faceSide, height: faceSide))
    canvas.lockFocus()
    NSGradient(starting: f.top, ending: f.bottom)?
        .draw(in: NSRect(x: 0, y: 0, width: faceSide, height: faceSide), angle: -90)

    let para = NSMutableParagraphStyle()
    para.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: faceSide * 0.44, weight: .semibold),
        .foregroundColor: NSColor.white.withAlphaComponent(0.92),
        .paragraphStyle: para,
    ]
    let text = f.initial as NSString
    let size = text.size(withAttributes: attrs)
    text.draw(in: NSRect(x: 0, y: (faceSide - size.height) / 2,
                         width: faceSide, height: size.height), withAttributes: attrs)
    canvas.unlockFocus()

    guard let tiff = canvas.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
        FileHandle.standardError.write("encode failed for \(f.handle)\n".data(using: .utf8)!)
        continue
    }
    let dir = root.appendingPathComponent("sample-avatar-\(f.handle).imageset")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? jpg.write(to: dir.appendingPathComponent("art.jpg"))
    try? """
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
    """.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    faceCount += 1
    print("sample-avatar-\(f.handle)")
}
print("wrote \(faceCount) faces")


// MARK: - Coin marks
//
// `GeckoTrending` stamps each trending token's own logo onto
// `previewImageURL`, and `TokenWatch` does the same for a watched one — so a
// real Markets room is a column of round token faces. The demo's trending
// rows carried no image at all and fell back to the source glyph, which drew
// the same green GeckoTerminal mark three times.
//
// Monograms, not anybody's logo — the same call the publication marks above
// make, and for the same reason: the field holds a remote image we have no
// right to reproduce, so the stand-in should read as a stand-in. The demo's
// three WATCHED tokens (ETH/SOL/DEGEN) are different: those resolve to the
// app's own shipped `brand-*` assets, which it already draws elsewhere.

struct Coin {
    let symbol: String
    let initial: String
    let top: NSColor
    let bottom: NSColor
}

let coins: [Coin] = [
    .init(symbol: "aero", initial: "A", top: rgb(0x5B8DEF), bottom: rgb(0x2E5BC0)),
    .init(symbol: "brett", initial: "B", top: rgb(0x4CC2C0), bottom: rgb(0x1F8A88)),
    .init(symbol: "jup", initial: "J", top: rgb(0xC97BE8), bottom: rgb(0x8A3FB0)),
]

let coinSide: CGFloat = 320
var coinCount = 0
for c in coins {
    let canvas = NSImage(size: NSSize(width: coinSide, height: coinSide))
    canvas.lockFocus()
    NSGradient(starting: c.top, ending: c.bottom)?
        .draw(in: NSRect(x: 0, y: 0, width: coinSide, height: coinSide), angle: -90)
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: coinSide * 0.46, weight: .semibold),
        .foregroundColor: NSColor.white.withAlphaComponent(0.94),
        .paragraphStyle: style,
    ]
    let text = c.initial as NSString
    let size = text.size(withAttributes: attrs)
    text.draw(in: NSRect(x: 0, y: (coinSide - size.height) / 2,
                         width: coinSide, height: size.height), withAttributes: attrs)
    canvas.unlockFocus()

    guard let tiff = canvas.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
        FileHandle.standardError.write("encode failed for \(c.symbol)\n".data(using: .utf8)!)
        continue
    }
    let dir = root.appendingPathComponent("sample-coin-\(c.symbol).imageset")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? jpg.write(to: dir.appendingPathComponent("art.jpg"))
    try? """
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
    """.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    coinCount += 1
    print("sample-coin-\(c.symbol)")
}
print("wrote \(coinCount) coin marks")


// MARK: - Stream frames
//
// `TwitchBridge` stamps a FRAME OF THE STREAM onto `previewImageURL`, and the
// demo's Twitch room leads with `LiveStreamHero` — a full-width card that
// draws that image behind the stream's title. Pointed at the four bundled
// sample photos, the hero showed a football stadium under the words
// "Software and Game Development": the §83 failure in picture form, the same
// one the product stills above were generated to fix, on the largest image in
// the room.

let frames: [Still] = [
    .init(symbols: ["laptopcomputer", "desktopcomputer"], top: rgb(0x2B2350),
          bottom: rgb(0x171232), ink: rgb(0xB9A9FF), note: "nova — dev stream"),
    .init(symbols: ["gamecontroller.fill", "gamecontroller"], top: rgb(0x1F3A46),
          bottom: rgb(0x122630), ink: rgb(0x7FD9E8), note: "kestrel — Factorio"),
]

let frameW: CGFloat = 640, frameH: CGFloat = 360
var frameCount = 0
for (i, f) in frames.enumerated() {
    let canvas = NSImage(size: NSSize(width: frameW, height: frameH))
    canvas.lockFocus()
    NSGradient(starting: f.top, ending: f.bottom)?
        .draw(in: NSRect(x: 0, y: 0, width: frameW, height: frameH), angle: -90)
    if let glyph = symbol(f.symbols, size: frameH * 0.34, color: f.ink) {
        let s = glyph.size
        glyph.draw(in: NSRect(x: (frameW - s.width) / 2, y: (frameH - s.height) / 2,
                              width: s.width, height: s.height))
    }
    canvas.unlockFocus()
    guard let tiff = canvas.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.86]) else {
        FileHandle.standardError.write("encode failed for \(f.note)\n".data(using: .utf8)!)
        continue
    }
    let dir = root.appendingPathComponent("sample-frame-\(i + 1).imageset")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? jpg.write(to: dir.appendingPathComponent("art.jpg"))
    try? """
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
    """.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    frameCount += 1
    print("sample-frame-\(i + 1)  \(f.note)")
}
print("wrote \(frameCount) stream frames")


// MARK: - Book covers
//
// A Readwise highlight lands with its BOOK COVER on `previewImageURL` (the
// `cover` field of the book it came from), so a real reading room is a column
// of spines. The demo had none, and its rows fell back to the source glyph —
// six identical marks for three different books.
//
// Keyed by BOOK, not by row: the demo quotes each book more than once, and a
// second cover for the same title would say they were different books.
// Abstract grounds rather than any real jacket — the same call the coin and
// publication marks make about art we have no right to reproduce.

struct Cover {
    let key: String            // matches DemoSeedAll's own cover(for:) key
    let top: NSColor
    let bottom: NSColor
    let ink: NSColor
    let symbols: [String]
}

let covers: [Cover] = [
    .init(key: "state", top: rgb(0xC5502F), bottom: rgb(0x7E2C16),
          ink: rgb(0xF6E2CE), symbols: ["map.fill", "map"]),
    .init(key: "timeless", top: rgb(0x2E6B5E), bottom: rgb(0x17403A),
          ink: rgb(0xDCEFE6), symbols: ["square.grid.3x3.fill", "square.grid.3x3"]),
    .init(key: "systems", top: rgb(0x36508F), bottom: rgb(0x1C2C57),
          ink: rgb(0xDDE6FA), symbols: ["arrow.triangle.2.circlepath", "circle.fill"]),
]

let coverW: CGFloat = 400, coverH: CGFloat = 600
var coverCount = 0
for c in covers {
    let canvas = NSImage(size: NSSize(width: coverW, height: coverH))
    canvas.lockFocus()
    NSGradient(starting: c.top, ending: c.bottom)?
        .draw(in: NSRect(x: 0, y: 0, width: coverW, height: coverH), angle: -90)
    if let glyph = symbol(c.symbols, size: coverW * 0.36, color: c.ink.withAlphaComponent(0.9)) {
        let s = glyph.size
        glyph.draw(in: NSRect(x: (coverW - s.width) / 2, y: (coverH - s.height) / 2,
                              width: s.width, height: s.height))
    }
    canvas.unlockFocus()
    guard let tiff = canvas.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.86]) else {
        FileHandle.standardError.write("encode failed for \(c.key)\n".data(using: .utf8)!)
        continue
    }
    let dir = root.appendingPathComponent("sample-cover-\(c.key).imageset")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? jpg.write(to: dir.appendingPathComponent("art.jpg"))
    try? """
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
    """.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    coverCount += 1
    print("sample-cover-\(c.key)")
}
print("wrote \(coverCount) book covers")
