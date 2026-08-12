import Foundation

/// The two prediction rooms' browse book, for the demo (2026-08-12).
///
/// **These rooms were the demo's one hole in "THE DEMO REACHES NOTHING."**
/// `DemoMode` gates `BridgeRefresh.refreshAllConnected` and
/// `Notifications.submit`, but `PredictionBrowseSection.loadIfNeeded` is a
/// per-view `.task(id:)` fetch, not part of the foreground sweep — so opening
/// Kalshi or Polymarket in the demo went straight out to the exchanges. The
/// same shape `DemoSeedAll` already refuses for `TokenChart.route` (its own
/// "no dexscreener content URL" note), arriving by the one door that note
/// couldn't see.
///
/// Three things were wrong with reaching, and only the first is obvious:
/// the demo made real requests under someone who has not decided to keep the
/// app; the room's whole content depended on the network, so offline it drew
/// "couldn't reach the order book" as a first impression; and what came back
/// was whatever the exchange happened to be running, which is how a demo
/// ends up showing markets that CLOSED THREE MONTHS AGO in warning orange.
///
/// So the book is seeded instead. Close times are computed from `.now` at
/// call time rather than stored, which means they can never go stale the way
/// a fixed date does — `DemoMode.restampIfStale` exists precisely because
/// stored demo dates rot, and this side-steps needing it at all.
///
/// Probabilities are chosen to exercise the room's own branches rather than
/// to look plausible in isolation: a near-certain market, a long shot, a
/// genuine coin-flip, and a pair that Kalshi and Polymarket price DIFFERENTLY
/// so `PredictionDisagreement` has a real cross-venue twin to draw — the one
/// reading an aggregate produces that neither venue can produce alone, and
/// the thing most worth showing a first-time opener.
enum PredictionDemoBook {

    /// Minutes/hours/days out, never a stored date. `closeTime` in the past
    /// renders as orange "Closes N ago", which is what the live book was
    /// doing to the demo.
    private static func out(days: Double) -> Date {
        Date().addingTimeInterval(days * 86_400)
    }

    // MARK: - Kalshi

    /// Kalshi's side of the book. `previousProbability` is the previous
    /// CLOSE (its real read), so the deltas here are captioned "vs
    /// yesterday" by the card — see `KalshiWatch.Resolved`'s own note on why
    /// the two venues are never captioned alike.
    static func kalshi(query: String, category: String?) -> [KalshiWatch.Resolved] {
        let all: [KalshiWatch.Resolved] = [
            .init(ticker: "FED-26DEC-CUT", eventTicker: "FED-26DEC",
                  seriesTicker: "FED", title: "Will the Fed cut rates in December?",
                  subtitle: "Cut", probability: 0.72, previousProbability: 0.66,
                  volume: 184_000, category: "Economics", closeTime: out(days: 34)),
            .init(ticker: "CPI-26AUG-3", eventTicker: "CPI-26AUG",
                  seriesTicker: "CPI", title: "Will CPI come in under 3% this month?",
                  subtitle: "Under 3%", probability: 0.41, previousProbability: 0.47,
                  volume: 96_400, category: "Economics", closeTime: out(days: 9)),
            .init(ticker: "LIS-HIGH-26", eventTicker: "LIS-HIGH",
                  seriesTicker: "WEATHER", title: "Highest temperature in Lisbon this week?",
                  subtitle: "Above 32°C", probability: 0.58, previousProbability: 0.55,
                  volume: 12_800, category: "Climate", closeTime: out(days: 4)),
            .init(ticker: "SPX-26-5000", eventTicker: "SPX-26",
                  seriesTicker: "SPX", title: "Will the S&P close above 5,000 this year?",
                  subtitle: "Above 5,000", probability: 0.88, previousProbability: 0.87,
                  volume: 421_000, category: "Financials", closeTime: out(days: 121)),
            // The twin — Polymarket prices the same question 9 points lower,
            // so `PredictionDisagreement` has something real to compare.
            .init(ticker: "STARSHIP-26-Q4", eventTicker: "STARSHIP-26",
                  seriesTicker: "SPACE", title: "Will SpaceX launch Starship again in 2026?",
                  subtitle: "Yes", probability: 0.79, previousProbability: 0.74,
                  volume: 233_000, category: "Science", closeTime: out(days: 76)),
            .init(ticker: "WC-26-WINNER", eventTicker: "WC-26",
                  seriesTicker: "SOCCER", title: "Who wins the Champions League?",
                  subtitle: "Real Madrid", probability: 0.24, previousProbability: 0.21,
                  volume: 67_200, category: "Sports", closeTime: out(days: 58)),
        ]
        return narrow(all, query: query, category: category,
                      text: { [$0.title, $0.subtitle, $0.category] },
                      tags: { [$0.category.lowercased()] })
    }

    static func kalshiCategories() -> [String] {
        ordered(kalshi(query: "", category: nil).map(\.category))
    }

    // MARK: - Polymarket

    /// Polymarket's side. `previousProbability` is a WEEK ago here — Gamma
    /// serves no 1-day figure (`PolymarketBridge.Resolved`'s own note), and
    /// the demo keeps that difference rather than flattening it, because the
    /// card's caption reads "vs last week" off exactly this.
    static func polymarket(query: String, category: String?) -> [PolymarketBridge.Resolved] {
        let all: [PolymarketBridge.Resolved] = [
            .init(conditionId: "0xdemo01", slug: "starship-2026",
                  eventTitle: "Will SpaceX launch Starship again in 2026?",
                  title: "Will SpaceX launch Starship again in 2026?", subtitle: "Yes",
                  probability: 0.70, previousProbability: 0.61, volume: 1_240_000,
                  closed: false, yesWon: nil, closeTime: out(days: 76),
                  tags: ["science", "tech"], yesTokenId: nil),
            .init(conditionId: "0xdemo02", slug: "champions-league-winner",
                  eventTitle: "Champions League winner",
                  title: "Will Real Madrid win the Champions League?", subtitle: "Real Madrid",
                  probability: 0.27, previousProbability: 0.19, volume: 3_100_000,
                  closed: false, yesWon: nil, closeTime: out(days: 58),
                  tags: ["sports"], yesTokenId: nil),
            .init(conditionId: "0xdemo03", slug: "fed-december",
                  eventTitle: "Fed decision in December",
                  title: "Will the Fed cut rates in December?", subtitle: "Cut",
                  probability: 0.68, previousProbability: 0.70, volume: 880_000,
                  closed: false, yesWon: nil, closeTime: out(days: 34),
                  tags: ["economics", "politics"], yesTokenId: nil),
            .init(conditionId: "0xdemo04", slug: "gpt-5-by-year-end",
                  eventTitle: "Frontier model released by year end?",
                  title: "Will a new frontier model ship before year end?", subtitle: "Yes",
                  probability: 0.93, previousProbability: 0.90, volume: 512_000,
                  closed: false, yesWon: nil, closeTime: out(days: 121),
                  tags: ["tech"], yesTokenId: nil),
            .init(conditionId: "0xdemo05", slug: "eth-4000-2026",
                  eventTitle: "ETH above $4,000 in 2026?",
                  title: "Will ETH trade above $4,000 this year?", subtitle: "Yes",
                  probability: 0.36, previousProbability: 0.44, volume: 2_050_000,
                  closed: false, yesWon: nil, closeTime: out(days: 121),
                  tags: ["crypto"], yesTokenId: nil),
        ]
        return narrow(all, query: query, category: category,
                      text: { [$0.eventTitle, $0.title, $0.subtitle] },
                      tags: { $0.tags })
    }

    static func polymarketCategories() -> [String] {
        ordered(polymarket(query: "", category: nil).flatMap(\.tags).map(\.capitalized))
    }

    // MARK: - Shared narrowing

    /// Mirrors what both live books do to a query and a category: a
    /// case-insensitive substring over the row's own words, and an exact
    /// category/tag match. Kept deliberately simple — this is a demo book,
    /// not a search engine, and a seeded row that fails to match its own
    /// category chip reads as a broken room.
    private static func narrow<T>(_ rows: [T], query: String, category: String?,
                                  text: (T) -> [String], tags: (T) -> [String]) -> [T] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cat = category?.lowercased()
        return rows.filter { row in
            if let cat, !tags(row).contains(where: { $0.lowercased() == cat }) { return false }
            guard !q.isEmpty else { return true }
            return text(row).contains { $0.lowercased().contains(q) }
        }
    }

    /// Deduped, in first-appearance order — the browse strip's chips must not
    /// reshuffle between opens (the `MarketsRoom` switcher ruling).
    private static func ordered(_ values: [String]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for v in values where !seen.contains(v) { seen.insert(v); out.append(v) }
        return out
    }
}
