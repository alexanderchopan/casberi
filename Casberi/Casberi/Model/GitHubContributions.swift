import Foundation
import Observation

/// A year of GitHub contributions — the green-squares calendar, fetched from
/// GitHub's GraphQL v4 (`contributionsCollection.contributionCalendar`, the
/// only place the daily counts live — the REST events feed can't build it).
/// Real data, drawn on device; nothing about it is invented.
struct ContributionDay {
    /// Contributions that day.
    let count: Int
    /// GitHub's own quartile bucket, 0 (none) … 4 (most) — the intensity ramp.
    let level: Int
}

struct ContributionWeek {
    /// Sunday…Saturday; a partial leading/trailing week may hold fewer than 7.
    let days: [ContributionDay]
}

struct ContributionYear {
    let total: Int
    let weeks: [ContributionWeek]

    /// GitHub's contributionLevel enum → the 0…4 intensity the grid draws.
    static func level(_ raw: String?) -> Int {
        switch raw {
        case "FIRST_QUARTILE":  return 1
        case "SECOND_QUARTILE": return 2
        case "THIRD_QUARTILE":  return 3
        case "FOURTH_QUARTILE": return 4
        default:                return 0
        }
    }

    /// The whole calendar in one GraphQL call, with the connected token.
    static func fetch(token: String) async -> ContributionYear? {
        let query = """
        query { viewer { contributionsCollection { contributionCalendar { \
        totalContributions weeks { contributionDays { contributionCount contributionLevel } } } } } }
        """
        guard let root = await IngestSupport.postJSON(
            "https://api.github.com/graphql", auth: "Bearer \(token)",
            body: ["query": query]) as? [String: Any],
              let data = root["data"] as? [String: Any],
              let viewer = data["viewer"] as? [String: Any],
              let cc = viewer["contributionsCollection"] as? [String: Any],
              let cal = cc["contributionCalendar"] as? [String: Any],
              let weeksRaw = cal["weeks"] as? [[String: Any]] else { return nil }
        let weeks = weeksRaw.map { w -> ContributionWeek in
            let days = ((w["contributionDays"] as? [[String: Any]]) ?? []).map { d in
                ContributionDay(count: d["contributionCount"] as? Int ?? 0,
                                level: level(d["contributionLevel"] as? String))
            }
            return ContributionWeek(days: days)
        }
        return ContributionYear(total: cal["totalContributions"] as? Int ?? 0, weeks: weeks)
    }

    #if DEBUG
    /// A deterministic synthetic year — screenshot/verification only, so the
    /// Home tile can be seen rendering without a real account's data.
    static func demo() -> ContributionYear {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) & 0xFF)
        }
        var weeks: [ContributionWeek] = []
        var total = 0
        for _ in 0..<53 {
            var days: [ContributionDay] = []
            for _ in 0..<7 {
                let r = next()
                let level = r < 96 ? 0 : r < 156 ? 1 : r < 206 ? 2 : r < 238 ? 3 : 4
                let count = level == 0 ? 0 : level * 3 + (r % 5)
                total += count
                days.append(ContributionDay(count: count, level: level))
            }
            weeks.append(ContributionWeek(days: days))
        }
        return ContributionYear(total: total, weeks: weeks)
    }
    #endif
}

/// The in-memory cache for the contribution calendar — one fetch per few hours,
/// shared by the Home tile (the TokenPulse pattern: ephemeral, never
/// persisted). The tile reads `year` and calls `refreshIfStale` on appear.
@MainActor
@Observable
final class GitHubGraphStore {
    static let shared = GitHubGraphStore()
    private(set) var year: ContributionYear?
    private var fetchedAt: Date?
    private var fetching = false

    func refreshIfStale() async {
        #if DEBUG
        // `-ghGraphDemo YES` seeds a synthetic year so the tile can be seen on
        // the simulator, where there's no real account to read.
        if UserDefaults.standard.bool(forKey: "ghGraphDemo") {
            if year == nil { year = ContributionYear.demo() }
            return
        }
        #endif
        guard !fetching else { return }
        if let f = fetchedAt, year != nil, Date.now.timeIntervalSince(f) < 6 * 3600 { return }
        guard let token = TokenVault.get(TokenBridge.github.tokenKey) else { return }
        fetching = true
        defer { fetching = false }
        if let y = await ContributionYear.fetch(token: token) {
            year = y
            fetchedAt = .now
        }
    }
}
