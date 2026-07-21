import Foundation
import SwiftData

/// Watchlist asks (2026-07-14) — "how's my watchlist", "how are my tokens
/// doing". The ask names no corpus content to score, so retrieval has nothing
/// to ground on; the answer is the same 24h curves the feed pulse draws —
/// computed, current, no model. Also home of the away recap's token line:
/// each watched token's move over the frozen away window, from real candles
/// at the window's own resolution.
enum TokensAsk {

    /// True when the WHOLE ask is about the watchlist — the same residual
    /// discipline StatusAsk uses: after the cue and filler words, anything
    /// left is CONTENT, and content belongs to the scored retriever ("what
    /// did sam say about my tokens" is a search, not a price readout).
    static func matches(_ raw: String) -> Bool {
        let q = raw.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: CharacterSet(charactersIn: "?!. "))
        guard q.contains("watchlist") || q.contains("my tokens") || q.contains("my coins")
        else { return false }
        var words = q.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let filler: Set<String> = [
            "how", "hows", "s", "is", "are", "was", "were", "my", "the", "a",
            "doing", "going", "performing", "looking", "what", "whats", "about",
            "on", "with", "tokens", "token", "coins", "coin", "watchlist",
            "today", "now", "right", "up", "down", "tell", "me", "check",
        ]
        words.removeAll { filler.contains($0) }
        return words.isEmpty
    }

    /// The watched-token things — one fetch shape for the ask, the away
    /// line, and the honest empty (so the three can never disagree about
    /// what "watched" means).
    @MainActor
    static func watched(_ context: ModelContext) -> [Thing] {
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate {
            $0.source == "Tokens"
        })
        return (try? context.fetch(descriptor)) ?? []
    }

    struct Move {
        let thing: Thing
        let symbol: String
        let price: Double
        let change: Double   // fraction over 24h
    }

    /// Every watched token's 24h move, biggest swing first — read through
    /// TokenPulse's cache (refreshed if stale), so this answer and the feed
    /// rows can never disagree about the same token.
    @MainActor
    static func moves(context: ModelContext) async -> [Move] {
        await TokenPulse.shared.refresh(context: context)
        return watched(context).compactMap { thing -> Move? in
            guard let pulse = TokenPulse.shared.pulse(for: thing),
                  let price = pulse.closes.last else { return nil }
            return Move(thing: thing, symbol: symbol(of: thing.title),
                        price: price, change: pulse.change24h)
        }
        .sorted { abs($0.change) > abs($1.change) }
    }

    /// "Over the last 24h: DEGEN -12.4%, PEPE +3.1%, ETH +0.8%." — the same
    /// formatter the delta pills use, so the line and the rows can't
    /// disagree about a sign's shape.
    static func line(_ moves: [Move]) -> String {
        let parts = moves.prefix(5).map { "\($0.symbol) \(TokenChartStyle.changeText($0.change))" }
        return "Over the last 24h: \(parts.joined(separator: ", "))."
    }

    /// The watchlist's line for the away recap — each watched token's change
    /// over the away window itself, computed from real candles at the range
    /// that covers it (hourly for a day or a week, daily beyond). A window
    /// past the 30-day candles says "over the last 30 days" instead — the
    /// line never claims a window the data doesn't span. Coarse-fallback
    /// tokens (no real candles anywhere) are left out rather than guessed.
    @MainActor
    static func awayLine(window: Range<Date>, context: ModelContext) async -> String? {
        let routes = watched(context).compactMap { t -> (symbol: String, chain: String, address: String)? in
            guard let route = TokenChart.route(from: t.content) else { return nil }
            return (symbol(of: t.title), route.chain, route.address)
        }
        guard !routes.isEmpty else { return nil }

        let gap = window.upperBound.timeIntervalSince(window.lowerBound)
        let range: TokenRange = gap <= 86_400 ? .day
            : (gap <= 7 * 86_400 ? .week : .month)
        // Capped at 8 tokens — the recap wants the movers, not a census, and
        // each token is up to 3 GETs; the line shows 4 anyway.
        let charts = await IngestSupport.boundedGather(Array(routes.prefix(8)),
                                                       maxConcurrent: 4) { r in
            (r.symbol, await TokenChart.fetch(chain: r.chain, address: r.address,
                                              range: range))
        }
        // A gap past the 30-day candles gets the candles' own window; either
        // way the LABELED window is what every counted token must span.
        let capped = gap > Double(TokenRange.month.ohlcv.limit) * TokenRange.month.step
        let labeledWindow = min(gap, Double(TokenRange.month.ohlcv.limit) * TokenRange.month.step)
        let back = Int((labeledWindow / range.step).rounded(.up))

        var moves: [(symbol: String, change: Double)] = []
        for (sym, chart) in charts {
            guard let chart, !chart.coarse, chart.closes.count >= 2,
                  let last = chart.closes.last else { continue }
            // The candle nearest the window's start, clamped to the oldest —
            // candles-as-hours is the app's standing chart assumption (the
            // sheet's scrub makes the same one); a quiet pool returns SPARSE
            // candles, so demanding a full count would silently drop real
            // tokens from the line.
            let first = chart.closes[max(0, chart.closes.count - 1 - back)]
            guard first > 0 else { continue }
            moves.append((sym, (last - first) / first))
        }
        guard !moves.isEmpty else { return nil }
        moves.sort { abs($0.change) > abs($1.change) }
        let parts = moves.prefix(4).map { "\($0.symbol) \(TokenChartStyle.changeText($0.change))" }
        let windowWords = capped ? "over the last 30 days" : "while you were away"
        return "Your watchlist \(windowWords): \(parts.joined(separator: ", "))."
    }

    /// The bare ticker from "Name · $TICKER" (TokenWatch's title format) —
    /// the whole title when the format doesn't match. The one parser of the
    /// watch-title format (HomeComposition's pinned-tile chips read it too).
    static func symbol(of title: String) -> String {
        guard let dollar = title.range(of: "$", options: .backwards) else { return title }
        return String(title[dollar.upperBound...])
    }

    /// The name half of the same format — everything before the " · $TICKER"
    /// tail; the whole title when the format doesn't match. Companion to
    /// `symbol(of:)` (2026-07-17, the fat feed row) so the separator lives in
    /// this file only, never re-split at a call site.
    static func name(of title: String) -> String {
        guard let sep = title.range(of: " · $", options: .backwards) else { return title }
        return String(title[..<sep.lowerBound])
    }
}
