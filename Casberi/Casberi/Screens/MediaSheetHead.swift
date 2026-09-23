import SwiftUI

/// A track, a video or an episode leads with its art (prd §897).
///
/// Media had no anatomy of its own: a song drew "Link · 3d ago", its raw
/// "Song — Artist" title and a 140pt banner, the same sheet as any link. Now
/// the art fills the lead's well (a video at its own 16:9, capped at the well),
/// the shared head names who it is from — the channel or show where the row
/// stamps one, else the service — with the pink day, and the title is the
/// song alone, with the artist and the album under it.
///
/// **It wins over the article head.** A video whose description landed as a
/// body (`FeedArticleText.hasBody`) read as an article; a video is watched.
struct MediaSheetHead: View {
    let thing: Thing
    var onSource: (() -> Void)? = nil

    /// The services whose rows are media, not links.
    static let sources: Set<String> = ["Spotify", "Apple Music", "YouTube", "Podcasts", "Twitch"]

    static func isMedia(_ thing: Thing) -> Bool {
        thing.kind == .link && sources.contains(thing.source)
    }

    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if ArticleSheetHead.hasArt(thing) {
                art
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.bottom, DS.Space.s6)
            }
            SheetPartyHead(name: who, day: thing.capturedAt, line: whatLine, onFace: onSource) {
                BridgeIcon(name: thing.source, size: DS.Face.shelf, circular: true)
            }
            Text(verbatim: parts.title)
                .dsText(ThingSheetView.titleRung(for: parts.title).style)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.horizontal, DSRoomChassis.leadInset)
                .padding(.top, DS.Space.s4)
            if let byline {
                Text(verbatim: byline)
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DSRoomChassis.leadInset)
                    .padding(.top, DS.Space.s2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The art

    /// A video is 16:9; a cover and show art are square, and fill the well.
    private var aspect: CGFloat {
        thing.source == "YouTube" || thing.source == "Twitch"
            ? 9.0 / 16.0 : DSRoomChassis.leadHeight / 360
    }

    @ViewBuilder private var art: some View {
        SheetPictureFrame(aspect: aspect, cap: DSRoomChassis.leadHeight) {
            Color.clear
                .overlay {
                    if thing.previewImageData != nil {
                        PhotoWell(thing: thing)
                    } else if let url = thing.previewImageURL, !url.isEmpty {
                        GeometryReader { geo in
                            RemoteArt(urlString: url, width: geo.size.width,
                                      height: geo.size.height, cornerRadius: 0)
                        }
                    }
                }
                .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
    }

    // MARK: - The words

    private var isMusic: Bool { thing.source == "Spotify" || thing.source == "Apple Music" }

    /// "Dayvan Cowboy — Boards of Canada" as the song and the artist.
    private var parts: (title: String, artist: String?) {
        guard isMusic else { return (thing.title, nil) }
        let split = thing.title.components(separatedBy: " \u{2014} ")
        guard split.count >= 2 else { return (thing.title, nil) }
        return (split[0], split.dropFirst().joined(separator: " \u{2014} "))
    }

    /// The channel or the show, where the row stamps one; else the service.
    private var who: String {
        if !isMusic, let handle = thing.authorHandle?.trimmingCharacters(in: .whitespaces),
           !handle.isEmpty { return handle }
        return thing.source
    }

    private var whatLine: String? {
        if who != thing.source { return thing.source }
        let typeTags = Set(ThingKind.allCases.map(\.typeTag))
        return thing.tags.first { !typeTags.contains($0) }
    }

    /// "Boards of Canada · The Campfire Headphase (2005)" — the artist, and the
    /// album Spotify's own line names ("From The Campfire Headphase (2005)").
    private var byline: String? {
        let album = (thing.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let albumPart = album.hasPrefix("From ") ? String(album.dropFirst(5)) : nil
        let bits = [parts.artist, isMusic ? albumPart : nil].compactMap { $0 }
        return bits.isEmpty ? nil : bits.joined(separator: " · ")
    }
}
