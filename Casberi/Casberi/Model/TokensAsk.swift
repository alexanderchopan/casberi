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
            $0.source == "Markets"
        })
        // Tokens only: Markets also holds watched stocks (prd §1000), which
        // carry no pulse, so counting them here made a stocks-only watchlist
        // answer "couldn't read your prices" every time.
        return ((try? context.fetch(descriptor)) ?? []).filter(TokenWatch.isWatchedToken)
    }

    struct Move {
        let thing: Thing
        let symbol: String
        let price: Double
        let change: Double   // fraction over 24h
    }

    /// Every watched token's 24h move, biggest swing first — read through
    /// TokenPulse's cache (refreshed if stale), so this answer and the feed
    /// rows can never disagree about the same token. A row wanting the same
    /// closes for a sparkline (the brief's `moversTile`, 2026-07-23) reads
    /// `TokenPulse.shared.pulse(for:)` itself rather than `Move` carrying a
    /// second copy — the cache is already warm from this very refresh.
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
    ///
    /// Both seams: titles have been written `"Name — $SYM"` since §915, and a
    /// row landed before it still reads `"Name · $SYM"`. Splitting on the old
    /// one alone drew every watched row's whole title as its name.
    static func name(of title: String) -> String {
        guard let sep = title.range(of: " — $", options: .backwards)
                ?? title.range(of: " · $", options: .backwards) else { return title }
        return String(title[..<sep.lowerBound])
    }
}
