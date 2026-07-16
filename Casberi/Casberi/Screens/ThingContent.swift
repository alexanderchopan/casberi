import SwiftUI
import Photos
import LinkPresentation
import AVFoundation

/// Content by kind (S19) — the thing shows AS what it is: a screenshot is the
/// image, a link is its preview, a chat reads as a conversation, voice leads
/// with its waveform. Everything here renders only what the record actually
/// holds; nothing is fabricated.
struct ThingContentView: View {
    let thing: Thing

    /// True when the `.link` branch below resolves to the LinkPreviewCard,
    /// whose footer already names the host — ThingSheetView's Site row keys
    /// off this exact fact (not a lookalike condition) so the two views
    /// can't drift: a token/Kalshi link renders a chart with no host line,
    /// and its Site row must stay.
    static func showsLinkPreview(_ thing: Thing) -> Bool {
        // A product previews its page the same way a link does, so it dedups
        // the Site row identically — else the host shows twice.
        (thing.kind == .link || thing.kind == .product)
            && TokenChart.route(from: thing.content) == nil
            && KalshiMarket.route(from: thing.content) == nil
            && StockChart.route(from: thing.content) == nil
            && Capture.detectURL(in: thing.content.isEmpty ? thing.title : thing.content) != nil
    }

    var body: some View {
        switch thing.kind {
        case .screenshot:
            ScreenshotContent(assetID: thing.sourceRef)
        case .link:
            // A token link leads with its price chart (the token's "media",
            // like a screenshot leads with its image); everything else previews.
            if let route = TokenChart.route(from: thing.content) {
                TokenChartContent(thing: thing, chain: route.chain, address: route.address)
            } else if let route = KalshiMarket.route(from: thing.content) {
                KalshiMarketContent(series: route.series, event: route.event)
            } else if let ticker = StockChart.route(from: thing.content) {
                StockChartContent(thing: thing, ticker: ticker)
            } else if thing.source == "GitHub", thing.starCount != nil || thing.repoLanguage != nil {
                // A starred / watched repo leads with its preview, then the
                // language dot and the "since you starred" line.
                GitHubStarContent(thing: thing)
            } else if let url = Capture.detectURL(in: thing.content.isEmpty ? thing.title : thing.content) {
                LinkPreviewCard(url: url, storedImageURL: thing.previewImageURL)
            } else if let art = thing.previewImageURL, !art.isEmpty {
                // A link with stored art but no openable URL — an Apple Music
                // LIBRARY play comes back from MusicKit with no song.url, so
                // the thing's content is empty and detectURL finds nothing,
                // yet the record still carries its mzstatic cover. Lead with
                // that art instead of a blank sheet (fix 2026-07-12: every
                // music item opened to an empty sheet).
                StoredArtContent(urlString: art)
            }
        case .product:
            // A product leads with its page preview and photo — the store/deal
            // page in `content`, the product image in `previewImageURL` — the
            // same treatment a link gets, so a product never renders as a bare URL.
            if let url = Capture.detectURL(in: thing.content.isEmpty ? thing.title : thing.content) {
                LinkPreviewCard(url: url, storedImageURL: thing.previewImageURL)
            } else if let art = thing.previewImageURL, !art.isEmpty {
                StoredArtContent(urlString: art)
            }
        case .chat:
            if !thing.content.isEmpty { ChatBubbles(text: thing.content) }
        case .voice:
            VoiceContent(transcript: thing.content, sourceRef: thing.sourceRef,
                         audio: thing.audio)
        case .file, .output:
            FileChip(name: thing.title, note: thing.content)
        case .event:
            if !thing.content.isEmpty { ScheduleCard(text: thing.content) }
        case .approval:
            if !thing.content.isEmpty { CommandCard(text: thing.content) }
        default:
            if !thing.content.isEmpty {
                Text(thing.content)
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .lineLimit(12)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.bottom, DS.Space.s3)
            }
        }
    }
}

/// The screenshot itself, from the person's library. Reads only — no prompt
/// lives here; without a grant (or for demo rows with no asset) the frame
/// states what it is instead of pretending.
private struct ScreenshotContent: View {
    let assetID: String?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.fillFaint)
                    .frame(height: 140)
                    .overlay(
                        VStack(spacing: DS.Space.s1) {
                            Image(systemName: "photo")
                                .font(.system(size: 22))
                                .foregroundStyle(DS.textTertiary)
                            Text("In your photos")
                                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        }
                    )
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
        .task { await load() }
    }

    private func load() async {
        // Demo sample refs load their bundled image (the sheet leads with
        // media — a placeholder box on a sample thing reads as broken).
        if let assetID, assetID.hasPrefix("sample:") {
            image = UIImage.demoSample(for: assetID)
            return
        }
        guard let assetID,
              PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized
                || PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited,
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
                .firstObject
        else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true   // iCloud-optimized originals
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 800, height: 800),
            contentMode: .aspectFit,
            options: options
        ) { result, _ in
            if let result { image = result }
        }
    }
}

/// The universal Share entry (2026-07-13) — text/URL for most kinds, but a
/// screenshot's whole point IS the image, so sharing it as bare title text
/// read as hollow. Loads the same PHAsset ScreenshotContent already shows and
/// shares the real photo instead. One implementation, used by both the thing
/// sheet's Share row and the Feed row's swipe-to-share.
struct ThingShareLink<Label: View>: View {
    let thing: Thing
    @ViewBuilder let label: () -> Label
    @State private var screenshotImage: UIImage?

    private var shareText: String {
        thing.content.isEmpty ? thing.title : thing.content
    }

    var body: some View {
        Group {
            if thing.kind == .screenshot, let screenshotImage {
                ShareLink(item: Image(uiImage: screenshotImage),
                          preview: SharePreview(thing.title, image: Image(uiImage: screenshotImage))) {
                    label()
                }
            } else if let url = Capture.detectURL(in: shareText) {
                ShareLink(item: url) { label() }
            } else {
                ShareLink(item: shareText, subject: Text(thing.title)) { label() }
            }
        }
        .onAppear { loadScreenshotIfNeeded() }
    }

    /// Mirrors PhotoWell's loader (ShapedRows.swift) rather than reinventing
    /// a third copy: the corpus's own healed copy first (instant, no Photos
    /// round trip), then the PHAsset — waiting past a network asset's
    /// degraded placeholder callback so Share never hands out a blurry
    /// stand-in (same fix as GenCover/PhotoWell).
    private func loadScreenshotIfNeeded() {
        guard thing.kind == .screenshot, screenshotImage == nil,
              let ref = thing.sourceRef else { return }
        if ref.hasPrefix("sample:") {
            screenshotImage = UIImage.demoSample(for: ref)
            return
        }
        if let data = thing.previewImageData, let stored = UIImage(data: data) {
            screenshotImage = stored
            return
        }
        let assetID = ref.replacingOccurrences(of: "phasset:", with: "")
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
            .firstObject else { return }
        Task {
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            let loaded: UIImage? = await withCheckedContinuation { cont in
                var reported = false
                PHImageManager.default().requestImage(
                    for: asset, targetSize: CGSize(width: 1200, height: 1200),
                    contentMode: .aspectFit, options: options
                ) { img, info in
                    let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    if degraded { return }
                    guard !reported else { return }
                    reported = true
                    cont.resume(returning: img)
                }
            }
            if let loaded { screenshotImage = loaded }
        }
    }
}

/// A link's preview — title and image fetched through the system's own
/// LinkPresentation metadata. Falls back to the bare host line offline.
/// When the record already holds art (an Apple Music cover, a pin's photo),
/// that leads — instantly, no live fetch to gamble on; LP fills in the title.
private struct LinkPreviewCard: View {
    let url: URL
    var storedImageURL: String? = nil
    @Environment(\.openURL) private var openURL
    @State private var title: String?
    @State private var image: UIImage?

    var body: some View {
        Button {
            openURL(url)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                if let image {
                    // The image fills a fixed banner and never dictates the
                    // card's width — a bare scaledToFill's ideal size would
                    // stretch the whole card past the screen on a wide
                    // banner (the ZStack-expansion gotcha, same fix).
                    Color.clear
                        .frame(height: 140)
                        .overlay(Image(uiImage: image).resizable().scaledToFill())
                        .clipped()
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let title {
                        Text(title)
                            .dsText(.body17).foregroundStyle(DS.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Text(url.host() ?? url.absoluteString)
                        .dsText(.subhead13).foregroundStyle(DS.tint)
                        .lineLimit(1)
                }
                .padding(DS.Space.s3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.fillFaint,
                        in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
        .task { await fetch() }
    }

    private func fetch() async {
        // Stored art first: it's the record's own media and one cached CDN
        // request away, where LPMetadataProvider re-scrapes the whole page
        // and often comes back with nothing (music.apple.com especially).
        if let stored = storedImageURL, let storedURL = URL(string: stored),
           let (data, _) = try? await URLSession.shared.data(from: storedURL),
           let art = UIImage(data: data) {
            // The card only ever paints this into a 140pt banner — downsample
            // off-main so a full-resolution CDN image doesn't sit decoded in
            // memory for a fraction of its rendered size.
            image = await art.dsDownsampled(maxSide: 280)
        }
        let provider = LPMetadataProvider()
        guard let metadata = try? await provider.startFetchingMetadata(for: url) else { return }
        title = metadata.title
        guard image == nil, let imageProvider = metadata.imageProvider else { return }
        let fetched: UIImage? = await withCheckedContinuation { continuation in
            _ = imageProvider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
        if let fetched {
            image = await fetched.dsDownsampled(maxSide: 280)
        }
    }
}

/// A record that carries stored art but no openable URL — an Apple Music
/// library play (MusicKit returns no song.url, so the link's content is
/// empty) still holds its mzstatic cover. The sheet leads with that art,
/// square, instead of rendering nothing.
private struct StoredArtContent: View {
    let urlString: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.fillFaint)
                    .frame(height: 140)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 22))
                            .foregroundStyle(DS.textTertiary)
                    )
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
        .task(id: urlString) { await load() }
    }

    private func load() async {
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let ui = UIImage(data: data) else { return }
        // Rendered at most 280pt tall (`frame(maxHeight: 280)` above); no
        // reason to hold a full-resolution decode for that.
        image = await ui.dsDownsampled(maxSide: 560)
    }
}

private extension UIImage {
    /// Off-main downsample to fit within `maxSide` pixels — the same
    /// technique `RemoteImageLoader` uses for remote images (ShapedRows.swift),
    /// applied here to locally-decoded bytes so a detail sheet doesn't hold a
    /// full-resolution bitmap just to paint a small fixed-size banner/card.
    func dsDownsampled(maxSide: CGFloat) async -> UIImage {
        guard size.width > maxSide || size.height > maxSide else { return self }
        return await withCheckedContinuation { cont in
            prepareThumbnail(of: CGSize(width: maxSide, height: maxSide)) {
                cont.resume(returning: $0 ?? self)
            }
        }
    }
}

/// Chat content reads as a conversation — one bubble per paragraph. No
/// speakers are invented; the record holds text, the shape says chat.
private struct ChatBubbles: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ForEach(Array(text.split(separator: "\n").prefix(6).enumerated()),
                    id: \.offset) { _, line in
                Text(String(line))
                    .dsText(.callout15).foregroundStyle(DS.textPrimary)
                    .padding(.horizontal, DS.Space.s3)
                    .padding(.vertical, DS.Space.s2)
                    .background(DS.fillFaint,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
    }
}

/// Voice leads with its waveform — and plays, when the thing keeps its audio
/// file (things captured by the mic do; demo rows don't). The transcript
/// follows when one exists.
private struct VoiceContent: View {
    let transcript: String
    var sourceRef: String? = nil
    var audio: Data? = nil

    @State private var player: AVAudioPlayer?
    @State private var playing = false

    private var audioURL: URL? {
        sourceRef.flatMap(VoiceCapture.audioURL(for:))
            .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    private var hasAudio: Bool { audio != nil || audioURL != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                if hasAudio {
                    Button {
                        toggle()
                    } label: {
                        Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(DS.tint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(playing ? "Pause" : "Play")
                }
                HStack(spacing: 2) {
                    ForEach(Array([8, 14, 20, 12, 18, 8, 16, 22, 10, 14, 6, 12, 18, 9, 15].enumerated()),
                            id: \.offset) { _, h in
                        Capsule().fill(DS.tint).frame(width: 3, height: CGFloat(h))
                            .opacity(playing ? 1 : 0.7)
                    }
                }
                Spacer()
            }
            if !transcript.isEmpty {
                Text(transcript)
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .lineLimit(8)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
        .onDisappear { player?.stop() }
    }

    private func toggle() {
        if playing {
            player?.pause()
            playing = false
            return
        }
        if player == nil {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            if let audio {
                player = try? AVAudioPlayer(data: audio)
            } else if let url = audioURL {
                player = try? AVAudioPlayer(contentsOf: url)
            }
        }
        player?.play()
        playing = player?.isPlaying ?? false
    }
}

/// A file is a document chip — name, extension badge, and its note when the
/// record carries one.
private struct FileChip: View {
    let name: String
    let note: String

    private var ext: String? {
        let parts = name.split(separator: ".")
        return parts.count > 1 ? parts.last.map { String($0).uppercased() } : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s3) {
                Image(systemName: "doc")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(DS.tint)
                Text(name)
                    .dsText(.callout15).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                if let ext {
                    Text(ext)
                        .dsText(.label12).foregroundStyle(DS.textSecondary)
                        .padding(.horizontal, DS.Space.s2).frame(height: 22)
                        .background(DS.gray100, in: Capsule(style: .continuous))
                }
                Spacer()
            }
            .padding(DS.Space.s3)
            .background(DS.fillFaint,
                        in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            if !note.isEmpty {
                Text(note)
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
    }
}

/// What the agent wants to run — the exact ask, monospaced, nothing
/// paraphrased. The verbs below it are the answer.
private struct CommandCard: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(DS.textPrimary)
            .lineLimit(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.s3)
            .background(DS.fillFaint,
                        in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .padding(.horizontal, DS.Space.s4)
            .padding(.bottom, DS.Space.s3)
    }
}

/// An event's schedule line, stated plainly — the record's own words with a
/// clock, not a fabricated date block.
private struct ScheduleCard: View {
    let text: String

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            Image(systemName: "clock")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DS.tint)
            Text(text)
                .dsText(.body17).foregroundStyle(DS.textPrimary)
                .lineLimit(2)
            Spacer()
        }
        .padding(DS.Space.s3)
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
    }
}

/// A token's price, drawn natively — the full TokenChartView read (prd 51):
/// price, the delta pill, range chips, the scrubbable line, and (2026-07-14)
/// the since-you-watched anchor plus a market-structure strip (liquidity,
/// 24h volume, FDV, market cap — the Dexscreener pair payload that resolved
/// the token; a stat the pair doesn't report simply isn't shown).
/// Illiquid/dead tokens have no pool anywhere, so it falls back to the
/// plain link, never an empty chart.
private struct TokenChartContent: View {
    let thing: Thing
    let chain: String
    let address: String
    @State private var stats: TokenStats?

    /// The watch-time anchor — only when the record really carries one
    /// (tokens watched before the field stay anchorless, honestly).
    private var since: (price: Double, date: Date)? {
        guard thing.source == "Tokens", let p = thing.watchPriceUsd, p > 0
        else { return nil }
        return (p, thing.capturedAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            TokenChartView(chain: chain, address: address, since: since) {
                // No pool (dead/illiquid) — the plain link, honestly.
                if let url = URL(string: "https://dexscreener.com/\(chain)/\(address)") {
                    LinkPreviewCard(url: url)
                }
            }
            statStrip
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
        .task { stats = await TokenStats.fetch(chain: chain, address: address) }
    }

    /// The market's shape in four quiet numbers — cells only for stats the
    /// pair actually reported.
    @ViewBuilder private var statStrip: some View {
        if let stats {
            let cells: [(String, Double)] = [
                ("Liquidity", stats.liquidityUsd), ("24h volume", stats.volume24h),
                ("FDV", stats.fdv), ("Market cap", stats.marketCap),
            ].compactMap { label, value in value.map { (label, $0) } }
            HStack(alignment: .top, spacing: DS.Space.s3) {
                ForEach(cells, id: \.0) { label, value in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey(label))
                            .dsText(.label12).foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                        Text(TokenStats.compact(value))
                            .dsText(.callout15).foregroundStyle(DS.textPrimary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(DS.Space.s3)
            .background(DS.fillFaint,
                        in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
    }
}

/// A watched stock's price, drawn natively — the equity dose of the same
/// anatomy (StockChart/Yahoo behind the shared TokenChartView). No
/// market-structure strip: those stats ride the Dexscreener pair payload,
/// a token fact — Yahoo's chart JSON carries none we'd stand behind.
/// Yahoo unreachable → the plain Stocktwits link, never a broken chart.
private struct StockChartContent: View {
    let thing: Thing
    let ticker: String

    /// The watch-time anchor — only when the record really carries one.
    private var since: (price: Double, date: Date)? {
        guard thing.source == "Stocktwits", let p = thing.watchPriceUsd, p > 0
        else { return nil }
        return (p, thing.capturedAt)
    }

    var body: some View {
        TokenChartView(memoryKey: "stock.range.\(ticker)",
                       fetch: { (range: StockRange) in
                           await StockChart.fetch(ticker: ticker, range: range)
                       },
                       since: since) {
            if let url = URL(string: thing.content) {
                LinkPreviewCard(url: url)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
    }
}

/// A starred (or watched) repo: its link preview, then the language dot and —
/// for stars — "since you starred", the stargazer count the day you saved it
/// against where it is now. The anchor is stored at ingest; the current count
/// is fetched live (and simply omitted if the fetch can't reach it).
private struct GitHubStarContent: View {
    let thing: Thing
    @State private var currentStars: Int?

    /// The star-time anchor — only when the record really carries one.
    private var since: (stars: Int, date: Date)? {
        guard let c = thing.starCount, c > 0 else { return nil }
        return (c, thing.capturedAt)
    }

    /// "owner/repo" parsed from the repo's html_url.
    private var repoPath: String? {
        guard let url = URL(string: thing.content),
              (url.host ?? "").contains("github.com") else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return nil }
        return "\(parts[0])/\(parts[1])"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if let url = URL(string: thing.content) {
                LinkPreviewCard(url: url, storedImageURL: thing.previewImageURL)
            }
            metaRow
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
        .task { await loadCurrent() }
    }

    @ViewBuilder private var metaRow: some View {
        let language = thing.repoLanguage
        if (language?.isEmpty == false) || since != nil {
            HStack(spacing: DS.Space.s3) {
                if let language, !language.isEmpty {
                    HStack(spacing: 5) {
                        Circle().fill(Self.languageColor(language))
                            .frame(width: 9, height: 9)
                        Text(language)
                            .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                sinceLine
            }
        }
    }

    @ViewBuilder private var sinceLine: some View {
        if let since {
            HStack(spacing: 5) {
                Image(systemName: "star.fill")
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                if let now = currentStars, now != since.stars {
                    let delta = now - since.stars
                    Text("\(Self.compact(since.stars)) → \(Self.compact(now))")
                        .dsText(.subhead13).foregroundStyle(DS.textPrimary).monospacedDigit()
                    Text(delta > 0 ? "+\(Self.compact(delta)) since you starred"
                                   : "since you starred")
                        .dsText(.label12)
                        .foregroundStyle(delta > 0 ? DS.confirm : DS.textTertiary)
                } else {
                    Text("\(Self.compact(since.stars)) when you starred")
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary).monospacedDigit()
                }
            }
        }
    }

    private func loadCurrent() async {
        guard since != nil, let path = repoPath,
              let token = TokenVault.get(TokenBridge.github.tokenKey) else { return }
        currentStars = await GitHubFeedFetch.repoStars(path: path, token: token)
    }

    /// "8.4k", "1.2M" — GitHub's own compact star form.
    static func compact(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...:     return String(format: "%.1fk", Double(n) / 1_000)
        default:           return "\(n)"
        }
    }

    /// GitHub Linguist's canonical language colors; a neutral dot for the rest.
    static func languageColor(_ language: String) -> Color {
        colors[language] ?? DS.textTertiary
    }
    private static let colors: [String: Color] = [
        "Swift": Color(hex: "#F05138"),       "JavaScript": Color(hex: "#F1E05A"),
        "TypeScript": Color(hex: "#3178C6"),  "Python": Color(hex: "#3572A5"),
        "Rust": Color(hex: "#DEA584"),        "Go": Color(hex: "#00ADD8"),
        "Ruby": Color(hex: "#701516"),        "Java": Color(hex: "#B07219"),
        "Kotlin": Color(hex: "#A97BFF"),      "C": Color(hex: "#555555"),
        "C++": Color(hex: "#F34B7D"),         "C#": Color(hex: "#178600"),
        "Objective-C": Color(hex: "#438EFF"), "Shell": Color(hex: "#89E051"),
        "HTML": Color(hex: "#E34C26"),        "CSS": Color(hex: "#563D7C"),
        "PHP": Color(hex: "#4F5D95"),         "Dart": Color(hex: "#00B4AB"),
        "Scala": Color(hex: "#C22D40"),       "Elixir": Color(hex: "#6E4A7E"),
        "Haskell": Color(hex: "#5E5086"),     "Lua": Color(hex: "#000080"),
        "Vue": Color(hex: "#41B883"),         "Zig": Color(hex: "#EC915C"),
        "Solidity": Color(hex: "#AA6746"),    "Nix": Color(hex: "#7E7EFF"),
    ]
}

/// A Kalshi market's odds, drawn natively — the KalshiMarketView read: a
/// live probability, a delta pill, honest about active vs settled. A market
/// Kalshi no longer resolves (rare — expired far past close) falls back to
/// the plain link, never a blank read.
private struct KalshiMarketContent: View {
    let series: String
    let event: String

    var body: some View {
        KalshiMarketView(series: series, event: event) {
            if let url = URL(string: "https://kalshi.com/markets/\(series)/\(event)") {
                LinkPreviewCard(url: url)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
    }
}
