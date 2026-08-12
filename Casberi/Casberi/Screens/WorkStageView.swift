import SwiftUI

/// A Work row's hero, drawn as a receipt (2026-08-12, user: "less like a
/// database field, more like a receipt… lets pick a category and do the same,
/// start with work").
///
/// The §302 ledger's grammar, one category over: what happened, then what it
/// happened to, then where it happened — each on its own rung instead of
/// joined into one 22pt string. `WorkStage` decides every word; this file only
/// sets them, so the reasoning lives in one Foundation-only place a harness can
/// compile.
///
/// **The status line is state colour, on §302's own ruling** ("a gain wears
/// green"). Four registers, no fifth: red broke, amber is on somebody else's
/// desk, green finished well, and a row with no verdict wears plain text
/// rather than a colour implying one. The tone comes from `WorkStage.Tone`,
/// which reads stable English tags and never a localized title — so the colour
/// cannot flip when the device language changes (prd §340).
struct WorkStageView: View {
    let thing: Thing
    let reading: WorkStage.Reading
    /// The clause the title actually carried, when it said more than the
    /// status word does — PagerDuty's "Resolved after 2 hours". Passed in
    /// rather than recomputed so the view never touches the title.
    let detail: String?

    /// Liveness guard (build 188, corollary 5 — `ThingRowKeying.swift`).
    /// SwiftUI re-evaluates a leaf view's body on the model's OWN observation,
    /// independent of the parent that built it, so a guard upstream cannot
    /// protect this. Every stored-property read below sits behind it.
    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusLine
            headline.padding(.top, DS.Space.s1 - 2)
            if let project = reading.project {
                projectLine(project).padding(.top, DS.Space.s1 + 2)
            }
            // Always, and always amber (user ruling 2026-08-12: "those don't
            // need to be red tho, b/c it's not necessarily an alert for
            // someone that is bad. i think yellow is fine"). A deadline is a
            // fact about the future, not a verdict on it — a Trello card due
            // next month and a dispute due Friday are the same KIND of thing,
            // and colouring one of them as an alarm decides for the person how
            // to feel about their own calendar. The tinted strip is the
            // information; the tone stays even.
            if let due = thing.dueAt {
                deadlineStrip(due).padding(.top, DS.Space.s4)
            }
            if !pills.isEmpty {
                pillStrip.padding(.top, DS.Space.s4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Status

    private var statusLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2 - 3) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            // The detail carries the status word inside it when it exists
            // ("Resolved after 2 hours"), so the two are never printed
            // together — that duration is the most specific true thing this
            // row knows and it earns the slot outright.
            Text(verbatim: detail ?? reading.statusWord ?? "")
                .dsText(.callout15)
                .fontWeight(.semibold)
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Neutral deliberately resolves to ordinary text colour, not a hue —
    /// see the type's own doc. `DS.textSecondary`, not primary, so a verdictless
    /// status still sits UNDER the headline in the reading order.
    private var tint: Color {
        switch reading.tone {
        case .failed:  DS.destructive
        case .waiting: DS.attention
        case .landed:  DS.confirm
        case .neutral: DS.textSecondary
        }
    }

    // MARK: - Headline

    @ViewBuilder private var headline: some View {
        switch reading.face {
        case .money:  moneyHeadline
        // A star rating arrives as five glyphs that are already the verdict,
        // so the words beside them are a caption, not a claim — one rung down.
        case .stars:  wordsHeadline(.heading22)
        case .code:   codeHeadline
        case .words:  wordsHeadline(.stat24)
        }
    }

    private func wordsHeadline(_ style: DSTextStyle) -> some View {
        Text(verbatim: reading.subject)
            .dsText(style)
            .foregroundStyle(DS.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    /// An error message IS code, and setting it in the prose face makes it
    /// read as a sentence somebody wrote.
    ///
    /// `.monospaced()` over a ramp rung rather than a raw
    /// `.system(size: 19, design: .monospaced)`: the ramp carries the Dynamic
    /// Type scaling and the line height, and a hardcoded size is exactly the
    /// "froze while its neighbours grew" failure `DSTextStyle` documents. One
    /// rung down from `.stat24` because a monospaced face reads noticeably
    /// larger at the same point size, and these are the longest headlines in
    /// the category.
    private var codeHeadline: some View {
        Text(verbatim: reading.subject)
            .dsText(.heading17)
            .monospaced()
            .foregroundStyle(DS.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    /// The wallet's own hero rung, and the only Work face that gets it —
    /// money moving is the module doctrine's standing exception.
    ///
    /// Signed, and the sign follows the DIRECTION rather than the tone: a
    /// dispute takes money away from you whether it is opened, won or lost,
    /// and a payout brings it in. Green is reserved for money ARRIVING, on
    /// §302's ruling that a gain wears the colour whole; everything else stays
    /// white, because spending — or being challenged — is not a loss state and
    /// red here would editorialize twice (the status line already said it).
    private var moneyHeadline: some View {
        Text(verbatim: (moneyIncoming ? "+" : "−") + (moneyText ?? ""))
            .dsText(.price40)
            .monospacedDigit()
            .foregroundStyle(moneyIncoming ? DS.confirm : DS.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .truncationMode(.tail)
    }

    private var moneyIncoming: Bool {
        let tags = Set(thing.tags)
        return tags.contains("Payout") && !tags.contains("Failed")
            || tags.contains("Recovered")
            || tags.contains("Won")
    }

    /// Formatted from the row's OWN stored currency — never a guessed symbol.
    /// Nil (so the whole money face falls back) when the row predates the
    /// fields, which is every Stripe row landed before 2026-08-12: the cursor
    /// never re-reads an event, so those keep the words face and their title.
    private var moneyText: String? {
        guard let value = thing.priceValue, let code = thing.priceCurrency,
              !code.isEmpty
        else { return nil }
        return value.formatted(.currency(code: code))
    }

    // MARK: - Where

    private func projectLine(_ project: String) -> some View {
        Text(verbatim: project)
            .dsText(.callout15)
            .foregroundStyle(DS.textSecondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    // MARK: - Deadline

    private func deadlineStrip(_ due: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Image(systemName: "clock")
                .dsGlyph(15)
                .foregroundStyle(DS.attention)
                .accessibilityHidden(true)
            Text(verbatim: dueSentence(due))
                .dsText(.callout15)
                .foregroundStyle(DS.attention)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s3 - 2)
        .background(DS.attention.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    /// "Due Aug 19 · in 7 days" — the date AND the distance.
    ///
    /// Month and day, never a bare weekday: the Aerodrome lesson (prd, the
    /// veAERO vote window) is that "due Wed" is ambiguous for anything more
    /// than a few days out and reads as already-past exactly when it matters
    /// most. The relative half is what you actually act on, so it is said too
    /// rather than left for the reader to compute.
    private func dueSentence(_ due: Date) -> String {
        let date = due.formatted(.dateTime.month(.abbreviated).day())
        let days = Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: due)).day ?? 0
        let relative = switch days {
        case ..<0:  String(localized: "overdue")
        case 0:     String(localized: "today")
        case 1:     String(localized: "tomorrow")
        default:    String(localized: "in \(days) days")
        }
        return String(localized: "Due \(date) · \(relative)")
    }

    // MARK: - Pills

    /// The state the row is in, then the person's OWN labels — never our
    /// editorial shape marks, which `WorkStage.shapeTags` strips, because a
    /// chip repeating the status line above it in a quieter font is chrome
    /// pretending to be information.
    private var pills: [(String, Color?)] {
        var out: [(String, Color?)] = []
        // The state pill is the ONE place `Thing.mark` has ever been drawn on
        // a sheet: six Work seats write it (GitHub, GitLab, Linear, Jira,
        // Trello, Cloudflare) and until now nothing read it back.
        if thing.kind != .transaction, let state = markWord {
            out.append((state, tint))
        }
        let typeTags = Set(ThingKind.allCases.map(\.typeTag))
        for label in WorkStage.labels(
            .init(source: thing.source, title: thing.title, tags: thing.tags),
            typeTags: typeTags
        ) {
            out.append((label, nil))
        }
        return out
    }

    private var markWord: String? {
        switch thing.mark {
        case .todo:  String(localized: "Open")
        case .doing: String(localized: "In progress")
        case .done:  String(localized: "Done")
        default:     nil
        }
    }

    private var pillStrip: some View {
        // A wrapping rail, because a person's own labels are their words and
        // there is no honest cap — truncating to one line would hide the
        // label that mattered.
        FlowRail(spacing: DS.Space.s2 - 3) {
            ForEach(Array(pills.enumerated()), id: \.offset) { _, pill in
                HStack(spacing: DS.Space.s2 - 4) {
                    if let dot = pill.1 {
                        Circle().fill(dot).frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                    }
                    Text(verbatim: pill.0)
                        .dsText(.label12)
                        .foregroundStyle(pill.1 == nil ? DS.textSecondary : DS.textPrimary)
                }
                .padding(.horizontal, DS.Space.s2)
                .padding(.vertical, DS.Space.s1 + 1)
                .background(pill.1 == nil ? DS.fillFaint : DS.fillLine,
                            in: Capsule())
            }
        }
    }
}

/// A wrapping horizontal rail. `Layout` rather than a `LazyVGrid` because the
/// items are words of differing width and a grid would column them, leaving
/// ragged gaps between a two-letter label and a twenty-letter one.
struct FlowRail: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, width: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0,
                      height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        for row in layout(subviews: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layout(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        var x: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            // A single item wider than the rail still gets its own row rather
            // than being dropped.
            if !row.indices.isEmpty, x + size.width > width {
                rows.append(row)
                row = Row(y: row.y + row.height + spacing)
                x = 0
            }
            row.indices.append(index)
            x += size.width + spacing
            row.width = max(row.width, x - spacing)
            row.height = max(row.height, size.height)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
