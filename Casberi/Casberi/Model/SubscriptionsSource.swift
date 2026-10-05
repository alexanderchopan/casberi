import Foundation
import Observation
import SwiftData

/// The Subscriptions tile's READING half (prd §1105): landed rows and the
/// hand-added list turned into the plain values `Subscriptions` merges.
///
/// It reads its own sources with its own fetch rather than the Wallet room's
/// rows: the room's query is bounded (`sourceRoomFetchLimit`), and a busy
/// wallet's transfers would push a card's year of charges past the bound —
/// the series would then stop at two charges and the subscription would
/// silently vanish. The fetch runs from a `.task`, never a body (prd §628).
@Observable
@MainActor
final class SubscriptionsReading {
    static let shared = SubscriptionsReading()

    /// Every subscription, as last read.
    private(set) var items: [Subscriptions.Item] = []
    /// What the counted ones cost a month, in dollars.
    private(set) var total = Subscriptions.Total(monthly: 0, counted: 0, uncounted: [])
    /// True once a read has finished, so the tile can tell "none" from "not yet".
    private(set) var read = false
    /// The rates the last read converted at (`WalletCash`), for a scoped total.
    private(set) var rates: [String: Double] = [:]

    private init() {}

    /// The seats a subscription can be read from.
    static let sources: [String] = [AppleWalletBridge.sourceName, WalletCards.privacySource, RocketMoneyLive.source]

    func refresh(_ context: ModelContext, now: Date = .now) async {
        let members = Self.sources
        let d = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { members.contains($0.source) },
                                       sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        let things = ((try? context.fetch(d)) ?? []).live
        let found = SubscriptionsSource.found(from: things, now: now)
        let bills = SubscriptionsSource.bills(from: things, now: now)
        let composed = Subscriptions.compose(found: found, bills: bills,
                                             manual: SubscriptionStore.shared.all, now: now)
        let codes = Set(composed.map(\.currency)).subtracting(["USD"])
        let rates = codes.isEmpty ? [:] : await WalletCash.cachedRates(for: codes)
        let sum = Subscriptions.total(composed) { WalletCash.usd($0, $1, rates: rates) }
        if composed != items { items = composed }
        if sum != total { total = sum }
        if rates != self.rates { self.rates = rates }
        read = true
    }

    /// The monthly total of a scoped list, at the last read's rates.
    func total(of scoped: [Subscriptions.Item]) -> Subscriptions.Total {
        scoped == items ? total
            : Subscriptions.total(scoped) { WalletCash.usd($0, $1, rates: rates) }
    }

    /// The items a scoped room shows: every one on All, and on an app's pick
    /// only what that app saw. A hand-added one belongs to no app.
    func items(in sources: Set<String>?) -> [Subscriptions.Item] {
        guard let sources else { return items }
        return items.filter { !Set($0.foundIn).isDisjoint(with: sources) }
    }
}

enum SubscriptionsSource {

    /// How far back a charge counts: a year and a little, as the Apple Wallet
    /// room reads (`AppleWalletRoomSource`).
    static let lookbackDays = AppleWalletRoomSource.lookbackDays

    /// Whether a row is one this tile reads as a bill rather than news: a
    /// Rocket Money record dated ahead. Home and Coming up leave these to
    /// Subscriptions, so one bill is never on two tiles.
    @MainActor
    static func isBill(_ thing: Thing, now: Date = .now) -> Bool {
        thing.source == RocketMoneyLive.source && (thing.dueAt.map { $0 > now } ?? false)
    }

    /// Charges that name their merchant, grouped by what paid them, run
    /// through `AppleWalletRoom.recurringSeries` per payer.
    @MainActor
    static func found(from things: [Thing], now: Date) -> [Subscriptions.Found] {
        let floor = now.addingTimeInterval(-Double(lookbackDays) * 86_400)
        // payer → (source, spends)
        var byPayer: [String: (source: String, spends: [AppleWalletRoom.Spend])] = [:]
        for thing in things where thing.kind == .transaction && thing.capturedAt >= floor {
            guard let payer = payer(of: thing),
                  let amount = thing.priceValue,
                  let currency = thing.priceCurrency,
                  let merchant = thing.transferCounterparty, !merchant.isEmpty else { continue }
            let spend = AppleWalletRoom.Spend(
                merchant: merchant, amount: abs(amount), currency: currency,
                date: thing.capturedAt,
                isSettled: !thing.tags.contains("Pending"),
                isRefund: thing.tags.contains("Refund"))
            byPayer[payer, default: (thing.source, [])].spends.append(spend)
        }
        var out: [Subscriptions.Found] = []
        for (payer, entry) in byPayer.sorted(by: { $0.key < $1.key }) {
            let series = AppleWalletRoom.recurringSeries(entry.spends, now: now)
            let rises = AppleWalletRoom.creeps(series, now: now)
            for s in series {
                let rise = rises.first { Subscriptions.key($0.merchant) == Subscriptions.key(s.merchant)
                                         && $0.currency == s.currency }
                out.append(.init(series: s, paysWith: payer, source: entry.source, was: rise?.was))
            }
        }
        return out
    }

    /// What paid a charge, as the person knows it: Apple Wallet's account
    /// name ("Apple Card", off "Apple Card, ending 4821"), or the seat.
    @MainActor
    static func payer(of thing: Thing) -> String? {
        switch thing.source {
        case AppleWalletBridge.sourceName:
            let account = thing.authorHandle?
                .split(separator: ",").first
                .map { $0.trimmingCharacters(in: .whitespaces) }
            return (account?.isEmpty == false ? account : nil) ?? AppleWalletBridge.sourceName
        case WalletCards.privacySource:
            guard thing.sourceRef?.hasPrefix("privacy:txn:") ?? false else { return nil }
            return "Privacy.com"
        default:
            return nil
        }
    }

    /// Rocket Money's bills with a charge still to come.
    @MainActor
    static func bills(from things: [Thing], now: Date) -> [Subscriptions.Bill] {
        things.compactMap { thing in
            guard isBill(thing, now: now), let due = thing.dueAt else { return nil }
            let name = TitleSeam.split(thing.title).name
            return Subscriptions.Bill(name: name, amount: thing.priceValue,
                                      currency: thing.priceCurrency ?? "USD",
                                      due: due, source: thing.source)
        }
    }
}
