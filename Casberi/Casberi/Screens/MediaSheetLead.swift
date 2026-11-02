import SwiftUI
import SwiftData
import AVFoundation

/// A TRACK, A VIDEO OR AN EPISODE LEADS WITH ITSELF (prd §1650, amends §1398's
/// centred head for media): the medium's own shape is the head. A video's
/// frame stands edge to edge at the top and plays there; a song's cover
/// stands large over its name; an episode's show art sits beside the show,
/// the episode's name under it and the player under that. Then the words the
/// app holds (`summary`, the feed's own description), their chapters as rows.
/// Nothing else: the tiles come after.
///
/// Nothing here is read for the sheet, and nothing is added to it: every line
/// is a field the row already carries (§632).
struct MediaSheetLead: View {
    let thing: Thing
    /// Where the frame opens when it cannot play here (a Twitch stream).
    var onOpen: (() -> Void)? = nil
    /// The cover's own colour, for the sheet's ground (prd §1650 item 4),
    /// on the rule `ArtGround` keeps.
    var onGround: ((Color) -> Void)? = nil

    @State private var start: Int?

    private var kind: MediaSheetLead.Kind { Self.kind(of: thing) }

    enum Kind { case video, song, episode, vertical }

    static func kind(of thing: Thing) -> Kind {
        if isVertical(thing) { return .vertical }
        if MediaSheetBox.isVideo(thing) { return .video }
        return thing.source == "Podcasts" ? .episode : .song
    }

    /// The sheets whose ground takes the cover's colour: a square cover is
    /// one picture with one colour, as Apple Music's album page reads it. A
    /// video's frame is its own colour and keeps the ink.
    static func takesGround(_ thing: Thing) -> Bool {
        let kind = kind(of: thing)
        return kind == .song || kind == .episode
    }

    /// A TikTok you saved or posted, or an Instagram reel, with its cover in
    /// hand: a picture made to fill a phone, drawn so.
    static func isVertical(_ thing: Thing) -> Bool {
        guard thing.kind == .link, thing.isLive,
              thing.previewImageData != nil || !(thing.previewImageURL ?? "").isEmpty else { return false }
        switch thing.source {
        case "TikTok": return thing.tags.contains("Saved") || thing.tags.contains("Post")
        case "Instagram": return thing.tags.contains("Reel")
        default: return false
        }
    }

    /// A song's `summary` is its album line, drawn in the head; a video's
    /// or an episode's is its description.
    private var words: MediaChapters.Split {
        kind == .song ? MediaChapters.Split(prose: "", chapters: [])
            : MediaChapters.split(thing.summary ?? "")
    }

    var body: some View {
        if thing.isLive {
            VStack(alignment: .leading, spacing: 0) {
                switch kind {
                case .video: videoHead
                case .song: songHead
                case .episode: episodeHead
                case .vertical: MediaVerticalFrame(thing: thing, onOpen: onOpen)
                }
                if kind != .vertical, !words.prose.isEmpty {
                    MediaWords(text: words.prose)
                        .padding(.horizontal, DSRoomChassis.leadInset)
                        .padding(.top, DS.Space.s4)
                }
                if !words.chapters.isEmpty {
                    chapterRows
                        .padding(.top, DS.Space.s3)
                }
            }
            .task(id: thing.id) { await readGround() }
        }
    }

    // MARK: Heads

    @ViewBuilder private var videoHead: some View {
        MediaVideoFrame(thing: thing, start: start, onOpen: onOpen)
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text(verbatim: MediaSheetBox.title(thing))
                .dsText(.heading24)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Space.s3) {
                BridgeIcon(name: thing.source, size: DS.Face.badge * 1.8, circular: true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: channel ?? thing.source)
                        .dsText(.heading17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    whenLine(lead: channel == nil ? nil : thing.source)
                }
            }
        }
        .padding(.horizontal, DSRoomChassis.leadInset)
        .padding(.top, DS.Space.s4)
    }

    @ViewBuilder private var songHead: some View {
        MediaCover(thing: thing)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 20, y: 12)
            .padding(.horizontal, DS.Space.s8)
            .padding(.top, DS.Space.s6)
            .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: MediaSheetBox.title(thing))
                .dsText(.heading24)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let artist = TitleSeam.split(thing.title).line {
                Text(verbatim: artist)
                    .dsText(.heading20)
                    .fontWeight(.regular)
                    .foregroundStyle(DS.textSecondary)
            }
            if let album {
                Text(verbatim: album)
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(2)
                    .padding(.top, DS.Space.s1)
            }
            whenLine(lead: nil)
        }
        .padding(.horizontal, DSRoomChassis.leadInset)
        .padding(.top, DS.Space.s6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var episodeHead: some View {
        HStack(spacing: DS.Space.s4) {
            MediaCover(thing: thing)
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: channel ?? thing.source)
                    .dsText(.heading17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(2)
                whenLine(lead: nil)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DSRoomChassis.leadInset)
        .padding(.top, DS.Space.s6)
        Text(verbatim: MediaSheetBox.title(thing))
            .dsText(.heading28)
            .foregroundStyle(DS.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DSRoomChassis.leadInset)
            .padding(.top, DS.Space.s4)
        if let audio = EpisodePlayer.audioURL(thing) {
            EpisodePlayerView(url: audio, chapters: words.chapters, seek: $start)
                .padding(.horizontal, DSRoomChassis.leadInset)
                .padding(.top, DS.Space.s4)
        }
    }

    /// "<lead> · Today 9:14 PM": the day in the divider's ink (§882).
    private func whenLine(lead: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s1) {
            if let lead {
                Text(verbatim: "\(lead) ·")
                    .foregroundStyle(DS.textSecondary)
                    .layoutPriority(-1)
            }
            Text(FeedScreen.dayWord(thing.capturedAt))
                .foregroundStyle(DS.headInk)
            Text(verbatim: thing.capturedAt.formatted(date: .omitted, time: .shortened))
                .foregroundStyle(DS.textSecondary)
        }
        .dsText(.body17)
        .lineLimit(1)
    }

    // MARK: Chapters

    private var chapterRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(words.chapters) { chapter in
                Button {
                    DSHaptic.tap()
                    start = chapter.seconds
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
                        Text(verbatim: chapter.stamp)
                            .dsText(.body17)
                            .monospacedDigit()
                            .foregroundStyle(DS.pickInk)
                            .frame(minWidth: 48, alignment: .leading)
                        Text(verbatim: chapter.label)
                            .dsText(.body17)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, DS.Space.s2)
                    .padding(.horizontal, DSRoomChassis.leadInset)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .accessibilityLabel(Text(verbatim: "\(chapter.label), \(chapter.stamp)"))
            }
        }
    }

    // MARK: Facts

    private var channel: String? {
        let handle = (thing.authorHandle ?? "").trimmingCharacters(in: .whitespaces)
        return handle.isEmpty ? nil : handle
    }

    /// The album Spotify's own line names ("From The Campfire Headphase
    /// (2005)"), without the "From".
    private var album: String? {
        let line = (thing.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("From ") else { return nil }
        return String(line.dropFirst(5))
    }

    private func readGround() async {
        guard Self.takesGround(thing), let onGround else { return }
        var image = await StoredPixels.prepared(for: thing)?.image
        if image == nil, let url = thing.previewImageURL, !url.isEmpty,
           case .image(let art, _) = await RemoteImageLoader.load(urlString: url, targetSide: 120) {
            image = art
        }
        guard let image, let ground = ArtGround.color(from: image) else { return }
        withAnimation(DS.Motion.standard) { onGround(ground) }
    }
}

// MARK: - The cover

/// The art filling its frame: the stored picture, else the URL, else the
/// app's mark.
private struct MediaCover: View {
    let thing: Thing

    // The row can be deleted under an open sheet (liveness, `ThingRowKeying.swift`).
    var body: some View {
        if thing.isLive { live }
    }

    @ViewBuilder private var live: some View {
        Color.clear
            .overlay {
                if thing.previewImageData != nil {
                    PhotoWell(thing: thing)
                } else if let url = thing.previewImageURL, !url.isEmpty {
                    GeometryReader { geo in
                        RemoteArt(urlString: url, width: geo.size.width, height: geo.size.height,
                                  fallback: thing.source, cornerRadius: 0)
                    }
                } else {
                    ZStack {
                        DS.fillFaint
                        BridgeIcon(name: thing.source, size: DS.Mark.hero)
                    }
                }
            }
            .clipped()
    }
}

// MARK: - The video

/// The frame edge to edge, playing here when it is a YouTube video (§1092);
/// a chapter's press starts it at the chapter. Anything else opens.
private struct MediaVideoFrame: View {
    let thing: Thing
    let start: Int?
    var onOpen: (() -> Void)?
    @Environment(ShellChrome.self) private var chrome: ShellChrome?
    @State private var playing = false

    private var videoID: String? {
        let text = thing.content.isEmpty ? thing.title : thing.content
        guard let url = Capture.detectURL(in: text) else { return nil }
        return YouTubeShorts.videoID(in: url.absoluteString)
    }

    // The row can be deleted under an open sheet (liveness, `ThingRowKeying.swift`).
    var body: some View {
        if thing.isLive { live }
    }

    @ViewBuilder private var live: some View {
        ZStack {
            Color.black
            if playing, let videoID {
                YouTubeEmbedView(videoID: videoID, start: start ?? 0)
                    .id(start ?? 0)
            } else {
                MediaCover(thing: thing)
                Button(action: play) {
                    Image(systemName: "play.fill")
                        .dsGlyph(.title, weight: .bold)
                        .foregroundStyle(Color.white)
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                        .contentShape(Circle())
                }
                .buttonStyle(PressSpring())
                .disabled(videoID == nil && onOpen == nil)
                .accessibilityLabel(Text("Play video"))
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
        .onChange(of: start) { _, new in
            if new != nil { play() }
        }
    }

    private func play() {
        guard videoID != nil else { onOpen?(); return }
        guard !DemoMode.isActive else {
            chrome?.flash(String(localized: "Videos play once you leave the demo."))
            return
        }
        DSHaptic.tap()
        withAnimation(DS.Motion.standard) { playing = true }
    }
}

// MARK: - The vertical frame

/// A TikTok or a reel at 9:16 across the sheet, the caption and who posted it
/// over its foot on the player's own shade.
private struct MediaVerticalFrame: View {
    let thing: Thing
    var onOpen: (() -> Void)?

    private var caption: String {
        let words = (thing.postText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return words.isEmpty ? thing.title : words
    }

    private var handle: String? {
        let raw = (thing.authorHandle ?? "").trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty, raw != "you" else { return nil }
        return raw.hasPrefix("@") ? raw : "@\(raw)"
    }

    // The row can be deleted under an open sheet (liveness, `ThingRowKeying.swift`).
    var body: some View {
        if thing.isLive { live }
    }

    @ViewBuilder private var live: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { onOpen?() } label: {
                MediaCover(thing: thing)
                    .aspectRatio(9 / 16, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [.clear, .black.opacity(0.7)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 220)
                            .allowsHitTesting(false)
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: DS.Space.s2) {
                            if let handle {
                                Text(verbatim: handle)
                                    .dsText(.heading17)
                            }
                            Text(verbatim: caption)
                                .dsText(.body17)
                                .lineLimit(4)
                                .multilineTextAlignment(.leading)
                        }
                        .foregroundStyle(Color.white)
                        .shadow(color: .black.opacity(0.5), radius: 4)
                        .padding(DSRoomChassis.leadInset)
                    }
                    .overlay {
                        Image(systemName: "play.fill")
                            .dsGlyph(.title, weight: .bold)
                            .foregroundStyle(Color.white)
                            .frame(width: 64, height: 64)
                            .background(Circle().fill(Color.black.opacity(0.45)))
                            .opacity(onOpen == nil ? 0 : 1)
                    }
                    .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: DS.Radius.sheet,
                                                      bottomTrailingRadius: DS.Radius.sheet,
                                                      style: .continuous))
            }
            .buttonStyle(PressSpring())
            .disabled(onOpen == nil)
            .accessibilityLabel(Text(verbatim: [handle, caption].compactMap { $0 }.joined(separator: ", ")))
            .accessibilityHint(Text("Opens it in \(thing.source)"))
        }
    }
}

// MARK: - The words

/// The description, three lines until More.
private struct MediaWords: View {
    let text: String
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(verbatim: text)
                .dsText(.reading17)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(open ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if !open, text.count > 140 || text.contains("\n") {
                Button {
                    withAnimation(DS.Motion.standard) { open = true }
                } label: {
                    Text("More").dsText(.body17).foregroundStyle(DS.pickInk)
                }
                .buttonStyle(RowPress())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Chapters

/// The timestamps a description already lists ("3:12 The undercling"),
/// pulled out as chapters; the rest stays the prose. Two at least, or the
/// description is left whole: one time in a paragraph is not a list.
enum MediaChapters {
    struct Chapter: Identifiable, Equatable {
        let seconds: Int
        let stamp: String
        let label: String
        var id: Int { seconds }
    }

    struct Split: Equatable {
        var prose: String
        var chapters: [Chapter]
    }

    static func split(_ text: String) -> Split {
        let lines = text.components(separatedBy: .newlines)
        var prose: [String] = []
        var chapters: [Chapter] = []
        for line in lines {
            if let chapter = chapter(in: line), !chapters.contains(where: { $0.seconds == chapter.seconds }) {
                chapters.append(chapter)
            } else {
                prose.append(line)
            }
        }
        guard chapters.count >= 2 else {
            return Split(prose: text.trimmingCharacters(in: .whitespacesAndNewlines), chapters: [])
        }
        let words = prose.joined(separator: "\n")
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Split(prose: words, chapters: chapters.sorted { $0.seconds < $1.seconds })
    }

    /// "0:00 Intro", "(12:30) The send", "1:02:03 - Outro": a stamp at the
    /// line's start, then a name.
    static func chapter(in line: String) -> Chapter? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let match = trimmed.firstMatch(of: /^[\[\(]?((?:\d{1,2}:)?\d{1,2}:\d{2})[\]\)]?\s*[-–—:·|]?\s*(.+)$/) else {
            return nil
        }
        let stamp = String(match.output.1)
        let label = String(match.output.2).trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return nil }
        let parts = stamp.split(separator: ":").compactMap { Int($0) }
        let seconds = parts.reduce(0) { $0 * 60 + $1 }
        return Chapter(seconds: seconds, stamp: stamp, label: label)
    }
}

// MARK: - The episode's player

/// An episode's audio, played here from the enclosure the feed carries
/// (`externalLink`, `RSSIngest`). One player, gone when the sheet goes.
@MainActor @Observable
final class EpisodePlayer {
    private(set) var playing = false
    private(set) var elapsed: Double = 0
    private(set) var duration: Double = 0
    private var player: AVPlayer?
    private var observer: Any?

    static func audioURL(_ thing: Thing) -> URL? {
        guard thing.source == "Podcasts", let raw = thing.externalLink,
              let url = URL(string: raw), url.scheme?.hasPrefix("http") == true else { return nil }
        return url
    }

    func toggle(_ url: URL) {
        if player == nil { load(url) }
        guard let player else { return }
        if playing { player.pause() } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
        }
        playing.toggle()
    }

    func seek(_ seconds: Int, url: URL) {
        if player == nil { load(url) }
        player?.seek(to: CMTime(seconds: Double(seconds), preferredTimescale: 1))
        elapsed = Double(seconds)
        if !playing { toggle(url) }
    }

    func stop() {
        player?.pause()
        if let observer { player?.removeTimeObserver(observer) }
        observer = nil
        player = nil
        playing = false
    }

    private func load(_ url: URL) {
        NetworkLedger.shared.record(host: url.host() ?? "", as: "Podcasts")
        let player = AVPlayer(url: url)
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 2),
                                                  queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.elapsed = time.seconds
                if let total = player.currentItem?.duration.seconds, total.isFinite { self.duration = total }
            }
        }
        self.player = player
    }
}

private struct EpisodePlayerView: View {
    let url: URL
    let chapters: [MediaChapters.Chapter]
    @Binding var seek: Int?
    @Environment(ShellChrome.self) private var chrome: ShellChrome?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var player = EpisodePlayer()

    var body: some View {
        VStack(spacing: DS.Space.s2) {
            bar
            HStack {
                Text(verbatim: Self.clock(player.elapsed))
                Spacer()
                Text(verbatim: player.duration > 0 ? Self.clock(player.duration) : "")
            }
            .dsText(.label12)
            .monospacedDigit()
            .foregroundStyle(DS.textSecondary)
            HStack(spacing: DS.Space.s8) {
                skip(-15, glyph: "gobackward.15")
                Button {
                    guard !DemoMode.isActive else {
                        chrome?.flash(String(localized: "Episodes play once you leave the demo."))
                        return
                    }
                    DSHaptic.tap()
                    player.toggle(url)
                } label: {
                    Image(systemName: player.playing ? "pause.fill" : "play.fill")
                        .dsGlyph(.title, weight: .bold)
                        .foregroundStyle(Color.black)
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(Color.white))
                        .contentShape(Circle())
                        .dsSymbolSwap(player.playing ? "pause.fill" : "play.fill")
                }
                .buttonStyle(PressSpring())
                .accessibilityLabel(Text(player.playing ? "Pause" : "Play episode"))
                skip(30, glyph: "goforward.30")
            }
        }
        .onChange(of: seek) { _, new in
            guard let new, !DemoMode.isActive else { return }
            player.seek(new, url: url)
        }
        .onDisappear { player.stop() }
    }

    /// The progress, with a mark where each chapter starts once the length
    /// is known.
    private var bar: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let fraction = player.duration > 0 ? min(1, player.elapsed / player.duration) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(DS.fillStrong).frame(height: 4)
                // The fill runs through each half-second tick of the player
                // (`addPeriodicTimeObserver`), so it moves with the sound
                // rather than stepping.
                Capsule().fill(DS.textPrimary).frame(width: w * fraction, height: 4)
                    .animation(reduceMotion ? nil : .linear(duration: 0.5), value: fraction)
                if player.duration > 0 {
                    ForEach(chapters.filter { $0.seconds > 0 }) { chapter in
                        Capsule()
                            .fill(DS.textSecondary)
                            .frame(width: 3, height: 10)
                            .offset(x: w * min(1, Double(chapter.seconds) / player.duration) - 1.5)
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxHeight: .infinity)
            // The chapter marks arrive when the length is known.
            .animation(reduceMotion ? nil : DS.Motion.standard, value: player.duration > 0)
        }
        .frame(height: 12)
        .accessibilityElement()
        .accessibilityLabel(Text("Played \(Self.clock(player.elapsed))"))
    }

    private func skip(_ by: Int, glyph: String) -> some View {
        Button {
            guard !DemoMode.isActive else { return }
            DSHaptic.tap()
            player.seek(max(0, Int(player.elapsed) + by), url: url)
        } label: {
            Image(systemName: glyph)
                .dsGlyph(.title, weight: .semibold)
                .foregroundStyle(DS.textPrimary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(Text(by < 0 ? "Back 15 seconds" : "Forward 30 seconds"))
    }

    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - A picture's sheet (prd §1650)

/// A screenshot's or a photo's name over one line: the app and when.
struct ShotSheetHead: View {
    let thing: Thing

    // The row can be deleted under an open sheet (liveness, `ThingRowKeying.swift`).
    var body: some View {
        if thing.isLive { live }
    }

    @ViewBuilder private var live: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: TitleSeam.split(thing.title).name)
                .dsText(.heading24)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            // The title's second half (§915) on its own line, whole.
            if let line = TitleSeam.split(thing.title).line, !line.isEmpty {
                Text(verbatim: line)
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(2)
            }
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s1) {
                Text(verbatim: "\(BridgeCatalog.seatName(forSource: thing.source)) ·")
                    .foregroundStyle(DS.textSecondary)
                    .layoutPriority(-1)
                Text(FeedScreen.dayWord(thing.capturedAt))
                    .foregroundStyle(DS.headInk)
                Text(verbatim: thing.capturedAt.formatted(date: .omitted, time: .shortened))
                    .foregroundStyle(DS.textSecondary)
            }
            .dsText(.body17)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DSRoomChassis.leadInset)
        .accessibilityElement(children: .combine)
    }
}

/// The picture whole at the column's width, at its own shape (§1102): the
/// ratio is read once off the stored picture, a 3:4 well until it is.
struct ShotWhole: View {
    let thing: Thing
    @State private var ratio: CGFloat?

    // The row can be deleted under an open sheet (liveness, `ThingRowKeying.swift`).
    var body: some View {
        if thing.isLive { live }
    }

    @ViewBuilder private var live: some View {
        PhotoWell(thing: thing, anchor: .top, readsFolder: true)
            .aspectRatio(ratio ?? 3 / 4, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous))
            .task(id: thing.id) {
                if let size = StoredPixels.probe(thing), size.height > 0 { ratio = size.width / size.height }
            }
    }
}
