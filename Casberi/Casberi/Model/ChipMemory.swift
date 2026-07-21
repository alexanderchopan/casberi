import Foundation

/// Tap-learned ordering for the source strip (amends §131's chip order,
/// 2026-07-21): pure most-recent-first meant a chip you use constantly still
/// drifted back the moment something else landed anywhere in the corpus.
/// Each chip switch bumps a per-source counter; `MainSurface.chipLabels`
/// sorts by this weight first, falling back to the existing recency order
/// for ties (Swift's `sorted` is stable) — so a source you actually visit
/// anchors near the front, and everything you've never tapped still sorts
/// by "who I just heard from," exactly as before. Deterministic counters in
/// UserDefaults, no ratios, no ML, no edit surface — same shape as
/// `AskMemory`.
@MainActor
enum ChipMemory {
    private static let countsKey = "chips.visitCounts"
    private static let lastVisitKey = "chips.lastVisit"

    private static var counts: [String: Int] {
        get { UserDefaults.standard.dictionary(forKey: countsKey) as? [String: Int] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: countsKey) }
    }

    private static var lastVisit: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: lastVisitKey) as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: lastVisitKey) }
    }

    /// A chip switch landing on `source` — "All" is excluded, since it's the
    /// baseline every session starts from, not a source competing for a
    /// front slot.
    static func visited(_ source: String) {
        guard source != "All" else { return }
        var c = counts
        c[source, default: 0] += 1
        counts = c
        var v = lastVisit
        v[source] = Date.now.timeIntervalSinceReferenceDate
        lastVisit = v
    }

    /// The sort weight — halves for every `staleWindow` stretch since the
    /// last visit, so a source nobody's tapped in a week drifts back toward
    /// the recency-only tail on its own, no cap and nothing to manage.
    private static let staleWindow: Double = 7 * 86400
    static func weight(for source: String) -> Int {
        weight(for: source, counts: counts, lastVisit: lastVisit)
    }

    /// Both backing dictionaries, read once — for a caller (a sort
    /// comparator) that would otherwise call `weight(for:)` once per
    /// comparison, each re-deserializing both UserDefaults dictionaries from
    /// scratch (2026-07-21 audit: an O(n log n) comparator over the chip
    /// list did exactly that).
    static func snapshot() -> (counts: [String: Int], lastVisit: [String: Double]) {
        (counts, lastVisit)
    }

    /// Same weight, computed against an already-read snapshot.
    static func weight(for source: String, counts: [String: Int], lastVisit: [String: Double]) -> Int {
        guard let raw = counts[source], let last = lastVisit[source] else { return 0 }
        let elapsed = Date.now.timeIntervalSinceReferenceDate - last
        guard elapsed > 0 else { return raw }
        let halvings = Int(elapsed / staleWindow)
        guard halvings > 0 else { return raw }
        return raw >> min(halvings, 30)
    }

    #if DEBUG
    private static var seededThisLaunch = false
    /// `-chipStats "Wallet:9,Photos:2"` (or `clear`) seeds visit counts
    /// headlessly — each seeded source's last-visit stamps to now, so it
    /// reads at full weight without waiting on the decay window. Runs once
    /// per launch.
    static func seedFromLaunchArgs() {
        guard !seededThisLaunch else { return }
        seededThisLaunch = true
        guard let spec = UserDefaults.standard.string(forKey: "chipStats"),
              !spec.isEmpty else { return }
        if spec == "clear" {
            counts = [:]
            lastVisit = [:]
            return
        }
        var c = counts
        var v = lastVisit
        let now = Date.now.timeIntervalSinceReferenceDate
        for pair in spec.split(separator: ",") {
            let parts = pair.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let n = Int(parts[1]) else { continue }
            c[parts[0]] = n
            v[parts[0]] = now
        }
        counts = c
        lastVisit = v
    }
    #endif
}
