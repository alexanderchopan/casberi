import Foundation

/// WHAT A TRANSACTION DID, as a mark (2026-08-28, prd §516).
///
/// Every onchain row in this app is `ThingKind.transaction`, and `KindGlyph`
/// draws one symbol per kind — so the wallet's own history screen, whose rows
/// are ALL that kind, rendered as a column of the identical `⇄` glyph twelve
/// deep. The leading slot is the only part of a row you read before the words,
/// and it was saying the one thing every row already agreed on (user,
/// 2026-08-28: "it uses the same icons for each action, but send should be a
/// different arrow than receive. mint should be something and so on").
///
/// This is the exception to `KindGlyph`'s one-symbol-per-kind rule, and it is
/// scoped to the rooms where the kind carries no information: the wallet
/// history screen and an address's own history. Everywhere else a wallet row
/// leads with a BLOCKIE (`BandRow.leader`), so the wall never forms there and
/// nothing changes.
///
/// ## Every answer comes from a STAMPED FIELD or from the REF
///
/// §363's rule, and the reason this takes `direction`/`sourceRef` rather than
/// a title to read: a localized title reorders, and "Sent"/"Minted" are the
/// two words most likely to be translated into a shape this could not match.
/// A glyph derived from prose would be wrong in exactly the languages nobody
/// here reads.
///
/// So there are only two inputs and both are data:
///
/// - `sourceRef` — an APPROVAL announces itself by its namespace
///   (`wallet:approval:` / `wallet:permit2:`, the refs `WalletApprovals`
///   stamps). This is the one that was most wrong before: a grant is not an
///   exchange, and it wore the exchange arrow.
/// - `transferDirection` — `"sent"` / `"received"`, and since this ruling
///   `"minted"` / `"burned"` for the void arm (`WalletVerbs.voidVerb`). That
///   field is a RAW STRING by its own contract, precisely so a value a reader
///   does not know degrades instead of failing; every existing reader gates on
///   the two original values, so the two new ones are invisible to all of them.
///
/// ## What it refuses to answer
///
/// **A swap, a wrap, a stake, a deposit and a self-move all keep `⇄`**, and
/// that is correct rather than a gap: each is genuinely two-legged, which is
/// what that arrow says. They are also not separable from one another by any
/// stamped fact — a swap stores its router in `counterpartyAddress`, a
/// self-move stores one of your own wallets there, and telling those apart
/// needs the watch list, which is not a fact about the row.
///
/// **A mint or a burn landed BEFORE this ruling keeps `⇄` too.** The stamp is
/// written at ingest and healed for any leg still inside the read window
/// (`WalletIngest.healLandedTransfers`); a mint older than that window is
/// never re-read, and there is no field on it that separates a mint from a
/// burn — only the title, which is the one place this may not look. An honest
/// generic mark beats a coin-flip.
///
/// ## COLOUR, by user ruling (2026-08-29) — and this REVERSES §443 here
///
/// The first cut of this varied the SHAPE and kept the kind's hue on every
/// action, on §443's reasoning: green on an inbound transfer congratulates you
/// for being paid back and congratulates you identically for being dusted, and
/// red on an outbound one calls paying rent a loss. That concern was raised
/// and **the user overruled it** ("the colors should be different for a send
/// vs received vs swap … send should be red, received green, swap purple, and
/// we can do mint in the yellow or whatever gold color you are using"). The
/// user rules on design; this is that ruling, recorded rather than argued.
///
/// It is narrower than §443's ban in one way worth keeping: the hue is a
/// property of the ACTION, never of the outcome. Nothing here reads an amount,
/// a sign or a dollar value, so no row is ever coloured for being big, small,
/// a gain or a loss — a 4-cent dusting and a rent payment out wear the same
/// red because they are the same verb. §443's own rule for the ADDRESS card's
/// history rows is untouched and still guarded there.
///
/// The hues are FIXED hexes drawn from `ThingKind.hue`'s own palette rather
/// than from `DS.confirm`/`DS.destructive`, for that palette's stated reason:
/// a mark must not shift per scheme. `KindGlyph` darkens them for light mode
/// exactly as it darkens a kind's own.
///
/// Foundation-only by design, so the harness compiles it WHOLE and unmodified.
enum WalletActionMark {

    /// The two ref namespaces `WalletApprovals` stamps. Spelled once here and
    /// drift-guarded against that file: if the namespace is ever renamed, a
    /// prefix test left behind matches nothing, the room does not break, it
    /// goes QUIET, and every grant silently goes back to wearing the exchange
    /// arrow (§311's failure exactly).
    static let approvalRefPrefixes = ["wallet:approval:", "wallet:permit2:"]

    static func isApprovalRef(_ ref: String?) -> Bool {
        guard let ref else { return false }
        return approvalRefPrefixes.contains { ref.hasPrefix($0) }
    }

    /// The stamped values `transferDirection` may carry. `sent`/`received` are
    /// the field's originals and are read by a dozen call sites; `minted` and
    /// `burned` are this ruling's addition and are read only here.
    static let sent = "sent"
    static let received = "received"
    static let minted = "minted"
    static let burned = "burned"

    /// What a row DID, as a mark: one shape and one hue.
    ///
    /// `exchanged` is the default and covers everything this refuses to guess
    /// at — a swap, a wrap, a stake, a deposit, a self-move, and a mint landed
    /// before the stamp. It keeps the kind's own two-way arrow, which is what
    /// that arrow says.
    enum Action: String, CaseIterable {
        case sent, received, exchanged, minted, burned, granted

        /// The SF Symbol. `exchanged` returns `ThingKind.transaction`'s own,
        /// spelled here rather than left to the caller so this file states the
        /// whole mark and the harness can prove every case distinct.
        var symbol: String {
            switch self {
            case .sent:      return "arrow.up.right"
            case .received:  return "arrow.down.left"
            case .exchanged: return "arrow.left.arrow.right"
            // A mint is the only thing here that makes something exist, and
            // `sparkles` is already this app's word for that (`ThingKind.skill`).
            case .minted:    return "sparkles"
            case .burned:    return "flame"
            case .granted:   return "hand.raised"
            }
        }

        /// The hue, fixed per the user's ruling above. Every value is one the
        /// app's own kind palette already uses, so the column stays in the
        /// family it has always been in rather than introducing a sixth
        /// vocabulary of colour.
        var hex: String {
            switch self {
            // Red and green as named: `ThingKind.event`'s red and
            // `.screenshot`'s green, which are `DS.destructive`'s and
            // `DS.confirm`'s dark values.
            case .sent:      return "#ff453a"
            case .received:  return "#30d158"
            // Purple as named — `ThingKind.chat`'s.
            case .exchanged: return "#bf5af2"
            // "the yellow or whatever gold color you are using" —
            // `ThingKind.note`/`.skill`'s gold.
            case .minted:    return "#ffd60a"
            // NOT named in the ruling, so stated here: orange
            // (`ThingKind.reminder`'s, `DS.attention`'s dark value). A burn is
            // the mint's opposite and wants the warm end, and red is spoken
            // for by a send — two reds at 26pt in one column read as one.
            case .burned:    return "#ff9f0a"
            // Also not named: `ThingKind.approval`'s OWN crimson, which is
            // already this app's word for "needs your call". It sits close to
            // the send's red, which is why the grant is the one mark whose
            // SHAPE carries it — a raised hand is unmistakable at any size.
            case .granted:   return "#ff375f"
            }
        }
    }

    /// What this row did, from stamped facts alone.
    ///
    /// - Parameters:
    ///   - direction: `Thing.transferDirection`, verbatim.
    ///   - sourceRef: `Thing.sourceRef`, verbatim.
    static func action(direction: String?, sourceRef: String?) -> Action {
        // The ref FIRST. An approval carries no direction, so the order only
        // matters against a future row that carries both — and there the
        // namespace is the stronger fact: it says what the row IS, where a
        // direction says which way one leg of it went.
        if isApprovalRef(sourceRef) { return .granted }
        switch direction {
        case sent:     return .sent
        case received: return .received
        case minted:   return .minted
        case burned:   return .burned
        default:       return .exchanged
        }
    }
}
