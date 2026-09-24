import Foundation

/// Which face the All feed's cover wears (prd §389 amendment, 2026-08-16).
///
/// §389 shipped the cover with two faces — a picture, or the words — and the
/// words face is thin for exactly the things least likely to have a picture: a
/// reminder, a calendar event, a wallet transfer, a work item. The user's
/// ruling on seeing it: *"we should still show it but in a nice card somehow"*,
/// then, on the colour: *"color is fine now that it has a reason and isn't
/// everywhere."*
///
/// So the cover never declines for want of a picture. It picks a face, and the
/// pictureless faces take a solved colour ground (`DS.deckFill`) — the register
/// the 2026-08-15 colour night reserved for "one bright object per screen"
/// after rejecting the same colour on ROWS three times. One cover per feed is
/// that one object, which is the whole of the user's "isn't everywhere".
///
/// **PURE, and separated from the gathering so it can be tested** —
/// the widget's old day-lead ladder's shape exactly (deleted in §877), and for the same reason: the ladder is
/// the part that goes silently wrong (a money arrival drawn as the words face
/// renders perfectly and says far less than it could), while the gathering
/// needs `@MainActor` and a `Thing`.
enum FeedLedeFace {

    enum Kind: String, Equatable {
        /// The thing's own picture — stored pixels or remote art — as a band
        /// over the words: every category's picture face until its own batch
        /// of the face pass (prd §907) rules on it.
        case picture
        /// READING A (prd §907): the page's picture tall, the title under it,
        /// the source line under that.
        case pictureAspect
        /// MEDIA A (prd §907): the art IS the well, the words on a scrim.
        case mediaArt
        /// SOCIAL C (prd §907): the cast is the picture, the sentence its
        /// caption.
        case cast
        /// A money receipt (`MoneyReceiptSource.receipt`), which nine sources
        /// compose. Beats `picture` deliberately: an NFT purchase can carry
        /// both, and what the figure says is what the row is FOR.
        case money
        /// The thing carries a deadline, so the countdown leads and the title
        /// sits under it — §35's rule that a perishable shows its countdown
        /// everywhere, applied to the one surface big enough to lead with it.
        case clock
        /// Title and excerpt on the source's ground. The floor of the ladder,
        /// and deliberately not a decline: a note IS its words, so words at
        /// heading weight on a coloured field is the honest cover for it, not
        /// a consolation prize.
        case words

        /// Whether the body ladder (§772) draws under this face's statement.
        /// A face that is a picture, or that draws its one rung itself,
        /// passes none — §734's reason: the picture is the object, and a
        /// shelf under it would clip.
        var takesLadder: Bool {
            switch self {
            case .picture, .pictureAspect, .mediaArt, .cast: return false
            case .money, .clock, .words: return true
            }
        }
    }

    /// The ladder. Ordered most-specific first, and every rung is a fact about
    /// the thing rather than a judgement about it — the same discipline that
    /// keeps the cover's PICK positional (§389).
    ///
    /// There is no `none`: the decision to have a cover at all belongs to
    /// `FeedScreen.ledeThingID`, which declines three ways before this is ever
    /// asked.
    /// Once a cover is drawing, it draws something.
    ///
    /// **THE FACE PASS (prd §907): one box, a designed face per category.** The
    /// category is the dock's (`BridgeCatalog.category(forSource:)`), read
    /// once at the mount and handed in, so this stays a pure decision. The
    /// order is the order the user ruled the faces: money is a receipt
    /// wherever it lands; Media's art is the well; a cast leads wherever a
    /// thing carries one (an X notice, a GitHub roster, a group chat);
    /// Reading's picture stands tall; every other picture keeps the band
    /// until its batch; a clock, then words.
    static func kind(isMoney: Bool, hasArt: Bool, hasClock: Bool,
                     category: String? = nil, hasCast: Bool = false) -> Kind {
        if isMoney { return .money }
        if hasArt, category == "Media" { return .mediaArt }
        if hasCast { return .cast }
        if hasArt, category == "Reading" { return .pictureAspect }
        if hasArt { return .picture }
        if hasClock { return .clock }
        return .words
    }

    /// "In 4 hours" / "3 days ago" / "next Tuesday" — the deadline in the grain
    /// that is useful at that distance.
    ///
    /// ONE definition, shared with `FeedScreen.dueLine`, which forwards here.
    /// The two were the same single line of formatting and a second copy is
    /// exactly where a countdown quietly starts disagreeing with itself
    /// depending on which surface you read it on.
    ///
    /// Deliberately UNWINDOWED: a due date is the most useful fact about a
    /// thing that has one at every distance, and `.named` already degrades
    /// gracefully from minutes to months. A window would be a judgement about
    /// when a deadline stops mattering, which is not ours to make.
    static func dueLine(_ due: Date) -> String {
        due.formatted(.relative(presentation: .named))
    }

    /// Whether a deadline has already passed, so the card can say so in words
    /// rather than leaving `.named`'s "3 days ago" to carry it alone. A
    /// countdown that has run out is a different state, not a smaller number.
    static func isOverdue(_ due: Date, now: Date = .now) -> Bool { due < now }
}
