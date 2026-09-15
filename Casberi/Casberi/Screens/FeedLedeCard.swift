import SwiftUI

/// The newest thing, at size — the All feed's cover (prd §389, 2026-08-16).
///
/// The feed opens on a band row like every other row, so the thing that just
/// landed looks exactly like the thing that landed on Tuesday. This promotes
/// the newest single to a card at the top of the feed.
///
/// **It is positional, never editorial.** The pick is "the newest row", full
/// stop — no ranking, no score, no claim that this is the day's most important
/// thing (the §83 fake-status ban: a hero implies a judgement, so the only
/// honest hero is one whose rule you can state in four words). §254's own
/// promotion — the day's one picture at reading size — is the same instinct
/// held to a different question.
///
/// It is a CARD, and that is a deliberate second rhythm-breaker. Ruling
/// 2026-07-06 made the band the one row anatomy and §254 refused a full-width
/// banner under a title on exactly that grounds — but §254 was promoting a row
/// IN the run, where a second anatomy would break the run's silhouette. This
/// sits ABOVE the run as the feed's first object, the way `ApprovalCard`
/// already stands out of it, so the rhythm it breaks is one it precedes.
///
/// **It never declines for want of a picture** (§389 amendment, user: "we
/// should still show it but in a nice card somehow"). `FeedLedeFace` picks one
/// of four faces; since §749 none of them takes a ground.
///
/// **The colour ground is withdrawn (prd §749).** The pictureless faces stood
/// on `DS.deckFill`, the brand's hue solved for white ink, under the reasoning
/// that one cover per feed is the one bright object a screen may spend. The
/// user ruled the cover unbacked in every room, so the deck, the pour and the
/// shadow are gone and the card reads its tokens against the page like a row.
///
/// **Still no invented picture.** A face is never a photograph we did not
/// have; decoration in the picture's slot is a claim that there was something
/// to see (`AssetMark`'s no-invented-hue rule, one medium over).
///
/// **A POST IS COVERED AS A POST (prd §756).** §732 let a post card decline the
/// cover, so the rooms whose newest thing is nearly always a post — every social
/// room — were the ones that never got one. The post yields its card instead:
/// the row is lifted out of its run as usual, and this card draws it with the
/// AUTHOR's face and name (a post's row leads with the person, §744, so a cover
/// attributing it to `Farcaster` would be the one place in the app that does
/// not) and with the whole `postText` rather than `title`, which is an
/// 80-character clamp written for a row with no room. Three lines, one question
/// — `SocialRoomSource` answers all of them, because a second place deciding
/// what a post is drifts (§396a).
struct FeedLedeCard: View {
    let thing: Thing
    /// The Mac keyboard walk's selection. Taken as a parameter rather than
    /// drawn behind the row (`selectionWash`) because this card paints its own
    /// opaque surface — a wash underneath it would be invisible. Only ever
    /// true on Mac; `ShellChrome.canWalk` is Mac-only.
    var selected: Bool = false

    /// The art's height. Fixed rather than an aspect ratio so the card's own
    /// height is known before the image resolves — a ratio would restate the
    /// row's height when the picture lands, which in a `List` reflows every
    /// row below it. 16:9 at a phone's content width is ~178pt; this is that,
    /// rounded to the space scale.
    private static let artHeight: CGFloat = 176

    /// Liveness guard (build 188 — see `ThingRowKeying.swift`). SwiftUI
    /// re-evaluates a LEAF view's body on the model's own observation,
    /// independent of the parent that built it, so the `.live` check in
    /// `bundledSections`' own closure cannot protect this card once it is in
    /// the tree.
    var body: some View {
        if thing.isLive { liveBody }
    }

    /// **NO BACKING (prd §749, user: "the most recent item in a lede card w/o
    /// backing like we do on the home page and on music and on rss").** The
    /// cover stands on the page's own ink like the rows under it: no fill, no
    /// brand deck, no pour, no shadow. The picture keeps its own rounded
    /// corners, because a photograph needs an edge; the words sit in the rows'
    /// column, so the cover reads as the room's first object rather than a
    /// box above it. On Home, music and the reading list this was already how
    /// it looked in dark (a picture on `surfaceSheet`, which is black); a
    /// pictureless cover was the one that showed a card, as a brand hue.
    @ViewBuilder private var liveBody: some View {
        let receipt = MoneyReceiptSource.receipt(for: thing)
        let face = FeedLedeFace.kind(isMoney: receipt != nil,
                                     hasArt: artURL != nil || thing.previewImageData != nil,
                                     hasClock: thing.dueAt != nil)
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if face == .picture {
                art
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            }
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                // **THE MARK LEADS AS A DISC (prd §567) — UNLESS THE THING IS
                // A POST, AND THEN THE PERSON DOES (prd §756).** A post's own
                // row leads with the author's face and name (§744), so a cover
                // of that post leading with the network's mark would be the one
                // place in the app where a post is attributed to Farcaster
                // rather than to whoever wrote it. Same picture, same fallback
                // as `PostCard`'s lead: the avatar when there is one, the seat's
                // mark when there is not.
                postDisc
                    .padding(.bottom, DS.Space.s1)
                switch face {
                case .picture:         titleBlock(underArt: true)
                case .words:           titleBlock(underArt: false)
                case .money:           moneyBlock(receipt)
                case .clock:           clockBlock
                }
                eyebrow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // The Mac walk's selection — the one surface the cover may wear, bled
        // past the content so the words do not touch its edge.
        .background {
            if selected {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.tintDim)
                    .padding(-DS.Space.s3)
            }
        }
    }

    // MARK: - Faces

    /// **THE TITLE TAKES THE HEAD RUNG, BY LENGTH (prd §567).**
    ///
    /// This card is §389's "first object" — the newest thing, promoted out of
    /// the run — and it wore `heading22`, the same rung as the day divider
    /// directly above it. It takes `heading34` when it is a STATEMENT, which
    /// is `ThingSheetView`'s own rule (`> 100 ? .heading22 : .heading34`) at
    /// this card's width: at 40pt heavy on a 354pt card a line holds roughly
    /// fourteen characters, so the threshold is what fits four lines rather
    /// than the sheet's number.
    ///
    /// A paragraph never takes it. §559: at the head rung a long title is a
    /// sentence set as a headline, and the rung stops meaning anything the
    /// first time it wraps to six lines.
    ///
    /// **The picture face left this rule on 2026-09-14 (§734, below).** The
    /// length threshold now decides only the faces that have no picture, which
    /// is where it was always doing the work it claims to.
    private static let statementLimit = 56

    /// **UNDER A PICTURE THE TITLE IS A CAPTION, NOT A HEAD (prd §734, user:
    /// "the header card seems too large with the font so big. It basically
    /// takes up half the screen").** The head rung is for the one object a
    /// surface is about, and on the picture face that object is the picture —
    /// 176pt of it, already. Four lines of 40pt heavy under it made the card
    /// ~385pt on an 874pt phone, and §732 has just put this card at the top of
    /// every ROOM as well as the All feed, so that height is now the first
    /// thing on a dozen screens rather than one.
    ///
    /// The picture face alone drops to `heading22` at two lines, and gives up
    /// its excerpt: the picture, the title and the eyebrow say it three ways
    /// already, and a fourth block is what the words face exists for. The
    /// wordless faces keep the head rung untouched — a note IS its words
    /// (§567), and there is no picture there competing for the claim.
    ///
    /// The pictureless rung is also the honest one for what these titles ARE:
    /// a screenshot's title is the OCR line the heal wrote and a folder image's
    /// is its filename, so display type is the app shouting a string it
    /// assembled.
    private func titleBlock(underArt: Bool) -> some View {
        let short = words.count <= Self.statementLimit
        return VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(words)
                .dsText(underArt ? .heading22 : (short ? .heading34 : .heading22))
                .foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(underArt ? 2 : (short ? 4 : 3))
                .minimumScaleFactor(!underArt && short ? 0.8 : 1)
                .fixedSize(horizontal: false, vertical: true)
            if let note = excerpt, !underArt {
                Text(note)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The figure leads, the sentence follows — `MoneyReceipt`'s own anatomy at
    /// cover scale. Nothing here is parsed back out of a title: every string
    /// comes off the composed receipt, which is assembled from stamped fields
    /// (that type's central rule, §363).
    @ViewBuilder private func moneyBlock(_ receipt: MoneyReceipt?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let amount = receipt?.amount {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2 - 2) {
                    // `verbatim:` like the receipt card's own figure — the
                    // string is already locale-formatted or the bridge's own
                    // stamp, and must not be re-interpolated.
                    // The receipt's own hero rung (prd §567). `price40`, not
                    // `price48`: §506's crown is one per surface and this
                    // card sits under the day divider that holds it.
                    Text(verbatim: amount.number)
                        .dsText(.price40)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let unit = amount.unit {
                        Text(verbatim: unit)
                            .dsText(.label12)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                    }
                }
                // The tone COLOUR is deliberately dropped here. It was dropped
                // for a brand-hue ground that no longer exists (§749); it
                // stays dropped because the figure is the cover's head, not a
                // verdict. Direction is not lost — the sign is a glyph
                // inside `number` (U+2212 / "+"), which is §363's own rule and
                // the reason its spoken form spells the sign out.
                .foregroundStyle(DS.textPrimary)
            }
            // Under the figure, in the quiet tier — the amount is what the
            // row is FOR (`FeedLedeFace`'s own words for why money beats a
            // picture), and this says who it was with.
            Text(receipt.map { partyLine($0) } ?? thing.title)
                .dsText(.label12)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let sentence = receipt?.sentence, !sentence.isEmpty {
                Text(sentence)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "Received from vitalik.eth" — the receipt's lead and party as the one
    /// clause §363 made them. The lead stands alone when the counterparty was
    /// never captured, which that type documents as correct rather than
    /// missing.
    private func partyLine(_ receipt: MoneyReceipt) -> String {
        guard let party = receipt.party, !party.isEmpty else { return receipt.lead }
        return "\(receipt.lead) \(party)"
    }

    /// The countdown leads, because for a thing with a deadline the deadline is
    /// the payload — §35's "a perishable shows its countdown everywhere", on
    /// the one surface with room to say it at size.
    @ViewBuilder private var clockBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let due = thing.dueAt {
                // §35's perishable countdown, at the rung the money face
                // takes for the same reason (prd §567).
                Text(FeedLedeFace.dueLine(due))
                    .dsText(.price40)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(thing.title)
                .dsText(.label12)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let when = dueDetail {
                Text(when)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    /// The wall-clock time under the countdown — "3:00 PM", or the date when
    /// the deadline is further out than today. The countdown says how long,
    /// this says when, and a person acting on it needs both.
    private var dueDetail: String? {
        guard let due = thing.dueAt else { return nil }
        if Calendar.current.isDateInToday(due) || Calendar.current.isDateInTomorrow(due) {
            return due.formatted(date: .omitted, time: .shortened)
        }
        return due.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    // MARK: - The post face (prd §756)

    /// Whether this cover is over a POST — the one anatomy that yields its own
    /// card to the cover (prd §756, user: "we want the most recent post to be
    /// big, like it is on the all screen and that pattern should be on every
    /// screen").
    ///
    /// Asked THROUGH `SocialRoomSource.rowKind`, never spelled beside it: that
    /// is §489's rule and §396a's lesson — a second place answering "is this a
    /// post" drifts the first time one of them is fixed. It costs what the card
    /// already spends: `rowFacts` touches `previewImageData`, which `liveBody`
    /// reads on the line above to pick its face.
    private var isPost: Bool {
        SocialRoom.drawsPosts(thing.source) && SocialRoomSource.standsAlone(thing)
    }

    /// The disc: the author's picture on a post, the seat's mark on everything
    /// else — `PostCard`'s own lead, at this card's rung.
    @ViewBuilder private var postDisc: some View {
        if isPost, let avatar = thing.authorAvatarURL, !avatar.isEmpty {
            RemoteThumb(urlString: avatar, size: DS.Face.list,
                        fallback: thing.source, circular: true)
        } else {
            BridgeIcon(name: thing.source, size: DS.Face.list, circular: true)
        }
    }

    /// What the card says at size.
    ///
    /// A post's `title` is `titleLine()`'s 80-character clamp, written for a row
    /// that has no room — set as a headline it is a sentence cut mid-word with
    /// nothing saying it was cut. The cover has the room, so it takes the post
    /// itself (`SocialRoomSource.words(of:)`, the copy `PostCard` reads). Every
    /// other kind keeps its title, which for them IS the thing's name.
    private var words: String {
        isPost ? SocialRoomSource.words(of: thing) : thing.title
    }

    // MARK: - Shared pieces

    /// Who and when — the two facts the enlarged title drops by not being a
    /// band.
    /// Where it came from and when, under the thing itself (prd §567).
    ///
    /// **The icon is gone from this row and the NAME is not.** §565's rule is
    /// that a mark restating its own caption is not a mark — true where the
    /// two sit adjacent in one small cell, and the disc above is separated
    /// from this line by the title, so it heads the card rather than badging
    /// this row. The name stays because dropping it would lose the source on
    /// the feed's cover for every seat whose `BridgeIcon` has no bundled art,
    /// which is a real regression to buy a tidier line.
    private var eyebrow: some View {
        HStack(spacing: DS.Space.s2) {
            // The person leads on a post (prd §756), in the primary tier, and
            // the network follows in the quiet one — the order the row itself
            // uses, and the order that makes "who" the first thing read.
            // `verbatim:` because a handle is data, never a string to localize.
            if isPost {
                Text(verbatim: SocialRoomSource.author(of: thing))
                    .dsText(.label12)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
            }
            Text(thing.source)
                .dsText(.label12)
                .foregroundStyle(DS.textSecondary)
            LiveTimeText(date: thing.capturedAt)
        }
        .padding(.top, DS.Space.s1)
    }

    /// The remote art URL, when the row has one worth enlarging.
    private var artURL: String? {
        guard let url = thing.previewImageURL, !url.isEmpty else { return nil }
        return url
    }

    /// The picture. Stored pixels first (a screenshot, a folder image, an
    /// imported photo all carry their own bytes), then a remote URL.
    ///
    /// Both branches are pinned to a known height and clipped, never left to
    /// report an intrinsic size upward (the `scaledToFill`-in-a-ZStack trap,
    /// CLAUDE.md; `PhotoWell`'s fill mode carries its own `GeometryReader` for
    /// the same reason).
    @ViewBuilder private var art: some View {
        if thing.previewImageData != nil {
            PhotoWell(thing: thing)
                .frame(height: Self.artHeight)
                .clipped()
        } else if let url = artURL {
            GeometryReader { geo in
                RemoteArt(urlString: url,
                          width: geo.size.width,
                          height: Self.artHeight,
                          fallback: thing.source,
                          cornerRadius: 0)
            }
            .frame(height: Self.artHeight)
        }
    }

    /// The card's second line of words. `summary` only — it is the one field
    /// this app treats as DISPLAY copy (a Trello card's back, a Cursor run's
    /// summary). `content` can be a bare permalink and `enrichedText` is
    /// retrieval-only by the 2026-07-15 ruling, so neither may be drawn.
    /// Withheld when it merely repeats the title.
    private var excerpt: String? {
        guard let summary = thing.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty, summary != thing.title else { return nil }
        return summary
    }
}
