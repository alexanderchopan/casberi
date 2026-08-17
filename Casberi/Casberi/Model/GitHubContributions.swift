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
    /// The calendar day itself (2026-08-14, prd §384) — what a pressed cell
    /// NAMES. Optional with a nil default so every existing constructor is
    /// untouched; a grid built without dates still draws, its cells just
    /// answer a press with the count alone.
    var date: Date? = nil
}

struct ContributionWeek {
    /// Sunday…Saturday; a partial leading/trailing week may hold fewer than 7.
    let days: [ContributionDay]
}

struct ContributionYear {
    let total: Int
    let weeks: [ContributionWeek]

    /// A calendar of daily counts built from raw dates — the same 53×7 grid the
    /// GitHub graph draws, but sourced from any corpus (journal entries, workouts,
    /// screenshots) instead of GitHub's own API. Buckets each date into the
    /// trailing `columns` weeks ending this week (locale first-weekday aligned),
    /// and ramps intensity by the day's share of the busiest day — so the grid
    /// reads as a consistency-over-time story for whatever the source is.
    static func from(dates: [Date], calendar: Calendar = .current,
                     now: Date = .now, columns: Int = 53) -> ContributionYear {
        let startOfToday = calendar.startOfDay(for: now)
        // Days elapsed since this week began (respecting the locale's first day).
        let weekday = calendar.component(.weekday, from: startOfToday)
        let offsetIntoWeek = (weekday - calendar.firstWeekday + 7) % 7
        guard let startOfThisWeek = calendar.date(byAdding: .day, value: -offsetIntoWeek, to: startOfToday),
              let gridStart = calendar.date(byAdding: .day, value: -7 * (columns - 1), to: startOfThisWeek)
        else { return ContributionYear(total: 0, weeks: []) }

        var counts = [Int](repeating: 0, count: columns * 7)
        var total = 0
        for date in dates {
            let day = calendar.startOfDay(for: date)
            guard let diff = calendar.dateComponents([.day], from: gridStart, to: day).day,
                  diff >= 0, diff < counts.count else { continue }
            counts[diff] += 1
            total += 1
        }

        let busiest = counts.max() ?? 0
        func level(_ c: Int) -> Int {
            guard c > 0, busiest > 0 else { return 0 }
            switch Double(c) / Double(busiest) {
            case ..<0.25: return 1
            case ..<0.5:  return 2
            case ..<0.75: return 3
            default:      return 4
            }
        }

        var weeks: [ContributionWeek] = []
        weeks.reserveCapacity(columns)
        for col in 0..<columns {
            let days = (0..<7).map { row -> ContributionDay in
                let c = counts[col * 7 + row]
                // The cell's own day, off the same grid arithmetic that
                // bucketed the counts — so the date a press names is the date
                // the count was filed under, by construction.
                let date = calendar.date(byAdding: .day, value: col * 7 + row, to: gridStart)
                return ContributionDay(count: c, level: level(c), date: date)
            }
            weeks.append(ContributionWeek(days: days))
        }
        return ContributionYear(total: total, weeks: weeks)
    }

    /// Distinct days with at least one contribution — the grid needs a few lit
    /// cells to read as a heatmap rather than a loading skeleton.
    var activeDays: Int {
        weeks.reduce(0) { $0 + $1.days.filter { $0.count > 0 }.count }
    }

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
        totalContributions weeks { contributionDays { contributionCount contributionLevel date } } } } } }
        """
        guard let root = await IngestSupport.postJSON(
            "https://api.github.com/graphql", auth: "Bearer \(token)",
            body: ["query": query]) as? [String: Any],
              let data = root["data"] as? [String: Any],
              let viewer = data["viewer"] as? [String: Any],
              let cc = viewer["contributionsCollection"] as? [String: Any],
              let cal = cc["contributionCalendar"] as? [String: Any],
              let weeksRaw = cal["weeks"] as? [[String: Any]] else { return nil }
        // GitHub's own `date` field ("yyyy-MM-dd"), parsed once with a fixed
        // formatter — the calendar is UTC-day-keyed on their side, and a
        // pressed cell naming the day GitHub filed it under is the honest one.
        let dayFormat = DateFormatter()
        dayFormat.dateFormat = "yyyy-MM-dd"
        dayFormat.locale = Locale(identifier: "en_US_POSIX")
        let weeks = weeksRaw.map { w -> ContributionWeek in
            let days = ((w["contributionDays"] as? [[String: Any]]) ?? []).map { d in
                ContributionDay(count: d["contributionCount"] as? Int ?? 0,
                                level: level(d["contributionLevel"] as? String),
                                date: (d["date"] as? String).flatMap { dayFormat.date(from: $0) })
            }
            return ContributionWeek(days: days)
        }
        return ContributionYear(total: cal["totalContributions"] as? Int ?? 0, weeks: weeks)
    }

    /// A deterministic synthetic year — what the tile draws with no real
    /// account's data behind it.
    ///
    /// **Reachable in RELEASE since 2026-08-16, and that is the point.** It was
    /// `#if DEBUG` while its only caller was the `-ghGraphDemo` screenshot
    /// hook. The furnished demo is a mode a shipped build runs (prd §217), so
    /// the moment `GitHubGraphStore.refreshIfStale` began seeding this instead
    /// of reaching GitHub, a DEBUG-only body made the Release archive fail to
    /// compile — which is the good outcome of exactly the class
    /// `demo-selftest.py` check A was written for (`ChipMemory.seedDemo`
    /// shipping DEBUG-only while its caller was not). Every check in this repo
    /// compiles Debug, so nothing but a Release build could see it.
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
        // THE DEMO REACHES NOTHING (2026-08-16, caught by `verify.sh`'s own
        // "Demo reaches nothing" step: `api.github.com · 4 requests`, one per
        // launch, with `demoProbe| active=YES` in the same log).
        //
        // `BridgeRefresh.refreshAllConnected` returns instantly in demo mode
        // and that gate covers every SWEEP read — but this is a VIEW read, on
        // its own staleness clock, reached when the contribution tile mounts.
        // The sweep's gate can't see it, which is the whole bypass class this
        // check exists to catch, and the reason the gate belongs here rather
        // than one level up.
        //
        // It seeds the synthetic year rather than just returning: a demo whose
        // GitHub room draws an EMPTY grid is a worse demo than one that draws
        // a plausible one, and the same synthetic year already backs
        // `-ghGraphDemo`. Nothing is persisted and `fetchedAt` stays nil, so
        // leaving the demo re-arms a real fetch on the next mount.
        if DemoMode.isActive {
            if year == nil { year = ContributionYear.demo() }
            return
        }
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
