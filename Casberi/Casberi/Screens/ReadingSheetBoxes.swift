import SwiftUI

/// A POST, A MAIL AND AN ARTICLE IN THE ROOM'S FRAME (prd §1188, the design
/// canvas "Thing sheets, the Apple pass", Reading and messages): the title is
/// who or what it is from — the person, the sender, the publication — and the
/// box says the one thing big: the post's words, the subject, the headline.
/// A long headline or subject moves into the box, where it can take lines the
/// title row cannot.

// MARK: - A post

struct PostSheetBox: View {
    let thing: Thing
    var onFace: (() -> Void)? = nil

    /// The title row's name: the author's own name, else the handle.
    static func title(_ thing: Thing) -> String {
        let name = (thing.postAuthor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? SocialThread.shortHandle(thing.authorHandle ?? thing.source) : name
    }

    var body: some View {
        if thing.isLive {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                HStack(spacing: DS.Space.s2) {
                    face
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "@\(SocialThread.shortHandle(thing.authorHandle ?? ""))")
                            .dsText(.label12)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                        Text(verbatim: whereLine)
                            .dsText(.label12)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                    }
                }
                Text(verbatim: SocialSheetSource.words(for: thing))
                    .dsText(.heading20)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !stamps.isEmpty {
                    HStack(spacing: DS.Space.s2) {
                        ForEach(stamps, id: \.self) { DSStamp(word: $0) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
        }
    }

    /// "Bluesky · replying to @ana · Wednesday".
    private var whereLine: String {
        [thing.source, SocialThread.contextPhrase(for: thing), FeedScreen.dayWord(thing.capturedAt)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// What the network counted, only where it counted something.
    private var stamps: [String] {
        var out: [String] = []
        if let likes = thing.likeCount, likes > 0 {
            out.append(likes == 1 ? String(localized: "1 like") : String(localized: "\(likes) likes"))
        }
        if let replies = thing.replyCount, replies > 0 {
            out.append(replies == 1 ? String(localized: "1 reply") : String(localized: "\(replies) replies"))
        }
        return out
    }

    /// Whether the box cut the words, so the sheet sets them whole under the
    /// tiles. A count stands in for a measurement: four lines of the box
    /// hold about this many characters on the narrowest phone.
    static func cutsWords(_ thing: Thing) -> Bool {
        SocialSheetSource.words(for: thing).count > 140
    }

    @ViewBuilder private var face: some View {
        let mark = Group {
            if let avatar = thing.authorAvatarURL, !avatar.isEmpty {
                RemoteThumb(urlString: avatar, size: DS.Face.seat,
                            fallback: thing.source, circular: true)
            } else {
                BridgeIcon(name: thing.source, size: DS.Face.seat, circular: true)
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
