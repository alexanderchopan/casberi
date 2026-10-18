import SwiftUI

/// A POST, A MAIL AND AN ARTICLE IN THE ROOM'S FRAME (prd §1188, the design
/// canvas "Thing sheets, the Apple pass", Reading and messages): the title is
/// who or what it is from — the person, the sender, the publication — and the
/// box says the one thing big: the post's words, the subject, the headline.
/// A long headline or subject moves into the box, where it can take lines the
/// title row cannot.

// MARK: - A post

/// A post in the room's frame (prd §1188, re-laid by §1192): its picture
/// fills the box when it has one, with who and when over its foot; else the
/// person stands in it — their face, handle, network and time, and what the
/// network counted. The words are never in the box: they stand whole, once,
/// under the tiles.
/// The post sheet's facts and parts (prd §1397): its title, its face, its
/// picture, its counts. The box that drew them stood over the tiles until
/// the centred head took the person and the picture went under them.
@MainActor enum PostSheetBox {

    /// The title row's name: the author's own name, else the handle.
    static func title(_ thing: Thing) -> String {
        let name = (thing.postAuthor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        let handle = SocialThread.shortHandle(thing.authorHandle ?? thing.source)
        // YOUR OWN POST is not titled "you" over "@you" (the sweep): your
        // name, else what the post says first.
        if ChatBubbles.isMine(handle) {
            if DemoMode.isActive { return HomeScope.demoName }
            if let yours = ProfileStore.shared.name, !yours.isEmpty { return yours }
            let first = SocialSheetSource.words(for: thing)
                .split(whereSeparator: \.isNewline).first.map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            if !first.isEmpty { return first }
        }
        return handle
    }

    /// The picture the box leads with, when the post has one.
    static func leadPicture(_ thing: Thing) -> String? {
        let first = thing.imageURLs.first ?? thing.previewImageURL
        guard let url = first, !url.isEmpty, !RemoteImageLoader.isDead(url) else { return nil }
        return url
    }

    /// Whether the picture fills the box (and so stands down below).
    static func picturesTheBox(_ thing: Thing) -> Bool {
        leadPicture(thing) != nil || (thing.imageURLs.isEmpty && thing.previewImageData != nil)
    }

    /// What the network counted, only where it counted something.
    /// The author's face at a size (prd §1397): the centred head's.
    @ViewBuilder static func face(_ thing: Thing, size: CGFloat) -> some View {
        if let avatar = thing.authorAvatarURL, !avatar.isEmpty {
            RemoteThumb(urlString: avatar, size: size, fallback: thing.source, circular: true)
        } else {
            BridgeIcon(name: thing.source, size: size, circular: true)
        }
    }

    /// The post's picture, filling whatever frame it is given (prd §1397):
    /// under the tiles, since the head is the person.
    @ViewBuilder static func picture(_ thing: Thing) -> some View {
        if let url = leadPicture(thing) {
            GeometryReader { geo in
                RemoteArt(urlString: url, width: geo.size.width,
                          height: geo.size.height, cornerRadius: 0)
            }
        } else {
            PhotoWell(thing: thing)
        }
    }

    static func counts(_ thing: Thing) -> [String] {
        var out: [String] = []
        if let likes = thing.likeCount, likes > 0 {
            out.append(likes == 1 ? String(localized: "1 like") : String(localized: "\(likes) likes"))
        }
        if let replies = thing.replyCount, replies > 0 {
            out.append(replies == 1 ? String(localized: "1 reply") : String(localized: "\(replies) replies"))
        }
        return out
    }

}

// MARK: - A mail

struct ArticleSheetBox: View {
    let thing: Thing
    /// Under the centred head (prd §1397): the picture and the headline
    /// under the tiles, at their own height; the head said the rest.
    var headed: Bool = false

    /// The title row: who published it.
    static func publication(_ thing: Thing) -> String {
        let handle = (thing.authorHandle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return handle.isEmpty ? thing.source : handle
    }

    /// The picture's height inside the box, the headline under it.
    private static let artHeight: CGFloat = 96

    var body: some View {
        if thing.isLive {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                if ArticleSheetHead.hasArt(thing) {
                    art
                        .frame(height: headed ? ThingSheetView.sheetArtHeight : Self.artHeight)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: headed ? DS.Radius.widget : DS.Radius.widget / 2,
                                                    style: .continuous))
                }
                Text(verbatim: TitleSeam.split(thing.title).name)
                    .dsText(ArticleSheetHead.hasArt(thing) && !headed ? .heading20 : .heading24)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(headed ? 4 : ArticleSheetHead.hasArt(thing) ? 2 : 4)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                if !headed {
                    Spacer(minLength: 0)
                    Text(verbatim: metaLine)
                        .dsText(.label12)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: headed ? nil : .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
        }
    }

    /// "Quanta Magazine · 9 min read · Tuesday", the author when it is not
    /// the publication.
    private var metaLine: String {
        let author = (thing.postAuthor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !author.isEmpty, author != Self.publication(thing) { parts.append(author) }
        if let minutes = ArticleSheetHead.readingMinutes(thing) {
            parts.append(String(localized: "\(minutes) min read"))
        }
        parts.append(FeedScreen.dayWord(thing.capturedAt))
        return parts.joined(separator: " · ")
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
