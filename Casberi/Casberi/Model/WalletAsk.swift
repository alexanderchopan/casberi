import Foundation
import SwiftData

/// Wallet asks (2026-07-15) — "how's my wallet", "what are my wallets worth".
/// Like the watchlist ask, the words name no corpus content to score, so
/// retrieval has nothing to ground on; the answer is the live holdings total
/// plus the forward-only value line's own move — computed, current, no model.
/// Also home of the away recap's wallet line: the value's change over the frozen
/// away window, from the samples that bracket it.
///
/// Stays inside §71/§77's frame — the number is these watched wallets' onchain
/// value read on this iPhone, never a claim about the person's whole net worth,
/// so the copy says "in your wallet" / "across your wallets", never "portfolio"
/// or "net worth".
enum WalletAsk {

    /// True when the WHOLE ask is about the wallet — the residual discipline
    /// TokensAsk/StatusAsk use: after the cue and filler, anything left is
    /// CONTENT and belongs to the scored retriever ("what did sam send my
    /// wallet" is a search, not a value readout).
    static func matches(_ raw: String) -> Bool {
        let q = raw.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: CharacterSet(charactersIn: "?!. "))
        guard q.contains("wallet") || q.contains("my holdings") || q.contains("my portfolio")
        else { return false }
        var words = q.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let filler: Set<String> = [
            "how", "hows", "s", "is", "are", "was", "were", "my", "the", "a",
            "doing", "going", "performing", "looking", "what", "whats", "about",
            "on", "with", "wallet", "wallets", "holdings", "portfolio", "worth",
            "value", "net", "today", "now", "right", "up", "down", "tell", "me",
            "check", "hold", "holding", "much",
        ]
        words.removeAll { filler.contains($0) }
        return words.isEmpty
    }

    /// The computed answer — live holdings total, plus the value line's move
    /// since it began. nil ONLY when no wallet is watched (so the router can
    /// point at Apps → Wallet); an unreachable read still answers honestly from
    /// the last sample, or says it couldn't read.
    @MainActor
    static func answer() async -> String? {
        let store = WalletStore.shared
        guard !store.addresses.isEmpty else { return nil }
        let multi = store.addresses.count > 1
        let noun = multi ? String(localized: "your wallets") : String(localized: "your wallet")

        // Live first (records a fresh sample as a side effect), so read the
        // samples AFTER, catching that new point.
        let groups = await WalletIngest.topHoldingsByWallet()
        let liveTotal = groups.isEmpty ? nil : groups.reduce(0.0) { $0 + $1.totalUSD }
        let samples = multi
            ? store.combinedValueSamples()
            : store.valueSamples(forAddress: store.addresses[0].address)

        guard let total = liveTotal ?? samples.last?.usd else {
            return String(localized: "Couldn't read \(noun) right now — check your connection.")
        }
        let head = multi
            ? String(localized: "\(TokenStats.compact(total)) across your wallets")
            : String(localized: "\(TokenStats.compact(total)) in your wallet")
        if samples.count >= 2, let first = samples.first, first.usd > 0, let last = samples.last {
            let change = (last.usd - first.usd) / first.usd
            let since = first.at.formatted(.dateTime.month(.abbreviated).day())
            return "\(head), \(TokenChartStyle.changeText(change)) since \(since)."
        }
        return "\(head)."
    }

    /// The wallet's line for the away recap — the value's move over the away
    /// window, from the samples bracketing it (the last point at/before the
    /// window's start vs the latest). Synchronous: it reads the local value
    /// samples, no network. nil when nothing spans the window (no samples, one
    /// point, or a flat/zero start) — the line never claims a move it can't show.
    @MainActor
    static func awayLine(window: Range<Date>) -> String? {
        let store = WalletStore.shared
        guard !store.addresses.isEmpty else { return nil }
        let multi = store.addresses.count > 1
        let samples = multi
            ? store.combinedValueSamples()
            : store.valueSamples(forAddress: store.addresses[0].address)
        guard samples.count >= 2,
              let start = samples.last(where: { $0.at <= window.lowerBound }) ?? samples.first,
              let last = samples.last, last.at > start.at, start.usd > 0
        else { return nil }
        let change = (last.usd - start.usd) / start.usd
        let noun = multi ? String(localized: "Your wallets") : String(localized: "Your wallet")
        return String(localized: "\(noun) \(TokenChartStyle.changeText(change)) while you were away.")
    }
}
