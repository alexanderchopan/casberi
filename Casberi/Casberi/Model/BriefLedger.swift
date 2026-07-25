import Foundation

/// What the brief has already said — the memory "What's going on?" never had
/// (prd §214, user: "how would we make it smarter", 2026-07-25).
///
/// Every `TodayBrief.compose` before this was a fresh read of the current
/// window, so the screen could not say *still*, *again*, or *third day
/// running*, and re-opening at 4pm re-led with the mention it had already led
/// with at 8am. This is the substrate under all of that: a short ledger of
/// what each window's brief actually showed.
///
/// Deliberately tiny and deterministic, the same shape as `AskMemory` and
/// `ChipMemory` — a capped array in UserDefaults, no ratios, no ML, no edit
/// surface. It records only what a person actually SAW: `TodayBrief.compose`
/// takes a `presenting` flag, and the digest refresh (`KeptAskStore
/// .refreshDigests`, which composes every kept kind in the background on each
/// foreground) passes false, so the app can never claim to have told you
/// something it only computed.
///
/// **Every claim built on it is checked against the calendar, not the entry
/// count.** A person who opens the app on Monday, Wednesday and Friday has
/// three entries; saying "three days running" would be a lie. So `streak`
/// walks back one calendar day at a time and stops the moment a day is
/// missing, and the absence read names a real DATE rather than counting
/// entries.
@MainActor
enum BriefLedger {

    /// One window's brief, as shown. Merged in place while the window stays
    /// open (the agent recomposes on every rise), so `leadIDs` accumulates
    /// everything today's brief has led with rather than only the last read.
    struct Entry: Codable, Equatable {
        /// The window's IDENTITY — what merge and novelty key on.
        var windowStart: Date
        /// The CALENDAR DAY the brief was composed on, and the only thing the
        /// streak and absence walks are allowed to do date arithmetic with.
        ///
        /// These are two different days more often than not: `windowStart` is
        /// the frozen away window, so a first open of the morning carries
        /// LAST NIGHT's date. Walking back from it counted a seven-day streak
        /// as six (caught by the probe, 2026-07-25) — it treated yesterday as
        /// "today" and then skipped it as already counted.
        var day: Date
        /// The last time this window's brief was actually presented.
        var at: Date
        /// The things that led — a mention card, a reading card. What
        /// novelty suppression checks against.
        var leadIDs: [String] = []
        /// The holding the lede credited ("ETH did the lifting") — the
        /// streak's subject.
        var ledeSymbol: String = ""
        /// The theme cells the map drew.
        var themes: [String] = []
        /// The sources that landed in this window — what absence is measured
        /// against.
        var sources: [String] = []
    }

    /// Two weeks of windows. Enough for a streak and an absence claim to mean
    /// something, short enough that the whole thing decodes in a blink.
    static let depth = 14

    /// How long the brief must have gone unseen before it starts holding
    /// back what it already told you. Rising the agent twice in a minute must
    /// show the same screen — suppression there would rewrite the page under
    /// the person's eyes. Thirty minutes says "you went away and came back",
    /// which is the only case where "what's changed since" is the question.
    static let revisitGap: TimeInterval = 30 * 60

    private static let storeKey = "brief.ledger"

    /// The whole ledger, oldest first. Read ONCE per compose and passed to
    /// the query functions below — the `ChipMemory.snapshot()` discipline, so
    /// a screen's worth of questions doesn't re-decode the store each time.
    static func snapshot() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return entries.sorted { $0.windowStart < $1.windowStart }
    }

    private static func write(_ entries: [Entry]) {
        let capped = Array(entries.sorted { $0.windowStart < $1.windowStart }.suffix(depth))
        guard let data = try? JSONEncoder().encode(capped) else { return }
        UserDefaults.standard.set(data, forKey: storeKey)
    }

    /// Merge-or-append for the current window. Called only when the brief was
    /// actually presented.
    ///
    /// Takes the caller's already-loaded ledger rather than re-reading it —
    /// `compose` snapshots once and threads it through everything, and
    /// re-decoding here would have made this file break its own stated rule
    /// on the one path that runs it.
    static func record(into entries: [Entry], windowStart: Date, leadIDs: [String],
                       ledeSymbol: String, themes: [String], sources: [String],
                       now: Date = .now, calendar: Calendar = .current) {
        var entries = entries
        if let i = entries.firstIndex(where: { $0.windowStart == windowStart }) {
            var entry = entries[i]
            entry.at = now
            entry.day = calendar.startOfDay(for: now)
            // Union, order-preserving: what led at 8am is still something
            // this window has told you, even if 4pm's read leads with
            // something else.
            for id in leadIDs where !entry.leadIDs.contains(id) { entry.leadIDs.append(id) }
            if !ledeSymbol.isEmpty { entry.ledeSymbol = ledeSymbol }
            entry.themes = themes
            for source in sources where !entry.sources.contains(source) { entry.sources.append(source) }
            entries[i] = entry
        } else {
            entries.append(Entry(windowStart: windowStart, day: calendar.startOfDay(for: now),
                                 at: now, leadIDs: leadIDs, ledeSymbol: ledeSymbol,
                                 themes: themes, sources: sources))
        }
        write(entries)
    }

    // MARK: - Novelty

    /// What this window's brief has already led with, and only once enough
    /// time has passed that showing something else reads as an update rather
    /// than a flicker. Empty on the first read of a window, empty on a
    /// re-rise moments later.
    static func told(_ entries: [Entry], windowStart: Date, now: Date = .now) -> Set<String> {
        guard let entry = entries.last(where: { $0.windowStart == windowStart }),
              now.timeIntervalSince(entry.at) >= revisitGap
        else { return [] }
        return Set(entry.leadIDs)
    }

    // MARK: - Continuity

    /// How many consecutive calendar days — today included — this lede symbol
    /// has led. 1 means only today, which is no streak at all.
    static func symbolStreak(_ entries: [Entry], symbol: String, now: Date = .now,
                             calendar: Calendar = .current) -> Int {
        guard !symbol.isEmpty else { return 0 }
        return streak(entries, now: now, calendar: calendar) {
            $0.ledeSymbol.caseInsensitiveCompare(symbol) == .orderedSame
        }
    }

    /// The same walk for a theme cell — "Foldables has been building for four
    /// days".
    static func themeStreak(_ entries: [Entry], theme: String, now: Date = .now,
                            calendar: Calendar = .current) -> Int {
        guard !theme.isEmpty else { return 0 }
        return streak(entries, now: now, calendar: calendar) {
            $0.themes.contains { $0.caseInsensitiveCompare(theme) == .orderedSame }
        }
    }

    /// Walks back one calendar day at a time from TODAY and stops at the first
    /// day that either has no entry or whose entry fails `holds`. Counting
    /// entries instead would let three opens across a week wear the words
    /// "three days running"; anchoring on `windowStart` instead of `now`
    /// under-counted by one whenever the away window reached back past
    /// midnight, which is the ordinary morning case.
    private static func streak(_ entries: [Entry], now: Date, calendar: Calendar,
                               holds: (Entry) -> Bool) -> Int {
        var run = 1   // today
        var day = calendar.startOfDay(for: now)
        while true {
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            guard let entry = entries.last(where: { calendar.isDate($0.day, inSameDayAs: prev) }),
                  holds(entry) else { break }
            run += 1
            day = prev
        }
        return run
    }

    // MARK: - Absence

    /// A source that has landed something every single time the brief has
    /// looked, going back at least `absenceFloor` reads and a real stretch of
    /// calendar — and hasn't today. Returns the source and the date its run
    /// started, so the line can name a day instead of counting entries.
    ///
    /// The rarest honest signal left after §213 outlawed volume: an absence
    /// is a state change, not a tally, and it cannot be manufactured on a
    /// quiet day because a day where nothing landed at all is excluded by the
    /// caller.
    static func absent(_ entries: [Entry], landedSources: Set<String>,
                       now: Date = .now, calendar: Calendar = .current) -> (source: String, since: Date)? {
        let today = calendar.startOfDay(for: now)
        let prior = entries.filter { $0.day < today }
        guard prior.count >= absenceFloor else { return nil }
        var best: (source: String, since: Date, runs: Int)?
        // Only sources the ledger has actually seen are candidates — a source
        // connected this morning can't be "missing".
        for source in Set(prior.flatMap(\.sources)) where !landedSources.contains(source) {
            var runs = 0
            var since = today
            for entry in prior.reversed() {
                guard entry.sources.contains(source) else { break }
                runs += 1
                since = entry.day
            }
            guard runs >= absenceFloor,
                  let days = calendar.dateComponents([.day], from: since, to: now).day,
                  days >= absenceSpanDays
            else { continue }
            if best == nil || runs > best!.runs { best = (source, since, runs) }
        }
        return best.map { ($0.source, $0.since) }
    }

    /// Four unbroken appearances and five days of calendar before an absence
    /// is worth a sentence — under that it's a coincidence, and the whole
    /// point of this family is that it fires rarely.
    static let absenceFloor = 4
    static let absenceSpanDays = 5

    #if DEBUG
    /// `-briefLedger clear` empties the ledger;
    /// `-briefLedger "days=6;symbol=ETH;themes=Foldables,Recipes;sources=RSS,Bluesky"`
    /// plants that many prior daily entries (one per calendar day, ending
    /// yesterday) so a streak or an absence verifies in one launch instead of
    /// a week of real use. Runs once per launch.
    private static var seededThisLaunch = false
    static func seedFromLaunchArgs() {
        guard !seededThisLaunch else { return }
        seededThisLaunch = true
        guard let spec = UserDefaults.standard.string(forKey: "briefLedger"),
              !spec.isEmpty else { return }
        if spec == "clear" {
            UserDefaults.standard.removeObject(forKey: storeKey)
            NSLog("[Casberi] briefLedger: cleared")
            return
        }
        var fields: [String: String] = [:]
        for pair in spec.split(separator: ";") {
            guard let eq = pair.firstIndex(of: "=") else { continue }
            fields[String(pair[pair.startIndex..<eq]).trimmingCharacters(in: .whitespaces)] =
                String(pair[pair.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
        }
        let days = Int(fields["days"] ?? "") ?? 0
        guard days > 0 else { return }
        let list: (String) -> [String] = { key in
            (fields[key] ?? "").split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var entries: [Entry] = []
        for back in 1...days {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
            entries.append(Entry(windowStart: day, day: day, at: day,
                                 ledeSymbol: fields["symbol"] ?? "",
                                 themes: list("themes"), sources: list("sources")))
        }
        write(entries)
        NSLog("[Casberi] briefLedger: seeded %d prior windows", entries.count)
    }
    #endif
}
