import Foundation
import Testing
@testable import Casberi

/// **The demo is one person's life, not one subject in every room** (prd §1026).
///
/// Every picture the demo drew was its own file by 2026-09-23 (§890), and it
/// still read as the same room twice: espresso landed 45 times across eleven
/// rooms — all eight TikTok rows, three of eight YouTube videos, three Photos
/// screenshots, the podcasts, a ChatGPT chat — and Lisbon 31 times across ten.
/// No row was a copy of another; the SUBJECT was. Nothing could see it, because
/// each room was written on its own to fill its own topic map, by picking two
/// or three tag words and starting each title with one ("Espresso — grind
/// chart", "Shipping small beats planning big", "Shipping again this week").
///
/// Asked of the POURED rows, like `DemoPictureTests`, because `ocrTopics` is
/// what a room's topic map draws and what a person reads as "what this room is
/// about".
@MainActor
struct DemoSpreadTests {

    /// How many rooms one topic may appear in. Two lets a thread cross on
    /// purpose — the Lisbon trip is in Photos and Instagram, the books in
    /// Obsidian and Bluesky — while a third room is a subject the whole demo
    /// is about.
    private static let roomsPerTopic = 2

    /// How many of one room's rows may open with the same one of that room's
    /// topics. A topic map's rows are written to feed it, and the cheap way to
    /// do that is to lead every title with the tag.
    private static let rowsPerLead = 2

    private static var topical: [Thing] {
        DemoSeedAll.rooms().filter { !$0.ocrTopics.isEmpty }
    }

    @Test func noTopicSpansMoreThanTwoRooms() {
        var rooms: [String: Set<String>] = [:]
        for thing in Self.topical {
            for topic in thing.ocrTopics {
                rooms[topic.lowercased(), default: []].insert(thing.source)
            }
        }
        let wide = rooms.filter { $0.value.count > Self.roomsPerTopic }
            .map { "\($0.key): \($0.value.sorted().joined(separator: ", "))" }
            .sorted()
        #expect(wide.isEmpty, "topics in more than \(Self.roomsPerTopic) rooms:\n\(wide.joined(separator: "\n"))")
    }

    @Test func noRoomLeadsItsTitlesWithOneWord() {
        var topics: [String: Set<String>] = [:]
        for thing in Self.topical {
            topics[thing.source, default: []].formUnion(thing.ocrTopics.map { $0.lowercased() })
        }
        var leads: [String: [String: Int]] = [:]
        for thing in Self.topical {
            // A reply's title is the bridge's own "To @handle · text"; the
            // words someone wrote start after the dot.
            var title = Substring(thing.title)
            if title.hasPrefix("To @"), let dot = title.range(of: " · ") {
                title = title[dot.upperBound...]
            }
            guard let first = title.split(separator: " ").first else { continue }
            let word = first.lowercased().trimmingCharacters(in: .punctuationCharacters)
            guard topics[thing.source, default: []].contains(word) else { continue }
            leads[thing.source, default: [:]][word, default: 0] += 1
        }
        let samey = leads.flatMap { source, words in
            words.filter { $0.value > Self.rowsPerLead }.map { "\(source): \"\($0.key)\" × \($0.value)" }
        }.sorted()
        #expect(samey.isEmpty, "rooms whose titles open with one of their topics:\n\(samey.joined(separator: "\n"))")
    }

    /// The checks above can only fail if the demo carries topic rows at all.
    @Test func theDemoHasTopicRooms() {
        #expect(Set(Self.topical.map(\.source)).count >= 6)
    }
}
