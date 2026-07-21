import Foundation

/// Tap-learning decay for the composer's ask tiles (ruling 2026-07-16, prd
/// 95): a tile offered `neglectThreshold` opens without a tap steps behind
/// the next qualifier; a tap resets its counter. Deterministic and tiny —
/// per-ask counters in UserDefaults, no ratios, no ML.
///
/// Keys are the ask's MEMORY KEY: the stable kind ("week", "wallet"), or
/// kind:qualifier where one kind wears many faces ("showtag:recipes",
/// "context:Photos") — so neglect earned by one tag's tile never pre-demotes
/// a different tag's first offering. Never display strings — titles carry
/// live counts and would fragment the counters. The exemption lives HERE,
/// in one place: "away" is timely, not evergreen (it already gates on a
/// real gap), so it neither counts nor demotes.
@MainActor
enum AskMemory {
    static let neglectThreshold = 10
    private static let exempt: Set<String> = ["away"]
    private static let storeKey = "composer.askShownCounts"

    /// Times each ask has been offered since its last tap.
    private static var counts: [String: Int] {
        get { UserDefaults.standard.dictionary(forKey: storeKey) as? [String: Int] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: storeKey) }
    }

    static func neglected(_ key: String) -> Bool {
        !exempt.contains(key) && counts[key, default: 0] >= neglectThreshold
    }

    /// Called once per composer open with the asks actually offered — the
    /// caller skips opens that immediately fill the draft (a handed-off
    /// ask), where the tiles never had a chance to be tapped.
    static func shown(_ keys: [String]) {
        let counted = keys.filter { !exempt.contains($0) }
        guard !counted.isEmpty else { return }
        var c = counts
        for key in counted { c[key, default: 0] += 1 }
        counts = c
    }

    /// The tap is the rescue — the counter starts over.
    static func tapped(_ key: String) {
        var c = counts
        c[key] = 0
        counts = c
    }

    // MARK: - Asks made (proactive minting, docs/agent-brief.md 2026-07-20)

    /// The INVERSE counter: how many times each keepable ask has actually
    /// been ASKED (typed or tile-tapped), keyed by the same kind strings the
    /// kept-ask store uses ("wallet", "showtag:recipes", "search:design
    /// links"). Crossing `mintThreshold` upgrades the answer's quiet Keep
    /// pill to a prominent "You ask this a lot — keep it?" prompt. Keeping
    /// (or the ask being already kept) makes the counter moot — it's never
    /// read for a kept kind, so no reset is needed on keep.
    static let mintThreshold = 3
    private static let madeKey = "composer.asksMadeCounts"

    private static var madeCounts: [String: Int] {
        get { UserDefaults.standard.dictionary(forKey: madeKey) as? [String: Int] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: madeKey) }
    }

    /// Called once per settled, keepable ask (commit()'s settle step).
    static func asked(_ key: String) {
        var c = madeCounts
        c[key, default: 0] += 1
        madeCounts = c
    }

    static func askedOften(_ key: String) -> Bool {
        madeCounts[key, default: 0] >= mintThreshold
    }

    #if DEBUG
    /// `-askStats "<key>:<n>[,<key>:<n>…]"` or `-askStats clear` — seed the
    /// counters headlessly so the decay verifies without ten launches. Runs
    /// once per launch (a @State guard in the composer resets per sheet
    /// presentation and would re-clobber shown()'s bumps on every open).
    private static var seededThisLaunch = false
    static func seedFromLaunchArgs() {
        guard !seededThisLaunch else { return }
        seededThisLaunch = true
        guard let spec = UserDefaults.standard.string(forKey: "askStats"),
              !spec.isEmpty else { return }
        if spec == "clear" {
            counts = [:]
            return
        }
        var c = counts
        for pair in spec.split(separator: ",") {
            let parts = pair.split(separator: ":").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2, let n = Int(parts[1]) else { continue }
            c[parts[0]] = n
        }
        counts = c
    }

    /// `-asksMade "<key>:<n>[,…]"` or `-asksMade clear` — seed the minting
    /// counter headlessly so the "keep it?" upgrade verifies in one launch.
    /// Splits each pair on the LAST colon (a compound key like
    /// `search:design links` carries its own).
    private static var madeSeededThisLaunch = false
    static func seedMadeFromLaunchArgs() {
        guard !madeSeededThisLaunch else { return }
        madeSeededThisLaunch = true
        guard let spec = UserDefaults.standard.string(forKey: "asksMade"),
              !spec.isEmpty else { return }
        if spec == "clear" {
            madeCounts = [:]
            return
        }
        var c = madeCounts
        for pair in spec.split(separator: ",") {
            guard let colon = pair.range(of: ":", options: .backwards)?.lowerBound,
                  let n = Int(pair[pair.index(after: colon)...].trimmingCharacters(in: .whitespaces))
            else { continue }
            c[String(pair[pair.startIndex..<colon]).trimmingCharacters(in: .whitespaces)] = n
        }
        madeCounts = c
    }
    #endif
}
