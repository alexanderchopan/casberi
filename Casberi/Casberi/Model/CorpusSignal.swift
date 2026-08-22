import Foundation
import Observation
import SwiftData

/// A bump every time the corpus changes in a way `things.count` doesn't catch —
/// a tag rename, a bulk retag. Home composes from tags, so a rename must
/// repaint it (the count is unchanged, so `onChange(of: count)` never fires).
/// Organize writes bump this; Home observes it and recomposes.
@Observable
final class CorpusSignal {
    static let shared = CorpusSignal()
    private(set) var revision = 0
    func bump() { revision += 1 }
    private init() {}
}

extension Corpus {
    /// What a surface watches to know the corpus changed — the pair a
    /// `.task(id:)` or `onChange(of:)` should key on (2026-08-12).
    ///
    /// TWO terms, because neither catches what the other does:
    ///
    ///   • `count` catches arrivals and deletions, and nothing else. It is a
    ///     SQL `COUNT`, so unlike a bounded `@Query`'s `.count` it has no
    ///     ceiling and materialises no models (see `Corpus.count`).
    ///   • `signal` catches an IN-PLACE change — a retitle, a retag, a bulk
    ///     reorganise — which by definition moves no count. `CorpusSignal` was
    ///     built for exactly this and had NINE writers and no reader at all:
    ///     its doc says "Home observes it and recomposes", Home retired
    ///     2026-07-20, and its only reader went with it. This is that reader.
    ///
    /// A PAIR rather than a sum, so the two can never cancel: a delete landing
    /// in the same pass as a retag moves count down one and signal up one, and
    /// added together that is the number we started with — an update the
    /// screen would silently skip.
    ///
    /// `.idle` is for a surface that has nothing to watch (a room whose own
    /// predicated query already coordinates it). Distinct from a real zero, so
    /// an empty corpus still reads as a change when the first thing lands.
    struct Revision: Equatable {
        let count: Int
        let signal: Int
        static let idle = Revision(count: -1, signal: -1)
    }

    /// Reading `CorpusSignal.shared.revision` HERE is what registers the
    /// observation: this is called from a body-evaluated key expression, so
    /// `@Observable` ties the view to it and a `bump()` invalidates.
    @MainActor
    static func revision(in context: ModelContext) -> Revision {
        Revision(count: count(in: context), signal: CorpusSignal.shared.revision)
    }

    /// The same pair, scoped to ONE source (PERF 2026-08-21).
    ///
    /// A source room already has a predicated `@Query` coordinating its ROWS,
    /// which is why `.idle` was the right answer for everything a room's own
    /// list does. It is the wrong answer for anything computed ABOUT the room —
    /// the head chain — because that needs a key it can be memoised against,
    /// and the only key available was `things.count`, which is the property
    /// wrapper's getter and therefore materialises every row it counts (the
    /// 2026-08-06 measurement, and the trap `corpusRevision`'s own doc records).
    ///
    /// A scoped SQL `COUNT` answers the same question with no model
    /// instantiation at all. The `signal` term is deliberately the GLOBAL one:
    /// `CorpusSignal` doesn't record which source a retag touched, and a head
    /// recomputed once too often is a cost, while one recomputed too rarely is
    /// a card that disagrees with the rows under it.
    @MainActor
    static func revision(in context: ModelContext, source: String) -> Revision {
        var d = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == source })
        d.propertiesToFetch = []
        let n = (try? context.fetchCount(d)) ?? 0
        return Revision(count: n, signal: CorpusSignal.shared.revision)
    }
}
