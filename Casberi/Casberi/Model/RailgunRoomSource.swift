import Foundation
import SwiftData

/// The Railgun room head's reading half (2026-08-11) — landed rows turned
/// into the card's own value, with every judgement left to `RailgunRoom`.
///
/// The split is `PeerRoomSource`'s and exists for its reason: this file
/// touches `Thing` and so can never be compiled by a harness, while
/// `RailgunRoom.swift` is Foundation-only and is compiled WHOLE by
/// `scripts/wallet-rooms-selftest.sh`.
enum RailgunRoomSource {

    /// The bridge's own source name, taken from the bridge rather than
    /// spelled again — see `RailgunBridge.sourceName`.
    static let source = RailgunBridge.sourceName

    /// The card draws at most this many tokens; the rest are counted in the
    /// footnote rather than silently dropped.
    static let rowCap = 3

    /// The head, or nil when there is nothing worth drawing.
    @MainActor
    static func compose(things: [Thing] = [], now: Date = .now) -> RailgunRoom? {
        // Filtered live at the BOUNDARY before any stored property is read
        // (corollary 4) — the caller's array may be a debounced snapshot, and
        // the foreground sweep deletes rows while it is held.
        let rows = things.live.filter { $0.source == source }
        guard !rows.isEmpty else { return nil }
        let room = RailgunRoom.compose(moves: rows.map(sighting))
        return room.isEmpty ? nil : room
    }

    /// One landed row, reduced to what the head reads. The ONLY place a
    /// `Thing` is touched.
    @MainActor
    private static func sighting(_ thing: Thing) -> RailgunRoom.Sighting {
        RailgunRoom.Sighting(ref: thing.sourceRef,
                             token: thing.priceCurrency,
                             amount: thing.priceValue,
                             at: thing.capturedAt)
    }

    /// The probe's lines — driven by `-railgunRoomProbe`, calling the REAL
    /// `compose` (the `ASCRoomSource.probeLines` rule: a probe explaining the
    /// card must not be able to disagree with it).
    ///
    /// An empty or thin head has FIVE causes that render as one nothing, and
    /// only the last two are bugs:
    ///
    ///   1. no wallet is watched, so the seat never ran and there are no rows;
    ///   2. the watched wallets have shielded once or not at all
    ///      (`minimumMoves`) — the common healthy case, and the expected one
    ///      given `RailgunBridge`'s own "only about half of shields are
    ///      attributable" ceiling;
    ///   3. every move landed but no token symbol could be read, so
    ///      everything is UNPLACED and the titles are wearing short hexes;
    ///   4. every move landed but decimals couldn't be read, so tokens group
    ///      correctly but every amount stays silent;
    ///   5. a ref shape this build does not recognise, which lands nothing in
    ///      `direction(ref:)` and is invisible from the feed — the row still
    ///      draws.
    @MainActor
    static func probeLines(things: [Thing], now: Date = .now) -> [String] {
        let rows = things.live.filter { $0.source == source }
        var out: [String] = [
            "railgunRoom| source=\(source) handed=\(things.count) railgunRows=\(rows.count)"
                + " rowCap=\(rowCap) minimumMoves=\(RailgunRoom.minimumMoves)",
        ]
        for sight in rows.map(sighting).sorted(by: { $0.at > $1.at }) {
            let dir = RailgunRoom.direction(ref: sight.ref)
            out.append("railgunRoomMove| direction=\(dir?.rawValue ?? "UNRECOGNISED")"
                       + " token=\(sight.token ?? "UNPLACED")"
                       + " amount=\(sight.amount.map { String($0) } ?? "unknown")"
                       + " at=\(sight.at.formatted(.iso8601))"
                       + " ref=\(sight.ref ?? "none")")
        }
        guard let room = compose(things: things, now: now) else {
            out.append("compose=nil — no card (no wallet watched, or under"
                       + " \(RailgunRoom.minimumMoves) moves)")
            return out
        }
        out.append("headline=\(RailgunRoom.headline(room))")
        out.append("note=\(RailgunRoom.note(room))")
        out.append("footnote=\(RailgunRoom.footnote(room, drawn: min(rowCap, room.tokens.count), now: now) ?? "none")")
        out.append("totals| shields=\(room.shields) unshields=\(room.unshields)"
                   + " unplaced=\(room.unplaced) tokens=\(room.tokens.count)"
                   + " newest=\(room.newest?.formatted(.iso8601) ?? "none")")
        let top = room.lead?.moves ?? 0
        for token in room.tokens.prefix(rowCap) {
            out.append("railgunRoomToken| \(token.symbol)"
                       + " · \(RailgunRoom.tokenLine(token))"
                       + " · newest=\(token.newest.formatted(.iso8601))"
                       + " · share=\(String(format: "%.2f", RailgunRoom.share(moves: token.moves, of: top)))")
        }
        return out
    }
}
