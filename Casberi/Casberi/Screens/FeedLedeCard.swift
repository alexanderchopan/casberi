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
/// of four faces and the three pictureless ones take a solved colour ground.
///
/// **The colour, and why it is allowed here.** `DS.deckFill` is the register
/// the 2026-08-15 colour night kept after rejecting the same colour on ROWS
/// three times in one evening — its own doc reserves it for "one bright object
/// per screen (the wallet hero, the brief's lede card)", and it had no callers
/// until this. One cover per feed is that one object; the user's ruling was
/// "color is fine now that it has a reason and isn't everywhere". The fill and
/// the ink are ONE decision (deckFill's own doc), so a coloured face pins
/// `.dark` on its subtree and every token below re-points itself. A
/// near-neutral brand (X, ChatGPT, 0xBow) returns nil by design and lands on
/// the neutral card — restraint, not failure.
///
/// **Still no invented picture.** A face is never a photograph we did not
/// have; decoration in the picture's slot is a claim that there was something
/// to see (`AssetMark`'s no-invented-hue rule, one medium over).
struct FeedLedeCard: View {
    let thing: Thing
    /// The Mac keyboard walk's selection. Taken as a parameter rather than
    /// drawn behind the row (`selectionWash`) because this card paints its own
    /// opaque surface — a wash underneath it would be invisible. Only ever
    /// true on Mac; `ShellChrome.canWalk` is Mac-only.
    var selected: Bool = false

    @Environment(\.colorScheme) private var colorScheme

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

    @ViewBuilder private var liveBody: some View {
        let receipt = MoneyReceiptSource.receipt(for: thing)
        let face = FeedLedeFace.kind(isMoney: receipt != nil,
                                     hasArt: artURL != nil || thing.previewImageData != nil,
                                     hasClock: thing.dueAt != nil)
        // Nil for a picture face (the picture is the ground) and for a
        // near-neutral brand — both land on the neutral surface below.
        let deck = face == .picture ? nil : deckGround
        VStack(alignment: .leading, spacing: 0) {
            if face == .picture { art }
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                // **THE MARK LEADS AS A DISC (prd §567).** It was 14pt inline
                // ahead of the source's own name, in the same row as the time
                // — the §553 grammar has it at 36 and top-left, where it heads
                // the card instead of labelling it.
                BridgeIcon(name: thing.source, size: DS.Face.list, circular: true)
                    .padding(.bottom, DS.Space.s1)
                switch face {
                case .picture, .words: titleBlock
                case .money:           moneyBlock(receipt)
                case .clock:           clockBlock
                }
                eyebrow(onDeck: deck != nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.s4)
        }
        .background(background(deck))
        // The card's TOP (prd §542). With no deck the fill is ink on the ink
        // page, so the pour is the only thing separating this card from the
        // feed behind it; over a deck it is §524's rule applied evenly, the
        // same top every other card in the app now wears.
        .background(alignment: .top) {
            LinearGradient(colors: [DS.pourInk, DS.pourInk.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 150)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .shadow(color: DS.raisedShadow, radius: 10, x: 0, y: 2)
        // The fill and the ink are ONE decision (`DS.deckFill`'s doc): the
        // solver always returns the DARK register, so the whole subtree reads
        // its tokens against `.dark` and every rung of the ramp — primary,
        // secondary, tertiary, glyphs — re-points in one line. Exactly the
        // mechanic `shapedListRow` uses for a skinned row.
        .environment(\.colorScheme, deck != nil ? .dark : colorScheme)
    }

    @ViewBuilder private func background(_ deck: Color?) -> some View {
        // `DS.surfaceSheet`, not the gray (prd §542): this is a feed card
        // and every other card in the feed is that token, so the no-deck
        // fallback was the one row in the run wearing a different surface.
        if selected { DS.tintDim } else if let deck { deck } else { DS.surfaceSheet }
    }

    /// The source's own hue, solved to the register. Nil when the brand is
    /// near-neutral — `deckFill`'s documented "no honest colour, no card".
    private var deckGround: Color? {
        DS.brandHue(for: thing.source).flatMap { DS.deckFill(for: $0) }
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
    private static let statementLimit = 56

    private var titleBlock: some View {
        let short = thing.title.count <= Self.statementLimit
        return VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(thing.title)
                .dsText(short ? .heading34 : .heading22)
                .foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(short ? 4 : 3)
                .minimumScaleFactor(short ? 0.8 : 1)
                .fixedSize(horizontal: false, vertical: true)
            if let note = excerpt {
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
                // The tone COLOUR is deliberately dropped here. The receipt
                // card greens an arrival against the page's own ink ramp; this
                // card's ground is an arbitrary brand hue solved for WHITE ink
                // (`DS.deckFill`), so nothing guarantees `confirm` clears
                // contrast on it. Direction is not lost — the sign is a glyph
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

    // MARK: - Shared pieces

    /// Who and when — the two facts the enlarged title drops by not being a
    /// band. On a deck the source name takes the primary ramp: `legibleInk`'s
    /// brand tint is solved against the PAGE, and this ground is the brand's
    /// own hue, so a tinted name on it is the one place that tint cannot be
    /// read.
    /// Where it came from and when, under the thing itself (prd §567).
    ///
    /// **The icon is gone from this row and the NAME is not.** §565's rule is
    /// that a mark restating its own caption is not a mark — true where the
    /// two sit adjacent in one small cell, and the disc above is separated
    /// from this line by the title, so it heads the card rather than badging
    /// this row. The name stays because dropping it would lose the source on
    /// the feed's cover for every seat whose `BridgeIcon` has no bundled art,
    /// which is a real regression to buy a tidier line.
    private func eyebrow(onDeck: Bool) -> some View {
        HStack(spacing: DS.Space.s2) {
            Text(thing.source)
                .dsText(.label12)
                .foregroundStyle(onDeck ? DS.textPrimary : DS.textSecondary)
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
