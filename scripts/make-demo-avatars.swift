#!/usr/bin/env swift
//
// make-demo-avatars.swift — the demo cast's FACES.
//
// Run from the repo root:  swift scripts/make-demo-avatars.swift
// Writes: Casberi/Casberi/Assets.xcassets/sample-avatar-<handle>.imageset/face.png
//
// WHY THIS IS SEPARATE FROM `make-demo-art.swift`. That script is offline and
// deterministic — it draws everything it produces. This one FETCHES from
// avataaars.io at generation time, so it is run by hand when the cast changes
// and never as part of a build. The app ships the PNGs; nothing reaches
// anything at runtime, which is the whole point of `PredictionDemoBook` and
// the `sample:` scheme.
//
// WHY FACES AT ALL, when the monograms were a deliberate choice. The original
// call (see `make-demo-art.swift`'s Faces section) was that a monogram is what
// a real account without a photo actually looks like, and that it is
// "obviously not a photograph of a person who doesn't exist". Both halves of
// that still hold — and an illustrated avatar satisfies BOTH better than a
// letter does: nobody mistakes a drawing for a photograph, and a real social
// roster is a column of faces, not a column of initials. The monogram was the
// right answer to "don't fake a person"; it was the wrong answer to "show what
// this room looks like when it is full".
//
// PUBLICATIONS KEEP THEIR MONOGRAMS and are deliberately not in this cast.
// `RSSIngest` stamps a site's FAVICON on `authorAvatarURL`, so The Verge and
// Hacker News are marks, not people. Giving them a face would say a person
// wrote for us.
//
// Avataaars is Pablo Stanley's illustration set; avataaars.io is the renderer.
// Each request returns SVG, which AppKit rasterizes.

import AppKit

struct Face {
    let handle: String     // matches `DemoSeedAll.avatarArt(_:)`, minus any "@"
    let note: String       // which part of the demo this person is
    let query: String
}

// One config per person, deliberately varied — same hair on two accounts in one
// room reads as a rendering bug rather than two people.
let cast: [Face] = [
    .init(handle: "you", note: "the account marked yours",
          query: "topType=ShortHairShortWaved&accessoriesType=Prescription02&hairColor=BrownDark&facialHairType=Blank&clotheType=Hoodie&clotheColor=Blue03&eyeType=Happy&eyebrowType=DefaultNatural&mouthType=Smile&skinColor=Light"),
    .init(handle: "mia", note: "Farcaster — design",
          query: "topType=LongHairCurly&accessoriesType=Blank&hairColor=Black&facialHairType=Blank&clotheType=BlazerShirt&eyeType=Default&eyebrowType=RaisedExcited&mouthType=Smile&skinColor=Brown"),
    .init(handle: "sam", note: "Farcaster — building in the open",
          query: "topType=ShortHairDreads01&accessoriesType=Blank&hairColor=Black&facialHairType=BeardLight&facialHairColor=Black&clotheType=ShirtCrewNeck&clotheColor=PastelGreen&eyeType=Default&eyebrowType=Default&mouthType=Smile&skinColor=DarkBrown"),
    .init(handle: "nils", note: "Bluesky",
          query: "topType=ShortHairTheCaesarSidePart&accessoriesType=Blank&hairColor=Blonde&facialHairType=MoustacheFancy&facialHairColor=Blonde&clotheType=CollarSweater&clotheColor=Heather&eyeType=Squint&eyebrowType=UpDown&mouthType=Twinkle&skinColor=Pale"),
    .init(handle: "uma", note: "Bluesky",
          query: "topType=LongHairStraight2&accessoriesType=Round&hairColor=Auburn&facialHairType=Blank&clotheType=ShirtScoopNeck&clotheColor=Pink&eyeType=Wink&eyebrowType=Default&mouthType=Smile&skinColor=Tanned"),
    // Stocktwits' three. The handles really are @trader0/1/2, so the faces
    // carry the difference the names don't.
    .init(handle: "trader0", note: "Stocktwits",
          query: "topType=ShortHairFrizzle&accessoriesType=Sunglasses&hairColor=Black&facialHairType=Blank&clotheType=GraphicShirt&clotheColor=Gray01&eyeType=Default&eyebrowType=Default&mouthType=Serious&skinColor=Brown"),
    .init(handle: "trader1", note: "Stocktwits",
          query: "topType=Hat&accessoriesType=Blank&facialHairType=BeardMedium&facialHairColor=Auburn&clotheType=ShirtVNeck&clotheColor=Red&eyeType=Squint&eyebrowType=UpDownNatural&mouthType=Serious&skinColor=Light"),
    .init(handle: "trader2", note: "Stocktwits",
          query: "topType=LongHairBob&accessoriesType=Prescription01&hairColor=Platinum&facialHairType=Blank&clotheType=CollarSweater&clotheColor=Blue02&eyeType=Default&eyebrowType=Default&mouthType=Default&skinColor=Pale"),
    // The X archive's liked-post authors.
    .init(handle: "lindsey", note: "X — liked",
          query: "topType=LongHairMiaWallace&accessoriesType=Blank&hairColor=Red&facialHairType=Blank&clotheType=Overall&clotheColor=PastelBlue&eyeType=Happy&eyebrowType=RaisedExcitedNatural&mouthType=Smile&skinColor=Light"),
    .init(handle: "rauno", note: "X — liked",
          query: "topType=ShortHairShortFlat&accessoriesType=Blank&hairColor=SilverGray&facialHairType=Blank&clotheType=ShirtCrewNeck&clotheColor=Black&eyeType=Default&eyebrowType=Default&mouthType=Serious&skinColor=Light"),
    // Twitch's two channels (2026-08-14). `TwitchIngest` reads the streamer's
    // own profile picture, so a real Twitch room is a column of faces with a
    // live frame beside each title.
    .init(handle: "nova", note: "Twitch — live",
          query: "topType=LongHairStraightStrand&accessoriesType=Blank&hairColor=BlondeGolden&facialHairType=Blank&clotheType=ShirtCrewNeck&clotheColor=PastelOrange&eyeType=Happy&eyebrowType=RaisedExcited&mouthType=Smile&skinColor=Light"),
    .init(handle: "kestrel", note: "Twitch — live",
          query: "topType=WinterHat3&accessoriesType=Prescription02&hairColor=Brown&facialHairType=BeardLight&facialHairColor=Brown&clotheType=Hoodie&clotheColor=Gray02&eyeType=Squint&eyebrowType=DefaultNatural&mouthType=Serious&skinColor=Brown"),
    .init(handle: "tufte_bot", note: "X — liked (a bot account, and it has a face like any other)",
          query: "topType=ShortHairSides&accessoriesType=Round&hairColor=Black&facialHairType=Blank&clotheType=GraphicShirt&clotheColor=White&eyeType=Wink&eyebrowType=Default&mouthType=Twinkle&skinColor=Yellow"),
    // The address book (2026-08-26). `ContactsIngest` stamps
    // `CNContact.thumbnailImageData` onto `previewImageData`, so a real
    // Contacts search returns people with faces; the demo's three had none, and
    // `PersonCard` falls back to their INITIALS on a grey disc — the one card
    // in the app whose whole subject is a person, drawn as two letters.
    .init(handle: "ana", note: "Contacts — Ana Kovač",
          query: "topType=LongHairBigHair&accessoriesType=Blank&hairColor=BrownDark&facialHairType=Blank&clotheType=BlazerSweater&eyeType=Default&eyebrowType=Default&mouthType=Smile&skinColor=Light"),
    .init(handle: "samrees", note: "Contacts — Sam Rees (named apart from the Farcaster `sam`: two different people, and one face on both would say otherwise)",
          query: "topType=ShortHairShaggyMullet&accessoriesType=Blank&hairColor=Auburn&facialHairType=BeardMedium&facialHairColor=Auburn&clotheType=ShirtCrewNeck&clotheColor=Blue01&eyeType=Default&eyebrowType=DefaultNatural&mouthType=Serious&skinColor=Light"),
    .init(handle: "mira", note: "Contacts — Mira Novak",
          query: "topType=LongHairFroBand&accessoriesType=Prescription02&hairColor=Black&facialHairType=Blank&clotheType=Overall&clotheColor=Gray01&eyeType=Happy&eyebrowType=RaisedExcited&mouthType=Smile&skinColor=Brown"),
]

/// Regenerating every face on every run rewrites thirteen imagesets to add one,
/// which buries a real change in noise. `ONLY=ana,mira` scopes a run to the
/// handles named; unset, it does the whole cast.
let only: Set<String> = {
    guard let raw = ProcessInfo.processInfo.environment["ONLY"], !raw.isEmpty else { return [] }
    return Set(raw.split(separator: ",").map {
        $0.trimmingCharacters(in: .whitespaces)
    })
}()

let side: CGFloat = 320
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Casberi/Casberi/Assets.xcassets")

func fetch(_ query: String) -> Data? {
    guard let url = URL(string: "https://avataaars.io/?avatarStyle=Circle&" + query) else { return nil }
    var out: Data?
    let sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: url) { data, response, _ in
        if let http = response as? HTTPURLResponse, http.statusCode == 200 { out = data }
        sem.signal()
    }.resume()
    _ = sem.wait(timeout: .now() + 30)
    return out
}

var wrote = 0
for face in cast {
    if !only.isEmpty && !only.contains(face.handle) { continue }
    guard let svg = fetch(face.query), let art = NSImage(data: svg) else {
        FileHandle.standardError.write("✗ \(face.handle) — no render\n".data(using: .utf8)!)
        continue
    }
    // Aspect-FILL into a square: the source is 264×280, and the app draws these
    // through a circular mask, so letterboxing would leave a transparent ring
    // inside the circle. Filling crops a few pixels of shoulder instead.
    let canvas = NSImage(size: NSSize(width: side, height: side))
    canvas.lockFocus()
    let scale = max(side / art.size.width, side / art.size.height)
    let w = art.size.width * scale, h = art.size.height * scale
    art.draw(in: NSRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
    canvas.unlockFocus()

    // PNG, not JPEG: the circle style has transparent corners and JPEG has no
    // alpha, so a JPEG face arrives on a black square.
    guard let tiff = canvas.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("✗ \(face.handle) — encode failed\n".data(using: .utf8)!)
        continue
    }
    let dir = root.appendingPathComponent("sample-avatar-\(face.handle).imageset")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? png.write(to: dir.appendingPathComponent("face.png"))
    // The monogram generator wrote `art.jpg`; a stale one beside the new PNG
    // would leave two files in the imageset and one of them unreferenced.
    try? FileManager.default.removeItem(at: dir.appendingPathComponent("art.jpg"))
    try? """
    {
      "images" : [
        {
          "filename" : "face.png",
          "idiom" : "universal"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    wrote += 1
    print("sample-avatar-\(face.handle)  \(face.note)")
}
print("wrote \(wrote) faces of \(cast.count)")
