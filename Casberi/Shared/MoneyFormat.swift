import Foundation

/// How this app writes a dollar figure short (moved to `Shared/` 2026-08-14).
///
/// It lived in `AgentPanel` and was fine there while one process drew money.
/// The wallet widget draws the same wallet in ANOTHER PROCESS, and a second
/// copy of these five thresholds is the drift this codebase keeps paying for in
/// other domains — "two copies of a retriever drift, and then the same question
/// answers differently depending on whether a key is configured". Here it would
/// be worse than a different answer: the tile and the balance card would print
/// two different figures for one wallet, on one screen, at the same moment, and
/// neither would look wrong on its own.
///
/// `AgentPanel.compactUSD` forwards here, so there is exactly one table.
/// Foundation-only, so every harness that compiles a caller can compile this.
enum MoneyFormat {
    /// `$12,480` → `$12K`, `$1,240,000` → `$1.2M`. Thresholds are the shipped
    /// ones, unchanged by the move.
    ///
    /// Note the deliberate asymmetry at the thousands rung: below $10K a figure
    /// keeps one decimal (`$1.2K`) and above it loses it (`$47K`). That is not
    /// an oversight — at four significant figures the decimal is noise, and at
    /// three it is the difference between $1,200 and $1,900.
    static func compactUSD(_ usd: Double) -> String {
        let v = abs(usd)
        if v >= 1_000_000_000 { return String(format: "$%.1fB", usd / 1_000_000_000) }
        if v >= 1_000_000     { return String(format: "$%.1fM", usd / 1_000_000) }
        if v >= 10_000        { return String(format: "$%.0fK", usd / 1_000) }
        if v >= 1_000         { return String(format: "$%.1fK", usd / 1_000) }
        return String(format: "$%.0f", usd)
    }

    /// Is a percent change too small to have a direction?
    ///
    /// Mirrors `TokenChartStyle.isFlat` — the §83 corollary that "a change that
    /// rounds to zero has no direction: no sign, no green/red". That one takes a
    /// FRACTION (`abs(c * 100) < 0.05`); this takes a percent, because that is
    /// what the widget payload carries, and converting at each of three call
    /// sites is how a rule gets applied to the wrong unit.
    static func isFlatPercent(_ pct: Double) -> Bool { abs(pct) < 0.05 }

    /// `+2.1%` / `−0.4%` / `0.0%` when flat. A flat change gets NO sign at all,
    /// which is the whole point of `isFlatPercent`.
    static func percentLabel(_ pct: Double) -> String {
        guard !isFlatPercent(pct) else { return "0.0%" }
        return String(format: "%@%.1f%%", pct > 0 ? "+" : "−", abs(pct))
    }
}
