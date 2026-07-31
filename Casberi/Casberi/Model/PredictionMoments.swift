import Foundation
import SwiftData

/// Delight for the two prediction-market bridges (2026-07-28, alongside
/// Polymarket) — the shape only this category has: a market doesn't just
/// move, it eventually resolves into a fact. Four moments, all self-
/// throttled and silent on first sight (a baseline is never a moment, same
/// doctrine as every other file riding `SourceMoments`):
///
/// 1. RESOLUTION RECEIPT — a watched market settles. Names the odds the day
///    you watched it, never a payout — the 5.3 line: this reports your
///    ATTENTION, never money. No P&L, no stake, no "you'd have won $X" —
///    that sentence is a betting app's, not this one's.
/// 2. THE FLIP — a watched market crosses 50%. Symmetric both directions,
///    unlike the wallet's new-high: a favorite changing is news either way.
/// 3. DISAGREEMENT — the same real-world event watched on BOTH Kalshi and
///    Polymarket, odds diverging — a pure local join, no extra network call,
///    and something no single-market app can ever show.
/// 4. CORPUS CROSSING — a watched market's title names a token already on
///    the Tokens watchlist — the SocialMoments.checkSlackCrossings shape
///    (a comparison across two bridges' own landed things, zero network).
///
/// PredictionPulse.refresh is the only caller, once per foreground pass.
@MainActor
enum PredictionMoments {

    private static let flipBand: Double = 0.5

    static func check(_ refreshed: [(thing: Thing, before: Double?, market: PredictionMarket)],
                      context: ModelContext) {
        guard !refreshed.isEmpty else { return }
        for entry in refreshed {
            checkResolution(entry)
            checkFlip(entry)
        }
        checkDisagreement(refreshed.map(\.market))
        checkCrossings(refreshed.map(\.thing), context: context)
    }

    // MARK: 1. Resolution receipt

    private static func checkResolution(_ entry: (thing: Thing, before: Double?, market: PredictionMarket)) {
        let thing = entry.thing
        let market = entry.market
        guard market.resolved, let yesWon = market.yesWon, let ref = thing.sourceRef,
              // The anchor: the probability the moment you started watching —
              // Tokens' since-you-watched field, reused for a 0...1
              // probability instead of a dollar price (KalshiWatch.add /
              // PolymarketBridge.add both set this at watch time).
              let watchProb = thing.watchPriceUsd
        else { return }
        let key = "moment.resolved.\(ref)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let pct = Int((watchProb * 100).rounded())
        let line: String = if yesWon {
            pct <= 25
                ? String(localized: "You watched this at \(pct)%. It happened.")
                : String(localized: "Resolved: \(thing.title) — you were watching at \(pct)%")
        } else {
            String(localized: "Resolved: \(thing.title) didn't happen — you were watching at \(pct)%")
        }
        SourceMoments.shared.fire(line, source: market.source.rawValue)
    }

    // MARK: 2. The flip

    private static func checkFlip(_ entry: (thing: Thing, before: Double?, market: PredictionMarket)) {
        let thing = entry.thing
        let market = entry.market
        // A thin book crosses 50% on a single small order — that's noise
        // wearing a headline, not a favorite changing. Only a market with
        // real trade behind it can fire this.
        guard !market.resolved, !market.isThin, let before = entry.before else { return }
        let crossed = (before < flipBand && market.probability >= flipBand)
                   || (before >= flipBand && market.probability < flipBand)
        guard crossed else { return }
        let pct = Int((market.probability * 100).rounded())
        let line = market.probability >= flipBand
            ? String(localized: "\(thing.title) flipped — now \(pct)%")
            : String(localized: "\(thing.title) flipped — now \(100 - pct)% the other way")
        SourceMoments.shared.fire(line, source: market.source.rawValue)
    }

    // MARK: 3. Disagreement across bridges

    /// Only markets that refreshed THIS pass are compared — a disagreement
    /// is news the moment it's noticed, not a standing fact re-announced
    /// every foreground.
    private static func checkDisagreement(_ markets: [PredictionMarket]) {
        let kalshi = markets.filter { $0.source == .kalshi && !$0.resolved }
        let poly = markets.filter { $0.source == .polymarket && !$0.resolved }
        guard !kalshi.isEmpty, !poly.isEmpty else { return }
        for k in kalshi {
            for p in poly {
                guard titlesMatch(k.title, p.title) else { continue }
                let diff = abs(k.probability - p.probability)
                guard diff >= 0.10 else { continue }
                let key = "moment.disagree.\(k.id).\(p.id)"
                guard !UserDefaults.standard.bool(forKey: key) else { continue }
                UserDefaults.standard.set(true, forKey: key)
                let kPct = Int((k.probability * 100).rounded())
                let pPct = Int((p.probability * 100).rounded())
                SourceMoments.shared.fire(
                    String(localized: "Kalshi says \(kPct)%, Polymarket says \(pPct)% — same question, different odds"),
                    source: nil)
            }
        }
    }

    /// Loose title matching across two exchanges that phrase the same
    /// question differently — shared significant words, not exact equality
    /// (exact string equality across two copy styles would almost never fire).
    /// Shared with the twin-offer path (`PredictionTwin`), so the question
    /// "are these the same market?" has exactly one answer in the app.
    static func titlesMatch(_ a: String, _ b: String) -> Bool {
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

    // MARK: 4. Corpus crossing

    /// A watched market naming a token already on the Tokens watchlist —
    /// e.g. a Polymarket "Will Bitcoin reach $X" market against a watched
    /// BTC. Zero network cost: both sides are already-landed things.
    private static func checkCrossings(_ markets: [Thing], context: ModelContext) {
        let tokensDescriptor = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == "Tokens" })
        guard let tokens = try? context.fetch(tokensDescriptor), !tokens.isEmpty else { return }
        for market in markets {
            guard let ref = market.sourceRef else { continue }
            let marketWords = significantWords(market.title)
            for token in tokens {
                let name = TokensAsk.name(of: token.title)
                let nameWords = significantWords(name)
                guard !nameWords.isEmpty, nameWords.isSubset(of: marketWords) else { continue }
                let key = "moment.crossing.\(ref).\(token.sourceRef ?? name)"
                guard !UserDefaults.standard.bool(forKey: key) else { continue }
                UserDefaults.standard.set(true, forKey: key)
                SourceMoments.shared.fire(
                    String(localized: "\(market.title) — you're already watching \(name)"), source: nil)
            }
        }
    }
}
