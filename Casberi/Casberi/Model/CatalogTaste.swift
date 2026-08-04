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
        /// The eyebrow, built from the real count. Stating the NUMBER rather
        /// than "a lot" (2026-08-04): the count was already computed and then
        /// thrown away on the way to the screen, so five cards asserted a
        /// vague claim where they could have stated a fact the person can
        /// check against their own feed. Specific beats emphatic, and it is
        /// the same instinct as the setup screens' "3 games in" — a number you
        /// can verify is worth more than an adjective you can't.
        let eyebrow: (Int) -> String
        let offers: [String]
    }

    /// The signals, strongest-intent first. Each names a real capture habit and
    /// the bridge that serves it — never a stretch (a screenshot habit points
    /// at Photos, not at "you might like NFTs").
    ///
    /// Widened 2026-08-04 from five kinds to nine: notes, products, reminders
    /// and files were unreadable signals, so a corpus made mostly of any of
    /// them got no taste seat at all and fell through to the plain backfill —
    /// the deck read as knowing you only if you happened to be a link-and-
    /// screenshot person.
    /// `String(localized:)` at build time, not a `LocalizedStringKey` at
    /// render time: the deck renders an eyebrow through
    /// `Text(LocalizedStringKey(…))`, which for a string built at runtime can
    /// only ever fall back to the string itself — so an interpolated eyebrow
    /// has to arrive already localized, the way every other counted line in
    /// the app does (`"\(added) \(bridge.noun) in"`).
    private static let signals: [Signal] = [
        Signal(kind: .link,        eyebrow: { String(localized: "You've saved \($0) links") },      offers: ["Readwise", "RSS", "Raindrop"]),
        Signal(kind: .screenshot,  eyebrow: { String(localized: "\($0) screenshots in here") },     offers: ["Photos"]),
        Signal(kind: .chat,        eyebrow: { String(localized: "You've kept \($0) chats") },       offers: ["Claude", "ChatGPT"]),
        Signal(kind: .event,       eyebrow: { String(localized: "\($0) things on your calendar") }, offers: ["Calendar", "Cal.com"]),
        Signal(kind: .transaction, eyebrow: { String(localized: "\($0) onchain moves kept") },      offers: ["Tokens", "OpenSea"]),
        Signal(kind: .note,        eyebrow: { String(localized: "You've written \($0) notes") },    offers: ["Obsidian", "Apple Notes", "Day One"]),
        Signal(kind: .product,     eyebrow: { String(localized: "You're watching \($0) things") },  offers: ["Deals", "Shopify"]),
        Signal(kind: .reminder,    eyebrow: { String(localized: "\($0) things to do") },            offers: ["Todoist", "Reminders"]),
        Signal(kind: .file,        eyebrow: { String(localized: "\($0) files in here") },           offers: ["Dropbox", "Files"]),
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
            return Reason(offerName: offer, eyebrow: signal.eyebrow(n), weight: n)
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
