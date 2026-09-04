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
/// The money receipt keeps its own view — it has an amount block with a
/// signed figure, which does not generalise. This is its head, made available
/// to sheets that have no amount to draw.
///
/// **THERE IS NO PAPER UNDER IT ANY MORE** (prd §583, 2026-09-03, user: *"i
/// think it looks WAY better without the card"*). §495's raised ground, ink
/// pour and torn edge are deleted; the anatomy above is what fixed "a jumble
/// of text", and the object around it was drawing a second boundary for a
/// block that already had one. `DSSheetHeadBlock` at the bottom of this file
/// carries the spacing that is left, and its doc has the reasoning.
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
    // `torn` was HERE and is deleted (prd §583, 2026-09-03, user: "i think it
    // looks WAY better without the card"). It chose whether the paper's bottom
    // edge was scalloped, and there is no paper left for an edge to belong to.
    //
    // On this head the tear was always DECORATION — §498's own door says so
    // ("every caller here passes `true`") — so nothing it carried is lost.
    // The money receipt's tear was STATE, and that is answered separately in
    // `MoneyReceiptCard`: every `.open` receipt already carries a non-quiet
    // stamp, so the word was saying it too.

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
        // **IT IS THE ARRANGEMENT, NOT AN OBJECT** (prd §583, 2026-09-03).
        //
        // §495 read the head's illegibility ("a jumble of text") as a missing
        // OBJECT and gave it a raised surface, an ink pour and a scalloped
        // bottom edge. It also gave it the anatomy above — disc and stamp on a
        // row, lead, title at the head rung, one supporting line, one sentence
        // — and that is the half that did the work. With a real ramp running
        // 12 → 40 down the block, the paper was a second boundary around
        // something that already had one, and it read as packaging.
        //
        // So §495's "deliberate exception to headers-no-cards" is withdrawn
        // and the general rule applies here after all.
        .dsSheetHeadBlock()
    }
}

/// THE HEAD'S OWN METRICS, with no object under them (prd §583, 2026-09-03,
/// user: *"i think it looks WAY better without the card"*).
///
/// **This replaces `DSReceiptPaper`, and the deletion is the ruling.** §495
/// gave every sheet head a receipt paper — a raised ground, an ink pour and a
/// scalloped bottom edge — on the reasoning that a head drawn bare read as
/// "a jumble of text". That reasoning was about ARRANGEMENT, and the
/// arrangement is what fixed it: a subject disc and a stamp on one row, then
/// the lead, then the title at the head rung, then one supporting line and one
/// sentence. With the ramp doing that work the paper was drawing a second
/// boundary around a block that already had one, and the object read as
/// packaging.
///
/// **What the paper actually contributed, and why a modifier survives it.**
/// Strip the ground, the pour, the clip and the shadow and what is left is
/// spacing — a horizontal inset and top/bottom room. That still wants to live
/// in one place for §498's original reason: five heads composing their own
/// insets is how they drift apart with every check still green. So the
/// modifier stays and only its body changes.
///
/// **The inset is `s4` and it is load-bearing.** The paper ran full-bleed with
/// its content inset `s4`, so removing it without this would put a 40pt title
/// against the screen edge. On the money receipt the paper was ALSO inset `s4`
/// by its call site, which double-indented that head one step deeper than the
/// eyebrow above it and the rows below it — visible in the §583 mockup and
/// noticed there before this shipped. One inset now, so every line on a sheet
/// shares a left edge.
///
/// The top is `s4` rather than the paper's `s6`: `s6` was the object's own
/// internal padding, and bare on the ground it reads as a gap where a heading
/// should be. The bottom keeps `s6`, which is separation between the head and
/// what follows rather than padding inside anything.
struct DSSheetHeadBlock: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s4)
            .padding(.bottom, DS.Space.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// The head's spacing, with nothing drawn under it.
    ///
    /// `dsReceiptPaper(torn:)` and `dsReceiptPaper(tear:)` were HERE and are
    /// deleted (prd §583). The `Color?` pour and the `inkCard` fork both set
    /// the precedent this follows: an option nobody may take is a fork waiting
    /// to drift back, so the paper is removed rather than defaulted off.
    func dsSheetHeadBlock() -> some View {
        modifier(DSSheetHeadBlock())
    }
}
