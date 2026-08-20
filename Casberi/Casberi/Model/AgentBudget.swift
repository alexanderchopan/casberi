import Foundation

/// A monthly ceiling on what the app may spend on its own schedule
/// (2026-08-20) — and the one provider that can honestly have one.
///
/// `AgentLibrarian` is the only path here that bills without a tap: it names
/// screenshots and reads imported chats on the foreground sweep's schedule, on
/// a device with no Apple Intelligence to do it free. Its three rules
/// (opt-in, device-wins, bounded-per-pass) bound each PASS and say nothing
/// about the month. Somebody who turns it on and then imports a fifteen-year X
/// archive has consented to a small recurring cost and bought a large one.
///
/// **This exists for OpenRouter and only OpenRouter, because a cap you cannot
/// measure is a promise you cannot keep.** `AgentSpend` records TOKENS and
/// refuses to price them — a per-model rate table renders perfectly whatever is
/// in it and goes stale the day a provider re-prices, and a wrong number on a
/// spending screen is believed. So a dollar cap is only sayable where the
/// provider itself states dollars, which is OpenRouter's free `/v1/auth/key`
/// read (`data.usage`) and nowhere else in the catalog. Every other provider
/// gets no cap and the screen says why, rather than offering a control that
/// silently governs nothing.
///
/// **Three rules, each the difference between a cap and a lie.**
///
/// 1. **The month's spend is a DELTA against a baseline we watched.**
///    `data.usage` is the key's lifetime total, so a key that has already spent
///    $40 elsewhere would read as instantly over any cap. The baseline is
///    re-taken at each month boundary; a month we never saw the start of
///    baselines at first sight and reports $0 spent, which understates rather
///    than inventing.
/// 2. **An unreadable figure NEVER pauses anything.** Not knowing and knowing
///    it's fine are different states, and pausing on the first is a control
///    that stops the app working whenever the network is bad. Only a real
///    reading at or above the cap pauses.
/// 3. **It governs the librarian, never an ask.** An ask is a tap: the person
///    is standing there, chose to spend, and being told "no" by a setting they
///    configured a month ago is the dead control the honesty rule bans. A
///    librarian sweep is the app deciding, which is exactly what a ceiling is
///    for.
enum AgentBudget {

    private static let capKey      = "agent.budget.monthlyUSD"
    private static let monthKeyKey = "agent.budget.monthKey"
    private static let baselineKey = "agent.budget.baselineUSD"

    /// The only provider that reports its own spend in dollars, so the only
    /// one a dollar cap can be enforced against. Spelled as a value rather
    /// than inlined at each test so the reason travels with it.
    static let measurableProvider: AgentProvider = .openrouter

    // MARK: - Pure month arithmetic

    /// "2026-08". The person's own calendar, because a billing month is a human
    /// unit and a UTC boundary would roll a day early or late depending on
    /// where they are. Injectable for the harness.
    static func monthKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    /// Where the month's counting starts from.
    struct Baseline: Equatable, Sendable {
        var month: String
        /// The provider's own lifetime total at the moment this month began
        /// being watched.
        var usd: Double
    }

    /// What the baseline should become, given the reading that just arrived.
    /// Pure — `observe` below is the same function with UserDefaults on both
    /// ends, so the arithmetic can be proved without a key or a network.
    ///
    /// Re-baselines in three cases and they are not the same case: a first
    /// sight, a new month, and a reading BELOW the stored baseline. The third
    /// means the lifetime total went backwards, which a lifetime total cannot
    /// do — so the key was replaced, or the provider reset it, and continuing
    /// to subtract the old baseline would report a negative spend forever.
    static func rebased(_ current: Baseline?, reported: Double, month: String) -> Baseline {
        guard let current, current.month == month, current.usd <= reported else {
            return Baseline(month: month, usd: reported)
        }
        return current
    }

    /// This month's spend, or nil when it isn't knowable. Never negative:
    /// `rebased` has already handled the backwards case, and a clamp here means
    /// a caller that skipped it still cannot render "-$3.10 used".
    static func spent(_ baseline: Baseline?, reported: Double?, month: String) -> Double? {
        guard let reported, let baseline, baseline.month == month else { return nil }
        return max(0, reported - baseline.usd)
    }

    /// Whether a cap has been reached. `cap` nil means no ceiling was set;
    /// `spent` nil means we could not read one — and both answer false, because
    /// rule 2 says not knowing is not a reason to stop.
    static func exhausted(spent: Double?, cap: Double?) -> Bool {
        guard let cap, cap > 0, let spent else { return false }
        return spent >= cap
    }

    // MARK: - Stored state

    /// nil means no ceiling. Setting one re-baselines to the CURRENT reading,
    /// so a cap set today counts from today rather than retroactively spending
    /// a month that already happened.
    static var monthlyCap: Double? {
        get {
            let value = UserDefaults.standard.double(forKey: capKey)
            return value > 0 ? value : nil
        }
        set {
            let d = UserDefaults.standard
            guard let newValue, newValue > 0 else {
                d.removeObject(forKey: capKey)
                return
            }
            d.set(newValue, forKey: capKey)
            if let reported = AgentSpend.shared.entry(for: measurableProvider)?.reportedUSD {
                let month = monthKey(.now)
                d.set(month, forKey: monthKeyKey)
                d.set(reported, forKey: baselineKey)
            }
        }
    }

    static var baseline: Baseline? {
        guard let month = UserDefaults.standard.string(forKey: monthKeyKey),
              let usd = UserDefaults.standard.object(forKey: baselineKey) as? Double
        else { return nil }
        return Baseline(month: month, usd: usd)
    }

    /// Folds a fresh lifetime reading in. Called from `OpenRouterCredits.record`
    /// — the same free `/v1/auth/key` read that already runs at connect time
    /// and behind the foreground sweep's ~10-minute heal window, so this costs
    /// no request of its own.
    static func observe(reportedUSD: Double, now: Date = .now) {
        let month = monthKey(now)
        let next = rebased(baseline, reported: reportedUSD, month: month)
        UserDefaults.standard.set(next.month, forKey: monthKeyKey)
        UserDefaults.standard.set(next.usd, forKey: baselineKey)
    }

    /// This month's spend on the measurable provider, or nil when unknown.
    static var spentThisMonth: Double? {
        spent(baseline,
              reported: AgentSpend.shared.entry(for: measurableProvider)?.reportedUSD,
              month: monthKey(.now))
    }

    /// Whether the librarian must stand down. False for every provider but the
    /// measurable one — not because the others are cheap, but because claiming
    /// to cap a spend we cannot read would be the fake status this app's
    /// honesty rule exists to forbid.
    static func pausesLibrarian(_ provider: AgentProvider) -> Bool {
        guard provider == measurableProvider else { return false }
        return exhausted(spent: spentThisMonth, cap: monthlyCap)
    }

    /// One plain sentence for the settings row, or nil when there is nothing
    /// true to say (no cap, or no reading to say it against).
    static func line(for provider: AgentProvider) -> String? {
        guard provider == measurableProvider, let cap = monthlyCap else { return nil }
        guard let spent = spentThisMonth else {
            return String(localized: "Capped at \(usd(cap)) a month. Nothing read from \(provider.company) yet this month.")
        }
        if exhausted(spent: spent, cap: cap) {
            return String(localized: "\(usd(spent)) of \(usd(cap)) used — organizing is paused until next month. Asking still works.")
        }
        return String(localized: "\(usd(spent)) of \(usd(cap)) used this month.")
    }

    static func usd(_ value: Double) -> String { String(format: "$%.2f", value) }

    static func clear() {
        let d = UserDefaults.standard
        d.removeObject(forKey: capKey)
        d.removeObject(forKey: monthKeyKey)
        d.removeObject(forKey: baselineKey)
    }
}
