import SwiftUI
import SwiftData
import Photos
import LinkPresentation
import AVFoundation

/// Which chart a thing LEADS with, decided once (2026-07-27).
///
/// Three places needed this answer — `ThingContentView.kindContent` (what to
/// draw), `ThingContentView.showsLinkPreview` (whether the sheet's Site row
/// would be a duplicate), and `ThingSheetView`'s detent (a chart is tall, so
/// it opens full-height) — and each had hand-written its own chain of
/// `route(from:)` calls. They had already drifted: the detent check listed
/// Token and Stock but not Kalshi, so a Kalshi market opened half-height with
/// its verbs below the fold. Adding PostHog would have been a fourth clause in
/// three places; it's one case here instead.
enum ThingChart {
    case token(chain: String, address: String)
    case kalshi(series: String, event: String)
    case stock(ticker: String)
    case postHogMetric(event: String)

    /// Charts are a `.link` affordance only — a `.product` previews its page
    /// even when the URL would otherwise parse.
    static func kind(for thing: Thing) -> ThingChart? {
        guard thing.kind == .link else { return nil }
        if let route = TokenChart.route(from: thing.content) {
            return .token(chain: route.chain, address: route.address)
        }
        if let route = KalshiMarket.route(from: thing.content) {
            return .kalshi(series: route.series, event: route.event)
        }
        if let ticker = StockChart.route(from: thing.content) {
            return .stock(ticker: ticker)
        }
        // PostHog can't ride `route(from:)`: a watched metric's content is a
        // plain project URL, shared verbatim by its annotation, milestone and
        // silence things — the ref is what separates them.
        if thing.source == "PostHog", let event = PostHogWatch.event(from: thing) {
            return .postHogMetric(event: event)
        }
        return nil
    }
}

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
            && ThingChart.kind(for: thing) == nil
            && Capture.detectURL(in: thing.content.isEmpty ? thing.title : thing.content) != nil
    }

    /// A product's stated price, formatted in its own currency — nil (never
    /// a guess) when the record doesn't carry one.
    static func productPrice(_ thing: Thing) -> String? {
        guard let value = thing.priceValue else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = thing.priceCurrency ?? "USD"
        return formatter.string(from: NSNumber(value: value))
    }

    var body: some View {
        // The kind's own media, then the source's own words (2026-07-22).
        // spacing 0 — every branch below already pads its own bottom, and the
        // summary block pads its own top.
        VStack(alignment: .leading, spacing: 0) {
            kindContent
            summaryBlock
        }
    }

    /// The source's own abstract — a feed item's summary, a task's notes, a
    /// Linear issue's body, the rest of a clamped Readwise highlight. Follows
    /// the media, the way a screenshot's caption follows its image. Skipped
    /// when it would only repeat what's already on screen.
    @ViewBuilder private var summaryBlock: some View {
        let text = (thing.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let dupe = text == thing.title.trimmingCharacters(in: .whitespacesAndNewlines)
            || text == thing.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty, !dupe {
            Text(text)
                .dsText(.callout15)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s3)
        }
    }

    @ViewBuilder private var kindContent: some View {
        switch thing.kind {
        case .screenshot:
            ScreenshotContent(assetID: thing.sourceRef)
        case .link:
            // A charted link leads with its curve (the chart is the link's
            // "media", like a screenshot leads with its image); everything
            // else previews.
            if let chart = ThingChart.kind(for: thing) {
                switch chart {
                case .token(let chain, let address):
                    TokenChartContent(thing: thing, chain: chain, address: address)
                case .kalshi(let series, let event):
                    KalshiMarketContent(series: series, event: event)
                case .stock(let ticker):
                    StockChartContent(thing: thing, ticker: ticker)
                case .postHogMetric(let event):
                    // A watched metric leads with its own curve, and the
                    // project's annotations land on it as marks, so a spike
                    // sits beside the deploy that caused it.
                    PostHogMetricContent(thing: thing, event: event)
                }
            } else if thing.source == "GitHub", thing.sourceRef?.hasPrefix("gh:release:") == true {
                // A release leads with its preview, then its own notes —
                // read live, since `enrichedText` is retrieval-only.
                GitHubReleaseContent(thing: thing)
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
            let url = Capture.detectURL(in: thing.content.isEmpty ? thing.title : thing.content)
            let art = thing.previewImageURL
            if let url {
                LinkPreviewCard(url: url, storedImageURL: art)
            } else if let art, !art.isEmpty {
                StoredArtContent(urlString: art)
            }
            // The price the record holds — a fact of its own, shown beside
            // whatever media rendered above (or, when neither URL nor stored
            // art exist, doing the work of not leaving the sheet blank).
            if let price = Self.productPrice(thing) {
                Text(price)
                    .dsText(.heading17).foregroundStyle(DS.textPrimary)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.bottom, DS.Space.s3)
            } else if url == nil, (art ?? "").isEmpty, !thing.content.isEmpty {
                // No URL, no art, no price — the sheet used to render nothing
                // here at all. The record's own words are the honest fallback,
                // same as every other kind's default case.
                Text(thing.content)
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .lineLimit(6)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.bottom, DS.Space.s3)
            }
        case .chat:
            // A post/cast is not a conversation — it's one person's words,
            // its pictures, what it quotes, and how it landed. Its own read
            // (2026-07-16); the ChatBubbles path stayed for the imports
            // (ChatGPT, Claude) whose content really is a transcript. Before
            // this, a post rendered its `content` as bubbles — and a post's
            // content is its PERMALINK, so the sheet showed a URL in a bubble.
            if SocialThread.isSocial(thing.source) {
                SocialPostContent(thing: thing)
            } else if !thing.content.isEmpty {
                ChatBubbles(text: thing.content)
            }
        case .voice:
            VoiceContent(transcript: thing.content, sourceRef: thing.sourceRef,
                         audio: thing.audio)
        case .file, .output:
            FileChip(name: thing.title, note: thing.content)
        case .event:
            if !thing.content.isEmpty { ScheduleCard(text: thing.content) }
        case .mail:
            // Real inbox mail (MailBridge) carries no body — `content` is
            // just "From <sender>" — so its content-area anatomy is the
            // sender, with the same initial-circle identity the feed row
            // already draws, instead of that raw string in a bare text
            // bubble. Demo/sample mail things DO carry real body text with
            // no sender field at all — MailContentView shows whichever facts
            // the record actually has, never both when they'd say the same
            // thing.
            MailContentView(thing: thing)
        case .reminder:
            if let due = thing.dueAt {
                ReminderDueRow(due: due)
            } else if !thing.content.isEmpty {
                // No structured due date (a Todoist task, or a Reminders item
                // with none set) — the same bare-text fallback every kind
                // without a dedicated anatomy gets.
                Text(thing.content)
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .lineLimit(12)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.bottom, DS.Space.s3)
            }
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
                                .accessibilityHidden(true)
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
                            .accessibilityHidden(true)
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
///
/// A long imported transcript (ChatGPT, Claude) used to hard-cut at 6
/// paragraphs with no sign anything was missing — a silent truncation, the
/// same class of dishonesty the app polices everywhere else (a cut needs a
/// seam). "Show more" names what's hidden and lets it in.
private struct ChatBubbles: View {
    let text: String
    @State private var expanded = false

    private var paragraphs: [Substring] { text.split(separator: "\n") }
    private static let collapsedCount = 6

    var body: some View {
        let shown = expanded ? paragraphs : Array(paragraphs.prefix(Self.collapsedCount))
        let hiddenCount = paragraphs.count - shown.count
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, line in
                Text(String(line))
                    .dsText(.callout15).foregroundStyle(DS.textPrimary)
                    .padding(.horizontal, DS.Space.s3)
                    .padding(.vertical, DS.Space.s2)
                    .background(DS.fillFaint,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if hiddenCount > 0 {
                Button {
                    withAnimation(DS.Motion.standard) { expanded = true }
                } label: {
                    Text("Show \(hiddenCount) more")
                        .dsText(.subhead13).foregroundStyle(DS.tint)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DS.Space.s3)
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
    /// The real amplitude envelope, read off the audio file itself — nil
    /// until decoded, or forever when there's no audio to read one from. Was
    /// a hardcoded bar-height array before 2026-07-21 (pure decoration, in an
    /// app that otherwise polices fake status hard); a flat, even bar shape
    /// is the honest placeholder while this hasn't loaded, never invented
    /// peaks and valleys.
    @State private var envelope: [CGFloat]?

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
                    ForEach(Array((envelope ?? Self.flatBars).enumerated()), id: \.offset) { _, h in
                        Capsule().fill(DS.tint).frame(width: 3, height: h)
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
        .task { envelope = await Self.readEnvelope(url: audioURL, data: audio) }
    }

    /// The flat placeholder — 15 bars, all the same height, drawn while the
    /// real envelope hasn't loaded (or never will). Even, not shaped: it
    /// says "audio" without claiming to depict this recording's peaks.
    private static let flatBars = [CGFloat](repeating: 10, count: 15)

    /// Peak amplitude per bar, read straight off the file's PCM samples — 15
    /// bars, normalized so the loudest bar in THIS recording always reaches
    /// full height (there's no absolute loudness to compare against, only
    /// this clip's own shape).
    private static func readEnvelope(url: URL?, data: Data?) async -> [CGFloat]? {
        await Task.detached(priority: .utility) {
            var tempURL: URL?
            defer { tempURL.map { try? FileManager.default.removeItem(at: $0) } }
            let fileURL: URL
            if let url {
                fileURL = url
            } else if let data {
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".m4a")
                guard (try? data.write(to: tmp)) != nil else { return nil }
                tempURL = tmp
                fileURL = tmp
            } else {
                return nil
            }
            guard let file = try? AVAudioFile(forReading: fileURL) else { return nil }
            let frameCount = AVAudioFrameCount(file.length)
            guard frameCount > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: frameCount),
                  (try? file.read(into: buffer)) != nil,
                  let channelData = buffer.floatChannelData
            else { return nil }
            let channels = Int(buffer.format.channelCount)
            let frames = Int(buffer.frameLength)
            let bars = 15
            guard frames > 0, channels > 0 else { return nil }
            let samplesPerBar = max(1, frames / bars)
            var peaks = [Float](repeating: 0, count: bars)
            for bar in 0..<bars {
                let start = bar * samplesPerBar
                let end = min(start + samplesPerBar, frames)
                guard start < end else { continue }
                var peak: Float = 0
                for ch in 0..<channels {
                    let samples = channelData[ch]
                    for i in start..<end { peak = max(peak, abs(samples[i])) }
                }
                peaks[bar] = peak
            }
            guard let maxPeak = peaks.max(), maxPeak > 0 else { return nil }
            // 6...22pt, the same range the old hardcoded bars drew in.
            return peaks.map { 6 + CGFloat($0 / maxPeak) * 16 }
        }.value
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
                    .accessibilityHidden(true)
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

/// A mail thing's content-area anatomy: the sender, in the same
/// initial-circle identity the feed row draws (SenderInitial, ShapedRows.swift),
/// plus whatever body text the record actually carries. `MailBridge` stores
/// no body (`content` is just "From <sender>"), so real inbox mail shows only
/// the sender row; demo/sample mail carries real body text with no sender
/// field, and shows only that — never a duplicate "From …" line next to the
/// same fact restated.
private struct MailContentView: View {
    let thing: Thing

    /// New rows carry the sender in `authorHandle`; older rows stored it only
    /// as the content's "From …" prefix — the same fallback the feed row uses,
    /// so a mail thing never loses its sender to a schema gap.
    private var sender: String? {
        if let from = thing.authorHandle, !from.isEmpty { return from }
        if thing.content.hasPrefix("From ") {
            let from = String(thing.content.dropFirst("From ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return from.isEmpty ? nil : from
        }
        return nil
    }

    private var isFromLine: Bool { thing.content.hasPrefix("From ") }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if let sender {
                HStack(spacing: DS.Space.s2) {
                    SenderInitial(sender: sender, size: 26)
                    Text(SenderInitial.displayName(of: sender))
                        .dsText(.callout15).foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
            }
            if !isFromLine, !thing.content.isEmpty {
                Text(thing.content)
                    .dsText(.callout15).foregroundStyle(DS.textPrimary)
                    .lineLimit(10)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
    }
}

/// A reminder's structured deadline — read straight off `dueAt`, the same
/// field the "Coming up" lane already reads (KeptAskComposers.swift), so the
/// sheet finally shows the date the app is quietly tracking for you rather
/// than only the free-text title.
private struct ReminderDueRow: View {
    let due: Date

    private var overdue: Bool { due < .now }

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            Image(systemName: "clock")
                .accessibilityHidden(true)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(overdue ? DS.destructive : DS.tint)
            Text(due.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                .dsText(.body17)
                .foregroundStyle(overdue ? DS.destructive : DS.textPrimary)
            if overdue {
                Text("Overdue")
                    .dsText(.label12).foregroundStyle(DS.destructive)
            }
            Spacer()
        }
        .padding(DS.Space.s3)
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
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
            .dsText(.mono13)
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
                .accessibilityHidden(true)
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
///
/// A token discovered elsewhere — GeckoTerminal trending, a pasted
/// Dexscreener link — draws the exact same chart (trending is discovery,
/// watching stays the Tokens bridge's explicit tap), so it also carries the
/// one-verb Watch row (2026-07-15) — the same door TokenQuickSheet already
/// offers a held-but-unwatched wallet holding, here for any token thing.
private struct TokenChartContent: View {
    let thing: Thing
    let chain: String
    let address: String
    @State private var stats: TokenStats?
    @Environment(\.modelContext) private var modelContext
    // Optional on purpose (2026-07-17): this content mounts from sheet
    // chains that don't all carry the store (the deep-link/-openThing sheet
    // hangs outside RootShell's `.environment(bridges)`), and the REQUIRED
    // form is a mount-time fatal — the sheet crashed the app before the
    // first frame. Missing store only skips bridge registration on Watch.
    @Environment(BridgeStore.self) private var store: BridgeStore?
    @State private var resolved: TokenWatch.Resolved?
    @State private var watchedTitle: String?

    /// The watch-time anchor — only when the record really carries one
    /// (tokens watched before the field stay anchorless, honestly).
    private var since: (price: Double, date: Date)? {
        guard thing.source == "Tokens", let p = thing.watchPriceUsd, p > 0
        else { return nil }
        return (p, thing.capturedAt)
    }

    /// This IS the watchlist's own thing — the row below already says so via
    /// its "since you watched" anchor, so a second Watch verb would be a
    /// dead control on the one place it can never apply.
    private var offersWatch: Bool { thing.source != "Tokens" }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            TokenChartView(chain: chain, address: address, since: since, hero: true) {
                // No pool (dead/illiquid) — the plain link, honestly.
                if let url = URL(string: "https://dexscreener.com/\(chain)/\(address)") {
                    LinkPreviewCard(url: url)
                }
            }
            statStrip
            if offersWatch { watchRow }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
        .task { stats = await TokenStats.fetch(chain: chain, address: address) }
        .task {
            guard offersWatch else { return }
            let route = TokenQuickRoute(chain: chain, address: address)
            if let already = route.watchedThing(in: modelContext) {
                watchedTitle = already.title
            } else {
                resolved = await TokenWatch.search(address).first { $0.id == route.id }
            }
        }
    }

    /// One real verb: Watch — the same one-tap door TokenQuickSheet offers a
    /// held-but-unwatched holding, styled to sit inline among this content's
    /// other quiet cards rather than as a full sheet row.
    @ViewBuilder private var watchRow: some View {
        if let watchedTitle {
            // The settled state wears the same full-width capsule the verb
            // did — quiet fill, confirm check — so watching doesn't snap the
            // layout, and it stays a label, not a control.
            HStack(spacing: DS.Space.s2) {
                Image(systemName: "checkmark")
                    .accessibilityHidden(true)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DS.confirm)
                Text("Watching \(watchedTitle)")
                    .dsText(.callout15).fontWeight(.semibold)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(DS.fillFaint, in: Capsule(style: .continuous))
        } else if let resolved {
            // The one verb, at full Cash-App weight (Big money, 2026-07-17):
            // a tint-filled capsule spanning the sheet.
            Button {
                DSHaptic.tap()
                if let watched = TokenWatch.add(resolved, context: modelContext) {
                    DSHaptic.success()
                    watchedTitle = watched.title
                    if let store {
                        TokenWatch.registerBridge(store: store, context: modelContext)
                    }
                } else {
                    watchedTitle = "\(resolved.name) · $\(resolved.symbol)"
                }
            } label: {
                Text("Watch this token")
                    .dsText(.body17).fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(DS.tint, in: Capsule(style: .continuous))
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    /// The market's shape, re-ranked (Big money, 2026-07-17): the two
    /// biggest facts — market cap and 24h volume, in rank order — lead as
    /// bold cards; whatever else the pair reported follows in the SAME
    /// two-column grid as smaller cards (user checkpoint 2026-07-17: the
    /// free-floating chips broke the block's cohesion — demotion is scale,
    /// not a different anatomy). Still cells only for stats actually
    /// reported: a token with no cap leads with what it HAS (FDV honestly
    /// labeled FDV), never an invented number.
    @ViewBuilder private var statStrip: some View {
        if let stats {
            let cells: [(String, Double)] = [
                ("Market cap", stats.marketCap), ("24h volume", stats.volume24h),
                ("FDV", stats.fdv), ("Liquidity", stats.liquidityUsd),
            ].compactMap { label, value in value.map { (label, $0) } }
            let lead = cells.prefix(2)
            let rest = cells.dropFirst(2)
            VStack(spacing: DS.Space.s2) {
                if !lead.isEmpty {
                    HStack(alignment: .top, spacing: DS.Space.s2) {
                        ForEach(lead, id: \.0) { label, value in
                            statCard(label: label, value: value, lead: true)
                        }
                        // A lone cell keeps its half-width column — three
                        // reported stats must not turn the grid ragged.
                        if lead.count == 1 { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                    }
                }
                if !rest.isEmpty {
                    HStack(alignment: .top, spacing: DS.Space.s2) {
                        ForEach(rest, id: \.0) { label, value in
                            statCard(label: label, value: value, lead: false)
                        }
                        if rest.count == 1 { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                    }
                }
            }
        }
    }

    /// One card anatomy for every stat — the tile radius, a full s4 pad, the
    /// value in the rounded money voice. Lead wears stat24; the rest demote
    /// to price16 in the same seat.
    private func statCard(label: String, value: Double, lead: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(label))
                .dsText(.label12).foregroundStyle(DS.textTertiary)
                .lineLimit(1)
            Text(TokenStats.compact(value))
                .dsText(lead ? .stat24 : .price16)
                .foregroundStyle(DS.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s4)
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.widget,
                                         style: .continuous))
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

/// A watched PostHog metric: its 30-day curve with the project's annotations
/// marked on it, the milestone it's chasing, and the ring's own progress.
///
/// The milestone line is the one place this bridge lets a COUNT be the
/// headline, and it earns it by being a moment rather than a tally — so it
/// rolls (`CountUpText`) instead of just appearing, the same acknowledgement
/// the app gives every other number that took work to reach. Tapping a mark
/// names the annotation it belongs to; nothing is drawn that isn't read.
private struct PostHogMetricContent: View {
    let thing: Thing
    let event: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @State private var reading = PostHogState.Metric()
    /// The annotations already in the corpus — the refresh landed them as
    /// Things minutes ago, so re-fetching them over the network on every sheet
    /// open bought a round trip and a chance to disagree with the feed.
    @State private var annotations: [(date: Date, title: String)] = []
    @State private var tappedMark: String?

    /// The series as a chart. Counts are not prices, but the shape is the
    /// same fact — one value per sample — so it draws through the plot every
    /// other curve in the app uses rather than growing a second chart stack.
    /// A counts series legitimately starts at zero, which `TokenChart.from`
    /// rejects (a price that starts at 0 has no meaningful change), so the
    /// zero-start case falls back to a flat change rather than no chart.
    private var chart: TokenChart? {
        let closes = reading.series.map(Double.init)
        guard closes.count >= 2, let last = closes.last else { return nil }
        return TokenChart.from(closes: closes)
            ?? TokenChart(closes: closes, price: last, change: 0)
    }

    /// Annotations that fall inside the drawn window, placed at their own day.
    /// Ids are STABLE across body evaluations — a fresh `UUID()` each time made
    /// `TokenChartPlot`'s `ForEach` tear down and replay every mark's landing
    /// animation on each re-render (review, 2026-07-27). Capped like the
    /// wallet's own mark set, so a busy timeline can't stipple the curve.
    private var marks: [TokenChartMark] {
        let days = reading.series.count
        guard days >= 2 else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return annotations.prefix(10).compactMap { note in
            let back = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: note.date), to: today).day ?? 0
            guard back >= 0, back < days else { return nil }
            return TokenChartMark(id: markID(note.title, back), x: Double(days - 1 - back),
                                  label: note.title)
        }
    }

    /// A stable id per (note, day) pair — derived, not minted.
    private func markID(_ title: String, _ back: Int) -> UUID {
        var hasher = Hasher()
        hasher.combine(title)
        hasher.combine(back)
        let value = UInt64(bitPattern: Int64(hasher.finalize()))
        return UUID(uuid: (UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8),
                           UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 24),
                           UInt8(truncatingIfNeeded: value >> 32), UInt8(truncatingIfNeeded: value >> 40),
                           UInt8(truncatingIfNeeded: value >> 48), UInt8(truncatingIfNeeded: value >> 56),
                           0, 0, 0, 0, 0, 0, 0, 0))
    }

    private var accent: Color {
        TokenChartStyle.accent(change: chart?.change ?? 0, scheme: scheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            header
            if let chart {
                TokenChartPlot(chart: chart, accent: accent, marks: marks,
                               onTapMark: { tappedMark = $0.label })
            }
            if let tappedMark {
                Text(tappedMark)
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
            }
            milestoneLine
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
        .onAppear(perform: load)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            // The window's own total, not the all-time one — the number the
            // curve above it actually draws.
            Text(PostHogIngest.formatted(reading.series.suffix(7).reduce(0, +)))
                .dsText(.stat24).monospacedDigit()
                .foregroundStyle(DS.textPrimary)
            Text("\(event) · last 7 days")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
        }
    }

    /// "728 of 1,000" — where this metric stands on the ladder. Absent until a
    /// total is read: an unread total is a fact we don't have, and a ring at
    /// zero would claim one.
    @ViewBuilder private var milestoneLine: some View {
        if reading.total > 0 {
            let next = PostHogMilestone.next(after: reading.total)
            HStack(spacing: DS.Space.s2) {
                MetricDisc(series: reading.series,
                           progress: PostHogMilestone.progress(reading.total),
                           change: chart?.change, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    CountUpText(text: PostHogIngest.formatted(reading.total))
                        .dsText(.body17).monospacedDigit()
                        .foregroundStyle(DS.textPrimary)
                    Text("all time · next \(PostHogIngest.formatted(next))")
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Everything here is already on device — the reading from the bridge's
    /// own state, the annotations from the corpus the refresh landed them in.
    /// No network, so the sheet paints immediately and can never show a
    /// different timeline than the feed behind it.
    private func load() {
        reading = PostHogState.get(event)
        let prefix = "posthog:annotation:"
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate {
                $0.source == "PostHog" && ($0.sourceRef?.starts(with: prefix) ?? false)
            },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchLimit = 25
        annotations = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter(\.isLive)
            .map { (date: $0.capturedAt, title: $0.title) }
    }
}

/// A starred (or watched) repo: its link preview, then the language dot and —
/// for stars — "since you starred", the stargazer count the day you saved it
/// against where it is now. The anchor is stored at ingest; the current count
/// is fetched live (and simply omitted if the fetch can't reach it).
/// Not private (2026-07-21): `compact(_:)` and `languageColor(_:)` are also
/// what the GitHub feed row's trailing star/language enrichment reuses
/// (ShapedRows.swift) — one star-formatting and one Linguist-color table, not
/// two copies drifting apart.
struct GitHubStarContent: View {
    let thing: Thing
    @State private var currentStars: Int?

    /// The star-time anchor — only when the record really carries one.
    private var since: (stars: Int, date: Date)? {
        guard let c = thing.starCount, c > 0 else { return nil }
        return (c, thing.capturedAt)
    }

    /// "owner/repo" parsed from the repo's html_url.
    private var repoPath: String? {
        GitHubFeedFetch.repoPath(fromWebURL: thing.content)
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
                    .accessibilityHidden(true)
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

/// A release: its link preview, then its own notes — read fresh when the
/// sheet opens (2026-07-16), the `enrichedText`-is-retrieval-only rule means
/// this can't be stored, so it follows the star-count/social-engagement
/// precedent instead: live, and simply absent if the fetch can't reach it.
private struct GitHubReleaseContent: View {
    let thing: Thing
    @State private var notes: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if let url = URL(string: thing.content) {
                LinkPreviewCard(url: url, storedImageURL: thing.previewImageURL)
            }
            if let notes {
                Text(notes)
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .lineLimit(10)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
        .task { await load() }
    }

    private func load() async {
        guard let token = TokenVault.get(TokenBridge.github.tokenKey) else { return }
        notes = await GitHubFeedFetch.releaseBody(thing: thing, token: token)
    }
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
