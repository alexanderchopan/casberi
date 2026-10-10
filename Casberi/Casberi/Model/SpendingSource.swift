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
    /// Home's Cards (prd §1232): each card's month, what it owes and its
    /// offers, in the order `WalletCardRoll` draws them.
    private(set) var cards: [WalletCardRoll.Card] = []

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
        let roll = WalletCardRoll.compose(
            spends: raw.compactMap { c in
                guard let card = c.card, let usd = WalletCash.usd(c.amount, c.currency, rates: rates)
                else { return nil }
                return WalletCardRoll.Spend(card: card, app: c.app, usd: usd, at: c.at)
            },
            owed: Self.owed(),
            offers: Self.offers(context),
            now: now, calendar: calendar)
        if roll != cards { cards = roll }
        // The newest charge that is a spend, back to its row (the rows are
        // newest first, and a charge carries its row's moment).
        let newestAt = raw.filter { $0.amount > 0 }.map(\.at).max()
        let found = newestAt.flatMap { at in things.first { $0.capturedAt == at } }
        if found?.id != latest?.id { latest = found }
        read = true
    }

    /// What each Apple Wallet credit account owes and when, as FinanceKit
    /// last said it (the bridge's snapshots, never inferred).
    private static func owed() -> [WalletCardRoll.Owed] {
        let owed = AppleWalletBridge.owed
        let dues = AppleWalletBridge.dues
        return Set(owed.keys).union(dues.keys).map { name in
            WalletCardRoll.Owed(card: name, app: AppleWalletBridge.sourceName,
                                amount: owed[name]?.value, currency: owed[name]?.currency ?? "USD",
                                due: dues[name].map { Date(timeIntervalSince1970: $0) })
        }
    }

    /// CardPointers' offers still in play, on the card each is for; the
    /// row's own fields, as `CardPointersRoomSource` reads them.
    private static func offers(_ context: ModelContext) -> [WalletCardRoll.Offer] {
        let source = CardPointersRoomSource.source
        let d = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == source })
        return ((try? context.fetch(d)) ?? []).live.compactMap { thing in
            guard thing.sourceRef?.hasPrefix("cardpointers:offer:") ?? false, thing.mark != .done else { return nil }
            let card = thing.authorHandle.flatMap { $0.isEmpty ? nil : $0 } ?? source
            return WalletCardRoll.Offer(card: card, app: source, expires: thing.dueAt)
        }
    }
}

enum SpendingSource {

    struct Raw {
        var place: String
        var amount: Double
        var currency: String
        var at: Date
        /// The card it went on, for Home's Cards; nil for a move that is no card's.
        var card: String? = nil
        var app: String = ""
    }

    /// A card spend's card as the person knows it.
    static func cardName(forSource source: String) -> String {
        source == EtherFiCash.source ? "ether.fi Cash" : source
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
                           currency: currency, at: thing.capturedAt,
                           card: SubscriptionsSource.payer(of: thing), app: thing.source)
            case GnosisPayBridge.sourceName, MetaMaskCardBridge.source, EtherFiCash.source:
                // The chain names no merchant for any of the three cards, so
                // the card is the place.
                guard CardSpendSeat.isSpend(thing, seat: thing.source),
                      let amount = thing.priceValue, let currency = thing.priceCurrency else { return nil }
                return Raw(place: thing.source, amount: abs(amount), currency: currency, at: thing.capturedAt,
                           card: cardName(forSource: thing.source), app: thing.source)
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
