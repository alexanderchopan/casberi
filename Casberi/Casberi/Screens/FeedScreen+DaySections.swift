import SwiftUI
import SwiftData

// The day sections: the bundled feed, the floor, dividers, lede/bundle/strip
// rows, grouped sections, the day section and the windowed rows (prd §264), split out of
// FeedScreen.swift (prd §718). Nothing here changed but the file it lives
// in and, where another file reads a member, its access level.
extension FeedScreen {
    #if DEBUG
    /// The All room's census — see the call site in `bundledSections` for why
    /// it is emitted from the render rather than mirrored in `ProbeHooks`.
    ///
    /// Takes no `Thing` by design (`hasCover` is a Bool, not the cover): this
    /// is called from inside a body evaluation, and the liveness rules above
    /// mean a census has no business holding a model to count it. Every input
    /// is already a value type by the time it arrives.
    ///
    /// De-duplicated on the composed text because this runs on every body pass:
    /// a census that repeats forty times a launch buries the one line that
    /// changed, and `verify.sh` greps for presence, not for the last write.
    private func logAllFeedCensus(groups: [(String, [FeedRow])],
                                  hasCover: Bool,
                                  appHeads: Int,
                                  categories: [String],
                                  imageOnly: Set<UUID>,
                                  wideArt: Set<UUID>,
                                  coarse: Set<String>,
                                  more: Bool,
                                  dayLine: DayBrief.Whisper?,
                                  tailDays: Int,
                                  tailDrawn: Int) -> Void {
        var single = 0, ambient = 0
        for (_, rows) in groups {
            for row in rows {
                if row.ambient { ambient += 1 }
                single += 1
            }
        }
        // Each line is one FEATURE of this room, named the way `verify.sh`'s
        // required list names it. Counts, never contents: a census that printed
        // titles would be a corpus dump, and the question here is only ever
        // "can this room draw this at all on the demo".
        let lines = [
            "days=\(groups.count) rows=\(single)",
            "cover=\(hasCover ? 1 : 0)",
            "single=\(single) appHeads=\(appHeads)",
            "imageOnly=\(imageOnly.count) wideArt=\(wideArt.count)",
            "coarse=\(coarse.count)",
            // Home's sections in the order they draw (prd §1152), so a
            // reordered dock can be read back off the log.
            "categories=\(categories.joined(separator: "/"))",
            "window=\(more ? "open" : "whole")",
            "dayLine=\(dayLine == nil ? 0 : 1)",
            "ambient=\(ambient)",
            // Both terms of `coarsenIfSparse`'s ratio, plus its verdict. The
            // gate needs `tailDays >= 6` AND `tailDrawn / tailDays < 1.5`, so
            // printing the average alone would hide which half is failing.
            "tailDays=\(tailDays) tailDrawn=\(tailDrawn)",
            "tailAvg=\(tailDays == 0 ? "n/a" : String(format: "%.2f", Double(tailDrawn) / Double(tailDays)))"
                + " coarsens=\(tailDays >= 6 && Double(tailDrawn) / Double(max(tailDays, 1)) < 1.5 ? 1 : 0)",
        ]
        let composed = lines.joined(separator: ";")
        guard Self.lastAllFeedCensus != composed else { return }
        Self.lastAllFeedCensus = composed
        for line in lines { NSLog("[Casberi] allFeed| %@", line) }
        // The terminator `verify.sh` waits on — without it the reader cannot
        // tell "the census finished" from "the census never ran", which for a
        // room that legitimately draws zero bundles is the whole question.
        NSLog("[Casberi] allFeed| census complete")
    }
    @MainActor private static var lastAllFeedCensus = ""
    #endif

    func bundledSections(_ visible: [Thing], nextEventID: UUID?,
                                 heroShown: Bool) -> some View {
        // Derive ONCE per render, then share — the day bundles, each day's true
        // total, and the new-since boundary. Read inside the row/header loops
        // (as `newBoundaryID` and `dayGroups.first(where:)` were) they rebuilt
        // the whole chain per row/section — the Feed freeze (perf pass
        // 2026-07-13).
        // Memoized (PERF 2026-07-31 — see `DerivationMemo`): recomputed only
        // when `visible` actually changed, not on all ~18 launch-window body
        // passes over the same set.
        // `heroShown` rides the key (§591b): the cover is chosen from it now,
        // and a stream going live flips it WITHOUT `visible` changing — so
        // without this the feed would keep drawing a cover under a hero until
        // the next write, which is the exact stacking the gate exists to stop.
        var key = derivationKey(visible)
        key = key &* 31 &+ (heroShown ? 1 : 0)
        // The cover's freshness reads the away window (`isCoverFresh`), which
        // moves at a foreground without `visible` moving. To the minute:
        // DEBUG's `-awayGap` slides the window with the clock, and a key that
        // changed every second would re-derive the feed on every render.
        if source == "All" {
            key = key &* 31 &+ Int((AppVisit.away?.lowerBound.timeIntervalSince1970 ?? 0) / 60)
            // Home's sections follow the dock's category order (prd §1152),
            // which Settings changes without `visible` changing.
            key = key &* 31 &+ CategoryOrder.current.hashValue
        }
        if memo.key != key {
            memo.key = key
            // HOME IS TODAY (prd §1136 item 7, user: "i don't mind we get rid
            // of yesterday b/c that is less important"): each app's newest
            // thing TODAY, and the categories hold the past.
            memo.days = perfAccum("dayGrouping") {
                source == "All"
                    ? dayGroups(visible.filter { $0.isLive && Self.groupingCalendar.isDateInToday($0.capturedAt) })
                    : recentDaysThenCoarseTail(visible)
            }
            // The cover is chosen over THINGS and before the fold (prd §389c),
            // which is the whole of the fix: chosen after it, the newest thing
            // could be inside a fold and the card would lead with something
            // older than a row beneath it.
            // **ONE COVER PER FEED (§591b, 2026-09-04, user: "we only have
            // one big thing on top").** §389's own doc justifies this card as
            // "the feed's first object… the rhythm it breaks is one it
            // precedes" — an argument that holds only while it IS first. A
            // live-stream hero, an anniversary, a topic map or any other head
            // card precedes it, and then the feed opens on two full-width
            // objects stacked with a day header wedged between them, which is
            // what the demo corpus shows every time (a Twitch hero over a
            // GeckoTerminal cover).
            //
            // The rule is not new here, only newly applied: `waitingSection`
            // and the shaped rooms' covers (prd §732) are gated on `heroShown`
            // for exactly this reason. This card was the
            // one lede that never got the gate, because it arrived later
            // (§389) than the rule did.
            //
            // Gated at the CHOICE rather than at the draw, which is
            // load-bearing: `memo.lede` is also what `bundle(excluding:)`
            // removes from the run, so suppressing only the drawing would take
            // the row off the screen entirely instead of returning it to the
            // list where it belongs.
            memo.lede = heroShown ? nil : ledeThingID(in: memo.days)
            // `nextEventID` rides in so the clock carve-out (prd §377) can
            // spare the next-up row. Both it and the live set can change
            // WITHOUT `visible` changing, and this memo keys on the snapshot's
            // revision (see `derivationKey`), so a newly-live row can stay
            // folded until the next write. That is a delay, never a
            // regression: before this carve-out existed those rows folded
            // unconditionally, so the stale case is exactly the old behaviour.
            let dayRows = perfAccum("bundle") {
                feedRows(memo.days, excluding: memo.lede)
            }
            // BY CATEGORY (prd §1152, user: "it looks smarter to be by
            // category and also helps them understand the app. and their
            // day"): Home's today stands in category sections, in the dock's
            // order, each app once under them. Today is the one day Home
            // holds (§1136 item 7), so nothing is lost by leaving time order.
            memo.groups = source == "All" ? Self.categorySections(dayRows) : dayRows
            // The post-fold row floor (§723) was Home's alone, and Home is
            // Today since prd §1136i — short by design, one row per app — so
            // it left the box empty most days. It is gone; no room ever had
            // it (a room's cover answers "the newest thing here").
            memo.imageOnly = perfAccum("imageOnlyIDs") { imageOnlyIDs(memo.days) }
            // Chosen over the DAY (one landmark a day, §254), before the
            // rows went into category sections.
            memo.wideArt = perfAccum("wideArtIDs") { wideArtIDs(dayRows) }
            memo.coarse = perfAccum("coarseLabels") { coarseLabels(in: memo.days) }
        }
        // Under app headers (prd §1103), inside each category (§1152). The
        // away split ("Since you left", §389, §879) and the new-since seam
        // went with time order: a section named by its category cannot also
        // be cut by a clock, and Home holds only today.
        let byApp = Self.groupedByApp(memo.groups)
        let heads = byApp.heads
        // NOT WINDOWED (prd §1154, user: "at the end of the day is the end
        // of the day"): Home is today, one row per app, so it draws whole and
        // ends where the day does. §264's window bounds a feed that reaches
        // back; this one does not.
        let window = (shown: byApp.groups, more: false, hidden: 0)
        let _ = { memo.windowHasMore = window.more }()
        // Home's box falls back to the newest thing when today chose no
        // cover (prd §1136i); that row stands in the box, so it leaves the
        // list under it, as a chosen cover always has (prd §389c).
        let fallbackCover = memo.lede == nil && source == "All" && !heroShown ? newestKept(visible) : nil
        let groups = fallbackCover.map { cover in
            window.shown.map { ($0.0, $0.1.filter { $0.id != cover.id.uuidString }) }.filter { !$0.1.isEmpty }
        } ?? window.shown
        // The cover is already OUT of `memo.groups` (prd §389c), so it is
        // resolved from the day it came from rather than searched for among the
        // rows. `.isLive` before the id read: `memo.days` is held across
        // renders, so a heal's delete can land under it — and the first day is
        // the only one that can hold the cover, so the scan is bounded by a day
        // rather than by the corpus.
        let ledeThing = memo.lede.flatMap { id in
            memo.days.first?.1.first { $0.isLive && $0.id == id }
        }
        let imageOnly = memo.imageOnly
        let wideArt = memo.wideArt
        let coarse = memo.coarse
        // The day header speaks (prd §385, 2026-08-14): the Today header
        // carries the day's own sentence — `DayBrief`'s whisper, the ONE
        // implementation of "what today was" (the capsule, the kept pill and
        // now this header all read it, so no two can disagree). Deliberately
        // NOT in the memo above: the whisper depends on the away window and
        // the wallet's day move, both of which change without the corpus
        // changing, and it is a filter-plus-scan over an already-bounded
        // array — cheap enough to stay time-fresh. Nil composes to no line
        // (honesty law: a day with nothing to say says nothing).
        //
        // BOUNDED TO TODAY (2026-09-21): Home holds today alone (§1136
        // item 7), so the line counts from the day's start, never from the
        // away window.
        let dayLine = DayBrief.whisper(
            things: visible,
            since: Calendar.current.startOfDay(for: .now))
        #if DEBUG
        // `-allFeedProbe YES` — the All room's own census (2026-08-17), and the
        // only demo-parity check that can see this room AT ALL.
        //
        // Every other demo coverage step reaches a SOURCE room: `verify.sh`'s
        // room-head step probes ten of them by name, its sheet-anatomy step
        // opens one record at a time, and `demo-selftest.py`'s check F
        // explicitly exempts this one (`SHAPE_NO_SOURCE = {"all"}`). But All is
        // the ONLY room that runs `bundledSections`, so the cover (§389c),
        // folding into strips and bundles (§377), the image-only and wide-art
        // treatments, the coarse tail and its subjects (§379) and the away
        // split (§389) exist NOWHERE ELSE — none of them has ever been checked
        // against the demo corpus, and All is the room the demo opens on. It is
        // the first screen a first-time opener sees, and it was the last one
        // with no parity check.
        //
        // Emitted from HERE rather than mirrored in `ProbeHooks`, for
        // `MainSurface`'s `categoryFold|` reason (2026-08-11): a probe that
        // recomputes an answer can only ever prove its own copy of the rule.
        // That is the documented weakness of `-roomInsightProbe`, whose own
        // header says the order "lives in `FeedScreen.shapedSections` — this
        // mirrors it, so a change there means a change here." This derives
        // nothing: every value below is one this render is about to draw with,
        // read at the one moment they all exist together.
        //
        // One NSLog per line (the `-todayProbe` truncation lesson).
        if UserDefaults.standard.bool(forKey: "allFeedProbe") {
            // THE TAIL'S OWN ARITHMETIC (2026-08-17). `coarse` measured 0 and
            // — unlike every other feature here — no amount of seeding can
            // change that on its own: `coarsenIfSparse` fires only when the
            // older-than-7-days section averages under 1.5 DRAWN rows per day,
            // and drawn is post-fold, not row count. So the question "how far
            // off is the demo" has a number, and guessing at it would mean
            // restructuring 56 days of dates on a theory. Reported as the two
            // terms of the ratio plus the gate's own verdict, because an
            // average alone cannot say whether the fix is fewer rows or more
            // folding — which are different changes to the demo.
            let tailCutoff = Self.groupingCalendar.date(
                byAdding: .day, value: -7,
                to: Self.groupingCalendar.startOfDay(for: .now))
            let tail = tailCutoff.map { cut in
                visible.filter { $0.isLive && $0.capturedAt < cut }
            } ?? []
            let tailDayGroups = dayGroups(tail)
            let tailDrawn = tailDayGroups.reduce(0) { $0 + appRowCount($1.1) }
            // `memo.groups`, NOT `groups` — measured 2026-08-17 on the demo and
            // the difference is the whole check: `groups` is `windowed(...)`'s
            // SHOWN slice (prd §264), so the first census over a 467-row demo
            // read `days=1 rows=3` while `wideArt` — taken from `memo`, i.e.
            // the full set — read 12 in the same breath. Two units in one
            // census, and the smaller one is the one `verify.sh` tests for
            // zero, so a healthy room would have reported missing features
            // forever. The question here is what the room CAN draw, which is a
            // property of the whole composed feed; whether the window is open
            // is reported separately, as its own fact.
            logAllFeedCensus(groups: memo.groups, hasCover: ledeThing != nil,
                             appHeads: heads.count,
                             categories: byApp.groups.map(\.0),
                             imageOnly: imageOnly, wideArt: wideArt,
                             coarse: coarse, more: window.more,
                             dayLine: dayLine,
                             tailDays: tailDayGroups.count, tailDrawn: tailDrawn)
        }
        #endif
        return Group {
        // THE COVER STANDS ABOVE THE FIRST DIVIDER (prd §906): the same
        // height as every room's lead, never under "Today". It is already
        // absent from every group's rows (prd §389c), so the run positions
        // below see the true row list with no filtering.
        // HOME'S BOX ALWAYS HOLDS THE NEWEST THING (prd §1136i, user: "this
        // needs to be populated w/ the newest thing"): today's, else — a day
        // with nothing in it yet — the newest thing kept, so the box is never
        // the day's empty state while there is anything to show.
        let homeCover = ledeThing ?? fallbackCover
        homeLead(homeCover)
        // You's tiles under the box, the slot every room's tiles stand in
        // (prd §1136 item 1).
        if source == "All" { youTilesSection(.feed) }
        // What stopped working, named, before anything that arrived (prd §1162).
        if source == "All" { reconnectSection }
        // "Nothing yet today" only when today truly holds nothing: a box
        // holding today's one thing IS today.
        if source == "All", groups.isEmpty,
           !(homeCover.map { $0.isLive && Self.groupingCalendar.isDateInToday($0.capturedAt) } ?? false) {
            nothingYetToday
        }
        ForEach(groups, id: \.0) { label, rows in
            // Bundles merge into the day card like any row-shaped thing —
            // only a single that stands alone (consent, token) breaks the run.
            let positions = cardRunPositions(
                count: rows.count,
                isBreaker: { i in
                    if case .single(let item) = rows[i].kind,
                       let thing = item.live { return standsAlone(thing) }
                    return false
                })
            Section {
                // UNPINNED (2026-08-29) — the day label is a ROW, not a `header:`.
                //
                // `.plain` pins section headers, and this one carries no backdrop of
                // its own — `.scrollContentBackground(.hidden)` takes away the
                // material the system would otherwise lend the pinned one — so the
                // label floated unreadably over whatever scrolled beneath it. Worst
                // over the cover (`ledeListRow`), the one row in this feed that
                // paints its own opaque surface: "Since you left" and its subline
                // landed straight on top of the card's own title, reported from a
                // device as a text overlay.
                //
                // A backdrop was the other way out and the ruling against it already
                // exists: the 2026-07-28 twin in `daySection` strips the system's
                // material precisely because it reads as an unwanted gray box on the
                // one header that happens to be pinned. With no backdrop allowed,
                // not pinning is what is left — and a day label that scrolls away
                // with the day it names is what a day label is for.
                //
                // Insets are ZEROED and the leading spelled here, so the column is a
                // value in this file rather than whatever the system hands a header
                // slot: it lands on `shapedListRow`'s own leading, i.e. the left edge
                // of the day's card run.
                // No count (prd §218, 2026-07-25). §213 retired volume as news
                // in the brief ("people do not care how many things landed"),
                // and the widget's own tally went the same day; this header was
                // the last surface still counting. "Monday, Jun 15 · 1" was the
                // clearest case against it — a number that can only ever say
                // "one", under a header already carrying the date.
                // THE CLAUSE RIDES THE NAME'S BASELINE when it fits (prd §767),
                // the shape a room's divider already had with its count.
                // THE DAY ALONE (prd §902 — user: "ok re Today heading no
                // numbers"). The divider carried §379's subject line, §385's
                // whisper sentence and §389's "Last here …"; a header that
                // reads a wallet figure or a count is a datum standing where
                // a name belongs. The whisper keeps its capsule and the
                // Since-you-left group keeps its name.
                // A CATEGORY, NOT A DAY (prd §1152): Home's sections are named
                // by what they hold, in the pink every title wears (§1156),
                // and each is a door to its
                // category's combined page, as the tray's row is (user: "will
                // the category be tappable?").
                categoryHeaderRow(label)
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    if case .single(let item) = row.kind {
                        // `live` before ANY read (corollary 3, build 176 —
                        // see `ThingRowKeying`): this closure is re-evaluated
                        // against the array it already holds when a heal's
                        // delete lands, and `imageOnly.contains(thing.id)`
                        // below is an argument, evaluated here, ahead of any
                        // guard inside the builder.
                        if let thing = item.live {
                            // The day's promoted anchor NEVER recedes (§378
                            // amendment, found by auditing §254 × §378): every
                            // promotable row is ambient by construction —
                            // `artRidesBesideIdentity` admits only social/RSS
                            // — so without this exemption the one row §254
                            // chose as the day's landmark was the one row
                            // guaranteed quiet. A dimmed landmark is a
                            // contradiction in terms, and it stays exempt
                            // below the read boundary too: landmarks are for
                            // wayfinding, which already-read territory needs
                            // MORE of, not less.
                            let anchor = wideArt.contains(thing.id)
                            shapedListRow(thing, index: i, nextEventID: nextEventID,
                                          position: positions[i],
                                          imageOnly: imageOnly.contains(thing.id),
                                          wideArt: anchor, grouped: true,
                                          app: heads[row.id].map { (source: $0, date: row.date) })
                                .opacity(!anchor && isQuiet(row) ? Self.quietRow : 1)
                                // The app's icon leads the row (prd §1157);
                                // the row's own lead stands empty (§1103a).
                                .environment(\.dsGroupedSource, row.source)
                        }
                    }
                }
                // The moment closed with a sentence here until prd §915
                // ("You're caught up — everything below, you've seen"). The
                // list just ends: the next day header already says the away
                // window is over, and Mail never narrates its own end.
            }
        }
        }
    }

    /// The newest live thing that has already happened — Home's cover on a
    /// day with nothing in it yet (prd §1136i). `.isLive` before the date
    /// read, the dead-Thing rule.
    func newestKept(_ visible: [Thing]) -> Thing? {
        let now = Date.now
        return visible.lazy.filter { $0.isLive && $0.capturedAt <= now }
            .max { $0.capturedAt < $1.capturedAt }
    }

    /// Home's box (prd §1136): today's cover, or — when today has none, or
    /// too few rows for one (`ledeMinRows`) — the day itself, so the tiles
    /// below always stand under a box and never at the top of the screen
    /// (prd §752, §862).
    @ViewBuilder
    func homeLead(_ ledeThing: Thing?) -> some View {
        if let ledeThing, ledeThing.isLive {
            Section { ledeListRow(ledeThing) }
        } else if source == "All" {
            Section {
                emptyLeadRow(headline: Text(Date.now.formatted(.dateTime.weekday(.wide))),
                             words: Text(Date.now.formatted(.dateTime.month(.wide).day())))
            }
        }
    }

    /// Today with nothing in it yet: the day divider over one quiet line, so
    /// Coming up below never reads as today.
    @ViewBuilder
    var nothingYetToday: some View {
        Section {
            FeedDayDivider(label: String(localized: "Today")) { EmptyView() }
                .textCase(nil)
                .padding(.leading, DSRoomChassis.rowInset)
                .padding(.vertical, DS.Space.s1)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            Text("Nothing yet today.")
                .dsText(.body17)
                .foregroundStyle(DS.textSecondary)
                .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset,
                                          bottom: DS.Space.s2, trailing: DSRoomChassis.rowInset))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    /// The floor (prd §218, 2026-07-25) — one quiet line at the very bottom of
    /// the All feed naming when the corpus starts.
    ///
    /// Delight that is a FACT, not a compliment: it's the real date of the
    /// oldest thing kept, it can't fire wrongly, and it can't fire twice. It
    /// also does a structural job — a scroll with no visible end teaches you
    /// never to reach one, and the newly coarsened tail finally has a bottom
    /// worth walking to. Deliberately NOT a count of anything (§213).
    ///
    /// Withheld on a corpus too young to have a history: "this is where it
    /// starts · today" is a fact nobody needs, and a floor under three rows
    /// reads as an empty-state apology.
    @ViewBuilder
    func corpusFloorSection(_ visible: [Thing]) -> some View {
        // `.isLive` before reading `capturedAt`: this walks a DERIVED array to
        // its oldest member, and a reconciliation or CloudKit delete can land
        // in the same graph update (CLAUDE.md, the dead-Thing rule).
        let live = visible.filter(\.isLive)
        // NOT WHILE `Show older` IS ON SCREEN (prd §866a). The window (§264)
        // draws 30 rows and a door to the rest, and this section renders
        // BELOW that door — so on the demo's 559 rows the feed said "This is
        // where it starts · Jul 23" one gap under a button holding 122 more
        // days, and drew the app's own mark over it to celebrate. The date is
        // read from `visible`, the WHOLE corpus, so it was never the oldest
        // thing you could see; it named one two months past the last row on
        // screen.
        //
        // The rule already existed one control away: `olderRow`'s own doc
        // says "while this is on screen the room is NOT whole, so
        // `caughtUpFooter` stands down", for the §83 fake-status reason.
        // "You're all caught up" and "this is where it starts" are the same
        // claim pointing at opposite ends of the feed, and only one of them
        // was gated. Read exactly as `caughtUpFooter` reads it — written
        // during `bundledSections`' body, which a `ViewBuilder` evaluates
        // before this.
        if live.count >= 8, !memo.windowHasMore,
           let oldest = live.last?.capturedAt,
           Date.now.timeIntervalSince(oldest) > 7 * 86_400 {
            Section {
                // The mark draws itself here (prd §866) — `CorpusFloor` holds
                // both the line and the gesture, so the gate above stays the
                // one place that decides whether a floor is honest at all.
                CorpusFloor(oldest: oldest)
                    .padding(.vertical, DS.Space.s6)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
    }

    /// The boundary line — words only, no drawn rule (the no-hairlines law).
    /// Everything above it arrived since you last left this screen.
    /// How far a receding row steps back (prd §378). One step, and only one:
    /// a row is quiet or it isn't, never quieter for two reasons at once
    /// (see `isQuiet`). Opacity rather than the `done` treatment's colour step
    /// because this must recede a row WHOLE — its picture and its brand mark
    /// included — and colour reaches only text; it is also one modifier with
    /// no layout change, so nothing shifts as the boundary moves.
    private static let quietRow = 0.68

    /// THE LIST'S SHARE OF A ROW'S AIR (prd §900). `DSFeedRow` pads itself by
    /// s2 above and below, and every feed row ALSO sat in an s2 list inset, so
    /// a one-line row was 25pt of words in 40pt of air: a 65pt pitch, nine
    /// rows a screen. The list now adds s1, so a row carries s3 of air on each
    /// side — one padding, a 53pt pitch, eleven rows. The day divider still
    /// carries the big gap, so days keep clustering (the 2026-07-13 reason the
    /// inset went back to s2 was that EVERY gap was the same size; that is
    /// still not the case).
    static let rowAir: CGFloat = DS.Space.s1

    /// The air above and below each of Home's rows (prd §1157): the gap
    /// between two apps, which the app's header row held until the icon
    /// moved into the row.
    static let groupAir: CGFloat = DS.Space.s3

    /// Whether a row steps back on a skim — ambient, or already read.
    ///
    /// The two reasons are OR'd into ONE step deliberately. They answer the
    /// same practical question ("can I skip this?") and multiplying them would
    /// double-dim an ambient row below the boundary into unreadability, which
    /// is how a legibility change becomes a legibility bug. Above the divider
    /// the tiers do the sorting; below it everything recedes together, which
    /// is honest — you have read it.
    ///
    /// Never applied under increased contrast: dimming is exactly what that
    /// setting exists to refuse, and the feed's structure must not be the one
    /// thing it costs you.
    ///
    /// Never applied to TODAY either (prd §773): nothing from today steps back,
    /// ambient or read. A bundle's date is its newest member, so a fold that
    /// reaches today stays lit.
    private func isQuiet(_ row: FeedRow) -> Bool {
        guard contrast != .increased else { return false }
        guard !Self.groupingCalendar.isDateInToday(row.date) else { return false }
        if row.ambient { return true }
        guard let newSince else { return false }
        return row.date <= newSince
    }

    var newSinceDivider: some View {
        // A FACT, so a stamp (prd §746) — it was a quiet capsule. Still not
        // tint-coloured prose, which reads as a tappable link; the air around
        // a centred word is the boundary.
        DSStamp(word: newSinceText)
            .settleIn()   // honours Reduce Motion; the seam it arrived beside is gone (§915)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Space.s1)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// The seam's words (2026-07-21): "what's new" differs by source, so the
    /// divider names it concretely instead of a bare "New since Friday". Most
    /// feeds get a count ("New since Friday · 4"); a Wallet feed — whose rows
    /// are SCANNED, not read — names the flow instead ("2 in, 1 out since
    /// Friday"), the question a wallet actually answers. Counts run over the
    /// frozen `visible` (things newer than the last-visit stamp); the divider
    /// renders once per boundary, so this reads `visible` a single time.
    private var newSinceText: String {
        guard let newSince else { return "" }
        let fresh = visible.filter { $0.capturedAt > newSince }
        if shape == .wallet {
            let inN = fresh.filter { $0.transferDirection == "received" }.count
            let outN = fresh.filter { $0.transferDirection == "sent" }.count
            if inN > 0 || outN > 0 {
                var parts: [String] = []
                if inN > 0 { parts.append(String(localized: "\(inN) in")) }
                if outN > 0 { parts.append(String(localized: "\(outN) out")) }
                return String(localized: "\(parts.joined(separator: ", ")) since \(sinceLabel)")
            }
        }
        return fresh.isEmpty
            ? String(localized: "New since \(sinceLabel)")
            : String(localized: "New since \(sinceLabel) · \(fresh.count)")
    }

    private var sinceLabel: String {
        guard let newSince else { return "" }
        if Calendar.current.isDateInToday(newSince) {
            return newSince.formatted(date: .omitted, time: .shortened)
        }
        if Calendar.current.isDateInYesterday(newSince) { return "yesterday" }
        return newSince.formatted(.dateTime.weekday(.wide))
    }

    /// The cover in the list (prd §389). ONE gesture, opening the same sheet
    /// the row would have — a cover is a bigger read of one thing, not a
    /// second kind of destination.
    ///
    /// It carries no `runBackground`: the card paints its own surface (it is
    /// the one object here that is a card rather than a row on a card), so the
    /// run underneath it starts clean at the row below. That is also why the
    /// Mac walk's selection is passed INTO the card rather than washed behind
    /// it — a `selectionWash` under an opaque card is a selection you cannot
    /// see.
    ///
    /// `.id` is load-bearing on Mac: `walkRowIDs` publishes this row's id from
    /// `memo.groups`, which still holds the promoted row, so without an id here
    /// ↓ onto the cover would scroll to nothing and highlight nothing — the
    /// exact dead-walk failure `walkRowIDs`' own doc warns about.
    ///
    /// `top`/`bottom` are the kind-tile rooms' (prd §815): there the cover is
    /// the well at the top of the row with the tiles `contentGap` under it —
    /// `DSRoomChassis.Head`'s geometry when it has tiles. The cover holds the
    /// box in every room since prd §904, so the tiles never move and no
    /// flag has to say so here.
    func ledeListRow(_ thing: Thing,
                             top: CGFloat = DS.Space.s2,
                             bottom: CGFloat = DSRoomChassis.leadGap) -> some View {
        Button {
            openThing(thing)
        } label: {
            FeedLedeCard(thing: thing,
                         selected: DS.isMac
                            && chrome.walkSelected == thing.id.uuidString,
                         // A quiet head's sentence, under the cover (prd §760).
                         note: heads?.quietHead?.quietLine)
                .modifier(rowEntrance(0))
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        // The row's long press, on the cover too: the cover IS the newest
        // row, lifted out of the list, so without it the newest note had no
        // Delete and no Pin.
        .contextMenu {
            RowVerbMenu(thing: thing, room: source, run: { run($0, on: $1) }, onDelete: askDeleteNote,
                        onFile: fileThing, onNewFolder: { folderPrompt = .make(filing: $0) })
        }
        .dsHover()
        .macHoverLift()
        .id(thing.id.uuidString)
        .listRowBackground(Color.clear)
        // A wider gap below than above: the cover is its own object, and the
        // day's run begins under it rather than continuing from it. The
        // chassis's own numbers (prd §763), which every other lead now wears.
        // Since §766 the card draws its own `s3` inside a well, so the row
        // stands at `inset`, where `dsRoomHeadPlacement` puts every head.
        .listRowInsets(.init(top: top,
                             leading: DSRoomChassis.inset,
                             bottom: bottom,
                             trailing: DSRoomChassis.inset))
        .listRowSeparator(.hidden)
    }

    /// An app's header in the All feed (prd §1103, §1103a): a LABEL over its
    /// item, never a second item. §1103 drew it at the row's own size and
    /// ink, one weight up, and the column still blended (user: "the source
    /// title is same color or weght ir whatever as the item in it"). So it is
    /// the badge mark and the name at `label12` in the secondary ink — the
    /// Notification Center order: app, then the thing, louder. The row under
    /// it draws no lead and starts flush with the mark. The tap lands in the
    /// app's room, as a fold's did (§377).
    /// A category's name over its section of Home (prd §1152), a door to
    /// its combined page — the landing the tray's category row makes,
    /// dropping an app picked there earlier so the page opens on every app.
    /// You (a note of yours) is no category and has no page, so it is a
    /// label only.
    @ViewBuilder
    private func categoryHeaderRow(_ category: String) -> some View {
        // Every section's name is pink, as every title is (prd §1156).
        let divider = FeedDayDivider(label: category) { EmptyView() }
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        Group {
            if CategoryFold.isCategory(category) {
                Button { openCategory(category) } label: { divider }
                    .buttonStyle(RowPress())
                    .accessibilityAddTraits(.isHeader)
            } else {
                divider
            }
        }
        .padding(.leading, DSRoomChassis.rowInset)
        .padding(.top, DS.Space.s3)
        .padding(.bottom, DS.Space.s1)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func openCategory(_ category: String) {
        DSHaptic.selection()
        if category == CategoryFold.walletRoom {
            chrome.walletScope = nil
        } else {
            chrome.mergedScope[category] = nil
        }
        chrome.lastChipTouch = Date.timeIntervalSinceReferenceDate
        chrome.sourceRequest = category
    }

    /// Home's lead (prd §1157): the app's icon at `DS.Mark.notice`, its own
    /// door to the app's room (§1103's header tap). A row with no app beside
    /// it keeps the column empty, so every row's words share one left edge.
    @ViewBuilder
    func appLead(_ source: String?) -> some View {
        if let source {
            Button {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) { filter.source = source }
            } label: {
                BridgeIcon(name: source, size: DS.Mark.notice)
                    // The icon is 38pt; the door is a finger tall.
                    .frame(minHeight: DS.Hit.min, alignment: .top)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressSpring())
            .accessibilityLabel(Text(verbatim: BridgeCatalog.seatName(forSource: source)))
        } else {
            Color.clear.frame(width: DS.Mark.notice, height: DS.Mark.notice)
        }
    }

    /// The row's top line on Home (prd §1152, §1157): the app's name, and
    /// when its thing landed at the trailing edge, as a notification
    /// carries its time.
    func appLine(_ source: String, at date: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Text(BridgeCatalog.seatName(forSource: source))
                .dsText(.label12)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(date.formatted(date: .omitted, time: .shortened))
                .dsText(.label12)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    func groupedSections(_ groups: [(String, [Thing])],
                                 nextEventID: UUID?,
                                 boundary: UUID? = nil,
                                 replies: [String: [Thing]] = [:],
                                 // Do these labels name a TIME? (prd §740.)
                                 // Every chronological room says yes by
                                 // default; the handful grouped by something
                                 // else — repositories, watched wallets, a
                                 // due-date bucket — pass false and keep the
                                 // primary ramp. Spelled at the call site
                                 // rather than sniffed from the label: the
                                 // labels are localized, and a new room's
                                 // author should have to answer this.
                                 dated: Bool = true,
                                 cover: UUID? = nil,
                                 // Which of a day's things TILE under its
                                 // header (prd §910) — the six picture rooms
                                 // pass their grid test, everything else none.
                                 isTile: ((Thing) -> Bool)? = nil,
                                 tileShape: PhotoCell.Shape = .square,
                                 // Draw the room's scope control under the
                                 // cover (prd §959) — the day-grouped rooms
                                 // that pick a person or a source.
                                 scopeControl: Bool = false) -> some View {
        // Computed once for the whole feed rather than per section: every
        // shaped room routes its groups through here, so the folded tail's
        // lighter header (prd §254) reaches all of them from one place.
        let coarse = coarseLabels(in: groups)
        // Windowed (prd §264) — `coarse` and `boundary` are computed against
        // the FULL set above, so a label or a divider does not change meaning
        // when the window opens.
        let window = windowed(groups)
        let _ = { memo.windowHasMore = window.more }()
        // THE COVER STANDS ABOVE THE FIRST DAY, in every room (prd §906).
        // It used to draw INSIDE the first day's section, under that day's
        // header, while the photo rooms, the kind-tile rooms and every head
        // drew their lead above it — so the same card started at two heights
        // depending on the room. §763's rule was always lead first, then the
        // days; this is where the day-grouped rooms finally keep it. The day
        // section still takes `cover` so the covered thing is lifted OUT of
        // its run and draws once.
        let coverThing: Thing? = cover.flatMap { id in
            groups.flatMap { $0.1 }.first(where: { (thing: Thing) -> Bool in thing.isLive && thing.id == id })
        }
        if let coverThing { Section { ledeListRow(coverThing) } }
        if scopeControl {
            // A pick that emptied the room holds the lead with the room's own
            // empty state (§862), so the control never rises to the top of
            // the screen (§752) and is still there to undo the pick.
            if coverThing == nil && groups.isEmpty && roomScopePicked {
                Section {
                    emptyLeadRow(headline: DSProse.text("Nothing here yet."),
                                 words: Text("Nothing here yet."))
                }
            }
            roomScopeSection
        }
        // The room's own share door stands under whatever leads — the cover
        // here, or the tiles a kind-tiled room drew before calling this —
        // and above the first day, in every room that offers one.
        roomShareDoor(groups.flatMap { $0.1 })
        ForEach(window.shown, id: \.0) { label, rows in
            daySection(label, rows, nextEventID: nextEventID, boundary: boundary,
                       replies: replies, coarse: coarse.contains(label),
                       dated: dated, cover: cover, isTile: isTile, tileShape: tileShape)
        }
        if window.more { olderRow(hidden: window.hidden) }
    }

    /// A day group as a native section: the day's rows share ONE sheet card
    /// (2026-07-21 — see RunPosition), rhythm-breakers stand free between
    /// runs, native scroll — no gesture fights.
    @ViewBuilder
    func daySection(_ label: String, _ rows: [Thing],
                            nextEventID: UUID?,
                            boundary: UUID? = nil,
                            replies: [String: [Thing]] = [:],
                            // A week/month group from the folded tail rather
                            // than a day — its header weighs one step less
                            // (prd §254). Defaults false for the one caller
                            // that isn't a day at all (the kind-filtered All
                            // room, whose single header is the filter's name).
                            coarse: Bool = false,
                            // Does this label name a TIME? (prd §740.) True
                            // takes the brand hue; the named-group callers
                            // below ("Doing", "Waiting on you", a pinned room,
                            // a kind filter) pass false and stay on the
                            // primary ramp.
                            dated: Bool = true,
                            // A shaped room's cover (prd §732): drawn as
                            // `FeedLedeCard` under the header of the group that
                            // holds it, and lifted out of that group's run.
                            cover: UUID? = nil,
                            // THE DAY'S PICTURES TILE UNDER ITS HEADER, and its
                            // other things row beneath them (prd §910). Kind
                            // used to stand above time in the picture rooms:
                            // every tile in the room first, then the rows by
                            // day, so a PDF saved this morning sat under
                            // Monday's photographs, and the grid needed its
                            // own day pills because it stood outside the days.
                            isTile: ((Thing) -> Bool)? = nil,
                            tileShape: PhotoCell.Shape = .square,
                            // The Notes room's one plain list (prd §969): no
                            // header at all — its rows are yours, ordered by
                            // when you acted, and a day over them would say
                            // the corpus's clock instead.
                            headed: Bool = true) -> some View {
        // LIVE ONLY, before anything reads a stored property (build 150 crash,
        // 2026-07-25 — pull-to-refresh, symbolicated to `countLabel` inside
        // this section's own header). `rows` is a DERIVED array (the day
        // grouping) holding models by reference, and everything below touches
        // persisted properties on them: `standsAlone`/`.id` for the run
        // positions and the row bodies. A refresh runs the bridge heals,
        // each of which deletes upstream-gone rows on the MAIN context — so a
        // delete lands inside the same graph update that re-evaluates this
        // section, and the first read of a tombstoned model traps in SwiftData.
        //
        // The keying rule (`ThingRowKeying`) fixed the ForEach's own identity
        // diffing; it can't help a header that reads the array directly. This
        // is the same rule's other half: guard a HELD reference with `isLive`
        // before reading through it. Filtering here covers the positions, the
        // rows, and the header at once — a row that just died drops out of the
        // day it was in, which is what the next `@Query` emission says anyway.
        let rows = rows.filter(\.isLive)
        // The day's tiles and the rest (prd §910).
        let (dayTiles, dayRows) = isTile.map { Self.splitTiles(rows, by: $0) } ?? ([], rows)
        let coverThing = cover.flatMap { id in rows.first { $0.id == id } }
        let tiles = coverThing == nil ? dayTiles : dayTiles.filter { $0.id != cover }
        let run = coverThing == nil ? dayRows : dayRows.filter { $0.id != cover }
        let positions = cardRunPositions(count: run.count,
                                         isBreaker: { standsAlone(run[$0]) },
                                         isBoundary: { run[$0].id == boundary })
        // Asked of what the section DRAWS, not of what it was handed: the
        // cover is lifted out above, so a day holding only the cover has a
        // header and nothing under it (2026-09-26).
        if !tiles.isEmpty || !run.isEmpty {
            Section {
                // UNPINNED (2026-08-29) — a ROW, not a `header:`. The twin in
                // `bundledSections` carries the full reasoning; the short of it is
                // that `.plain` pins headers, the backdrop that would make a pinned
                // one legible was deliberately stripped below on 2026-07-28, and a
                // header with neither pins ON TOP of the rows scrolling under it.
                // The day's own gap and column are spelled here, so nothing depends
                // on what the system hands a header slot.
                // The day alone — its count is deleted (prd §914, user:
                // "people don't want to know").
                if headed {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                        Text(label)
                            .dsText(.heading20)
                            // The folded tail weighs less than today (prd §254) —
                            // see the twin in `bundledSections` for the reasoning.
                            .fontWeight(coarse ? .medium : .semibold)
                            // The day wears the brand hue (prd §740); a group
                            // named by something other than time keeps the
                            // primary ramp.
                            .foregroundStyle(dated ? DS.brandInk : DS.textPrimary)
                    }
                    .textCase(nil)
                    .padding(.leading, DSRoomChassis.rowInset)
                    // Days read as clusters: the gap ABOVE a day header is the
                    // feed's biggest (2026-07-13), and since 2026-07-21 the day's
                    // rows also share one card — the header's s6 plus the card's own
                    // silhouette say "new day" without drawing a line.
                    .padding(.top, DS.Space.s6)
                    .padding(.bottom, DS.Space.s1)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                // The day's pictures, first (prd §910): a grid cannot interleave
                // with rows by the minute, and the day is the grain the header
                // promises.
                if !tiles.isEmpty { tileRows(tiles, shape: tileShape) }
                // Rows dispatch by shape (shaped feeds); the swipe stays triage —
                // reads only, writes live in the sheet (ruling), Copy sheet-only.
                // The cover is drawn by `groupedSections`, above this header
                // (prd §906); here it is only lifted out of the run.
                ForEach(Array(keyed(run).enumerated()), id: \.element.id) { i, item in
                    // The `rows.filter(\.isLive)` above runs when this view
                    // VALUE is made; this runs again each time the closure is
                    // re-evaluated, which is when the delete actually lands
                    // (corollary 3, build 176 — see `ThingRowKeying`).
                    if let thing = item.live {
                        if thing.id == boundary { newSinceDivider }
                        shapedListRow(thing, index: i, nextEventID: nextEventID,
                                      position: positions[i], replies: replies)
                    }
                }
            }
        }
    }

    /// **THE LIST JUST ENDS (prd §915).** The feed closed on a sentence from
    /// 2026-07-13 to §914 — "That's everything from npm so far", "That's
    /// everything you've pinned", a thin room's mark-and-line — and none of
    /// it said anything the empty air under the last row did not. Mail never
    /// narrates its own end. One line survives, because it is a DOOR and an
    /// honesty fact rather than a closing: at the fetch bound this is NOT the
    /// end of the corpus, and saying nothing there would be the §83 fake
    /// status in the one place a person is deciding whether anything older
    /// exists. The room stops fetching at `allRoomFetchLimit`; the copy says
    /// which stop this is, and the door it offers is real — a source room
    /// carries its own predicated query and still no row bound, so opening
    /// one genuinely reaches further back than the All room can.
    ///
    /// The caller's gates stand (§264, §482, §486): the line is still a claim
    /// about the list on screen, so a scope with no rows draws nothing.
    /// Takes the render's `visible` (the Feed-freeze rule) for that reason.
    @ViewBuilder
    func caughtUpFooter(_ rows: [Thing]) -> some View {
        if reachedFetchCeiling {
            Text("Showing your most recent things — open a source to go further back")
                .dsText(.subhead12)
                .foregroundStyle(DS.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, DS.Space.s6)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    // MARK: - Windowed rows (prd §264)

    /// How many ROWS a room draws before it stops. Whole day groups only, so
    /// the real count overshoots to the end of whichever group crosses this.
    ///
    /// A room built EVERY row it held on every render, and a device profile put
    /// `feedList` at 46% of all main-thread samples with 36 hangs of up to
    /// 850ms in the first ten seconds. That cost scaled with the room, not with
    /// what anyone could see. The derivations above are unchanged and still run
    /// over the WHOLE set — the grouping, the bundling, the themes treemap and
    /// every count stay corpus-true — because the expensive thing was never the
    /// deriving (it is memoized, once per real change), it was handing a
    /// thousand rows to a `ForEach` whose content closure runs for each one.
    ///
    /// Distinct from the off-screen page trim rejected in §263: that deferred a
    /// page's rows to the body evaluation that made it ACTIVE, which moved the
    /// cost onto the moment of arrival. This never builds the rest at all until
    /// the person scrolls toward it, and then it builds a few groups.
    /// About two screenfuls. The screen holds 8-12 rows, so this is a small
    /// amount of pre-built content ahead of the viewport rather than the ten
    /// screens the first cut budgeted (user, 2026-08-01: "why not just show the
    /// last day and current day only on load" — right that it was too
    /// generous; see `windowed` for why the unit is rows and not days).
    private static let windowRowTarget = 30

    /// How many rows a room's `@Query` will materialise, ever. See the long
    /// note in `init` for the measurement that produced it: unbounded, that
    /// query was 26.6% of the main thread on a 6,000-row corpus, because
    /// SwiftData instantiates every row as a real model object on the main
    /// actor. ~40 "Show older" taps of headroom, and constant thereafter no
    /// matter how large the corpus grows.
    ///
    /// The pinned room still takes neither bound — see `init` for why that one
    /// room must never have a ceiling. Source rooms took the light columns on
    /// 2026-08-14, this bound on 2026-09-04; see `sourceRoomFetchLimit`.
    static let allRoomFetchLimit = 1200

    /// The same bound for a SOURCE room (prd §600, 2026-09-04) — and it is
    /// half a fix, never a whole one. The other half is `fullRoomRows`.
    ///
    /// A source room is the one place a single query can be enormous: §307
    /// raised the X caps to 10,000 posts and 5,000 likes, and §309 did the same
    /// for Instagram, TikTok and Snapchat, so a bulk import lands thousands of
    /// rows under ONE source in an afternoon. Since 2026-08-31 that query also
    /// carries the heavy inline text again (the iOS 18.6 `propertiesToFetch`
    /// defect — see `init`), so an unbounded read is the single largest
    /// main-actor cost this screen has.
    ///
    /// LOWER than the All room's 1,200 on purpose, and the arithmetic is the
    /// reason rather than taste: the window opens `windowRowTarget` (30) rows
    /// per "Show older" tap, so 600 is twenty taps — far past anyone's
    /// scrolling in one visit — while a source room's rows are individually
    /// heavier than All's, because this branch cannot use `lightColumns`. The
    /// All room's 1,200 is the light-column read and stays where it is.
    ///
    /// The ceiling is reachable, so the footer says so (`reachedFetchCeiling`).
    static let sourceRoomFetchLimit = 600

    /// True when the window has opened as far as the FETCH will go — the
    /// person has reached the bound above, not the end of their corpus.
    ///
    /// This exists so the bound can never masquerade as the end (§83). The
    /// caught-up footer is a claim about the CORPUS ("nothing older exists"),
    /// and at this edge that claim is false: there is more, we simply stopped
    /// fetching it. `windowed` reports `more: false` here for exactly the same
    /// reason it does when a room really is exhausted, so nothing downstream
    /// can tell the two apart — which is why this is asked separately.
    ///
    /// SOURCE ROOMS TOO SINCE 2026-09-04 (prd §600) — they gained a bound, so
    /// they gained the sentence that keeps the bound from lying. Leaving this
    /// All-room-only while bounding those rooms is exactly the §83 failure the
    /// property exists to prevent, and it would have been a silent one: the
    /// footer would have read "That's everything from X" over a room holding
    /// ten thousand posts.
    ///
    /// The pinned room is unbounded by design and correctly never matches.
    private var reachedFetchCeiling: Bool {
        guard filter.tag == "All" else { return false }
        if source == "All" { return windowRowBudget >= Self.allRoomFetchLimit }
        guard !Pinboard.isPinnedRoom(source) else { return false }
        return windowRowBudget >= Self.sourceRoomFetchLimit
    }

    /// `-feedWindowSteps <n>` (DEBUG, 2026-09-22) opens the window n steps on
    /// arrival, so a probe can see rows past the first screenful — a section
    /// longer than the budget (the away section after days gone) otherwise
    /// needs a tap on "Show older" that a headless run cannot make.
    static var initialWindowSteps: Int {
        #if DEBUG
        return max(0, UserDefaults.standard.integer(forKey: "feedWindowSteps"))
        #else
        return 0
        #endif
    }

    /// One more screenful per step, deliberately linear (user ruling,
    /// 2026-08-01: "most people won't be scrolling back to previous history").
    /// Geometric growth was offered and declined — it only helps the person
    /// walking a long room to its beginning, which is the rare case, and the
    /// cost of getting the common case right is what this whole change is for.
    private var windowRowBudget: Int { Self.windowRowTarget * (windowSteps + 1) }

    /// Whole groups covering the budget, plus whether any were held back.
    ///
    /// ROWS are the unit, not days, and that is the whole point: a day is not a
    /// bound on work. An import (Instagram, Snapchat, ChatGPT) lands its entire
    /// history at once and those cluster onto dates, so ONE day in that room
    /// can be thousands of rows — "draw today and yesterday" would leave the
    /// cost completely unbounded. A row budget also adapts by itself: a busy
    /// day fills the screen, a quiet week shows several days.
    ///
    /// Whole days wherever possible, because a half-drawn day would otherwise
    /// need its header to lie about what sits under it. The exception is a day
    /// bigger than one step (`windowRowTarget`) — the import case above —
    /// which is truncated to what the budget holds rather than allowed to
    /// unbound the room, or to hold back every tap until the budget covers
    /// it. Its header keeps stating the day's REAL total (`daySection` is
    /// handed the full day for counting), so the count stays true and "Show
    /// older" explains the gap.
    ///
    /// `hidden` is how many THINGS the door holds back (prd §900), so it can
    /// say so: `weight` counts a fold as its members, and everything else as
    /// one. It is the total minus what is drawn, over the same groups, so it
    /// cannot disagree with `more`.
    private func windowed<T>(_ groups: [(String, [T])],
                             weight: (T) -> Int = { _ in 1 })
        -> (shown: [(String, [T])], more: Bool, hidden: Int) {
        var shown: [(String, [T])] = []
        var rows = 0
        func result(_ more: Bool) -> (shown: [(String, [T])], more: Bool, hidden: Int) {
            guard more else { return (shown, false, 0) }
            let all = groups.reduce(0) { $0 + $1.1.reduce(0) { $0 + weight($1) } }
            let drawn = shown.reduce(0) { $0 + $1.1.reduce(0) { $0 + weight($1) } }
            return (shown, true, max(0, all - drawn))
        }
        for group in groups {
            let remaining = windowRowBudget - rows
            if group.1.count > remaining {
                // A day bigger than one step: take what the budget holds of it.
                // Held back whole, a tap that grows the budget by one step
                // could not reach it, so "Show older" did nothing on tap after
                // tap until the budget covered the whole day (beta feedback,
                // 2026-09-24: "the older button doesn't do nun" — a small day
                // over an import's day). One day bigger than the whole budget
                // is the same case with nothing above it. A day that fits in
                // one step waits whole for the next tap.
                if group.1.count > Self.windowRowTarget, remaining > 0 {
                    shown.append((group.0, Array(group.1.prefix(remaining))))
                }
                return result(true)
            }
            shown.append(group)
            rows += group.1.count
            if rows >= windowRowBudget { break }
        }
        return result(shown.count < groups.count)
    }

    /// The row that opens the next step — a TAP, deliberately, not an
    /// appearance trigger.
    ///
    /// Growing on `.onAppear` was the first cut and is a runaway: `List`
    /// realizes rows ahead of the viewport, so the row appears immediately,
    /// grows the window, re-renders, appears again. Measured — it drove
    /// `feedList` from 12% of main-thread samples to 60%, i.e. it cost far more
    /// than the windowing saved, while looking like seamless infinite scroll.
    /// A tap fires exactly once per request and cannot feed back into its own
    /// trigger.
    ///
    /// While this is on screen the room is NOT whole, so `caughtUpFooter`
    /// stands down; `memo.windowHasMore` carries that (see `feedList`).
    ///
    /// **A ROW IN THE COLUMN, and it says what it holds (prd §900).** It was
    /// the only centred element on a left-aligned screen, a 12pt word with
    /// nothing saying how much was behind it. It is the rows' own anatomy now
    /// — a 26pt lead, the verb where a title stands, the count where a time
    /// stands — in the tint, because it is the one row on the screen whose
    /// whole job is a tap.
    private func olderRow(hidden: Int) -> some View {
        Button {
            DSHaptic.tap()
            withAnimation(DS.Motion.standard) { windowSteps += 1 }
        } label: {
            DSPushRowLabel(title: Text("Show older"),
                           fact: hidden > 0 ? Text("\(hidden) more") : nil,
                           tint: DS.tint,
                           opens: false) {
                DSGlyphLead(glyph: "arrow.down", tint: DS.tint)
            }
            .padding(.vertical, DS.Space.s2)
            .frame(minHeight: DS.Hit.min)
        }
        .buttonStyle(RowPress())
        .listRowBackground(Color.clear)
        .listRowInsets(.init(top: Self.rowAir,
                             leading: DSRoomChassis.rowInset,
                             bottom: Self.rowAir,
                             trailing: DSRoomChassis.rowInset))
        .listRowSeparator(.hidden)
    }
}
