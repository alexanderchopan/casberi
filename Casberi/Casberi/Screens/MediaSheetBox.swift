import SwiftUI

/// A TRACK, A VIDEO, AN EPISODE IN THE ROOM'S FRAME (prd §1186, the design
/// canvas "Thing sheets, the Apple pass"): the title is the sheet's room
/// title, and the box is the thing — a video's frame fills it, edge to edge,
/// a door to watching it; a cover or show art stands square beside the
/// service, the artist, the album and when you played it.
struct MediaSheetBox: View {
    /// The services whose rows are media, not links.
    static let sources: Set<String> = ["Spotify", "Apple Music", "YouTube", "Podcasts", "Twitch"]

    static func isMedia(_ thing: Thing) -> Bool {
        thing.kind == .link && sources.contains(thing.source)
    }

    let thing: Thing
    var onOpen: (() -> Void)? = nil

    static func isVideo(_ thing: Thing) -> Bool {
        thing.source == "YouTube" || thing.source == "Twitch"
    }

    /// The song, stream or episode alone, off the app's one seam (§915).
    static func title(_ thing: Thing) -> String { TitleSeam.split(thing.title).name }

    var body: some View {
        if thing.isLive {
            if Self.isVideo(thing) { video } else { cover }
        }
    }

    private var video: some View {
        Button { onOpen?() } label: {
            ZStack {
                artFill
                // The player's own shade at the frame's foot, so the channel
                // reads on a white thumbnail as on a dark one.
                VStack {
                    Spacer()
                    LinearGradient(colors: [.clear, .black.opacity(0.6)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 72)
                }
                .allowsHitTesting(false)
                Image(systemName: "play.fill")
                    .dsGlyph(.title, weight: .bold)
                    .foregroundStyle(Color.white)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(Color.black.opacity(0.55)))
                VStack {
                    Spacer()
                    HStack {
                        Text(verbatim: "\(who) · \(thing.capturedAt.formatted(.relative(presentation: .named)))")
                            .dsText(.label12)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.6), radius: 4)
                        Spacer(minLength: 0)
                    }
                }
                .padding(DS.Space.s3)
            }
        }
        .buttonStyle(PressSpring())
        .disabled(onOpen == nil)
        .accessibilityLabel(Text(verbatim: "\(Self.title(thing)), \(who)"))
        .accessibilityHint(Text("Opens the video"))
    }

    private var cover: some View {
        HStack(alignment: .center, spacing: DS.Space.s4) {
            artFill
                .frame(width: 176, height: 176)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: thing.source)
                    .dsText(.label12).foregroundStyle(DS.textSecondary).lineLimit(1)
                if let artist {
                    Text(verbatim: artist)
                        .dsText(.heading20).foregroundStyle(DS.textPrimary)
                        .lineLimit(2).minimumScaleFactor(0.8)
                        .padding(.top, DS.Space.s3)
                }
                if let album {
                    Text(verbatim: album)
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                        .lineLimit(2).minimumScaleFactor(0.8)
                }
                Spacer(minLength: DS.Space.s2)
                Text(verbatim: thing.capturedAt.formatted(.dateTime.weekday(.wide).hour().minute()))
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: 176, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// The art filling whatever frame it is given, cropped to it.
    private var artFill: some View {
        Color.clear
            .overlay {
                if thing.previewImageData != nil {
                    PhotoWell(thing: thing)
                } else if let url = thing.previewImageURL, !url.isEmpty {
                    GeometryReader { geo in
                        RemoteArt(urlString: url, width: geo.size.width,
                                  height: geo.size.height, cornerRadius: 0)
                    }
                } else {
                    BridgeIcon(name: thing.source, size: DS.Mark.hero)
                }
            }
            .clipped()
    }

    private var isMusic: Bool { thing.source == "Spotify" || thing.source == "Apple Music" }

    /// The channel or the show, where the row stamps one; else the service.
    private var who: String {
        if !isMusic, let handle = thing.authorHandle?.trimmingCharacters(in: .whitespaces),
           !handle.isEmpty { return handle }
        return thing.source
    }

    private var artist: String? {
        isMusic ? TitleSeam.split(thing.title).line : (who != thing.source ? who : nil)
    }

    /// The album Spotify's own line names ("From The Campfire Headphase").
    private var album: String? {
        let line = (thing.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard isMusic, line.hasPrefix("From ") else { return nil }
        return String(line.dropFirst(5))
    }
}
