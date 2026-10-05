import Foundation
import Observation
import SwiftData

/// Day's Subscriptions tile, its READING half (prd §1111): the mail seats'
/// landed mail, through `MailSubscriptions`. Its own fetch, as the Wallet's
/// tile has (`SubscriptionsReading`): the room's query is bounded, and a
/// year of newsletters would push a list's older issues past it. Run from a
/// `.task`, never a body (prd §628). A mail files by its list header, or
/// because the person added its sender (`MailSubscriptionStore`, prd §1115).
@Observable
@MainActor
final class MailSubscriptionsReading {
    static let shared = MailSubscriptionsReading()

    private(set) var items: [MailSubscriptions.Item] = []
    /// True once a read has finished, so the tile can tell "none" from "not yet".
    private(set) var read = false

    private init() {}

    /// The seats a list's mail lands in.
    static let sources: [String] = [MailProvider.gmail.source, MailProvider.icloud.source]

    func refresh(_ context: ModelContext, now: Date = .now) {
        let members = Self.sources
        var d = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { members.contains($0.source) },
                                       sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        // Every column the loop below reads (prd §722).
        d.propertiesToFetch = [\.id, \.source, \.facts, \.authorHandle, \.authorEmail, \.capturedAt]
        let things = ((try? context.fetch(d)) ?? []).live
        let landed: [MailSubscriptions.Landed] = things.map { thing in
            let facts = thing.factList
            return .init(id: thing.id,
                         listKey: facts.first(where: { $0.action == .list })?.value,
                         sender: MailSubscriptions.senderName(thing.authorHandle),
                         address: MailSubscriptions.address(thing.authorEmail, sender: thing.authorHandle),
                         unsubscribe: facts.first { $0.action == .unsubscribe }.map { "<\($0.value)>" },
                         at: thing.capturedAt, source: thing.source)
        }
        // A header files a mail; so does a sender the person added (§1115).
        let mails = MailSubscriptions.file(landed, added: MailSubscriptionStore.shared.addresses)
        let composed = MailSubscriptions.compose(mails, now: now)
        if composed != items { items = composed }
        read = true
    }

    /// The list a landed mail is on, if any — a mail's sheet asks, to draw
    /// its door to the list or the add (prd §1115).
    func item(holding mail: UUID) -> MailSubscriptions.Item? {
        items.first { $0.mailIDs.contains(mail) }
    }

    /// The lists a scoped room shows: every one on All, and on an app's pick
    /// only what landed in that app.
    func items(in sources: Set<String>?) -> [MailSubscriptions.Item] {
        guard let sources else { return items }
        return items.filter { !Set($0.sources).isDisjoint(with: sources) }
    }
}
