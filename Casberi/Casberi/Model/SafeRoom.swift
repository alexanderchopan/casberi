import Foundation

/// THE SAFE ROOM'S HEAD (2026-08-11, prd §349 amendment) — the signature
/// queue as rings, ranked by who it's actually waiting on.
///
/// Safe is the only wallet-riding seat where OTHER PEOPLE act on your behalf
/// and you wait on them (`SafeQueueCard`'s own framing, one screen deeper).
/// A plain list of "N of M signatures collected" rows answers "what's
/// pending" one row at a time; this answers the standing question — is
/// anything waiting on ME right now, and how long has the oldest thing been
/// sitting there.
///
/// ## It spends nothing
///
/// Every fact here comes off `SafeBridge.pendingSnapshot()` — the SAME
/// tracking store `SafeBridge.sync` already keeps to know when a pending
/// transaction resolves (its loop-closer, prd §349's own amendment (5)/(8)),
/// upserted with `have`/`required`/`yourTurn`/`submittedAt`/a cached
/// description every pass regardless of whether a new `Thing` landed. No
/// request, no new `Thing` property, no CloudKit deploy — the
/// `StripeRoom`/`CursorRoom` contract.
///
/// ## What it may NOT draw: a live recheck
///
/// The counts here are AS OF THE LAST SYNC PASS, not a fresh read — same as
/// every sibling room head. A tap opens the real thing, whose sheet
/// (`SafeQueueCard`) does the live re-check this card deliberately doesn't
/// pay for.
///
/// ## What it may NOT draw: the full signer roster
///
/// `SafeQueueCard` already draws every owner's face, lit or dim — that is
/// SHEET detail, reached by a tap on a specific transaction. This card is a
/// glance across every Safe at once; drawing a face row per pending item
/// would be the sheet's own card duplicated N times at 1/3 the size.
///
/// Foundation-only by design so `scripts/wallet-rooms-selftest.sh` can
/// compile it WHOLE and unmodified. Everything touching `Thing`/`SafeBridge`
/// lives in `SafeRoomSource`.
struct SafeRoom: Equatable {

    // MARK: - What a row is

    /// One currently-open pending transaction, reduced to what the card
    /// reads.
    struct Entry: Identifiable, Equatable {
        var id: String { ref }
        let ref: String
        let safeAddress: String
        let have: Int
        let required: Int
        /// True only when reached via a signer's own watched EOA and that
        /// signer hasn't signed yet — a directly-watched Safe can't say
        /// which of its N owners is "you" (`SafeBridge.describe`'s own
        /// rule, mirrored here).
        let yourTurn: Bool
        /// Safe's own `submissionDate` for the transaction — nil only when
        /// the wire didn't carry one. Real waiting time, not app-observed.
        let submittedAt: Date?
        /// "a transfer of 1,500 USDC to alice.eth" — `SafeBridge.describe`'s
        /// own rendering, cached at tracking time so this card never
        /// recomputes it.
        let descriptionText: String
    }

    /// Ranked — see `ordered`.
    let entries: [Entry]
    /// Every Safe this app has ever confirmed real for the watched wallets
    /// (`SafeBridge.detectedCount()`) — the standing inventory this card
    /// reports on, independent of whether any of them currently has
    /// something pending.
    let safeCount: Int
    /// Modules currently enabled across every detected Safe — funds movable
    /// WITHOUT a signature, the highest-stakes fact this bridge can state
    /// (`SafeBridge`'s own top-of-file doc).
    let moduleCount: Int

    var pendingCount: Int { entries.count }
    var yourTurnCount: Int { entries.filter(\.yourTurn).count }
    var lead: Entry? { entries.first }

    /// Below this the card is not worth drawing: no Safe was ever detected
    /// at all, so there is nothing to report on, standing or pending.
    var isEmpty: Bool { safeCount == 0 }

    // MARK: - Composing

    static func compose(entries raw: [Entry], safeCount: Int, moduleCount: Int) -> SafeRoom {
        SafeRoom(entries: ordered(raw), safeCount: safeCount, moduleCount: moduleCount)
    }

    // MARK: - Ranking

    /// Your turn first (the thing only you can unblock), then longest-
    /// waiting first within each group, then the ref for stability when two
    /// entries carry the same or no `submittedAt` — TOTAL, the
    /// `PeerRoom.ordered`/`RailgunRoom.ordered` reasoning: a card that
    /// reshuffles between opens over identical data reads as broken.
    static func ordered(_ entries: [Entry]) -> [Entry] {
        entries.sorted { a, b in
            if a.yourTurn != b.yourTurn { return a.yourTurn && !b.yourTurn }
            let da = a.submittedAt ?? .distantPast
            let db = b.submittedAt ?? .distantPast
            if da != db { return da < db }
            return a.ref < b.ref
        }
    }

    // MARK: - Words

    /// The one line at the top of the card. "Your turn" always leads when
    /// there is one — the shape of news nothing else in this app carries:
    /// somebody else is waiting on a decision only you can make.
    static func headline(_ room: SafeRoom) -> String {
        if room.yourTurnCount > 0 {
            return room.yourTurnCount == 1
                ? String(localized: "Your signature is needed on 1 transaction")
                : String(localized: "Your signature is needed on \(room.yourTurnCount) transactions")
        }
        if room.pendingCount > 0 {
            return room.pendingCount == 1
                ? String(localized: "1 signature pending — waiting on others")
                : String(localized: "\(room.pendingCount) signatures pending — waiting on others")
        }
        return room.safeCount == 1
            ? String(localized: "Nothing pending on your Safe")
            : String(localized: "Nothing pending across your \(room.safeCount) Safes")
    }

    /// The line under it — the module warning, when there is one. Nil rather
    /// than restating the headline's own count, the `RailgunRoom.note`
    /// shape: a second sentence earns its place only when it says something
    /// new.
    static func note(_ room: SafeRoom) -> String? {
        guard room.moduleCount > 0 else { return nil }
        return room.moduleCount == 1
            ? String(localized: "1 module can move funds without a signature")
            : String(localized: "\(room.moduleCount) modules can move funds without a signature")
    }

    /// "today" / "1 day" / "N days" — how long a pending entry has waited,
    /// off Safe's own `submissionDate`. "waiting" when the wire carried none
    /// — never a fabricated duration.
    static func waitLabel(_ entry: Entry, now: Date = .now) -> String {
        guard let submittedAt = entry.submittedAt else { return String(localized: "waiting") }
        let days = max(0, Int(now.timeIntervalSince(submittedAt) / 86_400))
        if days == 0 { return String(localized: "today") }
        if days == 1 { return String(localized: "1 day") }
        return String(localized: "\(days) days")
    }

    /// The card draws at most this many entries; the rest are counted in
    /// the footnote rather than silently dropped.
    static let rowCap = 3

    /// The quiet line at the foot: pending entries not drawn.
    static func footnote(_ room: SafeRoom, drawn: Int) -> String? {
        let hidden = room.entries.count - drawn
        guard hidden > 0 else { return nil }
        return hidden == 1 ? String(localized: "1 more pending")
                           : String(localized: "\(hidden) more pending")
    }
}
