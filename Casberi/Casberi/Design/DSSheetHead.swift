import SwiftUI

/// THE SHEET HEAD — one anatomy for what a thing sheet opens with (prd §495,
/// user: *"the sheet for activity should look in some way like the design we
/// have for wallet activity"*, then *"so should account sheets, and
/// permissions sheets"*).
///
/// **Lifted from `MoneyReceiptCard`, which is where this shape was settled**
/// (§363): a subject disc and a stamp on one row, then the lead, the subject's
/// own words, one supporting line, and one sentence saying what it means now.
/// That anatomy was written for money and is not about money — every part of
/// it answers a question any event has (who, what state, when, what happened,
/// what it means), which is why three vibenet sheets were each inventing a
/// worse version of it.
///
/// **It takes plain values, not a `MoneyReceipt`.** The receipt type carries
/// amounts, currencies and a finality that only a transaction has; coupling
/// the shape to it is what kept the shape in one room. What is shared here is
/// the ARRANGEMENT, and each caller decides what fills it.
///
/// The money receipt keeps its own card — it has a torn edge that carries
/// state (§363: torn means final, flat means the paper is still in the
/// machine) and an amount block with a signed figure, neither of which
/// generalises. This is its head, made available to sheets that have no
/// amount to draw.
struct DSSheetHead<Disc: View>: View {
    /// The subject, drawn as this sheet's own mark — a face, an identicon, a
    /// tinted glyph. Handed in rather than derived, so a room that already
    /// knows how to draw its subject keeps drawing it that way.
    @ViewBuilder let disc: () -> Disc
    /// The state word, top-right — "Authorized", "Revoked", "Locked". nil
    /// where the thing has no state worth stamping.
    var stamp: String?
    /// What the stamp MEANS — a closed weight, never a colour (2026-08-28).
    ///
    /// This was `stampInk: Color`, which is how one component ends up with
    /// several reds: an open colour asks each caller to pick a shade for a
    /// state, and `DSStamp`'s own doc has the rest of the reasoning. Quiet by
    /// default, so a caller that has not thought about it cannot raise an
    /// alarm by omission.
    var stampWeight: DSStamp.Weight = .quiet
    /// When it happened, above the title — the receipt's own `lead`.
    var lead: String?
    /// The thing's own words, at `heading34` — the HEAD rung (prd §532).
    ///
    /// **This doc said `heading22`, "the receipt's `party` tier", and had said
    /// it since §532 raised the code without it (prd §560, 2026-09-01).** A
    /// stale doc on a shared component is worse than none: it points at the
    /// loser of a settled question, so the next reader either "fixes" the code
    /// down to it or copies the wrong number into a fourth sheet.
    ///
    /// **And the receipt's `party` really is `heading22`, correctly** — which
    /// is what made the contradiction look like drift rather than staleness.
    /// `MoneyReceiptCard` has `amountBlock` at `price40` directly beneath, so
    /// the head rung there belongs to the FIGURE and the party is the line
    /// under it. A `DSSheetHead` has no amount, so its title is the largest
    /// thing on the paper and takes the rung the figure would have. One rule —
    /// the head rung goes to whatever the sheet is actually about — reading
    /// out as two numbers because the two sheets are about different things.
    ///
    /// **INSIDE A `DSTray` IT IS `heading22`, and that is the same rule rather
    /// than an exception to it** (2026-09-02). "Its title is the largest thing
    /// on the paper" is the premise the whole paragraph above rests on, and in
    /// a tray it is false: `DSTray` draws its own title at `heading34` four
    /// points higher (§532 — a tray is a place). §560 raised this line without
    /// noticing, so **five of the six heads in the app began drawing a second
    /// head under the first** — 120pt of headline before the first fact, which
    /// on `VibenetCreateSheet` pushed the new account's address under the
    /// pinned action and sliced it through the middle. Both rulings are intact:
    /// the tray title says WHERE YOU ARE, this says WHAT IT IS, and one surface
    /// spends the head rung once (`heading34`'s own doc, and §506's rule for
    /// the crown one rung up).
    ///
    /// It reads that from the environment rather than a parameter, so no caller
    /// can get it wrong — `EnvironmentValues.dsSurfaceHasHead`.
    let title: String
    /// One supporting line under the title — an id, a curve, a handle.
    var secondary: String?
    /// What it means NOW, in a sentence. The receipt's own closing line, and
    /// the part that makes a head an answer rather than a label.
    var sentence: String?
    /// Whether the paper is TORN along its bottom edge.
    ///
    /// On a money receipt this carries state (§363: torn means final, flat
    /// means the paper is still in the machine). A sheet with no such
    /// distinction passes true and simply gets the receipt's silhouette,
    /// which is the part that makes it read as an object rather than as text
    /// on a page — the difference the user named: *"right now it just looks
    /// like a jumble of text"*.
    var torn: Bool = true
    // `inkCard` was HERE and is deleted (prd §542, 2026-08-31, user: "we have
    // this gray colored card — i want that gone from everywhere in the app.
    // should be the dark ink one"). The 2026-08-29 ruling that scoped ink to
    // the three short trays — on the reasoning that a full-page surface has
    // margin enough for a `DS.surfaceRaised` card to read as a paper resting
    // on ink — is overturned: every paper is ink now, so there is no fork
    // left for a caller to choose.

    @Environment(\.colorScheme) private var scheme
    /// Set by `DSTray` — see `title` and `EnvironmentValues.dsSurfaceHasHead`.
    @Environment(\.dsSurfaceHasHead) private var surfaceHasHead

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                disc()
                    // THE SUBJECT ARRIVES (prd §501). The sheet's stage
                    // settles in rather than being already there, so opening a
                    // row reads as that row becoming this page.
                    //
                    // **This is the arrival, not the FLIGHT the spec drew, and
                    // the difference is a platform fact rather than a
                    // compromise chosen for effort.** A flight needs one
                    // overlay drawing over both endpoints, and a `.sheet` is a
                    // separate presentation — an `overlayPreferenceValue` in
                    // the room cannot paint over it, which is why
                    // `AddressFlight` works at all: both of ITS endpoints are
                    // on one screen. The system zoom would cross that boundary
                    // and is banned here (§232, a deterministic device-
                    // specific crash the simulator never reproduced). So what
                    // ships is the visible half, on one recipe both rooms
                    // read, and the flight proper stays unbuilt with its
                    // reason written down.
                    .settleIn()
                Spacer(minLength: DS.Space.s3)
                if let stamp {
                    // Hidden from VoiceOver HERE rather than in `DSStamp`,
                    // because it is this head that restates the state in its
                    // own sentence below — the money receipt does not, and
                    // keeps its pill audible.
                    DSStamp(word: stamp, weight: stampWeight)
                        .accessibilityHidden(true)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                if let lead {
                    Text(lead)
                        // Whose sheet this is — a caption, not a sentence.
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                }
                Text(title)
                    // The head rung (prd §532) — this line IS the subject of
                    // the sheet, so it takes the largest words in the app…
                    // **unless the surface already spent that rung** (see
                    // `title`), in which case it takes the next one down.
                    .dsText(surfaceHasHead ? .heading22 : .heading34)
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(.top, DS.Space.s3)
            if let secondary {
                Text(secondary)
                    .dsText(.callout15)
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            if let sentence {
                Text(sentence)
                    .dsText(.callout15)
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s4)
            }
        }
        // **IT IS A PIECE OF PAPER, NOT A BLOCK OF TEXT** (prd §495).
        //
        // The head was drawn bare on the page and read as "a jumble of text"
        // beside Wallet's, whose whole legibility comes from being an OBJECT:
        // a raised surface, a pour at the top (ink since 2026-08-29), and the
        // scalloped bottom edge that makes it a receipt rather than a card.
        // `ReceiptPaper` is that silhouette and is reused rather than
        // re-drawn, so the two rooms cannot drift into two papers.
        //
        // This is a deliberate exception to "headers no cards": that ruling
        // is about a LIST's rows and a room's readings, and this is a single
        // object standing for a single moment — which is exactly what §363
        // argued when it gave the receipt its paper in the first place.
        .dsReceiptPaper(torn: torn)
    }
}

/// THE PAPER ITSELF, without the arrangement on it (prd §498).
///
/// `DSSheetHead` above is one anatomy AND one silhouette, which is right for
/// every sheet whose head is a run of static facts. The address card is the
/// one head that is partly a CONTROL — §444 moved renaming in place, because
/// naming is the act that card exists for and an alert covered the cascade it
/// triggers — so it cannot hand its title over as a `String`.
///
/// The answer is not a second paper. Extracting the treatment means the two
/// heads share the silhouette, the pour, the raised ground and the shadow, and
/// can only ever differ in what stands on them — the failure mode a sibling
/// session named the same day: *"shared COMPONENTS are not a shared
/// TEMPLATE"*, five compositions of the same parts drifting apart with every
/// check still green. `DSSheetHead` is itself the first caller, so the shared
/// path is the one every existing sheet already runs.
struct DSReceiptPaper: ViewModifier {
    /// HOW FAR THE TEETH HAVE CUT: 0 flat, 1 fully torn — a fraction, not a
    /// flag (2026-08-28).
    ///
    /// It was a `Bool`, and that is the one reason `MoneyReceiptCard` — the
    /// card this modifier was lifted OUT of, so that "the two rooms cannot
    /// drift into two papers" — never adopted it and went on spelling the
    /// whole padding/pour/surface/clip/shadow stack inline. On a receipt the
    /// tear is a TRANSITION (§363: a pending authorization settling is the
    /// paper finishing its cut), and a Bool cannot be interpolated, so the
    /// shared path could not carry the one caller it was extracted from.
    ///
    /// The bottom padding interpolates WITH the cut on purpose: at a fixed
    /// padding the card jumps a tooth's worth of height the instant the
    /// animation starts.
    ///
    /// Every other caller passes 0 or 1 through the `torn:` convenience
    /// below, where the silhouette is decoration rather than state — see
    /// `dsReceiptPaper(torn:)`.
    var tear: CGFloat = 1

    /// The paper's own fill, under the ink pour: `DS.inkGround`, always
    /// (prd §542, 2026-08-31 — "i want that gone from everywhere in the app.
    /// should be the dark ink one"). This was a `base: Color` parameter
    /// defaulting to `DS.surfaceRaised`, with `DS.inkGround` scoped to the
    /// three short trays via `DSSheetHead.inkCard`; the user ruled the gray
    /// paper dead on sight of Hegotá's UTXO/frame/account/activity sheets,
    /// so the parameter is REMOVED rather than re-defaulted — the pour's own
    /// `Color?` precedent: an option nobody may take is a fork waiting to
    /// drift back. On ink the paper's edge is carried by the pour, the torn
    /// silhouette and (in light) `raisedShadow`, not by a tonal step.
    private var base: Color { DS.inkGround }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s6)
            .padding(.bottom, DS.Space.s6 + (ReceiptPaper.tooth + 2) * tear)
            .frame(maxWidth: .infinity, alignment: .leading)
            // THE POUR IS INK, AND EVERY PAPER GETS ONE (2026-08-29, user
            // ruling — `DS.pourInk`'s own doc carries the reasoning and the
            // words it was ruled in).
            //
            // It took a `Color?` and the nil meant "no pour at all", which
            // was the honest answer while the colour was a claim: a room with
            // no brand hue had nothing true to pour. A neutral makes no
            // claim, so there is nothing left for a caller to opt out of —
            // and the option is REMOVED rather than defaulted, because a
            // paper without a top is the "jumble of text" §495 exists to fix
            // and no sheet should be able to choose it by omission.
            .background(alignment: .top) {
                LinearGradient(colors: [DS.pourInk, DS.pourInk.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(base)
            .clipShape(ReceiptPaper(tear: tear))
            .shadow(color: DS.raisedShadow, radius: 10, y: 2)
    }
}

extension View {
    /// The paper, torn or flat. **The tear is DECORATION on this door** — it
    /// is the silhouette that makes a head read as an object rather than as
    /// text on a page (§495), and every caller here passes `true`.
    ///
    /// On a money receipt it is STATE (§363: torn means final, flat means the
    /// paper is still in the machine), and that caller reaches for the
    /// fraction below instead. The two doors are separate so the distinction
    /// stays legible: nothing about a vibenet key sheet's edge is claiming to
    /// mean anything, and nothing should read it as though it does.
    func dsReceiptPaper(torn: Bool = true) -> some View {
        modifier(DSReceiptPaper(tear: torn ? 1 : 0))
    }

    /// The paper mid-cut — for the one caller whose edge carries state and
    /// animates between the two.
    func dsReceiptPaper(tear: CGFloat) -> some View {
        modifier(DSReceiptPaper(tear: tear))
    }
}
