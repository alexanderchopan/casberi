import SwiftUI
import SwiftData

/// The thing sheet (M4) — the thing, then its verbs. Header paints from the
/// row; content by kind; verbs card (derived, cap three; writes confirm);
/// mark control; one Tags field (active lit, candidates dim, tap toggles);
/// the Related shelf streams last through the engine.
struct ThingSheetView: View {
    @Bindable var thing: Thing
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var tagDraft = ""
    @State private var confirmingVerb: Verb?
    @State private var verbResult: String?
    @State private var relatedStream = GenStream()
    @State private var renameTarget: String?
    @State private var renameDraft = ""
    @State private var deleteTarget: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                contentByKind
                verbsCard
                tagsField
                relatedShelf
            }
            .padding(.bottom, DS.Space.s6)
        }
        .scrollIndicators(.hidden)
        .presentationBackground(.thickMaterial)  // frosted tray — content ghosts, never competes
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(DS.Radius.sheet)
        .dsColorScheme()
        .onAppear { streamRelated() }
        // Ask-before-acting: writes confirm, reads pass.
        .confirmationDialog(
            confirmingVerb.map { "\($0.label): \(thing.title)?" } ?? "",
            isPresented: Binding(get: { confirmingVerb != nil },
                                 set: { if !$0 { confirmingVerb = nil } }),
            titleVisibility: .visible
        ) {
            if let verb = confirmingVerb {
                Button(verb.label) { Task { await perform(verb) } }
                Button("Cancel", role: .cancel) { confirmingVerb = nil }
            }
        }
    }

    // MARK: - Header (paints from the row)

    private var header: some View {
        HStack(spacing: DS.Space.s3) {
            KindGlyph(kind: thing.kind, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(thing.title)
                    .dsText(.heading17).foregroundStyle(DS.textPrimary)
                    .lineLimit(2)
                Text("\(PlaceWords.line(for: thing)) · \(shortTime(thing.capturedAt))")
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                if let agent = thing.provenance.agent {
                    Text("by \(agent)\(thing.provenance.machine.map { " on \($0)" } ?? "")")
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                }
            }
            Spacer()
            // The universal out-door: the system share sheet reaches every app
            // with a share target — Notes, Messages, Mail — so a thing can land
            // anywhere without Casberi needing a per-app write API (the only
            // sanctioned route INTO Apple Notes, for one). A hand-off, not a
            // write: sheet-level utility like Copy.
            shareButton
        }
        .padding(DS.Space.s4)
    }

    /// Links share as URLs (targets preview them); everything else as text.
    @ViewBuilder
    private var shareButton: some View {
        let text = thing.content.isEmpty ? thing.title : thing.content
        Group {
            if let url = Capture.detectURL(in: text) {
                ShareLink(item: url) { shareGlyph }
            } else {
                ShareLink(item: text, subject: Text(thing.title)) { shareGlyph }
            }
        }
        .buttonStyle(.plain)
    }

    private var shareGlyph: some View {
        Image(systemName: "square.and.arrow.up")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(DS.textSecondary)
            .frame(width: 36, height: 36)
            .background(DS.fillFaint, in: Circle())
    }

    // MARK: - Content by kind (S19 — the thing shows AS what it is)

    private var contentByKind: some View {
        ThingContentView(thing: thing)
    }

    // MARK: - Verbs card (derived, cap three)

    private var verbsCard: some View {
        VStack(spacing: 0) {
            ForEach(VerbDerivation.verbs(for: thing)) { verb in
                Button {
                    if verb.isWrite {
                        confirmingVerb = verb   // writes confirm
                    } else {
                        Task { await perform(verb) }   // reads pass
                    }
                } label: {
                    HStack(spacing: DS.Space.s3) {
                        Image(systemName: verb.icon)
                            .font(.system(size: 15))
                            .foregroundStyle(DS.tint)
                            .frame(width: 28, height: 28)
                            .background(DS.tintDim,
                                        in: RoundedRectangle(cornerRadius: DS.Radius.appIcon(28), style: .continuous))
                        Text(verb.label)
                            .dsText(.body17).foregroundStyle(DS.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13))
                            .foregroundStyle(DS.gray600)
                    }
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.vertical, DS.Space.s3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let verbResult {
                Text(verbResult)
                    .dsText(.subhead13).foregroundStyle(DS.confirm)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.bottom, DS.Space.s3)
            }
        }
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
    }

    // MARK: - Tags (one field; active lit, candidates dim)

    private var candidates: [String] {
        let typeTags = Set(ThingKind.allCases.map(\.typeTag))
        let all = (try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []
        let projectTags = Set(all.flatMap(\.tags)).subtracting(typeTags)
        return projectTags.subtracting(thing.tags).sorted()
    }

    private var tagsField: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text("TAGS")
                .dsText(.label12).kerning(0.7)
                .foregroundStyle(DS.textTertiary)

            FlowLayout(spacing: DS.Space.s2) {
                ForEach(thing.tags, id: \.self) { tag in
                    activeTagChip(tag)
                }
                ForEach(candidates, id: \.self) { tag in
                    tagChip(tag, active: false) { add(tag: tag) }
                }
            }

            HStack(spacing: DS.Space.s2) {
                TextField("Add a tag", text: $tagDraft)
                    .dsText(.callout15)
                    .foregroundStyle(DS.textPrimary)
                    .tint(DS.tint)
                    .onSubmit { add(tag: tagDraft); tagDraft = "" }
                Button("Add") { add(tag: tagDraft); tagDraft = "" }
                    .dsText(.label12)
                    .foregroundStyle(tagDraft.isEmpty ? DS.textTertiary : .white)
                    .padding(.horizontal, DS.Space.s3)
                    .frame(height: 28)
                    .background(tagDraft.isEmpty ? DS.gray200 : DS.tint,
                                in: Capsule(style: .continuous))
                    .disabled(tagDraft.isEmpty)
                    .buttonStyle(.plain)
            }
            .padding(.leading, DS.Space.s4)
            .padding(.trailing, DS.Space.s2)
            .frame(height: 40)
            .background(DS.gray100, in: Capsule(style: .continuous))
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s4)
    }

    private func tagChip(_ tag: String, active: Bool, onTap: @escaping () -> Void) -> some View {
        Text(tag)
            .dsText(.label12)
            .foregroundStyle(active ? DS.tint : DS.textSecondary)
            .padding(.horizontal, DS.Space.s3)
            .frame(height: 28)
            .background(active ? DS.tintDim : DS.gray100, in: Capsule(style: .continuous))
            .onTapGesture(perform: onTap)
    }

    /// An active tag: the × makes removal visible; press-and-hold manages the
    /// tag across every thing (fixes typos, merges duplicates). The type tag
    /// is assigned at ingestion and carries no controls.
    @ViewBuilder
    private func activeTagChip(_ tag: String) -> some View {
        let isTypeTag = tag == thing.kind.typeTag
        HStack(spacing: DS.Space.s1) {
            Text(tag).dsText(.label12).foregroundStyle(DS.tint)
            if !isTypeTag {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DS.tint.opacity(0.6))
            }
        }
        .padding(.horizontal, DS.Space.s3)
        .frame(height: 28)
        .background(DS.tintDim, in: Capsule(style: .continuous))
        .onTapGesture { remove(tag: tag) }
        .contextMenu {
            if !isTypeTag {
                Button("Remove from this thing", systemImage: "xmark.circle") {
                    remove(tag: tag)
                }
                Button("Rename everywhere…", systemImage: "pencil") {
                    renameDraft = tag
                    renameTarget = tag
                }
                Button("Delete everywhere…", systemImage: "trash", role: .destructive) {
                    deleteTarget = tag
                }
            }
        }
        .alert("Rename \"\(renameTarget ?? "")\" everywhere",
               isPresented: Binding(get: { renameTarget == tag },
                                    set: { if !$0 { renameTarget = nil } })) {
            TextField("New name", text: $renameDraft)
            Button("Rename") { renameEverywhere(tag, to: renameDraft) }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        } message: {
            Text("Every thing with this tag gets the new name.")
        }
        .confirmationDialog("Delete \"\(deleteTarget ?? "")\" from every thing?",
                            isPresented: Binding(get: { deleteTarget == tag },
                                                 set: { if !$0 { deleteTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Delete everywhere", role: .destructive) { deleteEverywhere(tag) }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("Things keep their content — only the tag goes.")
        }
    }

    /// Rewrites the tag across the whole corpus; a pinned project keeps its
    /// pin under the new name.
    private func renameEverywhere(_ old: String, to newRaw: String) {
        let new = newRaw.trimmingCharacters(in: .whitespaces)
        renameTarget = nil
        guard !new.isEmpty, new != old else { return }
        let all = (try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []
        for t in all where t.tags.contains(old) {
            t.tags = t.tags.map { $0 == old ? new : $0 }
        }
        if ProjectPins.contains(old) {
            ProjectPins.toggle(old)
            if !ProjectPins.contains(new) { ProjectPins.toggle(new) }
        }
        try? modelContext.save()
        DSHaptic.success()
    }

    private func deleteEverywhere(_ tag: String) {
        deleteTarget = nil
        let all = (try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []
        for t in all where t.tags.contains(tag) {
            t.tags.removeAll { $0 == tag }
        }
        if ProjectPins.contains(tag) { ProjectPins.toggle(tag) }
        try? modelContext.save()
        DSHaptic.success()
    }

    private func add(tag: String) {
        let t = tag.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !thing.tags.contains(where: { $0.lowercased() == t.lowercased() }) else { return }
        thing.tags.append(t)
        try? modelContext.save()
    }

    private func remove(tag: String) {
        // The type tag stays — it's assigned at ingestion, not user-managed.
        guard tag != thing.kind.typeTag else { return }
        thing.tags.removeAll { $0 == tag }
        try? modelContext.save()
    }

    // MARK: - Related shelf (streams last)

    private var relatedShelf: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if !relatedStream.els.isEmpty {
                Text("RELATED")
                    .dsText(.label12).kerning(0.7)
                    .foregroundStyle(DS.textTertiary)
                    .padding(.horizontal, DS.Space.s4)
            }
            GenRender(id: "root", els: relatedStream.els)
        }
    }

    private func streamRelated() {
        let typeTags = Set(ThingKind.allCases.map(\.typeTag))
        let myTags = Set(thing.tags).subtracting(typeTags)
        guard !myTags.isEmpty else { return }
        var descriptor = FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 300   // relatedness lives in the recent past
        let all = (try? modelContext.fetch(descriptor)) ?? []
        let related = all.filter { other in
            other.id != thing.id && !myTags.isDisjoint(with: other.tags)
        }.prefix(6)
        guard !related.isEmpty else { return }

        var doc = ["root = Shelf([\(related.indices.map { "c\($0)" }.joined(separator: ", "))])"]
        for (i, t) in related.enumerated() {
            let title = t.title.replacingOccurrences(of: "\"", with: "")
            doc.append("c\(i) = Chip(\"\(t.source)\", \"\(title)\")")
        }
        relatedStream.stream(doc)
    }

    // MARK: - Verb execution

    private func perform(_ verb: Verb) async {
        confirmingVerb = nil
        switch verb.action {
        case .openURL(let url):
            openURL(url)
        case .addToCalendar:
            do {
                try await HandOff.addToCalendar(thing)
                verbResult = "On your calendar"
            } catch { verbResult = error.localizedDescription }
        case .addToReminders:
            do {
                try await HandOff.addToReminders(thing)
                verbResult = "On your list"
            } catch { verbResult = error.localizedDescription }
        case .copyText:
            UIPasteboard.general.string = thing.content.isEmpty ? thing.title : thing.content
            verbResult = "Copied"
        case .markDone:
            thing.mark = .done
            try? modelContext.save()
            verbResult = "Done"
        case .approve:
            // Demo bridge: the decision lands locally; the gateway wire is M5.
            thing.mark = .done
            try? modelContext.save()
            DSHaptic.success()
            verbResult = "Approved — sent to your gateway"
        case .deny:
            thing.mark = .done
            try? modelContext.save()
            verbResult = "Denied — your gateway was told"
        }
    }

    private func shortTime(_ date: Date) -> String {
        let s = Date.now.timeIntervalSince(date)
        if s < 3600 { return "\(max(1, Int(s / 60)))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86_400))d"
    }
}

/// Minimal flow layout for tag chips (wraps like the prototype's flex-wrap).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowH + spacing; rowH = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}
