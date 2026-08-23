import Foundation

/// Whether the feeds behind a reading room are still answering — said in the
/// ROOM, where the silence actually shows (2026-08-23, prd §455).
///
/// WHY THIS EXISTS. `FeedFreshness.trouble(for:)` has been able to say "hasn't
/// answered in 12 days" since 2026-08-05, and it said it in exactly one place:
/// the bridge's own setup screen, which is a screen you visit to ADD a feed
/// and then never open again. The room is where the consequence lands, and in
/// the room a feed that has gone quiet and a feed that has DIED are the same
/// thing — rows that stopped growing. §312 built the observation and left it
/// somewhere nobody stands.
///
/// SILENT BY DEFAULT, which is most of the time and the whole reason this can
/// be a room-level line at all: a healthy room says nothing, so the note is
/// never chrome. It appears when the app has genuinely observed a feed failing
/// repeatedly (see `FeedFreshness.troubleAfter` — three consecutive misses
/// spanning three days, a floor measured against YouTube's throttle-404s).
///
/// IT NEVER SAYS A FEED IS GONE, inheriting `trouble`'s own discipline: a
/// status code cannot support that claim. One feed is named with the
/// observation `trouble` made about it; several are COUNTED with a line that
/// says only that they want looking at, because their reasons differ (an
/// address that never answered and a blog quiet for a week are not one fact)
/// and a count that picked one reason to print would be applying it to feeds
/// it does not describe.
///
/// PURE, and `trouble` is injected rather than called: this file is
/// Foundation-only by design so `scripts/feed-reading-selftest.sh` can compile
/// it WHOLE and unmodified. `FeedFreshness` reads UserDefaults, and a harness
/// cannot make a publisher stop answering.
///
/// STATED CEILING. A follow whose feed URL was never resolved — a YouTube
/// `@handle` that has not synced yet, so `FeedFollowEntry.feedURL` is empty —
/// is EXCLUDED rather than counted as troubled. `FeedFreshness` is keyed by
/// URL, so there is no record to read and therefore no observation to report,
/// and inventing one would be a claim about a feed the app has never asked
/// for. It reads as healthy until the first sync gives it an address to fail
/// at, which is one sync of silence and the honest cost of never guessing.
enum FeedRoomHealth {

    /// One followed feed, as the room knows it. A `(name, url)` pair rather
    /// than either store's own type, because five bridges keep two different
    /// structs and this reads the same fact from both.
    struct Feed: Equatable {
        let name: String
        let url: String

        init(name: String, url: String) {
            self.name = name
            self.url = url
        }
    }

    struct Standing: Equatable {
        /// The display names the verdict is about, in the order given.
        let quiet: [String]
        /// The line the room draws.
        let line: String
    }

    /// What the room should say about its own feeds, or nil for nothing —
    /// which is the common case.
    ///
    /// `trouble` is `FeedFreshness.trouble(for:)` in the app and a fixture in
    /// the harness. A feed with no URL is skipped before it is ever asked
    /// about; see the type doc.
    static func standing(feeds: [Feed],
                         trouble: (String) -> String?) -> Standing? {
        // Name and reason are carried TOGETHER rather than the reason being
        // accumulated beside the list. The first shape of this kept a
        // `firstReason` variable, and the harness proved it untestable: a
        // reason is only ever printed when exactly one feed is troubled, so
        // first and last are the same value by construction and no fixture
        // could tell a correct accumulator from a broken one. Pairing them
        // deletes the question.
        var quiet: [(name: String, reason: String)] = []
        for feed in feeds {
            let url = feed.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { continue }
            guard let reason = trouble(url) else { continue }
            // The name a person gave or the feed learned, never the raw URL:
            // this line is read at a glance in a room, and a line beginning
            // "https://…" is plumbing quoted at somebody.
            let name = feed.name.trimmingCharacters(in: .whitespacesAndNewlines)
            quiet.append((name.isEmpty ? url : name, reason))
        }
        guard !quiet.isEmpty else { return nil }
        // ONE feed carries its own observed reason; SEVERAL are counted
        // without one — see the type doc for why their reasons are not merged.
        // The count is of TROUBLED feeds, never of feeds followed: this line
        // is read as "how much is broken", and the follow count would say
        // everything is.
        let line: String
        if quiet.count == 1 {
            line = String(localized: "\(quiet[0].name) · \(quiet[0].reason)")
        } else {
            line = String(localized: "\(quiet.count.formatted()) feeds need a look")
        }
        return Standing(quiet: quiet.map(\.name), line: line)
    }
}
