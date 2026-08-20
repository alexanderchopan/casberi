import Foundation

/// "Are these two exchanges asking the same question?" — the one definition
/// of that test, shared by every caller that needs it (`PredictionTwin`,
/// `PredictionDisagreement`, `PredictionCrossings`).
///
/// Extracted from the old `PredictionMoments` when the in-app moment bus was
/// removed (2026-08-19): the four moments that file existed to fire are gone,
/// but the matching rule underneath them was never about moments — it is what
/// lets a Kalshi market find its Polymarket twin, which the room still draws.
/// Kept as one function rather than re-derived per caller, since two copies
/// drift and then the same pair of markets is "the same question" in one place
/// and two different ones in another.
enum PredictionTitles {

    /// Loose title matching across two exchanges that phrase the same
    /// question differently — shared significant words, not exact equality
    /// (exact string equality across two copy styles would almost never fire).
    static func match(_ a: String, _ b: String) -> Bool {
        let wordsA = significantWords(a)
        guard !wordsA.isEmpty else { return false }
        let shared = wordsA.intersection(significantWords(b))
        return Double(shared.count) / Double(wordsA.count) >= 0.6
    }

    private static let stopWords: Set<String> = [
        "will", "the", "a", "an", "to", "in", "on", "by", "of", "for",
        "win", "wins", "be", "is", "at", "or", "than", "before",
    ]

    /// Not `private` — `PredictionCrossings` reuses this exact test at
    /// browse time (2026-07-30), so "are these the same thing?" has one
    /// definition whichever caller asks it.
    static func significantWords(_ s: String) -> Set<String> {
        Set(s.lowercased().split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 2 && !stopWords.contains($0) })
    }
}
