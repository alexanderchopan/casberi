import Foundation
import SwiftData
import Testing
import UIKit
@testable import Casberi

/// **No two demo rows draw the same picture** (prd §890).
///
/// Every picture the furnished demo showed was one of four bundled football
/// photographs, handed out by `DemoSeedAll.art(n % 4)` to thirty-odd rooms —
/// a Figma screenshot, a Lisbon tram timetable, a Radiohead song and a Notion
/// page all wore the same luchador mask, and the prd had called the repetition
/// "by design" (§344). It was the first thing a person scrolling two rooms
/// would notice, and nothing could see it: every room rendered, every check
/// was green, because each room on its own drew exactly what it was given.
///
/// It lives here, not in a `scripts/` harness, because the question is about
/// the POURED rows — `DemoSeedAll.rooms()` builds `Thing`s, and a picture can
/// arrive three ways (a `sample:` URL, an `imageURLs` gallery, or stored bytes
/// on `previewImageData`), so a grep over the seed file would miss the case
/// that actually repeats: two keys whose assets are the same image.
@MainActor
struct DemoPictureTests {

    /// Pictures that SHOULD repeat, because they name one thing that recurs:
    /// a book's cover on each of its highlights (keyed by book on purpose,
    /// `DemoSeedAll.bookCover`), a token's mark on each row about that token.
    /// Faces never reach these fields — they ride `authorAvatarURL`.
    private static let keyedByThing = ["sample:cover-", "sample:token-", "sample:coin-"]

    /// Every picture a row draws: its `sample:` URLs, and its stored bytes.
    /// A screenshot or a file draws its own `sourceRef` in the sheet.
    private static func pictures(of thing: Thing) -> (refs: Set<String>, bytes: Data?) {
        var refs = Set(([thing.previewImageURL].compactMap { $0 } + thing.imageURLs)
            .filter { $0.hasPrefix("sample:") })
        if let ref = thing.sourceRef, ref.hasPrefix("sample:") { refs.insert(ref) }
        refs = refs.filter { ref in !keyedByThing.contains { ref.hasPrefix($0) } }
        return (refs, thing.previewImageData)
    }

    private static func who(_ thing: Thing) -> String {
        "\(thing.source) · \(thing.sourceRef ?? thing.title)"
    }

    @Test func noTwoRowsShareAPictureRef() {
        var owner: [String: String] = [:]
        var clashes: [String] = []
        for thing in DemoSeedAll.rooms() {
            for ref in Self.pictures(of: thing).refs {
                if let first = owner[ref] {
                    clashes.append("\(ref): \(first) and \(Self.who(thing))")
                } else {
                    owner[ref] = Self.who(thing)
                }
            }
        }
        #expect(clashes.isEmpty, "rows sharing a picture:\n\(clashes.joined(separator: "\n"))")
    }

    /// The same question asked of the PIXELS, which is the one a person
    /// actually sees: two keys whose assets are one image, or two rows
    /// storing the same bytes under different refs, are a repeat as surely
    /// as one key used twice.
    @Test func noTwoRowsStoreTheSameImage() {
        var owner: [Data: String] = [:]
        var clashes: [String] = []
        for thing in DemoSeedAll.rooms() {
            guard let bytes = Self.pictures(of: thing).bytes else { continue }
            if let first = owner[bytes] {
                clashes.append("\(first) and \(Self.who(thing))")
            } else {
                owner[bytes] = Self.who(thing)
            }
        }
        #expect(clashes.isEmpty, "rows storing one image:\n\(clashes.joined(separator: "\n"))")
    }

    /// Every `sample:` picture a row names is bundled. `demoSample` no longer
    /// falls back to a stand-in photo, so a key with no asset draws nothing —
    /// this is where that is caught, rather than on a screen.
    @Test func everyNamedPictureIsBundled() {
        var missing: [String] = []
        for thing in DemoSeedAll.rooms() {
            let named = ([thing.previewImageURL, thing.authorAvatarURL].compactMap { $0 }
                + thing.imageURLs + [thing.sourceRef].compactMap { $0 })
                .filter { $0.hasPrefix("sample:") }
            for ref in named where UIImage.demoSample(for: ref) == nil {
                missing.append("\(ref) on \(Self.who(thing))")
            }
        }
        #expect(missing.isEmpty, "unbundled pictures:\n\(missing.joined(separator: "\n"))")
    }
}
