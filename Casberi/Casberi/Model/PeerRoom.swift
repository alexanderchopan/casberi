import Foundation

/// THE PEER ROOM'S HEAD (2026-08-10, prd §348) — which rail your money
/// actually moves on.
///
/// Peer is an on-ramp and an off-ramp, and the room landed its fills as a plain
/// list of them: the §247 gap, in a room where the standing fact is not any one
/// trade. Opening it, the question is not "what was my last fill" — the newest
/// row already says that — it is **which payment rail do I really use, and did
/// anything fall through?** A list newest-first cannot answer either.
///
/// ## It spends nothing
///
/// Every fact here is on a landed row: the `sourceRef` prefix
/// `PeerBridge` stamps, the funding rail it puts on `authorHandle` (§311 — the
/// rail as DATA, added precisely so something could group on it), and
/// `capturedAt`. No request, no new `Thing` property, no CloudKit deploy, no
/// `UserDefaults` — the `StripeRoom`/`CursorRoom` contract, and for its reason:
/// a head that costs a call is a head that can fail, and a room's lede must not
/// be able to fail differently from the rows beneath it.
///
/// ## What it may NOT draw: money
///
/// This card counts fills and never totals them, and that is a hard limit
/// rather than a simplification. `PeerBridge` stamps no `priceValue`, no
/// `transferUSD` and no `transferAmount` — the amount exists only as formatted
/// prose inside each row's title ("Bought 10.03 USDC with Cash App on Peer")
/// and inside the §237 rate line on `enrichedText`. Re-parsing display prose
/// back into arithmetic is the thing `Thing`'s own doc argues against, and it
/// would be worse here than most: the token differs per fill, so a sum over
/// parsed numbers would add USDC to ETH and print the result as one figure.
/// `GnosisPayRoom` states money because its bridge lands `priceValue` and
/// `priceCurrency`; this one cannot, so it does not.
///
/// ## What it may NOT draw: a date for a fall-through
///
/// A fill that expired lands with `capturedAt: .now` — the bridge has no event
/// to date it by, because nothing happened on chain; the deadline simply
/// passed and we noticed on this pass. So an expired row's timestamp records
/// when WE LOOKED, not when it fell through. Two consequences, both encoded:
/// `newest` is computed over settled fills only (an expired row would make a
/// dormant room read as active this morning), and a fall-through is never
/// dated, never called recent, and never leads the card on recency. It is
/// counted, because the count is real.
///
/// Foundation-only by design so `scripts/wallet-rooms-selftest.sh` can compile
/// it WHOLE and unmodified — the strongest form of "the harness ran the shipped
/// logic". Everything touching `Thing` lives in `PeerRoomSource`.
struct PeerRoom: Equatable {

    // MARK: - What a row is

    /// What a landed Peer row records. Read from the `sourceRef` prefix rather
    /// than from the title, which is localized: a device in Spanish would have
    /// no "Sold" to match, and a room that read every sale as a purchase is the
    /// §83 fake status in the one place it is expensive.
    enum Kind: String, Equatable, CaseIterable {
        /// Fiat in, crypto out — `peer:<hash>`.
        case bought
        /// Crypto in, fiat out — `peer:sell:<hash>`.
        case sold
        /// A buyer's payment never arrived and the crypto came back —
        /// `peer:expired:<hash>`.
        case fellThrough

        /// Whether this row records something that actually settled. A
        /// fall-through settled nothing, which is why it is neither counted as
        /// a fill nor allowed to date the room.
        var settled: Bool { self != .fellThrough }
    }

    /// The `sourceRef` prefixes `PeerBridge` lands, LONGEST FIRST.
    ///
    /// The order is the correctness, not a style: every ref here begins
    /// `peer:`, so testing the bare prefix first would read `peer:sell:0x…` as
    /// a purchase and silently fold the whole sell side into the buy side.
    /// A room reporting that you only ever buy, on an account that mostly
    /// sells, renders perfectly.
    static let prefixes: [(String, Kind)] = [
        ("peer:sell:", .sold),
        ("peer:expired:", .fellThrough),
        ("peer:", .bought),
    ]

    /// Which kind a `sourceRef` records, or nil for anything that is not a
    /// Peer row shape this build knows. Nil is EXCLUDED and counted, never
    /// guessed into a bucket.
    static func kind(ref: String?) -> Kind? {
        guard let ref else { return nil }
        for (prefix, kind) in prefixes where ref.hasPrefix(prefix) { return kind }
        return nil
    }

    /// One landed row, reduced to the three facts this card reads. The source
    /// builds these, so every judgement below is harness-testable with no
    /// `Thing` in sight.
    struct Sighting: Equatable {
        let ref: String?
        /// `Thing.authorHandle` — the funding rail, as data. Nil when the
        /// fill's IntentSignaled event could not be found, and on every
        /// expired row (the bridge stamps no rail there).
        let rail: String?
        let at: Date
    }

    /// One rail's standing, already reduced to what the card draws.
    struct Rail: Identifiable, Equatable {
        /// The rail's own name — what the card hands back, so it never has to
        /// hold a `Thing` (corollary 5).
        var id: String { name }
        let name: String
        let bought: Int
        let sold: Int
        /// Settled fills on this rail. Never includes a fall-through: those
        /// carry no rail at all.
        var fills: Int { bought + sold }
        let newest: Date
    }

    /// Ranked — see `ordered`. Holds EVERY rail, not just the drawn ones, so
    /// the headline and the note can never disagree about how many there are
    /// (the `StripeRoom` bug, caught in its own review).
    let rails: [Rail]
    /// Settled fills that were PLACED on a rail. `unplaced` is not in here.
    let bought: Int
    let sold: Int
    /// Settled fills whose rail could not be named. Counted, never bucketed
    /// into an "Unknown" rail that would then rank beside real ones.
    let unplaced: Int
    /// Sales whose buyer never paid. Counted; never dated — see the type note.
    let fellThrough: Int
    /// The newest SETTLED fill, or nil. Deliberately not the newest row.
    let newest: Date?

    /// Below this the card is not worth drawing: one fill is a row, and the row
    /// already says everything this card would.
    static let minimumFills = 2

    /// Every settled fill. `unplaced` is a SUBSET of this, not a sibling of it —
    /// a fill is counted as bought or sold before its rail is even looked at, so
    /// a fill nobody could place is still a fill. Adding the two would
    /// double-count, and a single unplaced fill would then clear
    /// `minimumFills` on its own and draw a card over one row.
    var fills: Int { bought + sold }
    var lead: Rail? { rails.first }

    /// Nothing worth a card.
    ///
    /// Keyed on SETTLED fills, which INCLUDE the unplaced ones: a room holding
    /// four real fills whose rails we could not name has plenty to say (four
    /// fills, none placed), and hiding the card would leave the person with no
    /// hint that anything is missing. It is `rails.isEmpty` that draws no rows,
    /// not that draws no card.
    var isEmpty: Bool { fills < PeerRoom.minimumFills }

    // MARK: - Composing

    /// The whole card, off landed rows and nothing else.
    static func compose(fills sightings: [Sighting]) -> PeerRoom {
        var bought = 0, sold = 0, unplaced = 0, fellThrough = 0
        var newest: Date?
        // Keyed by the rail's own name, so grouping cannot invent a bucket: a
        // fill with no rail has nowhere to land by construction rather than by
        // remembering to exclude it.
        var buckets: [String: (bought: Int, sold: Int, newest: Date)] = [:]

        for sighting in sightings {
            guard let kind = kind(ref: sighting.ref) else { continue }
            guard kind.settled else { fellThrough += 1; continue }
            // Over SETTLED fills only — an expired row's date is when we
            // looked, not when anything happened.
            if newest == nil || sighting.at > newest! { newest = sighting.at }
            if kind == .bought { bought += 1 } else { sold += 1 }

            let name = sighting.rail?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let name, !name.isEmpty else { unplaced += 1; continue }
            var bucket = buckets[name] ?? (bought: 0, sold: 0, newest: sighting.at)
            if kind == .bought { bucket.bought += 1 } else { bucket.sold += 1 }
            if sighting.at > bucket.newest { bucket.newest = sighting.at }
            buckets[name] = bucket
        }

        let rails = buckets.map { name, bucket in
            Rail(name: name, bought: bucket.bought, sold: bucket.sold, newest: bucket.newest)
        }
        return PeerRoom(rails: ordered(rails), bought: bought, sold: sold,
                        unplaced: unplaced, fellThrough: fellThrough, newest: newest)
    }

    // MARK: - Ranking

    /// Fills, then recency, then name — TOTAL, so two composes over the same
    /// data can never disagree. A card that reshuffles between opens over
    /// identical rows reads as broken, and the dictionary this is built from
    /// has no order of its own to fall back on.
    ///
    /// Ranked by USE and nothing else. There is deliberately no "trouble first"
    /// rung of the kind `CursorRoom` and `StripeRoom` open with, because
    /// nothing on this card is trouble: a rail cannot fail, and the one bad
    /// outcome Peer has — a buyer's payment falling through — carries no rail
    /// to rank.
    static func ordered(_ rails: [Rail]) -> [Rail] {
        rails.sorted { a, b in
            if a.fills != b.fills { return a.fills > b.fills }
            if a.newest != b.newest { return a.newest > b.newest }
            return a.name < b.name
        }
    }

    // MARK: - The bar

    /// A rail's share of the busiest one, 0…1 — the only drawing on this card,
    /// and it encodes ONE thing: how much of your Peer traffic went this way.
    /// Clamped, and zero when there is nothing to compare against (a zero
    /// denominator draws as nothing, which SwiftUI renders as a NaN-width
    /// capsule — the `AgentPanel` lesson).
    ///
    /// It is not a buy/sell split bar: a two-tone bar invites reading the ratio
    /// as a balance somebody chose, and the two counts are stated exactly in
    /// words beside it instead.
    static func share(fills: Int, of top: Int) -> Double {
        guard top > 0 else { return 0 }
        return min(max(Double(fills) / Double(top), 0), 1)
    }

    // MARK: - Days

    /// Whole CALENDAR days, not `timeIntervalSince / 86400` — "nothing for 3
    /// days" means days, so an 11pm read the night after a fill is one day on,
    /// not zero-point-oh-four.
    static func days(from now: Date, to later: Date, calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: now)
        let b = calendar.startOfDay(for: later)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    // MARK: - Words

    static func fillsLabel(_ count: Int) -> String {
        count == 1 ? String(localized: "1 fill") : String(localized: "\(count) fills")
    }

    /// The line beside a rail: which way the money went through it. Both
    /// directions are named when both happened, because a rail you only cash
    /// OUT through and one you only buy with are different facts about your
    /// life, and a bare fill count hides the difference.
    static func railLine(_ rail: Rail) -> String {
        if rail.bought > 0 && rail.sold > 0 {
            return String(localized: "\(rail.bought) in · \(rail.sold) out")
        }
        if rail.sold > 0 {
            return rail.sold == 1 ? String(localized: "1 sale")
                                  : String(localized: "\(rail.sold) sales")
        }
        return rail.bought == 1 ? String(localized: "1 purchase")
                                : String(localized: "\(rail.bought) purchases")
    }

    /// The one line at the top of the card.
    ///
    /// The ranking is a judgement worth stating. Volume leads, because the
    /// standing fact about an on-ramp is which rail carries it — that is what
    /// the room is FOR, and unlike a Stripe deadline or a Cursor failure there
    /// is nothing here that needs you today. A fall-through is real news, but
    /// it is news that already reached the person as a row and as a rain, and
    /// it carries no date this card is allowed to trust, so leading with it
    /// would put a possibly-ancient event at the top forever.
    static func headline(_ room: PeerRoom) -> String {
        guard room.fills > 0 else { return String(localized: "Nothing has settled yet") }
        guard let lead = room.lead else {
            // Real fills, no rail on any of them — say the true thing, which
            // is the count. Naming a rail here is exactly the invention
            // `unplaced` exists to refuse.
            return String(localized: "\(fillsLabel(room.fills)) settled on Peer")
        }
        if room.rails.count > 1 {
            return String(localized: "Mostly \(lead.name) — \(fillsLabel(room.fills)) across \(room.rails.count) rails")
        }
        return String(localized: "\(fillsLabel(room.fills)) settled through \(lead.name)")
    }

    /// The line under it. Never a restatement of the headline: the headline
    /// carries the rail and the volume, so this carries the DIRECTION — which
    /// way the room's money actually flows, summed across every rail.
    static func note(_ room: PeerRoom) -> String {
        if room.bought > 0 && room.sold > 0 {
            return String(localized: "\(room.bought) bought · \(room.sold) sold")
        }
        if room.sold > 0 { return String(localized: "Cashing out — \(room.sold) sold, nothing bought") }
        if room.bought > 0 { return String(localized: "Buying only — \(room.bought) in, nothing sold") }
        return String(localized: "Nothing has settled yet")
    }

    /// The quiet line at the foot: rails not drawn, fills that could not be
    /// placed, sales that fell through, and how long the room has been still.
    /// Any of them, all of them, or nothing.
    ///
    /// The unplaced clause is not optional politeness — a fill this card cannot
    /// place is a fill missing from every rail above it, and a total that
    /// silently omits rows is the failure the import drop counters exist to
    /// prevent, one room over.
    static func footnote(_ room: PeerRoom, drawn: Int, now: Date = .now) -> String? {
        var parts: [String] = []
        let hidden = room.rails.count - drawn
        if hidden > 0 {
            parts.append(hidden == 1 ? String(localized: "1 more rail")
                                     : String(localized: "\(hidden) more rails"))
        }
        if room.unplaced > 0 {
            parts.append(room.unplaced == 1
                         ? String(localized: "1 fill has no rail")
                         : String(localized: "\(room.unplaced) fills have no rail"))
        }
        if room.fellThrough > 0 {
            // Never "recently" and never dated — see the type note.
            parts.append(room.fellThrough == 1
                         ? String(localized: "1 sale fell through")
                         : String(localized: "\(room.fellThrough) sales fell through"))
        }
        if let idle = idleNote(newest: room.newest, now: now) { parts.append(idle) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "nothing for 21 days" — said only once the quiet is long enough to mean
    /// something. Under the threshold it says nothing, because a room that
    /// traded last week needs no explanation and a card narrating every
    /// ordinary gap is a card people stop reading.
    ///
    /// The threshold is deliberately far longer than `CursorRoom`'s week: an
    /// on-ramp is used when you need it, and a fortnight without buying crypto
    /// is not a fact about anything.
    static func idleNote(newest: Date?, now: Date = .now, quietAfter: Int = 30) -> String? {
        guard let newest else { return nil }
        let days = days(from: newest, to: now)
        guard days >= quietAfter else { return nil }
        return String(localized: "nothing for \(days) days")
    }
}
