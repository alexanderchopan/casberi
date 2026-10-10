import Foundation
import Observation
import SwiftData

/// The Wallet Home's Spending section's READING: landed rows turned into
/// `Spending.Charge`s, converted to dollars at `WalletCash`'s rates.
///
/// Its own fetch, from a `.task` (prd §628), for `SubscriptionsReading`'s
/// reason: the room's query is bounded, and a busy wallet's transfers would
/// push a month of card charges past the bound.
@Observable
@MainActor
final class SpendingReading {
    static let shared = SpendingReading()

    private(set) var reading = Spending.Reading(total: 0, earlier: nil, places: [])
    /// True once a read has finished, so the section can tell "none" from "not yet".
    private(set) var read = false
    /// The newest purchase, for Home's Spending tile (prd §1219).
    private(set) var latest: Thing?

    private init() {}

    static let cardSources: [String] = [
        AppleWalletBridge.sourceName, WalletCards.privacySource,
        GnosisPayBridge.sourceName, MetaMaskCardBridge.source, EtherFiCash.source,
    ]
    static let walletSource = "Wallet"
    static var sources: [String] { cardSources + [WiseShape.source, walletSource] }

    func refresh(_ context: ModelContext, now: Date = .now, calendar: Calendar = .current) async {
        let members = Self.sources
        // Two months back covers this month and last month to date.
        let floor = calendar.date(byAdding: .month, value: -2, to: now) ?? now
        let d = FetchDescriptor<Thing>(
            predicate: #Predicate<Thing> { members.contains($0.source) && $0.capturedAt >= floor },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        let things = ((try? context.fetch(d)) ?? []).live
        let raw = SpendingSource.charges(from: things)
        let codes = Set(raw.map(\.currency)).subtracting(["USD"])
        let rates = codes.isEmpty ? [:] : await WalletCash.cachedRates(for: codes)
        let charges = raw.compactMap { c in
            WalletCash.usd(c.amount, c.currency, rates: rates)
                .map { Spending.Charge(place: c.place, usd: $0, at: c.at) }
        }
        let next = Spending.read(charges, now: now, calendar: calendar)
        if next != reading { reading = next }
        // The newest charge that is a spend, back to its row (the rows are
        // newest first, and a charge carries its row's moment).
        let newestAt = raw.filter { $0.amount > 0 }.map(\.at).max()
        let found = newestAt.flatMap { at in things.first { $0.capturedAt == at } }
        if found?.id != latest?.id { latest = found }
        read = true
    }
}

enum SpendingSource {

    struct Raw {
        var place: String
        var amount: Double
        var currency: String
        var at: Date
    }

    @MainActor
    static func charges(from things: [Thing]) -> [Raw] {
        // Every address a watched wallet's row was read for is yours, so a
        // send to one of them is a move, not spending.
        let own = Set(things.compactMap { $0.walletAddress?.lowercased() })
        return things.compactMap { thing in
            guard thing.kind == .transaction else { return nil }
            switch thing.source {
            case AppleWalletBridge.sourceName, WalletCards.privacySource:
                guard SubscriptionsSource.payer(of: thing) != nil,
                      !thing.tags.contains("Pending"),
                      let amount = thing.priceValue, let currency = thing.priceCurrency,
                      let merchant = thing.transferCounterparty, !merchant.isEmpty else { return nil }
                let refund = thing.tags.contains("Refund")
                return Raw(place: merchant, amount: refund ? -abs(amount) : abs(amount),
                           currency: currency, at: thing.capturedAt)
            case GnosisPayBridge.sourceName, MetaMaskCardBridge.source, EtherFiCash.source:
                // The chain names no merchant for any of the three cards, so
                // the card is the place.
                guard CardSpendSeat.isSpend(thing, seat: thing.source),
                      let amount = thing.priceValue, let currency = thing.priceCurrency else { return nil }
                return Raw(place: thing.source, amount: abs(amount), currency: currency, at: thing.capturedAt)
            case WiseShape.source:
                guard thing.transferDirection == "sent",
                      !thing.tags.contains(String(localized: "Pending")),
                      !thing.tags.contains(String(localized: "Returned")),
                      let amount = thing.priceValue, let currency = thing.priceCurrency else { return nil }
                let place = thing.transferCounterparty.flatMap { $0.isEmpty ? nil : $0 } ?? WiseShape.source
                return Raw(place: place, amount: abs(amount), currency: currency, at: thing.capturedAt)
            case SpendingReading.walletSource:
                guard thing.transferDirection == "sent",
                      let usd = thing.transferUSD, usd.isFinite, usd > 0 else { return nil }
                if thing.sourceRef?.hasPrefix("wallet:swap:") ?? false { return nil }
                if let to = thing.counterpartyAddress?.lowercased() {
                    if own.contains(to) { return nil }
                    // Machinery is not a place you spent at: a router or an
                    // onramp trades the money back, and a card's Safe tops up
                    // a card whose spends are counted at the card. A person,
                    // an exchange's deposit address and an address nobody
                    // named are where money went.
                    if WalletIngest.isKnownContract(to) { return nil }
                    switch AddressBook.shared.entry(for: to)?.kind {
                    case .contract?, .safe?: return nil
                    default: break
                    }
                }
                let place = thing.transferCounterparty.flatMap { $0.isEmpty ? nil : $0 }
                    ?? thing.counterpartyAddress.map(WalletStore.shortAddress)
                guard let place else { return nil }
                return Raw(place: place, amount: usd, currency: "USD", at: thing.capturedAt)
            default:
                return nil
            }
        }
    }
}
