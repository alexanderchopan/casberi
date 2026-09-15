import Foundation
import Observation

/// THE PEOPLE A THING NAMES, kept per thing (prd §772).
///
/// **The gap this closes.** A notice's sentence names a cast — "New post
/// notifications for Roman Storm and 7 others" — and the corpus stored exactly
/// one of them. `XLiveNotifications.actor(from:)` reads `template.from_users`,
/// which is an ARRAY, and takes `.first` by an explicit §707 decision: the row's
/// lead is a 26pt disc, so one face is all it can draw and the headline already
/// says how many there were. That reasoning is correct for a row and wrong for a
/// 316pt lead, which is where the same notice landed once §755/§756 put a cover
/// at the top of every room — eight people named, one face drawn, and 176pt of
/// black under the sentence (user, 2026-09-15: "we made it so there wouldn't be
/// any air on the leads. so for like this, could you show more avatars or
/// something?").
///
/// **Why a store and not a `Thing` field.** `SocialLikers`' reasoning, one seat
/// over, and it holds here for the same two reasons. A cast is a PROPERTY of the
/// notice rather than an event of its own, and a new stored property on `Thing`
/// is a CloudKit Production deploy (`docs/cloudkit-deploy.md`) — a real ship cost
/// for a fact re-read from the network on every foreground sweep. This is bridge
/// state, so it lives where bridge state lives: `UserDefaults`.
///
/// **The cost that buys, stated rather than hidden.** The roster is device-local:
/// it does not sync, and a notice that has scrolled past X's own 40-entry window
/// (§704's finding) can never gain one. Both are the same shape as the likers'
/// roll, and both are honest failures — a lead with no cast falls to the next
/// rung of §772's ladder rather than drawing an empty shelf.
///
/// **Generic on purpose.** Keyed on `Thing.sourceRef`, holding handles and face
/// URLs, with nothing about X in it. X's notice digest is the first caller; a
/// Farcaster "N others liked", a GitHub review roster and a group chat are the
/// same fact and get the same store rather than a second one (§489's rule).
///
/// Unisolated and `@Observable` like `SocialLikers`/`FarcasterStore` beside it:
/// written from the `@MainActor` ingest passes, read from a lead's body,
/// persisted on every change.
@Observable
final class ThingCast {

    static let shared = ThingCast()

    /// How many members a roll KEEPS. `DSLeadCast` draws as many as the width
    /// holds — five at a phone's lead width, seven on a Pro Max in landscape —
    /// so this is that with headroom, and no more: every member past what any
    /// screen can draw is bytes in `UserDefaults` that nothing will ever read.
    static let memberCap = 10

    /// How many things' rolls are kept, oldest evicted first. X's own window is
    /// 40 entries (§704) and a sweep re-reads all of them, so this holds several
    /// windows without letting a long-lived install accumulate one entry per
    /// notice forever.
    static let rollCap = 120

    private static let key = "thing.cast"

    private(set) var rolls: [String: ThingCastRoll]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([String: ThingCastRoll].self, from: data) {
            rolls = saved
        } else {
            rolls = [:]
        }
    }

    /// The cast for a thing, by its `sourceRef`. Present only where a read
    /// actually named more than one person, so a caller needs no test of its own.
    func cast(for ref: String?) -> ThingCastRoll? {
        guard let ref, !ref.isEmpty else { return nil }
        return rolls[ref]
    }

    /// Records what one read saw. `total` is everyone the notice named, which
    /// may exceed what could be resolved — the lead counts the remainder rather
    /// than pretending the roster is complete.
    ///
    /// **A cast of one is never written**, and that is the rule this type turns
    /// on rather than a cap: one person is `authorHandle`/`authorAvatarURL`,
    /// which every row and sheet already draws (§707). A shelf holding a single
    /// face restates the disc six inches above it, so the ladder's next rung is
    /// the honest draw.
    ///
    /// Writes nothing when the roll is unchanged — this runs on every foreground
    /// sweep, and a write per sweep would re-encode the whole book and re-render
    /// every lead reading it for no new information.
    func record(ref: String, members: [ThingCastMember], total: Int, when: Date) {
        let kept = Array(members.filter { !$0.isEmpty }.prefix(Self.memberCap))
        guard !ref.isEmpty, kept.count > 1 else { return }
        let roll = ThingCastRoll(members: kept,
                                 total: max(total, kept.count),
                                 when: when)
        guard rolls[ref] != roll else { return }
        rolls[ref] = roll
        evict()
        persist()
    }

    /// Drops every roll whose ref shares this prefix — teardown, so
    /// disconnecting a seat doesn't leave its rosters to be re-adopted by a
    /// later reconnect (the `FollowerLedger.forget` discipline, and the reason
    /// `SocialLikers` carries the same method).
    func forget(refPrefix: String) {
        let survivors = rolls.filter { !$0.key.hasPrefix(refPrefix) }
        guard survivors.count != rolls.count else { return }
        rolls = survivors
        persist()
    }

    /// The furnished demo's rosters. Refs are the demo's own, so `forgetDemo`
    /// removes exactly these and nothing a real sweep recorded under a real ref.
    /// Not `#if DEBUG` — the demo is a Release-reachable mode (`demo-selftest.py`
    /// check A).
    func seedDemo(_ casts: [(ref: String, members: [ThingCastMember], total: Int)],
                  when: Date = .now) {
        for c in casts {
            record(ref: c.ref, members: c.members, total: c.total, when: when)
        }
    }

    func forgetDemo(refs: [String]) {
        var changed = false
        for ref in refs where rolls.removeValue(forKey: ref) != nil { changed = true }
        if changed { persist() }
    }

    private func evict() {
        guard rolls.count > Self.rollCap else { return }
        let keep = rolls.sorted { $0.value.when > $1.value.when }.prefix(Self.rollCap)
        rolls = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }

    private func persist() {
        // Through `DefaultsWrite` (§721): a `UserDefaults` write posts its
        // notification synchronously, and this is written from an ingest pass
        // while view bodies reading `rolls` are being evaluated.
        guard let data = try? JSONEncoder().encode(rolls) else { return }
        DefaultsWrite.set(data, forKey: Self.key)
    }
}

/// One person in a thing's cast — a name and, where the read carried one, a face.
struct ThingCastMember: Codable, Equatable, Hashable {

    /// The handle, bare (no `@`). A member with neither this nor a face is
    /// dropped at record time.
    var handle: String
    /// The face URL. Optional on purpose: an archive-landed person often has a
    /// handle and no picture, and a named stranger is still a member — the view
    /// falls back the way every other face in the app does.
    var avatarURL: String?

    var isEmpty: Bool {
        handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (avatarURL?.isEmpty ?? true)
    }
}

/// One thing's cast: the people that could be resolved, how many there were in
/// all, and when the read happened.
struct ThingCastRoll: Codable, Equatable {

    /// The members, in the order the source named them — so the face the
    /// sentence leads with leads the shelf. At most `ThingCast.memberCap`.
    var members: [ThingCastMember]
    /// Everyone the notice named, resolved or not. Never below `members.count`.
    var total: Int
    /// When the read happened.
    var when: Date

    /// How many the shelf cannot show once it has drawn `shown` of them. Zero
    /// when the shelf holds the whole cast, which is the case where no counter
    /// is drawn at all — `+0` is the §83 dead control, in a circle.
    func remainder(afterShowing shown: Int) -> Int {
        max(total - shown, 0)
    }
}
