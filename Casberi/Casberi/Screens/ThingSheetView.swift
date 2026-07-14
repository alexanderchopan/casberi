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
    /// A bridge's no must READ as a no — green success styling on a failure
    /// would claim a write that didn't happen (honesty rule).
    @State private var verbResultIsError = false
    @State private var relatedStream = GenStream()
    /// "Related" for tag overlap; "In your things" when a watched token's
    /// shelf holds the corpus things that mention it (2026-07-14).
    @State private var relatedTitle = "Related"
    @State private var renameTarget: String?
    @State private var renameDraft = ""
    @State private var deleteTarget: String?
    /// The TAGS row opens the full editor (chips, rename, delete) in place.
    @State private var editingTags = false
    /// The hue wash pours in on open (delight 2026-07-13) — once per sheet.
    @State private var washPoured = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Seeded by the record's shape (2026-07-13 polish): a TALL thing (media
    /// or a long body) still opens FULL-height so its verbs never start
    /// below the fold — the original `.large` ruling, kept for the case that
    /// earned it. A short record opens `.medium` instead of one card of
    /// content over a screen of black. Both detents stay a drag away.
    @State private var detent: PresentationDetent

    init(thing: Thing, focusTags: Bool = false) {
        self.thing = thing
        self.focusTags = focusTags
        let hasMedia = thing.kind == .screenshot
            || !(thing.previewImageURL ?? "").isEmpty
            || TokenChart.route(from: thing.content) != nil
        _detent = State(initialValue:
            hasMedia || thing.content.count > 280 ? .large : .medium)
    }

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
                let contentShown = thing.kind != .event
                    && thing.content.trimmingCharacters(in: .whitespacesAndNewlines)
                        != thing.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if contentShown {
                    ThingContentView(thing: thing)
                        .padding(.top, DS.Space.s3)
                }
                specTable(contentShown: contentShown)
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
            if let hue = DS.washHue(for: thing.source) {
                // Bold, not a film (user ruling 2026-07-13): the crown IS
                // the source's color, flowing into the sheet's ink.
                LinearGradient(stops: [
                    .init(color: hue, location: 0),
                    .init(color: hue, location: 0.3),
                    .init(color: hue.opacity(0), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                    .frame(height: 300)
                    // The pour (delight 2026-07-13): the bleed slides down
                    // into place as the sheet opens — a bleed that literally
                    // bleeds in. Once per open; instant under Reduce Motion.
                    .opacity(washPoured ? 1 : 0)
                    .offset(y: washPoured ? 0 : -140)
                    .frame(maxHeight: .infinity, alignment: .top)
                    // TOP only: the wash bleeds under the notch, but ignoring
                    // the BOTTOM edge too let the scroll content run under the
                    // home indicator, clipping the last actions on hue'd sheets.
                    .ignoresSafeArea(edges: .top)
                    .onAppear {
                        if reduceMotion { washPoured = true } else {
                            withAnimation(.easeOut(duration: 0.35).delay(0.05)) {
                                washPoured = true
                            }
                        }
                    }
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

    private func specTable(contentShown: Bool) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if thing.kind == .event, !thing.content.isEmpty {
                specRow("When", thing.content)
            }
            // Tokens' content URL is plumbing (the chart's technical
            // dependency, not a site the person browsed to) — the native
            // TokenChartView above already carries the read; a "Site" row
            // would just leak that dependency's brand under the "Tokens"
            // eyebrow (report 2026-07-13). And when the link preview card is
            // on screen its footer already names the host — repeating it here
            // read as a stutter (2026-07-13 polish). Keyed to the content
            // view's OWN branch fact (a token/Kalshi link renders a chart,
            // no host footer — the Site row must stay for those).
            if thing.kind == .link, thing.source != "Tokens",
               !(contentShown && ThingContentView.showsLinkPreview(thing)),
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
        // One quiet card (2026-07-13 polish): the bare rows floated in the
        // sheet's field; the same faint fill the link preview wears gathers
        // them into one readable spec block.
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    private func specRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(LocalizedStringKey(label))
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
                .frame(width: 80, alignment: .leading)
            // Callout, not body — the values were the loudest type on the
            // sheet ("saved by you" outweighed the title's own facts).
            Text(LocalizedStringKey(value))
                .dsText(.callout15).foregroundStyle(DS.textPrimary)
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
                    .dsText(.callout15).foregroundStyle(DS.textTertiary)
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
        return line.font(.system(size: 15))
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
                    .dsText(.subhead13)
                    .foregroundStyle(verbResultIsError ? DS.attention : DS.confirm)
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
                Text(LocalizedStringKey(relatedTitle))
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .padding(.horizontal, DS.Space.s4)
            }
            GenRender(id: "root", els: relatedStream.els)
        }
    }

    private func streamRelated() {
        // A thing that can't have related items costs no fetch — the old
        // invariant, kept: only a watched token (mentions) or a tagged thing
        // (overlap) has anything to look for.
        let typeTags = Set(ThingKind.allCases.map(\.typeTag))
        let myTags = Set(thing.tags).subtracting(typeTags)
        let isToken = thing.source == "Tokens"
        guard isToken || !myTags.isEmpty else { return }

        var descriptor = FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 300   // relatedness lives in the recent past
        let all = (try? modelContext.fetch(descriptor)) ?? []

        // A watched token's relatedness is MENTION, not tags (2026-07-14) —
        // every watchlist thing shares the Watchlist tag, so tag overlap only
        // ever surfaced the other watched tokens. The saves, chats, and
        // screenshots that name this token answer the question a watchlist
        // can't: why am I watching this? Tag overlap stays as the fallback.
        let mentions = isToken ? tokenMentions(in: all) : []
        let related: [Thing]
        if !mentions.isEmpty {
            relatedTitle = "In your things"
            related = mentions
        } else {
            guard !myTags.isEmpty else { return }
            related = Array(all.filter { other in
                other.id != thing.id && !myTags.isDisjoint(with: other.tags)
            }.prefix(6))
        }
        guard !related.isEmpty else { return }

        var doc = ["root = Shelf([\(related.indices.map { "c\($0)" }.joined(separator: ", "))])"]
        for (i, t) in related.enumerated() {
            let title = t.title.replacingOccurrences(of: "\"", with: "")
            doc.append("c\(i) = Chip(\"\(t.source)\", \"\(title)\")")
        }
        relatedStream.stream(doc)
    }

    /// Corpus things that MENTION this watched token — a cashtag ($PEPE,
    /// boundary-checked so $PEPE never claims $PEPEX) or the token's full
    /// name as a whole word when it's distinctive (4+ characters — "Pepe"
    /// matches, a name like "Sol" would false-hit half the corpus). Other
    /// watchlist rows are excluded: they're the watchlist, not context.
    private func tokenMentions(in all: [Thing]) -> [Thing] {
        guard thing.source == "Tokens" else { return [] }
        let symbol = TokensAsk.symbol(of: thing.title)
        let name = thing.title.components(separatedBy: " · $").first ?? ""
        var patterns: [String] = []
        if !symbol.isEmpty {
            patterns.append("\\$\(NSRegularExpression.escapedPattern(for: symbol))\\b")
        }
        if name.count >= 4 {
            patterns.append("\\b\(NSRegularExpression.escapedPattern(for: name))\\b")
        }
        guard !patterns.isEmpty,
              let regex = try? NSRegularExpression(pattern: patterns.joined(separator: "|"),
                                                   options: [.caseInsensitive])
        else { return [] }
        return Array(all.filter { other in
            guard other.id != thing.id, other.source != "Tokens" else { return false }
            let text = "\(other.title) \(other.content)"
            return regex.firstMatch(in: text, options: [],
                                    range: NSRange(text.startIndex..., in: text)) != nil
        }.prefix(6))
    }

    // MARK: - Verb execution

    private func perform(_ verb: Verb) async {
        confirmingVerb = nil
        verbResultIsError = false
        switch verb.action {
        case .openURL(let url):
            openURL(url)
        case .addToCalendar:
            do {
                try await HandOff.addToCalendar(thing)
                verbResult = "On your calendar"
            } catch { verbResult = error.localizedDescription; verbResultIsError = true }
        case .addToReminders:
            do {
                try await HandOff.addToReminders(thing)
                verbResult = "On your list"
            } catch { verbResult = error.localizedDescription; verbResultIsError = true }
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
        case .bridgeWrite(let write):
            // The consent already happened (this runs from the confirm
            // dialog); the API's answer is reported as it came.
            let outcome = await BridgeWrites.perform(write)
            verbResult = outcome.line
            verbResultIsError = !outcome.ok
            if outcome.ok {
                // The write landed at the source — the mirror settles too,
                // so the verb retires and the row reads done.
                thing.mark = .done
                try? modelContext.save()
                CorpusSignal.shared.bump()
                DSHaptic.success()
            }
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
