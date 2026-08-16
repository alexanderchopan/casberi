import Foundation

/// A stock chart's time windows — the equity sibling of TokenRange. "5D" is
/// five TRADING days (Yahoo's own window), deliberately not rounded up to a
/// "7D" label: the chip says what the data is. Same for "1M" (a month of
/// daily candles, ~22 trading days).
enum StockRange: String, CaseIterable, PriceRange {
    case day = "1D", week = "5D", month = "1M"

    /// Yahoo v8 chart params: window + candle size.
    var yahoo: (range: String, interval: String) {
        switch self {
        case .day:   ("1d", "5m")
        case .week:  ("5d", "30m")
        case .month: ("1mo", "1d")
        }
    }

    /// Seconds per candle — the scrub's "9h ago" math.
    var step: TimeInterval {
        switch self {
        case .day:   300
        case .week:  1_800
        case .month: 86_400
        }
    }

    static var base: StockRange { .day }

    /// No scrub "when" label for stocks: candles exist only during trading
    /// hours, so index × step math would call a five-trading-day-old candle
    /// "~32h ago". The header still carries the scrubbed value.
    func agoLabel(indexFromEnd: Int) -> String? { nil }
}

/// A stock's recent price, drawn natively (2026-07-15) — the equity leg of
/// the price-chart family, behind the same TokenChartView anatomy a watched
/// token wears. The curve comes from Yahoo Finance's v8 chart endpoint:
/// unofficial but keyless — the same JSON finance.yahoo.com itself draws
/// from — and it can change without notice, so the honest-failure rule
/// applies in full: unreachable means the sheet falls back to the plain
/// Stocktwits link, never a broken or faked chart.
struct StockChart {

    /// Pulls the ticker out of a Stocktwits symbol link
    /// (`https://stocktwits.com/symbol/AAPL`) — the URL a watched stock's
    /// thing carries. Post links (`stocktwits.com/<user>/message/<id>`)
    /// deliberately don't match: only the watchlist row leads with a chart.
    static func route(from content: String) -> String? {
        guard let url = URL(string: content),
              url.host()?.contains("stocktwits.com") == true else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, parts[0] == "symbol", !parts[1].isEmpty else { return nil }
        return parts[1].uppercased()
    }

    /// Yahoo's WAF quirk (measured 2026-07-15): this bare, dated UA gets 200
    /// while realistic full UA strings — desktop Safari, desktop Chrome, and
    /// every iPhone-shaped one, including IngestSupport.safariUserAgent —
    /// get 429 on the same endpoint seconds apart. Don't "fix" this to a
    /// real browser string; verify with `-stockChartProbe` if touching it.
    private static let yahooUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"

    /// Fetches a ticker's price curve for the range, or nil when Yahoo is
    /// unreachable / rate-limiting / no longer serving the symbol.
    static func fetch(ticker: String, range: StockRange) async -> TokenChart? {
        // query1 and query2 serve identical data — try both before giving up
        // (they rate-limit independently).
        for host in ["query1", "query2"] {
            if let chart = await fetch(ticker: ticker, range: range, host: host) {
                return chart
            }
        }
        return nil
    }

    /// Stocktwits spelling → Yahoo spelling. Stocktwits marks crypto with a
    /// ".X" suffix (BTC.X) where Yahoo pairs against the dollar (BTC-USD),
    /// and writes share classes with a dot (BRK.B) where Yahoo uses a dash
    /// (BRK-B). A symbol this mapping still can't resolve just charts
    /// nothing — the honest link fallback.
    private static func yahooSymbol(_ ticker: String) -> String {
        if ticker.hasSuffix(".X") { return String(ticker.dropLast(2)) + "-USD" }
        return ticker.replacingOccurrences(of: ".", with: "-")
    }

    private static func fetch(ticker: String, range: StockRange,
                              host: String) async -> TokenChart? {
        guard let symbol = yahooSymbol(ticker).addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed) else { return nil }
        let (window, interval) = range.yahoo
        guard let root = await IngestSupport.getJSON(
            "https://\(host).finance.yahoo.com/v8/finance/chart/\(symbol)"
                + "?range=\(window)&interval=\(interval)",
            headers: ["User-Agent": yahooUA]) as? [String: Any],
              let result = ((root["chart"] as? [String: Any])?["result"]
                as? [[String: Any]])?.first,
              let quote = ((result["indicators"] as? [String: Any])?["quote"]
                as? [[String: Any]])?.first
        else { return nil }

        // Missing candles arrive as nulls (halts, thin pre-market) — they
        // drop out rather than plotting as zeros.
        let closes = ((quote["close"] as? [Any]) ?? []).compactMap { $0 as? Double }
        guard closes.count >= 2, let first = closes.first, let last = closes.last,
              first > 0 else { return nil }

        // The live tick — fresher than the last candle's close while the
        // market is open; the candle stands in when meta doesn't carry it.
        let meta = result["meta"] as? [String: Any]
        let price = (meta?["regularMarketPrice"] as? Double) ?? last
        // The delta is measured against the SAME number the figure shows
        // (2026-08-16). It used to be `(last - first) / first` — the last
        // CANDLE against the first — while `price` is the live tick, so while
        // the market is open the 40pt figure and the pill beneath it described
        // two different moves, and the pill still said "· 1D". Whichever number
        // leads is the one the percentage has to be about.
        return TokenChart(closes: closes, price: price,
                          change: (price - first) / first)
    }
}
