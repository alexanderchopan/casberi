import Foundation
import SwiftData

/// "Because of what you keep" — the Discover deck's corpus-aware seats
/// (2026-07-21, the app-catalog surprise-&-delight pass). App-to-app adjacency
/// ("Goes with GitHub") already reads as the store knowing your SETUP; this
/// reads what's actually in your corpus and suggests the bridge that would keep
/// more of it. Every reason is a real count over your things — the same
/// honesty `AggregateAsk` holds: no model, no guess, an eyebrow that states a
/// fact you could verify yourself.
///
/// Kind filters happen in memory after a plain fetch — the §36v rule (a
/// `#Predicate` can't compare the Codable `ThingKind`, and a `try?` made the
/// miss silent). The whole corpus is read once per Apps appearance, not per
/// frame.
enum CatalogTaste {

    /// A suggested offer plus the honest reason it surfaced.
    struct Reason {
        let offerName: String
        let eyebrow: String
        /// The count behind it — used only to order stronger signals first.
        let weight: Int
    }

    /// A kind you keep a lot of, and the offers that would keep more of it.
    /// One kind can point at several offers (links → Readwise, RSS); the deck's
    /// own dedupe + not-connected guard picks whichever seat is still open.
    private struct Signal {
        let kind: ThingKind
        let eyebrow: String
        let offers: [String]
    }

    /// The signals, strongest-intent first. Each names a real capture habit and
    /// the bridge that serves it — never a stretch (a screenshot habit points
    /// at Photos, not at "you might like NFTs").
    private static let signals: [Signal] = [
        Signal(kind: .link,       eyebrow: "You save a lot of links",  offers: ["Readwise", "RSS", "Raindrop"]),
        Signal(kind: .screenshot, eyebrow: "You screenshot a lot",     offers: ["Photos"]),
        Signal(kind: .chat,       eyebrow: "You keep a lot of chats",  offers: ["Claude", "ChatGPT"]),
        Signal(kind: .event,      eyebrow: "Your days fill up",        offers: ["Calendar", "Cal.com"]),
        Signal(kind: .transaction, eyebrow: "You watch onchain",       offers: ["Tokens", "OpenSea"]),
    ]

    /// A habit has to be a HABIT, not a one-off — five of a kind before the
    /// store reads anything into it.
    private static let floor = 5

    /// The corpus-derived reasons, strongest first. `context` is the app's own
    /// model context. Returns nothing when the corpus is too thin to read —
    /// silence is the honest default, and the deck backfills as before.
    @MainActor
    static func reasons(context: ModelContext) -> [Reason] {
        let things = (try? context.fetch(FetchDescriptor<Thing>())) ?? []
        guard things.count >= floor else { return [] }

        var counts: [ThingKind: Int] = [:]
        for thing in things { counts[thing.kind, default: 0] += 1 }

        return signals.compactMap { signal -> Reason? in
            let n = counts[signal.kind] ?? 0
            guard n >= floor, let offer = signal.offers.first else { return nil }
            // The eyebrow names the offer set's shared reason; the deck resolves
            // which specific offer's seat is still open, so pass them all as
            // candidates ordered by the signal's own preference.
            return Reason(offerName: offer, eyebrow: signal.eyebrow, weight: n)
        }
        .sorted { $0.weight > $1.weight }
    }

    /// All candidate offer names for a given first suggestion — lets the deck
    /// fall through to the next offer in a signal when the first is already
    /// connected (links → Readwise taken → RSS).
    static func candidates(for offerName: String) -> [String] {
        signals.first { $0.offers.first == offerName }?.offers ?? [offerName]
    }
}
