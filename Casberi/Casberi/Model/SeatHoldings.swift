import Foundation

/// **WHAT AN APP PICKED HOLDS, WHERE NO WALLET READ CARRIES IT (prd §1703,
/// user: "Show something" in Holdings, then "Also add new reads").** §1702
/// put 0xBow's private money and Plasma One's card under Holdings on their
/// picks; this is the rest that can be said honestly:
///
/// - **ENS** — the names you follow, each with the expiry its title states.
/// - **CardPointers** — the cards it tracks, each with its unused offers.
/// - **MetaMask Card** — "Can spend": per wallet and chain, the lower of the
///   card's foxConnect allowance and the stablecoin it may draw. That money
///   is the wallet's own, already in Tokens, so this is NEVER counted.
/// - **Privacy.com** — each open card's limit, and what is left of a
///   monthly one. A limit is no money held: drawn as words, never summed.
/// - **ether.fi** — each Cash account's collateral and what it can still
///   borrow. The collateral sits in the safe you watch, already in the
///   Wallet's number, so this is NEVER counted.
/// - **Rocket Money** — the accounts it tracks, each with its balance, a
///   card's or loan's as owed words (§1704, UNMEASURED). Never counted.
/// - **Peer** — what a seller has in Peer's escrow (`remainingDeposits` +
///   `outstandingIntentAmount`). It left the wallet, so it is in no total
///   — and it is not added to one here either (§1703 item 5).
///
/// Every reading is the app's own, kept as its read left it
/// (`UserDefaults`, JSON); the demo holds its own (§483: it reads nothing).
/// `wallet-total-audit.py` rule §1703 fails any of them reaching the
/// Wallet's number. `seat-holdings-selftest.sh` holds the compositions.
enum SeatHoldings {

    /// One thing an app holds for you: a name, its dollars when it has any
    /// (0 when it is no money, or none could be priced), and the words that
    /// stand in for dollars.
    struct Item: Equatable, Codable, Sendable {
        let name: String
        let usd: Double
        let figure: String?
        /// A landed row's ref, when the item is one (ENS), so its row opens it.
        var ref: String? = nil
    }

    // MARK: - From rows the seat already landed

    /// ENS: every followed name the seat has read, with the words after its
    /// name in its own title ("expires 9 Dec 2027", "in grace until …").
    /// A name nobody has registered holds nothing and is left out.
    static func ens(_ rows: [(ref: String?, title: String, live: Bool)]) -> [Item] {
        rows.compactMap { row in
            guard row.live, let ref = row.ref, let name = ENSRef.name(ref) else { return nil }
            let rest = row.title.hasPrefix(name)
                ? String(row.title.dropFirst(name.count)).trimmingCharacters(in: .whitespaces)
                : ""
            // "— nobody has registered it": not held by anyone.
            guard !rest.hasPrefix("—") else { return nil }
            return Item(name: name, usd: 0, figure: rest.isEmpty ? nil : rest, ref: ref)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// CardPointers: the cards its offers name, A–Z, each with how many of
    /// its offers are still unused. A card whose offers are all used stays,
    /// at none: it is still a card it tracks.
    static func cardPointers(_ rows: [(card: String?, done: Bool, live: Bool)]) -> [Item] {
        var unused: [String: Int] = [:]
        for row in rows where row.live {
            guard let card = row.card?.trimmingCharacters(in: .whitespaces), !card.isEmpty else { continue }
            unused[card, default: 0] += row.done ? 0 : 1
        }
        return unused.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { card in
            let n = unused[card] ?? 0
            let words = n == 0 ? String(localized: "No unused offers")
                : n == 1 ? String(localized: "1 unused offer")
                : String(localized: "\(n) unused offers")
            return Item(name: card, usd: 0, figure: words)
        }
    }

    // MARK: - Privacy.com: a card's limit (UNMEASURED, prd §780b)

    /// One card as `GET /v1/cards` describes it. UNMEASURED: the field names
    /// are Privacy's published ones (`token`, `last_four`, `memo`, `state`,
    /// `spend_limit` in cents, `spend_limit_duration`), never read live from
    /// this app; `-privacyProbe` is where they get reconciled.
    struct PrivacyCard: Equatable, Sendable {
        let token: String
        let lastFour: String?
        let memo: String?
        let state: String
        let limitCents: Int?
        let duration: String?
    }

    static func privacyCard(_ raw: [String: Any]) -> PrivacyCard? {
        guard let token = raw["token"] as? String, !token.isEmpty else { return nil }
        let limit = (raw["spend_limit"] as? Int) ?? (raw["spend_limit"] as? NSNumber)?.intValue
        return PrivacyCard(token: token,
                           lastFour: raw["last_four"] as? String,
                           memo: (raw["memo"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                           state: (raw["state"] as? String)?.uppercased() ?? "",
                           limitCents: limit.flatMap { $0 > 0 ? $0 : nil },
                           duration: (raw["spend_limit_duration"] as? String)?.uppercased())
    }

    /// The open and paused cards, each with its limit in words. A MONTHLY
    /// limit says what is left this calendar month, from `spentCents` — the
    /// approved purchases the same pass read, keyed by card token. Any other
    /// duration states the limit alone: a yearly or lifetime sum would need
    /// more history than one page of transactions holds.
    static func privacy(_ cards: [PrivacyCard], spentCents: [String: Int]) -> [Item] {
        cards.filter { $0.state == "OPEN" || $0.state == "PAUSED" }.map { card in
            let name = card.memo ?? card.lastFour.map { String(localized: "Card ending \($0)") }
                ?? String(localized: "Card")
            return Item(name: name, usd: 0, figure: privacyWords(card, spent: spentCents[card.token] ?? 0))
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func privacyWords(_ card: PrivacyCard, spent: Int) -> String {
        if card.state == "PAUSED" { return String(localized: "Paused") }
        guard let limit = card.limitCents else { return String(localized: "No limit") }
        let cap = dollars(limit)
        switch card.duration {
        case "MONTHLY":
            return String(localized: "\(dollars(max(0, limit - spent))) left of \(cap) a month")
        case "ANNUALLY":     return String(localized: "\(cap) a year")
        case "TRANSACTION":  return String(localized: "\(cap) a purchase")
        case "FOREVER":      return String(localized: "\(cap) in all")
        default:             return cap
        }
    }

    private static func dollars(_ cents: Int) -> String {
        (Double(cents) / 100).formatted(.currency(code: "USD"))
    }

    // MARK: - ether.fi Cash: collateral and what it can still borrow

    static func etherFi(_ accounts: [(safe: String, collateralUSD: Double, remainingUSD: Double)]) -> [Item] {
        accounts.map { account in
            Item(name: String(localized: "Cash account \(AddressTail.short(account.safe))"),
                 usd: account.collateralUSD,
                 figure: String(localized: "\(account.remainingUSD.formatted(.currency(code: "USD"))) to borrow"))
        }
    }

    // MARK: - Peer: a seller's money in escrow (UNMEASURED, prd §780b)

    /// `getDeposit(depositId)`'s words 6 and 7, `remainingDeposits` and
    /// `outstandingIntentAmount`, after `depositor, delegate, token,
    /// intentAmountRange{min, max}, acceptingIntents` — the struct as Peer's
    /// `IEscrow.sol` declares it, and word 5 is the `acceptingIntents` this
    /// seat already MEASURED. Words 6–7 were not read live: UNMEASURED.
    static func peerHeld(remaining: Double, outstanding: Double) -> Double { remaining + outstanding }

    /// One deposit's escrowed money: dollars for a dollar stablecoin, the
    /// token's own quantity otherwise (no price is guessed, §83).
    static func peer(_ deposits: [(id: String, symbol: String?, amount: Double)]) -> [Item] {
        deposits.filter { $0.amount > 0 }.map { deposit in
            let symbol = deposit.symbol ?? ""
            let usd = dollarStables.contains(symbol.uppercased()) ? deposit.amount : 0
            return Item(name: String(localized: "Deposit #\(deposit.id)"), usd: usd,
                        figure: usd > 0 ? nil : "\(deposit.amount.formatted(.number.precision(.fractionLength(0...4)))) \(symbol)")
        }
    }

    static let dollarStables: Set<String> = ["USDC", "USDT", "USDBC", "DAI", "MUSD", "AUSDC", "AMUSD"]

    // MARK: - Rocket Money: the accounts it tracks (UNMEASURED, prd §780b)

    /// One account Rocket Money tracks, as its accounts read hands it over.
    /// UNMEASURED (prd §780b): the operation that carries them is whichever
    /// the live page was seen to send (`RocketMoneyIngest.accountOperations`),
    /// and its field names are conventions `LooseJSON` tries, never observed.
    struct RocketAccount: Equatable, Sendable {
        let name: String
        let institution: String?
        let balance: Double?
        /// The account's type in Rocket Money's words ("credit", "loan",
        /// "depository"…), lower-cased; nil when none was read.
        let kind: String?
        var closed: Bool = false
    }

    /// A balance on a credit card or a loan is OWED, never held (§1078), so
    /// it is stated in words and sized as nothing.
    static func rocketOwes(_ kind: String?) -> Bool {
        guard let kind else { return false }
        return ["credit", "loan", "mortgage", "liability"].contains { kind.contains($0) }
    }

    /// The accounts Rocket Money tracks, open ones only, named "Bank ·
    /// account" (the bank once), largest held first, then what is owed A–Z.
    /// These banks may already reach the Wallet through SimpleFIN or Apple
    /// Wallet, so nothing here is EVER counted (`wallet-total-audit.py`,
    /// prd §1704).
    static func rocketMoney(_ accounts: [RocketAccount]) -> [Item] {
        accounts.filter { !$0.closed }.map { account in
            let name: String
            if let bank = account.institution?.trimmingCharacters(in: .whitespaces), !bank.isEmpty,
               !account.name.localizedCaseInsensitiveContains(bank) {
                name = "\(bank) · \(account.name)"
            } else {
                name = account.name
            }
            guard let balance = account.balance else {
                return Item(name: name, usd: 0, figure: String(localized: "No balance read"))
            }
            if rocketOwes(account.kind) {
                let owed = abs(balance).formatted(.currency(code: "USD"))
                return Item(name: name, usd: 0, figure: String(localized: "\(owed) owed"))
            }
            return Item(name: name, usd: max(0, balance), figure: nil)
        }
        .sorted { a, b in
            a.usd != b.usd ? a.usd > b.usd : a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    // MARK: - MetaMask Card: what the card can draw

    /// The card can draw the lower of what the allowance lets it take and
    /// what the wallet holds of that token — per token, then summed (each a
    /// dollar stablecoin, `Spendable.currency == "USD"`).
    static func canSpend(_ pairs: [(allowance: Double, balance: Double)]) -> Double {
        pairs.reduce(0) { $0 + max(0, min($1.allowance, $1.balance)) }
    }

    static func metaMask(_ usd: Double) -> [Item] {
        usd > 0 ? [Item(name: String(localized: "Can spend"), usd: usd, figure: nil)] : []
    }
}

/// The name behind an ENS seat ref (`ens:name:<name>`), pure so the self-test
/// compiles it without the seat.
enum ENSRef {
    static func name(_ ref: String) -> String? {
        let prefix = "ens:name:"
        guard ref.hasPrefix(prefix) else { return nil }
        let name = String(ref.dropFirst(prefix.count))
        return name.isEmpty ? nil : name
    }
}
