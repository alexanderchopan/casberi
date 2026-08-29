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
/// ## No colour, and that is a ruling not an omission
///
/// The mark keeps the kind's own hue on every action. §443 already settled
/// this for the same rows one screen over: green on an inbound transfer
/// congratulates you for being paid back and congratulates you identically for
/// being dusted, and red on an outbound one calls paying rent a loss. The
/// SHAPE differs; the colour is the kind's. `wallet-action-mark-selftest.sh`
/// fails the build if this file ever names a state colour.
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

    /// The SF Symbol this row's action deserves, or nil to keep the kind's own.
    ///
    /// nil is the honest default and the common one — a swap, a wrap, a stake,
    /// a self-move, a Peer fill, a pool deposit, and every mint that predates
    /// the stamp. The caller draws `ThingKind.transaction`'s `⇄` for all of
    /// them, which is what they wore before this existed.
    ///
    /// - Parameters:
    ///   - direction: `Thing.transferDirection`, verbatim.
    ///   - sourceRef: `Thing.sourceRef`, verbatim.
    static func symbol(direction: String?, sourceRef: String?) -> String? {
        // The ref FIRST. An approval carries no direction, so the order only
        // matters against a future row that carries both — and there the
        // namespace is the stronger fact: it says what the row IS, where a
        // direction says which way one leg of it went.
        if isApprovalRef(sourceRef) { return "hand.raised" }
        switch direction {
        case sent:     return "arrow.up.right"
        case received: return "arrow.down.left"
        // A mint is the only thing here that makes something exist, and
        // `sparkles` is already this app's word for that (`ThingKind.skill`).
        case minted:   return "sparkles"
        case burned:   return "flame"
        default:       return nil
        }
    }
}
