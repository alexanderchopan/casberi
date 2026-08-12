import Foundation

/// The receipt — one anatomy for every money thing in the corpus (prd §369,
/// 2026-08-12).
///
/// **Why this exists.** Until now exactly three things got a hero on the thing
/// sheet, and the gate was a source-name string: `kind == .transaction &&
/// source == "Wallet"` (`ThingStage`'s three parsers). Everything else — an
/// Apple Wallet charge, a Gnosis Pay spend, a Peer fill, a Privacy Pools
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
/// **Foundation-only by design**, the `GnosisPayRoom` split: everything that can
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

        var word: String {
            switch self {
            case .settled:      return String(localized: "Settled")
            case .pending:      return String(localized: "Pending")
            case .settling:     return String(localized: "Settling")
            case .filled:       return String(localized: "Filled")
            case .yourTurn:     return String(localized: "Your turn")
            case .shielded:     return String(localized: "Shielded")
            case .screening:    return String(localized: "Screening")
            case .needsProof:   return String(localized: "Needs proof")
            case .refund:       return String(localized: "Refund")
            case .openPosition: return String(localized: "Open position")
            case .cleared:      return String(localized: "Clear to withdraw")
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
            case .shielded:                              return .private_
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
    }

    /// Which sources get a receipt. Declared once, and deliberately a SET of
    /// names rather than a `kind` test: `.transaction` also covers rows that are
    /// really notices ("this address hasn't moved since March"), and a source
    /// missing from here keeps exactly the sheet it has today rather than
    /// getting a half-composed hero.
    static let sources: Set<String> = [
        "Wallet", "Apple Wallet", "Gnosis Pay", "ether.fi", "Privacy",
        "Peer", "Privacy Pools", "Railgun", "Safe",
    ]

    // MARK: - Composition

    /// The receipt, or nil when this thing isn't one we draw.
    static func compose(_ f: Facts) -> MoneyReceipt? {
        guard sources.contains(f.source) else { return nil }
        switch f.source {
        case "Apple Wallet":                 return card(f, hue: .neutral)
        case "Gnosis Pay", "ether.fi", "Privacy": return card(f, hue: .card)
        case "Peer":                         return peer(f)
        case "Privacy Pools":                return pools(f)
        case "Railgun":                      return railgun(f)
        case "Safe":                         return safe(f)
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
        let party = f.partyLabel ?? f.counterparty
        return MoneyReceipt(
            subject: subject(address: f.counterpartyAddress, name: party,
                             fallbackAsset: parts.unit),
            mine: f.walletAddress,
            lead: received ? String(localized: "Received from")
                           : String(localized: "Sent to"),
            party: party,
            titleFallback: nil,
            amount: Amount(number: (received ? "+" : "−") + parts.number,
                           unit: parts.unit,
                           tone: received ? .gain : .plain),
            secondary: worthLine(f.usd),
            sentence: transferSentence(f, received: received),
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
            party: f.myLabel,
            titleFallback: parts.number.isEmpty ? f.title : nil,
            amount: parts.number.isEmpty ? nil
                : Amount(number: (received ? "+" : "−") + parts.number,
                         unit: parts.unit, tone: received ? .gain : .plain),
            // Said out loud rather than left blank: this bridge reads a chain,
            // and a blank where every other receipt shows a dollar figure reads
            // as a number we failed to fetch.
            secondary: String(localized: "Casberi reads the chain here, not a market — so there's no dollar figure to give you."),
            sentence: bitcoinSentence(f),
            stamp: settling ? .settling : .settled,
            finality: settling ? .open : .torn,
            hue: .bitcoin)
    }

    // MARK: Card spends

    /// Apple Wallet, Gnosis Pay, ether.fi Cash and Privacy.com. One arm,
    /// because a card spend is a card spend; the differences that matter are
    /// which subject can be drawn (a merchant name, or a void where the chain
    /// carries none) and whether the amount can still change.
    private static func card(_ f: Facts, hue: Hue) -> MoneyReceipt {
        let refund = f.tags.contains("Refund")
        let pending = f.tags.contains("Pending")
        let merchant = f.counterparty
        let money = currency(f.priceValue, code: f.priceCurrency)
            ?? split(f.amount).number
        let onchain = f.source == "Gnosis Pay" || f.source == "ether.fi"
        return MoneyReceipt(
            subject: merchant.map { Subject.named($0) }
                ?? (onchain ? .absent(.merchantOffchain) : .named(f.source)),
            // No second face: a card spend has one party and it is the shop.
            mine: nil,
            lead: refund ? String(localized: "Refunded by")
                         : String(localized: "Spent at"),
            party: merchant ?? (onchain ? nil : f.source),
            titleFallback: money.isEmpty ? f.title : nil,
            amount: money.isEmpty ? nil
                : Amount(number: (refund ? "+" : "−") + money, unit: nil,
                         tone: refund ? .gain : .plain),
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
        let parts = split(f.amount)
        let sell = f.sourceRef?.hasPrefix("peer:sell:") == true
        return MoneyReceipt(
            // The rail is the subject: it is the thing you'd recognize, and
            // it's a known app so `AssetMark` may have real artwork for it.
            subject: rail.map { Subject.named($0) } ?? .named("Peer"),
            mine: f.walletAddress,
            lead: sell ? String(localized: "Sold through")
                       : String(localized: "Bought with"),
            party: rail,
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

    // MARK: Privacy Pools

    private static func pools(_ f: Facts) -> MoneyReceipt {
        // Tagged structurally by the bridge, so the state is read and never
        // inferred from the localized title.
        let cleared = f.tags.contains("Approved") || f.tags.contains("Cleared")
        let proof = f.tags.contains("Proof") || f.tags.contains("POI")
        let screening = !cleared && !proof
        let parts = split(f.amount)
        let sentence: String
        if proof {
            sentence = String(localized: "In since \(dayPhrase(f.capturedAt)). Privacy Pools has asked you for proof before it will clear.")
        } else if cleared {
            sentence = String(localized: "Cleared screening — this is yours to withdraw.")
        } else {
            sentence = String(localized: "In since \(dayPhrase(f.capturedAt)). Still being screened, so it isn't yours to withdraw yet.")
        }
        return MoneyReceipt(
            subject: .asset(parts.unit ?? "ETH"),
            mine: f.walletAddress,
            lead: String(localized: "Put into"),
            party: String(localized: "Privacy Pools"),
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
            // The one place a void is the RIGHT subject: an unshield's sender
            // is absent by design, and a monogram would imply we merely
            // couldn't read it.
            subject: unshield ? .absent(.senderPrivate)
                              : .asset(parts.unit ?? "ETH"),
            mine: f.walletAddress,
            lead: unshield ? String(localized: "Unshielded into")
                           : String(localized: "Shielded from"),
            party: f.myLabel,
            titleFallback: parts.number.isEmpty ? f.title : nil,
            amount: parts.number.isEmpty ? nil
                : Amount(number: (unshield ? "+" : "−") + parts.number,
                         unit: parts.unit, tone: unshield ? .gain : .plain),
            secondary: unshield
                ? String(localized: "The chain shows where it arrived, and nothing about where it came from.")
                : worthLine(f.usd),
            sentence: placeSentence(unshield ? String(localized: "Arrived")
                                             : String(localized: "Shielded"), f),
            stamp: .shielded,
            // The arrival genuinely is final. Privacy is not incompleteness.
            finality: .torn,
            hue: .railgun)
    }

    // MARK: Safe

    private static func safe(_ f: Facts) -> MoneyReceipt {
        let yourTurn = f.tags.contains("Your turn")
        let have = f.signaturesHave ?? 0
        let need = f.signaturesNeed ?? 0
        let waiting = need > 0 && have < need
        return MoneyReceipt(
            subject: subject(address: f.walletAddress,
                             name: f.myLabel, fallbackAsset: nil),
            mine: f.counterpartyAddress,
            lead: waiting ? String(localized: "Waiting to send")
                          : String(localized: "Sent from"),
            party: f.myLabel,
            // Safe stamps no amount field, and a multisig payload's value is
            // exactly the kind of number this file will not parse out of prose.
            titleFallback: f.title,
            amount: nil,
            secondary: waiting && need - have == 1
                ? String(localized: "one more signature and it goes")
                : nil,
            sentence: waiting
                // Said in words, because an empty "Receipt —" row reads as a bug
                // where a sentence reads as the truth.
                ? String(localized: "Proposed \(dayPhrase(f.capturedAt)). Nothing has moved yet, so there's no receipt to show.")
                : placeSentence(String(localized: "Executed"), f),
            stamp: yourTurn ? .yourTurn : (waiting ? .pending : .settled),
            finality: waiting ? .open : .torn,
            hue: .safe)
    }

    // MARK: The fallback that is not a failure

    /// A money row with no stamped signed amount: a self-move, a swap, a
    /// Hyperliquid open or close, a Morpho supply, a risk crossing. It gets the
    /// pour, the subject, the stamp, the sentence and the tear — everything but
    /// a headline figure it was never given.
    private static func generic(_ f: Facts, hue: Hue) -> MoneyReceipt {
        let risk = f.tags.contains("At risk")
        return MoneyReceipt(
            subject: subject(address: f.counterpartyAddress,
                             name: f.partyLabel ?? f.venue,
                             fallbackAsset: nil),
            mine: f.walletAddress,
            lead: String(localized: "In your wallet"),
            party: f.myLabel,
            titleFallback: f.title,
            amount: nil,
            secondary: worthLine(f.usd),
            sentence: placeSentence(String(localized: "Happened"), f),
            stamp: risk ? .openPosition : nil,
            // An open position is never a finished record and this receipt must
            // never look like history.
            finality: risk ? .open : .torn,
            hue: risk ? .risk : hue)
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
    static func currency(_ value: Double?, code: String?) -> String? {
        guard let value, let code, !code.isEmpty else { return nil }
        return abs(value).formatted(.currency(code: code)
            .precision(.fractionLength(abs(value) < 100 ? 2 : 0)))
    }

    /// "0.9962 ETH" → ("0.9962", "ETH").
    ///
    /// The unit is the LAST whitespace component, and only when it looks like a
    /// ticker: letters alone, at most `unitCap` of them. **A token "name" is
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
              last.allSatisfy({ $0.isLetter }) else { return (raw, nil) }
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
        if calendar.isDateInToday(date) {
            let hour = calendar.component(.hour, from: date)
            switch hour {
            case ..<5:   return String(localized: "overnight")
            case ..<12:  return String(localized: "this morning")
            case ..<18:  return String(localized: "this afternoon")
            default:     return String(localized: "this evening")
            }
        }
        if calendar.isDateInYesterday(date) { return String(localized: "yesterday") }
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
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
