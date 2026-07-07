import SwiftUI
import SwiftData

/// Project detail (gap §9.1 / PRD open item 4) — the header paints from the
/// tile (record), the composition streams under it (synthesis). Things group
/// by what they're doing in the project: in motion, saved, recent.
struct ProjectDetailScreen: View {
    let projectName: String
    @Query(sort: \Thing.capturedAt, order: .reverse) private var things: [Thing]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var stream = GenStream()
    @State private var renaming = false
    @State private var newName = ""

    private var members: [Thing] {
        things.filter { $0.tags.contains(projectName) }
    }
    private var sourceCount: Int { Set(members.map(\.source)).count }
    private var kindLine: String {
        let kinds = Array(Set(members.map { $0.kind.typeTag.lowercased() + "s" })).sorted().prefix(3)
        let joined = kinds.joined(separator: ", ")
        return joined.isEmpty ? "" : joined.prefix(1).uppercased() + joined.dropFirst()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header card — paints at once from what the tile knew.
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text(projectName)
                        .dsText(.heading34).foregroundStyle(DS.textPrimary)
                    Text(kindLine)
                        .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    Text("\(members.count) things · \(sourceCount) apps")
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.s4)
                .background(ProjectHue.color(for: projectName).opacity(0.5),
                            in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
                .padding(DS.Space.s4)
                .mountIn()

                // The synthesis streams under the painted record.
                GenRender(id: "root", els: stream.els)
            }
            .padding(.top, ShellMetrics.topInset)
            .padding(.bottom, ShellMetrics.bottomInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .dsPageBackground()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { stream.stream(compose()) }
        // The person renames; the person never files. (The project PIN died
        // 2026-07-07 — every project already sits on Home's map, so a pin
        // that only re-sorted it was a second pin system. Thing pins remain.)
        .toolbar {
            Button {
                newName = projectName
                renaming = true
            } label: {
                Image(systemName: "pencil")
            }
            .tint(DS.tint)
            .accessibilityLabel("Rename project")
        }
        .alert("Rename \(projectName)", isPresented: $renaming) {
            TextField("Project name", text: $newName)
            Button("Rename") { rename() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The name changes on every thing that carries it.")
        }
    }

    /// Rename = rewrite the tag across the corpus. The cluster IS the tag, so
    /// the project follows its things (S21). The screen closes because its
    /// route is the old name.
    private func rename() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != projectName else { return }
        for thing in members {
            // Map, then dedupe: renaming onto a tag the thing already carries
            // must merge, not double.
            var seen = Set<String>()
            thing.tags = thing.tags
                .map { $0 == projectName ? name : $0 }
                .filter { seen.insert($0.lowercased()).inserted }
        }
        try? modelContext.save()
        DSHaptic.success()
        dismiss()
    }

    /// Authors the project composition locally (server /compose swaps in at M2's
    /// back half). Groups: in motion (todo/doing), saved, recent unmarked.
    private func compose() -> [String] {
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
            insight = "\(moving.count) thing\(moving.count == 1 ? "" : "s") in motion."
        } else if members.contains(where: { $0.mark == .saved }) {
            insight = "Saved and waiting. Nothing started."
        } else {
            insight = "\(members.count) things across \(sourceCount) apps."
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
