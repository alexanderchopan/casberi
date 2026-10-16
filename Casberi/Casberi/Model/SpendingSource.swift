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
    /// Home's Cards (prd §1232): each card's month, what it owes and its
    /// offers, in the order `WalletCardRoll` draws them.
    private(set) var cards: [WalletCardRoll.Card] = []

    private init() {}

    static let cardSources: [String] = [
        AppleWalletBridge.sourceName, WalletCards.privacySource,
        MetaMaskCardBridge.source, EtherFiCash.source, PlasmaOneCard.source,
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
        let followed = followedWallets()
        let cards: [Raw] = things.compactMap { thing in
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
            case MetaMaskCardBridge.source, EtherFiCash.source, PlasmaOneCard.source:
                // The chain names no merchant for any of the three cards, so
                // the card is the place. Plasma One's row is a day's total
                // (prd §1311), which a sum by place adds exactly the same.
                // A card read off a wallet the person no longer follows is
                // not theirs (prd §1330).
                guard CardSpendSeat.isSpend(thing, seat: thing.source),
                      thing.walletAddress.map({ followed.contains($0.lowercased()) }) ?? true,
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
            default:
                return nil
            }
        }
        return cards + walletCharges(things, followed: followed)
    }

    /// The wallets the person follows NOW, lowercased, each in its watched
    /// and its resolved spelling (prd §1330). Never the wallets the rows
    /// were read for: a wallet or Safe that was unfollowed leaves rows
    /// behind until the prune reaches them, and those were never yours.
    @MainActor
    static func followedWallets() -> Set<String> {
        WalletStore.shared.followedForms()
    }

    /// The `Wallet` rows' sends, through `Spending.walletSpends` — the one
    /// rule for which onchain sends are spending (prd §1201, §1330).
    @MainActor
    static func walletCharges(_ things: [Thing], followed own: Set<String>) -> [Raw] {
        let moves: [Spending.Move] = things.compactMap { thing in
            guard thing.kind == .transaction, thing.source == SpendingReading.walletSource,
                  let wallet = thing.walletAddress?.lowercased() else { return nil }
            let way: Spending.Move.Way
            if thing.sourceRef?.hasPrefix("wallet:swap:") ?? false {
                way = .swap
            } else if thing.transferDirection == "sent" {
                way = .sent
            } else if thing.transferDirection == "received" || thing.transferDirection == WalletActionMark.minted {
                way = .received
            } else {
                return nil
            }
            // Every leg of one transaction opens the same explorer page.
            let tx = thing.content.isEmpty ? (thing.sourceRef ?? thing.id.uuidString) : thing.content.lowercased()
            let to = thing.counterpartyAddress?.lowercased()
            return Spending.Move(
                wallet: wallet, tx: tx, way: way,
                usd: thing.transferUSD, at: thing.capturedAt,
                counterparty: to,
                operation: operation(of: thing),
                machinery: way == .sent && to.map(isMachinery) ?? false,
                place: thing.transferCounterparty.flatMap { $0.isEmpty ? nil : $0 }
                    ?? thing.counterpartyAddress.map(WalletStore.shortAddress))
        }
        return Spending.walletSpends(moves, own: own).compactMap { move in
            guard let place = move.place, let usd = move.usd else { return nil }
            return Raw(place: place, amount: usd, currency: "USD", at: move.at)
        }
    }

    /// Machinery is not a place you spent at: a router or an onramp trades
    /// the money back, and a card's Safe tops up a card whose spends are
    /// counted at the card. A person, an exchange's deposit address and an
    /// address nobody named are where money went.
    @MainActor
    private static func isMachinery(_ address: String) -> Bool {
        if WalletIngest.isKnownContract(address) { return true }
        switch AddressBook.shared.entry(for: address)?.kind {
        case .contract?, .safe?: return true
        default: return false
        }
    }

    // MARK: - What the read called a transaction

    /// The label a sent leg's operation fact carries. Never drawn: the
    /// action is rowless.
    static let operationLabel = "Operation"

    /// What the read (Zerion) called the transaction a SENT leg belongs to,
    /// when it was anything but a plain send — "trade", "deposit",
    /// "execute" — or nil. Stamped at landing and by the heal
    /// (`WalletIngest`), read by Spending: a send the read called a trade
    /// is half a swap whose other half never landed, never a purchase.
    static func operation(of thing: Thing) -> String? {
        thing.factList.first { $0.action == .operation }?.value
    }

    /// Stamps `operation` on a sent leg, once. A plain "send" is the
    /// absence of the fact. Returns whether the thing changed.
    @discardableResult
    static func stampOperation(_ thing: Thing, _ operation: String?) -> Bool {
        guard let operation, !operation.isEmpty, operation != "send",
              Self.operation(of: thing) == nil else { return false }
        thing.facts.append(ThingFact(operationLabel, operation, .operation).encoded)
        return true
    }
}
