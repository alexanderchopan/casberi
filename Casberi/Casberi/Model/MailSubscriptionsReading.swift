import Foundation
import Observation
import SwiftData

/// Day's Subscriptions tile, its READING half (prd §1111): the mail seats'
/// landed mail, through `MailSubscriptions`. Its own fetch, as the Wallet's
/// tile has (`SubscriptionsReading`): the room's query is bounded, and a
/// year of newsletters would push a list's older issues past it. Run from a
/// `.task`, never a body (prd §628).
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
        var mails: [MailSubscriptions.Mail] = []
        for thing in things {
            let facts = thing.factList
            guard let key = facts.first(where: { $0.action == .list })?.value else { continue }
            mails.append(.init(id: thing.id, key: key,
                               sender: thing.authorHandle ?? key,
                               address: thing.authorEmail,
                               unsubscribe: facts.first { $0.action == .unsubscribe }.map { "<\($0.value)>" },
                               at: thing.capturedAt, source: thing.source))
        }
        let composed = MailSubscriptions.compose(mails, now: now)
        if composed != items { items = composed }
        read = true
    }

    /// The lists a scoped room shows: every one on All, and on an app's pick
    /// only what landed in that app.
    func items(in sources: Set<String>?) -> [MailSubscriptions.Item] {
        guard let sources else { return items }
        return items.filter { !Set($0.sources).isDisjoint(with: sources) }
    }
}
