import SwiftUI
import UIKit

/// The share card — one image of a thing, in the app's own hand, that a
/// person sends out (docs/social-spec.md section 2, 2026-09-24).
///
/// This is the app's first OUTWARD-facing surface: the card goes into a text
/// thread, a mail, a post, and is the only thing about Casberi the person on
/// the other end sees. So it is drawn on the ink sheet (the solid black
/// sheets are the identity, not the theme of the day), it carries the thing's
/// own words and never a model's (§645), and it draws no figure a reader
/// could act on — no balance, no address (§83 applied outward).
///
/// `Model` is pure and built once on the main actor from a live `Thing`;
/// the pictures are fetched after, off it; `render` turns the finished model
/// into a bitmap through `ImageRenderer`. Every dynamic colour is RESOLVED
/// against a dark trait collection before it reaches the renderer —
/// `TileDrop.image(for:)` paid for that rule: an unresolved `UIColor`-backed
/// token renders as its light variant, whatever the environment says.
enum ShareCard {

    /// Portrait 4:5 in points; rendered at 3× → 1080×1350, the size every
    /// messaging and social surface previews whole.
    static let size = CGSize(width: 360, height: 450)
    static let scale: CGFloat = 3
    /// Where the app lives, printed on every card's foot.
    static let home = "casberi.app"

    struct Model {
        /// `thing.source` — what `BridgeIcon` draws the lead from.
        let source: String
        /// The seat's spoken name, for the eyebrow.
        let sourceName: String
        /// A post leads with its author (prd §756); nil for anything else.
        let author: String?
        let day: String
        let title: String
        /// The thing's own words under the title — the full post, the lede,
        /// the content — never the permalink and never a URL on its own.
        let words: String
        /// The web link a target that takes links gets, and the body of a
        /// text or mail.
        let link: URL?
        /// The remote art to fetch, when the thing has no stored pixels.
        let artURL: String?
        /// The author's face to fetch, for a post.
        let faceURL: String?
        var picture: UIImage? = nil
        var face: UIImage? = nil
        /// A room's figure (a week's contributions, a streak) — the big
        /// number, its caption, and seven days of bars, today last. A
        /// thing's card has none of these.
        var figure: String? = nil
        var caption: String? = nil
        var bars: [Int]? = nil
        /// A workout's measurements: (value, unit), drawn as columns.
        var stats: [(String, String)] = []
        /// A highlight (prd §1020): the title is a quoted passage and the
        /// words name the page, so the statement may run long.
        var quote = false
        /// A folder's things (prd §1021), each a mark and a one-line title.
        var rows: [Row] = []
        /// The eyebrow's mark when it is not the seat's: a note's glyph in
        /// the brand pink (§976a), a folder's, a highlight's.
        var symbol: String? = nil
        /// A voice note's waveform (prd §1024): the player's 32 bars, read
        /// off the bytes after the model is built, and its length as drawn
        /// on the row ("0:42"). The card draws every bar solid: no playhead.
        var wave: [CGFloat]? = nil
        var length: String? = nil
    }

    /// One row on a folder's card.
    struct Row: Hashable {
        let source: String
        let symbol: String?
        let title: String
    }

    /// The model, or nil for a thing the sheet cannot draw (a tombstone).
    @MainActor
    static func model(for thing: Thing) -> Model? {
        guard thing.isLive else { return nil }
        if Highlight.isHighlight(thing) { return highlightModel(thing) }
        let link = ShareTargetMemo.url(for: thing)
        let handle = (thing.authorHandle ?? "").trimmingCharacters(in: .whitespaces)
        let post = (thing.postText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let isPost = !post.isEmpty && !handle.isEmpty
        let stats = workoutStats(thing)
        let body = isPost ? post : (stats.isEmpty ? bodyWords(thing, link: link) : "")
        // A post's title is `titleLine()`'s 80-character clamp of the same
        // words, so the card draws the words once, as the statement. Any
        // other title splits at its one seam (prd §915): the name is the
        // statement, the qualifier leads the words.
        let seam = TitleSeam.split(thing.title)
        let title = isPost ? "" : seam.name
        let words: String
        if isPost {
            words = body
        } else if let rest = wordsAfterName(seam.name, clampedTitle: thing.title, content: body) {
            // A title clamped off the thing's own words (a note, a pasted
            // paragraph) is a prefix of them: the name is the statement and
            // the rest of the words follow it once, never the clamp's line
            // and then the whole text again.
            words = rest
        } else {
            words = [seam.line, body].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        }
        return Model(source: thing.source,
                     sourceName: BridgeCatalog.seatName(forSource: thing.source),
                     author: isPost ? handle : nil,
                     day: thing.capturedAt.formatted(date: .abbreviated, time: .omitted),
                     title: title,
                     words: words,
                     link: link,
                     artURL: thing.previewImageURL.flatMap { $0.isEmpty ? nil : $0 },
                     faceURL: isPost ? thing.authorAvatarURL : nil,
                     picture: StoredPixels.cached(for: thing),
                     stats: stats,
                     symbol: BridgeIcon.noteSymbol(for: thing),
                     length: voiceLength(thing))
    }

    /// A highlight's card (prd §1020): the passage in quotation marks as
    /// the statement, the page it came from as the line under it, and the
    /// page's link as the second share item.
    @MainActor
    private static func highlightModel(_ thing: Thing) -> Model {
        let passage = thing.content.trimmingCharacters(in: .whitespacesAndNewlines)
        var from = Highlight.originTitle(of: thing).map { TitleSeam.split($0).name } ?? ""
        if let origin = thing.modelContext.flatMap({ Highlight.origin(of: thing, context: $0) }) {
            let seat = BridgeCatalog.seatName(forSource: origin.source)
            from = [seat, TitleSeam.split(origin.title).name].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return Model(source: thing.source,
                     sourceName: BridgeCatalog.seatName(forSource: thing.source),
                     author: nil,
                     day: thing.capturedAt.formatted(date: .abbreviated, time: .omitted),
                     title: "\u{201C}\(passage)\u{201D}",
                     words: from,
                     link: thing.externalLink.flatMap(URL.init(string:)),
                     artURL: nil, faceURL: nil, picture: nil, quote: true,
                     symbol: BridgeIcon.noteSymbol(for: thing))
    }

    /// A kept voice note's length (§987.1), off its stored span; nil for
    /// anything else, a sealed note included (its `audio` is a box, §982.6).
    static func voiceLength(_ thing: Thing) -> String? {
        guard isVoice(thing) else { return nil }
        return VoiceLength.seconds(from: thing.capturedAt, to: thing.endAt).map { VoiceLength.label($0) }
    }

    /// A voice note of yours with a recording to share.
    static func isVoice(_ thing: Thing) -> Bool {
        thing.kind == .voice && NoteSheetSource.isKeptNote(thing) && !NoteLock.isLocked(thing)
            && (thing.audio?.isEmpty == false)
    }

    /// The recording as a file for the share sheet (prd §1024): the kept
    /// `.m4a` bytes under the note's name in a temporary folder of their
    /// own. A `Transferable` case could not carry it — the sheet types every
    /// item of one `Transferable` by its first representation, so the
    /// recording went out as "2 Images" (measured) — so a voice note's
    /// Share hands the system sheet the card and this file as two items.
    static func audioFile(_ audio: Data, name: String) -> URL? {
        let safe = name.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-" + UUID().uuidString, isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil
        else { return nil }
        let url = dir.appendingPathComponent((safe.isEmpty ? "Voice note" : safe) + ".m4a")
        guard (try? audio.write(to: url)) != nil else { return nil }
        return url
    }

    /// The waveform, read off the bytes (prd §1024). Off main; nil when the
    /// bytes will not decode, and the card then draws no strip.
    static func wave(for audio: Data) async -> [CGFloat]? {
        await VoiceEnvelope.read(url: nil, data: audio)?.bars
    }

    /// A workout's measurements off its facts — `HealthIngest.workoutFacts`
    /// writes km, Duration, Pace / km and kcal as `.metric` facts, and the
    /// card draws those as columns rather than a line of prose.
    private static func workoutStats(_ thing: Thing) -> [(String, String)] {
        let facts = thing.facts.compactMap(ThingFact.init(encoded:)).filter { $0.action == .metric }
        guard !facts.isEmpty else { return [] }
        let order = ["km", "Duration", "Pace / km", "kcal"]
        return order.compactMap { label in
            facts.first { $0.label == label }.map { ($0.value, label == "Pace / km" ? "/km" : label) }
        }
    }

    /// The words after the name, when the title is a clamp of `content`
    /// (its text up to the ellipsis is where the content starts); nil
    /// otherwise, so a title that says something the words don't keeps it.
    static func wordsAfterName(_ name: String, clampedTitle: String, content: String) -> String? {
        var stem = clampedTitle.trimmingCharacters(in: .whitespaces)
        for tail in ["…", "..."] where stem.hasSuffix(tail) {
            stem = String(stem.dropLast(tail.count)).trimmingCharacters(in: .whitespaces)
        }
        guard !stem.isEmpty, stem != clampedTitle || content.count > stem.count,
              content.hasPrefix(stem), content.hasPrefix(name) else { return nil }
        var rest = Substring(content.dropFirst(name.count))
        rest = rest.drop { $0.isWhitespace || $0 == "—" || $0 == "–" || $0 == "-" || $0 == "·" }
        return String(rest).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The words under a title. `content` is the row's own words, except
    /// where it is nothing but the link the card already carries.
    private static func bodyWords(_ thing: Thing, link: URL?) -> String {
        var content = thing.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return "" }
        if let link, content == link.absoluteString { return "" }
        if content.lowercased().hasPrefix("from ") && thing.kind == .mail { return "" }
        // A screenshot's content opens with its own title; the card has
        // already said it once.
        if content.hasPrefix(thing.title) {
            content = String(content.dropFirst(thing.title.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return content
    }

    /// The pictures, fetched: stored pixels are already in the model; a
    /// thing with `previewImageData` but no decoded bitmap is decoded here,
    /// off main; remote art and a face go through the shared URL cache. One
    /// fetch each, on a tap, for a picture the person is about to send.
    static func fetchingPictures(_ model: Model, storedPixels: Data?) async -> Model {
        var out = model
        if out.picture == nil, let data = storedPixels {
            out.picture = await Task.detached(priority: .userInitiated) { UIImage(data: data) }.value
        }
        if out.picture == nil, let art = model.artURL {
            out.picture = await fetch(art)
        }
        if let face = model.faceURL {
            out.face = await fetch(face)
        }
        return out
    }

    private static func fetch(_ urlString: String) async -> UIImage? {
        // The demo's bundled stills and faces ride the same `sample:` refs
        // every row resolves through `demoSample(for:)`.
        if urlString.hasPrefix("sample:") { return await MainActor.run { UIImage.demoSample(for: urlString) } }
        guard let url = URL(string: urlString), let scheme = url.scheme,
              scheme == "https" || scheme == "http" else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 8
        // A picture the card fetches is a host reached, so it is a receipt
        // like every other read (prd §277, `receipts-coverage-audit.py`).
        NetworkLedger.shared.record(request)
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return await Task.detached(priority: .userInitiated) { UIImage(data: data) }.value
    }

    /// The bitmap. Rendered on the main actor because `ImageRenderer` walks
    /// a SwiftUI tree; the tree is small and the call is on a tap.
    @MainActor
    static func render(_ model: Model) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCardView(model: model, ink: Ink.resolved()))
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.uiImage
    }

    /// PNG bytes, for a composer attachment.
    @MainActor
    static func png(_ model: Model) -> Data? {
        render(model)?.pngData()
    }

    /// The card's colours, resolved once against the dark appearance the
    /// ink sheet always wears. See the type doc for why they cannot be the
    /// tokens themselves.
    struct Ink {
        let ground: Color
        let primary: Color
        let secondary: Color
        let tertiary: Color
        let brand: Color
        let fill: Color

        static func resolved() -> Ink {
            let dark = UITraitCollection(userInterfaceStyle: .dark)
            func fix(_ c: Color) -> Color { Color(uiColor: UIColor(c).resolvedColor(with: dark)) }
            // The raised surface, not pure black: the tray the card is
            // previewed on IS black, and a black card on it has no edge.
            return Ink(ground: fix(DS.surfaceRaised),
                       primary: fix(DS.textPrimary),
                       secondary: fix(DS.textSecondary),
                       tertiary: fix(DS.textTertiary),
                       brand: fix(DS.brandInk),
                       fill: fix(DS.fillLine))
        }
    }
}

/// What the share sheet is handed: the card, then the thing's link as an
/// item of its own. One item carrying both as representations gave every
/// target ONE of them — Messages, Mail and a post took the picture and
/// dropped the link, so an RSS article went out as a card with no way to
/// the article. Two items, and each target takes all it can.
///
/// A thing with no link offers its title as the card's text representation
/// instead — never the app's own site in place of a link the thing does not
/// have (§83).
enum ShareCardPart: Transferable {
    case card(UIImage, words: String?)
    case link(URL)

    /// The items for one card: the card, then the link when there is one.
    static func items(image: UIImage, link: URL?, title: String) -> [ShareCardPart] {
        guard let link else { return [.card(image, words: title)] }
        return [.card(image, words: nil), .link(link)]
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { part in
            guard case .card(let image, _) = part else { return Data() }
            return image.pngData() ?? Data()
        }
        .exportingCondition { if case .card = $0 { true } else { false } }
        // The link goes out as `public.url` DATA — the URL's own UTF-8 bytes,
        // the convention every reader of that type decodes
        // (`NSURL(dataRepresentation:)`, the pasteboard, every share
        // extension). A `ProxyRepresentation` to a `URL` here let
        // CoreTransferable serialise it as a CoreFoundation property list, and
        // X posted those bytes as the text (`bplist00%C2%A3…https://…`) — the
        // card arrived, the link did not (§1018, measured on device). No force
        // unwrap on the part's own value: `exportingCondition` does not stop
        // the closure from being CALLED (measured: a nil link trapped at the
        // first tap), it only stops its result from being exported.
        DataRepresentation(exportedContentType: .url) { part in
            guard case .link(let url) = part else { return Data() }
            return url.dataRepresentation
        }
        .exportingCondition { if case .link = $0 { true } else { false } }
        ProxyRepresentation { part in
            guard case .card(_, let words?) = part else { return "" }
            return words
        }
        .exportingCondition { if case .card(_, _?) = $0 { true } else { false } }
    }
}
