import Foundation
import SwiftData

/// The Privacy Pools room head's reading half (2026-08-10, prd §349; widened
/// 2026-08-17, prd §397) — landed rows turned into the card's own value, with
/// every judgement left to `PrivacyPoolsRoom`.
///
/// The split is `CursorRoomSource`'s. Everything that could be wrong in a way
/// that still renders perfectly — an alert counted as a second deposit, a
/// deposit with no state tag reported as pending, a stuck deposit ranked below
/// forty cleared ones, a reclaimed deposit still demanding to be reclaimed —
/// lives on the other side of that line, in a file the harness compiles whole.
enum PrivacyPoolsRoomSource {

    /// The bridge's own source name, taken from the bridge rather than spelled
    /// again — see `PeerBridge.sourceName`.
    static let source = PrivacyPoolsBridge.sourceName

    /// The head, or nil when there is nothing worth drawing.
    @MainActor
    static func compose(things: [Thing] = [], now: Date = .now) -> PrivacyPoolsRoom? {
        // Live at the BOUNDARY, before any stored property is read
        // (corollary 4).
        let rows = things.live.filter { $0.source == source }
        guard !rows.isEmpty else { return nil }
        let room = PrivacyPoolsRoom.compose(rows: rows.map(sighting),
                                            covers: covers(rows: rows))
        return room.isEmpty ? nil : room
    }

    /// One landed row, reduced to what the head reads. The ONLY place a `Thing`
    /// is touched.
    ///
    /// `priceValue`/`priceCurrency` are read as DATA — never `transferAmount`,
    /// which is a rounded display string whose thousands separator is
    /// locale-dependent, and never the title, which is prose
    /// (`GnosisPayRoomSource`'s rule, and the reason §349 could not state a
    /// figure at all until the bridge started stamping this pair).
    @MainActor
    private static func sighting(_ thing: Thing) -> PrivacyPoolsRoom.Sighting {
        PrivacyPoolsRoom.Sighting(ref: thing.sourceRef,
                                  tags: thing.tags,
                                  asset: thing.priceCurrency,
                                  amount: thing.priceValue,
                                  at: thing.capturedAt)
    }

    /// The anonymity-set readings, one per pool we have a number for
    /// (prd §397). Empty until the bridge's once-a-day refresh has run at
    /// least once, which is a real state and not an error — the card simply
    /// says nothing about cover.
    ///
    /// `atLanding` is the snapshot taken when the person's FIRST deposit in
    /// that pool landed, which is what makes "up from" mean "since you got
    /// in". Deliberately the oldest deposit rather than the newest: the growth
    /// worth stating is the cover a standing deposit has accumulated, and
    /// keying on the newest would reset that claim to near-zero every time
    /// somebody deposits again.
    ///
    /// It is also deliberately NOT restricted to deposits still in the pools.
    /// The sentence says "when you first deposited", which stays true of a
    /// deposit later reclaimed, and excluding those would make the baseline
    /// jump forward the day an old deposit is taken out — a growth figure that
    /// shrinks because you withdrew is a wrong reading of a right number.
    @MainActor
    private static func covers(rows: [Thing]) -> [PrivacyPoolsRoom.Cover] {
        let current = PrivacyPoolsCover.current()
        guard !current.isEmpty else { return [] }
        var firstDeposit: [String: (at: Date, label: String)] = [:]
        for thing in rows {
            guard let ref = thing.sourceRef,
                  ref.hasPrefix(PrivacyPoolsRoom.depositPrefix),
                  let label = PrivacyPoolsRoom.label(ref: ref),
                  let symbol = thing.priceCurrency, !symbol.isEmpty else { continue }
            let at = thing.capturedAt
            if let known = firstDeposit[symbol], known.at <= at { continue }
            firstDeposit[symbol] = (at, label)
        }
        return current.compactMap { symbol, count -> PrivacyPoolsRoom.Cover? in
            guard count > 0 else { return nil }
            let landed = firstDeposit[symbol]
                .flatMap { PrivacyPoolsCover.landingCount(label: $0.label) }
            return PrivacyPoolsRoom.Cover(symbol: symbol, current: count,
                                          atLanding: landed)
        }
    }

    /// The probe's lines — driven by `-privacyPoolsRoomProbe`, calling the REAL
    /// `compose`.
    ///
    /// It exists because a wrong-looking head here has causes that render
    /// identically, and one of them shipped for months:
    ///
    ///   1. no wallet is watched, so the seat never ran;
    ///   2. the watched wallets have never deposited — the healthy common case;
    ///   3. every deposit really IS pending, because the ASP has not ruled;
    ///   4. **the state tag is not moving** — §311 shipped `retag` looking up a
    ///      `sourceRef` spelled `privacypools:deposit:` while deposits land
    ///      under `privacypools:dep:`, so from §311 until 2026-08-10 every
    ///      deposit on every device read `Pending` for life, including cleared
    ///      ones. Nothing could see it: the alert row still landed and still
    ///      rained, and the tag nobody read was the only casualty;
    ///   5. deposits predating the tag entirely, which are `untagged` and must
    ///      never be counted as pending;
    ///   6. deposits predating `priceValue`/`priceCurrency` (prd §397), which
    ///      are `unpriced` — the room says how many deposits it has and
    ///      refuses to say how much, which reads exactly like a broken money
    ///      line;
    ///   7. no cover reading yet, because the once-a-day refresh has not run
    ///      or `pools-stats` was unreachable.
    ///
    /// 3, 4, 5 and 6 are the same card. Hence one line PER ROW naming its ref
    /// shape, its tags AND its stamped pair (the `-todayProbe` truncation
    /// lesson), so "pending because the screener is slow" can be told from
    /// "pending because nothing ever writes anything else", and "no money line
    /// because these are old rows" from "no money line because the stamp
    /// broke".
    @MainActor
    static func probeLines(things: [Thing], now: Date = .now) -> [String] {
        let rows = things.live.filter { $0.source == source }
        var out: [String] = [
            "privacyPoolsRoom| source=\(source) handed=\(things.count)"
                + " ppRows=\(rows.count) states=\(PrivacyPoolsRoom.states.joined(separator: "/"))",
        ]
        // The reclaim join, printed before the rows so a row reading
        // `deposit(Declined)` beside a label in this set is legible as the
        // card correctly overriding a stale tag rather than as a disagreement.
        let sightings = rows.map(sighting)
        let reclaimedLabels = PrivacyPoolsRoom.reclaimedLabels(sightings)
        out.append("privacyPoolsReclaimJoin| labels=[\(reclaimedLabels.sorted().joined(separator: ","))]")
        for sight in sightings.sorted(by: { $0.at > $1.at }) {
            let shape: String
            switch PrivacyPoolsRoom.row(ref: sight.ref, tags: sight.tags) {
            case .deposit(let state): shape = "deposit(\(state?.rawValue ?? "UNTAGGED"))"
            case .reclaimed:          shape = "reclaimed"
            // Counted nowhere BY DESIGN — an alert is news about a deposit the
            // card already counts, and counting it would report a cleared
            // deposit twice.
            case .alert:              shape = "alert (not counted)"
            case .none:               shape = "UNRECOGNISED"
            }
            let outOfPool = PrivacyPoolsRoom.label(ref: sight.ref)
                .map { reclaimedLabels.contains($0) } ?? false
            out.append("privacyPoolsRow| \(shape)"
                       + " tags=[\(sight.tags.joined(separator: ","))]"
                       + " asset=\(sight.asset ?? "UNPRICED")"
                       + " amount=\(sight.amount.map { String($0) } ?? "unknown")"
                       + " reclaimed=\(outOfPool ? "YES" : "no")"
                       + " at=\(sight.at.formatted(.iso8601))"
                       + " ref=\(sight.ref ?? "none")")
        }
        // The cover store, printed whether or not a card composes — an empty
        // store and an unreachable host look identical on screen.
        let store = PrivacyPoolsCover.current()
        out.append("privacyPoolsCoverStore| pools=\(store.count)"
                   + " lastRead=\(PrivacyPoolsCover.lastRead?.formatted(.iso8601) ?? "never")"
                   + " due=\(PrivacyPoolsCover.needsRefresh(now: now) ? "YES" : "no")"
                   + " · " + store.sorted { $0.key < $1.key }
                        .map { "\($0.key)=\($0.value)" }.joined(separator: ","))
        guard let room = compose(things: things, now: now) else {
            out.append("compose=nil — no card (no wallet watched, or no deposit"
                       + " and nothing reclaimed)")
            return out
        }
        out.append("headline=\(PrivacyPoolsRoom.headline(room, now: now))")
        out.append("note=\(PrivacyPoolsRoom.note(room))")
        out.append("holdings=\(PrivacyPoolsRoom.holdingsLine(room) ?? "none")")
        out.append("cover=\(PrivacyPoolsRoom.coverLine(room.cover) ?? "none")")
        // The old single `footnote` is two scope captions now (prd §486) —
        // printed apart, because they answer different questions and a room
        // can legitimately have one and not the other.
        out.append("shieldedNote=\(PrivacyPoolsRoom.shieldedNote(room) ?? "none")")
        out.append("activityNote=\(PrivacyPoolsRoom.activityNote(room, now: now) ?? "none")")
        // WHICH SCOPES THE ROOM WOULD OFFER, and which wears the dot. It is
        // the strip's own gate, so a room that draws no control has a cause
        // that is otherwise invisible from outside: one scope is not a
        // control, and a room of two untagged deposits is meant to look like a
        // short list.
        let scopes = PrivacyPoolsSection.present(
            shielded: !room.holdings.isEmpty,
            review: !room.segments.isEmpty || room.untagged > 0)
        out.append("privacyPoolsScopes| "
                   + scopes.map(\.rawValue).joined(separator: ",")
                   + " · strip=\(PrivacyPoolsSection.shows(present: scopes) ? "YES" : "no")"
                   + " · dot=\(PrivacyPoolsSection.attention(needsProof: room.needsYou != nil, declined: room.needsReclaim != nil, present: scopes).map(\.rawValue).sorted().joined(separator: ",").isEmpty ? "none" : "review")")
        out.append("totals| deposits=\(room.deposits) inPools=\(room.inPools)"
                   + " waiting=\(room.waiting)"
                   + " untagged=\(room.untagged) unpriced=\(room.unpriced)"
                   + " unattachedReclaims=\(room.unattachedReclaims)"
                   + " newest=\(room.newest?.formatted(.iso8601) ?? "none")"
                   + " reviewDaysObserved=\(room.reviewDays.map(String.init) ?? "none")")
        for segment in room.segments {
            out.append("privacyPoolsSegment| \(segment.state.rawValue)"
                       + " · \(PrivacyPoolsRoom.segmentLine(segment))"
                       + " · rank=\(PrivacyPoolsRoom.rank(segment.state))"
                       + " · share=\(String(format: "%.2f", PrivacyPoolsRoom.share(count: segment.count, of: room.deposits)))"
                       + " · wait=\(PrivacyPoolsRoom.waitLabel(segment, now: now) ?? "none")"
                       + " · oldestAt=\(segment.oldestAt?.formatted(.iso8601) ?? "none")")
        }
        // THE LEGEND AS DRAWN, untagged row included (prd §486) — the split
        // bar's gap is a row now, and this is the only place its wording can
        // be checked without a screenshot.
        for row in PrivacyPoolsRoom.legendRows(room) {
            out.append("privacyPoolsLegend| \(PrivacyPoolsRoom.name(row.slice))"
                       + " · \(PrivacyPoolsRoom.legendLine(row, now: now))"
                       + " · count=\(row.count)")
        }
        for holding in room.holdings {
            out.append("privacyPoolsHolding| \(holding.symbol)"
                       + " · \(PrivacyPoolsRoom.holdingText(holding))"
                       + " · deposits=\(holding.deposits) waiting=\(holding.waiting)"
                       + " · amount=\(holding.amount.map { String($0) } ?? "incomplete")")
        }
        // The bridge's own watchlist, printed BESIDE the corpus reading rather
        // than folded into it. The card deliberately does not read this (one
        // source of truth), but the two disagreeing is exactly the shape of
        // cause 4 above: labels still being polled whose rows never re-tag.
        out.append("privacyPoolsWatch| \(PrivacyPoolsBridge.pendingSummary())")
        return out
    }
}
