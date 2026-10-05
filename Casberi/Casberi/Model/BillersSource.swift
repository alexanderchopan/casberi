import Foundation
import SwiftData

/// The billers' READING half (prd §1106): the Subscriptions tile's own
/// sources and parsers (`SubscriptionsSource`), composed by `Billers`, for the
/// Addresses index. Main-actor, as every store it reads is; it runs from the
/// index's rebuild (a probe or a foreground sweep), never from a body (§628).
@MainActor
enum BillersSource {

    /// The billers as of the last `read`, by their identity key
    /// (`biller:<merchant>`), for the contact sheet's facts.
    private(set) static var byKey: [String: Billers.Biller] = [:]

    /// One fetch of the billing seats, composed, and the snapshot replaced.
    @discardableResult
    static func read(context: ModelContext, now: Date = .now) -> [Billers.Biller] {
        let members = SubscriptionsReading.sources
        let d = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { members.contains($0.source) },
                                       sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        let things = ((try? context.fetch(d)) ?? []).live
        let billers = Billers.compose(found: SubscriptionsSource.found(from: things, now: now),
                                      bills: SubscriptionsSource.bills(from: things, now: now),
                                      manual: SubscriptionStore.shared.all, now: now)
        var keyed: [String: Billers.Biller] = [:]
        for biller in billers {
            let key = Identity.key(.biller, biller.item.name)
            if keyed[key] == nil { keyed[key] = biller }
        }
        byKey = keyed
        return billers
    }

    /// The merchant a billing seat's row names, nil for any other row: a
    /// card charge's counterparty (Apple Wallet, Privacy.com — what
    /// `SubscriptionsSource.payer` accepts), or a Rocket Money bill's name.
    /// A wallet transfer's counterparty is NEVER a merchant here, or every
    /// named address would grow a biller twin.
    static func merchant(of thing: Thing) -> String? {
        switch thing.source {
        case AppleWalletBridge.sourceName, WalletCards.privacySource:
            guard thing.kind == .transaction, SubscriptionsSource.payer(of: thing) != nil,
                  let name = thing.transferCounterparty, !name.isEmpty else { return nil }
            return name
        case RocketMoneyLive.source:
            guard thing.dueAt != nil else { return nil }
            let name = TitleSeam.split(thing.title).name
            return name.isEmpty ? nil : name
        default:
            return nil
        }
    }

    // MARK: - Category

    /// The category a biller files under in Addresses (prd §1106a): the
    /// catalogue's own category when the merchant IS an app there (Claude in
    /// Agents, Linear in Work), else Wallet. The merchant is matched by name,
    /// cased as the card cased it, and again without a web suffix
    /// ("Netflix.com", "CLAUDE.AI") — never by `contains`, which files "Apple
    /// Store" under Apple Music.
    nonisolated static func category(ofMerchant raw: String) -> String {
        // The name's forms are `ServiceIdentity`'s, the one rule for "the
        // same service", so Addresses and the doors between a plan, its app
        // and its mail cannot disagree.
        for candidate in ServiceIdentity.names(raw) {
            if let category = categoryByOfferName[candidate] { return category }
        }
        return fallbackCategory
    }

    /// A biller the catalogue does not know is money, and money is Wallet.
    nonisolated static let fallbackCategory = "Wallet"

    /// Every catalogue offer's name, lowercased, to its category — built once.
    nonisolated private static let categoryByOfferName: [String: String] = {
        var out: [String: String] = [:]
        for offer in BridgeCatalog.allOffers where out[offer.name.lowercased()] == nil {
            out[offer.name.lowercased()] = BridgeCatalog.category(of: offer)
        }
        return out
    }()

    /// How many of each billing seat's newest rows a biller's sheet reads
    /// for its charges — a year of a busy card, bounded.
    static let chargeWindow = 1_000

    /// A biller's charges and bills, newest first: each billing seat's newest
    /// rows, matched to the key in Swift (a `.contains` predicate is the
    /// trap CLAUDE.md records, and the key is a fold of the stored name).
    static func things(forKey key: String, context: ModelContext, limit: Int,
                       keep: (Thing) -> Bool = { _ in true }) -> [Thing] {
        var out: [Thing] = []
        for source in SubscriptionsReading.sources {
            var d = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == source },
                                           sortBy: [SortDescriptor(\Thing.capturedAt, order: .reverse)])
            d.fetchLimit = chargeWindow
            for thing in (try? context.fetch(d)) ?? [] where keep(thing) {
                guard let name = merchant(of: thing), Identity.key(.biller, name) == key else { continue }
                out.append(thing)
            }
        }
        return Array(out.sorted { $0.capturedAt > $1.capturedAt }.prefix(limit))
    }
}
