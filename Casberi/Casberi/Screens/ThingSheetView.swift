import SwiftUI
import SwiftData

/// The thing sheet (M4, redesigned 2026-07-07 — "Ink with Gallery grafted
/// in", user's pick): ink-black ground, no cards. The source's hue washes
/// down from the top (2026-07-10 ruling — wash + icon, the dot died), an
/// eyebrow (source icon · kind · age), the title large, the thing's media,
/// then a quiet spec table (WHEN/SITE/BY/FROM/TAGS — labels change per
/// kind). Verbs are text rows (derived, cap three; writes confirm), plus
/// Pin and Share. The tag editor keeps all its power behind a tap on the
/// TAGS row. Related streams last. Spacing does the separating — no
/// hairlines.
struct ThingSheetView: View {
    @Bindable var thing: Thing
    /// True when the Tag swipe opened the sheet — it lands scrolled to the
    /// Tags field (one sheet for everything; the swipe is just a shortcut).
    var focusTags: Bool = false
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
    /// The TAGS row opens the full editor (chips, rename, delete) in place.
    @State private var editingTags = false
    /// Open FULL-height so the actions are never below the fold — a tall thing
    /// (a long title + media + related) overflowed `.medium` and clipped its
    /// verbs. `.medium` stays reachable by dragging down for a quick peek.
    @State private var detent: PresentationDetent = .large

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                eyebrow
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s6)
                Text(thing.title)
                    .dsText(.heading34).foregroundStyle(DS.textPrimary)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s3)
                // Events speak through WHEN below; and when the content is
                // just the title again (a short note with no body beyond its
                // own headline), showing it twice reads as a stutter.
                if thing.kind != .event,
                   thing.content.trimmingCharacters(in: .whitespacesAndNewlines)
                        != thing.title.trimmingCharacters(in: .whitespacesAndNewlines) {
                    ThingContentView(thing: thing)
                        .padding(.top, DS.Space.s3)
                }
                specTable
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s6)
                if editingTags {
                    tagsField
                        .padding(.top, DS.Space.s3)
                        .id("tags")
                }
                actionRows
                    .padding(.top, DS.Space.s6)
                relatedShelf
                    .padding(.top, DS.Space.s4)
            }
            .padding(.bottom, DS.Space.s6)
        }
        .scrollIndicators(.hidden)
        .background(alignment: .top) {
            // The source's hue washes down from the top and fades into the
            // ink (ruling 2026-07-10, user: "it's gorgeous"). One fixed
            // recipe — 45% into clear over 260pt, no per-hue tuning — and
            // it sits UNDER the content as atmosphere: no ink ever depends
            // on it for contrast, which is why this wash lives while the
            // treemap fills and the banner died. Hueless sources (your own
            // notes, unknown apps) stay pure ink: the gray fallback is a
            // fill, not an identity.
            if let hue = DS.brandHue(for: thing.source) {
                LinearGradient(colors: [hue.opacity(0.45), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 260)
                    .frame(maxHeight: .infinity, alignment: .top)
                    // TOP only: the wash bleeds under the notch, but ignoring
                    // the BOTTOM edge too let the scroll content run under the
                    // home indicator, clipping the last actions on hue'd sheets.
                    .ignoresSafeArea(edges: .top)
            }
        }
        // Ink: the sheet is black in both modes, like a photo viewer — its
        // controls render dark regardless of the app's theme.
        .presentationBackground(Color.black)
        .colorScheme(.dark)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(DS.Radius.sheet)
        .onAppear {
            streamRelated()
            if focusTags {
                // Land in the tag editor — the swipe's whole point.
                editingTags = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(80))
                    withAnimation(DS.Motion.standard) {
                        proxy.scrollTo("tags", anchor: .top)
                    }
                }
            }
        }
        }
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

    // MARK: - Eyebrow (source icon · kind · age)

    private var eyebrow: some View {
        HStack(spacing: DS.Space.s2) {
            // The source's own mark names the wash above it — the 6px dot
            // died with the hue ruling (2026-07-10). BridgeIcon falls back
            // to the glyph-on-hue circle for sources without a bundled
            // asset, so the seat is never empty.
            BridgeIcon(name: thing.source, size: 18, circular: true)
                // The mark coin-flips as the sheet opens (delight, 2026-07-12).
                .coinFlip(trigger: thing.id)
            Text("\(thing.kind.typeTag) · \(shortTime(thing.capturedAt)) ago")
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        }
    }

    // MARK: - Spec table (Gallery's graft — labels change per kind)

    private var specTable: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if thing.kind == .event, !thing.content.isEmpty {
                specRow("When", thing.content)
            }
            if thing.kind == .link,
               let url = Capture.detectURL(in: thing.content.isEmpty ? thing.title : thing.content),
               let host = url.host() {
                specRow("Site", host.replacingOccurrences(of: "www.", with: ""))
            }
            if let agent = thing.provenance.agent {
                specRow("By", "\(agent)\(thing.provenance.machine.map { " on \($0)" } ?? "")")
            }
            specRow("From", PlaceWords.line(for: thing))
            tagsRow
        }
    }

    private func specRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(LocalizedStringKey(label))
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
                .frame(width: 80, alignment: .leading)
            Text(LocalizedStringKey(value))
                .dsText(.body17).foregroundStyle(DS.textPrimary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    /// Tags as a text line — your own tags wear their hue; the "+" opens the
    /// full editor (chips, rename everywhere, delete everywhere) in place.
    private var tagsRow: some View {
        Button {
            withAnimation(DS.Motion.standard) { editingTags.toggle() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Tags")
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .frame(width: 80, alignment: .leading)
                tagsLine
                Text(editingTags ? "  −" : "  +")
                    .dsText(.body17).foregroundStyle(DS.textTertiary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var tagsLine: Text {
        var line = Text("")
        for (i, tag) in thing.tags.enumerated() {
            if i > 0 { line = line + Text(" · ").foregroundStyle(DS.textTertiary) }
            let isType = ThingKind.from(typeTag: tag) != nil
            line = line + Text(tag)
                .foregroundStyle(isType ? DS.textSecondary : ProjectHue.color(for: tag))
        }
        return line.font(.system(size: 17))
    }

    // MARK: - Actions (quiet text rows — verbs, then Pin, then Share)

    private var actionRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(VerbDerivation.verbs(for: thing)) { verb in
                Button {
                    if verb.isWrite {
                        confirmingVerb = verb   // writes confirm
                    } else {
                        Task { await perform(verb) }   // reads pass
                    }
                } label: {
                    actionRow(icon: verb.icon, label: verb.label)
                }
                .buttonStyle(.plain)
            }
            shareRow
            if let verbResult {
                Text(verbResult)
                    .dsText(.subhead13).foregroundStyle(DS.confirm)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s2)
            }
        }
    }

    private func actionRow(icon: String, label: String) -> some View {
        HStack(spacing: DS.Space.s4) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 26, alignment: .center)
            Text(LocalizedStringKey(label))
                .dsText(.heading17).foregroundStyle(DS.textPrimary)
            Spacer()
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s4)
        .contentShape(Rectangle())
    }

    /// The universal out-door: the system share sheet reaches every app with
    /// a share target — the only sanctioned route INTO Apple Notes, for one.
    /// A screenshot shares its actual photo, not just its title (ThingShareLink).
    private var shareRow: some View {
        ThingShareLink(thing: thing) {
            actionRow(icon: "square.and.arrow.up", label: "Share")
        }
        .buttonStyle(.plain)
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
            Text("Tags")
                .dsText(.label12)
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
        try? modelContext.save()
        // A retag changes projectClusters but not things.count — Home composes
        // a doc, not a live @Query, so nudge it to recompose (the same signal
        // HomeScreen already listens on).
        CorpusSignal.shared.bump()
        DSHaptic.success()
    }

    private func deleteEverywhere(_ tag: String) {
        deleteTarget = nil
        let all = (try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []
        for t in all where t.tags.contains(tag) {
            t.tags.removeAll { $0 == tag }
        }
        try? modelContext.save()
        CorpusSignal.shared.bump()
        DSHaptic.success()
    }

    private func add(tag: String) {
        let t = tag.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !thing.tags.contains(where: { $0.lowercased() == t.lowercased() }) else { return }
        thing.tags.append(t)
        try? modelContext.save()
        CorpusSignal.shared.bump()
    }

    private func remove(tag: String) {
        // The type tag stays — it's assigned at ingestion, not user-managed.
        guard tag != thing.kind.typeTag else { return }
        thing.tags.removeAll { $0 == tag }
        try? modelContext.save()
        CorpusSignal.shared.bump()
    }

    // MARK: - Related shelf (streams last)

    private var relatedShelf: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if !relatedStream.els.isEmpty {
                Text("Related")
                    .dsText(.label12)
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
            CorpusSignal.shared.bump()
            verbResult = "Done"
        case .approve:
            // Demo bridge: the decision lands locally; the gateway wire is M5.
            thing.mark = .done
            try? modelContext.save()
            CorpusSignal.shared.bump()
            DSHaptic.success()
            verbResult = "Approved — sent to your gateway"
        case .deny:
            thing.mark = .done
            try? modelContext.save()
            CorpusSignal.shared.bump()
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
