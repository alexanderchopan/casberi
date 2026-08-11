import Foundation
import SwiftData

/// The Safe room head's reading half (2026-08-11) — `SafeBridge`'s own
/// tracking store turned into the card's value, with every judgement left to
/// `SafeRoom`.
///
/// The split is `RailgunRoomSource`'s and exists for its reason: this file
/// can touch `Thing`/`SwiftData` and so can never be compiled by a harness,
/// while `SafeRoom.swift` is Foundation-only and is compiled WHOLE by
/// `scripts/wallet-rooms-selftest.sh`. In practice this source reads no
/// `Thing` at all — its subject is `SafeBridge`'s persisted STATE, the
/// `ASCRoomSource` shape — but it keeps the `things:`/`now:` signature every
/// member of the `sourceHead` chain shares.
enum SafeRoomSource {

    static let source = SafeBridge.sourceName
    static let rowCap = SafeRoom.rowCap

    /// The head, or nil when no Safe has ever been detected for the watched
    /// wallets. `things` is unused (see the file doc) but kept for the
    /// uniform `sourceHead` dispatch signature.
    @MainActor
    static func compose(things: [Thing] = [], now: Date = .now) -> SafeRoom? {
        let safeCount = SafeBridge.detectedCount()
        guard safeCount > 0 else { return nil }
        let moduleCount = SafeBridge.knownModules().reduce(0) { $0 + $1.modules.count }
        let entries = SafeBridge.pendingSnapshot().map(entry)
        let room = SafeRoom.compose(entries: entries, safeCount: safeCount, moduleCount: moduleCount)
        // A quiet Safe with no module risk has nothing this card would say
        // beyond "nothing pending" — the `RailgunRoom.isEmpty` shape: one
        // fact is a sentence, not a card.
        return (room.pendingCount > 0 || room.moduleCount > 0) ? room : nil
    }

    private static func entry(_ s: SafeBridge.PendingSnapshot) -> SafeRoom.Entry {
        SafeRoom.Entry(ref: s.ref, safeAddress: s.safeAddress, have: s.have, required: s.required,
                       yourTurn: s.yourTurn, submittedAt: s.submittedAt, descriptionText: s.descriptionText)
    }

    /// The probe's lines — driven by `-safeRoomProbe`, calling the REAL
    /// `compose` (the `ASCRoomSource.probeLines` rule).
    ///
    /// An empty or thin head has FOUR causes that render as one nothing, and
    /// only the last is a bug:
    ///
    ///   1. no EVM wallet is watched, so `SafeBridge` never ran;
    ///   2. wallets are watched but none is a Safe or a Safe signer — the
    ///      common case for most people;
    ///   3. a detected Safe is genuinely quiet — nothing pending, no module
    ///      enabled — which is the healthy state `compose` returns nil for;
    ///   4. the tracking store lost its entries to the 2026-08-11 shape
    ///      change (harmless, self-heals within one sync pass — see
    ///      `SafeBridge.TrackEntry`'s own doc) but `detectedCount()` still
    ///      reports Safes, so the card draws with zero rows — worth
    ///      re-running the probe after one more sync if this is why.
    @MainActor
    static func probeLines(now: Date = .now) -> [String] {
        let safeCount = SafeBridge.detectedCount()
        let modules = SafeBridge.knownModules()
        let moduleCount = modules.reduce(0) { $0 + $1.modules.count }
        let snapshot = SafeBridge.pendingSnapshot()
        var out: [String] = [
            "safeRoom| safeCount=\(safeCount) moduleCount=\(moduleCount)"
                + " tracked=\(snapshot.count) rowCap=\(rowCap)",
        ]
        for s in snapshot.sorted(by: { ($0.submittedAt ?? .distantPast) < ($1.submittedAt ?? .distantPast) }) {
            out.append("safeRoomEntry| yourTurn=\(s.yourTurn) \(s.have)/\(s.required)"
                       + " submitted=\(s.submittedAt?.formatted(.iso8601) ?? "unknown")"
                       + " · \(s.descriptionText) · ref=\(s.ref)")
        }
        guard let room = compose(now: now) else {
            out.append("compose=nil — no card (no Safe detected, or a detected"
                       + " Safe is quiet with nothing pending and no module)")
            return out
        }
        out.append("headline=\(SafeRoom.headline(room))")
        out.append("note=\(SafeRoom.note(room) ?? "none")")
        out.append("footnote=\(SafeRoom.footnote(room, drawn: min(rowCap, room.entries.count)) ?? "none")")
        out.append("totals| pending=\(room.pendingCount) yourTurn=\(room.yourTurnCount)")
        for entry in room.entries.prefix(rowCap) {
            out.append("safeRoomRow| \(SafeRoom.waitLabel(entry, now: now)) · \(entry.have)/\(entry.required)"
                       + " · \(entry.descriptionText)")
        }
        return out
    }
}
