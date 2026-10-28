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

    /// How many of the conversation's opening turns this box draws — the
    /// first ask and the first reply, when they lead it — so the transcript
    /// under the tiles starts after them (the sweep's P7).
    static func turnsDrawn(_ reading: AgentSheet.Conversation) -> Int {
        let ask = reading.turns.firstIndex { $0.voice == .you }
        let reply = reading.turns.firstIndex { $0.voice == .assistant }
        var n = 0
        while n < reading.turns.count, n == ask || n == reply { n += 1 }
        return n
    }

    private static func flat(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - A chat with a person

struct ChatTranscriptBox: View {
    let thing: Thing

    /// The network, how much and the day. The messages stand under the
    /// tiles, whole (prd §1578): two of them here were cut to two lines and
    /// drawn nowhere else, and stood above the chat they end.
    var body: some View {
        if thing.isLive {
            HStack(spacing: DS.Space.s2) {
                BridgeIcon(name: thing.source, size: DS.Face.row, circular: true)
                Text(verbatim: metaLine)
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        FeedScreen.dayWord(thing.capturedAt)
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

// MARK: - What the box drew

/// WHAT A SHEET'S BOX ALREADY DREW, handed to the body under the tiles so the
/// two never draw the same thing (the redundancy sweep, 2026-10-16): the
/// picture once, a chat's turns once, the words once, a contact's face once.
/// `postLeadPictureDrawn` was the first of these; this is the rest of them.
struct SheetBoxDrawn: Equatable {
    /// The box drew the thing's picture.
    var picture = false
    /// The sentences the box set — its statement, its words, its headline. A
    /// body paragraph equal to one of them is not drawn again.
    var words: [String] = []
    /// An agent chat's opening turns the box drew (the ask and the reply's
    /// first words), so the transcript under the tiles starts after them.
    var firstTurns = 0
    /// A contact's face and role line stand in the box; the card under the
    /// tiles is their numbers and addresses alone.
    var person = false
}

private struct SheetBoxDrawnKey: EnvironmentKey {
    static let defaultValue = SheetBoxDrawn()
}

extension EnvironmentValues {
    var sheetBoxDrawn: SheetBoxDrawn {
        get { self[SheetBoxDrawnKey.self] }
        set { self[SheetBoxDrawnKey.self] = newValue }
    }
}

/// The plain frame's share of `SheetBoxDrawn`: the sheet says it drew the
/// plain frame through `linkInBox` (prd §1258), so this reads that and adds
/// what `ThingSheetBox` drew — and tells a post's body its picture is in the
/// box, as `PostSheetBox` does (a TikTok, a Pinterest pin).
struct PlainBoxDrawn: ViewModifier {
    let thing: Thing
    let drawn: SheetBoxDrawn
    @Environment(\.linkInBox) private var plainFrame

    func body(content: Content) -> some View {
        var all = drawn
        if plainFrame {
            let box = ThingSheetBox.drawn(thing)
            all.picture = all.picture || box.picture
            all.words += box.words
            all.person = all.person || box.person
        }
        return content
            .environment(\.sheetBoxDrawn, all)
            .environment(\.postLeadPictureDrawn, PostSheetBox.picturesTheBox(thing) || all.picture)
    }
}

enum SheetRepeat {
    /// A sentence reduced to what it says, for comparing a head with a body:
    /// case, surrounding space and closing punctuation do not make it new.
    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?…:;,").union(.whitespaces))
            .lowercased()
    }

    /// The body without its opening paragraphs or sentences that only restate
    /// a head (`heads`: the title, the box's headline, its words). A Linear
    /// issue's description opens with the issue's own title; a Slack message
    /// with the channel the box already named.
    static func dropping(_ text: String, heads: [String]) -> String {
        let keys = Set(heads.map(normalized).filter { !$0.isEmpty })
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keys.isEmpty else { return rest }
        while !rest.isEmpty {
            // A whole first paragraph…
            let para = rest.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            if keys.contains(normalized(String(para[0]))) {
                rest = para.count > 1 ? String(para[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
                continue
            }
            // …or the first sentence of it.
            if let end = rest.range(of: #"[.!?](\s+)"#, options: .regularExpression),
               end.lowerBound < (rest.firstIndex(of: "\n") ?? rest.endIndex),
               keys.contains(normalized(String(rest[..<end.lowerBound]))) {
                rest = String(rest[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            break
        }
        return rest
    }
}

// MARK: - Anything else

struct ThingSheetBox: View {
    let thing: Thing
    /// Under the centred head (prd §1397): the head is the face, the name
    /// and the app with the day, so the box draws none of them again and
    /// takes its own height under the tiles.
    var headed: Bool = false

    private static let artHeight: CGFloat = 96

    var body: some View {
        if thing.isLive {
            if thing.kind == .file, FileFirstPage.isDocument(thing.sourceRef),
               thing.previewImageData != nil {
                documentBox
            } else if thing.kind == .contact {
                contactBox
            } else {
                plainBox
            }
        }
    }

    // MARK: The plain frame's words, decided once for the box and the sheet

    /// What the title said after its seam (§915): "Failed", "Dataset", "4
    /// missed in a row". The title row shows the name alone, so the line half
    /// is the box's statement, or it is said nowhere. A file's dash is its
    /// own, never the seam.
    static func statement(_ thing: Thing) -> String? {
        guard thing.kind != .file else { return nil }
        let line = TitleSeam.split(thing.title).line?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (line ?? "").isEmpty ? nil : line
    }

    /// What it says beyond its title: the summary, else words that are not
    /// the title, the statement or a bare link. Never a raw URL.
    static func words(_ thing: Thing) -> String? {
        let heads = [thing.title, TitleSeam.split(thing.title).name, statement(thing) ?? ""]
            .map(SheetRepeat.normalized)
        for raw in [thing.summary, thing.content] {
            let words = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !words.isEmpty, !heads.contains(SheetRepeat.normalized(words)),
                  !isBareLink(words) else { continue }
            return words
        }
        return nil
    }

    /// A body that is one URL and nothing else: plumbing, not prose.
    static func isBareLink(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.contains(where: \.isWhitespace)
            && (t.hasPrefix("http://") || t.hasPrefix("https://") || Capture.detectURL(in: t) != nil)
    }

    /// NOTHING BUT ITS TITLE (P10): no picture, no statement, no words. The
    /// box then carries the title at the headline rung, never an empty well,
    /// and the title row says where it is from, so nothing is said twice.
    static func carriesTitle(_ thing: Thing) -> Bool {
        thing.kind != .file && thing.kind != .contact && !ArticleSheetHead.hasArt(thing)
            && statement(thing) == nil && words(thing) == nil
    }

    /// The plain frame's title row: the thing's name, else (when the box
    /// carries the name) the app it is from.
    static func frameTitle(_ thing: Thing) -> String {
        if thing.kind == .file { return thing.title }
        if carriesTitle(thing) { return BridgeCatalog.seatName(forSource: thing.source) }
        return TitleSeam.split(thing.title).name
    }

    /// What this box draws, for the body under the tiles.
    static func drawn(_ thing: Thing) -> SheetBoxDrawn {
        guard thing.isLive else { return SheetBoxDrawn() }
        if thing.kind == .contact {
            return SheetBoxDrawn(picture: true, words: [thing.summary ?? ""].filter { !$0.isEmpty },
                                 person: true)
        }
        if thing.kind == .file, FileFirstPage.isDocument(thing.sourceRef), thing.previewImageData != nil {
            return SheetBoxDrawn(picture: true)
        }
        var said: [String] = []
        if let s = statement(thing) { said.append(s) }
        if let w = words(thing) { said.append(w) }
        if carriesTitle(thing) { said.append(thing.title) }
        return SheetBoxDrawn(picture: ArticleSheetHead.hasArt(thing), words: said)
    }

    /// The link tile is named for where it lands (prd §364): "Open in GitHub"
    /// when the page is the app's own, else "Open link" — never a bare
    /// "Open", which says nothing about where you go.
    static func openLabel(for url: URL, thing: Thing) -> String {
        if let app = landingApp(url, source: thing.source) {
            return String(localized: "Open in \(app)")
        }
        return String(localized: "Open link")
    }

    /// The catalogue app a URL belongs to: the row's own app when the host is
    /// its domain ("polar.sh" for Polar, "app.dodopayments.com" for Dodo
    /// Payments), else the app whose declared hosts serve it.
    static func landingApp(_ url: URL, source: String) -> String? {
        guard var host = url.host()?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let labels = host.split(separator: ".").map(String.init)
        let seat = BridgeCatalog.seatName(forSource: source)
        let squash: (String) -> String = { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
        let names = Set([squash(source), squash(seat)].filter { $0.count >= 1 })
        // The registrable label, and every label left of it ("explorer.
        // testnet.lez.logos.co" names Logos at "logos").
        if labels.count >= 2, labels.dropLast().contains(where: { names.contains($0) }) {
            return seat
        }
        if let service = NetworkReach.service(forHost: host),
           BridgeCatalog.offer(forSource: service) != nil {
            return BridgeCatalog.seatName(forSource: service)
        }
        return nil
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

    /// A CONTACT IS ONE CARD (the sweep's contact, "name 3×, face 2×"): the
    /// name is the title, the face and what they do stand in the box, and the
    /// card under the tiles is their numbers and addresses alone.
    private var contactBox: some View {
        let role = thing.factList.filter { $0.label == "Role" || $0.label == "Company" }
            .map(\.value).joined(separator: " · ")
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            if !headed {
                PersonFace(name: thing.title, photo: thing.previewImageData, size: 76)
            }
            if !role.isEmpty {
                Text(verbatim: role)
                    .dsText(.heading20)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !headed {
                Spacer(minLength: 0)
                Text(verbatim: "\(thing.source) · \(FeedScreen.dayWord(thing.capturedAt))")
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: headed ? nil : .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private var plainBox: some View {
        let pictured = ArticleSheetHead.hasArt(thing)
        let statement = Self.statement(thing)
        let words = Self.words(thing)
        let carries = Self.carriesTitle(thing)
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            if pictured {
                // The picture takes the box when there is nothing to say
                // under it; a line or words keep it a band.
                art
                    .frame(minHeight: Self.artHeight,
                           maxHeight: headed ? ThingSheetView.sheetArtHeight
                               : statement == nil && words == nil ? .infinity : Self.artHeight)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget / 2, style: .continuous))
            } else if !headed {
                BridgeIcon(name: thing.source, size: DS.Face.seat, circular: true)
            }
            // The row's own sentence at the headline rung: the title's line
            // half, else (nothing else to say) the title itself. Never a host.
            if let headline = statement ?? (carries ? TitleSeam.split(thing.title).name : nil) {
                Text(verbatim: headline)
                    .dsText(pictured ? .heading20 : .heading24)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(pictured ? 2 : 4)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let words {
                Text(verbatim: words)
                    .dsText(statement == nil && !pictured ? .body17 : .subhead12)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(statement == nil ? 4 : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !headed {
                if pictured || statement != nil || words != nil || carries {
                    Spacer(minLength: 0)
                }
                // The title row names the app when the box carries the title.
                Text(verbatim: carries ? FeedScreen.dayWord(thing.capturedAt)
                                       : "\(thing.source) · \(FeedScreen.dayWord(thing.capturedAt))")
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: headed ? nil : .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var art: some View {
        if thing.previewImageData != nil {
            PhotoWell(thing: thing)
        } else if let url = thing.previewImageURL, !url.isEmpty {
            GeometryReader { geo in
                RemoteArt(urlString: url, width: geo.size.width,
                          height: geo.size.height, cornerRadius: 0)
            }
        }
    }
}

/// A person's face: their photo in a circle, else their initials.
struct PersonFace: View {
    let name: String
    let photo: Data?
    var size: CGFloat = 76

    private var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    var body: some View {
        if let photo, let image = UIImage(data: photo) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                // Pinned before the clip: a bare resizable image expands its
                // stack to the image's own size.
                .frame(width: size, height: size)
                .clipShape(Circle())
                .accessibilityLabel(Text(verbatim: name))
        } else {
            Text(verbatim: initials)
                .dsText(.heading24)
                .foregroundStyle(DS.textPrimary)
                .frame(width: size, height: size)
                .background(DS.gray100, in: Circle())
                .accessibilityLabel(Text(verbatim: name))
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
