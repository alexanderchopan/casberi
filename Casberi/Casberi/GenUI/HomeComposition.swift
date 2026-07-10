import Foundation
import SwiftData

/// Authors the Home composition document from the live corpus. In M2's server
/// half the model authors this per moment through /compose; until then this
/// local author produces the same document shape from the same facts, and the
/// engine streams it identically — swapping the source later changes no visuals.
///
/// Voice constraints (Home spec): themes and content, no obligations. Tile
/// sublines read content, not status. Hero: one synthesis statement, facts
/// only, priority project movement > pending decision > imminent event >
/// bridge arrival. Evening (hour ≥ 15) leads with the TagMap.
enum HomeComposition {

    static func compose(things: [Thing],
                        walletHoldings: [WalletIngest.HoldingsGroup] = [],
                        hour: Int = Calendar.current.component(.hour, from: .now),
                        weekday: Int = Calendar.current.component(.weekday, from: .now)) -> [String] {
        let projects = projectClusters(things: things)
        // Saturday/Sunday reads as a recap — the week, banked.
        if weekday == 1 || weekday == 7 {
            return weekend(things: things, projects: projects, walletHoldings: walletHoldings)
        }
        return hour < 15
            ? morning(things: things, projects: projects, walletHoldings: walletHoldings)
            : evening(things: things, projects: projects, walletHoldings: walletHoldings)
    }

    /// True when nothing has landed today — the composition acknowledges the
    /// quiet instead of pretending motion (voice: facts, no obligations).
    private static func isQuietDay(_ things: [Thing]) -> Bool {
        !things.isEmpty && !things.contains { Calendar.current.isDateInToday($0.capturedAt) }
    }

    // MARK: - Documents

    private static func morning(things: [Thing], projects: [Cluster], walletHoldings: [WalletIngest.HoldingsGroup] = []) -> [String] {
        var doc: [String] = []
        var rootRefs: [String] = []

        // The COVER (H7) replaces the sheet-card hero: the day's newest image
        // thing when one landed (this week as the fallback image), else the
        // quiet 140pt cover carrying the same Hero content and priority rules.
        // The doc only names facts; the renderer owns image, bleed, fallbacks.
        doc.append(cover(things: things))
        rootRefs.append("cover")

        // A quiet day says so with the berry, not an empty lineup (§5).
        if isQuietDay(things) {
            doc.append("quiet = Quiet(\(q("Quiet so far today.")))")
            rootRefs.append("quiet")
        }

        // Pinned — things the person chose to keep in view, ahead of the map
        // (ruling 2026-07-09): a deliberate choice outranks an automatic
        // clustering, and it shouldn't cost a scroll to reach. User-chosen,
        // so it passes the no-obligations rule: Casberi never picked these.
        appendPinned(things, to: &doc, rootRefs: &rootRefs)
        appendWalletHoldings(walletHoldings, to: &doc, rootRefs: &rootRefs)

        // Where the map belongs even when it didn't compose yet — the starter
        // preview slots in here, not at the tail.
        let mapSlot = rootRefs.count
        // Projects — an interactive treemap: magnitude fill, tap opens the
        // project (amendment: the tile bento died; the map is the projects).
        if !projects.isEmpty {
            let items = projects.prefix(6).map { "\($0.name) \($0.things.count)" }
            doc.append("map = TagMap(\(q("What's going on")), null, [\(items.joined(separator: ", "))])")
            rootRefs.append("map")
        } else {
            let sources = sourceClusters(things: things)
            if !sources.isEmpty {
                let items = sources.prefix(6).map { "\($0.name) \($0.things.count)" }
                doc.append("map = TagMap(\(q("What's going on")), \(q("By app — tags take over as they form")), [\(items.joined(separator: ", "))], \(q("source")))")
                rootRefs.append("map")
            }
        }
        // Threads resurface what's slipping away — links older than 3 days
        // (yesterday's links are Feed's top rows; mirroring them is filler).
        // Widget child-drop rule (gap §9.2): no rows → no widget line at all.
        let links = resurfaceable(things).prefix(2)
        if !links.isEmpty {
            let ids = links.indices.map { "t\($0)" }
            doc.append("themes = Widget(\(q("Threads across apps")), null, [\(ids.joined(separator: ", "))])")
            for (i, t) in links.enumerated() { doc.append(row(id: "t\(i)", t)) }
            rootRefs.append("themes")
        }

        appendStarterPreviews(things: things,
                              hasMap: rootRefs.contains("map"),
                              mapSlot: mapSlot,
                              hasThreads: !links.isEmpty, to: &doc, rootRefs: &rootRefs)

        doc.insert("root = Stack([\(rootRefs.joined(separator: ", "))])", at: 0)
        return doc
    }

    private static func evening(things: [Thing], projects: [Cluster], walletHoldings: [WalletIngest.HoldingsGroup] = []) -> [String] {
        var doc: [String] = []
        var rootRefs: [String] = []

        // The cover leads (H7); evening keeps its own lineup below it.
        doc.append(cover(things: things))
        rootRefs.append("cover")

        if isQuietDay(things) {
            doc.append("quiet = Quiet(\(q("Quiet so far today.")))")
            rootRefs.append("quiet")
        }

        // Pinned rides evening too — same rule as morning, ahead of the map.
        appendPinned(things, to: &doc, rootRefs: &rootRefs)
        appendWalletHoldings(walletHoldings, to: &doc, rootRefs: &rootRefs)

        let mapSlot = rootRefs.count
        if !projects.isEmpty {
            let items = projects.prefix(6).map { "\($0.name) \($0.things.count)" }
            doc.append("map = TagMap(\(q("What's going on")), null, [\(items.joined(separator: ", "))])")
            rootRefs.append("map")
        } else {
            let sources = sourceClusters(things: things)
            if !sources.isEmpty {
                let items = sources.prefix(6).map { "\($0.name) \($0.things.count)" }
                doc.append("map = TagMap(\(q("What's going on")), \(q("By app — tags take over as they form")), [\(items.joined(separator: ", "))], \(q("source")))")
                rootRefs.append("map")
            }
        }
        // Threads — resurfacing, not mirroring (see morning).
        let links = resurfaceable(things).prefix(2)
        if !links.isEmpty {
            let ids = links.indices.map { "t\($0)" }
            doc.append("themes = Widget(\(q("Threads across apps")), null, [\(ids.joined(separator: ", "))])")
            for (i, t) in links.enumerated() { doc.append(row(id: "t\(i)", t)) }
            rootRefs.append("themes")
        }

        appendStarterPreviews(things: things,
                              hasMap: rootRefs.contains("map"),
                              mapSlot: mapSlot,
                              hasThreads: !links.isEmpty, to: &doc, rootRefs: &rootRefs)

        doc.insert("root = Stack([\(rootRefs.joined(separator: ", "))])", at: 0)
        return doc
    }

    /// Weekend — the week, banked: the recap voice rides the cover's eyebrow
    /// with the week's newest image (H7); then the map and threads. Same
    /// grammar, calmer voice; still no obligations.
    private static func weekend(things: [Thing], projects: [Cluster], walletHoldings: [WalletIngest.HoldingsGroup] = []) -> [String] {
        var doc: [String] = []
        var rootRefs: [String] = []

        let week = things.filter { $0.capturedAt > .now.addingTimeInterval(-7 * 86_400) }

        // The weekend cover: recap words, a set banner behind them or black
        // (2-tier, ruling 2026-07-10) — same as every other day.
        let title: String
        let subline: String
        if week.isEmpty && !things.isEmpty {
            title = "A quiet week"
            subline = "Your things keep — \(things.count) in all."
        } else if let top = projects.first {
            title = "Your week, banked"
            subline = "\(week.count) things · \(top.name) led"
        } else {
            title = "Your week, banked"
            subline = week.count == 1 ? "1 thing landed" : "\(week.count) things landed"
        }
        if !things.isEmpty {
            // No chips here: the weekend cover is a WEEK recap and its
            // subline already carries that story; today-only counts under
            // "your week, banked" would misread as the week's composition
            // (and stacking both broke the counts-are-the-subline rule).
            let coverRef = hasBanner ? "banner" : ""
            doc.append("cover = Cover(\(q("Weekend")), \(q(title)), \(q(subline)), \(q(coverRef)), \(q(dateline(things: things))), \(q("quiet")))")
            rootRefs.append("cover")
        }

        appendPinned(things, to: &doc, rootRefs: &rootRefs)
        appendWalletHoldings(walletHoldings, to: &doc, rootRefs: &rootRefs)

        if !projects.isEmpty {
            let items = projects.prefix(6).map { "\($0.name) \($0.things.count)" }
            doc.append("map = TagMap(\(q("The week")), \(q("What it was about")), [\(items.joined(separator: ", "))])")
            rootRefs.append("map")
        }
        let links = resurfaceable(things).prefix(2)
        if !links.isEmpty {
            let ids = links.indices.map { "t\($0)" }
            doc.append("themes = Widget(\(q("Worth returning to")), null, [\(ids.joined(separator: ", "))])")
            for (i, t) in links.enumerated() { doc.append(row(id: "t\(i)", t)) }
            rootRefs.append("themes")
        }

        doc.insert("root = Stack([\(rootRefs.joined(separator: ", "))])", at: 0)
        return doc
    }

    /// The empty state previews the real modules — the muted map and skeleton
    /// thread rows show the SHAPE of home and say plainly that connecting apps
    /// fills it. Preview, not fake data: kind names, no counts, nothing to tap.
    static let empty: [String] = [
        "root = Stack([hero, map, threads])",
        "hero = Hero(\"Getting started\", \"Your home builds itself\", \"Connect an app or capture one thing - what lands composes this screen.\")",
        previewMapLine,
        previewThreadsLine,
        "s1 = Skeleton()",
        "s2 = Skeleton()",
    ]

    /// The preview modules, shared by the empty doc and the sparse-corpus path.
    private static let previewMapLine =
        "map = TagMapPreview(\(q("What's going on")), \(q("Your things map here as they land")), [Links, Notes, Events, Mail, Screenshots])"
    private static let previewThreadsLine =
        "threads = Widget(\(q("Threads across apps")), \(q("Saved links resurface here")), [s1, s2])"

    /// A corpus this small hasn't earned real modules yet — one connected app
    /// or a first capture. The previews stay alongside the real rows so the
    /// screen shows where it's going instead of trailing off.
    private static func isSparse(_ things: [Thing]) -> Bool { things.count < 8 }

    /// Appends the preview map / threads when the real ones didn't compose.
    /// `mapSlot` is where a real map would have landed in `rootRefs` (right
    /// after cover/quiet/insight) — the preview takes that slot too, instead
    /// of trailing behind pinned/threads content composed after it.
    private static func appendStarterPreviews(things: [Thing], hasMap: Bool, mapSlot: Int, hasThreads: Bool,
                                              to doc: inout [String], rootRefs: inout [String]) {
        guard isSparse(things) else { return }
        if !hasMap {
            doc.append(previewMapLine)
            rootRefs.insert("map", at: mapSlot)
        }
        if !hasThreads {
            doc.append(previewThreadsLine)
            doc.append("s1 = Skeleton()")
            doc.append("s2 = Skeleton()")
            rootRefs.append("threads")
        }
    }

    // MARK: - Derivations

    struct Cluster {
        let name: String
        let things: [Thing]
    }

    /// Until tags form, the map speaks in APPS: real things clustered by
    /// source (min 2, "You" included). Honest for a fresh corpus — bridge
    /// things arrive untagged, and a real user's Home earned no map at all.
    static func sourceClusters(things: [Thing]) -> [Cluster] {
        var buckets: [String: [Thing]] = [:]
        for thing in things { buckets[thing.source, default: []].append(thing) }
        return buckets
            .filter { $0.value.count >= 2 }
            .map { Cluster(name: $0.key, things: $0.value) }
            .sorted {
                $0.things.count != $1.things.count
                    ? $0.things.count > $1.things.count
                    : $0.name < $1.name
            }
    }

    /// A project is a computed cluster; membership rides a tag (brief §3).
    static func projectClusters(things: [Thing]) -> [Cluster] {
        let typeTags = Set(ThingKind.allCases.map { $0.typeTag.lowercased() })
        var buckets: [String: [Thing]] = [:]
        for thing in things {
            for tag in thing.tags where !typeTags.contains(tag.lowercased()) {
                buckets[tag, default: []].append(thing)
            }
        }
        return buckets
            .filter { $0.value.count >= 2 }
            .map { Cluster(name: $0.key, things: $0.value) }
            .sorted {
                // Magnitude, then name — stable. (Project pins died 2026-07-07.)
                $0.things.count != $1.things.count
                    ? $0.things.count > $1.things.count
                    : $0.name < $1.name
            }
    }

    private static func tagCounts(things: [Thing]) -> [(String, Int)] {
        projectClusters(things: things).map { ($0.name, $0.things.count) }
    }

    /// Links old enough to be slipping away (3+ days), oldest last so the
    /// most recently at-risk lead.
    private static func resurfaceable(_ things: [Thing]) -> [Thing] {
        things.filter {
            $0.kind == .link && $0.capturedAt < .now.addingTimeInterval(-3 * 86_400)
        }
    }

    // MARK: - Cover (H7 — the doc names facts; the renderer owns the rest)

    /// "Thursday, July 9" — the day, stated plainly (ruling 2026-07-09: the
    /// landed count was noise for anyone with feeds — always a big number,
    /// never news; the kind pills below already tell today's story, and the
    /// quiet cover carries the quiet-day fact).
    private static func dateline(things: [Thing]) -> String {
        Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    /// True when the person set their own Home cover. Home's cover is
    /// 2-tier now (ruling 2026-07-10, amending 36a): a set banner, or black
    /// — a screenshot never auto-leads Home, full stop. The earlier
    /// "automatic newest screenshot" tier was a real privacy gap (a capture
    /// you didn't intend to see full-bleed could still show up there with
    /// zero action from you); an explicit Banner is the only way a photo
    /// reaches the cover. Renders shorter than the old live-capture height
    /// (150pt vs 250pt) so a banner still reads as "this is what I chose,"
    /// not "this just happened."
    private static var hasBanner: Bool { HomeCoverStore.shared.banner != nil }

    /// The cover line for morning/evening: a set banner, or the quiet cover
    /// carrying the shipped Hero content — same priority rules, no
    /// obligations. The words never change based on which image shows (or
    /// doesn't), so the cover never implies a static banner is today's
    /// activity. Today's kind counts ride every cover as chips (ruling
    /// 2026-07-09): the counts ARE the subline, so the old bottom "What
    /// landed today" section is gone and the cover's middle earns its
    /// height. The word subline returns only when nothing landed today.
    private static func cover(things: [Thing]) -> String {
        let date = dateline(things: things)
        // One today-sweep, shared by the chips (compose already scans the
        // corpus enough times per render).
        let today = things.filter { Calendar.current.isDateInToday($0.capturedAt) }
        let chips = coverChips(today)
        let chipsArg = chips.map { ", \($0)" } ?? ""
        let bannerRef = hasBanner ? "banner" : ""
        // Quiet cover — the shipped Hero lines, verbatim priority. Approvals
        // never lead Home (voice guardrail: agent asks live in Feed; the cover
        // states what landed, never what's waiting on the person).
        if isQuietDay(things) {
            return "cover = Cover(\(q("Today")), \(q("A quiet day")), \(q("Nothing new yet — your things keep.")), \(q(bannerRef)), \(q(date)), \(q("quiet")))"
        }
        if let latest = things.first(where: { $0.kind != .approval }) {
            // The 6th arg marks the stream complete so the renderer's black
            // field doesn't flash in before the doc settles.
            let subline = chips != nil ? "" : "\(latest.kind.typeTag) · \(latest.source)"
            return "cover = Cover(\(q("Just landed · \(latest.source)")), \(q(latest.title)), \(q(subline)), \(q(bannerRef)), \(q(date)), \(q(latest.kind.typeTag))\(chipsArg))"
        }
        return "cover = Cover(\(q("Now")), \(q("Your things go here")), \(q("Paste, speak, or share one in.")), \(q(bannerRef)), \(q(date)), \(q("quiet")))"
    }

    // MARK: - Cover chips (what landed today, on the cover — ruling 2026-07-09)

    /// Today's kind counts, "[Tag N, ...]", count-ordered, max 5 — the
    /// cover's chip row (the KindPills section moved up into the banner).
    /// Takes the pre-filtered today pool. Nil when nothing landed today: the
    /// quiet cover states that in words, and yesterday's counts aren't news.
    /// Approvals never count — same guardrail as the cover lead: the cover
    /// states what landed, never what's waiting on the person.
    private static func coverChips(_ today: [Thing]) -> String? {
        var counts: [ThingKind: Int] = [:]
        for t in today where t.kind != .approval { counts[t.kind, default: 0] += 1 }
        guard !counts.isEmpty else { return nil }
        let items = counts.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.key.typeTag < $1.key.typeTag
        }.prefix(5).map { "\($0.key.typeTag) \($0.value)" }
        return "[\(items.joined(separator: ", "))]"
    }

    // MARK: - Line builders

    private static func hero(eyebrow: String, title: String, subline: String) -> String {
        "hero = Hero(\(q(eyebrow)), \(q(title)), \(q(subline)))"
    }

    private static func projectTile(id: String, _ c: Cluster) -> String {
        let sources = Array(Set(c.things.map(\.source))).sorted().prefix(3).joined(separator: ",")
        // Subline reads content, not status: name the kinds inside.
        let kindWords = Array(Set(c.things.map { $0.kind.typeTag.lowercased() + "s" })).sorted().prefix(3)
        let subline = kindWords.joined(separator: ", ").capitalizedFirst
        return "\(id) = ProjectTile(\(q("1")), \(q(c.name)), \(q(sources)), \(q(subline)), \(q("\(c.things.count) things")), blue)"
    }

    /// Feed pins surface on Home too (ruling 2026-07-06): a pin means "keep
    /// this in view", and Home is the view. Newest first, capped at 3.
    private static func appendPinned(_ things: [Thing],
                                     to doc: inout [String],
                                     rootRefs: inout [String]) {
        let pinned = things.filter(\.pinned).prefix(3)
        guard !pinned.isEmpty else { return }
        let ids = pinned.indices.map { "pn\($0)" }
        doc.append("pinnedW = Widget(\(q("Pinned")), null, [\(ids.joined(separator: ", "))])")
        for (i, t) in pinned.enumerated() { doc.append(row(id: "pn\(i)", t)) }
        rootRefs.append("pinnedW")
    }

    /// Wallet holdings on Home (ruling 2026-07-08): pinning the wallet shows
    /// each watched wallet's own top-5-by-value treemap, the same TagMap
    /// idiom the map itself uses — synthesis, not a thing, so it rides
    /// alongside Pinned rather than inside it. One map per wallet, not
    /// combined (ruling 2026-07-09): two watched addresses are usually two
    /// different purposes, and summing them hid which wallet held what.
    /// Groups arrive pre-computed (WalletIngest.topHoldingsByWallet()) since
    /// composing the doc is synchronous and the fetch is not.
    private static func appendWalletHoldings(_ groups: [WalletIngest.HoldingsGroup],
                                             to doc: inout [String],
                                             rootRefs: inout [String]) {
        for (i, g) in groups.enumerated() {
            let id = "walletMap\(i)"
            doc.append("\(id) = TagMap(\(q(g.label)), \(q("Holdings by value")), [\(g.cells.joined(separator: ", "))], \(q("token")))")
            rootRefs.append(id)
        }
    }

    /// A token link leads with its price chart, same rule as the thing sheet
    /// (ThingContent.swift) — the token's "media" is the chart, not a link row.
    private static func row(id: String, _ t: Thing) -> String {
        if t.kind == .link, let route = TokenChart.route(from: t.content) {
            return "\(id) = TokenRow(\(q(t.title)), \(q(route.chain)), \(q(route.address)), \(q(shortTime(t.capturedAt))))"
        }
        return "\(id) = Row(\(q(t.title)), \(q(t.kind.typeTag)), \(q(t.source)), \(q(shortTime(t.capturedAt))))"
    }

    private static func shortTime(_ date: Date) -> String {
        let s = Date.now.timeIntervalSince(date)
        if s < 3600 { return "\(max(1, Int(s / 60)))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86_400))d"
    }

    /// Quotes a string for the document; strips embedded quotes rather than
    /// escaping (the line grammar has no escape sequence).
    private static func q(_ s: String) -> String {
        "\"\(s.replacingOccurrences(of: "\"", with: ""))\""
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
