import Foundation
import SwiftData
import Observation

/// The agent NOTICES — at most one deterministic, checkable observation a day,
/// behind a glint on the agent bar (2026-08-14, prd §384).
///
/// This is the deterministic sibling of `HomeInsightStore`'s model-written
/// "Noticed" line, and the split is the design: the model's line is a
/// CONNECTION it composed (and may decline), this is a FACT the corpus can
/// prove — an anniversary, two rooms speaking about the same subject on the
/// same day, a fullest-day-ever. Every notice carries the ids of the things
/// it stands on, so the claim can be checked rather than believed (§83's rule
/// applied to delight). Three kinds, in priority order:
///
///   1. ANNIVERSARY — a thing from exactly N years ago today. The rarest and
///      the most personal; nil on nearly every day, which is correct — an
///      anniversary that fires constantly isn't one.
///   2. CROSS-SOURCE ECHO — two different rooms landed things wearing the
///      same tag today. The read only a corpus can make.
///   3. FULLEST DAY — today holds more captures than any day before it.
///      High-water seeded SILENTLY on first sight (`SourceMoments`' own
///      convention), so a fresh install's first day is never a fake record.
///
/// RARITY IS THE DESIGN: one notice per calendar day at most, each distinct
/// notice shown once ever (a capped ledger), and the whole thing stands down
/// silently on most days. A companion that taps you on the shoulder hourly is
/// a slot machine; the glint only means something if it is rare.
///
/// COST: its own bounded fetches (the §382 widget-deadline-scan precedent —
/// the foreground pass's newest-600 window structurally cannot hold a
/// three-years-ago thing): up to five one-day predicated fetches for the
/// anniversary years, one today-window fetch, one `fetchCount`. No model, no
/// network, no new `Thing` field.
@MainActor
@Observable
final class AgentNoticed {
    static let shared = AgentNoticed()

    struct Notice: Equatable {
        /// The observation, as one sentence.
        let line: String
        /// The things it stands on — the evidence rows the answer paints.
        let ids: [String]
        /// The dedupe identity ("anniv:<uuid>:<year>", "echo:<tag>:<day>",
        /// "record:<day>") — a notice is shown once, ever.
        let key: String
    }

    /// Today's notice, or nil — most days. Persisted so a relaunch keeps the
    /// glint it hadn't shown yet.
    private(set) var notice: Notice?
    /// Whether the person has RISEN to it — the glint clears on the first
    /// agent open after the notice lands; the chip stays for the day.
    private(set) var seen = false

    var glint: Bool { notice != nil && !seen }

    private static let lineKey = "agent.noticed.line"
    private static let idsKey = "agent.noticed.ids"
    private static let keyKey = "agent.noticed.key"
    private static let seenKey = "agent.noticed.seen"
    private static let dayKey = "agent.noticed.day"
    private static let ledgerKey = "agent.noticed.ledger"
    private static let highKey = "agent.noticed.dayHigh"

    private init() {
        let d = UserDefaults.standard
        if let line = d.string(forKey: Self.lineKey),
           let key = d.string(forKey: Self.keyKey),
           d.string(forKey: Self.dayKey) == Self.today() {
            notice = Notice(line: line,
                            ids: d.stringArray(forKey: Self.idsKey) ?? [],
                            key: key)
            seen = d.bool(forKey: Self.seenKey)
        }
    }

    /// The words that ask for it — the chip's own query, plus the natural
    /// phrasing. ONE definition, read by the chip and `RootShell`'s answer
    /// branch, so the chip can never send a query the answer path won't catch.
    nonisolated static func matches(_ query: String) -> Bool {
        let q = query.lowercased()
        return q == "noticed today" || q.contains("what did you notice")
            || q.contains("what have you noticed")
    }

    /// Recompute today's notice. Idempotent and cheap on repeat calls: once a
    /// notice exists for today (or today is stamped as checked-and-quiet),
    /// this returns immediately. Called from the same foreground block that
    /// refreshes `HomeInsightStore`.
    func refresh(context: ModelContext) {
        let today = Self.today()
        let d = UserDefaults.standard
        // ≤1 a day: today already produced its notice (or its silence).
        guard d.string(forKey: Self.dayKey) != today else { return }

        var ledger = Set(d.stringArray(forKey: Self.ledgerKey) ?? [])
        let found = observe(context: context, ledger: ledger)

        // Stamp the DAY either way — a quiet day is an answer, and re-walking
        // the corpus on every foreground to keep re-learning it is waste.
        d.set(today, forKey: Self.dayKey)
        notice = found
        seen = false
        if let found {
            ledger.insert(found.key)
            // Capped — the ledger is a dedupe record, not an archive.
            if ledger.count > 300 { ledger = Set(Array(ledger).suffix(250)) }
            d.set(Array(ledger), forKey: Self.ledgerKey)
            d.set(found.line, forKey: Self.lineKey)
            d.set(found.ids, forKey: Self.idsKey)
            d.set(found.key, forKey: Self.keyKey)
            d.set(false, forKey: Self.seenKey)
        } else {
            d.removeObject(forKey: Self.lineKey)
            d.removeObject(forKey: Self.idsKey)
            d.removeObject(forKey: Self.keyKey)
        }
    }

    /// The first agent open after a notice lands clears the glint — the tap
    /// on the shoulder was felt; the chip stays for the day.
    func markSeen() {
        guard notice != nil, !seen else { return }
        seen = true
        UserDefaults.standard.set(true, forKey: Self.seenKey)
    }

    // MARK: - The observations

    private func observe(context: ModelContext, ledger: Set<String>) -> Notice? {
        if let n = anniversary(context: context, ledger: ledger) { return n }
        if let n = crossSourceEcho(context: context, ledger: ledger) { return n }
        return recordDay(context: context, ledger: ledger)
    }

    /// A thing from exactly N years ago today (N in 1…5). Five one-day
    /// predicated fetches — a month/day match can't be expressed in a
    /// predicate, but "this exact historical day" can, and five tiny windows
    /// beat materializing the corpus. Import receipts excluded — the app's
    /// own row about a sync is not a memory.
    private func anniversary(context: ModelContext, ledger: Set<String>) -> Notice? {
        let cal = Calendar.current
        for years in 1...5 {
            guard let day = cal.date(byAdding: .year, value: -years, to: .now) else { continue }
            let start = cal.startOfDay(for: day)
            guard let end = cal.date(byAdding: .day, value: 1, to: start) else { continue }
            var fd = FetchDescriptor<Thing>(
                predicate: #Predicate<Thing> { $0.capturedAt >= start && $0.capturedAt < end },
                sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
            fd.fetchLimit = 12
            guard let rows = try? context.fetch(fd) else { continue }
            // Prefer something with a face or real words — a photo, a note, a
            // saved link — over firehose rows; a transaction anniversary is
            // nobody's memory.
            let candidates = rows.filter {
                !Corpus.isImportReceipt($0) && $0.kind != .transaction
                    && !$0.title.isEmpty
            }
            guard let pick = candidates.first(where: { $0.previewImageURL != nil })
                    ?? candidates.first else { continue }
            let key = "anniv:\(pick.id.uuidString):\(years)"
            guard !ledger.contains(key) else { continue }
            let title = pick.title.count > 60 ? String(pick.title.prefix(60)) + "…" : pick.title
            let when = years == 1
                ? String(localized: "A year ago today")
                : String(localized: "\(Self.spelled(years)) years ago today")
            return Notice(line: "\(when): \(title)",
                          ids: [pick.id.uuidString], key: key)
        }
        return nil
    }

    /// Two different rooms wearing the same tag today. Tags are filtered in
    /// Swift after a today-window fetch (the transformable-array predicate
    /// crash class — never `tags.contains` in a predicate).
    private func crossSourceEcho(context: ModelContext, ledger: Set<String>) -> Notice? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        var fd = FetchDescriptor<Thing>(
            predicate: #Predicate<Thing> { $0.capturedAt >= start },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        fd.fetchLimit = 200
        guard let rows = try? context.fetch(fd) else { return nil }
        // tag → (sources, thing ids), skipping the facet/machinery tags that
        // aren't subjects (§308's facets, pins, the state tags).
        let dull: Set<String> = ["Post", "Reply", "Liked", "Saved", "Thread", "Gone",
                                 "Conversation", "Memory", "Photo", "Shorts", "Video",
                                 "Pending", "Refund", "Watchlist", "Alert",
                                 "Review", "Release", "Build"]
        var byTag: [String: (sources: Set<String>, ids: [String])] = [:]
        for row in rows where !Corpus.isImportReceipt(row) {
            for tag in row.tags where !dull.contains(tag) {
                var entry = byTag[tag] ?? ([], [])
                entry.sources.insert(row.source)
                if entry.ids.count < 4 { entry.ids.append(row.id.uuidString) }
                byTag[tag] = entry
            }
        }
        let day = Self.today()
        // Deterministic winner: most sources, then alphabetical tag.
        let hits = byTag.filter { $0.value.sources.count >= 2 }
            .sorted { a, b in
                a.value.sources.count == b.value.sources.count
                    ? a.key < b.key : a.value.sources.count > b.value.sources.count
            }
        for (tag, entry) in hits {
            let key = "echo:\(tag):\(day)"
            guard !ledger.contains(key) else { continue }
            let names = ListFormatter.localizedString(byJoining: entry.sources.sorted())
            return Notice(line: String(localized: "\(names) are both on \(tag) today."),
                          ids: entry.ids, key: key)
        }
        return nil
    }

    /// Today holds more captures than any day before it. One `fetchCount`
    /// against a persisted high-water; the first sight SEEDS silently
    /// (`SourceMoments.notedNewHigh`'s rule), so no fresh install ever opens
    /// on a fake record. The floor keeps a two-thing Tuesday from ever being
    /// a "record".
    private func recordDay(context: ModelContext, ledger: Set<String>) -> Notice? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        let fd = FetchDescriptor<Thing>(
            predicate: #Predicate<Thing> { $0.capturedAt >= start })
        guard let count = try? context.fetchCount(fd) else { return nil }
        let d = UserDefaults.standard
        let high = d.integer(forKey: Self.highKey)
        if high == 0 {
            d.set(max(count, 1), forKey: Self.highKey)
            return nil
        }
        guard count > high else { return nil }
        d.set(count, forKey: Self.highKey)
        guard count >= 12 else { return nil }
        let day = Self.today()
        let key = "record:\(day)"
        guard !ledger.contains(key) else { return nil }
        return Notice(line: String(localized: "Your fullest day yet — \(count) things landed today."),
                      ids: [], key: key)
    }

    // MARK: - Helpers

    private static func today() -> String {
        Date.now.formatted(.iso8601.year().month().day())
    }

    private static func spelled(_ n: Int) -> String {
        switch n {
        case 2: return String(localized: "Two")
        case 3: return String(localized: "Three")
        case 4: return String(localized: "Four")
        case 5: return String(localized: "Five")
        default: return "\(n)"
        }
    }
}
