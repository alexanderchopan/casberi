import Foundation
import SwiftData

/// Builds `CardPointers.Room` from the corpus (prd §420).
///
/// The usual split: everything touching `Thing` lives here, so the judgement
/// itself stays Foundation-only and provable in `cardpointers-selftest.sh`.
///
/// **The offer is rebuilt from the ROW's own stored fields, never re-parsed out
/// of the title.** `CardPointersIngest` writes the card to `authorHandle`, the
/// terms to `summary` and the expiry to `dueAt`, so the room reads those three
/// directly. Splitting "Amex Gold · Amazon" back apart would break the moment a
/// merchant contained the separator, and `titleLine` clamps at 80 anyway — the
/// same rule `GnosisPayRoomSource` follows for its amounts.
enum CardPointersRoomSource {
    static let source = CardPointersIngest.source

    @MainActor
    static func compose(things: [Thing], now: Date = .now) -> CardPointers.Room? {
        var offers: [CardPointers.Offer] = []
        // Filtered live AT THE BOUNDARY, before any stored property is read
        // (the liveness corollary 4).
        for thing in things.live where thing.source == source {
            guard let ref = thing.sourceRef, ref.hasPrefix("cardpointers:offer:") else { continue }
            let card = thing.authorHandle
            // The merchant is what the title says after the card, and the card
            // is a stored field — so this is a strip, not a parse: if the
            // prefix isn't there the whole title IS the merchant.
            let merchant: String
            if let card, thing.title.hasPrefix(card + " · ") {
                merchant = String(thing.title.dropFirst(card.count + 3))
            } else {
                merchant = thing.title
            }
            // A landed row is one the ingest kept ACTIVE — `heal` clears
            // `dueAt` when an offer finishes, and the room's own floor and
            // deadline logic take it from there.
            offers.append(CardPointers.Offer(
                id: ref, merchant: merchant, card: card,
                status: .active, expires: thing.dueAt, terms: thing.summary))
        }
        return CardPointers.room(offers: offers, now: now)
    }

    /// `-cardPointersRoomProbe YES` — one line per card row, plus the head.
    /// An empty head has four causes that render as one nothing: not
    /// connected, an account without CardPointers+, a book below the floor,
    /// and every offer snoozed or finished. Only the last two are readable
    /// from here, so the probe prints the count it actually saw.
    @MainActor
    static func probeLines(context: ModelContext) -> [String] {
        let descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "CardPointers" })
        let rows = (try? context.fetch(descriptor)) ?? []
        guard let room = compose(things: rows) else {
            return ["no head — \(rows.count) row(s) in the corpus"]
        }
        var out = ["head: \(room.headline) · undated=\(room.undated) · rows=\(rows.count)"]
        if let soonest = room.soonest {
            out.append("soonest: \(soonest.merchant) on \(soonest.card ?? "?")")
        }
        for card in room.cards {
            out.append("card| \(card.name) active=\(card.active) soonest=\(card.soonest.map(String.init(describing:)) ?? "none")")
        }
        return out
    }
}
