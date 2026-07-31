import Foundation
import SwiftData

/// The Tokens-watchlist join, at BROWSE time (2026-07-30).
///
/// `PredictionMoments.checkCrossings` already fires this exact comparison —
/// a watched market's title naming a token already on the Tokens
/// watchlist — but only as a post-FOLLOW moment, once per pair, ever
/// (UserDefaults-guarded). That means the crossing was invisible at the
/// one point it could actually change a decision: browsing "Bitcoin above
/// $150k this year?" without knowing you already watch BTC is exactly the
/// gap `PredictionDisagreement` filled for the twin-venue case, applied
/// here to the token case. Deliberately NOT a duplicate moment-firing path —
/// this only READS the corpus and returns a label; `PredictionMoments` still
/// owns the one-time delight fire.
@MainActor
enum PredictionCrossings {
    /// Filtered `.live` at THIS boundary (build-177 corollary 4) — the
    /// caller holds the result in `@State` across a load cycle, during
    /// which a foreground heal can delete a Tokens row out from under it.
    static func watchedTokens(context: ModelContext) -> [Thing] {
        let d = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == "Tokens" })
        return ((try? context.fetch(d)) ?? []).live
    }

    /// The first watched token this title names, if any — reuses
    /// `PredictionMoments.significantWords`/subset test exactly, so "is this
    /// the same thing?" has one answer whether it's asked at browse time or
    /// at follow time.
    static func crossing(for title: String, tokens: [Thing]) -> String? {
        guard !tokens.isEmpty else { return nil }
        let marketWords = PredictionMoments.significantWords(title)
        for token in tokens {
            let name = TokensAsk.name(of: token.title)
            let nameWords = PredictionMoments.significantWords(name)
            guard !nameWords.isEmpty, nameWords.isSubset(of: marketWords) else { continue }
            return name
        }
        return nil
    }
}
