import Foundation
import SwiftData

/// The Privacy Pools room head's reading half (2026-08-10, prd §348) — landed
/// rows turned into the card's own value, with every judgement left to
/// `PrivacyPoolsRoom`.
///
/// The split is `CursorRoomSource`'s. Everything that could be wrong in a way
/// that still renders perfectly — an alert counted as a second deposit, a
/// deposit with no state tag reported as pending, a stuck deposit ranked below
/// forty cleared ones — lives on the other side of that line, in a file the
/// harness compiles whole.
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
        let room = PrivacyPoolsRoom.compose(rows: rows.map(sighting))
        return room.isEmpty ? nil : room
    }

    /// One landed row, reduced to what the head reads. The ONLY place a `Thing`
    /// is touched.
    @MainActor
    private static func sighting(_ thing: Thing) -> PrivacyPoolsRoom.Sighting {
        PrivacyPoolsRoom.Sighting(ref: thing.sourceRef,
                                  tags: thing.tags,
                                  at: thing.capturedAt)
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
    ///      never be counted as pending.
    ///
    /// 3, 4 and 5 are the same card. Hence one line PER ROW naming its ref
    /// shape and its tags (the `-todayProbe` truncation lesson), so "pending
    /// because the screener is slow" can be told from "pending because nothing
    /// ever writes anything else".
    @MainActor
    static func probeLines(things: [Thing], now: Date = .now) -> [String] {
        let rows = things.live.filter { $0.source == source }
        var out: [String] = [
            "privacyPoolsRoom| source=\(source) handed=\(things.count)"
                + " ppRows=\(rows.count) states=\(PrivacyPoolsRoom.states.joined(separator: "/"))",
        ]
        for sight in rows.map(sighting).sorted(by: { $0.at > $1.at }) {
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
            out.append("privacyPoolsRow| \(shape)"
                       + " tags=[\(sight.tags.joined(separator: ","))]"
                       + " at=\(sight.at.formatted(.iso8601))"
                       + " ref=\(sight.ref ?? "none")")
        }
        guard let room = compose(things: things, now: now) else {
            out.append("compose=nil — no card (no wallet watched, or no deposit"
                       + " and nothing reclaimed)")
            return out
        }
        out.append("headline=\(PrivacyPoolsRoom.headline(room))")
        out.append("note=\(PrivacyPoolsRoom.note(room))")
        out.append("footnote=\(PrivacyPoolsRoom.footnote(room, now: now) ?? "none")")
        out.append("totals| deposits=\(room.deposits) waiting=\(room.waiting)"
                   + " untagged=\(room.untagged) reclaimed=\(room.reclaimed)"
                   + " newest=\(room.newest?.formatted(.iso8601) ?? "none")")
        for segment in room.segments {
            out.append("privacyPoolsSegment| \(segment.state.rawValue)"
                       + " · \(PrivacyPoolsRoom.segmentLine(segment))"
                       + " · rank=\(PrivacyPoolsRoom.rank(segment.state))"
                       + " · share=\(String(format: "%.2f", PrivacyPoolsRoom.share(count: segment.count, of: room.deposits)))")
        }
        // The bridge's own watchlist, printed BESIDE the corpus reading rather
        // than folded into it. The card deliberately does not read this (one
        // source of truth), but the two disagreeing is exactly the shape of
        // cause 4 above: labels still being polled whose rows never re-tag.
        out.append("privacyPoolsWatch| \(PrivacyPoolsBridge.pendingSummary())")
        return out
    }
}
