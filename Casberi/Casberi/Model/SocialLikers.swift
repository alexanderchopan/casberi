import Foundation
import Observation

/// WHO liked one of your posts, kept per post (2026-08-07, prd §330).
///
/// **The gap this closes.** §239 built the inbound half and stated its own
/// rule — "names, not numbers" — but only half of it ever reached a screen.
/// `readLikes` on both networks filled the post's `likeCount` and then threw
/// every liker's identity away, except when the liker happened to be an
/// account you already WATCH, and even then the only output was a toast that
/// scrolled past in a second and landed nothing. So
/// "who liked my posts?" — the plainest question this half exists to answer —
/// had no answer anywhere in the app, on either network. Farcaster had it
/// worse still: `Notifications.likes` (the §306 "Liked by paulg and 2 others"
/// notification, written to be called from the read itself, because the names
/// exist nowhere else) was wired for Bluesky and never for Farcaster, so a
/// Farcaster like was a bare integer end to end.
///
/// **Why a store and not a `Thing` field.** Two reasons, and they point the
/// same way. §239's module doctrine is explicit that a like never lands as a
/// record — it is a PROPERTY of your post, not an event of its own — and a new
/// stored property on `Thing` is a CloudKit Production deploy (see
/// `docs/cloudkit-deploy.md`), which is a real ship cost for a fact that is
/// re-read from the network on every foreground pass anyway. This is bridge
/// state, so it lives where every other bridge reading lives: `UserDefaults`,
/// the `ASCState`/`X402State` shape.
///
/// **Bounded on both axes.** `nameCap` bounds what a pass has to RESOLVE —
/// Bluesky hydrates a liker's handle inline (free), but Snapchain's
/// `reactionsByCast` reports fids only, so a name there costs one
/// `userDataByFid` each and naming a hundred of them per post would be a
/// hundred requests to write one line. Three names is what the line can show
/// anyway. `rollCap` bounds what is KEPT: the reads only ever ask about your
/// own recent posts (`SocialInbound.ownPostPage`), so the working set is
/// already small, and the oldest roll is evicted rather than letting a
/// long-lived install accumulate one entry per post forever.
///
/// **A roll with no names is never written.** A total with nobody named is the
/// tally the doctrine forbids, and it is also what the sheet's engagement line
/// already shows. If not one liker could be resolved, this says nothing.
/// Unisolated and `@Observable`, exactly like `FarcasterStore`/`BlueskyStore`
/// beside it: written from the `@MainActor` ingest passes, read from a row's
/// body, persisted to `UserDefaults` on every change.
@Observable
final class SocialLikers {

    static let shared = SocialLikers()

    /// How many likers a roll NAMES. Also the cap on how many profile lookups
    /// the Farcaster read pays per post — see the note above.
    static let nameCap = 3

    /// How many posts' rolls are kept, oldest evicted first.
    static let rollCap = 60

    private static let key = "social.likers"

    private(set) var rolls: [String: SocialLikeRoll]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([String: SocialLikeRoll].self, from: data) {
            rolls = saved
        } else {
            rolls = [:]
        }
    }

    /// The roll for a post, by its `sourceRef`. Present only for posts the
    /// inbound read has actually asked about — which is only ever your own —
    /// so a caller needs no "is this mine?" test of its own.
    func roll(for ref: String?) -> SocialLikeRoll? {
        guard let ref, !ref.isEmpty else { return nil }
        return rolls[ref]
    }

    /// Records what one read saw. `total` is every liker the page carried (your
    /// own like excluded by the caller); `atLeast` says the page was full, so
    /// the total is a floor rather than a count — `SocialCount`'s honesty valve
    /// in the one place a number is spoken out loud.
    ///
    /// Writes nothing when nobody could be named, and nothing when the roll is
    /// unchanged — this runs on every foreground pass, and a write per pass
    /// would re-encode the whole book and re-render every social row for no new
    /// information.
    func record(ref: String, handles: [String], total: Int, atLeast: Bool, when: Date) {
        let named = Array(handles.prefix(Self.nameCap))
        guard !ref.isEmpty, !named.isEmpty else { return }
        let roll = SocialLikeRoll(handles: named,
                                  total: max(total, named.count),
                                  atLeast: atLeast,
                                  when: when)
        guard rolls[ref] != roll else { return }
        rolls[ref] = roll
        evict()
        persist()
    }

    /// Drops every roll for a source whose refs share this prefix — teardown,
    /// so disconnecting an account doesn't leave its rolls to be re-adopted by
    /// a later reconnect (the `FollowerLedger.forget` discipline).
    func forget(refPrefix: String) {
        let survivors = rolls.filter { !$0.key.hasPrefix(refPrefix) }
        guard survivors.count != rolls.count else { return }
        rolls = survivors
        persist()
    }

    private func evict() {
        guard rolls.count > Self.rollCap else { return }
        let keep = rolls.sorted { $0.value.when > $1.value.when }.prefix(Self.rollCap)
        rolls = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(rolls) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}

/// One post's likers: a few names, how many there were in all, and when the
/// newest of them arrived.
struct SocialLikeRoll: Codable, Equatable {

    /// The newest likers, newest first, at most `SocialLikers.nameCap`.
    var handles: [String]
    /// Every liker the read saw, named or not. Never below `handles.count`.
    var total: Int
    /// The page was full, so `total` is a floor — rendered as "97+ others"
    /// rather than a number nobody counted.
    var atLeast: Bool
    /// When the newest like arrived, as the network reported it.
    var when: Date

    /// The line a row shows, or nil when there is nothing honest to say.
    ///
    /// Names lead, always — the whole point of §239's rule is that "3 people
    /// liked your post" is a tally and "Liked by @alice and 2 others" is
    /// people. The unnamed remainder is counted, never named, and a full page
    /// says so with a `+` rather than quoting a total the read couldn't reach.
    var line: String? {
        let named = handles.filter { !$0.isEmpty }
        guard !named.isEmpty else { return nil }
        let others = max(total - named.count, 0)
        let names = named.map { "@\($0)" }
        // "@a", "@a and @b", "@a, @b and @c" — one branch for the last join,
        // because the two-name case IS the general case with an empty comma
        // list, and spelling it separately only invents a second string to
        // translate.
        let lead = names.count == 1 ? names[0]
            : String(localized: "\(names.dropLast().joined(separator: ", ")) and \(names[names.count - 1])")
        // `atLeast` deliberately does NOT open this gate: a full page means at
        // least `total` likers and `total` exceeds `nameCap` by construction,
        // so `others` is already large — testing it here too would only let a
        // "and 0+ others" through if that ever stopped being true.
        guard others > 0 else { return String(localized: "Liked by \(lead)") }
        if others == 1, !atLeast { return String(localized: "Liked by \(lead) and 1 other") }
        // A full page can't say how many MORE there were, only that there were
        // more — so the count it does quote wears a `+`.
        let rest = atLeast ? "\(others)+" : "\(others)"
        return String(localized: "Liked by \(lead) and \(rest) others")
    }
}
