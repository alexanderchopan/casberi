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
    }

    /// The model, or nil for a thing the sheet cannot draw (a tombstone).
    @MainActor
    static func model(for thing: Thing) -> Model? {
        guard thing.isLive else { return nil }
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
        let words = isPost ? body : [seam.line, body].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
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
                     stats: stats)
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

/// What the share sheet is handed: the card first, so Messages, Mail and a
/// post get the picture; the thing's link second, so a target that takes
/// links (Notes, a browser) gets the link.
struct ShareCardItem: Transferable {
    let image: UIImage
    let link: URL?
    let title: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            item.image.pngData() ?? Data()
        }
        // A thing with no link offers its title as text instead — never the
        // app's own site in place of a link the thing does not have (§83).
        // No force unwrap: `exportingCondition` does not stop the proxy
        // closure from being CALLED (measured: a nil link trapped at the
        // first tap), it only stops its result from being exported.
        ProxyRepresentation { item in item.link ?? URL(string: "about:blank")! }
            .exportingCondition { $0.link != nil }
        ProxyRepresentation { item in item.title }
            .exportingCondition { $0.link == nil }
    }
}
