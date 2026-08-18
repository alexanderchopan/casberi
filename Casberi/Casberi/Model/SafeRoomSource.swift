import Foundation
import SwiftData

/// The Safe room head's reading half (2026-08-11) — `SafeBridge`'s own
/// tracking store turned into the card's value, with every judgement left to
/// `SafeRoom`.
///
/// The split is `RailgunRoomSource`'s and exists for its reason: this file
/// can touch `Thing`/`SwiftData` and so can never be compiled by a harness,
/// while `SafeRoom.swift` is Foundation-only and is compiled WHOLE by
/// `scripts/wallet-rooms-selftest.sh`. Its subject is mostly `SafeBridge`'s
/// persisted STATE, the `ASCRoomSource` shape — but since 2026-08-17 it does
/// read `things`, for one thing only: the ref a module-only card opens (see
/// `fallbackRef`).
enum SafeRoomSource {

    static let source = SafeBridge.sourceName
    static let rowCap = SafeRoom.rowCap

    /// The head, or nil when no Safe has ever been detected for the watched
    /// wallets.
    @MainActor
    static func compose(things: [Thing] = [], now: Date = .now) -> SafeRoom? {
        let safeCount = SafeBridge.detectedCount()
        guard safeCount > 0 else { return nil }
        let entries = SafeBridge.pendingSnapshot().map(entry)
        let room = SafeRoom.compose(entries: entries, safeCount: safeCount,
                                    moduleSafes: moduleSafes())
        // A quiet Safe with no module risk has nothing this card would say
        // beyond "nothing pending" — the `RailgunRoom.isEmpty` shape: one
        // fact is a sentence, not a card.
        return (room.pendingCount > 0 || room.moduleCount > 0) ? room : nil
    }

    private static func entry(_ s: SafeBridge.PendingSnapshot) -> SafeRoom.Entry {
        SafeRoom.Entry(ref: s.ref, safeAddress: s.safeAddress, have: s.have, required: s.required,
                       yourTurn: s.yourTurn, submittedAt: s.submittedAt,
                       descriptionText: s.descriptionText, nonce: s.nonce)
    }

    /// The module-carrying Safes, each named the way every other Safe surface
    /// names an address — `WalletIngest.knownLabel`'s chain (address book →
    /// Farcaster handle), falling back to short hex. §238's ruling that this
    /// bridge is about PEOPLE, applied to the one sentence that asks you to go
    /// and act on a specific Safe.
    @MainActor
    private static func moduleSafes() -> [SafeRoom.ModuleSafe] {
        SafeBridge.knownModules()
            .filter { !$0.modules.isEmpty }
            .map { SafeRoom.ModuleSafe(label: label(for: $0.safeAddress), count: $0.modules.count) }
    }

    @MainActor
    private static func label(for address: String) -> String {
        if let known = WalletIngest.knownLabel(for: address) { return known }
        // The same shortening the address book itself uses. Never the raw
        // hash: a 42-character address inside a sentence is not a name.
        guard address.count > 10 else { return address }
        return "\(address.prefix(6))…\(address.suffix(4))"
    }

    /// What the card opens when there is nothing pending to open.
    ///
    /// `compose` deliberately returns a card on module risk ALONE — that is
    /// the highest-stakes fact this bridge has, and it is worth a card with no
    /// queue behind it. But the card's tap has always resolved to
    /// `room.lead`, so that exact card announced "Opens this Safe" to
    /// VoiceOver and then did nothing: the honesty rule's dead control, on the
    /// one card whose subject is funds being movable without a signature
    /// (found 2026-08-17).
    ///
    /// The destination is the config-change alert `syncConfig` already lands
    /// when a module is enabled — the row that says which Safe and which
    /// module, which is exactly what someone tapping this wants. Nil when no
    /// such row exists (a module present at FIRST sight seeds the baseline
    /// silently by design, so there may genuinely be nothing to open), and
    /// the card then draws with no tap at all rather than a door onto nothing.
    static func fallbackRef(things: [Thing]) -> String? {
        things.live
            .filter { $0.source == source && ($0.sourceRef?.hasPrefix("wallet:safeconfig:") ?? false) }
            .max(by: { $0.capturedAt < $1.capturedAt })?
            .sourceRef
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
    ///
    /// `ready=` and `nonce=` are printed per entry because both distinguish
    /// states that render identically from outside: a 2-of-2 counted as
    /// "waiting on others" looks exactly like a 1-of-2, and a rival pair looks
    /// exactly like two unrelated transactions.
    @MainActor
    static func probeLines(things: [Thing] = [], now: Date = .now) -> [String] {
        let safeCount = SafeBridge.detectedCount()
        let modules = SafeBridge.knownModules()
        let moduleCount = modules.reduce(0) { $0 + $1.modules.count }
        let snapshot = SafeBridge.pendingSnapshot()
        var out: [String] = [
            "safeRoom| safeCount=\(safeCount) moduleCount=\(moduleCount)"
                + " tracked=\(snapshot.count) rowCap=\(rowCap)"
                + " fallbackRef=\(fallbackRef(things: things) ?? "none")",
        ]
        for s in snapshot.sorted(by: { ($0.submittedAt ?? .distantPast) < ($1.submittedAt ?? .distantPast) }) {
            out.append("safeRoomEntry| yourTurn=\(s.yourTurn) \(s.have)/\(s.required)"
                       + " nonce=\(s.nonce.map(String.init) ?? "unknown")"
                       + " submitted=\(s.submittedAt?.formatted(.iso8601) ?? "unknown")"
                       + " · \(s.descriptionText) · ref=\(s.ref)")
        }
        guard let room = compose(things: things, now: now) else {
            out.append("compose=nil — no card (no Safe detected, or a detected"
                       + " Safe is quiet with nothing pending and no module)")
            return out
        }
        out.append("headline=\(SafeRoom.headline(room))")
        out.append("note=\(SafeRoom.note(room) ?? "none")")
        out.append("stateNote=\(SafeRoom.stateNote(room) ?? "none")")
        out.append("footnote=\(SafeRoom.footnote(room, drawn: min(rowCap, room.entries.count)) ?? "none")")
        out.append("stuckLine=\(SafeRoom.stuckLine(room, now: now) ?? "none")")
        out.append("totals| pending=\(room.pendingCount) awaitsYou=\(room.awaitsYouCount)"
                   + " ready=\(room.readyCount) contested=\(room.contestedCount)")
        for entry in room.entries.prefix(rowCap) {
            out.append("safeRoomRow| \(SafeRoom.waitLabel(entry, now: now)) · \(entry.have)/\(entry.required)"
                       + " ready=\(entry.isReady) awaitsYou=\(entry.awaitsYou)"
                       + " contested=\(room.isContested(entry))"
                       + " · \(entry.descriptionText)")
        }
        return out
    }
}
