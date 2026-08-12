import Foundation
import SwiftData

/// The `Thing` half of the purchase sheet (prd §368, 2026-08-12) — everything
/// `PurchaseStage.swift` deliberately cannot see.
///
/// The split is the house pattern (`SocialSheet`/`SocialSheetSource`,
/// `StripeRoom`/`StripeRoomSource`): the judgement is Foundation-only so a
/// harness can compile it whole, and the reads that touch SwiftData live here,
/// where there is no judgement to test — only lookups.
enum PurchaseStageSource {

    /// The `PurchaseStage.Row` for a thing.
    ///
    /// Liveness: reads stored properties, so every caller must already hold a
    /// live model — which the sheet does (its `init` and `body` both guard).
    static func row(for thing: Thing) -> PurchaseStage.Row {
        PurchaseStage.Row(
            source: thing.source,
            sourceRef: thing.sourceRef,
            kind: thing.kind.rawValue,
            title: thing.title,
            tags: thing.tags,
            priceValue: thing.priceValue,
            priceCurrency: thing.priceCurrency,
            sellerField: thing.authorHandle,
            merchantField: thing.transferCounterparty,
            capturedAt: thing.capturedAt,
            enrichedText: thing.enrichedText)
    }

    static func reading(for thing: Thing) -> PurchaseStage.Reading? {
        PurchaseStage.reading(row(for: thing))
    }

    // MARK: - Recurrence

    /// How often you have paid this merchant, and whether the amount moved.
    ///
    /// **A COUNT and a COMPARISON, never a total, and that refusal is the
    /// point.** `Corpus.cardSpendSources` keeps Privacy.com out of every money
    /// rollup in the app for a measured reason: a return is unmeasured there,
    /// so a refund lands wearing its positive authorization amount and a sum
    /// would be silently wrong rather than absent. A sum here would walk
    /// straight into that, on the one screen where a wrong number is believed
    /// instantly. Counting charges and comparing two of them is safe under
    /// exactly the same uncertainty — a mis-signed row is still a charge that
    /// happened, at an amount the record states.
    struct Recurrence: Equatable {
        /// How many rows name this merchant, this one included.
        var count: Int
        /// The oldest amount we hold for them, when it is comparable.
        var first: Double?
        var currency: String
        var current: Double
        var since: Date?

        /// Unchanged, up, or down — nil when there is nothing to compare
        /// against or the currencies differ.
        var direction: Int? {
            guard let first else { return nil }
            if abs(first - current) < 0.005 { return 0 }
            return current > first ? 1 : -1
        }
    }

    /// Nil unless the merchant is named AND has been paid more than once —
    /// "the 1st time you've paid Netflix" is a sentence about nothing.
    ///
    /// Scoped to ONE source on purpose. The same merchant paid by two
    /// different cards is two different records to us and joining them would
    /// mean asserting they are the same account; and `normalizeMerchant`'s
    /// prefix table is measured for the seats that carry processor noise, not
    /// across them.
    @MainActor
    static func recurrence(for thing: Thing, context: ModelContext?) -> Recurrence? {
        guard let context,
              let reading = reading(for: thing), reading.archetype == .receipt,
              !PurchaseStage.isRefill(row(for: thing)),
              let merchant = thing.transferCounterparty?
                .trimmingCharacters(in: .whitespacesAndNewlines), !merchant.isEmpty,
              let current = thing.priceValue,
              let currency = thing.priceCurrency, !currency.isEmpty
        else { return nil }

        let source = thing.source
        // Case-INSENSITIVE matching is done in Swift rather than in the
        // predicate: `AppleWalletRoom.merchantKey` exists because a bank's
        // `merchantName` and its `transactionDescription` disagree about case,
        // and a split total is exactly what that key was written to prevent.
        // SwiftData can push down `==` on a stored String and not a folded
        // compare, so the fetch is scoped by SOURCE and the fold happens here.
        let d = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == source },
            sortBy: [SortDescriptor(\.capturedAt, order: .forward)])
        // `.live` at the boundary (corollary 4) — this array is walked below
        // and its stored properties read, so the guarantee is made once, here.
        let rows = ((try? context.fetch(d)) ?? []).live
        let key = AppleWalletRoom.merchantKey(merchant)
        let mine = rows.filter {
            $0.kind == .transaction || (($0.sourceRef ?? "").hasPrefix("bitrefill:order:"))
        }.filter {
            guard let name = $0.transferCounterparty, !name.isEmpty else { return false }
            return AppleWalletRoom.merchantKey(name) == key
        }
        guard mine.count > 1 else { return nil }

        // The oldest amount, and only when it is in the SAME currency — a
        // card that billed in euros and now bills in dollars has not "gone
        // up", and saying so would be arithmetic across two number systems
        // (the Gnosis Pay decimals lesson, one field over).
        let earlier = mine.first { $0.priceCurrency == currency && $0.priceValue != nil }
        return Recurrence(count: mine.count,
                          first: earlier?.priceValue,
                          currency: currency,
                          current: current,
                          since: earlier?.capturedAt)
    }
}
