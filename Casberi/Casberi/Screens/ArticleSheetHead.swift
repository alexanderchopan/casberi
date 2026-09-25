import SwiftUI

/// An article's sheet opens like the room it came from (prd §882).
///
/// The generic sheet set an article as a source line, a title sized by
/// length, then a 140pt picture inside the body — the same head a note or a
/// task gets. An article is the one thing people come to the sheet to READ,
/// so it leads the way its room's cover does: the picture fills the lead's
/// well (`DSRoomChassis.leadHeight`, the box every room's cover stands in),
/// then who published it and the day, the headline at the head rung, and who
/// wrote it.
///
/// **No picture, no well.** A 316pt box with only words at its foot read as
/// a picture that failed to load (the user, on the mock), so a thing with no
/// art starts at the publication line — the same give-way §772 rules for a
/// cover with nothing to fill its box. The decision is made from the RECORD
/// before layout (stored pixels, a stored URL not known dead), never from a
/// fetch, so the head cannot jump from one shape to the other while open.
///
/// **The day is pink, and it is the day divider's word.** The sheet has no
/// divider, so the eyebrow's day does the divider's job; it reads
/// `FeedScreen.dayWord`, the divider's own function, so it can only ever say
/// a day ("Yesterday", "Tuesday, September 14") — never an age or a clock.
/// It is the only brand ink on the sheet (`day-divider-audit.py` check 5).
///
/// **Nothing here was written by a model.** The headline, the publication and
/// the byline are the publisher's; the reading time is a count of the words
/// the sheet draws below, shown only when there is an article's worth of them.
struct ArticleSheetHead: View {
    let thing: Thing
    /// The publication line's door to its room — nil where the source has no
    /// room to leave for (the eyebrow's own rule, `Corpus.earnsRoom`).
    var onSource: (() -> Void)? = nil

    /// Past this many characters the headline is a sentence, not a head, and
    /// takes `heading24`: four lines of `heading40` on a phone is the most a
    /// head may be before it pushes the dial under the fold.
    static let headLength = 64
    /// Fewer words than this is a feed's one-line stand-in, not an article,
    /// and a "1 min read" over it would describe nothing.
    static let readingFloor = 200
    /// Words a minute for the reading time — the common adult silent-reading
    /// figure, rounded.
    static let wordsPerMinute = 230

    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if Self.hasArt(thing) {
                art
                    .frame(height: DSRoomChassis.leadHeight)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.bottom, DS.Space.s6)
            }
            // The title's seam (prd §915): the object is the head, the
            // qualifier — the game, the board — one quiet line under it.
            let seam = TitleSeam.split(thing.title)
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                eyebrow
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text(seam.name)
                        .dsText(Self.headStyle(for: seam.name))
                        .foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if let line = seam.line {
                        Text(verbatim: line)
                            .dsText(.body17)
                            .foregroundStyle(DS.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                byline
            }
            .padding(.horizontal, DSRoomChassis.leadInset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The picture

    /// Whether the record carries a picture this head can draw — decided
    /// before layout, so the well is there from the first frame or not at all.
    static func hasArt(_ thing: Thing) -> Bool {
        if thing.previewImageData != nil { return true }
        guard let url = thing.previewImageURL, !url.isEmpty else { return false }
        return !RemoteImageLoader.isDead(url)
    }

    /// The room cover's own two paths (`FeedLedeCard.art`), at the well's size.
    @ViewBuilder private var art: some View {
        if thing.previewImageData != nil {
            PhotoWell(thing: thing)
        } else if let url = thing.previewImageURL, !url.isEmpty {
            GeometryReader { geo in
                RemoteArt(urlString: url,
                          width: geo.size.width,
                          height: DSRoomChassis.leadHeight,
                          cornerRadius: 0)
            }
        }
    }

    // MARK: - Who published it, and the day

    private var publication: String {
        let handle = (thing.authorHandle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return handle.isEmpty ? thing.source : handle
    }

    @ViewBuilder private var eyebrow: some View {
        if let onSource {
            Button {
                DSHaptic.tap()
                onSource()
            } label: {
                eyebrowLine.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsHover()
        } else {
            eyebrowLine
        }
    }

    private var eyebrowLine: some View {
        HStack(spacing: DS.Space.s2) {
            publisherDisc
            Text(verbatim: publication)
                .dsText(.label12)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
            Spacer(minLength: DS.Space.s2)
            Text(FeedScreen.dayWord(thing.capturedAt))
                .dsText(.label12)
                .foregroundStyle(DS.brandInk)
                .lineLimit(1)
        }
    }

    @ViewBuilder private var publisherDisc: some View {
        if let avatar = thing.authorAvatarURL, !avatar.isEmpty {
            RemoteThumb(urlString: avatar, size: DS.Face.row,
                        fallback: thing.source, circular: true)
        } else {
            BridgeIcon(name: thing.source, size: DS.Face.row, circular: true)
        }
    }

    // MARK: - Who wrote it

    private var author: String? {
        let name = (thing.postAuthor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name == publication ? nil : name
    }

    /// Minutes to read the words the sheet draws — nil under `readingFloor`.
    static func readingMinutes(_ thing: Thing) -> Int? {
        let words = (thing.enrichedText ?? "")
            .split(whereSeparator: { $0.isWhitespace })
            .count
        guard words >= readingFloor else { return nil }
        return max(1, Int((Double(words) / Double(wordsPerMinute)).rounded(.up)))
    }

    static func headStyle(for title: String) -> DSTextStyle {
        title.trimmingCharacters(in: .whitespacesAndNewlines).count <= headLength
            ? .heading40 : .heading24
    }

    @ViewBuilder private var byline: some View {
        let minutes = Self.readingMinutes(thing)
        if author != nil || minutes != nil {
            HStack(spacing: DS.Space.s2) {
                if let author {
                    // A byline carries no picture on any feed we read, so the
                    // face is the name's first letter (§753's rule for a face
                    // with no picture).
                    Text(verbatim: String(author.prefix(1)).uppercased())
                        .dsText(.badgeInitial12)
                        .foregroundStyle(DS.textPrimary)
                        .frame(width: DS.Face.row, height: DS.Face.row)
                        .background(Circle().fill(DS.fillLine))
                        .accessibilityHidden(true)
                    Text(verbatim: author)
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                }
                if let minutes {
                    Text("\(minutes) min read")
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.top, DS.Space.s1)
        }
    }
}
