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

    var body: some View {
        switch thing.kind {
        case .screenshot:
            ScreenshotContent(assetID: thing.sourceRef)
        case .link:
            // A token link leads with its price chart (the token's "media",
            // like a screenshot leads with its image); everything else previews.
            if let route = TokenChart.route(from: thing.content) {
                TokenChartContent(chain: route.chain, address: route.address)
            } else if let route = KalshiMarket.route(from: thing.content) {
                KalshiMarketContent(series: route.series, event: route.event)
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
            image = art
        }
        let provider = LPMetadataProvider()
        guard let metadata = try? await provider.startFetchingMetadata(for: url) else { return }
        title = metadata.title
        guard image == nil, let imageProvider = metadata.imageProvider else { return }
        image = await withCheckedContinuation { continuation in
            _ = imageProvider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
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
        image = ui
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
/// price, the delta pill, range chips, the scrubbable line. Illiquid/dead
/// tokens have no pool anywhere, so it falls back to the plain link, never
/// an empty chart.
private struct TokenChartContent: View {
    let chain: String
    let address: String

    var body: some View {
        TokenChartView(chain: chain, address: address) {
            // No pool (dead/illiquid) — the plain link, honestly.
            if let url = URL(string: "https://dexscreener.com/\(chain)/\(address)") {
                LinkPreviewCard(url: url)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
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
