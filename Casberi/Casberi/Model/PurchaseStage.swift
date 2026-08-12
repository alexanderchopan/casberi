import Foundation

/// The receipt behind a thing you bought, and the card behind a thing you're
/// watching (prd §368, 2026-08-12; user: "less like a database field, more
/// like a receipt… start with shopping").
///
/// **The problem this solves.** Five Shopping seats land eight row shapes and
/// not one had a sheet anatomy of its own — every one fell through to the
/// generic path: a link-preview card and the label/value grid. The inventory
/// found the same disease in three forms, all of them facts the record already
/// held:
///
/// - **Money lived in a sentence.** Privacy and Bitrefill join the amount into
///   `title` at ingest (`"Netflix.com · $12.99"`), where nothing can total it
///   or re-format it. Shopify, Deals and Open Food Facts land a real
///   `priceValue` — and no feed row in this app draws that field, so its only
///   appearance anywhere was one unlabelled line in `ThingContent`'s
///   `.product` branch.
/// - **The seller was stamped and never drawn.** All three product bridges
///   write the store / publisher / brand to `authorHandle`, and
///   `BandRow.project` had no case for any of them, so it rendered in neither
///   the row nor the sheet.
/// - **`From — from a store you follow`** was the spec table's whole
///   contribution, and wrong for two of the three sources that got it: a deal
///   comes from a feed publisher, a barcode scan comes from your own hand.
///
/// **Not `ShopStage`.** A Privacy card purchase is the same archetype as an
/// Apple Wallet, Gnosis Pay or ether.fi spend — which sit in the Wallet band,
/// not Shopping. Scoping this to one catalog band would have given four card
/// seats two different purchase sheets, so the fork is what HAPPENED, never
/// which shelf the seat sits on.
///
/// **THE CENTRAL RULE, inherited unchanged from `WorkStage`: derive from
/// stable signals, never from the title.** Every joined title in this codebase
/// is `String(localized:)`, written in whatever language the device was in when
/// the row landed (prd §340). So the archetype comes from the `sourceRef`
/// prefix — a string this app WROTE, never localized, the same signal
/// `WorkStage.ascOutcome` reads Apple's raw states out of — and every word
/// this type returns is produced here, in the language the sheet is being read
/// in today.
///
/// **A pure "does it carry a price" test was tried first and is wrong.**
/// Measured against the shipped bridges, not assumed: Railgun and Peer both
/// stamp `priceValue` with a TOKEN amount and `priceCurrency` with a token
/// SYMBOL, and Bitcoin stamps a real USD value on an ordinary transfer. All
/// three would have been dressed as card purchases by the obvious test. A
/// transfer is not a purchase, and no stored field distinguishes them — the
/// ref does.
///
/// Foundation-only by design (no SwiftUI, no SwiftData, no `Thing`), so
/// `scripts/purchase-stage-selftest.sh` can compile it WHOLE and unmodified —
/// the `WorkStage`/`SocialSheet`/`ASCShape` precedent. It matters for the usual
/// reason: a mis-derived receipt renders as a perfectly good-looking sheet, so
/// a build, a screen sweep and every probe pass while it quietly states the
/// wrong thing.
enum PurchaseStage {

    // MARK: - Shape

    /// What this sheet is a receipt OF. Three, and the third is not a
    /// decoration: a balance crossing is neither a purchase nor a thing you
    /// are watching — it is the app telling you to act, and giving it the
    /// receipt's anatomy would put a "Paid" verb over an alarm.
    enum Archetype: String {
        /// Money left. The amount is the hero.
        case receipt
        /// Nothing was bought. The thing is the hero.
        case watch
        /// A threshold was crossed. What's left is the hero.
        case alarm
    }

    /// State colour, on §302's own ruling ("a gain wears green"). Three, not
    /// four: a purchase has no verdict to report — you bought a thing — so
    /// `neutral` is the common answer here and a hue is the exception.
    enum Tone: String {
        case neutral
        /// Needs you, or is not final yet. `DS.attention`.
        case attention
        /// Money came back, or the number moved in your favour. `DS.confirm`.
        case good
    }

    /// How the hero rung is set.
    enum Face: String {
        /// A formatted amount at the wallet's own hero rung.
        case money
        /// The product's own picture, with the words beneath it.
        case product
    }

    /// A word the row wears — its own state, never our editorial shape mark
    /// repeated in a quieter font.
    struct Badge: Equatable {
        var word: String
        var tone: Tone
    }

    /// Who is on the other side, and what they are to you. The role word is
    /// the whole reason this is a pair: "Slickdeals" alone reads as a shop,
    /// and it isn't one.
    struct Party: Equatable {
        var name: String
        var role: String
    }

    /// One slab row. Only ever built from a stored fact — a rung that invents
    /// a value renders indistinguishably from a correct one.
    struct Rung: Equatable {
        var key: String
        var value: String
        /// Secondary — a date, a fact that isn't the point of the row.
        var dim: Bool = false
    }

    /// One row's reading. `nil` fields are "we have nothing true to say".
    struct Reading: Equatable {
        var archetype: Archetype
        /// What you DID, in the app's voice: "Paid", "Bought", "Topped up".
        /// Nil on a watch card, where nothing was done.
        var verb: String?
        /// The headline — the merchant, the product, the thing.
        var subject: String
        /// The amount, already formatted in the row's OWN stored currency.
        var amount: String?
        var face: Face
        var state: Badge?
        var seller: Party?
        var rungs: [Rung]
        /// The sentence that replaces `From — from a store you follow`. Always
        /// present when a reading composes at all: it is the one thing the old
        /// row was for, said properly.
        var provenance: String
        /// The word under the dial's first disc — WHERE you land, never "Open"
        /// (§302's Explorer ruling, generalised).
        var destination: String?
        /// The price this row used to carry, when the app recorded the move.
        var history: PriceMove?
        /// The A–E grade Open Food Facts published, when there is one. On the
        /// reading rather than re-derived in the view, so the sheet cannot ask
        /// a different question than the one that composed this card.
        var nutriScore: String?
    }

    /// A recorded price change. Composed and parsed by `PriceHistory` below;
    /// carried here so the view never touches storage.
    struct PriceMove: Equatable {
        var was: Double
        var now: Double
        var currency: String
        var wasUntil: Date
        var fell: Bool { now < was }
        /// The move as a share of the old price, or nil when the old price was
        /// zero — a percentage off nothing is a division, not a fact.
        var fraction: Double? {
            guard was > 0 else { return nil }
            return (now - was) / was
        }
    }

    // MARK: - Entry

    /// Everything a reading is derived from. A plain value rather than a
    /// `Thing`, so the whole type stays Foundation-only.
    struct Row {
        var source: String
        var sourceRef: String?
        /// `ThingKind`'s raw value — a string for the same Foundation-only
        /// reason `WorkStage.Row.mark` is one.
        var kind: String
        var title: String
        var tags: [String]
        var priceValue: Double?
        var priceCurrency: String?
        /// `Thing.authorHandle` — the SELLER on a watch row (Shopify's store,
        /// Deals' publisher, Open Food Facts' brand). All three bridges have
        /// stamped it since they shipped.
        var sellerField: String?
        /// `Thing.transferCounterparty` — WHO the money went to, on a receipt.
        /// Apple Wallet has written the normalized merchant here since §317,
        /// and this pass stamps the same field on Privacy and Bitrefill rather
        /// than inventing a second home for one meaning.
        var merchantField: String?
        var capturedAt: Date
        /// `Thing.enrichedText` — retrieval-only by the 2026-07-15 ruling, and
        /// read here for exactly one thing: the machine line `PriceHistory`
        /// writes. Never rendered from here.
        var enrichedText: String?

        init(source: String, sourceRef: String? = nil, kind: String,
             title: String, tags: [String] = [],
             priceValue: Double? = nil, priceCurrency: String? = nil,
             sellerField: String? = nil, merchantField: String? = nil,
             capturedAt: Date = .distantPast, enrichedText: String? = nil) {
            self.source = source
            self.sourceRef = sourceRef
            self.kind = kind
            self.title = title
            self.tags = tags
            self.priceValue = priceValue
            self.priceCurrency = priceCurrency
            self.sellerField = sellerField
            self.merchantField = merchantField
            self.capturedAt = capturedAt
            self.enrichedText = enrichedText
        }
    }

    /// The reading, or nil when this row is not one we can speak about.
    ///
    /// Nil is a real answer and the common one — the sheet then renders
    /// exactly as it does today, which is what lets this land without a flag
    /// day.
    static func reading(_ row: Row) -> Reading? {
        switch archetype(row) {
        case .receipt: return receipt(row)
        case .watch:   return watch(row)
        case .alarm:   return alarm(row)
        case nil:      return nil
        }
    }

    // MARK: - The fork  (ref prefixes — signals this app wrote)

    /// Refs whose row is money LEAVING for something you bought.
    ///
    /// A list of REF SHAPES, not of source names, and the distinction is the
    /// point: these strings are written by this app in `…Bridge.swift` and
    /// never localized, so they answer "what happened" where a source name
    /// only answers "which seat". A new card seat is one entry.
    static let purchaseRefs = [
        "privacy:txn:", "bitrefill:order:",
        "applewallet:txn:", "gnosispay:spend:", "etherficash:spend:",
    ]

    /// Money moving the other way, onto a balance you spend from later. Its
    /// own entry because its verb and its counterparty both differ: you paid
    /// nobody, and what you paid WITH is the fact worth stating.
    static let refillRefs = ["bitrefill:invoice:"]

    static let alarmRefs = ["bitrefill:balance:low:"]

    static func archetype(_ row: Row) -> Archetype? {
        guard let ref = row.sourceRef else {
            // A product with no ref still reads as a product — the kind alone
            // is enough for the watch half, because `.product` is landed by
            // three bridges and nothing else in the app.
            return row.kind == "product" ? .watch : nil
        }
        if alarmRefs.contains(where: ref.hasPrefix) { return .alarm }
        if purchaseRefs.contains(where: ref.hasPrefix)
            || refillRefs.contains(where: ref.hasPrefix) { return .receipt }
        return row.kind == "product" ? .watch : nil
    }

    static func isRefill(_ row: Row) -> Bool {
        guard let ref = row.sourceRef else { return false }
        return refillRefs.contains(where: ref.hasPrefix)
    }

    // MARK: - Receipt

    private static func receipt(_ row: Row) -> Reading? {
        let refill = isRefill(row)
        let refunded = row.tags.contains("Refund")
        let verb = refill ? word("Topped up")
            : refunded ? word("Refunded") : word("Paid")
        let subject = receiptSubject(row, refill: refill)
        // A receipt with no amount is not a receipt — it is the title again,
        // and the generic sheet already draws that better than a hero with a
        // hole in it. Every purchase ref carries a price by construction, so
        // this is the row that predates its bridge's price fields.
        guard let amount = money(row) else { return nil }

        return Reading(
            archetype: .receipt,
            verb: verb,
            subject: subject,
            amount: amount,
            face: .money,
            state: receiptState(row),
            seller: receiptParty(row, refill: refill),
            rungs: receiptRungs(row),
            provenance: provenance(row),
            destination: destination(row),
            history: nil,
            nutriScore: nil)
    }

    /// The merchant, from a stored FIELD — never sliced out of the title.
    ///
    /// The fallback is the whole title, which is mildly redundant (it repeats
    /// the amount the hero already shows) and never wrong. That is the trade
    /// this file makes everywhere: a row landed before its bridge stamped the
    /// merchant keeps exactly the words it always had.
    static func receiptSubject(_ row: Row, refill: Bool) -> String {
        if refill { return word("Balance refill") }
        let merchant = (row.merchantField ?? "").trimmingCharacters(in: .whitespaces)
        return merchant.isEmpty ? row.title.trimmingCharacters(in: .whitespaces) : merchant
    }

    /// Who the money went to, or — on a refill — what it came from.
    ///
    /// One field, one meaning: `transferCounterparty` is "the other side of
    /// the money" on every seat that writes it, which is why a refill's
    /// payment rail lives there too rather than in a second field. The ROLE
    /// word is what keeps the two readable apart.
    private static func receiptParty(_ row: Row, refill: Bool) -> Party? {
        let name = (row.merchantField ?? "").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        // A purchase's merchant is already the subject, so naming it again
        // here would print it twice. Only a refill's rail earns the row.
        guard refill else { return nil }
        return Party(name: name, role: word("paid with"))
    }

    /// Settled, or not yet.
    ///
    /// **This is the §317 lesson in a second seat.** Apple Wallet's cursor bug
    /// was a pending authorization that could never settle; the same fact was
    /// being read and discarded by Privacy, whose payload distinguishes
    /// `settled_amount` from `amount` and whose bridge collapsed both into one
    /// number. An authorization can still change, and a receipt that doesn't
    /// say so is claiming a final figure it doesn't have.
    ///
    /// Read from English facet tags the bridges stamp (§340's precedent), so
    /// it survives a language change. A row with neither tag says nothing —
    /// never "settled" by default, which would be the fake status this app's
    /// design law bans on the one screen about money.
    static func receiptState(_ row: Row) -> Badge? {
        let tags = Set(row.tags)
        if tags.contains("Refund")   { return Badge(word: word("Refund"), tone: .good) }
        if tags.contains("Pending")  { return Badge(word: word("Not settled yet"), tone: .attention) }
        if tags.contains("Settled")  { return Badge(word: word("Settled"), tone: .neutral) }
        if tags.contains("Delivered"){ return Badge(word: word("Delivered"), tone: .neutral) }
        return nil
    }

    private static func receiptRungs(_ row: Row) -> [Rung] {
        var out: [Rung] = []
        if row.source == "Privacy" {
            out.append(Rung(key: word("Card"), value: word("Your Privacy card")))
        }
        out.append(Rung(key: word("When"), value: stamp(row.capturedAt), dim: true))
        return out
    }

    // MARK: - Watch

    private static func watch(_ row: Row) -> Reading? {
        Reading(
            archetype: .watch,
            verb: nil,
            subject: row.title.trimmingCharacters(in: .whitespaces),
            amount: money(row),
            face: .product,
            state: watchState(row),
            seller: watchParty(row),
            rungs: watchRungs(row),
            provenance: provenance(row),
            destination: destination(row),
            history: PriceHistory.parse(row.enrichedText),
            nutriScore: nutriScore(row))
    }

    /// The row's own state, from its tags. `Price drop` outranks `Sale`: both
    /// can be true at once and only one of them is news.
    static func watchState(_ row: Row) -> Badge? {
        let tags = Set(row.tags)
        if tags.contains("Price drop") { return Badge(word: word("Price drop"), tone: .good) }
        if tags.contains("Sale")       { return Badge(word: word("On sale"), tone: .good) }
        if tags.contains("Deal")       { return Badge(word: word("Deal"), tone: .neutral) }
        if tags.contains("Food")       { return Badge(word: word("Scanned"), tone: .neutral) }
        return nil
    }

    /// The seller, and what they are TO YOU — the role word is why this is a
    /// pair rather than a name. Open Food Facts' handle is a brand nobody
    /// follows; Deals' is a feed, not a shop, and reading it as one is the
    /// false sentence this whole pass started from.
    static func watchParty(_ row: Row) -> Party? {
        let name = (row.sellerField ?? "").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let role = switch row.source {
        case "Shopify":         word("a store you follow")
        case "Deals":           word("a feed you follow")
        case "Open Food Facts": word("brand")
        default:                word("seller")
        }
        return Party(name: name, role: role)
    }

    private static func watchRungs(_ row: Row) -> [Rung] {
        var out: [Rung] = []
        // The barcode, which is the one fact a scan has that nothing else
        // does — and it is sitting in the ref, unread, on every scanned row.
        if let code = barcode(row) {
            out.append(Rung(key: word("Barcode"), value: code, dim: true))
        }
        out.append(Rung(key: row.source == "Open Food Facts" ? word("Scanned") : word("Seen"),
                        value: stamp(row.capturedAt), dim: true))
        // Said out loud, because a missing number and an unread one are
        // different facts and the sheet used to show neither. Deals never
        // parses a price — the claim is in the headline the publisher wrote,
        // and repeating it as OUR number would be asserting something we
        // didn't measure.
        if row.priceValue == nil, row.source == "Deals" {
            out.append(Rung(key: word("Price"), value: word("Not checked"), dim: true))
        }
        return out
    }

    /// Open Food Facts keys every row on the barcode it scanned (`off:<code>`),
    /// so the digits are already stored — spaced in fours the way they are
    /// printed under the bars.
    static func barcode(_ row: Row) -> String? {
        guard row.source == "Open Food Facts",
              let ref = row.sourceRef, ref.hasPrefix("off:") else { return nil }
        let digits = String(ref.dropFirst(4))
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
        return stride(from: 0, to: digits.count, by: 4).map {
            String(digits.dropFirst($0).prefix(4))
        }.joined(separator: " ")
    }

    /// The grade Open Food Facts published, A–E, off the tag the bridge lands.
    ///
    /// **Read, never computed.** Open Food Facts validates the letter before
    /// it stamps it and this app has no nutrition model of its own — a grade
    /// we derived would be a health claim invented by a bookmarking app.
    static func nutriScore(_ row: Row) -> String? {
        guard row.source == "Open Food Facts" else { return nil }
        for tag in row.tags where tag.hasPrefix("Nutri-Score ") {
            let grade = String(tag.dropFirst("Nutri-Score ".count))
                .trimmingCharacters(in: .whitespaces).uppercased()
            if grade.count == 1, "ABCDE".contains(grade) { return grade }
        }
        return nil
    }

    // MARK: - Alarm

    private static func alarm(_ row: Row) -> Reading? {
        Reading(
            archetype: .alarm,
            verb: word("Left on your balance"),
            // The title IS the sentence here and there is no field to build a
            // better one from — the bridge computed the high-water mark and
            // the crossing and stored neither. Stated rather than silently
            // accepted: the honest fix is a field, and until there is one the
            // alarm says what it always said, in the right anatomy.
            subject: row.title.trimmingCharacters(in: .whitespaces),
            amount: money(row),
            face: .money,
            state: Badge(word: word("Running low"), tone: .attention),
            seller: nil,
            rungs: [Rung(key: word("Noticed"), value: stamp(row.capturedAt), dim: true)],
            provenance: word("Casberi noticed this — it isn't a Bitrefill notification. It fires once per crossing and re-arms when you top up."),
            destination: word("Bitrefill"),
            history: nil,
            nutriScore: nil)
    }

    // MARK: - Provenance

    /// The sentence that replaces the spec table's one row.
    ///
    /// Per seat, because the truth is per seat — this is the whole finding
    /// that started the pass: `from a store you follow` was rendered over a
    /// deal (which comes from a feed publisher) and over a barcode scan
    /// (which comes from your own hand).
    static func provenance(_ row: Row) -> String {
        switch row.source {
        case "Privacy":
            return word("Charged to your Privacy card. Privacy publishes no page for a single purchase, so the door below opens your account.")
        case "Bitrefill":
            return isRefill(row)
                ? word("Money you added to your Bitrefill balance.")
                : word("Bought on Bitrefill. The code lives on Bitrefill's own page — Casberi never stores it.")
        case "Shopify":
            return word("Read from the store's own catalogue. Nothing was bought and nothing can be — the door opens their page.")
        case "Deals":
            return word("A feed you follow posted this. Casberi follows the feed, not the shop, and hasn't checked the price or whether it's still live.")
        case "Open Food Facts":
            return word("You scanned this barcode. Nothing was bought and nothing is watched.")
        case "Apple Wallet":
            return word("Read from Apple Wallet on this device. Nothing about it left your phone.")
        case "Gnosis Pay":
            return word("Settled onchain from your Gnosis Pay account. The chain carries the amount and the moment — never the merchant.")
        default:
            return word("A purchase, read from the account you connected.")
        }
    }

    /// The word under the dial's first disc.
    static func destination(_ row: Row) -> String? {
        switch row.source {
        case "Privacy":         return word("Privacy")
        case "Bitrefill":       return word("Bitrefill")
        case "Shopify":         return word("Store")
        case "Deals":           return word("Deal page")
        case "Open Food Facts": return word("Full entry")
        default:                return nil
        }
    }

    // MARK: - Chrome

    /// Tags that name the row's SHAPE rather than the person's own taxonomy —
    /// the strings `watchState`/`receiptState` read above, so a chip strip
    /// showing them would print the badge back at you in a quieter font.
    static let shapeTags: Set<String> = [
        "Sale", "Price drop", "Deal", "Food", "Refund", "Pending", "Settled",
        "Delivered",
    ]

    static func labels(_ row: Row, typeTags: Set<String>) -> [String] {
        row.tags.filter {
            !shapeTags.contains($0) && !typeTags.contains($0)
                && !$0.hasPrefix("Nutri-Score ")
        }
    }

    // MARK: - Formatting

    /// The amount in the row's OWN stored currency — never a guessed symbol,
    /// and nil (so the caller falls back) when either half is missing. The two
    /// fields are written as a pair by every bridge here for exactly this
    /// reason: a value with no currency can't be re-formatted or compared.
    static func money(_ row: Row) -> String? {
        guard let value = row.priceValue,
              let code = row.priceCurrency?.trimmingCharacters(in: .whitespaces),
              !code.isEmpty
        else { return nil }
        return value.formatted(.currency(code: code))
    }

    static func money(_ value: Double, _ code: String) -> String {
        value.formatted(.currency(code: code))
    }

    static func stamp(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    /// Localization seam — see `WorkStage.word`. Every user-facing word this
    /// type returns is produced here, in the language the sheet is being read
    /// in today, rather than read back off a title stamped in the language of
    /// the day the row landed.
    private static func word(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }
}

// MARK: - Price history

/// The price a watched product used to carry, recorded so a drop can say what
/// it dropped FROM (2026-08-12).
///
/// **Why it needs recording at all.** `ShopifyIngest` compares the new price
/// against the old one, rewrites the title to `"Cast iron pan, 26cm (was
/// €90.00)"`, and then overwrites `priceValue`. So the drop — the entire reason
/// the row re-surfaced — survived only as a parenthetical inside an
/// 80-character-clamped string, and reading it back out is exactly the §340 bug
/// this file exists to avoid.
///
/// **Why `enrichedText` and not a new field.** A new `Thing` property is a
/// CloudKit **Production** deploy before it can ship (an undeployed field never
/// mirrors, silently, forever), and `enrichedText` already carries three
/// documented exceptions to the retrieval-only rule. The cost is honest and
/// stated: one machine line joins the retrieval index. The line is short and
/// the human sentence beneath it is genuinely worth indexing — "was €90.00,
/// now €72.00" is a thing somebody would search for.
///
/// **The format is versioned and locale-free, and only the machine line is ever
/// parsed.** Values are plain `Double` descriptions and the date is epoch
/// seconds, so nothing here depends on a decimal separator, a calendar or a
/// language. The sentence below it is prose for the index and for a reader; no
/// code reads it back.
enum PriceHistory {

    static let marker = "pricemove/1|"

    /// `pricemove/1|EUR|90.0|1754265600|72.0` followed by the human sentence.
    ///
    /// The composed sentence is deliberately NOT the source of truth for
    /// anything — if the marker line is missing or malformed, the sheet simply
    /// shows no history, which is what a row landed before this existed does.
    static func compose(was: Double, now: Double, currency: String,
                        wasUntil: Date) -> String {
        let head = "\(marker)\(currency)|\(was)|\(Int(wasUntil.timeIntervalSince1970))|\(now)"
        let sentence = String(
            localized: "Was \(PurchaseStage.money(was, currency)), now \(PurchaseStage.money(now, currency)).")
        return head + "\n" + sentence
    }

    /// The move, or nil. Every failure mode returns nil rather than a partial
    /// reading: a receipt that states half a price change is worse than one
    /// that states none.
    static func parse(_ text: String?) -> PurchaseStage.PriceMove? {
        guard let line = text?.split(separator: "\n", omittingEmptySubsequences: false).first,
              line.hasPrefix(marker) else { return nil }
        let parts = line.dropFirst(marker.count).split(separator: "|",
                                                       omittingEmptySubsequences: false)
        guard parts.count == 4,
              !parts[0].isEmpty,
              let was = Double(parts[1]),
              let seconds = TimeInterval(parts[2]),
              let now = Double(parts[3]),
              was > 0, now > 0
        else { return nil }
        return PurchaseStage.PriceMove(
            was: was, now: now, currency: String(parts[0]),
            wasUntil: Date(timeIntervalSince1970: seconds))
    }

    /// Whatever the row carried BEFORE this line was added, kept whole.
    ///
    /// A vault note, an article's reader text and a Privacy Pools cover all
    /// live on `enrichedText`, and a product could legitimately gain one
    /// tomorrow — so the writer preserves the existing body rather than
    /// assuming the field is ours. Idempotent: re-recording a move replaces
    /// the marker line and never stacks a second one.
    static func rewrite(existing: String?, with head: String) -> String {
        var lines = (existing ?? "").split(separator: "\n",
                                           omittingEmptySubsequences: false)
        // `compose` always writes exactly two lines — the marker and its
        // sentence — so removing our previous record is "drop the marker and
        // the one line under it", by POSITION. Matching the sentence by its
        // own words would be a localized read, and it would leave a stale
        // sentence in the retrieval index the day somebody changes language.
        if let index = lines.firstIndex(where: { $0.hasPrefix(marker) }) {
            let end = lines.index(index, offsetBy: 2, limitedBy: lines.endIndex)
                ?? lines.endIndex
            lines.removeSubrange(index..<end)
        }
        let body = lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? head : head + "\n" + body
    }

    /// Drop the recorded move and keep whatever else the field held — what a
    /// price RECOVERING calls. Nil rather than an empty string so a row that
    /// carried nothing but a move goes back to carrying nothing: an empty
    /// `enrichedText` is a value the retrieval index would still walk.
    static func clear(_ existing: String?) -> String? {
        guard let existing, existing.contains(marker) else { return existing }
        let kept = rewrite(existing: existing, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return kept.isEmpty ? nil : kept
    }
}
