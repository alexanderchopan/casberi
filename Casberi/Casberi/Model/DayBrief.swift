import Foundation

/// The day's shared reading (prd §165, extended §166) — the window the day's
/// news is measured from, the one nameable thing that leads it, and the
/// wallet's day move. Read by BOTH the whisper capsule's headline
/// (`RootShell.refreshWhisper`) and the Today brief's modules
/// (`TodayBrief`), so the line the capsule teases and the screen it opens can
/// never disagree about what today was.
///
/// Deterministic by construction (docs/agent-brief.md ruling 1's spine
/// guarantee — no model anywhere near the launch path): every fragment is a
/// fact the app already holds, joined in a fixed order, and a day with
/// nothing to say composes nil — the whisper simply doesn't show (honesty
/// law: no fake status, no manufactured news).
///
/// **Counts are not the fact** (user ruling, 2026-07-22): people receive
/// dozens of things a day and care WHAT landed, not how many. So the lead
/// names a thing — who mentioned you, what shipped, what settled — and falls
/// back to a bare count only when nothing nameable landed at all.
@MainActor
enum DayBrief {
    /// The boundary today's news is measured from: the frozen away window
    /// when one exists (overnight, typically, for a first open of the day),
    /// else midnight — the process died and relaunched across the day
    /// boundary, so no window froze.
    static func windowStart(now: Date = .now) -> Date {
        AppVisit.away?.lowerBound ?? Calendar.current.startOfDay(for: now)
    }

    /// Everything that landed since the boundary, preserving the caller's
    /// order (every caller fetches newest-first).
    static func landed(_ things: [Thing], now: Date = .now) -> [Thing] {
        let start = windowStart(now: now)
        return things.filter { $0.capturedAt > start }
    }

    /// What the whisper capsule says: the brief NAMED, and the day's facts
    /// under it.
    ///
    /// Two parts, not one line, by user ruling (2026-07-22): *"user won't know
    /// that is a daily synthesis, they will think it is just a single
    /// notification for a transaction."* A dot beside one sentence is
    /// notification grammar — it reads as an event, not a digest. Naming the
    /// artifact on its own line is what makes it a brief.
    struct Whisper {
        /// "Your Wednesday brief" — names what this IS.
        let title: String
        /// "1 transaction" — the day's subject, already budgeted to fit.
        let lead: String
        /// The wallet's day move as a percentage, kept SEPARATE from the lead
        /// (2026-07-22) so the capsule can paint it in its own direction's
        /// accent. A single pre-joined string couldn't: the view had no way to
        /// find the figure inside it, so a gain and a loss read identically.
        /// nil when the wallet can't speak at day scale — and a flat move is
        /// nil too, so the color never claims a direction that isn't there.
        let walletPct: Double?

        /// The two facts as one line — what the kept `today` pill shows as its
        /// digest, where there's no room for a second ink color.
        var detail: String {
            guard let walletPct else { return lead }
            return lead + String(format: ", wallet %+.1f%%", walletPct)
        }
    }

    static func whisper(things: [Thing], now: Date = .now) -> Whisper? {
        let move = walletMove(now: now)
        let wallet = move.map { String(format: "wallet %+.1f%%", $0.pct) }
        guard let subject = lead(landed(things, now: now)) ?? wallet.map({ Lead(full: $0, short: $0) })
        else { return nil }
        // The wallet fragment leads on its own only when nothing landed —
        // otherwise it's the tail, and must not be printed twice.
        let walletIsLead = subject.full == wallet
        var lead = subject.full
        // The line never wraps and never scrolls, so it's budgeted rather
        // than left to truncate: the wallet fragment is short and fixed, so
        // the lead yields to it instead of the tail being cut off mid-word
        // ("…, walle…", caught on-device 2026-07-22). Shortening a name is
        // honest; losing a whole fact to an ellipsis isn't.
        let tailCount = walletIsLead ? 0 : (wallet.map { $0.count + 2 } ?? 0)
        let room = lineBudget - tailCount
        if lead.count > room {
            // Prefer the lead's own SHORT form over a truncated long one —
            // "1 transaction" says more than "Swapped 0.5…". Only if that
            // still doesn't fit does anything get cut.
            lead = subject.short
            if lead.count > room, room > 8 { lead = clamp(lead, max: room) }
        }
        return Whisper(title: title(now: now), lead: lead,
                       walletPct: walletIsLead ? nil : move?.pct)
    }

    static func title(now: Date = .now) -> String {
        String(localized: "Your \(now.formatted(.dateTime.weekday(.wide))) brief")
    }

    /// The day's facts as one line — the kept `today` pill's digest. ONE
    /// implementation with the capsule's own text (it reads the same
    /// `Whisper`), so the pill's trailing signal and the capsule can't drift.
    static func detail(things: [Thing], now: Date = .now) -> String? {
        whisper(things: things, now: now)?.detail
    }

    /// The whole line, for logs and probes — the two parts as one string.
    static func headline(things: [Thing], now: Date = .now) -> String? {
        detail(things: things, now: now).map { "\(title(now: now)) · \($0)" }
    }

    /// Roughly what fits the capsule's detail line at `subhead13` on the
    /// narrowest phone — a character budget, not a measurement, which is why
    /// the clamp leaves margin rather than filling to the pixel. Bigger than
    /// the one-line version's was: naming the brief moved the weekday out of
    /// this line, giving the facts the whole width.
    private static let lineBudget = 40

    /// The day's subject in two lengths — the name, and something true that
    /// still fits when the name doesn't.
    struct Lead {
        let full: String
        let short: String
    }

    /// The one nameable thing that leads the day. Ranked by claim on the
    /// person, not by recency: someone addressing you outranks a release,
    /// which outranks money moving, which outranks whatever landed newest.
    /// Every branch names a subject; only the last resort counts.
    static func lead(_ landed: [Thing]) -> Lead? {
        guard !landed.isEmpty else { return nil }
        // Someone addressed you by name.
        if let mention = landed.first(where: { $0.socialContext == "mention" }) {
            if let who = mention.authorHandle, !who.isEmpty {
                return Lead(full: String(localized: "\(who) mentioned you"),
                            short: String(localized: "\(who) mentioned you"))
            }
            return Lead(full: String(localized: "you were mentioned"),
                        short: String(localized: "you were mentioned"))
        }
        // A repo you star shipped a major version.
        if let release = landed.first(where: {
            $0.source == "GitHub" && $0.tags.contains(GitHubFeedFetch.majorReleaseTag)
        }) {
            return Lead(full: clamp(release.title),
                        short: String(localized: "a major release"))
        }
        // Money actually moved (a settled fill, a transfer). This is the ONE
        // place a count is the fact rather than a tally, which is exactly why
        // it's the short form: "1 transaction" beats a half-truncated title.
        let money = landed.filter { $0.kind == .transaction || $0.source == "Peer" }
        if let first = money.first {
            let count = money.count == 1
                ? String(localized: "1 transaction")
                : String(localized: "\(money.count) transactions")
            return Lead(full: money.count == 1 ? clamp(first.title) : count, short: count)
        }
        // Nothing claimed you — name the newest thing instead of counting,
        // unless the day is genuinely a pile, where the pile IS the fact.
        guard let newest = landed.first else { return nil }
        if landed.count >= 8 {
            let pile = String(localized: "\(landed.count) new")
            return Lead(full: pile, short: pile)
        }
        return Lead(full: clamp(newest.title), short: String(localized: "\(landed.count) new"))
    }

    /// "wallet +1.5%" off the CACHED combined value line (`WalletStore`'s
    /// samples — synchronous, already on disk; the launch path never pays a
    /// network read for a whisper). Skips honestly when it can't speak at
    /// day scale: no watched wallets, a history younger than ~a day (a
    /// minutes-old delta wearing a daily headline would lie), or a move
    /// that rounds to flat — §83: a change that rounds to zero has no
    /// direction, so it gets no sign and no mention.
    static func walletFragment(now: Date = .now) -> String? {
        guard let move = walletMove(now: now) else { return nil }
        return String(format: "wallet %+.1f%%", move.pct)
    }

    /// The wallet's day move and the sample it's measured FROM — the anchor
    /// `TodayBrief` re-uses so its attribution ("ETH did the lifting") spans
    /// exactly the window the percentage claims.
    struct WalletMove {
        let pct: Double
        let usd: Double
        let since: Date
        /// The anchor sample's own value (2026-07-22) — the hero's total
        /// ROLLS from this to `usd` on mount, so the number tells the day's
        /// story before the delta pill summarizes it. Additive: every
        /// existing reader of `WalletMove` ignores a field it doesn't ask for.
        let anchorUSD: Double
    }

    static func walletMove(now: Date = .now) -> WalletMove? {
        let samples = WalletStore.shared.combinedValueSamples()
        guard let latest = samples.last, latest.usd > 0,
              let base = samples.last(where: {
                  $0.at <= now.addingTimeInterval(-dayScale)
              }),
              base.usd > 0
        else { return nil }
        let pct = (latest.usd - base.usd) / base.usd * 100
        guard abs(pct) >= 0.05 else { return nil }
        return WalletMove(pct: pct, usd: latest.usd, since: base.at, anchorUSD: base.usd)
    }

    /// How old a sample must be before a delta measured against it may wear
    /// the word "today". Deliberately under 24h (samples land at most every
    /// 4h, so a strict 24h anchor would often find nothing) but far enough
    /// back that the move is a day's, not an hour's.
    private static let dayScale: TimeInterval = 20 * 3600

    /// A title short enough to ride a one-line capsule, cut at a word.
    private static func clamp(_ s: String, max: Int = 42) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > max else { return t }
        let cut = t.prefix(max)
        if let space = cut.lastIndex(of: " ") {
            return String(cut[cut.startIndex..<space]) + "…"
        }
        return String(cut) + "…"
    }
}
