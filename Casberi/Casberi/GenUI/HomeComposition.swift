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
                        hour: Int = Calendar.current.component(.hour, from: .now),
                        weekday: Int = Calendar.current.component(.weekday, from: .now)) -> [String] {
        let projects = projectClusters(things: things)
        // Saturday/Sunday reads as a recap — the week, banked.
        if weekday == 1 || weekday == 7 {
            return weekend(things: things, projects: projects)
        }
        return hour < 15
            ? morning(things: things, projects: projects)
            : evening(things: things, projects: projects)
    }

    /// True when nothing has landed today — the composition acknowledges the
    /// quiet instead of pretending motion (voice: facts, no obligations).
    private static func isQuietDay(_ things: [Thing]) -> Bool {
        !things.isEmpty && !things.contains { Calendar.current.isDateInToday($0.capturedAt) }
    }

    // MARK: - Documents

    private static func morning(things: [Thing], projects: [Cluster]) -> [String] {
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

        // Insight — one cross-source connection, only when the corpus proves one.
        if let line = insightLine(projects: projects) {
            doc.append("insight = Insight(\(q(line)))")
            rootRefs.append("insight")
        }

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
                doc.append("map = TagMap(\(q("What's going on")), \(q("By app — tags take over as they form")), [\(items.joined(separator: ", "))])")
                rootRefs.append("map")
            }
        }
        if let pills = kindPillItems(things) {
            doc.append("kindPills = KindPills(\(q(kindPillEyebrow(things))), \(pills))")
            rootRefs.append("kindPills")
        }

        // Pinned — things the person chose to keep in view. User-chosen, so
        // it passes the no-obligations rule: Casberi never picked these.
        appendPinned(things, to: &doc, rootRefs: &rootRefs)

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
                              hasThreads: !links.isEmpty, to: &doc, rootRefs: &rootRefs)

        doc.insert("root = Stack([\(rootRefs.joined(separator: ", "))])", at: 0)
        return doc
    }

    private static func evening(things: [Thing], projects: [Cluster]) -> [String] {
        var doc: [String] = []
        var rootRefs: [String] = []

        // The cover leads (H7); evening keeps its own lineup below it.
        doc.append(cover(things: things))
        rootRefs.append("cover")

        if isQuietDay(things) {
            doc.append("quiet = Quiet(\(q("Quiet so far today.")))")
            rootRefs.append("quiet")
        }

        if !projects.isEmpty {
            let items = projects.prefix(6).map { "\($0.name) \($0.things.count)" }
            doc.append("map = TagMap(\(q("What's going on")), null, [\(items.joined(separator: ", "))])")
            rootRefs.append("map")
        } else {
            let sources = sourceClusters(things: things)
            if !sources.isEmpty {
                let items = sources.prefix(6).map { "\($0.name) \($0.things.count)" }
                doc.append("map = TagMap(\(q("What's going on")), \(q("By app — tags take over as they form")), [\(items.joined(separator: ", "))])")
                rootRefs.append("map")
            }
        }
        if let pills = kindPillItems(things) {
            doc.append("kindPills = KindPills(\(q(kindPillEyebrow(things))), \(pills))")
            rootRefs.append("kindPills")
        }

        // Pinned rides evening too — same rule as morning.
        appendPinned(things, to: &doc, rootRefs: &rootRefs)

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
                              hasThreads: !links.isEmpty, to: &doc, rootRefs: &rootRefs)

        doc.insert("root = Stack([\(rootRefs.joined(separator: ", "))])", at: 0)
        return doc
    }

    /// Weekend — the week, banked: the recap voice rides the cover's eyebrow
    /// with the week's newest image (H7); then the map and threads. Same
    /// grammar, calmer voice; still no obligations.
    private static func weekend(things: [Thing], projects: [Cluster]) -> [String] {
        var doc: [String] = []
        var rootRefs: [String] = []

        let week = things.filter { $0.capturedAt > .now.addingTimeInterval(-7 * 86_400) }

        // The weekend cover: recap words, the week's newest image behind them.
        let image = newestImageThing(things)
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
            doc.append("cover = Cover(\(q("Weekend")), \(q(title)), \(q(subline)), \(image.map { q($0.id.uuidString) } ?? "\"\""), \(q(dateline(things: things))), \(q("quiet")))")
            rootRefs.append("cover")
        }

        if !projects.isEmpty {
            let items = projects.prefix(6).map { "\($0.name) \($0.things.count)" }
            doc.append("map = TagMap(\(q("The week")), \(q("What it was about")), [\(items.joined(separator: ", "))])")
            rootRefs.append("map")
        }
        if let pills = kindPillItems(things) {
            doc.append("kindPills = KindPills(\(q("What it held")), \(pills))")
            rootRefs.append("kindPills")
        }

        appendPinned(things, to: &doc, rootRefs: &rootRefs)

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
    private static func appendStarterPreviews(things: [Thing], hasMap: Bool, hasThreads: Bool,
                                              to doc: inout [String], rootRefs: inout [String]) {
        guard isSparse(things) else { return }
        if !hasMap {
            doc.append(previewMapLine)
            rootRefs.append("map")
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

    /// One cross-source connection the corpus proves, or nothing.
    private static func insightLine(projects: [Cluster]) -> String? {
        for c in projects {
            let kinds = Set(c.things.map(\.kind))
            let sources = Set(c.things.map(\.source))
            if kinds.contains(.screenshot) && kinds.contains(.chat) && sources.count >= 2 {
                let shots = c.things.filter { $0.kind == .screenshot }.count
                return "\(shots == 1 ? "A screenshot matches" : "\(shots) screenshots match") the \(c.name) session."
            }
        }
        if let c = projects.first(where: { Set($0.things.map(\.source)).count >= 3 }) {
            return "\(c.name) now spans \(Set(c.things.map(\.source)).count) apps."
        }
        return nil
    }

    /// Links old enough to be slipping away (3+ days), oldest last so the
    /// most recently at-risk lead.
    private static func resurfaceable(_ things: [Thing]) -> [Thing] {
        things.filter {
            $0.kind == .link && $0.capturedAt < .now.addingTimeInterval(-3 * 86_400)
        }
    }

    /// The corpus's composition — kind counts for the kind bar (the type
    /// chart lives on Home now; Feed is a feed).
    private static func kindItems(_ things: [Thing]) -> String? {
        var counts: [ThingKind: Int] = [:]
        for t in things { counts[t.kind, default: 0] += 1 }
        guard counts.count >= 3 else { return nil }
        let items = counts.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.key.typeTag < $1.key.typeTag
        }.prefix(5).map { "\($0.key.typeTag) \($0.value)" }
        return "[\(items.joined(separator: ", "))]"
    }

    // MARK: - Cover (H7 — the doc names facts; the renderer owns the rest)

    /// The day's newest image thing, falling back to this week's (the cover's
    /// image rule). Screenshots are the image kind the corpus knows today —
    /// and only ones whose asset can resolve (a sourceRef): the author only
    /// names a thingId when the renderer's canvas will actually fill, so the
    /// 250pt cover never paints an empty skeleton (demo screenshots carry no
    /// asset and honestly fall to the quiet cover).
    private static func newestImageThing(_ things: [Thing]) -> Thing? {
        let images = things.filter { $0.kind == .screenshot && $0.sourceRef != nil }
        return images.first { Calendar.current.isDateInToday($0.capturedAt) }
            ?? images.first { $0.capturedAt > .now.addingTimeInterval(-7 * 86_400) }
    }

    /// "Monday · 14 things" / "Monday · Quiet so far" — the top edge earns
    /// its space. Landed counts only; never obligations.
    private static func dateline(things: [Thing]) -> String {
        let weekday = Date.now.formatted(.dateTime.weekday(.wide))
        let today = things.filter { Calendar.current.isDateInToday($0.capturedAt) }.count
        if today == 0 { return "\(weekday) · Quiet so far" }
        return "\(weekday) · \(today) thing\(today == 1 ? "" : "s")"
    }

    /// The cover line for morning/evening: the newest image thing when one
    /// exists (title, project · time), else the quiet cover carrying the
    /// shipped Hero content — same priority rules, no obligations.
    private static func cover(things: [Thing]) -> String {
        let date = dateline(things: things)
        if let image = newestImageThing(things) {
            let project = image.tags.first { ThingKind.from(typeTag: $0) == nil }
            let subline = [project, shortTime(image.capturedAt)]
                .compactMap { $0 }.joined(separator: " · ")
            return "cover = Cover(\(q("Just landed · \(image.source)")), \(q(image.title)), \(q(subline)), \(q(image.id.uuidString)), \(q(date)))"
        }
        // Quiet cover — the shipped Hero lines, verbatim priority. Approvals
        // never lead Home (voice guardrail: agent asks live in Feed; the cover
        // states what landed, never what's waiting on the person).
        if isQuietDay(things) {
            return "cover = Cover(\(q("Today")), \(q("A quiet day")), \(q("Nothing new yet — your things keep.")), \"\", \(q(date)), \(q("quiet")))"
        }
        if let latest = things.first(where: { $0.kind != .approval }) {
            // The 6th arg names the kind so the quiet cover can wear its hue
            // (the image cover extracts color from the photo instead).
            return "cover = Cover(\(q("Just landed")), \(q(latest.title)), \(q("\(latest.kind.typeTag) · \(latest.source)")), \"\", \(q(date)), \(q(latest.kind.typeTag)))"
        }
        return "cover = Cover(\(q("Now")), \(q("Your things go here")), \(q("Paste, speak, or share one in.")), \"\", \(q(date)), \(q("quiet")))"
    }

    // MARK: - Kind pills (replaces the KindBar on Home; the bar stays in the vocabulary)

    /// "What landed today" over today's things; the whole corpus (and the
    /// KindBar's old eyebrow) when today is empty.
    private static func kindPillEyebrow(_ things: [Thing]) -> String {
        things.contains { Calendar.current.isDateInToday($0.capturedAt) }
            ? "What landed today" : "What they are"
    }

    private static func kindPillItems(_ things: [Thing]) -> String? {
        let today = things.filter { Calendar.current.isDateInToday($0.capturedAt) }
        let pool = today.isEmpty ? things : today
        var counts: [ThingKind: Int] = [:]
        for t in pool { counts[t.kind, default: 0] += 1 }
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

    private static func row(id: String, _ t: Thing) -> String {
        "\(id) = Row(\(q(t.title)), \(q(t.kind.typeTag)), \(q(t.source)), \(q(shortTime(t.capturedAt))))"
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
