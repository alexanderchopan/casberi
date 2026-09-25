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
    /// The room's head sentence when the head had nothing else to draw (prd
    /// §760) — "Nothing needs you" — under the cover, in the note's register.
    var note: String? = nil
    /// **EVERY COVER HOLDS THE BOX (prd §904).** There is no flag here for a
    /// cover to shrink by. §772 let a thin `.words` cover give way to its
    /// words, §775 made every All cover do so and §815 held the kind-tile
    /// rooms' back open — three heights for one lead, decided by three rules
    /// a reader had to know to see why Reading's well was taller than All's.
    /// The user ruled the template over the fill ("it's better when all
    /// screens have the same size"), so the one geometry is `leadHeight` in
    /// every room, and the ladder below is what fills it.

    /// The art's height. Fixed rather than an aspect ratio so the card's own
    /// height is known before the image resolves — a ratio would restate the
    /// row's height when the picture lands, which in a `List` reflows every
    /// row below it. 16:9 at a phone's content width is ~178pt; this is that,
    /// rounded to the space scale.
    private static let artHeight = DSRoomChassis.leadArtHeight

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
        // Read ONCE per body pass (§626, §628): the ladder, then the face
        // decided from it — the cast face asks whether the ladder holds a
        // cast, so the roll is never fetched twice.
        let rungs = bodyRungs
        let hasCast = rungs.contains { if case .cast = $0 { return true } else { return false } }
        let category = BridgeCatalog.category(forSource: thing.source)
        // The three batch-two facts (prd §908), each read only where its
        // category could use it — a note body is a string walk and a work
        // reading a table lookup, neither owed to a song.
        let stateWord = category == "Work" ? WorkStage.reading(workRow)?.statusWord : nil
        let prose = category == "Notes" ? NoteSheetSource.body(for: thing).text : ""
        let face = FeedLedeFace.kind(isMoney: receipt != nil,
                                     hasArt: artURL != nil || thing.previewImageData != nil,
                                     hasClock: thing.dueAt != nil,
                                     category: category,
                                     hasCast: hasCast,
                                     hasMoment: moment != nil,
                                     hasState: !(stateWord ?? "").isEmpty,
                                     hasProse: !prose.isEmpty)
        // MEDIA A (prd §907): the art is the well. No block, no inner padding,
        // no ladder — the picture fills the lead's box edge to edge, at the
        // box's own radius, the way a live stream and the anniversary photo
        // already do, and the words ride a scrim at its foot. The row's
        // insets are the same, so the box stands where every other lead does.
        if face == .mediaArt {
            mediaWell
        } else {
            wellBody(face: face, receipt: receipt, rungs: rungs,
                     stateWord: stateWord, prose: prose)
        }
    }

    /// Every face but Media's: the block, the well, the box, the ladder.
    @ViewBuilder private func wellBody(face: FeedLedeFace.Kind, receipt: MoneyReceipt?,
                                       rungs: [BodyRung], stateWord: String?,
                                       prose: String) -> some View {
        let box = DSRoomChassis.leadHeight - 2 * DS.Space.s4
        // THE LONGEST COMPOSITION THAT FITS THE LEAD'S BOX (prd §760, widened
        // by §772). It used to vary one number — the excerpt's line count, six
        // then four then two — because the excerpt was the only thing the body
        // could hold. Now the STATEMENT gives way too: it was pinned at three
        // lines while 176pt of black sat under it, so a note longer than three
        // lines was cut in a box with room for eight (§766 set the RUNG, and
        // said nothing about how many lines of it a lead may draw).
        // Spelled out, never a `ForEach`: `ViewThatFits` measures its subviews,
        // and a `ForEach` is ONE subview however many rows it makes — so a loop
        // here would offer the layout a single candidate and the fit would
        // silently stop working.
        //
        // The ladder can choose because the box is DEFINITE: `ViewThatFits`
        // fits against the height it is proposed, and the frame below proposes
        // one because `minHeight == maxHeight` (prd §904). A `List` row proposes
        // nil on its own, which is why the old shrink path could not run the
        // ladder and drew one capped spelling instead.
        let extra = Extra(stateWord: stateWord, prose: prose)
        ViewThatFits(in: .vertical) {
            cover(face, receipt: receipt, rungs: rungs, fit: Self.fits[0], extra: extra)
            cover(face, receipt: receipt, rungs: rungs, fit: Self.fits[1], extra: extra)
            cover(face, receipt: receipt, rungs: rungs, fit: Self.fits[2], extra: extra)
            cover(face, receipt: receipt, rungs: rungs, fit: Self.fits[3], extra: extra)
            cover(face, receipt: receipt, rungs: rungs, fit: Self.fits[4], extra: extra)
            cover(face, receipt: receipt, rungs: rungs, fit: Self.fits[5], extra: extra)
            cover(face, receipt: receipt, rungs: rungs, fit: Self.fits[6], extra: extra)
            cover(face, receipt: receipt, rungs: rungs, fit: Self.fits[7], extra: extra)
            cover(face, receipt: receipt, rungs: rungs, fit: Self.fits[8], extra: extra)
            cover(face, receipt: receipt, rungs: rungs, fit: Self.fits[9], extra: extra)
            cover(face, receipt: receipt, rungs: rungs, fit: Self.fits[10], extra: extra)
            cover(face, receipt: receipt, rungs: rungs, fit: Self.fits[11], extra: extra)
        }
        // Every room's lead is one height (prd §760), and since §766 the cover
        // draws it the way a head does: `dsRoomHeadBlock` — the inset, the air
        // and the well — around a box `2 × s4` shorter than the lead. It was
        // the one lead with no inner padding, so its words started 15pt higher
        // than a head's in the room next door.
        //
        // **AND THE BOX NEVER GIVES WAY (prd §904, reversing §772's give-way
        // and §775).** `minHeight == maxHeight`, in every room and the All feed
        // alike, so the same thing stands in the same well wherever it leads.
        // What the ladder cannot fill stays air, on purpose: the user weighed
        // the air against covers of three heights and chose one height.
        .frame(maxWidth: .infinity,
               minHeight: box,
               maxHeight: box,
               alignment: .topLeading)
        .clipped()
        .dsRoomHeadBlock()
        // The Mac walk's selection washes the well (prd §766). The well is the
        // cover's edge now, so the wash no longer bleeds past the content.
        .background {
            if selected {
                RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous)
                    .fill(DS.tintDim)
            }
        }
    }

    /// The two batch-two strings a face may need (prd §908), read once in
    /// `liveBody` and carried down so no spelling of the cover re-reads them.
    struct Extra {
        var stateWord: String?
        var prose: String
    }

    /// One spelling of the cover at a fit (prd §760, §772).
    private func cover(_ face: FeedLedeFace.Kind, receipt: MoneyReceipt?,
                       rungs: [BodyRung], fit: Fit, extra: Extra = Extra(stateWord: nil, prose: "")) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if face == .picture || face == .pictureAspect {
                art(height: face == .pictureAspect ? Self.tallArtHeight : Self.artHeight)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    .padding(.bottom, DS.Space.s3)
            }
            VStack(alignment: .leading, spacing: 0) {
                // **THE MARK LEADS AS A DISC (prd §567) — UNLESS THE THING IS
                // A POST, AND THEN THE PERSON DOES (prd §756).** A post's own
                // row leads with the author's face and name (§744), so a cover
                // of that post leading with the network's mark would be the one
                // place in the app where a post is attributed to Farcaster
                // rather than to whoever wrote it. Same picture, same fallback
                // as `PostCard`'s lead: the avatar when there is one, the seat's
                // mark when there is not.
                //
                // **Who and when LEAD, on one line with the disc (prd §766).**
                // The disc sat alone above the title and the source and time
                // sat under it, so a post, an article and a receipt each put
                // their statement at a different y. The eyebrow first makes it
                // one y in every room.
                // READING A (prd §907) moves the source line UNDER the title,
                // where the mock put it: the picture leads, the title names
                // it, the source says where it is from. Every other face keeps
                // the eyebrow first (§766: one y for the statement).
                if face != .pictureAspect { eyebrow(castFace: face == .cast) }
                Group {
                    switch face {
                    case .picture:         titleBlock(underArt: true, fit: fit)
                    case .pictureAspect:   tallPictureBlock
                    case .cast:            castBlock(rungs, fit: fit)
                    case .dateTile:        dateTileBlock
                    case .stateWord:       stateWordBlock(extra.stateWord ?? "", fit: fit)
                    case .prose:           proseBlock(extra.prose)
                    // Drawn by `mediaWell`, never here — see `liveBody`.
                    case .mediaArt:        EmptyView()
                    case .words:           titleBlock(underArt: false, fit: fit)
                    case .money:           moneyBlock(receipt)
                    case .clock:           clockBlock
                    }
                }
                .padding(.top, face == .pictureAspect ? 0 : DS.Space.s2)
                // THE BODY (prd §772). Under the statement, above the note and
                // the foot. `bodyBlock` draws nothing on an empty ladder, so a
                // thing with no rung pays nothing for this — not even the gap.
                //
                // **THE PICTURE FACE PASSES NONE, and that is §734 standing
                // rather than an exception to §772.** There the object is the
                // picture: `leadArtHeight` plus the eyebrow, two lines and the
                // foot already come to ~254 of the box's 286, so this face has
                // no void to fill and no room to fill one — a 56pt face shelf
                // under it would clip, which is a worse answer than the 32pt of
                // air it replaces. §734 took the excerpt off this face for the
                // same reason and on the user's own report ("the header card
                // seems too large … it basically takes up half the screen").
                bodyBlock(face.takesLadder ? rungs : [], fit: fit)
                if let note {
                    Text(note)
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DS.Space.s2)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Faces

    /// **THE TITLE TAKES THE HEAD RUNG, BY LENGTH (prd §567).**
    ///
    /// This card is §389's "first object" — the newest thing, promoted out of
    /// the run — and it wore `heading24`, the same rung as the day divider
    /// directly above it. It takes `heading40` when it is a STATEMENT, which
    /// is `ThingSheetView`'s own rule (`> 100 ? .heading24 : .heading40`) at
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
    ///
    /// **WITHDRAWN (prd §766).** Words take `heading24` and a number takes
    /// `price40`, in every lead. A head's sentence was 24 and the cover's was 40
    /// or 24 by the length of a string, so two rooms side by side set the same
    /// kind of line two sizes apart — and a room's statement changed size when
    /// its newest post got longer. The sheet keeps its own length rule; a lead
    /// is one box with one grammar.

    /// **UNDER A PICTURE THE TITLE IS A CAPTION, NOT A HEAD (prd §734, user:
    /// "the header card seems too large with the font so big. It basically
    /// takes up half the screen").** The head rung is for the one object a
    /// surface is about, and on the picture face that object is the picture —
    /// 176pt of it, already. Four lines of 40pt heavy under it made the card
    /// ~385pt on an 874pt phone, and §732 has just put this card at the top of
    /// every ROOM as well as the All feed, so that height is now the first
    /// thing on a dozen screens rather than one.
    ///
    /// The picture face alone drops to `heading24` at two lines, and gives up
    /// its excerpt: the picture, the title and the eyebrow say it three ways
    /// already, and a fourth block is what the words face exists for. The
    /// wordless faces keep the head rung untouched — a note IS its words
    /// (§567), and there is no picture there competing for the claim.
    ///
    /// The pictureless rung is also the honest one for what these titles ARE:
    /// a screenshot's title is the OCR line the heal wrote and a folder image's
    /// is its filename, so display type is the app shouting a string it
    /// assembled.
    /// **THE STATEMENT ONLY — the excerpt moved out (prd §772).** It was drawn
    /// here because it was the body's only rung; now that the body is a ladder
    /// it is one rung of it, drawn by `body(_:fit:)` beside the cast, the post
    /// and the parts. Two places drawing the summary is how the summary ends up
    /// under a cover twice, which is §709's defect one surface over.
    ///
    /// **And the line limit is the fit's, not a constant.** Three lines was the
    /// cap in a box with room for eight, so a note longer than three lines was
    /// cut with 176pt of black beneath the cut. Under a picture it stays at two:
    /// there the object is the picture (§734) and the words are its caption.
    ///
    /// **AND THE RUNG IS THE FIT'S TOO (prd §905).** §766 fixed the words at
    /// `heading24` so two rooms' statements never sat two sizes apart by the
    /// length of a string. §905 keeps that reason and moves the decision: the
    /// rung is chosen by what FITS the box, not by a character count, so the
    /// same thing takes the same rung in every room. Under a picture the words
    /// are a caption (§734) and stay at `heading24` whatever the fit says.
    private func titleBlock(underArt: Bool, fit: Fit) -> some View {
        Text(words)
            .dsText(underArt ? .heading24 : fit.statementRung)
            .foregroundStyle(DS.textPrimary)
            .multilineTextAlignment(.leading)
            .lineLimit(underArt ? 2 : fit.statementLines)
            .fixedSize(horizontal: false, vertical: true)
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
                    // `price64`: §506's crown is one per surface and this
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
                    .dsText(.subhead12)
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
                    .dsText(.subhead12)
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
    ///
    /// **On the cast face the disc is the seat's mark (user, 2026-09-24).**
    /// The cast is the picture, and the person the eyebrow names is already
    /// its first face; their avatar in the disc too drew the same face twice,
    /// one row apart.
    @ViewBuilder private func postDisc(castFace: Bool) -> some View {
        if isPost, !castFace, let avatar = thing.authorAvatarURL, !avatar.isEmpty {
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
    private func eyebrow(castFace: Bool) -> some View {
        HStack(spacing: DS.Space.s2) {
            postDisc(castFace: castFace)
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
                .lineLimit(1)
            LiveTimeText(date: thing.capturedAt)
        }
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
    @ViewBuilder private func art(height: CGFloat) -> some View {
        if thing.previewImageData != nil {
            PhotoWell(thing: thing)
                .frame(height: height)
                .clipped()
        } else if let url = artURL {
            GeometryReader { geo in
                RemoteArt(urlString: url,
                          width: geo.size.width,
                          height: height,
                          fallback: thing.source,
                          cornerRadius: 0)
            }
            .frame(height: height)
        }
    }

    // MARK: - The faces the face pass ruled (prd §907)

    /// READING A's picture height. The box is 284 on a phone; under the art
    /// go a two-line title (56), its gap (14), the source line (17) and the
    /// foot (~25) — 112 — so the picture takes the rest and a 16:9 page
    /// picture (190 at a phone's width) is cropped by a tenth, never a third.
    static let tallArtHeight: CGFloat = 170

    /// READING A: the title under the picture, two lines, then where it is
    /// from — source, the feed's name, the age — in one quiet line.
    private var tallPictureBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(words)
                .dsText(.heading24)
                .foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            sourceLine
        }
    }

    /// "RSS · OBA Research · 4m": the eyebrow's facts as a line, for the face
    /// whose picture takes the eyebrow's place.
    private var sourceLine: some View {
        HStack(spacing: DS.Space.s1) {
            Text(thing.source)
            if let by = thing.authorHandle, !by.isEmpty {
                Text(verbatim: "·")
                Text(verbatim: by)
            }
            Text(verbatim: "·")
            LiveTimeText(date: thing.capturedAt)
        }
        .dsText(.subhead12)
        .foregroundStyle(DS.textSecondary)
        .lineLimit(1)
    }

    /// SOCIAL C: the cast is the picture — every face on two rows at `shelf`
    /// — and the sentence is its caption at `body17`, three lines. The roll is
    /// the ladder's own cast rung, read once in `liveBody`; this face draws
    /// it itself and passes the ladder nothing, so the shelf is never drawn
    /// twice.
    ///
    /// The sentence takes the FIT's rung and lines (prd §905), not a fixed
    /// `body17` × 3: every spelling of this face was identical, so the ladder
    /// had nothing to choose between and a short sentence stood over half a
    /// well of air (user, 2026-09-24).
    @ViewBuilder private func castBlock(_ rungs: [BodyRung], fit: Fit) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            ForEach(Array(rungs.enumerated()), id: \.offset) { _, rung in
                if case .cast(let roll) = rung {
                    DSLeadCast(roll: roll, source: thing.source, rows: 2)
                }
            }
            Text(words)
                .dsText(fit.statementRung)
                .foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(fit.statementLines)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The moment a Life thing is about (prd §908): an event's start rides
    /// `capturedAt` (`ScheduleIngest`'s rule), a reminder's due `dueAt`.
    private var moment: Date? {
        thing.kind == .event ? thing.capturedAt : thing.dueAt
    }

    /// The primitives `WorkStage` reads — `ThingSheetView.workRow`'s own
    /// spelling, so the cover's state word can never differ from the sheet's.
    private var workRow: WorkStage.Row {
        WorkStage.Row(source: thing.source,
                      sourceRef: thing.sourceRef,
                      title: thing.title,
                      tags: thing.tags,
                      mark: thing.mark.rawValue,
                      projectField: thing.authorHandle,
                      hasPrice: thing.priceValue != nil && thing.priceCurrency != nil)
    }

    /// LIFE B: the date tile beside the title — the day at `heading24`, the
    /// month at `label12`, on the faint fill — and the moment's line under
    /// the title: the time (or the day, further out) and how far off it is.
    /// The place and the tags are the ladder's (`facts`, `tags`), so nothing
    /// here says them twice.
    @ViewBuilder private var dateTileBlock: some View {
        if let when = moment {
            HStack(alignment: .center, spacing: DS.Space.s3) {
                VStack(spacing: 2) {
                    Text(verbatim: when.formatted(.dateTime.day()))
                        .dsText(.heading24)
                        .foregroundStyle(DS.textPrimary)
                    Text(verbatim: when.formatted(.dateTime.month(.abbreviated)).uppercased())
                        .dsText(.label12)
                        .foregroundStyle(DS.textSecondary)
                }
                .frame(width: Self.dateTileSide, height: Self.dateTileSide)
                .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.fillFaint))
                VStack(alignment: .leading, spacing: 2) {
                    Text(words)
                        .dsText(.heading24)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: "\(momentClock(when)) · \(FeedLedeFace.dueLine(when))")
                        .dsText(.body17)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    /// The tile is the shelf face's size, so a date and a person stand at
    /// one scale across the faces.
    private static let dateTileSide: CGFloat = DS.Face.shelf

    /// "3:00 PM" today or tomorrow, "Tuesday, Oct 7" further out — the sheet's
    /// own grain (`dueDetail`), for a moment rather than a due.
    private func momentClock(_ when: Date) -> String {
        if Calendar.current.isDateInToday(when) || Calendar.current.isDateInTomorrow(when) {
            return when.formatted(date: .omitted, time: .shortened)
        }
        return when.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    /// WORK B: the state word leads at the ladder's large rung, the title
    /// under it at `heading24`. The parts (`#412 · 2 comments`) are the
    /// ladder's facts, drawn below by `bodyBlock`.
    private func stateWordBlock(_ state: String, fit: Fit) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(verbatim: state)
                .dsText(.heading40)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(words)
                .dsText(.heading24)
                .foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(fit.statementLines)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// NOTES B: the note reads. Its title small (`heading17`), its first
    /// lines as prose at `body17`, as many as the box holds under the eyebrow
    /// and above the foot. The body is `NoteSheetSource.body(for:)` — the
    /// sheet's own words, never a model's (§645) — read once in `liveBody`.
    private func proseBlock(_ prose: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(words)
                .dsText(.heading17)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            Text(verbatim: prose)
                .dsText(.body17)
                .foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(Self.proseLines)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The box is 284 on a phone: the eyebrow and its gap (~46), the title
    /// (24) and its gap (10), the foot (~25) leave ~179, and a `body17` line
    /// is 25 — seven lines, none clipped.
    private static let proseLines = 7

    /// MEDIA A: the art is the well. `LiveStreamHero`'s anatomy — the box at
    /// `leadHeight`, the picture filling it at the widget radius, a scrim
    /// over its foot, the words on the scrim — for a song, a video, a game:
    /// the title, then the artist and the album (or the summary the bridge
    /// landed), then the source and the age.
    private var mediaWell: some View {
        Color.clear
            .frame(height: DSRoomChassis.leadHeight)
            .overlay {
                GeometryReader { geo in
                    if thing.previewImageData != nil {
                        PhotoWell(thing: thing)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    } else if let url = artURL {
                        RemoteArt(urlString: url,
                                  width: geo.size.width, height: geo.size.height,
                                  fallback: thing.source,
                                  cornerRadius: DS.Radius.widget)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.78)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 132)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text(mediaTitle)
                        .dsText(.heading24)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let line = mediaLine {
                        Text(verbatim: line)
                            .dsText(.body17)
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                    HStack(spacing: DS.Space.s1) {
                        Text(thing.source)
                        Text(verbatim: "·")
                        LiveTimeText(date: thing.capturedAt)
                    }
                    .dsText(.subhead12)
                    .foregroundStyle(.white.opacity(0.7))
                }
                .padding(DS.Space.s3)
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous)
                        .fill(DS.tintDim)
                }
            }
    }

    /// A media title is "Nightcall — Kavinsky" (`MusicRow`'s own split); the
    /// scrim shows the name at size and the artist on the line under it,
    /// beside the album the bridge landed as `summary`.
    private var mediaTitle: String {
        let comps = thing.title.components(separatedBy: " — ")
        return comps.count > 1 ? comps.dropLast().joined(separator: " — ") : thing.title
    }

    private var mediaLine: String? {
        let comps = thing.title.components(separatedBy: " — ")
        let artist = comps.count > 1 ? comps.last : nil
        let album = thing.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [artist, album].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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

    // MARK: - The body ladder (prd §772)

    /// One spelling of the cover: a TIER (how large the words and the shelf
    /// draw) and how many lines the statement and the body each get.
    /// `ViewThatFits` walks the ladder richest-first and takes the first that
    /// fits the box.
    ///
    /// **THE TIER (prd §905).** §904 fixed the box in every room, and the two
    /// covers the user then pointed at — an article with a one-line lede, a
    /// notice with a cast — drew every rung they had and still stood over
    /// half a well of air. The ladder only ever stepped DOWN: it started at
    /// `heading24` and took lines away. The tiers are the step up, tried
    /// first and kept only if they fit, so a thing with a lot to say lands on
    /// the same regular spelling it did before, and a thing with little to
    /// say fills the box with what it has.
    ///
    /// **THREE tiers, not two (prd §905a).** §905 shipped with one large tier
    /// that set the words at `heading40` AND the cast on two rows, so a
    /// notice whose sentence could not take 40pt fell all the way to the
    /// regular tier and drew four faces and a "+5" over a half-empty well —
    /// build 664, the user's screenshot. `mid` is the spelling between: the
    /// words at `heading24`, the lede and the shelf grown. What grows is
    /// decided per tier, never as one switch.
    enum Tier: Hashable {
        /// `heading40` words, `body17` lede, two face rows.
        case large
        /// `heading24` words, `body17` lede, two face rows.
        case mid
        /// What §772 drew: `heading24`, `subhead12`, one row.
        case regular
    }

    struct Fit: Hashable {
        let tier: Tier
        let statementLines: Int
        let bodyLines: Int

        /// The words' rung — one of two, never a third (§762's ramp).
        var statementRung: DSTextStyle { tier == .large ? .heading40 : .heading24 }
        /// The lede's rung.
        var ledeRung: DSTextStyle { tier == .regular ? .subhead12 : .body17 }
        /// How many rows of faces the cast shelf may take.
        var castRows: Int { tier == .regular ? 1 : 2 }
    }

    /// Richest first, in three tiers (prd §905, §905a). The LARGE tier goes
    /// first and the MID tier after it, two spellings each: everything the
    /// thing has to say, grown, and one step of give-way — a cover that would
    /// have to cut its content to keep the growth should keep the content
    /// instead, which the regular tier below does. Inside each tier the
    /// statement gives way before the body does — an eight-line sentence
    /// that crowds out the post a notice is about has said less than a
    /// four-line one beside it — and the body gives way last, because the
    /// last two rungs exist precisely to keep the box from being empty.
    ///
    /// TWELVE spellings. Each is measured in turn until one fits, so this
    /// list is the cover's layout cost; a new tier is a reason to measure
    /// `HitchMeter` on the room's open, not a free line here.
    static let fits: [Fit] = [
        Fit(tier: .large,   statementLines: 8, bodyLines: 6),
        Fit(tier: .large,   statementLines: 6, bodyLines: 4),
        Fit(tier: .mid,     statementLines: 8, bodyLines: 6),
        Fit(tier: .mid,     statementLines: 6, bodyLines: 4),
        Fit(tier: .regular, statementLines: 8, bodyLines: 6),
        Fit(tier: .regular, statementLines: 6, bodyLines: 6),
        Fit(tier: .regular, statementLines: 5, bodyLines: 4),
        Fit(tier: .regular, statementLines: 4, bodyLines: 3),
        Fit(tier: .regular, statementLines: 3, bodyLines: 3),
        Fit(tier: .regular, statementLines: 3, bodyLines: 2),
        Fit(tier: .regular, statementLines: 2, bodyLines: 2),
        Fit(tier: .regular, statementLines: 2, bodyLines: 1),
    ]

    /// One thing a lead can put under its statement. See `DSLeadBody` for the
    /// drawings and for why the ladder exists at all.
    enum BodyRung {
        /// The people the thing names, as faces (`ThingCast`).
        case cast(ThingCastRoll)
        /// The post the thing is ABOUT — `Thing.quote`, which the row and the
        /// sheet have drawn for a year and the cover never did.
        case quote(SocialCard)
        /// `summary`, this app's one display-copy field.
        case excerpt(String)
        /// The structured parts a bridge landed (`ThingFact`).
        case facts([ThingFact])
        /// What it is filed under. The quietest rung, and the one nearly every
        /// thing has.
        case tags([String])
    }

    /// What this thing can fill its body with, richest first.
    ///
    /// **Ordered by how much each says about the thing**, which on a notice is
    /// exactly the order the user ruled (2026-09-15, "The cast, then the post"):
    /// who it is about, then what it is about, then what it says about itself.
    ///
    /// Read once per body pass and handed down, never re-derived per fit — the
    /// `ViewThatFits` above builds up to twelve spellings of the cover and every
    /// one of them would otherwise decode `facts` and hit the cast store again
    /// (§626's per-render class, and §628's rule about reads in a body).
    private var bodyRungs: [BodyRung] {
        var out: [BodyRung] = []
        if let roll = ThingCast.shared.cast(for: thing.sourceRef), roll.members.count > 1 {
            out.append(.cast(roll))
        }
        if let quote = thing.quote, DSLeadQuote.draws(quote) {
            out.append(.quote(quote))
        }
        if let excerpt { out.append(.excerpt(excerpt)) }
        let facts = thing.factList
        if !facts.isEmpty { out.append(.facts(facts)) }
        let tags = thing.tags.filter { !$0.isEmpty }
        if !tags.isEmpty { out.append(.tags(tags)) }
        return out
    }

    /// **TWO RUNGS, at most.** The ladder is what the thing COULD say; this is
    /// what the box can hold well. A cast, a post and an excerpt and a parts
    /// list and a tag row stacked in 286pt is a screen inside a screen, and the
    /// fit ladder can only take lines away from the last of them — the fixed-
    /// height rungs above it would clip instead. Two is the user's own ruling
    /// for the notice ("the cast, then the post") generalised: the richest thing
    /// the lead knows, and the next richest.
    private static let rungCap = 2

    /// Named `bodyBlock` rather than `body`: a `View`'s `body` is the protocol's
    /// own requirement, and a second member of that name in the same type is a
    /// diagnostic nobody should have to read.
    @ViewBuilder private func bodyBlock(_ rungs: [BodyRung], fit: Fit) -> some View {
        let drawn = Array(rungs.prefix(Self.rungCap))
        if !drawn.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ForEach(Array(drawn.enumerated()), id: \.offset) { _, rung in
                    rungView(rung, fit: fit)
                }
            }
            .padding(.top, DSLeadBody.gap)
        }
    }

    @ViewBuilder private func rungView(_ rung: BodyRung, fit: Fit) -> some View {
        switch rung {
        case .cast(let roll):
            DSLeadCast(roll: roll, source: thing.source, rows: fit.castRows)
        case .quote(let card):
            DSLeadQuote(card: card, source: thing.source, lines: fit.bodyLines)
        case .excerpt(let text):
            Text(text)
                .dsText(fit.ledeRung)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(fit.bodyLines)
                .fixedSize(horizontal: false, vertical: true)
        case .facts(let facts):
            DSLeadFacts(facts: facts, limit: min(fit.bodyLines, 3))
        case .tags(let tags):
            DSLeadTags(tags: tags)
        }
    }
}
