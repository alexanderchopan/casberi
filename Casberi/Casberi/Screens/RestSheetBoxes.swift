import SwiftUI

/// THE REST OF THE SHEETS IN THE ROOM'S FRAME (prd §1191, the design canvas
/// "The rest, the Apple pass"): an agent chat, a chat with a person, a
/// journal entry, a vault note, a marked passage, and anything else. Every
/// word is the record's own — the reply's first words, the journal's day, the
/// passage — never a summary written for it.

// MARK: - An agent chat

struct AgentChatBox: View {
    let thing: Thing
    let reading: AgentSheet.Conversation

    var body: some View {
        if thing.isLive {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                HStack(spacing: DS.Space.s2) {
                    BridgeIcon(name: thing.source, size: DS.Face.row, circular: true)
                    Text(verbatim: metaLine)
                        .dsText(.label12)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                if let asked {
                    Text(verbatim: asked)
                        .dsText(.heading20)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if let answer {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: answer.name)
                            .dsText(.label12)
                            .foregroundStyle(DS.textSecondary)
                        Text(verbatim: answer.text)
                            .dsText(.body17)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(3)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
        }
    }

    /// "Claude Code · casberi · 12 turns · Tuesday".
    private var metaLine: String {
        let n = reading.counted ?? reading.turns.count
        return [thing.source, reading.project, String(localized: "\(n) turns"),
                FeedScreen.dayWord(thing.capturedAt)]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The first thing you asked.
    private var asked: String? {
        reading.turns.first { $0.voice == .you }.map { Self.flat($0.text) }
    }

    /// The reply's first words, in the agent's own name.
    private var answer: (name: String, text: String)? {
        reading.turns.first { $0.voice == .assistant }.map { ($0.name, Self.flat($0.text)) }
    }

    private static func flat(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - A chat with a person

struct ChatTranscriptBox: View {
    let thing: Thing

    var body: some View {
        if thing.isLive {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack(spacing: DS.Space.s2) {
                    BridgeIcon(name: thing.source, size: DS.Face.row, circular: true)
                    Text(verbatim: metaLine)
                        .dsText(.label12)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                ForEach(Array(lastExchange.enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line.words)
                        .dsText(.body17)
                        .foregroundStyle(line.mine ? Color.white : DS.textPrimary)
                        .lineLimit(2)
                        .padding(.horizontal, DS.Space.s3)
                        .padding(.vertical, DS.Space.s2)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(line.mine ? DS.tint : DS.fillStrong))
                        .frame(maxWidth: .infinity, alignment: line.mine ? .trailing : .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
        }
    }

    /// "Snapchat · 214 messages · since Mar 2024".
    private var metaLine: String {
        var parts = [thing.source]
        if let n = thing.messageCount, n > 0 { parts.append(String(localized: "\(n) messages")) }
        parts.append(FeedScreen.dayWord(thing.capturedAt))
        return parts.joined(separator: " · ")
    }

    /// The last two lines of the transcript, who said each.
    private var lastExchange: [(words: String, mine: Bool)] {
        let lines = thing.content.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.suffix(2).map { line in
            let said = ChatBubbles.speaker(of: line)
            return (said.words, said.name.map(ChatBubbles.isMine) ?? false)
        }
    }
}

// MARK: - A journal entry

struct JournalEntryBox: View {
    let thing: Thing
    /// How many other things the corpus holds from the entry's day.
    let sameDay: Int
    var onPhoto: (() -> Void)? = nil

    var body: some View {
        if thing.isLive {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text(verbatim: thing.source)
                        .dsText(.label12)
                        .foregroundStyle(DS.textSecondary)
                    Text(verbatim: dayWords)
                        .dsText(.heading28)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(verbatim: whenLine)
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if sameDay > 0 {
                        DSStamp(word: sameDay == 1 ? String(localized: "1 thing that day")
                                                   : String(localized: "\(sameDay) things that day"))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if thing.previewImageData != nil {
                    Button { onPhoto?() } label: {
                        PhotoWell(thing: thing)
                            .frame(width: 128)
                            .frame(maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget / 2, style: .continuous))
                    }
                    .buttonStyle(PressSpring())
                    .accessibilityLabel(Text("The entry's picture"))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// "Sunday, Sep 21".
    private var dayWords: String {
        thing.capturedAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    /// "9:00 PM · Lyon · 14°, clear" — the place and the weather only when the
    /// journal kept them as facts.
    private var whenLine: String {
        var parts = [thing.capturedAt.formatted(date: .omitted, time: .shortened)]
        for label in [String(localized: "Place"), String(localized: "Weather")] {
            if let value = thing.factList.first(where: { $0.label == label })?.value, !value.isEmpty {
                parts.append(value)
            }
        }
        if let minutes = ArticleSheetHead.readingMinutes(thing) {
            parts.append(String(localized: "\(minutes) min read"))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - A marked passage

struct PassageBox: View {
    let passage: String
    let author: String?
    let line: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text(verbatim: "\u{201C}\(passage)\u{201D}")
                .dsText(.heading20)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            Text(verbatim: line)
                .dsText(.label12)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    /// A passage too long for the box's six lines is set whole under the tiles.
    static func cuts(_ passage: String) -> Bool { passage.count > 220 }
}

// MARK: - A vault note

struct VaultNoteBox: View {
    let thing: Thing
    let tags: [String]

    var body: some View {
        if thing.isLive {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                HStack(spacing: DS.Space.s2) {
                    BridgeIcon(name: thing.source, size: DS.Face.row, circular: true,
                               symbol: BridgeIcon.noteSymbol(for: thing))
                    Text(verbatim: thing.source)
                        .dsText(.label12)
                        .foregroundStyle(DS.textSecondary)
                }
                Text(String(localized: "Edited \(FeedScreen.dayWord(thing.capturedAt))"))
                    .dsText(.heading24)
                    .foregroundStyle(DS.textPrimary)
                Text(verbatim: thing.capturedAt.formatted(date: .omitted, time: .shortened))
                    .dsText(.subhead12)
                    .foregroundStyle(DS.textSecondary)
                Spacer(minLength: 0)
                if !tags.isEmpty {
                    HStack(spacing: DS.Space.s2) {
                        ForEach(tags.prefix(3), id: \.self) { DSStamp(word: $0) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Anything else

struct ThingSheetBox: View {
    let thing: Thing

    /// A plain link's site, said big when there is no picture.
    private var host: String? {
        let raw = thing.externalLink ?? thing.content
        guard raw.hasPrefix("http"), let url = URL(string: raw), var h = url.host else { return nil }
        if h.hasPrefix("www.") { h.removeFirst(4) }
        return h
    }

    private static let artHeight: CGFloat = 96

    var body: some View {
        if thing.isLive {
            if thing.kind == .file, FileFirstPage.isDocument(thing.sourceRef),
               thing.previewImageData != nil {
                documentBox
            } else {
                plainBox
            }
        }
    }

    /// A document (prd §1192): its first page beside what it is — the app,
    /// the kind, the page count, the folder it is in, and the day.
    private var documentBox: some View {
        HStack(alignment: .top, spacing: DS.Space.s4) {
            PhotoWell(thing: thing)
                .frame(width: 152)
                .frame(maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget / 2, style: .continuous))
                .accessibilityLabel(Text("First page"))
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                HStack(spacing: DS.Space.s2) {
                    BridgeIcon(name: thing.source, size: DS.Face.badge, circular: true)
                    Text(verbatim: thing.source)
                        .dsText(.label12)
                        .foregroundStyle(DS.textSecondary)
                }
                Text(verbatim: kindWord)
                    .dsText(.heading20)
                    .foregroundStyle(DS.textPrimary)
                    .padding(.top, DS.Space.s2)
                if let pages = thing.factList.first(where: { $0.label == FileFirstPage.pagesLabel })?.value {
                    Text(Int(pages) == 1 ? String(localized: "1 page") : String(localized: "\(pages) pages"))
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                }
                if let folder {
                    Text(String(localized: "In \(folder)"))
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(verbatim: FeedScreen.dayWord(thing.capturedAt))
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    /// "PDF", "Pages", "Word": the file's extension, said as a kind.
    private var kindWord: String {
        let ext = ((thing.sourceRef ?? thing.title) as NSString).pathExtension
        return ext.isEmpty ? String(localized: "Document") : ext.uppercased()
    }

    /// The folder it sits in, when it sits in one.
    private var folder: String? {
        guard let ref = thing.sourceRef, let colon = ref.firstIndex(of: ":") else { return nil }
        let parent = (String(ref[ref.index(after: colon)...]) as NSString).deletingLastPathComponent
        let name = (parent as NSString).lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }

    private var plainBox: some View {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                if ArticleSheetHead.hasArt(thing) {
                    art
                        .frame(height: Self.artHeight)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget / 2, style: .continuous))
                } else {
                    BridgeIcon(name: thing.source, size: DS.Face.seat, circular: true)
                }
                if let host {
                    Text(verbatim: host)
                        .dsText(ArticleSheetHead.hasArt(thing) ? .heading20 : .heading28)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if let words = summary {
                    Text(verbatim: words)
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(host == nil ? 4 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text(verbatim: "\(thing.source) · \(FeedScreen.dayWord(thing.capturedAt))")
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
    }

    /// What it says beyond its title: the summary, else words that are not
    /// the title or a link.
    private var summary: String? {
        let title = TitleSeam.split(thing.title).name
        for raw in [thing.summary, thing.content] {
            let words = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !words.isEmpty, words != title, !words.hasPrefix("http") { return words }
        }
        return nil
    }

    @ViewBuilder private var art: some View {
        if thing.previewImageData != nil {
            PhotoWell(thing: thing)
        } else if let url = thing.previewImageURL, !url.isEmpty {
            GeometryReader { geo in
                RemoteArt(urlString: url, width: geo.size.width,
                          height: Self.artHeight, cornerRadius: 0)
            }
        }
    }
}

// MARK: - Review news

/// An incident, a milestone or a revision L2BEAT or Walletbeat recorded
/// (prd §1191): what kind it is, whose reading and when, and what happened,
/// in the reviewer's words. The detail stands under the tiles.
struct ReviewNewsBox: View {
    let label: String
    let urgent: Bool
    let meta: String
    let headline: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s2) {
                if urgent {
                    Image(systemName: "exclamationmark.triangle")
                        .dsGlyph(.caption, weight: .semibold)
                        .foregroundStyle(DS.attention)
                        .accessibilityHidden(true)
                }
                Text(verbatim: label)
                    .dsText(.label12)
                    .fontWeight(.semibold)
                    .foregroundStyle(urgent ? DS.attentionInk : DS.textSecondary)
                Spacer(minLength: DS.Space.s2)
                Text(verbatim: meta)
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }
            Text(verbatim: headline)
                .dsText(.heading24)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(4)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}
