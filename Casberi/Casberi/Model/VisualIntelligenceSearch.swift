import AppIntents
import Foundation
#if canImport(VisualIntelligence)
import VisualIntelligence
#endif

/// Visual Intelligence (iOS 26) — point the camera at something, or circle it
/// in a screenshot, and Casberi is one of the apps that can answer: the
/// system's labels for what's on screen run against the corpus, and matching
/// things come back as tappable entity cards (OpenThingIntent opens the
/// sheet). On-brand for a screenshot-heavy corpus: the thing you saved about
/// an espresso machine surfaces when you're looking at one.

/// The label→corpus matcher, shared by the system query below and the
/// `-viProbe` headless hook (Visual Intelligence's own UI can't be driven on
/// the simulator, so the probe exercises this function directly). Each label
/// that carries a usable term runs through the intents' shared matcher; merged
/// hits come back deduped, newest first. A label with NO usable term is
/// dropped rather than passed through — `IntentCorpus.match` treats an empty
/// term list as "everything, newest first" (the Search intent's browse
/// fallback), which here would dump the whole corpus into every camera frame.
enum VisualCorpusMatch {
    static func things(for labels: [String], limit: Int = 10) -> [Thing] {
        // One corpus fetch for the whole frame — several labels arrive at
        // once, and each in-memory match below is cheap against it.
        let corpus = (try? IntentCorpus.corpus()) ?? []
        var seen = Set<UUID>()
        var out: [Thing] = []
        for label in labels {
            let hasTerm = label.lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "? "))
                .split(separator: " ")
                .contains { $0.count > 2 }
            guard hasTerm else { continue }
            let hits = IntentCorpus.match(label, in: corpus, limit: limit)
            for thing in hits where seen.insert(thing.id).inserted {
                out.append(thing)
            }
        }
        return Array(out.sorted { $0.capturedAt > $1.capturedAt }.prefix(limit))
    }
}

#if canImport(VisualIntelligence)
/// The system entry point. Labels only, pixel buffer unused on purpose — the
/// corpus has no image-similarity index, and matching the system's own words
/// for the scene is honest; pretending to match pixels would not be.
@available(iOS 26.0, *)
struct ThingVisualIntelligenceQuery: IntentValueQuery {
    func values(for input: SemanticContentDescriptor) async throws -> [ThingEntity] {
        VisualCorpusMatch.things(for: input.labels).map(ThingEntity.init)
    }
}
#endif
