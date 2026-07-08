import Foundation
import Observation

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
