import Foundation
import SwiftData

/// The Peer room head's reading half (2026-08-10, prd §349) — landed rows
/// turned into the card's own value, with every judgement left to `PeerRoom`.
///
/// The split is `CursorRoomSource`'s and exists for its reason: this file
/// touches `Thing` and so can never be compiled by a harness, while
/// `PeerRoom.swift` is Foundation-only and is compiled WHOLE by
/// `scripts/wallet-rooms-selftest.sh`. Everything that could be wrong in a way
/// that still renders perfectly — a sell counted as a purchase, a rail nobody
/// named ranked beside real ones, a dormant room dated by a fall-through we
/// only just noticed — lives on the other side of that line.
enum PeerRoomSource {

    /// The bridge's own source name, taken from the bridge rather than spelled
    /// again — see `PeerBridge.sourceName`.
    static let source = PeerBridge.sourceName

    /// The card draws at most this many rails; the rest are counted in the
    /// footnote rather than silently dropped.
    static let rowCap = 3

    /// The head, or nil when there is nothing worth drawing.
    ///
    /// `now` is taken (and only used for the footnote's idle clause) so a probe
    /// can compose against a fixed clock — the signature every `…RoomSource` in
    /// the `sourceHead` chain shares.
    @MainActor
    static func compose(things: [Thing] = [], now: Date = .now) -> PeerRoom? {
        // Filtered live at the BOUNDARY before any stored property is read
        // (corollary 4) — the caller's array may be a debounced snapshot, and
        // the foreground sweep deletes rows while it is held.
        let rows = things.live.filter { $0.source == source }
        guard !rows.isEmpty else { return nil }
        let room = PeerRoom.compose(fills: rows.map(sighting))
        return room.isEmpty ? nil : room
    }

    /// One landed row, reduced to the three facts the head reads. The ONLY
    /// place a `Thing` is touched.
    @MainActor
    private static func sighting(_ thing: Thing) -> PeerRoom.Sighting {
        PeerRoom.Sighting(ref: thing.sourceRef,
                          // Where §311 stamps the funding rail, so the room
                          // groups on data rather than on a clamped display
                          // string. Nil on every expired row and on any fill
                          // whose IntentSignaled event could not be found.
                          rail: thing.authorHandle,
                          at: thing.capturedAt,
                          // priceValue/priceCurrency (2026-08-11) — the SAME
                          // generic "amount, in this currency, never summed
                          // across currencies" meaning `GnosisPayRoom` reads,
                          // reused rather than a new field. Nil on any fill
                          // whose token decimals couldn't be read.
                          token: thing.priceCurrency,
                          amount: thing.priceValue)
    }

    /// The probe's lines — driven by `-peerRoomProbe`, and deliberately calling
    /// the REAL `compose` rather than reimplementing it: a probe whose job is
    /// explaining the card must not be able to disagree with the card
    /// (`ASCRoomSource.probeLines`' own rule).
    ///
    /// It exists because an empty or thin head has FIVE causes that render as
    /// one nothing, and only the last two are bugs:
    ///
    ///   1. no wallet is watched, so the seat never ran and there are no rows;
    ///   2. the watched wallets have used Peer once or not at all
    ///      (`minimumFills`) — the common healthy case;
    ///   3. every fill is a fall-through, so nothing settled;
    ///   4. every fill was UNPLACED because no rail could be named, which means
    ///      the IntentSignaled join is failing and the titles are saying
    ///      "received" instead of "with Venmo";
    ///   5. a ref shape this build does not recognise, which lands nothing in
    ///      any bucket and is invisible from the feed — the rows still draw.
    ///
    /// Hence one line PER FILL naming its kind and rail (the `-todayProbe`
    /// truncation lesson: one NSLog per line, never a joined document).
    @MainActor
    static func probeLines(things: [Thing], now: Date = .now) -> [String] {
        let rows = things.live.filter { $0.source == source }
        var out: [String] = [
            "peerRoom| source=\(source) handed=\(things.count) peerRows=\(rows.count)"
                + " rowCap=\(rowCap) minimumFills=\(PeerRoom.minimumFills)",
        ]
        // The fills BEFORE grouping, newest first — so a card that grouped
        // wrongly can be told from one whose rows were already unreadable.
        // An unrecognised ref is named rather than dropped in silence.
        for sight in rows.map(sighting).sorted(by: { $0.at > $1.at }) {
            let kind = PeerRoom.kind(ref: sight.ref)
            out.append("peerRoomFill| kind=\(kind?.rawValue ?? "UNRECOGNISED")"
                       + " rail=\(sight.rail ?? "UNPLACED")"
                       + " token=\(sight.token ?? "UNPRICED")"
                       + " amount=\(sight.amount.map { String($0) } ?? "unknown")"
                       + " dated=\(kind?.settled == true ? "real" : "when-we-looked")"
                       + " at=\(sight.at.formatted(.iso8601))"
                       + " ref=\(sight.ref ?? "none")")
        }
        guard let room = compose(things: things, now: now) else {
            out.append("compose=nil — no card (no wallet watched, or under"
                       + " \(PeerRoom.minimumFills) fills)")
            return out
        }
        out.append("headline=\(PeerRoom.headline(room))")
        out.append("note=\(PeerRoom.note(room))")
        out.append("footnote=\(PeerRoom.footnote(room, drawn: min(rowCap, room.rails.count), now: now) ?? "none")")
        out.append("totals| bought=\(room.bought) sold=\(room.sold)"
                   + " unplaced=\(room.unplaced) fellThrough=\(room.fellThrough)"
                   + " rails=\(room.rails.count) tokens=\(room.tokens.count)"
                   + " newestSettled=\(room.newest?.formatted(.iso8601) ?? "none")")
        for token in room.tokens {
            out.append("peerRoomToken| \(token.symbol) · \(PeerRoom.tokenLine(token))")
        }
        let top = room.lead?.fills ?? 0
        for rail in room.rails.prefix(rowCap) {
            out.append("peerRoomRail| \(rail.name)"
                       + " · \(PeerRoom.railLine(rail))"
                       + " · newest=\(rail.newest.formatted(.iso8601))"
                       + " · share=\(String(format: "%.2f", PeerRoom.share(fills: rail.fills, of: top)))")
        }
        return out
    }
}
