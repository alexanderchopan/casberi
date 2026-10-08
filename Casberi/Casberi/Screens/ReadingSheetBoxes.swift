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
struct PostSheetBox: View {
    let thing: Thing
    var onFace: (() -> Void)? = nil

    /// The title row's name: the author's own name, else the handle.
    static func title(_ thing: Thing) -> String {
        let name = (thing.postAuthor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? SocialThread.shortHandle(thing.authorHandle ?? thing.source) : name
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

    var body: some View {
        if thing.isLive {
            if Self.picturesTheBox(thing) { pictureBox } else { personBox }
        }
    }

    private var whereLine: String {
        ["@\(SocialThread.shortHandle(thing.authorHandle ?? ""))", thing.source,
         FeedScreen.dayWord(thing.capturedAt)].joined(separator: " · ")
    }

    private var pictureBox: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let url = Self.leadPicture(thing) {
                    GeometryReader { geo in
                        RemoteArt(urlString: url, width: geo.size.width,
                                  height: geo.size.height, cornerRadius: 0)
                    }
                } else {
                    PhotoWell(thing: thing)
                }
            }
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                .frame(height: 64)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
            Text(verbatim: whereLine)
                .dsText(.label12)
                .fontWeight(.semibold)
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .padding(DS.Space.s3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(Self.title(thing)), \(whereLine)"))
    }

    private var personBox: some View {
        VStack(spacing: DS.Space.s2) {
            face.padding(.top, DS.Space.s1)
            Text(verbatim: "@\(SocialThread.shortHandle(thing.authorHandle ?? ""))")
                .dsText(.heading20)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            Text(verbatim: "\(thing.source) · \(FeedScreen.dayWord(thing.capturedAt)), \(thing.capturedAt.formatted(date: .omitted, time: .shortened))")
                .dsText(.subhead12)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            let counts = Self.counts(thing)
            if !counts.isEmpty {
                HStack(spacing: DS.Space.s2) {
                    ForEach(counts, id: \.self) { DSStamp(word: $0) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var face: some View {
        let mark = Group {
            if let avatar = thing.authorAvatarURL, !avatar.isEmpty {
                RemoteThumb(urlString: avatar, size: DS.Face.profile,
                            fallback: thing.source, circular: true)
            } else {
                BridgeIcon(name: thing.source, size: DS.Face.profile, circular: true)
            }
        }
        if let onFace {
            Button {
                DSHaptic.tap()
                onFace()
            } label: { mark }
                .buttonStyle(PressSpring())
                .accessibilityLabel(Text("Open profile"))
        } else {
            mark
        }
    }
}

// MARK: - A mail

struct MailSheetBox: View {
    let thing: Thing
    let sender: String?
    let address: String?

    var body: some View {
        if thing.isLive {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                HStack(spacing: DS.Space.s2) {
                    if let sender {
                        SenderInitial(sender: sender, size: DS.Face.seat)
                    } else {
                        BridgeIcon(name: thing.source, size: DS.Face.seat, circular: true)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        if let address {
                            Text(verbatim: address)
                                .dsText(.label12)
                                .foregroundStyle(DS.textSecondary)
                                .lineLimit(1)
                        }
                        Text(verbatim: "\(thing.source) · \(when)")
                            .dsText(.label12)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                    }
                }
                Text(verbatim: thing.title)
                    .dsText(.heading20)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let attached {
                    DSStamp(word: attached, glyph: "paperclip")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
        }
    }

    /// "Today, 2:54 PM".
    private var when: String {
        "\(FeedScreen.dayWord(thing.capturedAt)), \(thing.capturedAt.formatted(date: .omitted, time: .shortened))"
    }

    /// What came with it, as the mail's own fact names it (`MailIngest`).
    private var attached: String? {
        thing.factList.first { $0.label == MailIngest.attachedLabel }?.value
    }
}

// MARK: - An article

struct ArticleSheetBox: View {
    let thing: Thing

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
                        .frame(height: Self.artHeight)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget / 2, style: .continuous))
                }
                Text(verbatim: TitleSeam.split(thing.title).name)
                    .dsText(ArticleSheetHead.hasArt(thing) ? .heading20 : .heading24)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(ArticleSheetHead.hasArt(thing) ? 2 : 4)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(verbatim: metaLine)
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
