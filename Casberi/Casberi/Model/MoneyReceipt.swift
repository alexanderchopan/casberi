import Foundation

/// The receipt — one anatomy for every money thing in the corpus (prd §369,
/// 2026-08-12).
///
/// **Why this exists.** Until now exactly three things got a hero on the thing
/// sheet, and the gate was a source-name string: `kind == .transaction &&
/// source == "Wallet"` (`ThingStage`'s three parsers). Everything else — an
/// Apple Wallet charge, an ether.fi Cash spend, a Peer fill, a Privacy Pools
/// deposit, a Railgun unshield, a Safe transaction waiting on your signature, a
/// Morpho risk crossing — fell through `ThingContent`'s `default:` branch, which
/// renders `content` as a paragraph of body copy. For ten families `content` is
/// a block-explorer URL, so the sheet's body WAS
/// `https://basescan.org/tx/0x2c8b…`; for Apple Wallet and Safe `content` is
/// empty, so the body was nothing at all.
///
/// **Why a sentence and not a spec table.** The first cut of this pass drew the
/// facts as a labelled slab — an 84pt grey key column reading Into / Network /
/// Landed / Receipt. That is a database row with rounded corners (user, 2026-08-12:
/// "I want these to feel like they're in an app not like they're in a
/// database"). A wallet name, a chain and a time were never three facts; they
/// are one clause. So this type resolves to `sentence`, and the spec slab is
/// gone.
///
/// **The cost of that, stated.** Prose is fluent, and a fluent wrong statement
/// is much harder to notice than a wrong number in a labelled row — a label at
/// least tells you what was claimed. So every sentence here is assembled from
/// facts that were stamped at ingest, never parsed back out of a title, and
/// every clause has a shorter form for when the fact behind it is missing. The
/// harness (`scripts/money-receipt-selftest.sh`) exists for exactly this:
/// nothing else in the tree can tell a true sentence from a fluent one.
///
/// **Foundation-only by design**, the `CardSpendRoom` split: everything that can
/// be wrong in a way that still renders perfectly lives here, where the harness
/// compiles it whole and unmodified. `MoneyReceiptSource` holds the half that
/// touches `Thing`.
struct MoneyReceipt: Equatable {

    // MARK: - The pieces

    /// Why a subject is missing. NOT the same as "we don't know" — these are
    /// absences the protocol creates on purpose, and the view draws them as a
    /// recessed void rather than a monogram, so a designed absence can never be
    /// misread as a face that failed to load.
    enum Absence: Equatable {
        /// Railgun hides the sender (prd §268). The defining feature, not a gap.
        case senderPrivate
        /// A card that settles onchain carries no merchant name (prd §222).
        case merchantOffchain
    }

    /// Slot 0 — the one disc that opens every receipt, in the strongest form we
    /// can honestly draw. The four cases are four grades of knowing, and the
    /// ordering of that knowledge is the whole point: an identicon is derived
    /// from a real address, a bundled mark is real artwork, a monogram admits we
    /// have neither, and a void says the absence is deliberate.
    enum Subject: Equatable {
        /// An address — `WalletFace`'s identicon, deterministic from the hex.
        case address(String)
        /// A token symbol — `AssetMark`, which falls back to a neutral monogram
        /// on its own when no artwork is bundled.
        case asset(String)
        /// A merchant, rail, venue or protocol by name — same `AssetMark` rule.
        case named(String)
        case absent(Absence)
    }

    enum Tone: Equatable { case gain, plain, warn }

    /// Whether the record is finished. Drawn as the stub's bottom edge: torn
    /// means final, flat means the paper is still in the machine. It is a claim
    /// of finality and is only made once, which is why every "still happening"
    /// state below resolves to `.open` — a pending authorization whose amount
    /// can still change, an unsigned Safe transaction, a deposit in screening,
    /// an open position at risk.
    enum Finality: Equatable { case torn, open }

    /// Source identity as colour — the `crownPour` idiom scoped to a card. It
    /// encodes identity and NOTHING else: never gain, loss, size or urgency,
    /// which stay on the amount's tone and the stamp. `neutral` is not a
    /// fallback for laziness — Apple Card has no brand colour to borrow, and
    /// inventing one is the same lie `AssetMark` refuses one level up.
    enum Hue: Equatable {
        case wallet, bitcoin, shield, safe, peer, railgun, card, risk, neutral
    }

    /// The pill on the paper. State in form as well as words, so what needs
    /// attention reads before the sentence does.
    enum Stamp: Equatable {
        case settled, pending, settling, filled, yourTurn, shielded, screening
        case needsProof, refund, openPosition, cleared
        /// A Safe proposal not yet executed (prd §83: never "Settled").
        case waiting
        /// Railgun money leaving the pool: the opposite of shielded.
        case unshielded
        /// A Safe proposal a rival transaction took the nonce from.
        case replaced

        var word: String {
            switch self {
            case .settled:      return String(localized: "Settled")
            case .pending:      return String(localized: "Pending")
            case .settling:     return String(localized: "Settling")
            case .filled:       return String(localized: "Filled")
            // "Needs you", the app's one word for what waits on you (prd
            // §1333, user: "'your turn' is lame"); the Safe's tag stays data.
            case .yourTurn:     return String(localized: "Needs you")
            case .shielded:     return String(localized: "Shielded")
            case .screening:    return String(localized: "Screening")
            case .needsProof:   return String(localized: "Needs proof")
            case .refund:       return String(localized: "Refund")
            case .openPosition: return String(localized: "Open position")
            case .cleared:      return String(localized: "Clear to withdraw")
            case .waiting:      return String(localized: "Waiting")
            case .unshielded:   return String(localized: "Unshielded")
            case .replaced:     return String(localized: "Replaced")
            }
        }

        /// Which of the app's three semantic colours the pill wears. `quiet` is
        /// a real answer, not an absence — a settled refund is information, not
        /// an alarm.
        enum Weight: Equatable { case good, waiting, urgent, quiet, private_ }
        var weight: Weight {
            switch self {
            case .settled, .filled, .cleared:            return .good
            case .pending, .settling, .screening:        return .waiting
            case .yourTurn, .needsProof, .openPosition:  return .urgent
            case .refund:                                return .quiet
            case .replaced:                              return .quiet
            case .waiting:                               return .waiting
            case .shielded, .unshielded:                 return .private_
            }
        }
    }

    /// The money, split so the number can carry the display ramp's monospaced
    /// digits while its unit sits a rung down. `number` already carries its own
    /// sign — a receipt states direction in the figure, not in a badge beside it.
    struct Amount: Equatable {
        var number: String
        var unit: String?
        var tone: Tone
        /// The figure as a NUMBER, where one was actually stamped — what
        /// `contentTransition(.numericText(value:))` counts between when a
        /// pending authorization settles at a different amount (prd §369
        /// amendment).
        ///
        /// Optional and usually nil, deliberately. `number` is the display
        /// string and stays authoritative: for a card spend it came from
        /// `.formatted(.currency(code:))` and is already locale-correct, and
        /// for a chain transfer it is the bridge's own stamped string, which
        /// this file may not re-parse (see the type's doc). So this is filled
        /// only from a Double the bridge really stamped — never by reading
        /// `number` back — and a nil simply means the figure cross-fades the
        /// way it always did.
        var numeric: Double?

        init(number: String, unit: String? = nil, tone: Tone,
             numeric: Double? = nil) {
            self.number = number
            self.unit = unit
            self.tone = tone
            self.numeric = numeric
        }

        /// The figure said out loud. The sign is a GLYPH in `number` (U+2212
        /// MINUS SIGN, and a bare "+"), which is exactly the kind of character
        /// a screen reader is free to skip — so direction, the one thing on a
        /// receipt that must never be lost, is spelled.
        var spoken: String {
            var said = number
            if said.hasPrefix("−") {
                said = String(localized: "minus ") + said.dropFirst()
            } else if said.hasPrefix("+") {
                said = String(localized: "plus ") + said.dropFirst()
            }
            guard let unit, !unit.isEmpty else { return said }
            return "\(said) \(unit)"
        }
    }

    // MARK: - The receipt

    /// Slot 0.
    var subject: Subject
    /// The watched wallet this touched, as an address — drawn as a small face
    /// tucked into the subject's corner, so "from her, into Main" is one object.
    /// nil when the receipt has no second party to show (a card spend).
    var mine: String?
    /// The lead line above the name: "Received from", "Spent at", "Put into".
    var lead: String
    /// The name the lead points at. nil leaves the lead standing alone, which
    /// is correct for a transfer whose counterparty was never captured.
    var party: String?
    /// The headline figure. nil is a legitimate, common answer: several bridges
    /// stamp no machine-readable amount, and this type will not parse one back
    /// out of a localized title (see the type's own doc). Those receipts lead
    /// with `title` instead and are still complete.
    var titleFallback: String?
    var amount: Amount?
    /// The line under the figure — what it was worth when it landed, which card
    /// it hit, or plainly that we have no fiat figure to give.
    var secondary: String?
    /// The clause that replaced the spec table.
    var sentence: String
    var stamp: Stamp?
    var finality: Finality
    var hue: Hue
    /// A record of something that happened, or a READING of where things
    /// stand (prd §1341): an Acorns account's balance or a Splits account (a
    /// Rocket Money plan is a bill, a record, since §1341's amendment). A reading draws the box and nothing after it:
    /// no tiles, no history, no lock screen. Last, so every record arm keeps
    /// its call as it was.
    var form: Form = .record

    enum Form: Equatable { case record, reading }

    // MARK: - Said out loud

    /// The whole receipt as ONE spoken sentence (prd §369 amendment).
    ///
    /// **Why this is here and not in the view.** The card reads out as eight
    /// separate stops otherwise — "image", "Sent to", "maria.eth", "minus 0
    /// point 5 0", "E T H", "Settled", the sentence, "image" — which is the
    /// same eight facts in the order they happen to be laid out, with the
    /// relationships between them thrown away. Worse, `finality` is drawn as
    /// the SHAPE OF THE PAPER and nothing else, so the sharpest thing this
    /// card says is the one thing a screen reader could never reach.
    ///
    /// It lives beside `compose` because it can be wrong in exactly the way
    /// everything else in this file can be wrong — fluently, while the screen
    /// still looks perfect — and here the harness compiles it.
    var spokenLabel: String {
        var said: [String] = []
        if let party, !party.isEmpty {
            said.append("\(lead) \(party)")
        } else {
            said.append(lead)
        }
        if let amount {
            said.append(amount.spoken)
        } else if let titleFallback, !titleFallback.isEmpty {
            said.append(titleFallback)
        }
        if let secondary, !secondary.isEmpty { said.append(secondary) }
        said.append(sentence)
        return said.joined(separator: ". ")
    }

    /// The state, as the accessibility VALUE rather than part of the label —
    /// so a rotor pass hears what changed without re-reading the whole card,
    /// and so the tear survives being spoken.
    ///
    /// Finality is stated in words that do not lean on the metaphor: "final"
    /// and "not final yet", never "torn" or "flat", which describe a picture
    /// somebody listening has never seen.
    var spokenValue: String {
        let state = finality == .torn
            ? String(localized: "Final")
            : String(localized: "Not final yet")
        guard let stamp else { return state }
        return "\(stamp.word). \(state)"
    }

    // MARK: - Input

    /// One money thing, reduced to what the receipt reads. Every field here is
    /// stamped by a bridge at ingest; none is scraped from prose.
    ///
    /// The three resolved fields (`myLabel`, `partyLabel`, `network`) are filled
    /// by `MoneyReceiptSource`, which can reach `WalletStore` and
    /// `WalletIngest`. They arrive resolved so this file stays Foundation-only
    /// and the harness can compile it.
    struct Facts: Equatable {
        var source: String
        var title: String
        var content: String = ""
        var sourceRef: String?
        var capturedAt: Date = .now
        var direction: String?
        var amount: String?
        var counterparty: String?
        var venue: String?
        var usd: Double?
        var counterpartyAddress: String?
        var walletAddress: String?
        var priceValue: Double?
        var priceCurrency: String?
        var tags: [String] = []
        var authorHandle: String?
        /// Resolved by the source half.
        var myLabel: String?
        var partyLabel: String?
        /// The other end is one of the wallets you watch (prd §1349).
        var partyWatched = false
        var network: String?
        /// Bitcoin only — is this transfer still short of
        /// `BitcoinBridge.settledConfirmations`?
        ///
        /// A BOOL and not a count, deliberately. The bridge keeps its pending
        /// set as a list of txids in UserDefaults and stores no per-transfer
        /// confirmation number, so "3 of 6" is a fact this app does not have.
        /// Passing 0 for an unknown count would print "0 confirmations" over a
        /// transfer that may well have five, which is the fluent-wrong-answer
        /// this whole file is built to avoid.
        var settling: Bool?
        /// Safe only — read off `SafeBridge.Check`, which the sheet already
        /// fetches once per open, so these ARE real counts.
        var signaturesHave: Int?
        var signaturesNeed: Int?
        /// The day a deadline or a bill falls due, when the bridge stamped one.
        var dueAt: Date?
    }

    /// Which sources get a receipt. Declared once, and deliberately a SET of
    /// names rather than a `kind` test: `.transaction` also covers rows that are
    /// really notices ("this address hasn't moved since March"), and a source
    /// missing from here keeps exactly the sheet it has today rather than
    /// getting a half-composed hero.
    static let sources: Set<String> = [
        "Wallet", "Apple Wallet", "ether.fi", "Privacy.com",
        "Peer", "Privacy Pools", "Railgun", "Safe", "Wise",
        // EVERY MONEY ROW IN THE WALLET OPENS THE RECEIPT (prd §1341, user,
        // of a Lightning payment and an Acorns account in Home's
        // Transactions: "this is terrible", "they all look like that").
        "Lightning", "Privy", "Splits", "MetaMask Card", "Plasma One",
        "Acorns", "Rocket Money",
    ]

    /// The Wallet's apps whose rows are NOT money moves, each with where its
    /// rows open instead (prd §1341). `money-receipt-selftest.sh` reads every
    /// Wallet seat out of `RoomAccounts` and fails one in neither this nor
    /// `sources`, so a new money app cannot ship onto the generic sheet.
    static let elsewhere: [String: String] = [
        "Bitrefill": "orders and refills open the purchase receipt (PurchaseStage, prd §364)",
        "CardPointers": "card offers, reminders with an end date, never money moved",
        "ENS": "name expiries, never money moved",
    ]

    /// The rows a money app lands as a STATE — what it says you have or pay
    /// right now, updated in place — rather than as something that happened
    /// (prd §1341): an Acorns account and its balance, a Splits account. They open the receipt's calm form (`reading`).
    static func isReading(source: String, ref: String?) -> Bool {
        source == "Acorns"
            || (source == "Splits" && ref?.hasPrefix("splits:account:") == true)
    }

    /// A Rocket Money plan is a BILL, not a balance (prd §1341 amended): what
    /// it charges and the day it was charged or falls due, with Track beside
    /// it. It lands as a note, so the source half lets it through by name.
    static func isBill(source: String) -> Bool { source == "Rocket Money" }

    /// Rows that say what WILL happen — a staked-HYPE unlock, a name's expiry,
    /// a vote closing (prd §83: a deadline is never "Settled"). They are
    /// moments, not receipts, and fall to the moment head.
    static let ahead = ["hyperliquid:unlock:", "wallet:ensexpiry:", "aerodrome:vote:"]
    static func isAhead(ref: String?) -> Bool {
        guard let ref else { return false }
        // A demo row carries its bridge's ref after "demo:".
        let bare = ref.hasPrefix("demo:") ? String(ref.dropFirst("demo:".count)) : ref
        return ahead.contains { bare.hasPrefix($0) }
    }

    /// A state is never a transaction (prd §1341): an account (Acorns', a
    /// Splits team's), or an app that made you a wallet (`privy:app:`,
    /// Holdings' Apps since §1124). Home's Transactions and the history
    /// behind it leave these out, and Holdings lists them.
    ///
    /// A Rocket Money plan is a reading too and is NOT here: one dated ahead
    /// is Subscriptions' already (`SubscriptionsSource.isBill`), and one with
    /// no date ahead has no other place yet, so it stays listed rather than
    /// vanish.
    static func isState(source: String, ref: String?) -> Bool {
        source == "Acorns"
            || (source == "Splits" && ref?.hasPrefix("splits:account:") == true)
            || ref?.hasPrefix("privy:app:") == true
    }

    // MARK: - Composition

    /// The receipt, or nil when this thing isn't one we draw.
    static func compose(_ f: Facts) -> MoneyReceipt? {
        guard sources.contains(f.source), !isAhead(ref: f.sourceRef) else { return nil }
        if isReading(source: f.source, ref: f.sourceRef) { return reading(f) }
        if isBill(source: f.source) { return bill(f) }
        switch f.source {
        case "Apple Wallet" where f.tags.contains("Price rise"): return priceRise(f)
        case "Apple Wallet":                 return card(f, hue: .neutral)
        case "ether.fi", "Privacy.com", "MetaMask Card", "Plasma One":
            return card(f, hue: .card)
        case "Peer":                         return peer(f)
        case "Privacy Pools":                return pools(f)
        case "Railgun":                      return railgun(f)
        case "Safe":                         return safe(f)
        case "Wise":                         return wise(f)
        case "Lightning":                    return lightning(f)
        case "Privy":                        return privy(f)
        case "Splits":                       return splits(f)
        default:                             return wallet(f)
        }
    }

    // MARK: Wallet (transfers, self-moves, swaps, Bitcoin, everything riding it)

    private static func wallet(_ f: Facts) -> MoneyReceipt? {
        // Bitcoin announces itself by the unit on its own stamped amount, never
        // by the title — `BitcoinBridge` is the only writer that puts " BTC"
        // there. Checked before the generic transfer arm because its sentence
        // and its stamp are different (a block, and confirmations).
        let unit = split(f.amount).unit
        if unit == "BTC" { return bitcoin(f) }

        // **A SWAP SAYS WHAT IT TRADED (prd §1351, user: "ok").** "Swapped ETH
        // for USDC" over the legs the title's own " → " separates (the
        // `SwapStage` parse), settled; the header draws the two tokens.
        if f.title.hasPrefix("Swapped "), let arrow = f.title.range(of: " → ") {
            let out = split(String(f.title.dropFirst("Swapped ".count)[..<arrow.lowerBound]
                .replacingOccurrences(of: "Swapped ", with: "")))
            // The venue's " on Uniswap" is no leg (prd §1373): it read as the
            // token, titling a trade "Swapped USDC for Uniswap".
            var inLeg = String(f.title[arrow.upperBound...])
            if let on = inLeg.range(of: " on ") { inLeg = String(inLeg[..<on.lowerBound]) }
            let into = split(inLeg)
            if let a = out.unit, let b = into.unit {
                return MoneyReceipt(
                    subject: .asset(b), mine: f.walletAddress,
                    lead: String(localized: "Swapped"),
                    party: String(localized: "Swapped \(a) for \(b)"),
                    titleFallback: nil,
                    amount: Amount(number: into.number, unit: b, tone: .plain),
                    secondary: worthLine(f.usd),
                    sentence: placeSentence(String(localized: "Swapped"), f),
                    stamp: .settled, finality: .torn, hue: .wallet)
            }
        }
        guard let direction = f.direction, let raw = f.amount, !raw.isEmpty,
              direction == "sent" || direction == "received" else {
            // No stamped direction/amount. A self-move, a swap, a Hyperliquid
            // close, a Morpho supply, an Aerodrome vote deadline — all real
            // rows, none of which stamp a single signed figure, and none of
            // which will have one invented here. They get the whole receipt
            // except the headline number.
            return generic(f, hue: .wallet)
        }
        let received = direction == "received"
        let parts = split(raw)
        // **BETWEEN YOUR OWN WALLETS IT SAYS WHERE IT WENT (prd §1349, user:
        // "yes do all").** "Everyday to Savings", never one wallet's name as
        // if it were a person.
        let between: String? = f.partyWatched
            ? (received ? "\(f.partyLabel ?? f.counterparty ?? "") to \(f.myLabel ?? "")"
                        : "\(f.myLabel ?? "") to \(f.partyLabel ?? f.counterparty ?? "")")
            : nil
        let party = between ?? f.partyLabel ?? f.counterparty
        return MoneyReceipt(
            subject: subject(address: f.counterpartyAddress, name: party,
                             fallbackAsset: parts.unit),
            mine: f.walletAddress,
            lead: between != nil ? String(localized: "Moved")
                : received ? String(localized: "Received from") : String(localized: "Sent to"),
            party: party,
            titleFallback: nil,
            amount: Amount(number: (received ? "+" : "−") + parts.number,
                           unit: parts.unit,
                           tone: received ? .gain : .plain),
            secondary: worthLine(f.usd),
            sentence: transferSentence(f, received: received),
            // A direction and a figure read off the chain: it moved.
            stamp: .settled,
            finality: .torn,
            hue: .wallet)
    }

    private static func bitcoin(_ f: Facts) -> MoneyReceipt {
        let parts = split(f.amount)
        let received = f.direction != "sent"
        let settling = f.settling == true
        return MoneyReceipt(
            subject: .asset("BTC"),
            mine: f.walletAddress,
            lead: received ? String(localized: "Received into")
                           : String(localized: "Sent from"),
            // The row's own sentence ("Received 0.0250 BTC"), never the
            // wallet's name as the title (prd §1357.1).
            party: actionTitle(f.title),
            titleFallback: nil,
            amount: parts.number.isEmpty ? nil
                : Amount(number: (received ? "+" : "−") + parts.number,
                         unit: parts.unit, tone: received ? .gain : .plain),
            secondary: nil,
            sentence: bitcoinSentence(f),
            stamp: settling ? .settling : .settled,
            finality: settling ? .open : .torn,
            hue: .bitcoin)
    }

    // MARK: Card spends

    /// Apple Wallet, ether.fi Cash, Privacy.com, MetaMask Card and Plasma
    /// One (prd §1341; a Plasma One row is a day's settled spending). One arm,
    /// because a card spend is a card spend; the differences that matter are
    /// which subject can be drawn (a merchant name, or a void where the chain
    /// carries none) and whether the amount can still change.
    private static func card(_ f: Facts, hue: Hue) -> MoneyReceipt {
        let refund = f.tags.contains("Refund")
        let pending = f.tags.contains("Pending")
        let merchant = f.counterparty
        // Kept apart so `numeric` is filled ONLY when the figure on screen
        // really is this Double formatted — a fallback string parsed out of
        // `amount` has no number behind it, and pairing the two would let the
        // figure count toward a value it isn't showing.
        let priced = currency(f.priceValue, code: f.priceCurrency)
        // A token spend with no currency (MetaMask Card's WETH) keeps its
        // unit beside the figure, never a bare number.
        let fallback = split(f.amount)
        let money = priced ?? fallback.number
        // The three onchain cards: the chain carries no shop (prd §222).
        let onchain = ["ether.fi", "MetaMask Card", "Plasma One"].contains(f.source)
        return MoneyReceipt(
            subject: merchant.map { Subject.named($0) }
                ?? (onchain ? .absent(.merchantOffchain) : .named(f.source)),
            // No second face: a card spend has one party and it is the shop.
            mine: nil,
            // An onchain card names no shop (the chain carries none), so the
            // lead completes itself with the card rather than dangling as
            // "Spent at" over nothing (prd §1074).
            lead: merchant == nil && onchain
                ? (refund ? String(localized: "Refunded to \(f.source)")
                          : String(localized: "Spent with \(f.source)"))
                : (refund ? String(localized: "Refunded by") : String(localized: "Spent at")),
            party: merchant ?? (onchain ? nil : f.source),
            titleFallback: money.isEmpty ? f.title : nil,
            amount: money.isEmpty ? nil
                : Amount(number: (refund ? "+" : "−") + money,
                         unit: priced == nil ? fallback.unit : nil,
                         tone: refund ? .gain : .plain,
                         numeric: priced == nil ? nil : f.priceValue.map(abs)),
            secondary: cardLine(f),
            sentence: cardSentence(f, pending: pending, refund: refund),
            stamp: refund ? .refund : (pending ? .pending : .settled),
            finality: pending ? .open : .torn,
            hue: hue)
    }

    /// "on Apple Card, ending 4821" — built from the account label the bridge
    /// stamped, never from the title. nil when there's no account to name.
    private static func cardLine(_ f: Facts) -> String? {
        guard let account = f.authorHandle, !account.isEmpty else { return nil }
        return String(localized: "on \(account)")
    }

    // MARK: Peer

    private static func peer(_ f: Facts) -> MoneyReceipt {
        let rail = f.authorHandle
        let sell = f.sourceRef?.hasPrefix("peer:sell:") == true
        // The stamped amount, else the title's own ("Bought 250 USDC with …").
        let parts = f.amount?.isEmpty == false ? split(f.amount) : peerAmount(f.title)
        return MoneyReceipt(
            // The rail is the subject: it is the thing you'd recognize, and
            // it's a known app so `AssetMark` may have real artwork for it.
            subject: rail.map { Subject.named($0) } ?? .named("Peer"),
            mine: f.walletAddress,
            lead: sell ? String(localized: "Sold through")
                       : String(localized: "Bought with"),
            // **TITLED BY WHAT YOU TRADED (prd §1356)**, "Bought 250 USDC",
            // never the rail's name alone.
            party: parts.number.isEmpty ? rail
                : (sell ? String(localized: "Sold \(parts.number) \(parts.unit ?? "")")
                        : String(localized: "Bought \(parts.number) \(parts.unit ?? "")")),
            titleFallback: parts.number.isEmpty ? f.title : nil,
            amount: parts.number.isEmpty ? nil
                : Amount(number: (sell ? "−" : "+") + parts.number,
                         unit: parts.unit, tone: sell ? .plain : .gain),
            secondary: worthLine(f.usd),
            sentence: placeSentence(String(localized: "Filled"), f),
            stamp: .filled,
            finality: .torn,
            hue: .peer)
    }

    /// A row's own title as the sheet's (prd §1357): the sentence the bridge
    /// wrote, a parenthetical restatement dropped ("Received $12,000 (12,000
    /// USDC) from Acme Labs" → "Received $12,000 from Acme Labs").
    static func actionTitle(_ title: String) -> String {
        title.replacingOccurrences(of: #" \([^)]*\)"#, with: "", options: .regularExpression)
    }

    /// "Uniswap can spend your USDC" → "USDC" (prd §1360).
    static func approvalToken(_ title: String) -> String? {
        guard let r = title.range(of: " can spend your ") else { return nil }
        let token = String(title[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        return token.isEmpty ? nil : token
    }

    /// "Bought 250 USDC with Venmo on Peer" → ("250", "USDC").
    static func peerAmount(_ title: String) -> (number: String, unit: String?) {
        let words = title.split(separator: " ").map(String.init)
        guard words.count >= 3, words[0] == "Bought" || words[0] == "Sold" else { return ("", nil) }
        return (words[1], words[2])
    }

    /// **A PRICE RISE IS A RECEIPT (prd §1357).** It opened the bare sheet —
    /// an empty card, Reminders and Copy. Now: the plan and how much it went
    /// up as the title (the row's own words), what it costs now, what it was.
    private static func priceRise(_ f: Facts) -> MoneyReceipt {
        let now = currency(f.priceValue, code: f.priceCurrency)
        // What it cost before, off the REF the bridge keyed it by
        // (`AppleWalletRoom.creepRef`: "…:<was>:<now>:<day>", both in minor
        // units), never parsed back out of the localized title.
        let was = creepWas(ref: f.sourceRef).flatMap { currency($0, code: f.priceCurrency) }
        // The row's own words without the restated prices after the seam:
        // "Notion went up 20%" (prd §1357.4); the box carries the figures.
        let words = TitleSeam.split(f.title).name
        return MoneyReceipt(
            subject: f.counterparty.map { Subject.named($0) } ?? .named(f.source),
            mine: nil,
            lead: String(localized: "Price rise"),
            party: words,
            titleFallback: nil,
            amount: now.map { Amount(number: $0, unit: nil, tone: .warn) },
            secondary: was.map { String(localized: "was \($0)") },
            sentence: placeSentence(String(localized: "Went up"), f),
            stamp: nil,
            finality: .torn,
            hue: .neutral)
    }

    /// "applewallet:creep:notion:1000:1200:20367" → 10.0.
    static func creepWas(ref: String?) -> Double? {
        guard let ref, ref.contains("applewallet:creep:") else { return nil }
        let parts = ref.split(separator: ":")
        guard parts.count >= 3, let cents = Int(parts[parts.count - 3]) else { return nil }
        return Double(cents) / 100
    }

    // MARK: Wise

    /// **A WISE TRANSFER IS A RECEIPT (prd §1332, user, going through the
    /// Wallet's screens: "lets start with this from wise").** It drew the
    /// bare card, a face over nothing, under its raw title ("Needs attention
    /// · £200 → €235 · Deposit"). Now it names the transfer by the reference
    /// you wrote, says first what it is waiting on, and draws what left and
    /// what arrives. Read off the row `WiseShape` landed: the tags carry the
    /// state (`stuckTag`, "Pending", "Returned"), the price the money that
    /// left, and the title's second part the pair, never a figure computed here.
    private static func wise(_ f: Facts) -> MoneyReceipt {
        // "<state> · <amounts>[ · <reference>]" — `WiseShape.rowTitle`.
        let parts = f.title.components(separatedBy: " · ")
        let reference = parts.count > 2 ? parts[2...].joined(separator: " · ") : nil
        let arrives = parts.count > 1 ? parts[1].components(separatedBy: " → ").dropFirst().first : nil
        let stuck = f.tags.contains(String(localized: "Needs attention"))
        let returned = f.tags.contains(String(localized: "Returned"))
        let pending = !returned && f.tags.contains(String(localized: "Pending"))
        let priced = currency(f.priceValue, code: f.priceCurrency)
        let started = dayPhrase(f.capturedAt)
        // With no reference of yours, the title is what happened to the money
        // (prd §1357.1), never the state word alone ("Came back").
        let money = priced ?? (parts.count > 1 ? parts[1] : nil)
        let said: String? = money.map { m in
            stuck ? String(localized: "\(m) waits on you")
                : pending ? String(localized: "Sending \(m)")
                : returned ? String(localized: "\(m) came back")
                : String(localized: "Sent \(m)")
        }
        return MoneyReceipt(
            subject: .named("Wise"),
            mine: nil,
            lead: stuck ? String(localized: "Waiting on you")
                : pending ? String(localized: "Sending")
                : returned ? String(localized: "Came back")
                : String(localized: "Sent"),
            party: reference ?? said,
            titleFallback: priced == nil ? f.title : nil,
            amount: priced.map {
                Amount(number: (returned ? "+" : "−") + $0, unit: nil,
                       tone: returned ? .gain : .plain, numeric: f.priceValue.map(abs))
            },
            secondary: arrives.map { String(localized: "\($0) arrives") },
            sentence: stuck ? String(localized: "Wise won't send it until you act in Wise. Started \(started).")
                : pending ? String(localized: "On its way since \(started).")
                : returned ? String(localized: "The money came back. Started \(started).")
                : String(localized: "Sent \(started)."),
            stamp: stuck ? .yourTurn : pending ? .pending : returned ? .refund : .settled,
            finality: stuck || pending ? .open : .torn,
            hue: .neutral)
    }

    // MARK: Lightning (prd §1341)

    /// A settled Lightning payment, as `LightningIngest` lands it: the memo
    /// as the title (or the direction's own words when there is none), the
    /// sats stamped on `transferAmount`, and the dollars the bridge priced it
    /// at when it landed. Only settled payments land, so it is always final.
    private static func lightning(_ f: Facts) -> MoneyReceipt {
        let received = f.direction == "received"
        let lead = received ? String(localized: "Received over Lightning")
                            : String(localized: "Paid over Lightning")
        let parts = split(f.amount)
        // With no memo the bridge titles the row with these same words, so
        // the memo is the party only when it is a memo.
        let memo = f.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return MoneyReceipt(
            subject: .named("Lightning"),
            mine: nil,
            lead: lead,
            party: memo.isEmpty || memo == lead ? nil : memo,
            titleFallback: parts.number.isEmpty ? f.title : nil,
            amount: parts.number.isEmpty ? nil
                : Amount(number: (received ? "+" : "−") + parts.number,
                         unit: parts.unit, tone: received ? .gain : .plain),
            secondary: worthLine(f.priceCurrency == "USD" ? f.priceValue : nil),
            sentence: String(localized: "Settled \(dayPhrase(f.capturedAt))."),
            stamp: .settled,
            finality: .torn,
            hue: .bitcoin)
    }

    // MARK: Privy (prd §1341)

    /// What moved in a wallet an app made for you (`PrivyHomeLive`): the
    /// app's name rides `authorHandle`, the other side `counterpartyAddress`,
    /// and the dollars Zerion priced it at `transferUSD`. That wallet is not
    /// one you watch, so no tucked face.
    private static func privy(_ f: Facts) -> MoneyReceipt {
        let received = f.direction == "received"
        let parts = split(f.amount)
        return MoneyReceipt(
            // The app's own mark (prd §1341 amended): money in an app's wallet
            // wears the app, never a stranger's face or a person badge.
            subject: .named(f.source),
            mine: nil,
            lead: received ? String(localized: "Received into") : String(localized: "Sent from"),
            party: actionTitle(f.title),
            titleFallback: parts.number.isEmpty ? f.title : nil,
            amount: parts.number.isEmpty ? nil
                : Amount(number: (received ? "+" : "−") + parts.number,
                         unit: parts.unit, tone: received ? .gain : .plain),
            secondary: worthLine(f.usd),
            sentence: placeSentence(received ? String(localized: "Landed")
                                             : String(localized: "Left"), f),
            stamp: .settled,
            finality: .torn,
            hue: .wallet)
    }

    // MARK: Splits (prd §1341)

    /// A Splits team's transaction (`SplitsBridge`): the account it moved
    /// in on `authorHandle`, the direction, the dollars Splits displayed, and
    /// Splits' own title ("Received $12,000 (12,000 USDC) from Acme Labs"),
    /// which names the token and the other side and is drawn as written,
    /// never read back. A proposal still waiting on signatures is open.
    private static func splits(_ f: Facts) -> MoneyReceipt {
        let waiting = f.tags.contains("Waiting")
        let failed = f.tags.contains(String(localized: "Not executed"))
        let received = f.direction == "received"
        // Splits' own words, without the stage this app put in front of them
        // (`SplitsShape.rowTitle`: "<stage> · <Splits' title>").
        var words = f.title
        if waiting || failed, let seam = words.range(of: " · ") {
            words = String(words[seam.upperBound...])
        }
        // A figure needs a direction to wear a sign: Splits names none for
        // a shape it has not shown us (`SplitsShape.direction`), and then the
        // row leads with Splits' own words.
        let directed = f.direction == "received" || f.direction == "sent"
        let figure = directed ? f.usd.flatMap { $0 > 0 ? $0 : nil } : nil
        return MoneyReceipt(
            subject: .named("Splits"),
            mine: nil,
            lead: failed ? String(localized: "Not executed")
                : waiting ? String(localized: "Waiting to send from")
                : !directed ? String(localized: "In")
                : received ? String(localized: "Received into") : String(localized: "Sent from"),
            // Splits writes "<state> · <sentence>"; the state is the stamp.
            party: figure == nil || failed ? f.authorHandle.flatMap { $0.isEmpty ? nil : $0 }
                : actionTitle(f.title.components(separatedBy: " · ").last ?? f.title),
            titleFallback: figure == nil || failed ? words : nil,
            amount: failed ? nil : figure.map {
                Amount(number: (received ? "+" : "−") + fiat($0), unit: nil,
                       tone: received ? .gain : .plain, numeric: $0)
            },
            secondary: figure == nil || failed ? nil : words,
            sentence: waiting
                ? String(localized: "Proposed \(dayPhrase(f.capturedAt)). Nothing has moved yet.")
                : placeSentence(failed ? String(localized: "Proposed")
                                : received ? String(localized: "Landed") : String(localized: "Left"), f),
            stamp: failed ? nil : waiting ? .pending : .settled,
            finality: waiting ? .open : .torn,
            hue: .wallet)
    }

    // MARK: Readings (prd §1341)

    /// WHERE THINGS STAND, NOT WHAT HAPPENED: an account's balance (Acorns),
    /// an account (Splits). The receipt's calm
    /// form: the account's name, the figure the app read, and when. No sign,
    /// no stamp, no sentence about a move that never happened.
    ///
    /// Acorns titles a row "<name> — <money>" itself (`AcornsIngest`), so
    /// the name is the part before
    /// the seam; the figure is the stamped price when there is one, else the
    /// bridge's own money words after the seam, never a number parsed back.
    private static func reading(_ f: Facts) -> MoneyReceipt {
        var name = f.title
        var words: String?
        if let seam = f.title.range(of: " — ", options: .backwards) {
            name = String(f.title[..<seam.lowerBound])
            words = String(f.title[seam.upperBound...])
        }
        // To the cent, whatever the size: a balance is read, not rounded.
        let priced: String? = {
            guard let value = f.priceValue, let code = f.priceCurrency, !code.isEmpty else { return nil }
            return abs(value).formatted(.currency(code: code))
        }()
        // A balance below zero keeps its sign.
        let figure = priced.map { (f.priceValue ?? 0) < 0 ? "−" + $0 : $0 } ?? words
        let account = f.source == "Splits"
        let lead: String
        switch f.source {
        case "Acorns":       lead = String(localized: "Balance in Acorns")
        default:             lead = String(localized: "Account in \(f.source)")
        }
        return MoneyReceipt(
            subject: .named(f.source),
            mine: nil,
            lead: lead,
            party: name.isEmpty ? nil : name,
            // A Splits account carries no figure: its line says what it is
            // ("Account", "Archived account").
            titleFallback: figure == nil ? (account && !f.content.isEmpty ? f.content : lead) : nil,
            amount: figure.map {
                Amount(number: $0, unit: nil, tone: .plain,
                       numeric: priced == nil ? nil : f.priceValue)
            },
            secondary: nil,
            sentence: account ? String(localized: "An account in your Splits team.")
                : String(localized: "As of \(dayPhrase(f.capturedAt))."),
            stamp: nil,
            finality: .torn,
            hue: .neutral,
            form: .reading)
    }

    // MARK: Bills (prd §1341 amended)

    /// A Rocket Money plan as what it is: a bill. Its name (the part of
    /// `RocketMoneyLive`'s "<name> — <money>" before the seam), what it
    /// charges, and the day it was charged or falls due — a record with a
    /// Track tile, never a balance reading. No stamp: a plan has no state to
    /// settle.
    private static func bill(_ f: Facts) -> MoneyReceipt {
        var name = f.title
        var words: String?
        if let seam = f.title.range(of: " — ", options: .backwards) {
            name = String(f.title[..<seam.lowerBound])
            words = String(f.title[seam.upperBound...])
        }
        let priced = currency(f.priceValue, code: f.priceCurrency)
        let due = f.dueAt.map { $0 > Date.now } == true
        let figure = priced ?? words
        return MoneyReceipt(
            subject: .named(f.source),
            mine: nil,
            lead: String(localized: "Bill"),
            party: name.isEmpty ? nil : name,
            titleFallback: figure == nil ? f.title : nil,
            amount: figure.map {
                Amount(number: $0, unit: nil, tone: .plain,
                       numeric: priced == nil ? nil : f.priceValue.map(abs))
            },
            secondary: nil,
            sentence: due
                ? String(localized: "Next charge \(dayPhrase(f.dueAt ?? f.capturedAt)).")
                : String(localized: "Charged \(dayPhrase(f.capturedAt))."),
            stamp: nil,
            finality: .torn,
            hue: .neutral)
    }

    // MARK: Privacy Pools

    private static func pools(_ f: Facts) -> MoneyReceipt {
        // Tagged structurally by the bridge, so the state is read and never
        // inferred from the localized title.
        let cleared = f.tags.contains("Approved") || f.tags.contains("Cleared")
        let proof = f.tags.contains("Proof") || f.tags.contains("POI")
        let parts = split(f.amount)
        // The date alone: the stamp, the ladder and the commentary under the
        // receipt each already say where screening stands.
        let sentence = String(localized: "In since \(dayPhrase(f.capturedAt)).")
        return MoneyReceipt(
            // The pool's own mark, no person badge (prd §1341 amended): the
            // wallet it came from is the line under the figure.
            subject: .named(f.source),
            mine: nil,
            lead: String(localized: "Put into"),
            // Titled by what happened (prd §1357), never the app's name.
            party: actionTitle(f.title),
            titleFallback: parts.number.isEmpty ? f.title : nil,
            amount: parts.number.isEmpty ? nil
                : Amount(number: parts.number, unit: parts.unit, tone: .plain),
            secondary: f.myLabel.map { String(localized: "from \($0)") },
            sentence: sentence,
            stamp: proof ? .needsProof : (cleared ? .cleared : .screening),
            // Not yours to move until screening clears, so never torn while it
            // is still in review.
            finality: cleared ? .torn : .open,
            hue: .shield)
    }

    // MARK: Railgun

    private static func railgun(_ f: Facts) -> MoneyReceipt {
        let unshield = f.direction == "received"
        let parts = split(f.amount)
        return MoneyReceipt(
            // Railgun's own mark both ways (prd §1341 amended). The void drew
            // as an empty black disc with a person badge — a face that failed
            // to load; the sender's privacy is said in words, on the line.
            subject: .named(f.source),
            mine: nil,
            lead: unshield ? String(localized: "Unshielded into")
                           : String(localized: "Shielded from"),
            party: actionTitle(f.title),
            titleFallback: parts.number.isEmpty ? f.title : nil,
            amount: parts.number.isEmpty ? nil
                : Amount(number: (unshield ? "+" : "−") + parts.number,
                         unit: parts.unit, tone: unshield ? .gain : .plain),
            secondary: unshield
                ? String(localized: "The chain shows where it arrived, and nothing about where it came from.")
                : worthLine(f.usd),
            sentence: placeSentence(unshield ? String(localized: "Arrived")
                                             : String(localized: "Shielded"), f),
            // Out of the pool is UNshielded (prd §83): "Shielded" over an
            // unshield said the opposite of what happened.
            stamp: unshield ? .unshielded : .shielded,
            // The arrival genuinely is final. Privacy is not incompleteness.
            finality: .torn,
            hue: .railgun)
    }

    // MARK: Safe

    private static func safe(_ f: Facts) -> MoneyReceipt {
        let yourTurn = f.tags.contains("Your turn")
        // **A PROPOSAL IS NEVER SETTLED (prd §83).** Only the closing row the
        // bridge lands when a transaction leaves the queue
        // (`wallet:safeoutcome:`) is an outcome; every queue row is waiting,
        // whether or not the sheet's live check has answered.
        let outcome = f.sourceRef?.contains("wallet:safeoutcome:") == true
        let executed = outcome && f.title.hasPrefix("Executed")
        let replaced = outcome && f.title.hasPrefix("Replaced")
        let counts = f.signaturesNeed.map { (f.signaturesHave ?? 0, $0) } ?? safeCounts(f.title)
        let have = counts?.0 ?? 0
        let need = counts?.1 ?? 0
        let short = need > 0 && have < need ? need - have : 0
        // NAMED BY WHAT IT DOES (prd §1334, user: "ok on B"): the action the
        // row's own sentence carries ("a transfer of 1,500 USDC to
        // payroll.eth") is the title ("Send 1,500 USDC") and its party the
        // box's line ("to payroll.eth"); the Safe's name is the eyebrow.
        let act = safeAct(safeDescription(f.title))
        // WHO IT WAITS ON, said where the status is.
        let waitsOn: String? = outcome ? nil
            : yourTurn && short == 1 ? String(localized: "Waiting on one more signature, yours")
            : yourTurn ? String(localized: "Waiting on your signature")
            : short == 1 ? String(localized: "Waiting on one more signature")
            : short > 1 ? String(localized: "Waiting on \(short) more signatures")
            : f.title.hasPrefix("Fully signed") || (need > 0 && have >= need)
                ? String(localized: "Signed, waiting to be executed")
                : String(localized: "Waiting on its signers")
        return MoneyReceipt(
            // The Safe's own mark, not a blank person (prd §1334).
            subject: .named("Safe"),
            mine: f.counterpartyAddress,
            lead: outcome ? String(localized: "Sent from")
                          : String(localized: "Waiting to send"),
            // The row's own words when the act cannot be read, never the
            // Safe's name standing in (prd §1357.1).
            party: act?.title ?? actionTitle(f.title),
            // Safe stamps no amount field, and a multisig payload's value is
            // exactly the kind of number this file will not parse out of prose.
            titleFallback: act?.line,
            amount: nil,
            secondary: waitsOn,
            sentence: outcome
                ? placeSentence(executed ? String(localized: "Executed")
                                         : String(localized: "Replaced"), f)
                // Said in words, because an empty "Receipt —" row reads as a bug
                // where a sentence reads as the truth.
                : String(localized: "Proposed \(dayPhrase(f.capturedAt)). Nothing has moved yet, so there's no receipt to show."),
            stamp: executed ? .settled : replaced ? .replaced : outcome ? nil
                : yourTurn ? .yourTurn : .waiting,
            finality: outcome ? .torn : .open,
            hue: .safe)
    }

    /// "2 of 3 signatures collected on …" → (2, 3), `SafeBridge.rowFace`'s
    /// own shape; nil for any other sentence.
    static func safeCounts(_ title: String) -> (Int, Int)? {
        guard let r = title.range(of: " signatures collected on ") else { return nil }
        let head = title[..<r.lowerBound].split(separator: " ")
        guard head.count == 3, head[1] == "of", let have = Int(head[0]), let need = Int(head[2]) else { return nil }
        return (have, need)
    }

    /// The action inside a Safe row's sentence, as `SafeBridge.rowFace`
    /// writes it: "N of M signatures collected on <it>[ — …]" or "Fully
    /// signed — <it> is ready to execute / is behind …". nil when the
    /// sentence is in another shape (another language included).
    static func safeDescription(_ title: String) -> String? {
        var body = title
        if let r = body.range(of: " signatures collected on ") {
            body = String(body[r.upperBound...])
            if let dash = body.range(of: " — ") { body = String(body[..<dash.lowerBound]) }
            return body.isEmpty ? nil : body
        }
        // The closing row (`SafeBridge.landOutcome`): "Executed[ after …] —
        // <it> went through", "Replaced[ after …] — <it> never executed; …".
        if body.hasPrefix("Executed") || body.hasPrefix("Replaced"),
           let dash = body.range(of: " — ") {
            body = String(body[dash.upperBound...])
            for tail in [" went through", " never executed"] {
                if let t = body.range(of: tail) { body = String(body[..<t.lowerBound]) }
            }
            return body.isEmpty ? nil : body
        }
        if let r = body.range(of: "Fully signed — ") {
            body = String(body[r.upperBound...])
            for tail in [" is ready to execute", " is behind "] {
                if let t = body.range(of: tail) { body = String(body[..<t.lowerBound]) }
            }
            return body.isEmpty ? nil : body
        }
        return nil
    }

    /// The action as a title and a line: "a transfer of 1,500 USDC to
    /// payroll.eth" → ("Send 1,500 USDC", "to payroll.eth"); an approval
    /// names who may spend. Anything else stands as its own words,
    /// capitalised, with no line.
    static func safeAct(_ description: String?) -> (title: String, line: String?)? {
        guard let d = description, !d.isEmpty else { return nil }
        func cut(_ s: String, _ prefix: String) -> String? {
            s.hasPrefix(prefix) ? String(s.dropFirst(prefix.count)) : nil
        }
        if let rest = cut(d, "a transfer of "), let to = rest.range(of: " to ", options: .backwards) {
            return (String(localized: "Send \(rest[..<to.lowerBound])"),
                    String(localized: "to \(rest[to.upperBound...])"))
        }
        if let rest = cut(d, "a transfer to ") {
            return (String(localized: "Send"), String(localized: "to \(rest)"))
        }
        if let rest = cut(d, "an unlimited approval for ") {
            return (String(localized: "Approve \(rest)"), String(localized: "to spend without limit"))
        }
        if let rest = cut(d, "an approval for "), let spend = rest.range(of: " to spend ") {
            return (String(localized: "Approve \(rest[..<spend.lowerBound])"),
                    String(localized: "to spend \(rest[spend.upperBound...])"))
        }
        if let rest = cut(d, "an approval for ") {
            return (String(localized: "Approve \(rest)"), nil)
        }
        var words = d
        for article in ["a ", "an "] where words.hasPrefix(article) { words = String(words.dropFirst(article.count)) }
        return (words.prefix(1).uppercased() + words.dropFirst(), nil)
    }

    // MARK: The fallback that is not a failure

    /// A money row with no stamped signed amount: a self-move, a swap, a
    /// Hyperliquid open or close, a Morpho supply, a risk crossing. It gets the
    /// pour, the subject, the stamp, the sentence and the tear — everything but
    /// a headline figure it was never given.
    private static func generic(_ f: Facts, hue: Hue) -> MoneyReceipt? {
        // A row dated ahead (a deadline the bridge stamped `dueAt` on) says
        // what WILL happen: a moment, never a receipt (prd §83).
        if f.dueAt.map({ $0 > f.capturedAt }) == true { return nil }
        let risk = f.tags.contains("At risk")
        // An approval says who can spend what (prd §1357): "Uniswap can spend
        // your USDC", never the wallet's name as if it were the other side.
        let approval = f.sourceRef?.hasPrefix("wallet:approval:") == true
        // A figure the bridge stamped is drawn once, in the box, unsigned —
        // with no direction it has no sign to wear.
        let parts = split(f.amount)
        // **TITLED BY ITS OWN SENTENCE (prd §1357.1).** "Received 500 USDC
        // from sam.eth", "Bought SOL" — never "In your account" or the
        // wallet's name standing in for what happened.
        return MoneyReceipt(
            // An approval's other side is a contract that can spend, never a
            // person (prd §1360): the token it may spend, no face, no badge.
            subject: approval
                ? approvalToken(f.title).map { Subject.asset($0) } ?? .named("Wallet")
                : subject(address: f.counterpartyAddress,
                          name: f.partyLabel ?? f.venue,
                          fallbackAsset: nil),
            mine: approval ? nil : f.walletAddress,
            lead: String(localized: "In your account"),
            party: approval ? f.title : actionTitle(f.title),
            // **SAID ONCE (prd §1360, user: "seems silly to repeat the same
            // thing three times").** The title is the sentence; the box
            // states the figure, or nothing, never the sentence again.
            titleFallback: nil,
            amount: approval
                ? approvalToken(f.title).map { Amount(number: f.amount ?? "", unit: $0, tone: .plain) }
                : (parts.number.isEmpty ? nil : Amount(number: parts.number, unit: parts.unit, tone: .plain)),
            secondary: worthLine(f.usd),
            sentence: placeSentence(String(localized: "Happened"), f),
            // SETTLED ONLY WHEN IT SETTLED (prd §83): a past move the bridge
            // stamped a direction or a figure on. A trade or a supply with
            // neither states no status rather than a default one.
            stamp: risk ? .openPosition
                : (!approval && isPast(f) && (f.direction == "sent" || f.direction == "received"
                                              || !parts.number.isEmpty)) ? .settled : nil,
            // An open position is never a finished record and this receipt must
            // never look like history.
            finality: risk ? .open : .torn,
            hue: risk ? .risk : hue)
    }

    /// Dated now or earlier (a minute's grace for a clock that runs ahead).
    static func isPast(_ f: Facts, now: Date = .now) -> Bool {
        f.capturedAt <= now.addingTimeInterval(60)
    }

    // MARK: - Sentences

    private static func transferSentence(_ f: Facts, received: Bool) -> String {
        let verb = received ? String(localized: "Landed in")
                            : String(localized: "Left")
        guard let wallet = f.myLabel, !wallet.isEmpty else {
            return placeSentence(received ? String(localized: "Landed")
                                          : String(localized: "Left"), f)
        }
        if let network = f.network {
            return String(localized: "\(verb) \(wallet) \(dayPhrase(f.capturedAt)), on \(network).")
        }
        return String(localized: "\(verb) \(wallet) \(dayPhrase(f.capturedAt)).")
    }

    private static func bitcoinSentence(_ f: Facts) -> String {
        // `BitcoinBridge` parks the block on `transferVenue` — the
        // un-renameable "where it happened" slot — because a block is a
        // numbered, permanent, ten-minute-wide moment. Here it is the
        // sentence's subject rather than a table row.
        if let block = f.venue, !block.isEmpty {
            return String(localized: "Mined into \(block) \(dayPhrase(f.capturedAt)).")
        }
        return String(localized: "Seen \(dayPhrase(f.capturedAt)), not yet in a block.")
    }

    private static func cardSentence(_ f: Facts, pending: Bool, refund: Bool) -> String {
        if refund {
            return String(localized: "Refunded \(dayPhrase(f.capturedAt)).")
        }
        if pending {
            return String(localized: "Authorized \(dayPhrase(f.capturedAt)). The amount can still change until it settles.")
        }
        if let network = f.network {
            return String(localized: "Settled \(dayPhrase(f.capturedAt)), on \(network).")
        }
        return String(localized: "Posted \(dayPhrase(f.capturedAt)).")
    }

    /// "<Verb> this morning, on Base." — the shape every remaining family
    /// shares, with the network clause dropped rather than guessed when the
    /// content carries no chain.
    private static func placeSentence(_ verb: String, _ f: Facts) -> String {
        if let network = f.network, !network.isEmpty {
            return String(localized: "\(verb) \(dayPhrase(f.capturedAt)), on \(network).")
        }
        return String(localized: "\(verb) \(dayPhrase(f.capturedAt)).")
    }

    /// Priced AT LANDING (`transferUSD`, read off the bridge's own leg
    /// pricing) — never today's rate, which would restate history every time
    /// the market moved. nil shows nothing rather than a guess.
    private static func worthLine(_ usd: Double?) -> String? {
        guard let usd, usd > 0 else { return nil }
        return String(localized: "worth about \(fiat(usd)) when it landed")
    }

    // MARK: - Formatting

    /// "$3,480" / "$12.99" — cents only where they carry information.
    /// `TransferStageView.fiat`'s rule, kept when that view retired.
    static func fiat(_ usd: Double) -> String {
        usd.formatted(.currency(code: "USD")
            .precision(.fractionLength(usd < 100 ? 2 : 0)))
    }

    /// A minor-unit amount in its own currency. Returns nil rather than a bare
    /// number when either half is missing — an amount with no currency is not a
    /// figure a receipt may state.
    ///
    /// To the currency's own minor unit, whatever the size (a Plasma One day
    /// of $305.80 drew "$306"): a charge is read, not rounded, as a balance is.
    static func currency(_ value: Double?, code: String?) -> String? {
        guard let value, let code, !code.isEmpty else { return nil }
        return abs(value).formatted(.currency(code: code))
    }

    /// "0.9962 ETH" → ("0.9962", "ETH").
    ///
    /// The unit is the LAST whitespace component, and only when it looks like a
    /// ticker: letters and digits, one letter at least, at most `unitCap` of them. **A token "name" is
    /// attacker-controlled text** — a real spoofed row measured on this corpus
    /// read `4,672 USDT Staked • gitos.org`, a phishing domain — so anything
    /// that doesn't look like a ticker stays inside `number`, where the view
    /// clamps it to one line at a scaled-down size rather than promoting it to a
    /// display unit beside the figure. Letting that through would have printed a
    /// phishing domain in the receipt's own currency slot.
    static let unitCap = 12
    static func split(_ amount: String?) -> (number: String, unit: String?) {
        let raw = (amount ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return ("", nil) }
        let parts = raw.split(separator: " ")
        guard parts.count >= 2, let last = parts.last,
              last.count <= unitCap,
              // A ticker may carry a digit ("MAG7", "1INCH", prd §1373), never
              // punctuation, and is never a bare number.
              last.allSatisfy({ $0.isLetter || $0.isNumber }),
              last.contains(where: { $0.isLetter }) else { return (raw, nil) }
        return (parts.dropLast().joined(separator: " "), String(last))
    }

    /// The subject disc, chosen by what we actually hold. Order is the grades of
    /// knowing: a real address beats a name, a name beats a bare asset symbol.
    static func subject(address: String?, name: String?,
                        fallbackAsset: String?) -> Subject {
        if let address, !address.isEmpty { return .address(address) }
        if let name, !name.isEmpty { return .named(name) }
        if let fallbackAsset, !fallbackAsset.isEmpty { return .asset(fallbackAsset) }
        return .named("Wallet")
    }

    /// Human time — "this morning", "yesterday", "on Wednesday", "on 5 Aug".
    ///
    /// Deliberately vaguer than the timestamp it replaces, and that is the
    /// point: `Aug 11, 09:41` is a database column, and nobody reading their own
    /// receipt needs the minute. The exact instant is still on the row's own
    /// eyebrow and in the explorer the dial opens.
    static func dayPhrase(_ date: Date, now: Date = .now,
                          calendar: Calendar = .current) -> String {
        // Every branch measures against `now`, including today and yesterday
        // (2026-08-12). `isDateInToday`/`isDateInYesterday` read the SYSTEM
        // clock and ignore the `now` this function was handed, so the two
        // halves of one decision were measured against two different clocks:
        // "today" came from the real date while the weekday branch below came
        // from `now`. Production never noticed, because production passes the
        // real `.now` and the two agree — but the function could not be
        // tested at all, and its own harness asserted against a fixed clock
        // it had no way to honour.
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        if days == 0 {
            let hour = calendar.component(.hour, from: date)
            switch hour {
            case ..<5:   return String(localized: "overnight")
            case ..<12:  return String(localized: "this morning")
            case ..<18:  return String(localized: "this afternoon")
            default:     return String(localized: "this evening")
            }
        }
        if days == 1 { return String(localized: "yesterday") }
        // Inside a week a weekday is the most useful name; past that it stops
        // being unambiguous and the date is kinder. A FUTURE date (a clock skew,
        // a bridge stamping ahead) falls through to the dated form rather than
        // claiming a weekday that hasn't happened.
        if days >= 2, days <= 6 {
            return String(localized: "on \(date.formatted(.dateTime.weekday(.wide)))")
        }
        return String(localized: "on \(date.formatted(.dateTime.day().month(.abbreviated)))")
    }
}
