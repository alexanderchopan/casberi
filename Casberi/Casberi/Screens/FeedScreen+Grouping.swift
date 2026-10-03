import SwiftUI
import SwiftData

// Grouping and bundling: day, coarse and session groups, `FeedRow`, folds,
// the lede's pick and the moment split, split out of
// FeedScreen.swift (prd §718). Nothing here changed but the file it lives
// in and, where another file reads a member, its access level.
extension FeedScreen {
    /// Day groups, newest day first ("Today", "Yesterday", then dated). A feed
    /// is history — it reads from today back. A reminder/event lands with
    /// `capturedAt` set to when it's DUE, so a future-dated thing sorts newest
    /// by raw time and would LEAD the feed — a Wednesday sitting above Today
    /// (user, 2026-07-19). What's still ahead lives on Home's "Coming up" lane,
    /// not here, so future days are dropped from the walk; the feed starts on
    /// Today. (Timed things still to come LATER today stay under Today — the
    /// day, not the clock, is what leads.)
    func dayGroups(_ visible: [Thing]) -> [(String, [Thing])] {
        let today = Self.groupingCalendar.startOfDay(for: .now)
        var order: [String] = []
        var groups: [String: [Thing]] = [:]
        for thing in visible
        where Self.groupingCalendar.startOfDay(for: thing.capturedAt) <= today {
            let label = dayLabel(thing.capturedAt)
            if groups[label] == nil { order.append(label) }
            groups[label, default: []].append(thing)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    /// Day groups, but COARSENED to week/month grain when the source lands
    /// sparsely (ruling 2026-07-21, the day-cards sequel): a source that
    /// drops one thing most days would otherwise become a ladder of one-row
    /// day cards under big headers — exactly the confetti day-cards killed,
    /// re-expressed as headers. When the trailing history averages under
    /// ~1.5 things a day (and there's enough of it to judge), the same rows
    /// regroup as "This week / Last week / <month>" instead. A dense feed
    /// (social bursts, an RSS sync) stays day-grained untouched — this is a
    /// no-op above the threshold, so every chronological source can route
    /// through it safely.
    func chronoGroups(_ visible: [Thing]) -> [(String, [Thing])] {
        coarsenIfSparse(dayGroups(visible))
    }

    /// Day grain for the last week, coarsened grain behind it (prd §218).
    ///
    /// `coarsenIfSparse` judges a feed as a WHOLE and is all-or-nothing, which
    /// is right for one source's room. The All feed is different: it spans the
    /// entire corpus, so its head is dense (dozens a day) while its tail is
    /// always thin — and the whole-feed average, dragged up by the head, meant
    /// All was the ONE chronological feed that never coarsened at all. Scroll
    /// back far enough and it became the ladder of one-row day cards the
    /// 2026-07-21 ruling killed for every other source.
    ///
    /// So the split is by recency, not by average: the last 7 days always keep
    /// their own day cards (that's the part you're actually reading), and
    /// everything older goes through the existing sparseness gate — which
    /// leaves a genuinely dense older stretch day-grained, exactly as before.
    ///
    /// The gate is asked in ROWS here, not things (prd §255) — this is the one
    /// feed that bundles, so it's the one feed where the two numbers differ,
    /// and counting things is what kept the fold from ever happening.
    func recentDaysThenCoarseTail(_ visible: [Thing]) -> [(String, [Thing])] {
        let cal = Self.groupingCalendar
        guard let cutoff = cal.date(byAdding: .day, value: -7,
                                    to: cal.startOfDay(for: .now))
        else { return dayGroups(visible) }
        let recent = visible.filter { $0.capturedAt >= cutoff }
        let older = visible.filter { $0.capturedAt < cutoff }
        // Wrapped rather than passed by reference: `bundledRowCount` grew a
        // defaulted `nextEventID`, and Swift does not apply default arguments
        // when converting a function to a value.
        return dayGroups(recent)
            + coarsenIfSparse(dayGroups(older), rows: { bundledRowCount($0) })
    }

    /// The sparseness gate + regroup, shared by the plain day path and the
    /// agent path (which builds its own day groups first).
    ///
    /// `rows` answers how many ROWS a day will actually DRAW, which is not
    /// always how many things it holds (prd §255, 2026-07-31). In a source's
    /// own room the two are the same number and the default is right. The All
    /// feed BUNDLES after grouping, so a day whose seven wallet transactions
    /// collapse into one row was scoring seven here — and this gate, whose
    /// entire job is to prevent a ladder of one-row day cards, therefore never
    /// once fired on the one feed that actually had one. Measured on a real
    /// corpus: single-row days marching back 487 days, every header full
    /// weight, while the gate read the tail as "dense" and left it alone.
    ///
    /// The old comment here claimed the average "matches what the feed
    /// actually renders". That was the bug, stated as a fact.
    private func coarsenIfSparse(_ days: [(String, [Thing])],
                                 rows: ([Thing]) -> Int = { $0.count }) -> [(String, [Thing])] {
        let drawn = days.reduce(0) { $0 + rows($1.1) }
        guard days.count >= 6,
              Double(drawn) / Double(days.count) < 1.5 else { return days }
        return coarseGroups(days.flatMap { $0.1 })
    }

    /// How many rows a day's things draw once `bundle` has run over them.
    ///
    /// Asks the REAL fold decision (`foldBuckets` + `fold`) rather than
    /// mirroring it. It used to mirror — a hand-copy of "a source with
    /// `bundleThreshold`+ bundleable things collapses to one row" — and §255
    /// is the record of what that costs: the gate measured THINGS while the
    /// feed drew ROWS, so the tail-coarsening it guards never once fired.
    /// Two folds (a bundle and a strip, with different eligibility) is exactly
    /// where a second copy would go quietly wrong again, so there is only one.
    ///
    /// `nextEventID` defaults to nil, and that is CORRECT rather than lazy for
    /// this caller: the clock carve-out below only ever spares a FUTURE event,
    /// which by construction cannot sit in the coarsened tail this gate is
    /// deciding about.
    func bundledRowCount(_ dayThings: [Thing], nextEventID: UUID? = nil) -> Int {
        let (bySource, eligible) = foldBuckets(dayThings, nextEventID: nextEventID)
        var folded: Set<String> = []
        for (source, members) in bySource
        where FeedFold.decide(members, faceSources: BandRow.faceSources) != nil {
            folded.insert(source)
        }
        var rows = 0
        var seen: Set<String> = []
        for t in dayThings {
            if folded.contains(t.source), eligible.contains(ObjectIdentifier(t)) {
                if seen.insert(t.source).inserted { rows += 1 }
            } else {
                rows += 1
            }
        }
        return rows
    }

    /// Regroup already-ordered (newest-first) things by week, then month —
    /// "This week", "Last week", then month names for the tail (a week grain
    /// that ran all the way down would ladder into "3 weeks ago, 4 weeks
    /// ago"; months are how sparse history actually reads back).
    private func coarseGroups(_ things: [Thing]) -> [(String, [Thing])] {
        var order: [String] = []
        var groups: [String: [Thing]] = [:]
        for t in things {
            let label = coarseLabel(t.capturedAt)
            if groups[label] == nil { order.append(label) }
            groups[label, default: []].append(t)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    /// Which of these groups came from the COARSE regroup above rather than the
    /// day grain — the folded tail (prd §254, 2026-07-31), whose headers weigh
    /// one step less than a day's.
    ///
    /// Asked of `coarseLabel` ITSELF rather than pattern-matched off the
    /// string: a group is coarse exactly when its label is what `coarseLabel`
    /// would name its own members. That keeps it correct in every language (no
    /// English words here), and — the reason it isn't the simpler "is this not
    /// a `dayLabel`?" — it leaves the MUSIC room's session groups ("This
    /// morning", "Mon evening") alone, which are a different grain, not a
    /// coarser one.
    func coarseLabels(in groups: [(String, [Thing])]) -> Set<String> {
        Set(groups.compactMap { label, rows -> String? in
            // `.isLive` before `capturedAt`: a derived array, read during the
            // same graph update a heal's delete can land in (the dead-Thing
            // rule, CLAUDE.md).
            guard let first = rows.first(where: \.isLive) else { return nil }
            return label == coarseLabel(first.capturedAt) ? label : nil
        })
    }

    private func coarseLabel(_ date: Date) -> String {
        let cal = Self.groupingCalendar
        if cal.isDate(date, equalTo: .now, toGranularity: .weekOfYear) {
            return String(localized: "This week")
        }
        if let lastWeek = cal.date(byAdding: .weekOfYear, value: -1, to: .now),
           cal.isDate(date, equalTo: lastWeek, toGranularity: .weekOfYear) {
            return String(localized: "Last week")
        }
        if cal.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.wide))
        }
        return date.formatted(.dateTime.month(.wide).year())
    }

    /// Music lands in SITTINGS, not calendar days (ruling 2026-07-21) — the
    /// day header answers "when" but the real unit of listening is the
    /// session. Consecutive plays less than 45 min apart cluster into one
    /// group, labelled by its start ("This morning", "Yesterday evening",
    /// "Mon evening"). A single session that straddles the whole day still
    /// reads as one card; two listens hours apart split honestly.
    func sessionGroups(_ visible: [Thing]) -> [(String, [Thing])] {
        let sorted = visible.sorted { $0.capturedAt > $1.capturedAt }
        guard let first = sorted.first else { return [] }
        let gap: TimeInterval = 45 * 60
        var sessions: [[Thing]] = []
        var current: [Thing] = [first]
        for t in sorted.dropFirst() {
            if let last = current.last,
               last.capturedAt.timeIntervalSince(t.capturedAt) <= gap {
                current.append(t)
            } else {
                sessions.append(current)
                current = [t]
            }
        }
        sessions.append(current)
        let labelled = sessions.map { (sessionLabel($0.first!.capturedAt), $0) }
        // groupedSections keys its ForEach on the label, so two sittings that
        // share one ("this morning" twice, >45 min apart) would collide into
        // one SwiftUI id. Append the start clock ONLY to a colliding label, so
        // the common single-session case stays clean.
        var counts: [String: Int] = [:]
        for (label, _) in labelled { counts[label, default: 0] += 1 }
        return labelled.map { label, rows in
            guard (counts[label] ?? 0) > 1 else { return (label, rows) }
            let time = rows.first!.capturedAt.formatted(date: .omitted, time: .shortened)
            return ("\(label) · \(time)", rows)
        }
    }

    private func sessionLabel(_ date: Date) -> String {
        let cal = Self.groupingCalendar
        let part: String
        switch cal.component(.hour, from: date) {
        case 5..<12:  part = String(localized: "morning")
        case 12..<17: part = String(localized: "afternoon")
        case 17..<22: part = String(localized: "evening")
        default:      part = String(localized: "late night")
        }
        if cal.isDateInToday(date) {
            return String(localized: "This \(part)")
        }
        if cal.isDateInYesterday(date) {
            return String(localized: "Yesterday \(part)")
        }
        return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(part)"
    }

    // MARK: - Bundling (ruling 2026-07-09: volume compresses, never reorders)

    /// A feed row in the All shape: a thing, or one row standing in for a
    /// source's bulk arrivals that day.
    /// `id` and `date` are STORED, captured at construction — never computed
    /// off the wrapped `Thing` on demand (2026-07-24 crash fix). As an enum
    /// whose `id` read `t.id.uuidString` lazily, `ForEach`'s identity diffing
    /// (`ForEachChild.updateValue()`) reached into the SwiftData model every
    /// graph update; when a launch-time dedupe (`SyncReconcile`) or a CloudKit
    /// merge deleted that `Thing` mid-render, the read trapped inside SwiftData
    /// (`_assertionFailure`) — the field crash reported as "crashes on open
    /// after an update, never on a fresh install," since only an updated
    /// install has synced duplicates to delete. Capturing the id/date as plain
    /// value types at construction (below, while the `Thing` is still valid)
    /// keeps the diffing path off the model entirely; the model is only touched
    /// in the row body, which renders exclusively from the post-delete `@Query`
    /// snapshot that already excludes the deleted row.
    /// How many things a feed row stands for — a fold its members, anything
    /// else one (the `Show older` door's count, prd §900).
    static func things(in row: FeedRow) -> Int {
        switch row.kind {
        case .single: 1
        case .bundle(_, _, _, let count, _, _): count
        case .strip(_, _, let count, _, _): count
        }
    }

    struct FeedRow: Identifiable {
        let id: String
        let date: Date
        let kind: Kind
        /// The ambient tier (prd §378) — a row that arrived on its own rather
        /// than one you made or one that concerns you. STORED at construction,
        /// exactly like `id` and `date` and for the same reason: the render
        /// loop must be able to ask "does this recede?" without a
        /// stored-property read on a model a heal may since have deleted.
        let ambient: Bool
        enum Kind {
            /// `KeyedThing`, not a raw `Thing` — so every read of the model
            /// goes through `.thing`/`.live` and the liveness audit's check 3
            /// can SEE it. Build 176 trapped right here, in a row body that
            /// bound its `Thing` straight out of this payload: correct by the
            /// rules as written, invisible to the lint that enforces them.
            case single(KeyedThing)
            /// `art`: up to three member preview-image URLs, newest first — the
            /// bundle's own pictures (2026-07-21), so "Photos · 100 photos"
            /// can show what actually arrived instead of one brand glyph.
            ///
            /// `lead` is the newest member's title, the line the row draws
            /// before "+N more" (prd §896); `word` is the kind's plural, which
            /// only the Wallet room's own fold still says ("14 transfers").
            case bundle(source: String, word: String, lead: String, count: Int,
                        newest: Date, art: [String])
            /// A run folded into its MEMBERS rather than into a sentence about
            /// them (prd §377): screenshots and file images as their pictures,
            /// posts as their authors' faces, songs as their covers. Same
            /// one-row compression as `.bundle`, drawn side by side instead of
            /// as an overlapped fan.
            case strip(source: String, lead: String, count: Int, newest: Date, tiles: [StripTile])
        }
        static func single(_ t: Thing) -> FeedRow {
            FeedRow(id: t.id.uuidString, date: t.capturedAt, kind: .single(KeyedThing(t)),
                    ambient: FeedFold.tier(t) == .arrived)
        }
        static func bundle(source: String, word: String = "", lead: String = "",
                           count: Int, newest: Date, art: [String],
                           ambient: Bool) -> FeedRow {
            FeedRow(id: "bundle-\(source)-\(newest.timeIntervalSince1970)", date: newest,
                    kind: .bundle(source: source, word: word, lead: lead, count: count,
                                  newest: newest, art: art),
                    ambient: ambient)
        }
        static func strip(source: String, lead: String, count: Int,
                          newest: Date, tiles: [StripTile], ambient: Bool) -> FeedRow {
            FeedRow(id: "strip-\(source)-\(newest.timeIntervalSince1970)", date: newest,
                    kind: .strip(source: source, lead: lead, count: count,
                                 newest: newest, tiles: tiles),
                    ambient: ambient)
        }
    }

    /// `Screens/ThingRowKeying.swift`'s `KeyedThing` — this screen used to
    /// carry a PRIVATE copy of it, which shadowed the shared type here and let
    /// the two drift: the copy never gained `live`, the corollary-3 guard, and
    /// its doc still claimed row bodies "only ever render the post-delete
    /// `@Query` snapshot" (the assumption build 176 disproved). One type now.
    func keyed(_ things: [Thing]) -> [KeyedThing] { things.keyed }

    /// Consecutive self-replies fold into one thread (item 6 of the
    /// 2026-07-27 social enrichment pass) — a person's own reply chain reads
    /// top-to-bottom as one card in their room, instead of N separate rows a
    /// chronological feed would otherwise interleave with everything else.
    /// Pure over whatever `[Thing]` the caller hands it; called only for
    /// `shape == .social`, so the mixed All feed is never touched.
    ///
    /// `heads` is `things` with every swallowed reply removed — safe to feed
    /// straight into the existing day-grouped `ForEach` pipeline (same array
    /// shape, just fewer rows). `byHeadID` maps a head's `id.uuidString` to
    /// its ordered replies (oldest first, the order a thread was written
    /// in) — plain `[Thing]`, re-wrapped into a `KeyedThing` only at the
    /// point `SocialThreadCard` renders them, since these ride a side
    /// dictionary rather than a `ForEach`'s own diffed array.
    func foldThreadReplies(_ things: [Thing]) -> (heads: [Thing], byHeadID: [String: [Thing]]) {
        var bySourceRef: [String: Thing] = [:]
        for t in things {
            if let ref = t.sourceRef { bySourceRef[ref] = t }
        }
        var childrenOfRoot: [String: [Thing]] = [:]
        var swallowed: Set<UUID> = []
        for t in things {
            guard let handle = t.authorHandle, !handle.isEmpty,
                  let parentRef = t.parent?.ref,
                  let parent = bySourceRef[parentRef],
                  parent.authorHandle == handle,
                  // One network's thread: the merged Social room hands this
                  // every network at once (prd §1079), and a handle is only
                  // a person within its own network.
                  parent.source == t.source
            else { continue }
            // Walk to the chain's ROOT so a three-deep thread groups under
            // its first post rather than nesting a thread of threads. Capped
            // defensively — a real reply chain is never this deep, but
            // nothing here guarantees the data can't cycle.
            var root = parent
            var hops = 0
            while hops < 32,
                  let grandparentRef = root.parent?.ref,
                  let grandparent = bySourceRef[grandparentRef],
                  grandparent.authorHandle == handle,
                  grandparent.source == t.source {
                root = grandparent
                hops += 1
            }
            childrenOfRoot[root.id.uuidString, default: []].append(t)
            swallowed.insert(t.id)
        }
        guard !swallowed.isEmpty else { return (things, [:]) }
        let heads = things.filter { !swallowed.contains($0.id) }
        var byHeadID: [String: [Thing]] = [:]
        for (rootID, kids) in childrenOfRoot {
            byHeadID[rootID] = kids.sorted { $0.capturedAt < $1.capturedAt }
        }
        return (heads, byHeadID)
    }

    /// Machine bulk bundles; human captures never do. A screenshot, a voice
    /// note, or anything typed/pasted is one deliberate act each — an RSS
    /// sync or a wallet backfill is one act producing many rows.
    /// A screenshot Vision read and found NO words in — `ocrAt` set (the read
    /// happened) with nothing to show for it. Distinct from "not read yet",
    /// which still wears the placeholder and is about to be retitled.
    private func isWordless(_ t: Thing) -> Bool {
        if t.kind == .screenshot { return t.ocrAt != nil && t.content.isEmpty }
        // A folder-picked image reads the same way (2026-07-27) — OCR ran,
        // found nothing, and the picture already carries the row; gated on
        // `previewImageData` too so a not-yet-thumbnailed image (still
        // showing its byte size as `content`, `ocrAt` untouched) never
        // qualifies before there's actually a picture to show.
        if t.kind == .file, t.source == "Files" {
            return t.ocrAt != nil && t.content.isEmpty && t.previewImageData != nil
        }
        return false
    }

    /// Which rows render as a picture with no title (prd §218) — the wordless
    /// screenshots (and, since 2026-07-27, wordless Files images) of each
    /// day, but ONLY while they're a MINORITY of that day.
    ///
    /// The gate is the whole design. One wordless shot among five rows is a
    /// picture worth looking at; a day that's mostly wordless shots would
    /// become a column of 58pt tiles — which is the Photos grid, a shape that
    /// already exists behind its own chip. Past half a day, they fall back to
    /// the ordinary band and keep the honest filename as the title.
    func imageOnlyIDs(_ days: [(String, [Thing])]) -> Set<UUID> {
        var ids: Set<UUID> = []
        for (_, dayThings) in days {
            let wordless = dayThings.filter(isWordless)
            guard wordless.count * 2 < dayThings.count else { continue }
            ids.formUnion(wordless.map(\.id))
        }
        return ids
    }

    /// The ONE row per day whose own picture reads at size (prd §254,
    /// 2026-07-31) — the newest post or article that actually carries art.
    ///
    /// §218 gave a wordless screenshot the room its missing words would have
    /// had; this is the same argument for a row that HAS words: the picture is
    /// the part you can't get from the title, and at 26pt a day of them is a
    /// column of specks. One per day, so the feed gains an anchor without
    /// becoming a gallery — the same minority discipline `imageOnlyIDs` uses,
    /// stated as a count instead of a ratio.
    ///
    /// Read off the BUNDLED groups, not the raw days: a row that collapsed
    /// into a bundle never renders as a band, so choosing from the day would
    /// silently promote a row nobody can see (RSS is bundleable, and RSS is
    /// one of the three sources that qualify).
    ///
    /// Withheld under 3 rows — on a two-row day the promoted picture is half
    /// the day, which is a gallery, not an anchor.
    func wideArtIDs(_ groups: [(String, [FeedRow])]) -> Set<UUID> {
        var ids: Set<UUID> = []
        for (_, rows) in groups where rows.count >= 3 {
            for row in rows {
                // `.live` before any stored read (corollary 3, build 176).
                guard case .single(let item) = row.kind, let thing = item.live
                else { continue }
                if BandRow.artRidesBesideIdentity(thing) {
                    ids.insert(thing.id)
                    break
                }
            }
        }
        return ids
    }

    /// `bundleThreshold`+ foldable things from one source in one day collapse
    /// into ONE row at the position of their newest member — a `StripRow` when
    /// the members can be drawn as themselves, a `BundleRow` otherwise (see
    /// `fold`). Order is untouched either way — compression, not ranking.
    /// Takes the already-computed day groups so the caller derives `dayGroups`
    /// (→`visible`→`feedThings`) ONCE per render and reuses it for the day
    /// totals too, instead of rebuilding the whole chain here a second time.
    ///
    /// `excluding` is the cover (prd §389c) — removed BEFORE the fold buckets
    /// are built, not filtered out of the finished rows, so a source whose run
    /// the cover was part of counts and draws its remaining members honestly
    /// (three mails minus the cover is two mails, which is under
    /// `bundleThreshold` and correctly stops folding at all). Filtering after
    /// the fact would have left "iCloud Mail · 3 emails" beside a cover that is
    /// one of those three.
    func bundle(_ days: [(String, [Thing])],
                        nextEventID: UUID? = nil,
                        excluding cover: UUID? = nil) -> [(String, [FeedRow])] {
        days.map { label, allDayThings in
            let dayThings = cover.map { id in allDayThings.filter { $0.id != id } }
                ?? allDayThings
            // Grouped ONCE per day (perf, 2026-07-28): the old version
            // re-filtered the whole day for every bundled source it found
            // (O(day size²) — a heavy sync day with several bundled sources
            // multiplied its own count against itself). Same membership,
            // built with one pass instead of one pass per source.
            let (bySource, eligible) = foldBuckets(dayThings, nextEventID: nextEventID)
            var folded: [String: FeedFold.Decision] = [:]
            for (source, members) in bySource {
                if let decision = FeedFold.decide(members, faceSources: BandRow.faceSources) {
                    folded[source] = decision
                }
            }
            var rows: [FeedRow] = []
            var seen: Set<String> = []
            for t in dayThings {
                guard let decision = folded[t.source],
                      eligible.contains(ObjectIdentifier(t)) else {
                    rows.append(.single(t)); continue
                }
                guard seen.insert(t.source).inserted else { continue }
                let members = bySource[t.source] ?? []
                // The line names the newest member and counts the rest (prd
                // §896). `t` IS the newest: the fold stands where its first
                // member in the day's order stands. Read here, while the
                // model is live — the row value carries a string, never it.
                let lead = t.title
                // A fold recedes only if EVERY member would — one transaction
                // or one clock inside a mixed run keeps the whole row at full
                // weight, since the row is the only thing standing in for it.
                let ambient = FeedFold.ambient(members)
                switch decision {
                case .strip(let choices):
                    // A choice names its member by INDEX — the seam that keeps
                    // `FeedFold` free of SwiftData and therefore harnessable
                    // (§379). The models are still live here: this runs while
                    // building the row value, the same moment `FeedRow.single`
                    // captures its id.
                    let tiles = choices.map {
                        StripTile(members[$0.index], remote: $0.remote, circular: $0.circular)
                    }
                    rows.append(.strip(source: t.source, lead: lead,
                                       count: members.count, newest: t.capturedAt,
                                       tiles: tiles, ambient: ambient))
                case .bundle(let art):
                    rows.append(.bundle(source: t.source, lead: lead,
                                        count: members.count, newest: t.capturedAt,
                                        art: art, ambient: ambient))
                }
            }
            return (label, rows)
        }
        // A day whose only row was the cover has no run left, and a header
        // over nothing is a sentence about nothing (the All feed showed a
        // bare "Today" above "Yesterday" on a day-old pour, 2026-09-26). The
        // cover still resolves from `memo.days`, which is untouched.
        .filter { !$0.1.isEmpty }
    }

    /// The things in a day that are ELIGIBLE to fold, bucketed by source, plus
    /// their identities so the row loop can ask "was this one folded?" in
    /// constant time (the O(day²) trap the 2026-07-28 perf pass fixed once
    /// already — a `contains(where:)` per thing would put it straight back).
    ///
    /// Two things are held out, for opposite reasons:
    ///
    /// - Anything neither `bundleable` nor a strip candidate. A screenshot is
    ///   the case worth naming: it is deliberately still NOT `bundleable`, so
    ///   it can never collapse into "Photos · 4 screenshots" — a sentence that
    ///   hides the only thing a screenshot has. It folds only into a strip,
    ///   where its picture survives.
    /// - Anything carrying a CLOCK (prd §377). §35 ruled that perishables show
    ///   their countdown "everywhere … not just in their source's shape", and
    ///   nothing enforced it: a day with three calendar events folded the
    ///   next-up row away, and a live row can't be floated to the top of its
    ///   day (2026-07-21) once it has stopped existing as a row. Its siblings
    ///   still fold; the row with the clock stands out of the fold.
    private func foldBuckets(_ dayThings: [Thing], nextEventID: UUID?)
        -> (bySource: [String: [Thing]], eligible: Set<ObjectIdentifier>) {
        var bySource: [String: [Thing]] = [:]
        var eligible: Set<ObjectIdentifier> = []
        for t in dayThings {
            guard FeedFold.bundleable(t)
                    || FeedFold.stripCandidate(t, faceSources: BandRow.faceSources)
            else { continue }
            guard !FeedFold.carriesAClock(t, nextEventID: nextEventID,
                                          isLive: isLive(t)) else { continue }
            bySource[t.source, default: []].append(t)
            eligible.insert(ObjectIdentifier(t))
        }
        return (bySource, eligible)
    }

    /// The first row at-or-past the last-visit boundary — the "new since"
    /// divider renders above it. Nil when nothing is new (no divider at the
    /// very top) or everything is (no divider at the very bottom).
    ///
    /// Takes the already-bundled groups so the caller computes them ONCE per
    /// render and shares them — as a bare computed property this rebuilt the
    /// whole bundle chain, and it was read once per row (the Feed-freeze
    /// O(rows × corpus) blowup, perf pass 2026-07-13).
    func boundaryID(in groups: [(String, [FeedRow])]) -> String? {
        guard let newSince else { return nil }
        let all = groups.flatMap(\.1)
        guard let first = all.first, first.date > newSince else { return nil }
        return all.first(where: { $0.date <= newSince })?.id
    }

    /// Past this, the newest thing is not news and gets no cover (prd §389).
    /// A hero is a claim about recency and nothing else, so it needs a clock
    /// to be true — open the app after a quiet week and the top row is a week
    /// old, which is exactly when a cover would be lying by implication.
    private static let ledeMaxAge: TimeInterval = 24 * 3600

    /// Whether the All feed's newest thing is still news (prd §389, §879).
    ///
    /// NEWS TO YOU, not only news to the clock. §389's objection stands: open
    /// the app after a quiet week and a week-old top row under a cover lies by
    /// implication. But when that row landed AFTER you last left, it is
    /// exactly what the cover is for — the first thing you have not seen —
    /// and the 24-hour bound alone took the cover away on precisely the opens
    /// with the most news on them (away two days, and yesterday's arrivals
    /// are the story). `away` is `AppVisit.away`, the same window "Since you
    /// left" is cut on, so the cover and the section always agree.
    static func isCoverFresh(_ date: Date, away: Range<Date>?, now: Date = .now) -> Bool {
        if now.timeIntervalSince(date) <= ledeMaxAge { return true }
        guard let away else { return false }
        return date > away.lowerBound
    }

    /// A cover over a two-row feed IS the feed. Same minority discipline
    /// `wideArtIDs` states as its own floor, for the same reason.
    static let ledeMinRows = 3

    /// The THING that draws as the feed's cover (prd §389c, 2026-08-16) — the
    /// newest one in the newest day, full stop, whether or not it would
    /// otherwise have folded. It is lifted OUT of the rows below (see
    /// `bundle(_:nextEventID:excluding:)`), so it appears exactly once; when
    /// the next thing lands it takes the cover and this one drops back into its
    /// own row, or into its source's fold.
    ///
    /// **Chosen over THINGS, before bundling — not over rows, after it.** The
    /// §389b version read the bundled rows and stepped over folds to find the
    /// newest thing that had arrived on its own, and its own doc admitted the
    /// consequence: "the cover may not be the newest thing on screen, since a
    /// fold above it can be newer." Reported as exactly that within the day — an
    /// eight-hour-old voice note leading over a newer email, because mail had
    /// folded and voice can never fold (`FeedFold.bundleable` excludes voice,
    /// screenshots and anything from You, so the §389b candidate pool was
    /// biased toward precisely the rows that never fold, and a stale one could
    /// hold the top of the feed for a full `ledeMaxAge`). The feed's standing
    /// law is that volume compresses and NEVER reorders (§35); the cover was
    /// the one place that reordered, so the fix is to make it unable to.
    ///
    /// **THE TWO FRESHNESS GATES ARE THE ALL FEED'S ALONE (prd §723, user: "i
    /// think each room should always show its newest item in the card").** A
    /// ROOM always covers its newest thing. The two readings are different
    /// questions and it took the board's deletion to see it: the All feed is a
    /// river, so a cover there is a claim that something just landed and a
    /// day-old one would be a lie. A room is a PLACE you went to on purpose —
    /// "the newest thing from this source" is the answer you came for whether
    /// it arrived an hour ago or last month, and a quiet room's honest reading
    /// is the old item, not an empty head. `standsAlone` still applies in both:
    /// that one is structural, not a judgement about freshness.
    ///
    /// Three ways it declines, each because the card would say something
    /// untrue:
    ///
    /// - The newest thing is older than `ledeMaxAge` — IN THE ALL FEED ONLY. A
    ///   cover there is a claim about recency and nothing else. NOTE this is
    ///   asked when the derivation memo is rebuilt rather than per render, so a
    ///   session left open for a day keeps its cover until the next arrival —
    ///   deliberate: the cover and the fold that excludes it MUST be decided
    ///   together, and a per-render pick could name a thing that is still
    ///   inside `memo.groups`' fold, drawing it twice.
    /// - The feed is shorter than `ledeMinRows` — IN THE ALL FEED ONLY, counted
    ///   in THINGS here as a cheap upper bound, and re-asked in ROWS by the
    ///   caller once the fold has run (the real floor; see `bundledSections`).
    ///   A room with one thing in it covers that thing and shows nothing below,
    ///   which is what a room holding one thing looks like.
    /// - The newest thing `standsAlone` AND IS NOT A POST (`coverDeclines`,
    ///   prd §756) — a consent card and a token pulse are full anatomies sized
    ///   for their own reasons, and wrapping one in a cover is two
    ///   rhythm-breakers stacked (for `ApprovalCard` it would bury the verbs).
    ///   A POST yields its card to the cover, which is the one thing that
    ///   changed: it does not draw twice, because the covered row is lifted out
    ///   of its run. NOTE in the ALL FEED it declines rather than reaching PAST
    ///   it (a room reaches past, prd §763): a
    ///   stands-alone row keeps its own position at the top of the rows, so
    ///   covering something older would put a newer row underneath an older
    ///   card — the very thing this rewrite exists to make impossible.
    ///
    /// Scoped to the FIRST group: a cover is the top of the feed, and reaching
    /// into yesterday for one would be ranking, not position.
    ///
    /// Counted rather than flattened, deliberately: `flatMap` would allocate
    /// the whole thing list to read one group, on the screen with this app's
    /// worst measured perf history (`derivationKey`'s own
    /// 6.3-seconds-across-44-renders note).
    func ledeThingID(in days: [(String, [Thing])]) -> UUID? {
        // A room always covers its newest thing; the floors are the river's.
        let isRoom = source != "All"
        if !isRoom {
            let count = days.reduce(0) { $0 + $1.1.count }
            guard count >= Self.ledeMinRows else { return nil }
        }
        guard let head = days.first?.1 else { return nil }
        for thing in head {
            // `.isLive` before any stored read — a derived array read during the
            // same graph update a heal's delete can land in (the dead-Thing
            // rule). A dead row is skipped, not fatal: the next one may be fine.
            guard thing.isLive else { continue }
            // Newest-first, so the first one past the age bound means every
            // later one is too.
            guard isRoom || Self.isCoverFresh(thing.capturedAt, away: AppVisit.away)
            else { return nil }
            // **A ROOM COVERS ITS NEWEST COVERABLE THING (prd §763).** A newest
            // row that declines — a consent card, a token pulse, a takeaway —
            // used to leave the room with no lead at all, the one top in the
            // app that started with a row. It is skipped, and the next row of
            // the same day is the cover; the eyebrow says when it landed. The
            // All feed still DECLINES rather than reaching past it (the NOTE
            // above): §763 ruled for rooms, and the river's cover is a claim
            // about recency that an older card under a newer row would break.
            //
            // **THE NOTES ROOM NEVER DECLINES.** Its rows are anything you
            // pinned, so a room left holding only a pinned token pulse had no
            // cover, and the tiles rose to the top of the screen (§752's ban;
            // user: "the buttons stay put, and pinned item in the card", prd §979).
            if source != Pinboard.room, coverDeclines(thing) {
                guard isRoom else { return nil }
                continue
            }
            return thing.id
        }
        return nil
    }

    /// The COVER's veto, which is `standsAlone` minus the posts (prd §756,
    /// user: "we want the most recent post to be big, like it is on the all
    /// screen and that pattern should be on every screen").
    ///
    /// `standsAlone` answers a different question — does this row draw on a card
    /// of its own, i.e. does it break the day's run — and it must keep
    /// answering it for the run layout, so the cover asks its own. §732 made
    /// them the same answer ("option A": a post card already draws at card
    /// size, and a second anatomy for the same post is two rhythm-breakers
    /// stacked), and the user reversed it: a social room's newest thing is
    /// nearly always a post, so option A left the one room family whose newest
    /// thing IS the point without the cover every other room has.
    ///
    /// The "two anatomies" objection is answered by the cover itself rather
    /// than by declining: the covered row is LIFTED OUT of its run (§732), so
    /// the post draws once, and `FeedLedeCard` draws it as a post — the
    /// author's face, the author's name, the whole `postText` (§756).
    ///
    /// Everything else that stands alone still declines: a consent card (its
    /// verbs would be buried), a token pulse, a chat takeaway, and an approval
    /// that happens to have landed in a social room.
    private func coverDeclines(_ thing: Thing) -> Bool {
        guard standsAlone(thing) else { return false }
        guard SocialRoom.drawsPosts(thing.source) else { return true }
        return !SocialRoomSource.standsAlone(thing)
    }

    /// The away window lifted into its own section (prd §389) — "Since you
    /// left", then the day grain underneath it.
    ///
    /// The All feed has carried this boundary since 2026-07-09, as an inline
    /// capsule (`newSinceDivider`) sitting wherever it happened to fall inside
    /// a day. That says the same true thing in the weakest available position:
    /// a caption between two rows, competing with the day header above it.
    /// Promoting it to sectioning makes the FIRST thing the feed says be what
    /// you actually came to find out.
    ///
    /// Returns the groups unchanged (and `moment: false`) whenever the split
    /// would be degenerate — no away window, nothing new, or EVERYTHING new —
    /// which is `boundaryID`'s own rule: a divider at the very top or the very
    /// bottom marks nothing.
    ///
    /// Order carries the partition: groups are newest-first and so are the rows
    /// inside them, so the fresh side is a prefix and one pass splits it. A
    /// FOLD spanning the boundary lands whole on the fresh side, since a bundle
    /// dates itself by its newest member — the same place the inline divider
    /// has always put it, so nothing moves that wasn't already there.
    ///
    /// `days` names the rows that open each DAY inside the away section when
    /// it spans more than one (prd §879) — row id → that day's own label. The
    /// section used to be one flat run across however many days you were
    /// gone, so the same source's two daily folds sat back to back reading as
    /// one row twice, and nothing said where yesterday ended. Empty when the
    /// section is a single day, which is most opens: a day name under "Since
    /// you left" would only restate the obvious.
    func momentSplit(_ groups: [(String, [FeedRow])])
        -> (groups: [(String, [FeedRow])], moment: Bool, days: [String: String]) {
        guard let since = newSince,
              let first = groups.first?.1.first, first.date > since
        else { return (groups, false, [:]) }
        var fresh: [FeedRow] = []
        var rest: [(String, [FeedRow])] = []
        var days: [String: String] = [:]
        for (label, rows) in groups {
            let new = rows.prefix { $0.date > since }
            let old = rows.dropFirst(new.count)
            if let opener = new.first { days[opener.id] = label }
            fresh.append(contentsOf: new)
            guard !old.isEmpty else { continue }
            // A day the boundary cut through keeps its rows under a name that
            // says so. Only the CUT day is renamed — an untouched Today (the
            // boundary fell yesterday) is still just Today.
            let cut = !new.isEmpty && label == String(localized: "Today")
            rest.append((cut ? String(localized: "Earlier today") : label, Array(old)))
        }
        guard !fresh.isEmpty, !rest.isEmpty else { return (groups, false, [:]) }
        return ([(Self.momentLabel, fresh)] + rest, true, days.count > 1 ? days : [:])
    }

    /// The away section's name. A constant so the header's whisper gate and
    /// the seam can both ask for it by identity rather than re-localizing a
    /// literal and hoping the two strings match.
    static var momentLabel: String { String(localized: "Since you left") }

    /// One calendar for the per-thing day grouping — `Calendar.current` copies
    /// the user's calendar on every access, and `dayLabel` runs once per thing
    /// inside `dayGroups`, which the feed re-derives per paint.
    static let groupingCalendar = Calendar.current

    /// The next upcoming event — its ROW carries the emphasis (no hero).
    /// Events only: in the All shape other kinds share the list, and only
    /// an event's capture time means "starts at".
    func nextEventID(_ visible: [Thing]) -> UUID? {
        visible.filter { $0.isLive && $0.kind == .event && $0.capturedAt > .now }
            .min { $0.capturedAt < $1.capturedAt }?.id
    }

    func dayLabel(_ date: Date) -> String { Self.dayWord(date) }

    /// The day a thing landed, in the day divider's own words (prd §882). The
    /// article sheet's pink day word reads THIS, so the two pinks in the app
    /// always name a day the same way — never "4d", never a clock time.
    static func dayWord(_ date: Date) -> String {
        if Self.groupingCalendar.isDateInToday(date) { return String(localized: "Today") }
        if Self.groupingCalendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        // Only a list that reads forward (Day, Coming up) ever labels a day
        // ahead (every other feed drops future-dated rows in `dayGroups`), and
        // there "Tomorrow" is how the
        // next day is actually named — a dated weekday header for it read as
        // history sitting at the top of the list.
        if Self.groupingCalendar.isDateInTomorrow(date) { return String(localized: "Tomorrow") }
        return date.formatted(.dateTime.weekday(.wide).month().day())
    }
}
