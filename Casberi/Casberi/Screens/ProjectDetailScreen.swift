import SwiftUI
import SwiftData

/// Project detail (gap §9.1 / PRD open item 4) — the header paints from the
/// tile, the composition paints under it. Both are RECORD, not synthesis:
/// `compose()` is deterministic grouping of things the person already owns, so
/// per brief §5 ("generated surfaces stream; records paint") it paints whole,
/// not through the typewriter. Things group by what they're doing in the
/// project: in motion, saved, recent.
struct ProjectDetailScreen: View {
    let projectName: String
    /// REVERTED 2026-07-21: a `#Predicate<Thing> { $0.tags.contains(projectName) }`
    /// looked like the obvious perf win here (scope the query to this
    /// project's own tag instead of fetching everything) and compiled clean —
    /// but crashed at runtime, SIGSEGV inside CoreData's `_NSCoreDataStringSearch`
    /// during the live SQLite fetch (confirmed via crash report, reproduced by
    /// opening a project). `tags` is a transformable `[String]` attribute, and
    /// SwiftData's predicate translation for `.contains` on it isn't safe to
    /// push down to SQL here. Filtering in Swift after an unscoped fetch — the
    /// original shape — is the correct, safe form; don't reintroduce the
    /// predicate without verifying against a real on-device fetch first.
    /// Hydrating ONLY the columns this screen reads (PERF 2026-08-12) — the
    /// same treatment `MainSurface.chipCorpus` and the All room's query got.
    /// Without it every write re-materialised the whole corpus WITH its heavy
    /// inline text (`content`/`enrichedText`/`postText`), none of which this
    /// screen draws: the header reads tags/source/kind, and a row reads
    /// title/kind/source/capturedAt. Nothing here faults.
    ///
    /// Still UNBOUNDED and still unpredicated, both deliberately. A project is
    /// defined by a TAG, and a `#Predicate` over the transformable `tags`
    /// array traps at runtime (see the note above) — while a `fetchLimit`
    /// would silently drop the older half of a long-running project, which is
    /// the half this screen exists to show.
    @Query(ProjectDetailScreen.corpus) private var things: [Thing]
    private static var corpus: FetchDescriptor<Thing> {
        var d = FetchDescriptor<Thing>(sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        d.propertiesToFetch = [\.id, \.tags, \.source, \.kind, \.mark, \.title, \.capturedAt]
        return d
    }
    @Environment(\.modelContext) private var modelContext
    @State private var stream = GenStream()

    private var members: [Thing] {
        things.filter { $0.tags.contains(projectName) }
    }
    private func sourceCount(_ members: [Thing]) -> Int { Set(members.map(\.source)).count }
    private func kindLine(_ members: [Thing]) -> String {
        let kinds = Array(Set(members.map { $0.kind.typeTag.lowercased() + "s" })).sorted().prefix(3)
        let joined = kinds.joined(separator: ", ")
        return joined.isEmpty ? "" : joined.prefix(1).uppercased() + joined.dropFirst()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header card — paints at once from what the tile knew.
                header

                // The composition paints under the header (record, §5).
                GenRender(id: "root", els: stream.els)
            }
            .padding(.top, ShellMetrics.topInset)
            .padding(.bottom, ShellMetrics.bottomInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .navigationBarTitleDisplayMode(.inline)
        // Paint the whole composition at once — a record, not a stream (§5).
        // This screen is a zoom-transition DESTINATION (HomeScreen pushes it
        // with .navigationTransition(.zoom)). Streaming gen content under a zoom
        // transition HANGS THE MAIN THREAD: each typewriter tick mutates `els`,
        // which remounts widgets incrementally, and a widget mounting into the
        // zoom-presented geometry drives SwiftUI into a layout cycle that never
        // returns — the tick, its watchdog, and every other main-actor task stop
        // (proven 2026-07-10 by a background-vs-main heartbeat: BG kept ticking,
        // MAIN died at the 3rd widget). It reads as a half-parsed widget — an
        // empty "Recent"/"Saved" pane (audit finding) — but the whole app is
        // frozen; simctl still screenshots the framebuffer, which masked it.
        // Painting sets `els` once (no incremental mounts) and sidesteps it, and
        // a record has no "still writing" state, so painting is also honest here.
        // RULE: any gen surface presented under a zoom transition must paint.
        .onAppear { stream.paint(compose()) }
        // The corpus changed under it — repaint whole.
        // `Corpus.revision`, not `things.count` (2026-08-12). A project IS a
        // tag, so the change this screen most needs to notice is a RETAG — and
        // a retag moves no row count, so this recomposed for arrivals and
        // deletions and silently ignored something being tagged INTO or OUT OF
        // the project it is showing. `CorpusSignal` is bumped by exactly those
        // paths (`ThingSheetView`, `CounterpartyRetitle`, the Organize sweep)
        // and had no reader until now; this screen is the clearest case for
        // it in the app.
        .onChange(of: Corpus.revision(in: modelContext)) { stream.paint(compose()) }
    }

    /// ONE walk of the corpus, not three (PERF 2026-08-12). `members` is a
    /// computed property over the whole `@Query`, and this card used to ask
    /// for it three separate times — `count`, `sourceCount`, `kindLine` — on
    /// every body evaluation; `compose()` asked for it six more. Bound once
    /// here, where a `let` is legal, and passed to the two that need it.
    private var header: some View {
        let members = self.members
        return VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(projectName)
                .dsText(.heading34).foregroundStyle(DS.textPrimary)
            Text(kindLine(members))
                .dsText(.callout15).foregroundStyle(DS.textSecondary)
            Text("\(members.count) things · \(sourceCount(members)) apps")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s4)
        .background(ProjectHue.color(for: projectName).opacity(0.5),
                    in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        .padding(DS.Space.s4)
        .mountIn()
    }

    /// Authors the project composition locally (server /compose swaps in at M2's
    /// back half). Groups: in motion (todo/doing), saved, recent unmarked.
    private func compose() -> [String] {
        let members = self.members   // ONE walk; this function read it six times
        guard !members.isEmpty else {
            let name = projectName.replacingOccurrences(of: "\"", with: "")
            return ["root = Stack([ins])",
                    "ins = Insight(\"Nothing here yet. Things tagged \(name) will fill this in.\")"]
        }
        var doc: [String] = []
        var rootRefs: [String] = []

        // Insight — one fact the corpus proves.
        let moving = members.filter { $0.mark == .todo || $0.mark == .doing }
        let insight: String
        if !moving.isEmpty {
            insight = String(localized: "\(moving.count) thing in motion.")
        } else if members.contains(where: { $0.mark == .saved }) {
            insight = "Saved and waiting. Nothing started."
        } else {
            insight = "\(members.count) things across \(sourceCount(members)) apps."
        }
        doc.append("ins = Insight(\"\(insight)\")")
        rootRefs.append("ins")

        func widget(_ id: String, _ title: String, _ rows: ArraySlice<Thing>) {
            guard !rows.isEmpty else { return }   // widget child-drop rule
            let ids = rows.indices.map { "\(id)\($0)" }
            doc.append("\(id) = Widget(\"\(title)\", null, [\(ids.joined(separator: ", "))])")
            for (i, t) in zip(rows.indices, rows) {
                let title = t.title.replacingOccurrences(of: "\"", with: "")
                doc.append("\(id)\(i) = Row(\"\(title)\", \"\(t.kind.typeTag)\", \"\(t.source)\", \"\(Self.shortTime(t.capturedAt))\")")
            }
            rootRefs.append(id)
        }

        widget("m", "In motion", moving.prefix(4))
        widget("s", "Saved", members.filter { $0.mark == .saved }.prefix(4))
        widget("r", "Recent", members.filter { $0.mark == Mark.none }.prefix(4))

        doc.insert("root = Stack([\(rootRefs.joined(separator: ", "))])", at: 0)
        return doc
    }

    static func shortTime(_ date: Date) -> String {
        let s = Date.now.timeIntervalSince(date)
        if s < 3600 { return "\(max(1, Int(s / 60)))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86_400))d"
    }
}
