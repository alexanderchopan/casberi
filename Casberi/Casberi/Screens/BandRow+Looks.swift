import SwiftUI

// **A SOURCE'S ROW LOOKS LIKE ITS APP (prd §1645).** `FeedLook` decides which
// look a row wears; this draws it, in the band's own lead, column and 44pt
// head, with Casberi's type and inks. A look carries its second line on
// purpose — a sender over a subject, a post's words, a repository — so the
// Feed's title-only rule (§1497) does not reach it.
extension BandRow {

    /// The table's answer for this row. Each source's fields are read only
    /// for that source, so a row of any other app pays nothing here, and
    /// `content` is touched only by the sources whose fact lives in it.
    var feedLook: FeedLook {
        guard !imageOnly, !moneyColumn else { return .plain }
        let source = thing.source
        let social = FeedLook.postSources.contains(source)
        let outcome = WorkStage.outcome(WorkStage.Row(
            source: source, sourceRef: thing.sourceRef, title: thing.title, tags: thing.tags,
            mark: thing.mark.rawValue, projectField: thing.authorHandle, hasPrice: thing.priceValue != nil))
        let isAgent = thing.kind == .chat && AgentSheet.assistant(for: source) != nil
        let calendar = source == "Calendar"
        let handled = FeedLook.handleSources.contains(source)
        // The facts list is a decode: read it only for the two sources whose
        // look needs one.
        let factList = calendar || source == "Apple Music" ? thing.factList : []
        var facts = FeedLook.Facts(
            source: source,
            kind: thing.kind.rawValue,
            title: source == "GitHub" ? TitleSeam.split(thing.title).name : thing.title,
            content: isAgent || FeedLook.contentSources.contains(source) ? thing.content : "",
            tags: thing.tags,
            mark: thing.mark.rawValue,
            sourceRef: thing.sourceRef,
            isAgent: isAgent,
            postText: social ? thing.postText : nil,
            author: social ? SocialRoomSource.author(of: thing) : nil,
            socialContext: social ? thing.socialContext : nil,
            contextLabel: social ? SocialThread.contextLabel(for: thing) : nil,
            mailSender: FeedLook.mailSources.contains(source) ? mailSender : nil,
            duration: FeedLook.workoutSources.contains(source)
                ? thing.factList.first { $0.label == "Duration" }?.value : nil,
            workOutcome: outcome.map { FeedLook.Status(word: $0.0, tone: FeedLook.Tone(rawValue: $0.1.rawValue) ?? .neutral) },
            hasPrice: thing.priceValue != nil)
        if calendar {
            facts.start = thing.capturedAt
            facts.end = thing.endAt
            facts.allDay = factList.contains { $0.action == .allDay }
            facts.cancelled = factList.contains { $0.action == .state && $0.value == String(localized: "Cancelled") }
        }
        if handled {
            facts.authorHandle = thing.authorHandle
            facts.summary = thing.summary
            facts.dueAt = thing.dueAt
        }
        if source == "Apple Music" {
            facts.length = factList.first { $0.label == "Length" }?.value
        }
        return FeedLook.of(facts)
    }

    @ViewBuilder
    func lookRow(_ look: FeedLook) -> some View {
        HStack(alignment: look.isTall ? .top : .center, spacing: DS.Space.s3) {
            if groupedSource == nil {
                if case let .file(_, type, _) = look {
                    FileTypeMark(type: type)
                } else {
                    leaderView
                        .frame(width: DS.Mark.row, height: DS.Mark.row)
                }
            }
            lookBody(look)
        }
        .frame(minHeight: DSFeed.headHeight)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func lookBody(_ look: FeedLook) -> some View {
        switch look {
        case .plain:
            EmptyView()
        case .agentAsk(let question):
            DSChatBubble(feedText: question, fromSelf: true)
        case let .post(name, context, words):
            VStack(alignment: .leading, spacing: 2) {
                (Text(verbatim: name).fontWeight(.semibold)
                 + Text(verbatim: context.map { " · " + $0 } ?? "").foregroundStyle(DS.textSecondary))
                    .dsText(.body17)
                    .lineLimit(1)
                Text(verbatim: words)
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case let .mail(who, what), let .byline(who, what):
            // A publication over its headline is mail's look (prd §1648).
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: who)
                    .dsText(.body17).fontWeight(.semibold)
                    .lineLimit(1)
                Text(verbatim: what)
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case let .code(title, place, state):
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .dsText(.body17)
                    .lineLimit(1)
                Text(verbatim: place)
                    .dsText(.subhead12).monospaced()
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let state { statusWord(state) }
        case let .workout(name, figure, duration):
            Text(verbatim: name)
                .dsText(.body17)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: figure)
                .dsText(.body17).fontWeight(.semibold).monospacedDigit()
            if let duration {
                Text(verbatim: duration)
                    .dsText(.subhead12).monospacedDigit()
                    .foregroundStyle(DS.textSecondary)
            }
        case let .file(name, _, size):
            Text(verbatim: name)
                .dsText(.body17)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let size {
                Text(verbatim: size)
                    .dsText(.subhead12).monospacedDigit()
                    .foregroundStyle(DS.textSecondary)
            }
        case let .status(title, status):
            Text(verbatim: title)
                .dsText(.body17)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            statusWord(status)
        case let .event(title, start, end, allDay, place, cancelled):
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .dsText(.body17)
                    .foregroundStyle(cancelled ? DS.textTertiary : DS.textPrimary)
                    .strikethrough(cancelled, color: DS.textTertiary)
                    .lineLimit(1)
                eventLine(start: start, end: end, allDay: allDay, place: place, cancelled: cancelled)
                    .dsText(.subhead12)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case let .quote(passage, from):
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s1) {
                    Text(verbatim: "“")
                        .dsText(.heading24)
                        .foregroundStyle(DS.brandInk)
                        .accessibilityHidden(true)
                    Text(verbatim: passage)
                        .dsText(.body17)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(verbatim: from)
                    .dsText(.subhead12)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case let .review(title, by, stars):
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .dsText(.body17)
                    .lineLimit(1)
                if let by {
                    Text(verbatim: by)
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 1) {
                ForEach(0..<5, id: \.self) { i in
                    Image(systemName: "star.fill")
                        .dsGlyph(.caption, weight: .regular)
                        .foregroundStyle(i < stars ? DS.textPrimary : DS.fillStrong)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(stars) of 5 stars"))
        case let .figure(title, line, figure, style):
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .dsText(.body17)
                    .lineLimit(1)
                if let line {
                    Text(verbatim: line)
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            figureText(figure, style: style)
        }
    }

    /// "14:00–15:00 · Studio 3", "All day", or "Cancelled · 12:30" with the
    /// word in its ink. The hours are the time the row is about, so they
    /// stand in the primary ink, the place after them in the line's.
    private func eventLine(start: Date, end: Date?, allDay: Bool, place: String?, cancelled: Bool) -> Text {
        let clock = Date.FormatStyle(date: .omitted, time: .shortened)
        let hours: String = allDay ? String(localized: "All day")
            : end.map { "\(start.formatted(clock))–\($0.formatted(clock))" } ?? start.formatted(clock)
        var out = cancelled
            ? Text(String(localized: "Cancelled")).fontWeight(.semibold).foregroundStyle(DS.destructiveInk)
                + Text(verbatim: " · " + hours)
            : Text(verbatim: hours).fontWeight(.semibold).foregroundStyle(DS.textPrimary)
        if let place { out = out + Text(verbatim: " · " + place) }
        return out
    }

    @ViewBuilder
    private func figureText(_ figure: String, style: FeedLook.FigureStyle) -> some View {
        switch style {
        case .bold:
            Text(verbatim: figure)
                .dsText(.body17).fontWeight(.semibold).monospacedDigit()
                .lineLimit(1)
        case .code:
            Text(verbatim: figure)
                .dsText(.body17).monospaced()
                .lineLimit(1)
        case .quiet:
            Text(verbatim: figure)
                .dsText(.subhead12).monospacedDigit()
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
        case .attention:
            Text(verbatim: figure)
                .dsText(.subhead12).fontWeight(.semibold).monospacedDigit()
                .foregroundStyle(DS.attentionInk)
                .lineLimit(1)
        }
    }

    /// A status WORD takes its ink (§1004): red broke, amber waits on you,
    /// green landed, a word with no verdict stays grey.
    private func statusWord(_ status: FeedLook.Status) -> some View {
        Text(verbatim: status.word)
            .dsText(.subhead12).fontWeight(.semibold)
            .foregroundStyle(Self.ink(status.tone))
            .lineLimit(1)
    }

    static func ink(_ tone: FeedLook.Tone) -> Color {
        switch tone {
        case .failed:  DS.destructiveInk
        case .waiting: DS.attentionInk
        case .landed:  DS.confirmInk
        case .neutral: DS.textSecondary
        }
    }
}

extension FeedLook {
    /// A look whose words run past one line stands its lead at the top.
    var isTall: Bool {
        switch self {
        case .post, .mail, .code, .byline, .quote: true
        default: false
        }
    }
}

/// A file's type as Finder shows it (prd §1645): a page with its extension,
/// at the row lead's size. Drawn, never an app's artwork.
struct FileTypeMark: View {
    let type: String

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(DS.fillStrong)
                .frame(width: DS.Mark.row * 0.8, height: DS.Mark.row)
            Text(verbatim: type)
                .dsText(.dockCaption10).fontWeight(.heavy)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.bottom, 4)
                .frame(width: DS.Mark.row * 0.8)
        }
        .frame(width: DS.Mark.row, height: DS.Mark.row)
        .accessibilityHidden(true)
    }
}
