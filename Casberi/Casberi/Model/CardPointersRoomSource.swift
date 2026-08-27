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
            // The strip moved into `CardPointers` on §487 and is NOT re-spelled
            // here: the row now leads with the merchant too, so this became a
            // rule with two readers, and two copies is where a room's head and
            // its own rows start naming different things.
            let merchant = CardPointers.merchant(title: thing.title, card: card)
            // **The status comes off `mark`, and before §487 it did not.**
            // Every landed row was handed to the head as `.active`, so a
            // redeemed coupon went on being counted in "N offers waiting"
            // forever — the head disagreeing with its own rows, which is half
            // of why the room read as a pile. `CardPointersIngest.heal` stamps
            // `.done` on anything the service says is not in play (redeemed,
            // expired, and an offer deliberately snoozed), and `.redeemed`
            // stands in for all three here because the only question the model
            // asks of a status is `needsYou`.
            let done = thing.mark == .done
            offers.append(CardPointers.Offer(
                id: ref, merchant: merchant, card: card,
                status: done ? .redeemed : .active,
                expires: thing.dueAt, terms: thing.summary))
        }
        return CardPointers.room(offers: offers, now: now)
    }

    /// `-cardPointersRoomProbe YES` — the head, then one line per deadline.
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
        // Counted here rather than on the head, because §487 took both facts
        // OFF the head — the rows say them now, and the probe is where the
        // shapes a screenshot cannot separate still have to be readable: a
        // book of nothing but dateless offers and a book of nothing but
        // finished ones both draw one sentence and no rail.
        let dateless = rows.filter { $0.isLive && $0.dueAt == nil && $0.mark != .done }.count
        let done = rows.filter { $0.isLive && $0.mark == .done }.count
        var out = ["head: \(room.headline) · rows=\(rows.count) · dateless=\(dateless) · notActive=\(done)"]
        for date in room.deadlines {
            out.append("deadline| \(date)")
        }
        return out
    }
}
