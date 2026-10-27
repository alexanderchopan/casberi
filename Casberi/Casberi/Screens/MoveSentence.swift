import SwiftUI
import SwiftData
import UIKit

/// **MOVE IS A SENTENCE YOU FILL IN (prd §1438)**, from the 2026-10-19 canvas
/// (user: "its still intimidating like a form"; "oooooh i like this").
///
///     Swap  Send  Receive
///     0.004 USDC
///     for ≈ 12.1 AERO
///     on Base.
///
/// The verbs stand on their own line, the picked one bright (§1438a); under
/// them every blank is a word: the amount, the token you spend, what you
/// want or who it goes to, the network. Tap a word and its choices open in the space under
/// the sentence — what you hold, Uniswap's list, your addresses — and typing only
/// narrows them; nothing slides over the page. One grey line says the rest:
/// the other unit (tap it to type in it), what you have, the fee.
///
/// The foot holds the slider (a share of what you have) and two words: the
/// verb, which signs, and **Add**, which keeps the sentence as a line at the
/// top and starts the next one in the same transaction — keeping what it is
/// for or who it is to, and the network, so three tokens for one, or several
/// tokens to one person, is Add and a number each time.
struct MoveSentence: View {
    let account: String
    /// In `MoveTray` (prd §1442): the tray brings its own side padding and
    /// there is no tab bar to clear.
    var inTray = false

    /// The account was just brought to this phone (§1442j): the sentence
    /// opens on Receive and finishes itself, "Your account" turning into
    /// "Ready …3416", the verbs arriving. A made account has no arrival here:
    /// it ends on the walk's own Created page (prd §1501), and its line about
    /// what the first move activates went with it — the co-signer step says it.
    enum Arrival { case broughtHere }
    var arrival: Arrival?

    init(account: String, inTray: Bool = false, arrival: Arrival? = nil, opening: Verb? = nil,
         privately: PrivateMove.Mode? = nil, receivePrivately: Bool = false) {
        self.account = account
        self.inTray = inTray
        self.arrival = arrival
        let mode = PrivateMove.available ? privately : nil
        let toFresh = PrivateMove.freshAvailable && receivePrivately && mode == nil
        _verb = State(initialValue: mode != nil ? .send : toFresh ? .receive : opening ?? (arrival == nil ? .swap : .receive))
        _freshReceive = State(initialValue: toFresh)
        _fresh = State(initialValue: arrival != nil)
        _privateMode = State(initialValue: mode)
        _privateMove = State(initialValue: PrivateMove(mode: mode ?? .deposit))
    }

    /// **SEND, PRIVATELY (prd §1554): a recipient and a switch, never a
    /// verb.** "Your private balance" leads Send's recipients (`.deposit`);
    /// the Private switch under any other recipient sends from it (`.send`).
    /// Either draws `MovePrivateSentence` under these verbs, over the
    /// account's sentence, which stays as it was. Never remembered on.
    @State private var privateMode: PrivateMove.Mode?
    @State private var privateMove = PrivateMove()

    /// **RECEIVE, PRIVATELY (prd §1560): a fresh address.** Receive's Private
    /// switch draws `MoveFreshSentence` under these verbs, over the
    /// account's sentence. Off on every arrival, never remembered on.
    @State private var freshReceive = false

    private func goPrivate(_ mode: PrivateMove.Mode) {
        privateMove.mode = mode
        privateMove.recipient = mode == .send ? resolved?.address : nil
        withAnimation(DS.Motion.standard) { open = nil; privateMode = mode }
        DSHaptic.selection()
    }

    private func goFresh() {
        withAnimation(DS.Motion.standard) { open = nil; freshReceive = true }
        DSHaptic.selection()
    }

    /// Still the arrival's sentence: until a verb is picked.
    @State private var fresh = false
    /// The beat has played: the past tense is said and the verbs are in.
    @State private var arrived = false
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    typealias Op = YourAccountOp
    typealias Chain = YourAccountChain
    typealias Tokens = YourAccountTokens

    enum Verb: CaseIterable { case swap, send, receive, buy, sweep }
    enum Blank: Equatable { case with, buy, to, network, destination, elsewhere, elsewhereCoin, arrives, group, merchant }
    enum Field: Hashable { case amount, search, to }

    struct Recipient: Equatable {
        let address: String
        let name: String?
        /// A book entry this raw address imitates (address poisoning).
        let imitates: String?
    }

    @State private var verb: Verb = .swap
    @State private var network: Op.Network = Op.base
    /// The network is a blank too until it is picked (§1438c): the sentence
    /// starts "0 token for token on network." and the network comes first.
    @State private var networkPicked = false
    @State private var heldBy: [Int: [Tokens.Held]] = [:]
    /// The networks no node answered for: their empty list is unknown,
    /// never "nothing there".
    @State private var unread: Set<Int> = []
    /// The networks this phone can use the account on (§1442k); nil until
    /// read, and every network on the phone that made the account.
    @State private var reach: [Op.Network]?
    /// Uniswap's token list for each network, read at once (prd §1542).
    @State private var listedBy: [Int: [Tokens.Listed]] = [:]
    /// The list's matches for what is typed in For (prd §1542), per network:
    /// every network until one is picked (§1442a).
    @State private var found: [Int: [Tokens.Listed]] = [:]
    @State private var with: Tokens.Held?
    @State private var buy: Tokens.Listed?
    /// Where what Swap buys arrives, when that is another network (prd
    /// §1555): picked from "Get <token> on"; nil is the sending network.
    /// While it is set, `buy` is a token of that network (prd §1566).
    @State private var buyOn: Op.Network?
    /// A swap to another network that landed: its fill is read until it
    /// arrives (prd §1555).
    @State private var crossingWatch: YourAccountAcross.Crossing?
    @State private var amount = ""
    /// Dollars first (§1442a, user: "user may want to say a dollar value
    /// before they choose token"): the amount can be typed before anything
    /// is picked, and the token it buys is worked out once one is.
    @State private var inDollars = true
    @State private var to = ""
    @State private var resolved: Recipient?
    @State private var malformed = false
    @State private var open: Blank?
    @State private var search = ""
    @State private var pasted: [Int: Tokens.Listed] = [:]
    @State private var items: [Chain.Item] = []
    /// Where the line being filled stands among the kept swaps (§1442g): a
    /// kept line tapped to edit takes its own place, not the bottom.
    @State private var slot = 0
    @State private var quote: YourAccountSwap.Quote?
    @State private var quoteNote: String?
    /// Whose words `quoteNote` is, drawn as its mark (§1442n), when they are
    /// a service's rather than the app's.
    @State private var quoteFrom: String?
    @State private var stage: Chain.Stage?
    /// What a signed transaction became, said in the sentence's place (§1438b).
    @State private var receipt: Receipt?
    /// Receiving from another network (prd §1453): the route picked, the
    /// networks Relay takes deposits on, and which token.
    @State private var elsewhere: YourAccountElsewhere.Route?
    @State private var elsewhereNetworks: [YourAccountElsewhere.Network] = []
    /// What you picked to receive (prd §1470); nil takes the default, the
    /// network's dollar, or ETH for ETH.
    @State private var elsewhereArrives: Op.Token?
    @State private var elsewhereFinding: String?
    /// What the sentence says back for a moment — what is missing, what
    /// failed — in its own line, because a toast draws under the tray
    /// (§1442c). Cleared after a few seconds, or by the next one.
    struct Hint: Equatable { let text: String; let failure: Bool; var from: String? = nil; let id = UUID() }
    @State private var hint: Hint?

    // MARK: - Details (prd §1509)

    /// What signing the sentence would do now (`Chain.preview`), and the
    /// sentence it was read for: a preview of another sentence is never drawn.
    @State private var preview: Chain.Preview?
    @State private var previewFor = ""
    /// Details open under the grey line; Raw transaction, a page deeper.
    @State private var details = false
    @State private var rawOpen = false

    // MARK: - Warnings (prd §1509 item 2, §1513)

    @Environment(\.modelContext) private var context
    /// What `MoveChecks` found about the sentence's addresses and token, the
    /// sentence it was read for, and what Details says was checked.
    @State private var findings: [MoveWarnings.Finding] = []
    @State private var checkedWith: [String] = []
    @State private var findingsFor = ""
    /// The warning a first tap armed: the verb signs on the second tap only
    /// while this is still the warning on screen.
    @State private var armed = ""

    // MARK: - Buy (prd §1473)

    /// Buy stands on the verbs' line only with an account on this phone —
    /// known from the first frame (one `UserDefaults` read), never after the
    /// balances load: Buy arriving a second late read as an error (user,
    /// 2026-10-24: "it takes a second or two before it does so it looks like
    /// an error").
    @State private var buyAvailable = BitrefillX402.available
    @State private var buyGroup: BitrefillBuy.Group?
    @State private var buyProduct: BitrefillBuy.Product?
    /// Bitrefill's 25 most popular in the country, read once per visit.
    @State private var popular: [BitrefillBuy.Product] = []
    /// What searches found: a group's seed words, a typed word, a place's name.
    @State private var foundProducts: [BitrefillBuy.Product] = []
    @State private var buyReading = false
    /// The names Casberi already knows you pay: Spending's places,
    /// Subscriptions, what you bought here before.
    @State private var spendNames: [String] = []
    /// After the payment: Bitrefill delivering, said at the foot.
    @State private var delivering = false

    // MARK: - Sweep (prd §1537)

    /// $1 or $5, round-ups' two steps.
    @State private var sweepUnder = DustSweep.under
    /// What on the network is swept and what stays, and why; nil until read.
    @State private var sweepPlan: DustSweep.Plan?
    /// The pools are pricing the plan's sweeps.
    @State private var sweepPricing = false
    /// The swaps Sweep signs, one per swept token, in the plan's order.
    @State private var sweepItems: [Chain.Item] = []
    /// What you took out of this sweep, by token id.
    @State private var sweepLeftOut: Set<String> = []

    private func say(_ text: String, failure: Bool = false, seconds: Double = 3, from: String? = nil) {
        let h = Hint(text: text, failure: failure, from: from)
        withAnimation(DS.Motion.standard) { hint = h }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if hint?.id == h.id { withAnimation(DS.Motion.standard) { hint = nil } }
        }
    }

    /// A service's mark, in place of its name before its own words (§1442n):
    /// Relay's star on its white circle, as its credit draws it.
    @ViewBuilder static func mark(of service: String) -> some View {
        if service == "Bitrefill" {
            Image("brand-bitrefill")
                .resizable()
                .scaledToFill()
                .frame(width: 16, height: 16)
                .clipShape(Circle())
                .accessibilityLabel(Text(verbatim: service))
        } else if service == "Relay" {
            Image("brand-relay")
                .resizable()
                .scaledToFit()
                .frame(width: 10, height: 10)
                .frame(width: 16, height: 16)
                .background(Circle().fill(.white))
                .accessibilityLabel(Text(verbatim: service))
        }
    }

    private func hintText(_ h: Hint) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            if let from = h.from { Self.mark(of: from) }
            Text(verbatim: h.text)
                .dsText(.body17)
                .foregroundStyle(h.failure ? DS.attentionInk : DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .transition(.opacity)
    }

    /// Bumped to shake the To word once: an address that imitates a book entry.
    @State private var shake = 0
    @FocusState private var focus: Field?

    /// The sentence in the past tense, and how it went.
    struct Receipt: Equatable {
        /// One line: its small word for the gutter, and its value.
        struct Line: Equatable {
            var glue: String?
            var text: String
            /// A second sentence starts here: its glue is its verb ("Then
            /// sent"), grey, on a line of its own (prd §1494).
            var starts = false
        }
        let past: String
        let lines: [Line]
        var detail: String
        var link: URL? = nil
        var linkName: String? = nil
        /// Said instead of "View on <name>" when the door is not an explorer.
        var linkTitle: String? = nil
    }
    #if DEBUG
    @State private var drafted = false
    #endif

    // MARK: - What the sentence says

    private var held: [Tokens.Held] { heldBy[network.chainId] ?? [] }
    private var listed: [Tokens.Listed] { listedBy[network.chainId] ?? [] }
    /// Where a token list looks: the picked network, or all of them, the
    /// one holding the most first (§1442a: a token is tapped before a
    /// network as often as after).
    private var lookIn: [Op.Network] { networkPicked ? [network] : networksByWorth }
    /// What For's search looks in: the network a swap arrives on, once
    /// another is picked (prd §1566).
    private var searchedIn: [Op.Network] {
        if open == .buy, verb == .swap, let on = buyOn, on != network { return [on] }
        return lookIn
    }

    /// Read, and nothing anywhere: there is nothing to spend yet. A network
    /// no node answered for is not nothing, so it never says so.
    private var emptyEverywhere: Bool {
        !heldBy.isEmpty && unread.isEmpty && heldBy.values.allSatisfy(\.isEmpty)
    }

    /// Nothing found, because a read failed: the line says which networks
    /// and offers the read again, never "Receive something first".
    private var readFailed: Bool {
        !heldBy.isEmpty && !unread.isEmpty && heldBy.values.allSatisfy(\.isEmpty)
    }

    private var unreadNames: String {
        ListFormatter.localizedString(byJoining: Op.networks.filter { unread.contains($0.chainId) }.map(\.name))
    }

    /// **TOR, NAMED WHEN IT IS WHY (prd §1549, user, on "Couldn't read Base,
    /// Ethereum, and Robinhood": "can't read networks why").** Every read
    /// here leaves by Tor (§1495), so while Tor is still connecting, or could
    /// not, the networks are not what failed and are not named.
    private var readFailedWords: String {
        switch TorStatus.shared.state {
        case .connecting: String(localized: "Connecting to Tor: try again")
        case .failed: String(localized: "Couldn't reach Tor: try again")
        default: String(localized: "Couldn't read \(unreadNames): try again")
        }
    }

    /// What is left of a holding once the transaction's earlier lines are
    /// taken from it.
    private func left(_ h: Tokens.Held) -> String {
        let spent = items.reduce("0") { sum, item in
            switch item {
            case .send(let p) where p.token == h.token: Op.sum(sum, p.amount)
            case .swap(let s) where s.sell == h.token: Op.sum(sum, s.amount)
            default: sum
            }
        }
        return Op.difference(h.units, spent)
    }

    /// The amount in the token's base units, whichever unit it was typed in.
    private var units: String? {
        guard let with else { return nil }
        if inDollars {
            guard let price = with.price else { return nil }
            return Op.baseUnits(dollars: amount, price: price, decimals: with.token.decimals)
        }
        return Op.baseUnits(amount, decimals: with.token.decimals)
    }

    /// More than is left of the token: refused before Add or Swap (§1442c).
    private var over: Bool {
        guard let with, let units, units != "0" else { return false }
        return !Op.atMost(units, left(with))
    }

    /// Several for one (§1442c, user: "otherwise may confuse a user"): once
    /// a swap is kept, every swap in the transaction buys what it buys.
    private var lockedBuy: Op.Token? {
        for item in items { if case .swap(let s) = item { return s.buy } }
        return nil
    }

    /// **A SWAP TO ANOTHER NETWORK (prd §1555, §1566).** The network what
    /// Swap buys arrives on, when Across carries it there: ETH and the
    /// network's dollar arrive as themselves, any other token there is
    /// bought on arrival by its pools. Nil keeps the swap on its own network.
    private var crossTo: Op.Network? {
        guard verb == .swap, let on = buyOn, on != network,
              buy.map({ Self.arrives($0.token, from: network, on: on) }) ?? true else { return nil }
        return on
    }

    /// Whether `token`, a token of `on`, can be what a swap from `from`
    /// buys there: ETH or `on`'s dollar crossing, or any other token bought
    /// on arrival where the account swaps.
    static func arrives(_ token: Op.Token, from: Op.Network, on: Op.Network) -> Bool {
        if let asset = YourAccountAcross.asset(of: token, on: on) {
            return YourAccountAcross.carries(asset, from: from.chainId, to: on.chainId)
        }
        return token.contract != nil && YourAccountSwap.supported(on)
            && YourAccountAcross.carries(.eth, from: from.chainId, to: on.chainId)
    }

    /// What arrives there: a token of that network (USDC on Base arrives as
    /// USDG on Robinhood; prd §1566, anything on its list).
    private var crossBuy: Op.Token? {
        guard crossTo != nil else { return nil }
        return buy?.token
    }

    /// The network `buy` belongs to.
    private var buyHome: Op.Network { buyOn ?? network }

    /// The token Swap buys could arrive on another network: the sentence's
    /// last network then opens "Get <token> on" (prd §1555), never a list
    /// with nothing to pick.
    private var buyCrosses: Bool {
        guard verb == .swap, with != nil, items.isEmpty, buy != nil else { return false }
        return destinations.count > 1
    }

    /// Where a swap's token can arrive from this network: this network
    /// first, then every network of the account's that Across reaches and
    /// that swaps (prd §1566: anything on its list can be bought there).
    private var destinations: [Op.Network] {
        let usable = reach ?? Op.networks
        return [network] + Op.networks.filter { n in
            n != network && usable.contains(n) && YourAccountSwap.supported(n)
                && YourAccountAcross.carries(.eth, from: network.chainId, to: n.chainId)
        }
    }

    /// The same token on another network, as For would list it there: ETH
    /// is ETH, a network's dollar is the other's (USDC → USDG), anything
    /// else the list's own entry of that symbol; nil when it has none.
    private func equivalent(_ token: Op.Token, from: Op.Network, to: Op.Network) -> Tokens.Listed? {
        if token.contract == nil { return Tokens.Listed(token: Op.eth, name: "Ether", onList: true) }
        if token.contract?.lowercased() == from.dollar.lowercased() {
            let d = Op.dollar(on: to)
            return (listedBy[to.chainId] ?? []).first { $0.token == d } ?? Tokens.Listed(token: d, name: d.symbol, onList: true)
        }
        let list = listedBy[to.chainId] ?? []
        return list.first { $0.token.symbol == token.symbol && $0.onList } ?? list.first { $0.token.symbol == token.symbol }
    }

    private var pendingItem: Chain.Item? {
        guard let with, let units, units != "0", !over else { return nil }
        switch verb {
        case .swap:
            guard let buy, let quote, lockedBuy.map({ $0 == buy.token }) ?? true,
                  buyOn == nil || buyOn == network || crossTo != nil else { return nil }
            return .swap(Chain.Swap(network: network, sell: with.token, buy: crossBuy ?? buy.token, amount: units, quote: quote,
                                    to: crossTo))
        case .send:
            // A lookalike no longer blocks the line (prd §1509 item 2, amends
            // §1438b): it warns, and the verb takes a second tap.
            guard let r = resolved, stands(r) else { return nil }
            return .send(Op.Payment(network: network, token: with.token, amount: units, to: r.address, toName: r.name))
        case .receive, .buy, .sweep:
            return nil
        }
    }

    /// The recipient stands for what the field says NOW: a pasted address
    /// is resolved on the next pass, and until then the last person must
    /// not take the line (§1442l).
    private func stands(_ r: Recipient) -> Bool {
        let text = to.trimmingCharacters(in: .whitespacesAndNewlines)
        return WalletWatch.sameAddress(text, r.address) || r.name?.caseInsensitiveCompare(text) == .orderedSame
    }

    private var all: [Chain.Item] { items + (pendingItem.map { [$0] } ?? []) }

    // MARK: - Round-ups (prd §1452)

    /// This send's round-up: the dollars it sends on this network, rounded
    /// up, added to what is counted; nil when round-ups are off or nothing
    /// in it is the dollar.
    private var roundUpPlan: RoundUps.Plan? {
        let setting = RoundUps.setting
        // Moving privately, a network with no pool sets nothing aside (prd §1561).
        guard RoundUps.applies(setting, on: network.chainId), !network.isTest else { return nil }
        let dollar = Op.dollar(on: network)
        let sent: String
        switch verb {
        case .send:
            sent = all.compactMap { item -> String? in
                if case .send(let p) = item, p.token == dollar { return p.amount }
                return nil
            }.reduce("0") { Op.sum($0, $1) }
        case .swap:
            // **A SWAP ROUNDS UP WHAT IT SELLS (prd §1561)**, in dollars, on
            // the network it leaves from; no price or a wrap, no round-up.
            let usd = signing.compactMap { item -> Double? in
                guard case .swap(let s) = item else { return nil }
                return s.quote.wrap == nil ? soldDollars(s) : nil
            }.reduce(0, +)
            sent = RoundUps.soldUnits(usd: usd, wrap: false) ?? "0"
        case .buy:
            // A Buy rounds up its price in the dollar it pays (prd §1561).
            sent = buyPackage.flatMap { Op.baseUnits(BitrefillBuy.Product.valueText($0.price), decimals: 6) } ?? "0"
        default:
            return nil
        }
        guard sent != "0" else { return nil }
        // Into your private balance on Ethereum (prd §1565): its own count,
        // moving together once it reaches the pool's smallest deposit.
        if privateRoundUps {
            return RoundUps.privatePlan(dollarSent: sent, saved: RoundUps.privateSaved(on: network.chainId), step: setting.step,
                                        threshold: RoundUps.privateMoveAt(on: network.chainId, poolMinimum: PrivateMoneyStore.shared.roundUpsMinimum))
        }
        return RoundUps.plan(dollarSent: sent, saved: RoundUps.saved(on: network.chainId), step: setting.step)
    }

    /// Round-ups move into your private balance here (prd §1565): picked,
    /// on Ethereum, with private money on (the kill switch) and your
    /// account its owner.
    private var privateRoundUps: Bool {
        RoundUps.setting.movesPrivately && !network.isTest && network.chainId == RoundUps.ethereumPool
            && PrivateMove.available && PrivateOnEthereum.owner != nil
    }

    /// What this Face ID operation carries into your private balance: the
    /// whole count once it is due, when this act can spend the dollar (a
    /// send of it, a swap selling it), as the buy rides (prd §1545, §1561).
    private var privateRide: String? {
        guard privateRoundUps, RoundUps.carriesBuy(roundUpAct) else { return nil }
        return roundUpPlan?.buy
    }

    /// What rounds up here, for whether its transaction carries the buy.
    private var roundUpAct: RoundUps.Act {
        switch verb {
        case .swap:
            let dollar = Op.dollar(on: network)
            return .swap(sellsDollar: signing.allSatisfy { item in
                if case .swap(let s) = item { return s.sell == dollar }
                return false
            })
        case .buy: return .buy
        default: return .send
        }
    }

    /// The buy this transaction carries: the plan's, when the count reached
    /// it and this act can carry it (prd §1561).
    private var roundUpCarried: Chain.RoundUpBuy? {
        guard !privateRoundUps, RoundUps.carriesBuy(roundUpAct), let units = roundUpPlan?.buy else { return nil }
        return Chain.RoundUpBuy(units: units, target: RoundUps.setting.target)
    }

    /// Whether Relay carries this move (prd §1512, §1539, §1545): a send
    /// whose round-up buys a token on another network now, money arriving
    /// from another network. A round-up on the send's own network is bought
    /// on the exchanges, through Tor like a swap. Relay refuses
    /// every Tor exit, key or no key, so each says it on the foot. A swap and
    /// a sweep go straight to the pools through the account's own node, so
    /// through Tor (measured 2026-10-26), and are not Relay's.
    private var relayCarries: Bool {
        switch verb {
        case .swap, .send: roundUpCarried != nil && !RoundUps.setting.target.onExchanges(from: network.chainId)
        case .receive: elsewhere != nil
        case .buy: false
        case .sweep: false
        }
    }

    /// **THE EXCHANGE THAT DOES IT (prd §1539, user ruling).** "On Uniswap ·
    /// 0.05% pool fee" for one swap, "On Uniswap and Aerodrome" for several
    /// on both: the foot's credit for a swap or a sweep, in Relay's old
    /// place, with no "powered by". The pool fee is in the price.
    ///
    /// A send whose round-up buys on the exchanges (prd §1545) says it the
    /// same way, from the preview's own quote: "On Aerodrome · 0.01% pool fee".
    private var exchangeCredit: String? {
        if verb == .send {
            guard roundUpCarried != nil, let sold = shownPreview?.sold else { return nil }
            return YourAccountSwap.credit(sold.compactMap(\.route))
        }
        guard verb == .swap || verb == .sweep else { return nil }
        // **"THROUGH ACROSS · 0.06% FEE · ABOUT 10 SECONDS" (prd §1555).**
        // A swap to another network: Across's fee, rounded as a pool's is,
        // and its time; under the pool's words when a token is swapped first.
        // "Unwraps WETH · no fee" (prd §1559): one for one through the
        // network's WETH, no pool and no fee but the network's.
        if signing.count == 1, case .swap(let s) = signing[0], let w = s.quote.wrap {
            return YourAccountSwap.words(w)
        }
        for item in signing {
            guard case .swap(let s) = item, let leg = s.quote.across else { continue }
            let across = [YourAccountAcross.words(leg), YourAccountAcross.about(leg.seconds)].compactMap { $0 }.joined(separator: " · ")
            // In the order it happens: the pools here, Across, the pools
            // there (prd §1566: "On Uniswap · 0.05% pool fee on Ethereum").
            return [s.quote.route.map(YourAccountSwap.words), across, YourAccountAcross.arrivalWords(leg)]
                .compactMap { $0 }.joined(separator: "\n")
        }
        let routes = signing.compactMap { item -> YourAccountSwap.Route? in
            if case .swap(let s) = item { return s.quote.route }
            return nil
        }
        return YourAccountSwap.credit(routes)
    }

    /// The small print's word on round-ups: what is counted, or that this
    /// send buys with it.
    private var roundUpPrint: [String] {
        guard let plan = roundUpPlan else { return [] }
        let target = RoundUps.setting.target
        if privateRoundUps {
            if let due = plan.buy {
                let usd = Op.dollars(due, decimals: RoundUps.dollarDecimals, price: 1)
                return privateRide != nil
                    ? [String(localized: "\(Self.money(usd)) of round-ups moves to your private balance")]
                    : [String(localized: "\(Self.money(usd)) of round-ups so far, moved with your next send of \(Op.dollar(on: network).symbol)")]
            }
            let usd = Op.dollars(plan.savedAfter, decimals: RoundUps.dollarDecimals, price: 1)
            return [String(localized: "\(Self.money(usd)) of round-ups so far, for your private balance")]
        }
        // A swap of another token, or a Buy, cannot carry the buy (prd §1561).
        if let buy = plan.buy, !RoundUps.carriesBuy(roundUpAct) {
            let usd = Op.dollars(buy, decimals: RoundUps.dollarDecimals, price: 1)
            return [String(localized: "\(Self.money(usd)) of round-ups so far, bought with your next send of \(Op.dollar(on: network).symbol)")]
        }
        if let buy = plan.buy {
            let usd = Op.dollars(buy, decimals: RoundUps.dollarDecimals, price: 1)
            // The spend limit's key signs this send alone and never buys on
            // the exchanges (prd §1545): the change waits for Face ID.
            if shownPreview?.route == .session, !RoundUps.sessionCarries(target, from: network.chainId) {
                return [String(localized: "\(Self.money(usd)) of round-ups so far, bought with your next Face ID send")]
            }
            return [String(localized: "\(Self.money(usd)) of round-ups buys \(target.symbol) on \(target.network)")]
        }
        let usd = Op.dollars(plan.savedAfter, decimals: RoundUps.dollarDecimals, price: 1)
        return [String(localized: "\(Self.money(usd)) of round-ups so far, \(target.symbol) bought at $5")]
    }

    // MARK: - The page

    var body: some View {
        ZStack {
            accountPage
                .opacity(privateMode == nil && !freshReceive ? 1 : 0)
                .allowsHitTesting(privateMode == nil && !freshReceive)
                .accessibilityHidden(privateMode != nil || freshReceive)
            if freshReceive, privateMode == nil {
                MoveFreshSentence(inTray: inTray, leave: {
                    withAnimation(DS.Motion.standard) { freshReceive = false }
                }) { verbs }
                .transition(.opacity)
            }
            if privateMode != nil {
                MovePrivateSentence(move: privateMove, inTray: inTray, leave: { why in
                    withAnimation(DS.Motion.standard) {
                        privateMode = nil
                        if why == .pickRecipient { open = .to; search = "" }
                    }
                }) { verbs }
                .transition(.opacity)
            }
        }
        .animation(DS.Motion.standard, value: privateMode)
        .animation(DS.Motion.standard, value: freshReceive)
    }

    private var accountPage: some View {
        // The sentence stands at the top and never moves: a blank's choices
        // open under it, down toward the foot (§1442b, user: "it can't extend
        // up and then extend down ... this is just too jittery").
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if rawOpen {
                        rawPage
                            .transition(.opacity)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            sentence
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sentenceHeight = $0 }
                        space(room: geo.size.height)
                            .padding(.top, open == nil ? DS.Space.s6 : DS.Space.s4)
                    }
                }
                .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
                .padding(.top, inTray ? DS.Space.s2 : DS.Space.s6)
                .padding(.bottom, DS.Space.s4)
                .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .topLeading)
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        // While a blank is open the foot steps aside: its verb cannot sign a
        // half-picked sentence, and the list takes its room (§1442a).
        .safeAreaInset(edge: .bottom, spacing: 0) { if open == nil, !rawOpen { foot.transition(.opacity) } }
        .task(id: network.chainId) { await readNetwork() }
        .task {
            // The sentence finishes itself a moment after it lands (§1442j);
            // with Reduce Motion it is simply finished.
            guard fresh, !arrived else { return }
            if reduceMotion { arrived = true; return }
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(DS.Motion.standard) { arrived = true }
            DSHaptic.success()
        }
        .onChange(of: verb) { was, now in
            if fresh { withAnimation(DS.Motion.standard) { fresh = false; arrived = true } }
            if now == .buy { enterBuy() }
            if now == .sweep { enterSweep() }
            // Back from Receive: what was sent meanwhile is spendable.
            if was == .receive { Task { await readHoldings() } }
            // Details stays open across edits of the sentence, and closes
            // when the verb changes (prd §1509).
            details = false
            rawOpen = false
        }
        .onChange(of: scenePhase) { _, now in
            if now == .active, !heldBy.isEmpty { Task { await readHoldings() } }
        }
        // Tor connecting late reads what failed again, unasked (prd §1549).
        .onChange(of: TorStatus.shared.state) { _, now in
            if case .ready = now, !unread.isEmpty { Task { await readHoldings() } }
        }
        .task(id: quoteKey) { await requote() }
        .task(id: crossingWatch?.id) { await watchCrossing() }
        .task(id: sweepKey) { await resweep() }
        .task(id: previewKey) { await repreview() }
        .task(id: checkKey) { await recheck() }
        .task(id: to) { await resolve() }
        .task {
            await readAll()
            #if DEBUG
            draft()
            #endif
            // **THE FIRST BLANK OPENS ITSELF (prd §1534, user: "make sure …
            // that its very easy to use").** Swap and Send landed as a grey
            // sentence and nothing said the words were the controls. With
            // money to spend and nothing picked, what you hold is shown —
            // shown, not chosen (§1438c), and with the keyboard down.
            if open == nil, with == nil, verb == .swap || verb == .send,
               heldBy.values.contains(where: { !$0.isEmpty }) {
                withAnimation(DS.Motion.standard) { open = .with; search = "" }
            }
            // No keyboard on its own: Move is a page, and a keyboard raised
            // on arrival covers the tab bar until it is swiped away (user,
            // 2026-10-19). A tap on the amount, or a token picked, raises it.
        }
    }

    // MARK: - The sentence

    /// **ONE RUNNING SENTENCE (prd §1466, user: "my brain tells me the gutter
    /// is better but my heart tells me the sentence is").** The gutter of
    /// §1442f is gone: the sentence is a flow of CLAUSES at one size — a
    /// number with its token, a small word with the value it introduces —
    /// that never split across a line. A value grows to the right and only
    /// the clauses after it move; a clause that stops fitting hops to the
    /// next line whole, animated. The money is one line of small print
    /// under it, never a column.
    static let clauseGap: CGFloat = 9

    /// A line under the sentence (the numbered kept list, the round-up
    /// rows): its small word inline, then its content, flush left.
    private func row<Value: View>(_ glue: String?, ink: Color = DS.textPrimary,
                                  @ViewBuilder _ value: () -> Value) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            if let glue {
                Text(verbatim: glue)
                    .dsText(.heading17)
                    .foregroundStyle(ink)
            }
            value()
        }
    }

    private var sentence: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            // An arrival's sentence has no verbs until it has finished itself
            // (§1442j): before the account existed none could be tapped.
            if !fresh || arrived {
                verbs
                    .padding(.bottom, DS.Space.s4)
                    .transition(.opacity)
            }
            // What Add kept of the other verb stands under the verbs,
            // numbered, quieter than the sentence being filled (§1442c) —
            // on Receive and Buy; Swap and Send say it as a sentence of
            // its own (prd §1494).
            if receipt == nil, verb == .receive || verb == .buy || verb == .sweep, !keptLines.filter(showsKept).isEmpty {
                kept
                    .padding(.bottom, DS.Space.s4)
            }
            MoveFlow {
                if let receipt {
                    receiptClauses(receipt)
                } else if emptyEverywhere, verb != .receive {
                    MovePhrase(nothingYet, ink: DS.textSecondary)
                } else {
                    switch verb {
                    case .swap:
                        otherSentence
                        swapClauses(lead: thenWord)
                    case .send:
                        otherSentence
                        sendClauses(lead: thenWord)
                    case .receive: receiveClauses
                    case .buy: buyClauses
                    case .sweep: sweepClauses
                    }
                }
            }
            // A clause hops to the next line as one piece, and the hop is a
            // move, never a snap: every change that can re-wrap the flow
            // animates it, typed digits included.
            .animation(DS.Motion.standard, value: layoutKey)
            // Round-ups (prd §1452): the change, then what the whole send
            // comes to with it (user: "needs to be clear that the 5$ is
            // the total tx").
            // The Private switch (prd §1554): off, always, on arrival.
            if verb == .send, receipt == nil, PrivateMove.available {
                MovePrivateSwitch(isOn: Binding(get: { false }, set: { if $0 { goPrivate(.send) } }))
                    .padding(.top, DS.Space.s4)
                    .disabled(stage != nil)
            }
            // Receive's Private switch (prd §1560): off on arrival; on, a
            // fresh address. Your own account's Receive only, never a
            // route from another network or the arrival's sentence.
            if verb == .receive, receipt == nil, elsewhere == nil, !fresh, PrivateMove.freshAvailable {
                MovePrivateSwitch(isOn: Binding(get: { false }, set: { if $0 { goFresh() } }))
                    .padding(.top, DS.Space.s4)
            }
            if verb == .send || verb == .swap || verb == .buy, receipt == nil, let plan = roundUpPlan, plan.change != "0" {
                let change = Op.dollars(plan.change, decimals: RoundUps.dollarDecimals, price: 1)
                row(nil) {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                        Text("Round-up, toward \(RoundUps.setting.target.symbol)")
                            .dsText(.body17).foregroundStyle(DS.textPrimary)
                        Spacer(minLength: 0)
                        Text(verbatim: Self.money(change))
                            .dsText(.body17).foregroundStyle(DS.textSecondary).monospacedDigit()
                    }
                }
                .padding(.top, DS.Space.s3)
                if let sent = soldDollarsTotal {
                    row(nil) {
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                            Text("Total").dsText(.heading17).foregroundStyle(DS.textPrimary)
                            Spacer(minLength: 0)
                            Text(verbatim: Self.money(sent + change))
                                .dsText(.heading17).foregroundStyle(DS.textPrimary).monospacedDigit()
                        }
                    }
                }
            }
        }
        .animation(DS.Motion.standard, value: verb)
        .animation(DS.Motion.standard, value: receipt)
    }

    /// Everything that can change where the flow breaks a line.
    private var layoutKey: String {
        [amount, with?.token.symbol ?? "", buy?.token.symbol ?? "", String(network.chainId),
         String(items.count), String(slot), to, resolved?.name ?? "", inDollars ? "$" : "",
         quote?.buyAmount ?? "", String(reach?.count ?? -1), elsewhere?.token.symbol ?? "",
         buyGroup?.rawValue ?? "", buyProduct?.id ?? ""].joined(separator: "|")
    }

    /// **A SWAP IS A SENTENCE (§1466, amends §1442g's "no and").** What you
    /// sell, joined as a list reads — commas between, "and" before the last
    /// — then "for" what you get, "on" the network.
    @ViewBuilder private func swapClauses(lead: String?) -> some View {
        let order = sellOrder
        ForEach(Array(order.enumerated()), id: \.element) { n, line in
            let join = Self.joiner(n, of: order.count)
            let glue = n == 0 ? lead : join.glue
            switch line {
            case .kept(let id): keptSellClause(id, glue: glue, trail: join.trail, leads: n == 0 && lead != nil)
            case .current: currentSellClauses(glue: glue, trail: join.trail, leads: n == 0 && lead != nil)
            }
        }
        if let on = crossTo {
            // "Swap 0.01 ETH on Ethereum for USDC on Base." (prd §1555): both
            // networks are words, the first the one it leaves.
            MoveClause(glue: String(localized: "on")) { originWord }
            MoveClause(glue: String(localized: "for")) { buyWord }
            MoveClause(glue: String(localized: "on")) { destinationWord(on) }
        } else {
            MoveClause(glue: String(localized: "for")) { buyWord }
            MoveClause(glue: String(localized: "on")) { networkWord }
        }
    }

    /// **A SEND IS THE SAME SENTENCE, PERSON BY PERSON (§1466, amends
    /// §1442h).** Each person's tokens, then "to" them; the next person's
    /// first token follows an "and" of its own.
    @ViewBuilder private func sendClauses(lead: String?) -> some View {
        let groups = sendGroups
        ForEach(Array(groups.enumerated()), id: \.element.id) { g, group in
            ForEach(Array(group.lines.enumerated()), id: \.element) { n, line in
                let join = Self.joiner(n, of: group.lines.count)
                let first = n == 0 && g == 0
                let glue = first ? lead : n == 0 ? String(localized: "and") : join.glue
                switch line {
                case .kept(let id): keptSellClause(id, glue: glue, trail: join.trail, leads: first && lead != nil)
                case .current: currentSellClauses(glue: glue, trail: join.trail, leads: first && lead != nil)
                }
            }
            MoveClause(glue: String(localized: "to")) {
                if group.hasCurrent {
                    toWord
                } else {
                    word(group.name ?? "", ink: DS.pickInk)
                }
            }
        }
        MoveClause(glue: String(localized: "on")) { networkWord }
    }

    /// **A SECOND MOVE IS A SECOND SENTENCE (prd §1494, user: "this should
    /// turn into two separate sentences if someone is adding a second swap
    /// or send").** What Add kept of the other verb reads first, as a
    /// sentence of its own — its verb grey, as the receipt's is — and the
    /// one being filled starts a new line with "Then": "Swap 0.0004 ETH for
    /// ≈ 0.99 USDC. Then send $5 of USDC to ana.eth on Base." The network
    /// is said once, at the end: one transaction is on one network. Hold a
    /// kept line to take it out.
    @ViewBuilder private var otherSentence: some View {
        let pieces = otherPieces
        ForEach(Array(pieces.enumerated()), id: \.offset) { n, piece in
            MoveClause(glue: piece.glue, glueInk: n == 0 ? DS.textSecondary : DS.textPrimary) {
                MoveWord(piece.text + (n == pieces.count - 1 ? "." : ""), ink: DS.textPrimary)
            }
            .contextMenu {
                Button(role: .destructive) {
                    withAnimation(DS.Motion.standard) {
                        items.removeAll { piece.ids.contains($0.id) }
                        slot = min(slot, items.count)
                    }
                    DSHaptic.selection()
                } label: { Label("Remove", systemImage: "trash") }
            }
            .disabled(stage != nil)
            .transition(.opacity.combined(with: .offset(y: -8)))
        }
    }

    /// The other verb's sentence as clauses, so it wraps as this one does:
    /// each token once with its amounts summed, joined as a list reads, then
    /// "for ≈ what comes back" or "to whom". A piece removes its group.
    private var otherPieces: [(glue: String?, text: String, ids: [UUID])] {
        func amount(_ units: String, _ token: Op.Token) -> String { Self.figure(units, decimals: token.decimals) + " " + token.symbol }
        var out: [(glue: String?, text: String, ids: [UUID])] = []
        if verb == .send {
            let swaps = keptSwaps
            let buys = swaps.reduce(into: [Op.Token]()) { if !$0.contains($1.buy) { $0.append($1.buy) } }
            for (b, buyToken) in buys.enumerated() {
                let group = swaps.filter { $0.buy == buyToken }
                let ids = group.map(\.id)
                let sells = group.reduce(into: [Op.Token]()) { if !$0.contains($1.sell) { $0.append($1.sell) } }
                for (n, sell) in sells.enumerated() {
                    let units = group.filter { $0.sell == sell }.reduce("0") { Op.sum($0, $1.amount) }
                    let join = Self.joiner(n, of: sells.count)
                    out.append((n == 0 ? (b == 0 ? String(localized: "Swap") : String(localized: "and")) : join.glue,
                                amount(units, sell) + (join.trail ?? ""), ids))
                }
                let back = group.reduce("0") { Op.sum($0, $1.quote.buyAmount) }
                out.append((String(localized: "for"), "≈ " + amount(back, buyToken), ids))
            }
        } else if verb == .swap {
            let sends = keptSends
            var at = 0
            while at < sends.count {
                let to = sends[at].to
                var end = at
                while end < sends.count, WalletWatch.sameAddress(sends[end].to, to) { end += 1 }
                let group = Array(sends[at..<end])
                let ids = group.map(\.id)
                for (n, p) in group.enumerated() {
                    let join = Self.joiner(n, of: group.count)
                    out.append((n == 0 ? (at == 0 ? String(localized: "Send") : String(localized: "and")) : join.glue,
                                amount(p.amount, p.token) + (join.trail ?? ""), ids))
                }
                out.append((String(localized: "to"), sends[at].toName ?? YourAccount.short(to), ids))
                at = end
            }
        }
        return out
    }

    /// "Then send" or "Then swap", when the other verb's sentence stands
    /// before this one; nil when this is the only sentence.
    private var thenWord: String? {
        let other = verb == .swap ? !keptSends.isEmpty : !keptSwaps.isEmpty
        guard other else { return nil }
        return verb == .swap ? String(localized: "Then swap") : String(localized: "Then send")
    }

    // MARK: - Sweep (prd §1537)

    /// What the sentence says with nothing to spend anywhere.
    private var nothingYet: String {
        switch verb {
        case .swap: String(localized: "Nothing to swap yet.")
        case .buy: String(localized: "Nothing to pay with yet.")
        case .sweep: String(localized: "Nothing to sweep yet.")
        case .send, .receive: String(localized: "Nothing to send yet.")
        }
    }

    /// **SWEEP IS A SENTENCE TOO (prd §1537):** "3 tokens under $1 for
    /// ≈ 0.0004 ETH on Base." The line is round-ups' own menu, $1 or $5; ETH
    /// is what comes back, so it is a word, not a choice; the network is the
    /// sentence's own blank. What is swept and what stays is listed under it.
    @ViewBuilder private var sweepClauses: some View {
        if sweepsNothing {
            // An empty sweep says so, never "Nothing under $1 for ETH",
            // which reads as an order (user: "as in leave nothing?"); the
            // line under it keeps the $1 menu.
            MoveClause { word(String(localized: "Nothing to sweep"), ink: DS.textPrimary) }
            MoveClause(glue: String(localized: "on")) { networkWord }
        } else {
            sweepAmountClauses
        }
    }

    @ViewBuilder private var sweepAmountClauses: some View {
        MoveClause { word(sweepCountWord, ink: DS.textPrimary) }
        MoveClause(glue: String(localized: "under")) {
            sweepUnderMenu { MoveWord("$\(sweepUnder)", ink: DS.pickInk) }
        }
        MoveClause(glue: String(localized: "for")) {
            let back = word(sweepBackWord, ink: DS.textPrimary)
            if sweepPricing {
                // While the pools price it, the word breathes, as Swap's does.
                back.phaseAnimator([1.0, 0.4]) { content, phase in content.opacity(phase) } animation: { _ in .easeInOut(duration: 0.9) }
            } else {
                back
            }
        }
        MoveClause(glue: String(localized: "on")) { networkWord }
    }

    /// The line's menu, $1 or $5: the sentence's word and, on an empty
    /// sweep, the word in the line under it.
    private func sweepUnderMenu<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        Menu {
            Picker(selection: Binding(get: { sweepUnder }, set: { under in
                withAnimation(DS.Motion.standard) { sweepUnder = under }
                DustSweep.under = under
                DSHaptic.selection()
            })) {
                ForEach(DustSweep.choices, id: \.self) { step in Text(verbatim: "$\(step)").tag(step) }
            } label: { EmptyView() }
            .pickerStyle(.inline)
        } label: {
            label().contentTransition(.opacity)
        }
        .disabled(stage != nil)
        .accessibilityLabel(Text("Sweep what is under $\(sweepUnder)"))
    }

    /// The network is read and nothing on it would be swept.
    private var sweepsNothing: Bool {
        guard let plan = sweepPlan else { return false }
        return (sweepPricing ? plan.sweeps.count : sweepItems.count) == 0
    }

    /// "Everything" until the network is read, then what is swept.
    private var sweepCountWord: String {
        guard let plan = sweepPlan else { return String(localized: "Everything") }
        let swept = sweepPricing ? plan.sweeps.count : sweepItems.count
        if swept == 1, let only = plan.sweeps.first { return only.symbol }
        return String(localized: "\(swept) tokens")
    }

    /// "≈ 0.0004 ETH" once the pools have priced it: short here, exact in Details.
    private var sweepBackWord: String {
        let back = sweepBack
        guard !sweepPricing, DustSweep.isPositive(back) else { return Op.eth.symbol }
        return "≈ " + Self.short(back, decimals: Op.eth.decimals) + " " + Op.eth.symbol
    }

    /// The ETH the sweep's quotes return, in wei.
    private var sweepBack: String {
        DustSweep.total(sweepItems.compactMap { if case .swap(let s) = $0 { s.quote.buyAmount } else { nil } })
    }

    /// The network's fee is more than the sweep returns (user: "and yes
    /// ethereum too"): said under the rows, and the verb dims.
    private var sweepFeeNote: String? {
        guard verb == .sweep, !sweepItems.isEmpty, let fee = networkFeeUSD else { return nil }
        let back = ethPrice.flatMap { DustSweep.dollars(sweepBack, decimals: Op.eth.decimals, price: $0) }
        guard !DustSweep.worthSigning(backUSD: back, feeUSD: fee) else { return nil }
        return String(localized: "\(network.name)'s fee, \(Self.money(fee)), is more than this sweep returns")
    }

    /// Under the sentence: each token, swept or staying and why, then the
    /// small print and Details. A swept token's tap leaves it out of this
    /// sweep, and a second tap puts it back; a staying one says why.
    @ViewBuilder private var sweepLine: some View {
        if !networkPicked {
            EmptyView()
        } else if !YourAccountSwap.supported(network) {
            Text("Swaps are not on \(network.name)").dsText(.body17).foregroundStyle(DS.textSecondary)
        } else if let plan = sweepPlan {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                if plan.rows.isEmpty {
                    sweepUnderMenu {
                        Text("No tokens under \(Text(verbatim: "$\(sweepUnder)").foregroundStyle(DS.pickInk))")
                            .dsText(.body17).foregroundStyle(DS.textSecondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(plan.rows) { row in sweepRow(row) }
                    }
                }
                if offersDetails {
                    VStack(alignment: .leading, spacing: 0) {
                        let print = [sweepSoldPrint, swapFeePrint].compactMap { $0 }
                        detailsToggle(Text(verbatim: print.isEmpty ? "" : print.joined(separator: " · ") + " · ")
                            .foregroundStyle(DS.textSecondary))
                        if details { moveDetails }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                if let note = failNote ?? shownPreview?.refusal ?? sweepFeeNote {
                    Text(verbatim: note).dsText(.body17).foregroundStyle(DS.attentionInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if heldBy.isEmpty {
            Text("Reading…").dsText(.body17).foregroundStyle(DS.textSecondary)
        }
    }

    private func sweepRow(_ row: DustSweep.Row) -> some View {
        let h = row.holding
        let worth = h.usd.map { Self.money($0) }
        // A swept token names its exchange (prd §1539): "$0.42 · On Aerodrome".
        let exchange = sweepItems.lazy.compactMap { item -> String? in
            guard case .swap(let s) = item, (s.sell.contract?.lowercased() ?? s.sell.symbol) == h.id else { return nil }
            return s.quote.exchange.map(YourAccountSwap.on)
        }.first
        let swept = [worth, exchange].compactMap { $0 }.joined(separator: " · ")
        return listRow(h.symbol, sub: row.stay.map(Self.sweepWords) ?? (swept.isEmpty ? nil : swept),
                       trailing: row.stay == nil ? nil : worth, mark: h.symbol, dim: row.stay != nil) {
            switch row.stay {
            case nil:
                withAnimation(DS.Motion.standard) { _ = sweepLeftOut.insert(h.id) }
                DSHaptic.selection()
            case .leftOut:
                withAnimation(DS.Motion.standard) { _ = sweepLeftOut.remove(h.id) }
                DSHaptic.selection()
            case .some(let stay):
                say(Self.sweepWhy(stay, h.symbol))
            }
        }
        .disabled(stage != nil)
        .accessibilityHint(row.stay == nil ? Text("Leaves it out of this sweep")
                           : row.stay == .leftOut ? Text("Puts it back in this sweep") : Text("Says why it stays"))
    }

    /// Why a token stays, in the row's grey line.
    static func sweepWords(_ stay: DustSweep.Stay) -> String {
        switch stay {
        case .noPrice: String(localized: "No price")
        case .notVerified: String(localized: "Not on Uniswap's list")
        case .roundUps: String(localized: "Holds your round-ups")
        case .nextSweep: String(localized: "In the next sweep")
        case .noRoute: String(localized: "No pool trades it")
        case .costsMore: String(localized: "Costs more than it returns")
        case .leftOut: String(localized: "Left out")
        }
    }

    /// The same, said in full when the row is tapped.
    static func sweepWhy(_ stay: DustSweep.Stay, _ symbol: String) -> String {
        switch stay {
        case .noPrice: String(localized: "Nothing prices \(symbol), so nothing says it is under the line")
        case .notVerified: String(localized: "\(symbol) is not on Uniswap's list, and selling it would run its own contract")
        case .roundUps: String(localized: "Your round-ups wait in \(symbol) until they buy")
        case .nextSweep: String(localized: "Ten tokens a sweep: \(symbol) goes in the next one")
        case .noRoute: String(localized: "No pool here trades \(symbol) for ETH")
        case .costsMore: String(localized: "The pools would pay back less than half of what \(symbol) is worth")
        case .leftOut: String(localized: "Tap to put \(symbol) back")
        }
    }

    /// What the sweep sells, in dollars, for the small print.
    private var sweepSoldPrint: String? {
        guard let plan = sweepPlan else { return nil }
        let ids = Set(sweepItems.compactMap { item -> String? in
            if case .swap(let s) = item { return s.sell.contract?.lowercased() ?? s.sell.symbol }
            return nil
        })
        let usd = plan.sweeps.filter { ids.contains($0.id) }.compactMap(\.usd).reduce(0, +)
        return usd > 0 ? String(localized: "\(Self.money(usd)) in all") : nil
    }

    /// Face ID's words for a sweep: what it sells and what it buys.
    private func sweepFaceIDWords(_ batch: [Chain.Item]) -> String {
        batch.count == 1 ? faceIDWords(batch) : String(localized: "Sweep \(batch.count) tokens into ETH")
    }

    /// Sweep opens on the network list when none is picked (§1534's first
    /// blank, applied): a sweep is one network's.
    private func enterSweep() {
        details = false
        if !networkPicked, !heldBy.isEmpty {
            withAnimation(DS.Motion.standard) { open = .network; search = "" }
        }
    }

    /// The sweep is read again whenever what it would take changes.
    private var sweepKey: String {
        guard verb == .sweep, networkPicked, receipt == nil, let held = heldBy[network.chainId] else { return "" }
        let holds = held.map { "\($0.id)=\($0.units)" }.sorted().joined(separator: ",")
        return [String(network.chainId), String(sweepUnder), sweepLeftOut.sorted().joined(separator: ","), holds,
                String(listedBy[network.chainId]?.count ?? 0)].joined(separator: "|")
    }

    /// What is under the line, sorted by `DustSweep.plan`, then priced off
    /// the pools one token at a time, all at once, and judged: a token with
    /// no pool, or whose ETH is worth less than half of it, stays.
    private func resweep() async {
        let key = sweepKey
        guard !key.isEmpty else {
            sweepPlan = nil
            sweepItems = []
            sweepPricing = false
            return
        }
        let net = network
        let held = heldBy[net.chainId] ?? []
        guard YourAccountSwap.supported(net) else {
            sweepPlan = DustSweep.Plan(sweeps: [], stays: [])
            sweepItems = []
            sweepPricing = false
            return
        }
        let listed = listedBy[net.chainId] ?? []
        let bought = Set(Tokens.remembered(on: net).compactMap { $0.contract?.lowercased() })
        let dollar = Op.dollar(on: net).contract?.lowercased()
        let holdings = held.map { h -> DustSweep.Holding in
            let contract = h.token.contract?.lowercased()
            let isDollar = contract != nil && contract == dollar
            // On Uniswap's list, or a swap here bought it; the dollar is the account's own.
            let boughtHere = contract.map { bought.contains($0) } ?? false
            let verified = listed.contains { $0.onList && $0.id == h.id }
            return DustSweep.Holding(symbol: h.token.symbol, contract: h.token.contract, decimals: h.token.decimals,
                                     units: h.units, usd: h.usd, trusted: isDollar || boughtHere || verified,
                                     isDollar: isDollar)
        }
        let waiting = RoundUps.setting.on && DustSweep.isPositive(RoundUps.saved(on: net.chainId))
        let plan = DustSweep.plan(holdings, under: sweepUnder, roundUpsWaiting: waiting, leftOut: sweepLeftOut)
        withAnimation(DS.Motion.standard) {
            sweepPlan = plan
            sweepItems = []
            sweepPricing = !plan.sweeps.isEmpty
        }
        guard !plan.sweeps.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        let tokens = Dictionary(held.map { ($0.id, $0.token) }, uniquingKeysWith: { first, _ in first })
        let owner = account
        var quotes: [String: YourAccountSwap.Quote] = [:]
        await withTaskGroup(of: (String, YourAccountSwap.Quote?).self) { group in
            for h in plan.sweeps {
                guard let token = tokens[h.id] else { continue }
                let units = h.units, id = h.id
                group.addTask { @MainActor in
                    let q = try? await Chain.swapQuote(net, sell: token, buy: Op.eth, amount: units, account: owner)
                    return (id, q)
                }
            }
            for await (id, q) in group { if let q { quotes[id] = q } }
        }
        guard !Task.isCancelled, key == sweepKey else { return }
        let judged = DustSweep.judged(plan, back: { quotes[$0]?.buyAmount }, ethPrice: ethPrice)
        let swaps: [Chain.Item] = judged.sweeps.compactMap { h in
            guard let token = tokens[h.id], let q = quotes[h.id] else { return nil }
            return .swap(Chain.Swap(network: net, sell: token, buy: Op.eth, amount: h.units, quote: q))
        }
        withAnimation(DS.Motion.standard) {
            sweepPlan = judged
            sweepItems = swaps
            sweepPricing = false
        }
        #if DEBUG
        NSLog("moveSweep| %@ under=$%d swept=%d stays=%d", net.name, sweepUnder, swaps.count, judged.stays.count)
        for row in judged.rows {
            NSLog("moveSweep| %@ | %@ | %@", row.holding.symbol, row.holding.usd.map { Self.money($0) } ?? "-",
                  row.stay.map(Self.sweepWords) ?? "swept")
        }
        #endif
    }

    @ViewBuilder private var receiveClauses: some View {
        // A route taken is the sentence (prd §1470), even on an account just made.
        if let route = elsewhere {
            // **FROM ANOTHER NETWORK (prd §1453, user: "for z1 we wouldn't say
            // 'send' we would say 'receive'").** The tab says Receive, as
            // Send's amount stands with no word before it: the token leads.
            MoveClause {
                Button {
                    withAnimation(DS.Motion.standard) { open = .elsewhereCoin }
                    DSHaptic.selection()
                } label: { word(route.token.symbol, ink: DS.pickInk) }
                    .buttonStyle(RowPress())
                    .accessibilityHint(Text("Picks what they send"))
            }
            // Where the sender's money is (user: "'on' arbitrum would be better").
            MoveClause(glue: String(localized: "on")) {
                Button {
                    withAnimation(DS.Motion.standard) { open = .elsewhere }
                    DSHaptic.selection()
                } label: { word(route.from.name, ink: DS.pickInk) }
                    .buttonStyle(RowPress())
            }
            // What arrives is your pick (prd §1470): Relay swaps on the way.
            MoveClause(glue: String(localized: "as")) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Button {
                        withAnimation(DS.Motion.standard) { open = .arrives }
                        DSHaptic.selection()
                    } label: { word(route.arrives.symbol, ink: DS.pickInk) }
                        .buttonStyle(RowPress())
                        .accessibilityHint(Text("Picks what you receive"))
                    word(String(localized: "on \(route.to.name)."), ink: DS.textPrimary)
                }
            }
        } else if fresh {
            MoveClause {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    word(arrived ? String(localized: "Ready") : String(localized: "Your account"),
                         ink: arrived ? DS.textSecondary : DS.textPrimary)
                    if arrived {
                        // Never a copy without its network (prd §1488): the
                        // address opens the network list, and a pick there
                        // ends the arrival on Receive's own sentence.
                        Button {
                            withAnimation(DS.Motion.standard) { open = .elsewhere }
                            DSHaptic.selection()
                        } label: { word(YourAccount.short(account), ink: DS.textPrimary) }
                            .buttonStyle(RowPress())
                            .accessibilityLabel(Text("Your address, \(account)"))
                            .accessibilityHint(Text("Pick a network first"))
                            .transition(.asymmetric(insertion: .offset(y: 28).combined(with: .opacity), removal: .opacity))
                    }
                }
            }
            reachClauses
        } else {
            // **THE NETWORK IS PICKED, ALWAYS (prd §1486, user: "your address
            // is the same on other EVM chains … we should have them pick the
            // chain no matter what").** Until it is, the address is a word,
            // not a copy: a tap asks for the network first.
            MoveClause(glue: String(localized: "at")) {
                Button {
                    if networkPicked { copy() } else {
                        withAnimation(DS.Motion.standard) { open = .elsewhere }
                        DSHaptic.selection()
                    }
                } label: { word(YourAccount.short(account), ink: networkPicked ? DS.pickInk : DS.textPrimary) }
                    .buttonStyle(RowPress())
                    .accessibilityLabel(Text("Your address, \(account)"))
                    .accessibilityHint(networkPicked ? Text("Copies your address") : Text("Pick a network first"))
            }
            MoveClause(glue: String(localized: "on")) { receiveNetworkWord }
        }
    }

    /// Receive's one blank (prd §1486): the list it opens is your own
    /// networks, then every network Relay takes deposits on.
    private var receiveNetworkWord: some View {
        Group {
            if networkPicked {
                blank(network.name + ".", ink: DS.pickInk, .elsewhere, label: Text("On \(network.name), change"))
            } else {
                blank(String(localized: "network."), ink: DS.textTertiary, .elsewhere, label: Text("Pick a network"))
            }
        }
    }

    /// Where this phone can receive (§1442k): only the networks it can use
    /// the account on, as clauses so the line wraps between them.
    @ViewBuilder private var reachClauses: some View {
        if let reach {
            MovePhrase(YourAccountReach.words(reach), glue: String(localized: "on"), ink: DS.textPrimary)
        } else {
            MoveClause(glue: String(localized: "on")) { word("…", ink: DS.textTertiary) }
        }
    }

    /// "Swapped 0.004 USDC for 12.3 AERO on Base." — the verb rolls to the
    /// past, the ≈ resolves to what was paid out. The receipt in the
    /// sentence's own grammar (§1442l, §1466): the past tense leads the
    /// first clause, grey; every value white.
    @ViewBuilder private func receiptClauses(_ r: Receipt) -> some View {
        ForEach(Array(r.lines.enumerated()), id: \.offset) { n, line in
            MovePhrase(line.text, glue: n == 0 ? r.past : line.glue,
                       glueInk: n == 0 || line.starts ? DS.textSecondary : DS.textPrimary, ink: DS.textPrimary,
                       breaks: line.starts)
                .transition(.opacity.combined(with: .offset(y: 8)))
        }
    }

    /// **THE SENTENCE'S ONE SIZE (prd §1501).** Every word of every Move
    /// sentence, and of the create flow, wears it; nothing picks another.
    static let rung: DSTextStyle = .heading52
    /// The space between a phrase's words, as a share of the size: Figtree's
    /// own space advance (measured 0.231em, Figtree Bold).
    static let wordSpace: CGFloat = 0.231

    /// A quote's figure for the sentence: three significant figures, whole
    /// above a hundred — "24.9 USDC", "0.00104 ETH", "1,235 USDC". The ≈ and
    /// the exact figure are the print line's (§1479), so the sentence's
    /// clauses stay short.
    static func short(_ units: String, decimals: Int) -> String {
        let v = Double(Op.display(units, decimals: decimals, places: min(decimals, 12))) ?? 0
        if v == 0 { return "0" }
        if v >= 100 { return v.formatted(.number.precision(.fractionLength(0))) }
        return v.formatted(.number.precision(.significantDigits(1...3)))
    }

    private func word(_ text: String, ink: Color) -> some View {
        MoveWord(text, ink: ink)
    }

    /// A word that opens its choices under the sentence.
    private func blank(_ text: String, ink: Color, _ which: Blank, label: Text) -> some View {
        Button {
            // One transaction is one network: with lines kept, the word says
            // so rather than doing nothing (prd §83).
            if which == .network, !items.isEmpty {
                say(String(localized: "One transaction is one network. Sign this one first"))
                return
            }
            if which == .destination, !items.isEmpty {
                say(String(localized: "A swap to another network goes alone"))
                return
            }
            if which == .buy, lockedBuy != nil {
                say(String(localized: "One token for the whole swap"))
                return
            }
            // A token tapped before a network opens the tokens of every
            // network, each row naming its own; picking one picks both
            // (§1442a, user: "i clicked token and network came up").
            withAnimation(DS.Motion.standard) {
                if open == which { open = nil } else {
                    open = which
                    search = ""
                    // To opens on the whole book, the person above first
                    // ("Same as above", §1442h): what the line carried is a
                    // choice there, not a filter.
                    if which == .to {
                        to = ""
                        resolved = nil
                    }
                    // Every list opens with the keyboard down, so it has the
                    // room to the foot; its search row raises the keys (§1442b).
                    focus = nil
                }
            }
            DSHaptic.selection()
        } label: {
            word(text, ink: open == which ? DS.pickInk.opacity(0.6) : ink)
        }
        .buttonStyle(RowPress())
        .disabled(stage != nil)
        .accessibilityLabel(label)
        // A pick rises into its blank from the list under it (§1438b).
        .transition(.asymmetric(insertion: .offset(y: 28).combined(with: .opacity), removal: .opacity))
    }

    // MARK: - The receipt (§1442g)

    enum SellLine: Hashable { case kept(UUID), current }

    private var keptSwaps: [Chain.Swap] {
        items.compactMap { if case .swap(let s) = $0 { s } else { nil } }
    }

    private var keptSends: [Op.Payment] {
        items.compactMap { if case .send(let p) = $0 { p } else { nil } }
    }

    /// The numbered kept lines show only the other verb's: this verb's are
    /// the receipt's own lines.
    private func showsKept(_ line: (id: String, words: String, ids: [UUID])) -> Bool {
        switch verb {
        case .swap: line.id.hasPrefix("to|")
        case .send: line.id.hasPrefix("for|")
        case .receive, .buy, .sweep: true
        }
    }

    /// The kept swaps in order, the line being filled at its slot.
    private var sellOrder: [SellLine] {
        var lines = keptSwaps.map { SellLine.kept($0.id) }
        lines.insert(.current, at: min(slot, lines.count))
        return lines
    }

    /// One person's part of a send: their lines, in order, together.
    struct SendGroup: Identifiable {
        let id: String
        var lines: [SellLine]
        let address: String?
        let name: String?
        var hasCurrent: Bool
    }

    /// The send's lines, the one being filled at its slot, gathered into
    /// runs that go to the same address (§1442h). The line being filled
    /// joins the run before it when it goes to the same person; a new
    /// person, or none yet, starts a group of its own.
    private var sendGroups: [SendGroup] {
        let sends = keptSends
        var order = sends.map { SellLine.kept($0.id) }
        order.insert(.current, at: min(slot, order.count))
        var groups: [SendGroup] = []
        for line in order {
            let address: String?
            let name: String?
            switch line {
            case .kept(let id):
                guard let p = sends.first(where: { $0.id == id }) else { continue }
                address = p.to.lowercased()
                name = p.toName ?? YourAccount.short(p.to)
            case .current:
                address = resolved?.address.lowercased()
                name = nil
            }
            if let last = groups.last, let address, last.address == address {
                groups[groups.count - 1].lines.append(line)
                if line == .current { groups[groups.count - 1].hasCurrent = true }
            } else {
                let key: String
                switch line {
                case .kept(let id): key = id.uuidString
                case .current: key = "current"
                }
                groups.append(SendGroup(id: key, lines: [line], address: address, name: name, hasCurrent: line == .current))
            }
        }
        return groups
    }

    private func dollars(of group: SendGroup) -> Double? {
        let parts: [Double] = group.lines.compactMap { line in
            switch line {
            case .kept(let id): keptSends.first { $0.id == id }.flatMap(sentDollars)
            case .current: currentDollars
            }
        }
        let sum = parts.reduce(0, +)
        return sum > 0 ? sum : nil
    }

    private func sentDollars(_ p: Op.Payment) -> Double? {
        price(of: p.token).map { Op.dollars(p.amount, decimals: p.token.decimals, price: $0) }
    }

    /// How many people a send goes to, once it is more than one.
    private var peopleCount: Int {
        Set(sendGroups.compactMap(\.address)).count
    }

    private func price(of token: Op.Token) -> Double? {
        held.first { $0.token == token }?.price
    }

    private func soldDollars(_ s: Chain.Swap) -> Double? {
        price(of: s.sell).map { Op.dollars(s.amount, decimals: s.sell.decimals, price: $0) }
    }

    private var currentDollars: Double? {
        guard let with, let units, let p = with.price else { return nil }
        return Op.dollars(units, decimals: with.token.decimals, price: p)
    }

    /// What the whole swap sells, or the whole send sends, in dollars: the
    /// receipt's total.
    private var soldDollarsTotal: Double? {
        let kept = verb == .send ? keptSends.compactMap(sentDollars) : keptSwaps.compactMap(soldDollars)
        let parts = kept + (currentDollars.map { [$0] } ?? [])
        let sum = parts.reduce(0, +)
        return sum > 0 ? sum : nil
    }

    /// What the whole swap buys: every kept quote plus the line being filled.
    private var buyTotal: String? {
        let amounts = keptSwaps.map(\.quote.buyAmount) + (quote.map { [$0.buyAmount] } ?? [])
        guard !amounts.isEmpty else { return nil }
        return amounts.reduce("0") { Op.sum($0, $1) }
    }

    /// How a list reads inside a sentence: a comma after each but the last
    /// two, "and" before the last.
    static func joiner(_ n: Int, of count: Int) -> (glue: String?, trail: String?) {
        (count > 1 && n == count - 1 ? String(localized: "and") : nil,
         count > 2 && n < count - 2 ? "," : nil)
    }

    /// The line being filled: the amount with its token, one clause; typed
    /// in dollars, "of <token>" is the clause after it.
    @ViewBuilder private func currentSellClauses(glue: String?, trail: String?, leads: Bool = false) -> some View {
        MoveClause(glue: glue, glueInk: leads ? DS.textSecondary : DS.textPrimary, trail: inDollars ? nil : trail) {
            // The figure and its token wrap between them when the two are
            // wider than a line ("1234567.89" over "USDC"), never truncate.
            MoveClauseLayout(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    if inDollars { word("$", ink: amount.isEmpty ? DS.textTertiary : DS.pickInk) }
                    amountField
                }
                if !inDollars { withWord }
            }
            .contentShape(Rectangle())
            .onTapGesture { if stage == nil { focus = .amount } }
            .dsCardLead(Text("Edits the amount")) { if stage == nil { focus = .amount } }
        }
        .layoutValue(key: FlowBreak.self, value: leads)
        if inDollars {
            MoveClause(glue: String(localized: "of"), trail: trail) { withWord }
        }
    }

    /// A kept line: tap it to edit it in place, hold it to remove it.
    @ViewBuilder private func keptSellClause(_ id: UUID, glue: String?, trail: String?, leads: Bool = false) -> some View {
        let line: (amount: String, token: Op.Token)? = {
            if let s = keptSwaps.first(where: { $0.id == id }) { return (s.amount, s.sell) }
            if let p = keptSends.first(where: { $0.id == id }) { return (p.amount, p.token) }
            return nil
        }()
        if let s = line {
            MoveClause(glue: glue, glueInk: leads ? DS.textSecondary : DS.textPrimary, trail: trail) {
                word(Self.figure(s.amount, decimals: s.token.decimals) + " " + s.token.symbol, ink: DS.pickInk)
            }
            .layoutValue(key: FlowBreak.self, value: leads)
            .contentShape(Rectangle())
            .onTapGesture { edit(id) }
            .contextMenu {
                Button(role: .destructive) { remove(id) } label: { Label("Remove", systemImage: "trash") }
            }
            .accessibilityElement(children: .combine)
            .dsCardLead(Text("Edits this line")) { edit(id) }
            .accessibilityAction(named: Text("Remove")) { remove(id) }
            .transition(.opacity.combined(with: .offset(y: -8)))
        }
    }

    /// A kept line tapped: it becomes the line being filled, where it stands;
    /// a finished line that was being filled is kept in its place.
    private func edit(_ id: UUID) {
        guard stage == nil, let at = items.firstIndex(where: { $0.id == id }) else { return }
        let token: Op.Token, units: String
        switch items[at] {
        case .swap(let s): token = s.sell; units = s.amount
        case .send(let p): token = p.token; units = p.amount
        }
        let sent: Op.Payment? = { if case .send(let p) = items[at] { return p } else { return nil } }()
        withAnimation(DS.Motion.standard) {
            var index = at
            if let pending = pendingItem {
                let into = min(slot, items.count)
                items.insert(pending, at: into)
                if into <= index { index += 1 }
            }
            items.remove(at: index)
            slot = index
            if let h = held.first(where: { $0.token == token }) { with = h }
            inDollars = false
            amount = Op.display(units, decimals: token.decimals, places: token.decimals)
            // A sent line carries its person back into the sentence.
            if let sent {
                to = sent.toName ?? sent.to
                resolved = Recipient(address: sent.to, name: sent.toName, imitates: nil)
            }
            open = nil
        }
        DSHaptic.selection()
        focus = .amount
    }

    private func remove(_ id: UUID) {
        guard stage == nil, let at = items.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(DS.Motion.standard) {
            items.remove(at: at)
            if slot > at { slot -= 1 }
        }
        DSHaptic.selection()
    }

    /// The three verbs on their own line, the picked one bright (user:
    /// "send swap receive should be its own line user chooses which"). The
    /// sentence under it is what that verb does.
    private var verbs: some View {
        // Five verbs outgrow a phone's line at this spacing (prd §1537): the
        // gap narrows first, and past that the whole line shrinks evenly to
        // the width, its one rung kept — never a scroll, never a clip, never
        // a size of its own (prd §1558, user: "no scrolling", "we don't want
        // to hand roll sizes").
        ViewThatFits(in: .horizontal) {
            verbRow(spacing: DS.Space.s4)
            verbRow(spacing: DS.Space.s3)
            ScaledToWidth { verbRow(spacing: DS.Space.s2) }
        }
        .frame(minHeight: 44, alignment: .leading)
    }

    private func verbRow(spacing: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            // A–Z in the reader's language (prd §1547); Swap stays the
            // verb Move opens on, wherever it stands in the line.
            ForEach(Verb.allCases.filter { $0 != .buy || buyAvailable }
                .sorted { title($0).localizedStandardCompare(title($1)) == .orderedAscending }, id: \.self) { v in
                Button {
                    guard v != verb || receipt != nil || privateMode != nil || freshReceive else { return }
                    withAnimation(DS.Motion.standard) {
                        privateMode = nil
                        freshReceive = false
                        verb = v
                        open = nil
                        receipt = nil
                    }
                    DSHaptic.selection()
                } label: {
                    // A step under the sentence's floor (§1479): the verbs
                    // name what the sentence does, they are not the sentence.
                    Text(verbatim: title(v))
                        .dsText(.heading24)
                        .foregroundStyle(v == verb ? DS.textPrimary
                                         : v == .receive && emptyEverywhere ? DS.pickInk : DS.textTertiary)
                }
                .buttonStyle(RowPress())
                .disabled(stage != nil || privateMove.acting)
                .accessibilityAddTraits(v == verb ? [.isSelected] : [])
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func title(_ v: Verb) -> String {
        switch v {
        case .swap: String(localized: "Swap")
        case .send: String(localized: "Send")
        case .receive: String(localized: "Receive")
        case .buy: String(localized: "Buy")
        case .sweep: String(localized: "Sweep")
        }
    }

    private var amountField: some View {
        let typing = focus == .amount
        return MoveRungReader { rung in
            TextField(text: $amount, prompt: Text(verbatim: "0").foregroundStyle(DS.textTertiary)) { Text(verbatim: "0") }
            .keyboardType(.decimalPad)
            .focused($focus, equals: .amount)
            .dsText(rung)
            // The field is as wide as the figure drawn over it, so its
            // digits are the figure's: proportional "100" under a
            // monospaced one ate the gap before the token ("100USDC").
            .monospacedDigit()
            // Not typing, the figure is drawn over the field so its digits
            // roll as the slider moves (§1438b); the field still takes the tap.
            .foregroundStyle(typing || amount.isEmpty ? DS.pickInk : .clear)
            .overlay(alignment: .leading) {
                if !typing, !amount.isEmpty {
                    Text(verbatim: amount)
                        .dsText(rung)
                        .foregroundStyle(DS.pickInk)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .fixedSize()
                        .allowsHitTesting(false)
                }
            }
            .fixedSize()
        }
            .disabled(stage != nil)
            .accessibilityLabel(Text(inDollars ? "Amount in dollars" : "Amount"))
            .onChange(of: amount) { _, now in
                if open != nil, focus == .amount { open = nil }
                // Dollars take cents; a token takes as many places as it has.
                let places = inDollars ? 2 : (with?.token.decimals ?? 18)
                if let dot = now.firstIndex(where: { $0 == "." || $0 == "," }),
                   now.distance(from: dot, to: now.endIndex) - 1 > places {
                    amount = String(now[...now.index(dot, offsetBy: places)])
                }
            }
    }

    private var withWord: some View {
        blank(with?.token.symbol ?? String(localized: "token"), ink: with == nil ? DS.textTertiary : DS.pickInk,
              .with, label: Text("Spend \(with?.token.symbol ?? ""), change"))
    }

    @ViewBuilder private var buyWord: some View {
        if let buy {
            // Short in the sentence, the ≈ and the exact figure in the
            // print (§1479), so the clause stays whole at the biggest rung.
            let back = buyTotal.map { Self.short($0, decimals: buy.token.decimals) + " " }
            // The whole swap's result, pink like every value; locked by a
            // kept swap (§1442c), a tap says so (§1442g).
            let symbol = crossBuy?.symbol ?? buy.token.symbol
            let word = blank((back ?? "") + symbol, ink: DS.pickInk,
                             .buy, label: Text("For \(symbol), change"))
            if pricing {
                // While the pools price it, the word breathes: working, not stuck.
                word.phaseAnimator([1.0, 0.4]) { content, phase in content.opacity(phase) } animation: { _ in .easeInOut(duration: 0.9) }
            } else {
                word
            }
        } else {
            blank(String(localized: "token"), ink: DS.textTertiary, .buy, label: Text("Pick what you want"))
        }
    }

    /// A swap is being priced: everything is there but the pools' answer.
    private var pricing: Bool {
        verb == .swap && buy != nil && units != nil && !over && quote == nil && quoteNote == nil
    }

    private var toWord: some View {
        let shown = resolved?.name ?? (resolved.map { YourAccount.short($0.address) })
            ?? (to.isEmpty ? String(localized: "address")
                : to.contains(where: { ".@ ".contains($0) }) ? to : AddressTail.short(to))   // a pasted address waits as its tail (§1553)
        return blank(shown, ink: toWarningInk ?? (resolved?.imitates != nil ? DS.attentionInk : resolved == nil ? DS.textTertiary : DS.pickInk),
                  .to, label: Text("To \(shown), change"))
                // A look-alike shakes once: a refusal you feel.
                .keyframeAnimator(initialValue: 0.0, trigger: shake) { content, x in
                    content.offset(x: x)
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(-10, duration: 0.06)
                        LinearKeyframe(10, duration: 0.08)
                        LinearKeyframe(-6, duration: 0.08)
                        LinearKeyframe(6, duration: 0.08)
                        LinearKeyframe(0, duration: 0.06)
                    }
                }
    }

    private var networkWord: some View {
        Group {
            if networkPicked, buyCrosses {
                // The token could arrive elsewhere: its network is a choice
                // of where it arrives (prd §1555).
                blank(network.name + ".", ink: DS.pickInk, .destination, label: Text("Get it on \(network.name), change"))
            } else if networkPicked {
                blank(network.name + ".", ink: DS.pickInk, .network, label: Text("On \(network.name), change"))
            } else {
                blank(String(localized: "network."), ink: DS.textTertiary, .network, label: Text("Pick a network"))
            }
        }
    }

    /// The network a swap to another network leaves (prd §1555).
    private var originWord: some View {
        blank(network.name, ink: DS.pickInk, .network, label: Text("From \(network.name), change"))
    }

    /// The network it arrives on: opens "Get <token> on".
    private func destinationWord(_ on: Op.Network) -> some View {
        blank(on.name + ".", ink: DS.pickInk, .destination, label: Text("Get it on \(on.name), change"))
    }

    /// A token list's search, its first row: the sentence's word never turns
    /// into a field, so the line never reflows (§1442b).
    private func searchRow(for which: Blank) -> some View {
        HStack(spacing: DS.Space.s3) {
            Image(systemName: "magnifyingglass")
                .dsGlyph(.body, weight: .medium)
                .foregroundStyle(DS.textSecondary)
                .frame(width: DS.Face.list)
                .accessibilityHidden(true)
            if which == .to {
                // To opens like a token list (§1442b, §1442h): keyboard down,
                // the book in reach, and this row for a name, an ENS name or
                // an address; Done takes what resolved.
                TextField(String(localized: "Name, ENS or address"), text: $to)
                    .focused($focus, equals: .to)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { if resolved != nil { pick {} } }
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
            } else {
                // A contract pasted here is read off each network
                // (`lookUpPasted`), so the field says so and the list keeps no
                // paste row at its foot (prd §1533, user: "inside search bar
                // say search or paste").
                TextField(open == .buy || open == .arrives
                          ? String(localized: "Search or paste an address")
                          : String(localized: "Search"), text: $search)
                    .focused($focus, equals: .search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .task(id: search) { await lookUpPasted() }
            }
        }
        .frame(minHeight: DSFeed.headHeight)
        .padding(.horizontal, DS.Space.s4)
    }

    // MARK: - The space under it

    /// The sentence's own height, so the list under it takes what is left.
    @State private var sentenceHeight: CGFloat = 0

    /// Under the sentence: the line, or a blank's choices. One box for every
    /// blank, the same size whichever is open, its lists crossfading inside
    /// it — so moving between blanks moves nothing (§1442a, user: "it is very
    /// jittery. needs to be stable"). Line and box overlap while they swap,
    /// rather than stacking for the length of the animation.
    private func space(room: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if let open {
                choices(room: choicesRoom(room), searches: open == .with || open == .buy || open == .to || open == .arrives || open == .merchant, which: open) {
                    ZStack(alignment: .topLeading) {
                        Group {
                            switch open {
                            case .with: withList
                            case .buy: buyList
                            case .to: toList
                            case .network: networkList
                            case .destination: destinationList
                            case .elsewhere: elsewhereList
                            case .elsewhereCoin: elsewhereCoinList
                            case .arrives: arrivesList
                            case .group: groupList
                            case .merchant: merchantList
                            }
                        }
                        .id(open)
                        .transition(.opacity)
                    }
                }
                // The box rises into the space and fades as its pick lands.
                .transition(.asymmetric(insertion: .offset(y: 24).combined(with: .opacity), removal: .opacity))
            } else {
                line
                    .transition(.opacity)
            }
        }
    }

    /// Everything under the sentence, down to the foot (or the keys).
    private func choicesRoom(_ room: CGFloat) -> CGFloat {
        max(140, room - sentenceHeight - DS.Space.s4 * 2 - (inTray ? DS.Space.s2 : DS.Space.s6))
    }

    /// The rows' own height, so a short list draws a short box (§1442b).
    @State private var rowsHeight: CGFloat = 0

    /// A blank's choices on their own glass, the rooms tray's card (§1203):
    /// a layer that floats for a moment, so glass, while the sentence stays
    /// bare. As tall as its rows, up to the room under the sentence, then
    /// they scroll inside it. It grows downward only: the sentence above
    /// never moves (§1442b). A token list leads with its search.
    private func choices<Rows: View>(room: CGFloat, searches: Bool, which: Blank,
                                     @ViewBuilder _ rows: () -> Rows) -> some View {
        let head: CGFloat = searches ? 52 : 0
        return VStack(alignment: .leading, spacing: 0) {
            if let hint {
                hintText(hint)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s3)
            }
            if searches { searchRow(for: which) }
            ScrollView {
                rows()
                    .padding(.vertical, DS.Space.s2)
                    .padding(.horizontal, DS.Space.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowsHeight = $0 }
            }
            .scrollIndicators(.hidden)
            .frame(height: max(56, min(rowsHeight, room - head)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsGlass(cornerRadius: RoomsTray.radius)
    }

    /// The other unit (tap to type in it), what you have, the fee.
    @ViewBuilder private var line: some View {
        if let hint {
            hintText(hint)
        } else if let receipt {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if !receipt.detail.isEmpty {
                    Text(verbatim: receipt.detail).dsText(.body17).foregroundStyle(DS.textSecondary)
                }
                if let link = receipt.link, let name = receipt.linkName {
                    Button { openURL(link) } label: {
                        Text(verbatim: receipt.linkTitle ?? String(localized: "View on \(name)")).dsText(.body17).foregroundStyle(DS.pickInk).frame(minHeight: 44)
                    }
                    .buttonStyle(RowPress())
                }
            }
        } else if emptyEverywhere, verb != .receive {
            Button {
                withAnimation(DS.Motion.standard) { verb = .receive }
                DSHaptic.selection()
            } label: {
                Text("Receive something first").dsText(.body17).foregroundStyle(DS.pickInk).frame(minHeight: 44)
            }
            .buttonStyle(RowPress())
        } else if readFailed, verb != .receive {
            Button {
                DSHaptic.selection()
                Task { await readHoldings() }
            } label: {
                Text(verbatim: readFailedWords).dsText(.body17).foregroundStyle(DS.pickInk).frame(minHeight: 44)
            }
            .buttonStyle(RowPress())
        } else if verb == .sweep {
            sweepLine
        } else if verb == .receive {
            // **RECEIVE (§1442i, user: "when we show 'at' show …xxxx or complete
            // address. and somewhere on the page complete address should be
            // displayed. also with a copy button").** The sentence says
            // "…9f12"; the whole address stands here, readable, and the
            // foot's Copy address copies it (prd §1518). No exchange door: it
            // only copied and opened Coinbase (prd §1484). One column: `line`
            // stands in `space`'s ZStack, so two siblings here would draw
            // over each other.
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                if let route = elsewhere {
                    VStack(alignment: .leading, spacing: DS.Space.s3) {
                        Text(verbatim: route.address)
                            .dsText(.mono12)
                            .foregroundStyle(DS.textSecondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        // A wrong token sent here can be lost, so the line names
                        // the one it takes; a swap on the way is said (§83), since
                        // what lands is set by the price when it lands.
                        Text(Self.elsewhereLine(route))
                            .dsText(.body17).foregroundStyle(DS.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if !fresh, !networkPicked {
                    // No address under the sentence until its network is picked
                    // (prd §1486); a route Relay refused still says why.
                    if let elsewhereFinding {
                        Text(verbatim: elsewhereFinding).dsText(.body17).foregroundStyle(DS.attentionInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    VStack(alignment: .leading, spacing: DS.Space.s3) {
                        // The arrival names no one network, so it shows no address to
                        // copy (prd §1488).
                        if !fresh {
                            Text(verbatim: account)
                                .dsText(.mono12)
                                .foregroundStyle(DS.textSecondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            // The network the sentence names (prd §1486).
                            Text("Any coin on \(network.name).")
                                .dsText(.body17).foregroundStyle(DS.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        // Never an address the account cannot follow (§1442k); once a
                        // network is picked, the list offered only the ones it can.
                        if let reach, !YourAccountReach.isAll(reach), fresh || reach.isEmpty {
                            Text(reach.isEmpty
                                 ? "Not on any network from this \(ThisDevice.name) yet."
                                 : "Send to it only on \(reach.map(\.name).formatted(.list(type: .or))).")
                                .dsText(.body17).foregroundStyle(DS.attentionInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if fresh, arrived, emptyEverywhere {
                            Text("Nothing in it yet.")
                                .dsText(.body17).foregroundStyle(DS.textSecondary)
                                .transition(.opacity)
                        }
                        if let elsewhereFinding {
                            Text(verbatim: elsewhereFinding).dsText(.body17).foregroundStyle(DS.attentionInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                // **FROM ANOTHER WALLET (prd §1506):** a wallet of your own
                // elsewhere sends it all here, each send approved there — §1484's
                // bar, the transaction filled, never an address to paste. It needs
                // no network picked, so it stands from the first moment; the
                // demo's other wallet is made up too, and nothing connects.
                if elsewhere == nil {
                    DSDoorRow(icon: "arrow.down.left", label: "From another wallet") {
                        ReceiveFromWalletSheet.present(account: account, sample: YourAccountDemo.isDemo(account))
                    }
                }
            }
        } else if let warning = leadWarning {
            // A warning takes the grey line's place (prd §1509 item 2): red
            // when reported or refused, amber to check; one line, and Details
            // lists every finding. A refusal dims the verb (canvas figure 9).
            VStack(alignment: .leading, spacing: 0) {
                detailsToggle(Text(verbatim: warningLine(warning) + " ")
                    .foregroundStyle(warning.red ? DS.destructiveInk : DS.attentionInk))
                if details { moveDetails }
            }
            .fixedSize(horizontal: false, vertical: true)
        } else if let note = lineNote {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                if note == quoteNote, let quoteFrom { Self.mark(of: quoteFrom) }
                Text(verbatim: note).dsText(.body17).foregroundStyle(DS.attentionInk)
            }
        } else if let with {
            // One line of small print (§1442f): the other unit and the fee.
            // The exchange's credit is the foot's, and the slider, the amount's own
            // control, stands under it here rather than stranded at the foot.
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                // Swapping, the other unit is the receipt's column; the fee is
                // the whole swap's (§1442g).
                let print: [String] = switch verb {
                case .swap: [soldPrint, quotePrint, swapFeePrint].compactMap { $0 } + roundUpPrint
                case .send: [soldPrint].compactMap { $0 } + (peopleCount > 1 ? [String(localized: "To \(peopleCount) people")] : []) + roundUpPrint
                    + [sendFeePrint].compactMap { $0 }
                case .receive, .sweep: []
                case .buy: buyPrint + roundUpPrint
                }
                // "$25.00 · Fee up to $0.01 · Details" (prd §1509): the last
                // word opens this exact operation under the line.
                if offersDetails {
                    VStack(alignment: .leading, spacing: 0) {
                        detailsToggle(Text(verbatim: print.isEmpty ? "" : print.joined(separator: " · ") + " · ")
                            .foregroundStyle(DS.textSecondary))
                        if details { moveDetails }
                    }
                } else if !print.isEmpty {
                    Text(verbatim: print.joined(separator: " · "))
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                }
                // A test network says so wherever it is picked (prd §1439).
                if network.isTest {
                    Text("test coins").dsText(.body17).foregroundStyle(DS.attentionInk)
                }
                // The slider and the $ · token switch work on the line being
                // filled, so they share a row under the sentence (§1442g).
                if verb != .receive, receipt == nil {
                    HStack(spacing: DS.Space.s4) {
                        DSShareSlider(percent: shareBinding(with), enabled: stage == nil)
                        unitSwitch
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        } else if !networkPicked {
            EmptyView()
        } else if heldBy.isEmpty {
            Text("Reading…").dsText(.body17).foregroundStyle(DS.textSecondary)
        } else if held.isEmpty, unread.contains(network.chainId) {
            Text("Couldn't read \(network.name)").dsText(.body17).foregroundStyle(DS.attentionInk)
        } else if held.isEmpty {
            Text("Nothing on \(network.name) yet").dsText(.body17).foregroundStyle(DS.textSecondary)
        }
    }

    private var lineNote: String? {
        if verb != .receive, over { return String(localized: "More than you have") }
        if verb == .swap, let quoteNote { return quoteNote }
        if verb == .send {
            if malformed { return String(localized: "Check the address") }
        }
        // What signing would refuse, said before the tap: a fee the account
        // cannot pay, a node that would not price it (prd §1509).
        if verb == .send || verb == .swap, let refusal = shownPreview?.refusal { return refusal }
        return nil
    }

    // MARK: - Details (prd §1509)

    /// The preview of the sentence as it stands now; nil while it is read.
    private var shownPreview: Chain.Preview? {
        !previewKey.isEmpty && previewFor == previewKey ? preview : nil
    }

    /// Details is offered once there is a transaction to show.
    private var offersDetails: Bool { (verb == .send || verb == .swap || verb == .sweep) && !signing.isEmpty }

    /// What the foot's verb signs: the sentence's lines, or Sweep's swaps.
    private var signing: [Chain.Item] { verb == .sweep ? sweepItems : all }

    /// The red line when this exact operation would fail.
    private var failNote: String? {
        guard verb == .send || verb == .swap || verb == .sweep, let p = shownPreview else { return nil }
        return YourAccountPreview.failLine(p.checked, swap: verb != .send, network: network.name)
    }

    // MARK: - Warnings (prd §1509 item 2, §1513)

    /// The addresses the sentence pays: each send's, and the one being typed.
    private var recipients: [String] {
        guard verb == .send else { return [] }
        var out = keptSends.map(\.to)
        if let r = resolved, !YourAccountDemo.isYours(r.address) { out.append(r.address) }
        return out.reduce(into: [String]()) { list, a in if !list.contains(where: { WalletWatch.sameAddress($0, a) }) { list.append(a) } }
    }

    /// What the sentence is checked for: its recipients, or a swap's token.
    private var checkKey: String {
        guard verb == .send || verb == .swap, receipt == nil else { return "" }
        let token = verb == .swap ? buy.map { "\($0.token.contract ?? "eth")|\($0.onList)" } : nil
        guard !recipients.isEmpty || token != nil else { return "" }
        return ([account, String(network.chainId), token ?? "-"] + recipients.map { $0.lowercased() }).joined(separator: ";")
    }

    /// The findings for the sentence as it stands, the simulation's refusal first.
    private var shownFindings: [MoveWarnings.Finding] {
        var all = !checkKey.isEmpty && findingsFor == checkKey ? findings : []
        if let fail = failNote { all.append(.fails(fail)) }
        return MoveWarnings.ordered(all)
    }

    private var leadWarning: MoveWarnings.Finding? { shownFindings.first }

    private func warningLine(_ f: MoveWarnings.Finding) -> String {
        MoveWarnings.line(f, short: { YourAccountPreview.short(EIP55.checksum($0)) },
                          day: { $0.formatted(.dateTime.month(.abbreviated).day()) })
    }

    /// The To word takes the colour of a warning about who it is.
    private var toWarningInk: Color? {
        guard let lead = leadWarning else { return nil }
        switch lead {
        case .scam, .sanctioned: return DS.destructiveInk
        case .lookalike, .firstSend: return DS.attentionInk
        case .contract(let token, _, _, _): return token ? nil : DS.attentionInk
        case .fails: return nil
        }
    }

    /// "Send anyway" stands while a warning that arms it is on screen.
    private var warned: Bool { MoveWarnings.arms(shownFindings) }
    /// The whole sentence and its warning: an edit of the amount or the
    /// token after the first tap asks for the first tap again.
    private var armKey: String { previewKey + "|" + checkKey + "|" + (leadWarning.map(warningLine) ?? "") }

    /// Look the sentence's addresses and token up, a moment after it
    /// settles: history and OFAC on the phone, GoPlus and Blockscout through
    /// Tor. The demo's come off its table.
    private func recheck() async {
        let key = checkKey
        guard !key.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(YourAccountDemo.isDemo(account) ? 100 : 400))
        guard !Task.isCancelled else { return }
        let net = network
        let to = recipients
        let token = verb == .swap ? buy : nil
        var found: [MoveWarnings.Finding] = []
        var with: [String] = []
        let sanctions = MoveChecks.sanctions()
        if let sanctions {
            with.append(String(localized: "OFAC's sanctions list, \(sanctions.date.formatted(.dateTime.month(.abbreviated).day().year()))"))
            for a in to + [token?.token.contract].compactMap({ $0 }) where sanctions.addresses.contains(a.lowercased()) {
                found.append(.sanctioned(address: a, listed: sanctions.date))
            }
        }
        if YourAccountDemo.isDemo(account) {
            let demo = YourAccountDemo.findings(to: to, token: token)
            found += demo.findings
            with += demo.checkedWith
        } else {
            let sent = MoveChecks.sentTo(account, context: context)
            let named = MoveChecks.named()
            let own = Set([account.lowercased()] + [YourAccountKey.address?.lowercased()].compactMap { $0 })
            for a in to where !MoveWarnings.isKnown(a, sentTo: sent, named: Set(named.keys), own: own) {
                found.append(MoveWarnings.imitated(a, sentTo: sent, named: named, own: own,
                                                   looksLike: AddressSafety.isLookalike) ?? .firstSend)
            }
            // Both services, for every address at once: each is a Tor round
            // trip of a second or more (measured).
            let asked = to + [token?.token.contract].compactMap { $0 }
            var reports: [String: MoveWarnings.Report?] = [:]
            var made: [String: MoveWarnings.Creation?] = [:]
            await withTaskGroup(of: (String, MoveWarnings.Report?, MoveWarnings.Creation?).self) { group in
                for a in asked {
                    group.addTask {
                        async let r = MoveChecks.report(a, chainId: net.chainId)
                        async let c = MoveChecks.creation(a, chainId: net.chainId)
                        return (a, await r, await c)
                    }
                }
                for await (a, r, c) in group { reports[a] = r; made[a] = c }
            }
            let answered = asked.allSatisfy { reports[$0] ?? nil != nil }
            for a in to {
                if let r = reports[a] ?? nil, r.reported { found.append(.scam(address: a, sources: r.sources)) }
                if case .at(let when)? = made[a] ?? nil {
                    found.append(.contract(token: false, unverified: false, ageDays: MoveWarnings.ageDays(when, now: .now),
                                           neverUsed: sent[a.lowercased()] == nil))
                }
            }
            if let token, let contract = token.token.contract {
                if let r = reports[contract] ?? nil, r.reported { found.append(.scam(address: contract, sources: r.sources)) }
                var age: Int?
                if case .at(let when)? = made[contract] ?? nil { age = MoveWarnings.ageDays(when, now: .now) }
                found.append(.contract(token: true, unverified: !token.onList, ageDays: age,
                                       neverUsed: !held.contains { $0.token == token.token }
                                           && !MoveChecks.used(token.token.symbol, by: account, context: context)))
            }
            // Said only when GoPlus was asked something (§83).
            if !asked.isEmpty {
                with.append(answered ? String(localized: "GoPlus's reports (SlowMist, ScamSniffer)") : String(localized: "GoPlus did not answer: not checked"))
            }
        }
        // A contract finding that says nothing is no finding.
        found.removeAll { if case .contract(let t, let u, let d, let n) = $0 {
            MoveWarnings.contractLine(token: t, unverified: u, ageDays: d, neverUsed: n) == nil } else { false } }
        guard !Task.isCancelled, key == checkKey else { return }
        let lookedAlike = found.contains { if case .lookalike = $0 { true } else { false } }
        let wasAlike = findings.contains { if case .lookalike = $0 { true } else { false } } && findingsFor == key
        withAnimation(DS.Motion.standard) { findings = found; checkedWith = with; findingsFor = key }
        // A lookalike shakes the To word once (§1438b, kept).
        // A book name's lookalike already shook as it resolved.
        if lookedAlike, !wasAlike, resolved?.imitates == nil { shake += 1; DSHaptic.failure() }
        #if DEBUG
        if let probe = UserDefaults.standard.string(forKey: "moveWarnProbe"), !probe.isEmpty {
            NSLog("moveWarn| %@ | %@ | verb=%@ | findings=%d | with=%@", probe, leadWarning.map(warningLine) ?? "-",
                  footVerb, shownFindings.count, checkedWith.joined(separator: "; "))
        }
        #endif
    }

    /// The grey line ending in Details, a chevron after it; the whole line
    /// opens it, and a second tap closes it.
    private func detailsToggle(_ lead: Text) -> some View {
        Button {
            withAnimation(DS.Motion.standard) { details.toggle() }
            DSHaptic.selection()
        } label: {
            (lead + Text("Details").foregroundStyle(DS.textPrimary) + Text(verbatim: " ")
                + Text(Image(systemName: details ? "chevron.up" : "chevron.down")).foregroundStyle(DS.textPrimary))
                .dsText(.body17)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .accessibilityHint(details ? Text("Hides the details") : Text("Shows what this transaction does"))
    }

    private var moveDetails: some View {
        let sends = signing.compactMap { item -> String? in if case .send(let p) = item { p.to } else { nil } }
        let to = sends.reduce(into: [String]()) { list, a in if !list.contains(where: { WalletWatch.sameAddress($0, a) }) { list.append(a) } }
        return MoveDetails(preview: shownPreview, swap: verb != .send, to: to, account: account,
                           networkFeeUSD: networkFeeUSD,
                           warnings: shownFindings.map { (warningLine($0), $0.red) }, checkedWith: checkedWith) {
            withAnimation(DS.Motion.standard) { rawOpen = true }
            DSHaptic.selection()
        }
    }

    private var rawPage: some View {
        MoveRawPage(raw: shownPreview?.raw, refusal: shownPreview?.refusal) {
            withAnimation(DS.Motion.standard) { rawOpen = false }
            DSHaptic.selection()
        }
    }

    /// ETH's price for the fee: the Wallet's, read with the holdings.
    private var ethPrice: Double? {
        if YourAccountDemo.isDemo(account) { return YourAccountDemo.price(Op.eth) }
        return heldBy.values.joined().first { $0.token == Op.eth && $0.price != nil }?.price
    }

    /// The network fee's ceiling in dollars.
    private var networkFeeUSD: Double? {
        guard let wei = shownPreview?.feeWei, let price = ethPrice else { return nil }
        return Op.dollars(wei, decimals: 18, price: price)
    }

    /// A send's fee: "Fee up to $0.01", "Fee under a cent".
    private var sendFeePrint: String? {
        guard let wei = shownPreview?.feeWei else { return nil }
        return YourAccountPreview.feePhrase(usd: networkFeeUSD, wei: wei, money: Self.money)
    }

    /// A swap's fee is the network's alone (prd §1539): the pool's fee is in
    /// the price, and nobody stands between to charge another.
    private var swapFeePrint: String? {
        guard let wei = shownPreview?.feeWei else { return nil }
        return YourAccountPreview.feePhrase(usd: networkFeeUSD, wei: wei, money: Self.money)
    }

    /// The sentence the preview is of: its lines' contents, never their
    /// ids (the line being filled is a new value every read), the network
    /// and a round-up's buy.
    private var previewKey: String {
        guard verb == .send || verb == .swap || verb == .sweep, receipt == nil, !signing.isEmpty else { return "" }
        let lines = signing.map { item -> String in
            switch item {
            case .send(let p): "s|\(p.token.contract ?? "eth")|\(p.amount)|\(p.to.lowercased())"
            case .swap(let s): "w|\(s.sell.contract ?? "eth")|\(s.buy.contract ?? "eth")|\(s.amount)|\(s.to?.chainId ?? 0)"
            }
        }
        return ([account, String(network.chainId), roundUpCarried?.units ?? "-"] + lines).joined(separator: ";")
    }

    /// Ask for the preview once the sentence settles, then again every 40
    /// seconds while it stands, so the operation kept for signing is never
    /// older than `Chain.Prepared.lifetime`: what Raw transaction shows is
    /// what Face ID signs.
    private func repreview() async {
        let key = previewKey
        guard !key.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(YourAccountDemo.isDemo(account) ? 150 : 700))
        while !Task.isCancelled {
            if stage != nil {
                try? await Task.sleep(for: .seconds(2))
                continue
            }
            let roundUp = roundUpCarried
            let p = await Chain.preview(signing, account: account, roundUp: roundUp)
            guard !Task.isCancelled, key == previewKey else { return }
            withAnimation(DS.Motion.standard) { preview = p; previewFor = key }
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "moveRawProbe") { Self.logRaw(p) }
            #endif
            if YourAccountDemo.isDemo(account) { return }
            try? await Task.sleep(for: .seconds(40))
        }
    }

    /// What the line being filled is worth in its other unit, or, once a
    /// second line stands, what the whole sentence sells: the money is one
    /// line of small print, never a column (§1466, amends §1442g item 2).
    private var soldPrint: String? {
        let lines = (verb == .send ? keptSends.count : keptSwaps.count) + (units == nil ? 0 : 1)
        if lines > 1, let total = soldDollarsTotal { return String(localized: "\(Self.money(total)) in all") }
        guard let with, units != nil else { return nil }
        return otherUnit(with)
    }

    /// The quote exactly, with its ≈: "≈ 24.86 USDC" (§1479). The sentence
    /// says "24.9 USDC"; this is where the places went.
    private var quotePrint: String? {
        guard let buy, let back = buyTotal else { return nil }
        // To another network the token is the one that arrives there, and
        // Across pays exactly what it quoted: no ≈ (prd §1556).
        let token = crossBuy ?? buy.token
        // So does a wrap or an unwrap: one for one (prd §1559). A swap on
        // arrival is a pool's quote again, with its ≈ (prd §1566).
        let exact = quote?.across.map { $0.swap == nil } == true || quote?.wrap != nil
        return (exact ? "" : "≈ ") + Self.figure(back, decimals: token.decimals) + " " + token.symbol
    }

    /// "$0.004", or "0.004 USDC" when dollars are typed. nil when the token
    /// has no price, so there is nothing to flip to.
    private func otherUnit(_ h: Tokens.Held) -> String? {
        guard let price = h.price else { return nil }
        if inDollars {
            let u = units ?? "0"
            return Self.figure(u, decimals: h.token.decimals) + " " + h.token.symbol
        }
        return Self.money(Op.dollars(units ?? "0", decimals: h.token.decimals, price: price))
    }

    /// **$ · ETH (§1442d, user: "a user needs to be able to change token
    /// value from tokens to dollars ... something i do frequently in one
    /// transaction").** Two choices at the end of the amount line, the one
    /// typed in selected; the other converts the figure, keeping its value.
    /// Drawn once a token is picked: before that there is nothing to convert
    /// to, and a lone "$" would be a control that does nothing (§83).
    @ViewBuilder private var unitSwitch: some View {
        if let with, verb != .receive {
            HStack(spacing: DS.Space.s1) {
                unitChip("$", on: inDollars, label: Text("Type in dollars")) { setDollars(true, with) }
                unitChip(with.token.symbol, on: !inDollars, label: Text("Type in \(with.token.symbol)")) { setDollars(false, with) }
            }
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 8 }
        }
    }

    private func unitChip(_ text: String, on: Bool, label: Text, act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Chip(text: text, selected: on)
        }
        .buttonStyle(PressSpring())
        .disabled(stage != nil)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private func setDollars(_ dollars: Bool, _ h: Tokens.Held) {
        guard dollars != inDollars else { return }
        guard h.price != nil else {
            say(String(localized: "No dollar price for \(h.token.symbol)"))
            return
        }
        withAnimation(DS.Motion.standard) { flipUnit(h) }
        DSHaptic.selection()
    }

    /// The figure a flip replaced and the figure it wrote, so flipping back
    /// with nothing typed between returns exactly what was there: cents
    /// round, and $24.50 must not come back as 0.009998 ETH (§1442d).
    @State private var flipped: (before: String, after: String, token: String)?

    private func flipUnit(_ h: Tokens.Held) {
        guard let price = h.price else { return }
        let current = units
        let before = amount
        inDollars.toggle()
        if let f = flipped, f.after == amount, f.token == h.id {
            amount = f.before
            flipped = nil
            return
        }
        guard let current else { amount = ""; return }
        amount = inDollars
            ? String(format: "%.2f", Op.dollars(current, decimals: h.token.decimals, price: price))
            : Op.display(current, decimals: h.token.decimals, places: min(h.token.decimals, 8))
        flipped = (before, amount, h.id)
    }

    /// A token figure for the sentence: whole above a thousand, two places
    /// above one, four significant figures under it — so "≈ 28.96 AERO" fits
    /// the line (§1442a). Face ID and the receipt's link say the exact units.
    static func figure(_ units: String, decimals: Int) -> String {
        let v = Double(Op.display(units, decimals: decimals, places: min(decimals, 12))) ?? 0
        if v == 0 { return "0" }
        if v >= 1_000 { return v.formatted(.number.precision(.fractionLength(0))) }
        if v >= 1 { return v.formatted(.number.precision(.fractionLength(0...2))) }
        return v.formatted(.number.precision(.significantDigits(1...4)))
    }

    /// Dollars, with cents; under a cent, two significant figures.
    static func money(_ usd: Double) -> String {
        let text: String
        if usd >= 0.01 || usd == 0 {
            text = usd.formatted(.currency(code: "USD"))
        } else {
            text = "$" + usd.formatted(.number.precision(.significantDigits(2)))
        }
        return BalancePrivacy.shared.value(text)
    }

    // MARK: - The choices

    private func listRow(_ title: String, sub: String? = nil, trailing: String? = nil,
                         mark: String? = nil, image: String? = nil, brand: String? = nil,
                         remote: String? = nil, symbol: String? = nil, face: String? = nil, dim: Bool = false,
                         act: @escaping () -> Void) -> some View {
        Button(action: act) {
            HStack(spacing: DS.Space.s3) {
                if let face {
                    // A person: the face the Wallet draws for that address
                    // (its ENS avatar, else its tinted mark), never initials
                    // or an empty column (prd §1534).
                    WalletFace(address: face, size: DS.Face.list, circular: true)
                        .accessibilityHidden(true)
                } else if let brand {
                    // An app's or a company's own mark (`BridgeIcon`), not a
                    // token's (`AssetMark` reads token art only, prd §1481).
                    BridgeIcon(name: brand, size: DS.Face.list, circular: true)
                        .accessibilityHidden(true)
                } else if let image {
                    Image(image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: DS.Face.list, height: DS.Face.list)
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                } else if let remote {
                    // A picture the read named (Relay's network icon), over
                    // the letters until it lands (prd §1534).
                    RemoteAssetMark(urlString: remote, size: DS.Face.list,
                                    monogram: String((mark ?? title).prefix(2)).uppercased())
                } else if let symbol {
                    // A glyph for what has no logo of its own (Buy's
                    // categories, a person with no face, prd §1534).
                    Circle().fill(DS.fillStrong)
                        .frame(width: DS.Face.list, height: DS.Face.list)
                        .overlay(Image(systemName: symbol).dsGlyph(.body, weight: .semibold)
                            .foregroundStyle(DS.textSecondary))
                        .accessibilityHidden(true)
                } else if let mark {
                    AssetMark(name: mark, size: DS.Face.list)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(1)
                    if let sub { Text(verbatim: sub).dsText(.subhead12).foregroundStyle(DS.textSecondary).lineLimit(1) }
                }
                Spacer(minLength: DS.Space.s2)
                if let trailing {
                    Text(verbatim: trailing).dsText(.body17).foregroundStyle(DS.textSecondary).monospacedDigit()
                }
            }
            .frame(minHeight: DSFeed.headHeight)
            .contentShape(Rectangle())
            .opacity(dim ? 0.55 : 1)
        }
        .buttonStyle(RowPress())
    }

    private var withList: some View {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let rows: [(key: String, net: Op.Network, held: Tokens.Held)] = lookIn.flatMap { n in
            (heldBy[n.chainId] ?? []).map { ("\(n.chainId)|\($0.id)", n, $0) }
        }
        .filter { q.isEmpty || $0.held.token.symbol.lowercased().hasPrefix(q) }
        // What the whole swap buys is never also what it sells.
        .filter { row in lockedBuy.map { row.held.token != $0 || verb != .swap } ?? true }
        // Buy pays in USDC on Base, the one way Bitrefill's door takes (§1473).
        .filter { row in verb != .buy || Self.paysBuy(row.held, on: row.net) }
        // Biggest first, whichever network it is on.
        .sorted { ($0.held.usd ?? -1) > ($1.held.usd ?? -1) }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(rows, id: \.key) { row in
                let h = row.held
                let worth = h.usd.map { Self.money($0) }
                listRow(h.token.symbol,
                        sub: networkPicked ? worth : [worth, row.net.name].compactMap { $0 }.joined(separator: " · "),
                        trailing: Op.spoken(left(h), decimals: h.token.decimals), mark: h.token.symbol) {
                    pick {
                        if !networkPicked || row.net != network { switchNetwork(row.net) }
                        choose(h)
                    }
                }
            }
            if rows.isEmpty {
                Text(verbatim: heldBy.isEmpty ? String(localized: "Reading…")
                     : !q.isEmpty ? String(localized: "You have no \(search.trimmingCharacters(in: .whitespaces).uppercased())")
                     : networkPicked && unread.contains(network.chainId) ? String(localized: "Couldn't read \(network.name)")
                     : networkPicked ? String(localized: "Nothing on \(network.name) yet")
                     : String(localized: "Nothing to spend yet"))
                    .dsText(.body17).foregroundStyle(DS.textSecondary).frame(minHeight: 44)
            }
        }
    }

    /// A token For offers unasked (prd §1532): verified, and a stablecoin or
    /// one we have a mark for — the artwork `AssetMark` draws, or the icon
    /// book's picture (which the demo never draws).
    private func majorToken(_ l: Tokens.Listed) -> Bool {
        Tokens.major(l) { symbol in
            AssetMark.hasAsset(symbol) || (!DemoMode.isActive && TokenIconBook.url(for: symbol) != nil)
        }
    }

    /// What For offers, on the picked network or on each, a network's head
    /// of five when none is picked and nothing is typed.
    private var buyRows: [(key: String, net: Op.Network, listed: Tokens.Listed)] {
        let typed = !search.trimmingCharacters(in: .whitespaces).isEmpty
        var out: [(key: String, net: Op.Network, listed: Tokens.Listed)] = []
        var seen: Set<String> = []
        // Another network picked (prd §1566): its own list, what can arrive there.
        if verb == .swap, let on = buyOn, on != network {
            let pool = (typed ? (found[on.chainId] ?? []) : []) + (listedBy[on.chainId] ?? [])
            var rows = Tokens.matches(search, in: pool, held: heldBy[on.chainId] ?? [], shows: majorToken)
            if let p = pasted[on.chainId], !rows.contains(where: { $0.id == p.id }) { rows.insert(p, at: 0) }
            // Never its WETH: ETH is ETH there (prd §1559).
            let weth = YourAccountSwap.book(on.chainId)?.weth
            for l in rows where Self.arrives(l.token, from: network, on: on) && l.token.contract?.lowercased() != weth {
                let key = "\(on.chainId)|\(l.id)"
                if seen.insert(key).inserted { out.append((key, on, l)) }
            }
            return out
        }
        for n in lookIn {
            let pool = (typed ? (found[n.chainId] ?? []) : []) + (listedBy[n.chainId] ?? [])
            var rows = Tokens.matches(search, in: pool, held: heldBy[n.chainId] ?? [], shows: majorToken)
            if let p = pasted[n.chainId], !rows.contains(where: { $0.id == p.id }) { rows.insert(p, at: 0) }
            if !networkPicked, !typed { rows = Array(rows.prefix(5)) }
            for l in rows where !(n == network && networkPicked && l.token == with?.token) {
                let key = "\(n.chainId)|\(l.id)"
                if seen.insert(key).inserted { out.append((key, n, l)) }
            }
        }
        return out
    }

    private var buyList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(buyRows, id: \.key) { row in
                let l = row.listed
                let mine = (heldBy[row.net.chainId] ?? []).first { $0.id == l.id }
                let about = l.onList ? (l.name == l.token.symbol ? nil : l.name) : String(localized: "Not on Uniswap's list")
                listRow(l.token.symbol,
                        sub: networkPicked ? about : [about, row.net.name].compactMap { $0 }.joined(separator: " · "),
                        trailing: mine.map { Op.spoken($0.units, decimals: $0.token.decimals) },
                        mark: l.token.symbol, dim: !l.onList) {
                    pick {
                        // A token of the network it arrives on keeps the one it leaves (prd §1566).
                        if row.net != buyHome || !networkPicked { switchNetwork(row.net) }
                        buy = l
                    }
                    if amount.isEmpty { focus = .amount }
                }
            }
            if networkPicked, !YourAccountSwap.supported(network) {
                Text("Swaps are not on \(network.name)").dsText(.body17).foregroundStyle(DS.textSecondary).frame(minHeight: 44)
            }
        }
        // The list of the network it arrives on, read once (prd §1566).
        .task(id: buyOn?.chainId) {
            if let on = buyOn, listedBy[on.chainId] == nil { listedBy[on.chainId] = await Tokens.list(on) }
        }
    }

    private var toList: some View {
        let q = to.trimmingCharacters(in: .whitespaces).lowercased()
        let book = AddressBook.shared.all.filter { e in
            ENS.isHexAddress(e.address) && (q.isEmpty || e.name.lowercased().contains(q) || e.address.lowercased().hasPrefix(q))
        }
        // The person the line above goes to leads, said so (§1442h).
        let above = keptSends.last.flatMap { p in WalletWatch.sameAddress(p.to, resolved?.address ?? "") ? nil : p }
        return VStack(alignment: .leading, spacing: 0) {
            // Your private balance leads your own (prd §1554): one tap picks
            // it, never typed. Sepolia, DEBUG builds.
            if PrivateMove.available, q.isEmpty || String(localized: "Your private balance").lowercased().contains(q) {
                listRow(String(localized: "Your private balance"), sub: (PrivacyNetwork.current(debugAsks: PrivateMove.debugNetwork) ?? .ethereum).name, symbol: "eye.slash") {
                    goPrivate(.deposit)
                }
            }
            if let above, q.isEmpty {
                listRow(above.toName ?? YourAccount.short(above.to), sub: String(localized: "Same as above"),
                        face: above.to) {
                    to = above.toName ?? above.to
                    resolved = Recipient(address: above.to, name: above.toName, imitates: nil)
                    pick {}
                }
            }
            if let r = resolved, !book.contains(where: { WalletWatch.sameAddress($0.address, r.address) }) {
                listRow(r.name ?? YourAccount.short(r.address), sub: r.name == nil ? nil : YourAccount.short(r.address),
                        face: r.address) {
                    pick {}
                }
            }
            ForEach(Array(book.filter { e in above.map { !(q.isEmpty && WalletWatch.sameAddress($0.to, e.address)) } ?? true }.prefix(20)), id: \.address) { e in
                // A company in the book (Uniswap, Coinbase) wears its logo; a
                // person, their face (prd §1534).
                listRow(e.name, sub: YourAccount.short(e.address), mark: e.name,
                        face: AssetMark.hasAsset(e.name) ? nil : e.address) {
                    to = e.name
                    resolved = Recipient(address: EIP55.checksum(e.address), name: e.name, imitates: nil)
                    pick {}
                }
            }
            pasteRow { to = $0 }
        }
    }

    /// Where the money is (prd §1453, Receive's one network list since
    /// §1486): the account's own networks take your own address; every other
    /// network Relay takes deposits on goes through Relay, to your account on
    /// this network.
    private var elsewhereList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(networksByWorth) { n in
                listRow(n.name, sub: n.isTest ? String(localized: "Test network · its coins have no value") : String(localized: "your own address"),
                        image: Self.networkMark(n), dim: elsewhere == nil && networkPicked && n == network) {
                    pick {
                        elsewhere = nil
                        switchNetwork(n)
                        // A pick ends the arrival (prd §1488).
                        if fresh { fresh = false; arrived = true }
                    }
                }
            }
            ForEach(elsewhereNetworks) { n in
                listRow(n.name, sub: String(localized: "through Relay"), mark: n.name,
                        image: Self.networkMark(chainId: n.id), remote: n.icon) {
                    pick {}
                    takeRoute(from: n, token: n.coin(like: elsewhere?.token))
                }
            }
            if elsewhereNetworks.isEmpty, !YourAccountDemo.isOn {
                HStack(spacing: DS.Space.s2) {
                    DSSpinner()
                    Text("Asking Relay").dsText(.body17).foregroundStyle(DS.textSecondary)
                }
                .frame(minHeight: DSFeed.headHeight)
            }
        }
        // Relay's networks are asked for outside the demo only (§1475).
        .task { if elsewhereNetworks.isEmpty, !YourAccountDemo.isOn { elsewhereNetworks = await YourAccountElsewhere.networks() } }
    }

    /// Relay's address for the route, kept per route; on the network Receive
    /// stands on, Base when that is a test network.
    private func takeRoute(from: YourAccountElsewhere.Network, token: YourAccountElsewhere.Coin?) {
        guard let token else { return }
        let to = network.isTest ? Op.base : network
        let who = account
        let arrives = elsewhereArrives
        elsewhereFinding = nil
        Task {
            do {
                let route = try await YourAccountElsewhere.route(from: from, token: token, to: to, arrives: arrives, account: who)
                #if DEBUG
                NSLog("moveReceiveFrom: route %@ on %@ as %@ on %@ at %@ fee=%@", route.token.symbol, route.from.name,
                      route.arrives.symbol, route.to.name, route.address, route.feeUSD.map { String($0) } ?? "-")
                #endif
                withAnimation(DS.Motion.standard) { elsewhere = route }
                DSHaptic.tap()
            } catch let failure as Chain.Failure {
                elsewhereFinding = failure.message
            } catch {
                elsewhereFinding = String(localized: "Relay did not answer")
            }
        }
    }

    /// What they send (prd §1470): every coin Relay bridges from the route's
    /// network, its own coin first.
    private var elsewhereCoinList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let route = elsewhere {
                ForEach(route.from.coins) { c in
                    listRow(c.symbol, sub: c.isNative ? String(localized: "\(route.from.name)'s own coin") : nil,
                            mark: c.symbol, dim: c == route.token) {
                        pick {}
                        if c != route.token { takeRoute(from: route.from, token: c) }
                    }
                }
            }
        }
    }

    /// What you receive (prd §1470): the tokens For lists on your network
    /// (Uniswap's list), what you hold first; a search as you type. Relay
    /// brings what you pick, and says so if it cannot.
    private var arrivesList: some View {
        let to = network.isTest ? Op.base : network
        let typed = !search.trimmingCharacters(in: .whitespaces).isEmpty
        let pool = (typed ? (found[to.chainId] ?? []) : []) + (listedBy[to.chainId] ?? [])
        let rows = Tokens.matches(search, in: pool, held: heldBy[to.chainId] ?? [], shows: majorToken)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { l in
                let about = l.onList ? (l.name == l.token.symbol ? nil : l.name) : String(localized: "Not on Uniswap's list")
                listRow(l.token.symbol, sub: about, mark: l.token.symbol, dim: !l.onList || l.token == elsewhere?.arrives) {
                    pick { elsewhereArrives = l.token }
                    if let route = elsewhere, l.token != route.arrives { takeRoute(from: route.from, token: route.token) }
                }
            }
            if rows.isEmpty {
                HStack(spacing: DS.Space.s2) {
                    DSSpinner()
                    Text("Reading…").dsText(.body17).foregroundStyle(DS.textSecondary)
                }
                .frame(minHeight: DSFeed.headHeight)
            }
        }
        .task { if listedBy[to.chainId] == nil { listedBy[to.chainId] = await Tokens.list(to) } }
    }

    /// The one line under a route's address: what it takes, what lands, the
    /// fee. "This deposit address takes only USDT on Arbitrum. Relay brings it to your account as
    /// USDC on Base in seconds, at the price when it lands, for about $0.05."
    static func elsewhereLine(_ route: YourAccountElsewhere.Route) -> String {
        let brings = route.converts
            ? String(localized: "Relay brings it to your account as \(route.arrives.symbol) on \(route.to.name) in seconds, at the price when it lands")
            : String(localized: "Relay brings it to your account in seconds")
        let fee = route.feeUSD.map { String(localized: ", for about \(money(max($0, 0.01)))") } ?? ""
        return String(localized: "This deposit address takes only \(route.token.symbol) on \(route.from.name). \(brings)\(fee).")
    }

    private var networkList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(networksByWorth) { n in
                let total = (heldBy[n.chainId] ?? []).compactMap(\.usd).reduce(0, +)
                listRow(n.name, sub: n.isTest ? String(localized: "Test network · its coins have no value") : nil,
                        trailing: total > 0 ? Self.money(total) : nil, image: Self.networkMark(n),
                        dim: networkPicked && n == network) {
                    pick { switchNetwork(n) }
                }
            }
        }
    }

    /// **"GET USDC ON" (prd §1555, the user's design).** Where what Swap
    /// buys arrives: this network ("Same network"), or another the account
    /// is on that Across carries it to. Only ETH and the dollar cross, so a
    /// token that cannot never opens this list.
    private var destinationList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let buy {
                listHeader(String(localized: "Get \(buy.token.symbol) on"))
                ForEach(destinations) { n in
                    // The same token there, or none: For then opens on that
                    // network's list (prd §1566).
                    let there = n == buyHome ? buy : equivalent(buy.token, from: buyHome, to: n)
                    let sub: String? = n == network ? String(localized: "Same network")
                        : there.map { $0.token.symbol != buy.token.symbol ? String(localized: "As \($0.token.symbol)") : nil } ?? nil
                    listRow(n.name, sub: sub, image: Self.networkMark(n), dim: buyHome == n) {
                        pick {
                            self.buy = there
                            buyOn = n == network ? nil : n
                        }
                        if there == nil { open = .buy }
                    }
                }
            }
        }
        .task(id: destinations.map(\.chainId)) {
            for n in destinations where listedBy[n.chainId] == nil { listedBy[n.chainId] = await Tokens.list(n) }
        }
    }

    /// Each network's own mark, from the brand set the Wallet already draws.
    static func networkMark(_ n: Op.Network) -> String? { networkMark(chainId: n.chainId) }

    /// **EVERY NETWORK WEARS ITS MARK (prd §1534).** The bundled set by chain
    /// id — the L2BEAT marks the Wallet already ships, Base's for its test
    /// network — and nil where none is bundled, so the row falls back to
    /// Relay's own picture of the network, never a letter.
    static func networkMark(chainId: Int) -> String? {
        let l2b: [Int: String] = [
            10: "optimism", 100: "gnosis", 130: "unichain", 137: "polygon-pos", 169: "mantapacific",
            196: "xlayer", 288: "bobanetwork", 324: "zksync2", 360: "shape", 480: "worldchain",
            999: "hyperliquid", 1088: "metis", 1135: "lisk", 1337: "hyperliquid", 1868: "soneium",
            2020: "roninnetwork", 2741: "abstract", 2818: "morph", 4326: "megaeth", 4663: "robinhood",
            5000: "mantle", 8453: "base", 84532: "base", 33139: "apechain", 34443: "mode",
            42161: "arbitrum", 42220: "celo", 48900: "zircuit", 57073: "ink", 59144: "linea",
            60808: "bob", 98866: "plumenetwork", 534352: "scroll", 747474: "katana",
            3586256: "lighter", 5064014: "ethereal", 7777777: "zora", 9286185: "eclipse",
            548123634: "lighter-robinhood",
        ]
        if let name = l2b[chainId] { return "brand-l2b-" + name }
        switch chainId {
        case 1: return "brand-eth"
        case 792703809: return "brand-sol"
        case 8253038: return "brand-wbtc"
        default: return nil
        }
    }

    /// Where you hold the most first; the test network last.
    private var networksByWorth: [Op.Network] {
        func worth(_ n: Op.Network) -> Double { (heldBy[n.chainId] ?? []).compactMap(\.usd).reduce(0, +) }
        let usable = reach.map { r in Op.networks.filter { r.contains($0) } } ?? Op.networks
        return usable.enumerated()
            .sorted { ($0.element.isTest ? 1 : 0, -worth($0.element), $0.offset) < ($1.element.isTest ? 1 : 0, -worth($1.element), $1.offset) }
            .map(\.element)
    }

    private func pasteRow(_ put: @escaping (String) -> Void) -> some View {
        Button {
            guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                say(String(localized: "Nothing to paste"))
                return
            }
            put(text)
        } label: {
            Text("Paste an address")
                .dsText(.body17)
                .foregroundStyle(DS.pickInk)
                .frame(minHeight: 44, alignment: .leading)
        }
        .buttonStyle(RowPress())
    }

    private func pick(_ change: () -> Void) {
        withAnimation(DS.Motion.standard) {
            change()
            open = nil
        }
        search = ""
        DSHaptic.snap()
        if focus == .search || focus == .to { focus = nil }
    }

    /// A token picked: dollars typed before it stay, and become its units;
    /// an amount in another token's units does not carry over.
    private func choose(_ h: Tokens.Held) {
        if with?.id != h.id {
            if inDollars, h.price != nil {
                // The dollars stand.
            } else if inDollars {
                inDollars = false
                amount = ""
            } else {
                amount = ""
            }
        }
        with = h
        if buyOn == nil, buy?.token == h.token { buy = nil }
        if amount.isEmpty { focus = .amount }
    }

    private func switchNetwork(_ n: Op.Network) {
        networkPicked = true
        guard n != network else { return }
        network = n
        with = nil
        buy = nil
        buyOn = nil
        sweepLeftOut = []
        if !inDollars { amount = "" }
        quote = nil
    }

    // MARK: - Kept lines

    /// What Add kept, folded on what lines share: several tokens to one
    /// person, or several for one token, read as one line.
    private var keptLines: [(id: String, words: String, ids: [UUID])] {
        var order: [String] = []
        var groups: [String: [Chain.Item]] = [:]
        for item in items {
            let key: String
            switch item {
            case .send(let p): key = "to|" + p.to.lowercased()
            case .swap(let s): key = "for|" + (s.buy.contract?.lowercased() ?? s.buy.symbol)
            }
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(item)
        }
        return order.map { key in
            let group = groups[key] ?? []
            let spent = group.map { item -> String in
                switch item {
                case .send(let p): return Self.figure(p.amount, decimals: p.token.decimals) + " " + p.token.symbol
                case .swap(let s): return Self.figure(s.amount, decimals: s.sell.decimals) + " " + s.sell.symbol
                }
            }.formatted(.list(type: .and))
            let words: String
            switch group.first {
            case .send(let p):
                words = String(localized: "\(spent) to \(p.toName ?? YourAccount.short(p.to))")
            case .swap(let s):
                let back = group.reduce("0") { sum, item in
                    if case .swap(let x) = item { return Op.sum(sum, x.quote.buyAmount) }
                    return sum
                }
                words = String(localized: "\(spent) for ≈ \(Self.figure(back, decimals: s.buy.decimals)) \(s.buy.symbol)")
            case nil:
                words = ""
            }
            return (key, words, group.map(\.id))
        }
    }

    private var kept: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(keptLines.filter(showsKept).enumerated()), id: \.element.id) { n, line in
                row("\(n + 1)", ink: DS.textTertiary) {
                    Text(verbatim: line.words)
                        .dsText(.heading17)
                        .foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: DS.Space.s2)
                    Button {
                        withAnimation(DS.Motion.standard) {
                            items.removeAll { line.ids.contains($0.id) }
                            slot = min(slot, items.count)
                        }
                        DSHaptic.selection()
                    } label: {
                        Image(systemName: "xmark")
                            .dsGlyph(.caption, weight: .semibold)
                            .foregroundStyle(DS.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(PressSpring())
                    .disabled(stage != nil)
                    .accessibilityLabel(Text("Remove from this transaction"))
                }
                .frame(minHeight: 36)
            }
        }
    }

    // MARK: - The foot

    private var foot: some View {
        VStack(spacing: DS.Space.s2) {
            if receipt != nil {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(DS.Motion.standard) { receipt = nil }
                        DSHaptic.selection()
                    } label: {
                        Text("Done").dsText(.heading34).foregroundStyle(DS.textSecondary).frame(minHeight: 48, alignment: .trailing)
                    }
                    .buttonStyle(RowPress())
                }
            } else {
            // Add, then the verb (§1442d): the order you use them in, and the
            // act that signs at the trailing edge under the thumb, where iOS
            // puts a screen's main act.
            HStack(alignment: .firstTextBaseline) {
                if verb == .receive {
                    // **The foot's one act copies the address (prd §1518,
                    // user: "receive should have copy address").** Never an
                    // address without its network (prd §1486, the arrival
                    // too since §1488): grey until one is picked, and a tap
                    // opens the list. The demo's copy says it acts later.
                    Spacer(minLength: 0)
                    let ready = elsewhere != nil || (!fresh && networkPicked)
                    Button {
                        if ready { copy() } else {
                            say(String(localized: "Pick a network first"))
                            withAnimation(DS.Motion.standard) { open = .elsewhere }
                        }
                    } label: {
                        Text(verbatim: footVerb)
                            .dsText(.heading34)
                            .foregroundStyle(ready ? DS.pickInk : DS.textTertiary)
                            .frame(minHeight: 48, alignment: .trailing)
                    }
                    .buttonStyle(RowPress())
                    .accessibilityHint(ready ? Text("Copies your address") : Text("Pick a network first"))
                } else if nothingToMove {
                    // Nothing to swap, send or pay with: the sentence says so
                    // and offers Receive (prd §1518); no Add, no verb.
                    EmptyView()
                } else if verb != .buy && verb != .sweep {
                    Button { add() } label: {
                        // Pink is the values' and the signing verb's alone
                        // (§1442f): Add is white when ready, grey when not.
                        Text("Add")
                            .dsText(.heading24)
                            .foregroundStyle(pendingItem != nil && stage == nil ? DS.textPrimary : DS.textSecondary)
                            .frame(minHeight: 48)
                    }
                    .buttonStyle(RowPress())
                    // Never a dead word: unready, it says what is missing (§1442c).
                    .disabled(stage != nil)
                    .accessibilityHint(Text("Keeps this in the transaction and starts the next one"))
                }
                if verb != .receive, !nothingToMove {
                    Spacer(minLength: DS.Space.s3)
                    Button { sign() } label: {
                        Text(verbatim: footVerb)
                            .dsText(.heading34)
                            .foregroundStyle(!footOn ? DS.textTertiary
                                             : warned && stage == nil ? (leadWarning?.red == true ? DS.destructiveInk : DS.attentionInk)
                                             : DS.pickInk)
                            .frame(minHeight: 48, alignment: .trailing)
                    }
                    .buttonStyle(RowPress())
                    .disabled(!footOn)
                }
            }
            }
            // Relay's credit signs the foot, small and centred, as Apple
            // Pay's does (§1442f): a credit, not a fact about this move.
            // Wherever Relay carries the move, since it is read directly
            // (§1512): a round-up's buy and Receive from another network.
            if relayCarries, receipt == nil, !nothingToMove {
                HStack(spacing: DS.Space.s1) {
                    Text("Powered by Relay")
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                    Self.mark(of: "Relay")
                    // Relay refuses every Tor exit (measured, prd §1495): the
                    // one wallet act that leaves Tor says so where it happens.
                    if TorRoute.available {
                        Text("· not through Tor")
                            .dsText(.label12)
                            .foregroundStyle(DS.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, DS.Space.s1)
            }
            // A swap's or a sweep's exchange signs the foot in the same
            // place (prd §1539): "On Uniswap · 0.05% pool fee". It is a fact
            // about this swap, so it carries no "powered by".
            if let exchangeCredit, receipt == nil, !nothingToMove {
                Text(verbatim: exchangeCredit)
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, DS.Space.s1)
            }
            // Bitrefill's credit signs Buy's foot the same way (§1473, user:
            // "put bitrefill logo like we do w/ relay").
            if verb == .buy, receipt == nil {
                HStack(spacing: DS.Space.s1) {
                    Text("Powered by Bitrefill")
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                    Self.mark(of: "Bitrefill")
                }
                .frame(maxWidth: .infinity)
                .padding(.top, DS.Space.s1)
            }
        }
        .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
        .padding(.bottom, footClearance)
        // The page's own ground, so a long list scrolls under the foot.
        .background { if inTray { DS.surfaceSheet } else { DSPageBackground() } }
    }

    /// The phone's tab bar floats over the page's bottom edge and reserves
    /// nothing, so the foot clears it by the bar's own geometry; a keyboard
    /// covers the bar (prd §865), and the foot rides on the keys.
    private var footClearance: CGFloat {
        guard !inTray, sizeClass == .compact, !chrome.keyboardUp else { return DS.Space.s2 }
        return DSDock.agentSize(fold: chrome.fold) + DSDock.agentBottomInset(fold: chrome.fold) + DS.Space.s2
    }

    /// Read, nothing anywhere, and nothing under way: the foot has no act
    /// to draw (prd §1518). A move landing keeps its foot.
    private var nothingToMove: Bool {
        verb != .receive && emptyEverywhere && stage == nil && all.isEmpty
    }

    private var footOn: Bool {
        if verb == .buy { return stage == nil && buyReady }
        if verb == .sweep {
            return stage == nil && !sweepPricing && !sweepItems.isEmpty && failNote == nil && sweepFeeNote == nil
        }
        // A transaction the simulation refuses dims its verb (prd §1509).
        return verb == .receive || (stage == nil && !all.isEmpty && failNote == nil)
    }

    private var footVerb: String {
        switch stage {
        case .preparing: return String(localized: "Preparing…")
        case .signing: return String(localized: "Confirm with Face ID")
        case .sending: return String(localized: "Sending…")
        case .landing: return delivering ? String(localized: "Waiting for Bitrefill…") : String(localized: "Waiting for \(network.name)…")
        case nil: break
        }
        if verb == .receive { return String(localized: "Copy address") }
        if verb == .buy { return String(localized: "Buy") }
        if verb == .sweep {
            return sweepItems.count < 2 ? String(localized: "Sweep") : String(localized: "Sweep all \(sweepItems.count)")
        }
        // A warning makes it a second tap (prd §1509 item 2).
        if warned { return verb == .swap ? String(localized: "Swap anyway") : String(localized: "Send anyway") }
        let batch = all
        let swaps = batch.filter { if case .swap = $0 { true } else { false } }.count
        let kind: Verb? = swaps == batch.count ? .swap : swaps == 0 ? .send : nil
        switch batch.count {
        case 0, 1: return title(verb)
        case 2:
            switch kind {
            case .swap: return String(localized: "Swap both")
            case .send: return String(localized: "Send both")
            default: return String(localized: "Sign both")
            }
        default:
            switch kind {
            case .swap: return String(localized: "Swap all \(batch.count)")
            case .send: return String(localized: "Send all \(batch.count)")
            default: return String(localized: "Sign all \(batch.count)")
            }
        }
    }

    private func shareBinding(_ h: Tokens.Held) -> Binding<Int> {
        Binding(
            get: {
                let have = left(h)
                guard let u = units, have != "0" else { return 0 }
                if Op.atMost(have, u) { return 100 }
                let a = Double(Op.display(u, decimals: h.token.decimals, places: min(h.token.decimals, 12))) ?? 0
                let b = Double(Op.display(have, decimals: h.token.decimals, places: min(h.token.decimals, 12))) ?? 1
                return b > 0 ? min(100, Int((a / b * 100).rounded())) : 0
            },
            set: { p in
                let part = Op.share(left(h), percent: p)
                if inDollars, let price = h.price {
                    amount = p == 0 ? "" : String(format: "%.2f", Op.dollars(part, decimals: h.token.decimals, price: price))
                } else {
                    // Every place at 100% (all of it, exactly); short of
                    // that, as many as the sentence can carry — a 20-digit
                    // figure is a clause wider than the line (§1466).
                    amount = p == 0 ? "" : Op.display(part, decimals: h.token.decimals,
                                                      places: p == 100 ? h.token.decimals : min(h.token.decimals, 8))
                }
            })
    }

    // MARK: - Acts

    /// What the sentence still needs before Add can keep it.
    private var missing: String? {
        if verb == .buy, let why = buyMissing { return why }
        if !networkPicked && with == nil { return String(localized: "Pick a token first") }
        if with == nil { return String(localized: "Pick a token to spend") }
        if amount.isEmpty || units == "0" { return String(localized: "Type an amount first") }
        if over { return String(localized: "More than you have") }
        switch verb {
        case .swap:
            if buy == nil { return String(localized: "Pick what you want") }
            if let quoteNote { return quoteNote }
            if quote == nil { return String(localized: "Waiting for the price") }
        case .send:
            if resolved == nil { return String(localized: "Pick who it goes to") }
        case .receive, .buy, .sweep:
            break
        }
        return nil
    }

    private func add() {
        guard let item = pendingItem else {
            #if DEBUG
            NSLog("moveAdd: missing=%@", missing ?? "-")
            #endif
            if let missing { say(missing) }
            DSHaptic.selection()
            return
        }
        if let first = items.first, first.network != item.network {
            say(String(localized: "One transaction sends on one network"), failure: true)
            return
        }
        // A swap to another network is its transaction alone (prd §1555): the
        // Wallet shows that transaction as the one crossing.
        func crosses(_ i: Chain.Item) -> Bool { if case .swap(let s) = i { return s.crosses } else { return false } }
        if !items.isEmpty, crosses(item) || items.contains(where: crosses) {
            say(String(localized: "A swap to another network goes alone"), failure: true)
            return
        }
        withAnimation(DS.Motion.standard) {
            // **A LIKE SWAP IS ONE SWAP (prd §1494, user: "i made two swaps
            // both eth, which shouldn't show as two").** The same token for
            // the same token adds to the line already kept: one clause, one
            // swap signed. Its quote is the two summed for the sentence;
            // the pools are asked afresh for the whole at signing.
            if case .swap(let new) = item, let at = items.firstIndex(where: {
                if case .swap(let s) = $0 { return s.sell == new.sell && s.buy == new.buy }
                return false
            }), case .swap(let old) = items[at] {
                items[at] = .swap(Self.folded(old, new))
            } else {
                items.insert(item, at: min(slot, items.count))
            }
            slot = items.count
        }
        DSHaptic.tap()
        // The next sentence keeps what it is for or who it is to, and the
        // network; it moves to the next token with something left.
        amount = ""
        quote = nil
        // The next line takes a token with something left that this swap
        // has not sold, or this person has not been sent (§1442h).
        let goingTo = resolved?.address
        if let next = held.first(where: { h in
            h.id != with?.id && left(h) != "0" && h.token != buy?.token && !items.contains { item in
                switch item {
                case .swap(let s): s.sell == h.token
                case .send(let p): p.token == h.token && goingTo.map { WalletWatch.sameAddress($0, p.to) } == true
                }
            }
        }) {
            with = next
            if next.price == nil { inDollars = false }
        }
        // The new line is a new row (a send regroups it), so the field it
        // focuses exists only after this pass: raise the keys on the next.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            focus = .amount
        }
    }

    /// Two swaps of one token for one token as one: the amounts summed,
    /// the quote's figures summed for the sentence, no calls (signing asks
    /// the pools for the whole amount, `Chain.transact`).
    static func folded(_ a: Chain.Swap, _ b: Chain.Swap) -> Chain.Swap {
        let q = YourAccountSwap.Quote(sellAmount: Op.sum(a.quote.sellAmount, b.quote.sellAmount),
                                      buyAmount: Op.sum(a.quote.buyAmount, b.quote.buyAmount),
                                      minimumBuy: Op.sum(a.quote.minimumBuy, b.quote.minimumBuy),
                                      route: a.quote.route ?? b.quote.route, calls: [], wrap: a.quote.wrap)
        return Chain.Swap(id: a.id, network: a.network, sell: a.sell, buy: a.buy,
                          amount: Op.sum(a.amount, b.amount), quote: q, to: a.to)
    }

    private func sign() {
        guard stage == nil else { return }
        // The first tap on "Send anyway" only arms it; the second signs.
        if verb != .buy, warned, armed != armKey {
            armed = armKey
            DSHaptic.failure()
            #if DEBUG
            NSLog("moveWarn| armed %@", armKey)
            #endif
            return
        }
        // The demo's account signs nothing (§1475): it says so, as every demo act does.
        if YourAccountDemo.isDemo(account) { say(YourAccountDemo.actsLater); return }
        if verb == .buy { buyNow(); return }
        // Sweep signs its own swaps, and leaves the lines Add kept (prd §1537).
        let sweeping = verb == .sweep
        let batch = signing
        guard !batch.isEmpty else { return }
        let reason = sweeping ? sweepFaceIDWords(batch) : faceIDWords(batch)
        let net = network
        let roundUp = roundUpPlan
        let carried = roundUpCarried
        let toPrivate = privateRoundUps
        let rideUnits = privateRide
        stage = .preparing
        Task {
            do {
                let buy = carried
                // Round-ups due into your private balance (prd §1565): the
                // deposit proved now and carried by this operation; one that
                // cannot be written keeps counting, and the send goes alone.
                var ride: PrivateOnEthereum.Ride?
                if let rideUnits {
                    do { ride = try await PrivateOnEthereum.roundUpsRide(units: rideUnits) } catch {
                        NSLog("roundUpsPrivate| kept counting | %@", String(describing: error))
                    }
                }
                let done = try await Self.spend(batch, on: net, account: account, roundUp: buy, ride: ride?.calls ?? [], reason: reason,
                                                said: { line in await MainActor.run { say(line) } }) { s in
                    await MainActor.run { stage = s }
                }
                // The change is counted once the send has landed; a buy
                // empties the count with it, and a send that did not buy (the
                // spend limit's key, or no pool, prd §1545) keeps it all.
                if let roundUp, case .landed(let tx, _) = done.sent.outcome {
                    if toPrivate {
                        // The pool's minimum, read again for the next send's threshold.
                        Task { await PrivateMoneyStore.shared.readYield(including: .ethereum) }
                        let moved = ride != nil && done.rode
                        RoundUps.setPrivateSaved(RoundUps.savedAfter(roundUp, bought: moved), on: net.chainId)
                        if moved, let ride, let tx { Self.landPrivateRoundUps(ride, tx: tx, context: context) }
                    } else {
                        RoundUps.setSaved(RoundUps.savedAfter(roundUp, bought: buy != nil && !done.roundUpWaits), on: net.chainId)
                    }
                }
                let sent = done.sent
                stage = nil
                chrome.refreshRooms()
                // Landed or still on its way, the transaction is gone from the
                // page, so a second tap cannot pay it twice. The sentence
                // turns past tense in its place (§1438b): no toast.
                let made = Self.receipt(for: batch, done: done, on: net)
                // A token a swap just bought is spendable now, not when the
                // Wallet next reads the account (§1442l).
                if case .landed = sent.outcome {
                    for item in batch { if case .swap(let x) = item { Tokens.remember(x.buy, on: net) } }
                }
                withAnimation(DS.Motion.standard) {
                    if sweeping {
                        sweepItems = []
                        sweepPlan = nil
                        sweepLeftOut = []
                    } else {
                        items = []
                        slot = 0
                        amount = ""
                        quote = nil
                    }
                    receipt = made
                }
                if case .landed = sent.outcome {
                    DSHaptic.success()
                    chrome.rain(sources: ["Wallet"])
                }
                // A swap to another network: its arrival is read (prd §1555).
                if let crossing = done.crossing, crossing.tx != nil { crossingWatch = crossing }
                await readNetwork()
            } catch let failure as Chain.Failure {
                stage = nil
                #if DEBUG
                NSLog("moveSign: failed %@", failure.message)
                #endif
                say(failure.message, failure: true, seconds: 6, from: failure.from)
            } catch {
                stage = nil
                #if DEBUG
                NSLog("moveSign: not sent %@", String(describing: error))
                #endif
                // Face ID cancelled, or the Enclave refused: nothing left the phone.
                say(String(localized: "Not sent"), failure: true)
            }
        }
    }

    /// **UNDER THE LIMIT, FACE ID ALONE; OVER IT, THE SIGNER TOO (prd §1455).**
    /// With the spend limit on, sends of the dollar and ETH go on the session
    /// key; one the limit refuses (over the window's total, or a token it does
    /// not cover) and every swap are signed by this phone and the Signer, whose
    /// wallet is asked through the Signer sheet. A refusal before Face ID sends
    /// nothing, so asking both keys next pays nothing twice.
    static func spend(_ batch: [Chain.Item], on net: Op.Network, account: String, roundUp: Chain.RoundUpBuy?,
                      ride: [(to: String, data: String, value: String)] = [],
                      reason: String, said: @escaping @Sendable (String) async -> Void,
                      stage: @escaping @Sendable (Chain.Stage) async -> Void) async throws -> Chain.Transacted {
        guard case .on = (try? await Chain.limitState(net, account)) ?? .off else {
            return try await Chain.transact(batch, reason: reason, roundUp: roundUp, ride: ride, stage: stage)
        }
        let sends = batch.compactMap { if case .send(let p) = $0 { p } else { nil } }
        if sends.count == batch.count {
            let signed = SignedFlag()
            do {
                let sent = try await Chain.sessionSend(sends, roundUp: roundUp, reason: reason) { s in
                    if s == .signing { await signed.mark() }
                    await stage(s)
                }
                // The session buys only to another network (prd §1545).
                return Chain.Transacted(sent: sent, roundUpWaits: roundUp != nil && Chain.sessionRoundUp(roundUp, on: net) == nil)
            } catch let failure as Chain.Failure {
                // A send the simulation refuses fails on both keys too.
                guard await !signed.value, !failure.settled else { throw failure }
                #if DEBUG
                NSLog("moveSpend: over the limit, both keys: %@", failure.message)
                #endif
                await said(String(localized: "Over your limit: your Signer signs too"))
            }
        }
        guard let signer = try await Chain.signers(net, account).first else {
            throw Chain.Failure(message: String(localized: "Add a signer first: over the limit, a send waits on it"))
        }
        return try await Chain.transact(batch, reason: reason, coSigner: SignerRequestSheet.coSigner(owner: signer, chainId: net.chainId),
                                        roundUp: roundUp, renew: true, ride: ride, stage: stage)
    }

    /// Round-ups that rode a landed operation (prd §1565): the note kept
    /// waiting for approval, its Activity row with no verb.
    @MainActor
    static func landPrivateRoundUps(_ ride: PrivateOnEthereum.Ride, tx: String, context: ModelContext) {
        let n = ride.keep
        PrivateMoneyStore.shared.add(.init(commitment: n.commitment, label: n.label, labelHash: n.labelHash, symbol: n.symbol,
                                           amount: n.amount, decimals: n.decimals, chainId: n.chainId, tx: tx, at: Date(),
                                           status: .waiting, root: n.root, share: n.share))
        PrivateActivity.land(hash: tx, title: PrivateMoney.roundUpsTitle(figure: ride.figure), chainId: n.chainId, context: context)
        NSLog("roundUpsPrivate| moved | %@ | %@", tx, ride.figure)
    }

    /// Whether Face ID was reached, read across the send's tasks.
    actor SignedFlag {
        private(set) var value = false
        func mark() { value = true }
    }

    /// The sentence in the past tense: what was sent or swapped, what a filled
    /// order actually paid out, and how it went.
    static func receipt(for batch: [Chain.Item], done: Chain.Transacted, on net: Op.Network) -> Receipt {
        typealias Line = Receipt.Line
        let sent = done.sent
        let tx: String? = { if case .landed(let t, _) = sent.outcome { return t } else { return nil } }()
        let link = tx.flatMap { explorer($0, on: net) }
        let linkName: String? = net.chainId == 1 ? "Etherscan" : net.chainId == 4663 ? "Blockscout" : "Basescan"
        let on = Line(glue: String(localized: "on"), text: net.name + ".")
        func made(_ past: String, _ lines: [Line], _ detail: [String] = []) -> Receipt {
            Receipt(past: past, lines: lines, detail: detail.joined(separator: " · "),
                    link: link, linkName: link == nil ? nil : linkName)
        }
        if case .pending = sent.outcome {
            return Receipt(past: String(localized: "Sent,"),
                           lines: [Line(glue: nil, text: String(localized: "not yet seen")), on],
                           detail: String(localized: "Check before sending again"))
        }
        let swaps = batch.compactMap { if case .swap(let x) = $0 { x } else { nil } }
        let sends = batch.compactMap { if case .send(let p) = $0 { p } else { nil } }
        func amount(_ units: String, _ token: Op.Token) -> String { Self.figure(units, decimals: token.decimals) + " " + token.symbol }

        // **TO ANOTHER NETWORK (prd §1555):** "Swapped 0.01 ETH on Ethereum
        // for 24.87 USDC on Base." Exactly that arrives — a relayer pays the
        // deposit's own amount — and the line says it is on its way until the
        // fill is read.
        if swaps.count == 1, batch.count == 1, let x = swaps.first, x.crosses, let dest = x.to {
            let lines = [Line(glue: nil, text: amount(x.amount, x.sell)), Line(glue: String(localized: "on"), text: net.name),
                         Line(glue: String(localized: "for"), text: amount(x.quote.buyAmount, x.buy)),
                         Line(glue: String(localized: "on"), text: dest.name + ".")]
            let waiting = [String(localized: "Arriving on \(dest.name)"), YourAccountAcross.about(x.quote.across?.seconds)]
            return made(String(localized: "Swapped"), lines, waiting.compactMap { $0 })
        }

        // What each swap paid the account: `bought` is in the batch's order,
        // nil for a send.
        var bought: [String?] = done.bought
        if done.bought.count == batch.count {
            bought = zip(batch, done.bought).compactMap { item, paid -> String?? in
                if case .swap = item { return .some(paid) }
                return nil
            }
        }
        var paidBy: [UUID: String] = [:]
        if bought.count == swaps.count {
            for (x, paid) in zip(swaps, bought) { if let paid { paidBy[x.id] = paid } }
        }
        let measured = !swaps.isEmpty && swaps.allSatisfy { paidBy[$0.id] != nil }

        // **SWAPS (§1442g, prd §1494).** By what they bought; under each,
        // what they sold, one token once with its amounts summed ("two swaps
        // both eth … should have just done it as one"), joined as a list
        // reads; then "for" what came back — measured when every swap was,
        // else the quotes, ≈.
        var swapLines: [Line] = []
        var detail: [String] = []
        let buys = swaps.reduce(into: [Op.Token]()) { if !$0.contains($1.buy) { $0.append($1.buy) } }
        for (b, buyToken) in buys.enumerated() {
            let group = swaps.filter { $0.buy == buyToken }
            let sells = group.reduce(into: [Op.Token]()) { if !$0.contains($1.sell) { $0.append($1.sell) } }
            for (n, sell) in sells.enumerated() {
                let units = group.filter { $0.sell == sell }.reduce("0") { Op.sum($0, $1.amount) }
                let join = Self.joiner(n, of: sells.count)
                swapLines.append(Line(glue: n == 0 ? (b == 0 ? nil : String(localized: "and")) : join.glue,
                                      text: amount(units, sell) + (join.trail ?? "")))
            }
            let quoted = group.map(\.quote.buyAmount).reduce("0") { Op.sum($0, $1) }
            let back = measured ? group.compactMap { paidBy[$0.id] }.reduce("0") { Op.sum($0, $1) } : quoted
            swapLines.append(Line(glue: String(localized: "for"), text: (measured ? "" : "≈ ") + amount(back, buyToken)))
            // More than quoted is the honest surprise: the route paid more.
            if buys.count == 1, measured, Op.atMost(quoted, back), back != quoted {
                detail.append(String(localized: "\(Self.figure(Op.difference(back, quoted), decimals: buyToken.decimals)) \(buyToken.symbol) more than quoted"))
            }
        }
        // Sends (§1442h): each person's tokens, then "to <them>".
        var sendLines: [Line] = []
        var at = 0
        while at < sends.count {
            let to = sends[at].to
            var end = at
            while end < sends.count, WalletWatch.sameAddress(sends[end].to, to) {
                sendLines.append(Line(glue: nil, text: amount(sends[end].amount, sends[end].token)))
                end += 1
            }
            sendLines.append(Line(glue: String(localized: "to"), text: sends[at].toName ?? YourAccount.short(to)))
            at = end
        }
        let swapped = measured ? String(localized: "Swapped") : String(localized: "Swapping")
        if sends.isEmpty, !swaps.isEmpty { return made(swapped, swapLines + [on], detail) }
        if swaps.isEmpty, !sends.isEmpty { return made(String(localized: "Sent"), sendLines + [on]) }
        guard !swaps.isEmpty else {
            return made(String(localized: "Signed"), [Line(glue: nil, text: String(localized: "\(batch.count) in one transaction")), on])
        }
        // **BOTH: TWO SENTENCES (prd §1494).** The one signed first leads and
        // says the network; the other starts a line with "Then".
        let swapFirst: Bool = { if case .swap = batch.first { return true } else { return false } }()
        var second = swapFirst ? sendLines : swapLines
        second[0].glue = swapFirst ? String(localized: "Then sent")
                                   : (measured ? String(localized: "Then swapped") : String(localized: "Then swapping"))
        second[0].starts = true
        second[second.count - 1].text += "."
        return made(swapFirst ? swapped : String(localized: "Sent"),
                    (swapFirst ? swapLines : sendLines) + [on] + second, swapFirst ? detail : [])
    }

    /// What Face ID says: the whole sentence, the least a swap returns.
    private func faceIDWords(_ batch: [Chain.Item]) -> String {
        guard batch.count == 1, let item = batch.first else {
            return String(localized: "Sign \(batch.count) in one transaction")
        }
        switch item {
        case .send(let p):
            let who = p.toName ?? YourAccount.short(p.to)
            return String(localized: "Send \(Op.spoken(p.amount, decimals: p.token.decimals)) \(p.token.symbol) to \(who)")
        case .swap(let s) where s.crosses:
            return String(localized: "Swap \(Op.spoken(s.amount, decimals: s.sell.decimals)) \(s.sell.symbol) on \(s.network.name) for \(Op.spoken(s.quote.minimumBuy, decimals: s.buy.decimals)) \(s.buy.symbol) on \(s.to?.name ?? "")")
        case .swap(let s):
            return String(localized: "Swap \(Op.spoken(s.amount, decimals: s.sell.decimals)) \(s.sell.symbol) for at least \(Op.spoken(s.quote.minimumBuy, decimals: s.buy.decimals)) \(s.buy.symbol)")
        }
    }

    private static func explorer(_ transaction: String, on network: Op.Network) -> URL? {
        let host: String
        switch network.chainId {
        case 8453: host = "basescan.org"
        case 1: host = "etherscan.io"
        case 4663: host = "robinhoodchain.blockscout.com"
        case 84532: host = "sepolia.basescan.org"
        default: return nil
        }
        return URL(string: "https://\(host)/tx/\(transaction)")
    }

    /// The address Receive shows: your own, or a route's (prd §1453).
    private var receiveAddress: String { elsewhere?.address ?? account }

    private func copy() {
        // The demo's address holds no key: money sent there is lost, so it
        // is never copied (§1475).
        if YourAccountDemo.isDemo(account) { say(YourAccountDemo.actsLater); return }
        UIPasteboard.general.string = receiveAddress
        DSHaptic.tap()
        say(String(localized: "Address copied"))
    }

    /// **ARRIVED, READ (prd §1555).** A swap to another network that landed
    /// is followed until the receiving SpokePool says it was filled — read,
    /// never assumed — every four seconds for fifteen minutes; then the
    /// Wallet's Activity row keeps following it.
    private func watchCrossing() async {
        guard let c = crossingWatch else { return }
        let name = YourAccountAcross.networkName(c.to)
        let until = Date().addingTimeInterval(15 * 60)
        while !Task.isCancelled, Date() < until {
            if await Chain.acrossFill(c) == .filled {
                YourAccountAcross.update(c.id) { x in
                    if x.state == .waiting { x.state = .filled; x.settledAt = .now }
                }
                #if DEBUG
                NSLog("moveAcross| filled %@ → %@", YourAccountAcross.networkName(c.from), name)
                #endif
                if receipt != nil {
                    withAnimation(DS.Motion.standard) { receipt?.detail = String(localized: "Arrived on \(name)") }
                }
                DSHaptic.success()
                chrome.refreshRooms()
                crossingWatch = nil
                return
            }
            try? await Task.sleep(for: .seconds(4))
        }
    }

    // MARK: - Reads

    /// Every network's holdings at once; the sentence starts on the one
    /// holding the most, and spends its biggest token.
    private func readAll() async {
        await readHoldings()
        await readLists()
    }

    /// What the account holds, everywhere, read again whenever money may
    /// have arrived since (user: "i have money in my account but casberi
    /// says i can't receive or swap"): the app coming back and leaving
    /// Receive (another tab unmounts Move, so its return reads anew). A
    /// token being spent keeps up.
    private func readHoldings() async {
        // Every network at once: one slow node holds none of the others.
        var found: [Int: [Tokens.Held]] = [:]
        var failed: Set<Int> = []
        await withTaskGroup(of: (Int, [Tokens.Held]?).self) { group in
            for net in Op.networks {
                group.addTask { @MainActor in (net.chainId, await Tokens.read(account, on: net)) }
            }
            for await (id, held) in group {
                found[id] = held ?? []
                if held == nil { failed.insert(id) }
            }
        }
        // **A FAILED NETWORK IS ASKED ONCE MORE, ON ITS OWN (prd §1532, user:
        // "also get this error can't read networks").** Every node answered
        // from a desk minutes later, so a read that came back empty on all
        // three networks at once was the phone's connection in the instant
        // the tab opened, not the nodes. One more ask two seconds on, before
        // the error is said, and only for what failed.
        if !failed.isEmpty {
            try? await Task.sleep(for: .seconds(2))
            await withTaskGroup(of: (Int, [Tokens.Held]?).self) { group in
                for net in Op.networks where failed.contains(net.chainId) {
                    group.addTask { @MainActor in (net.chainId, await Tokens.read(account, on: net)) }
                }
                for await (id, held) in group where held != nil {
                    found[id] = held
                    failed.remove(id)
                }
            }
        }
        heldBy = found
        unread = failed
        if let w = with, !failed.contains(network.chainId) {
            with = found[network.chainId]?.first { $0.id == w.id }
        }
        reach = await YourAccountReach.usable(account)
    }

    private func readLists() async {
        // Nothing is picked for you (§1438c): the lists lead with where you
        // hold the most, and the sentence waits for your picks.
        var lists: [Int: [Tokens.Listed]] = [:]
        await withTaskGroup(of: (Int, [Tokens.Listed]).self) { group in
            for net in Op.networks {
                group.addTask { @MainActor in (net.chainId, await Tokens.list(net)) }
            }
            for await (id, list) in group { lists[id] = list }
        }
        listedBy = lists
        buyAvailable = BitrefillX402.available
    }

    private func readNetwork() async {
        let read = await Tokens.read(account, on: network)
        let now = read ?? []
        heldBy[network.chainId] = now
        if read == nil { unread.insert(network.chainId) } else { unread.remove(network.chainId) }
        if let w = with { with = now.first { $0.id == w.id } }
        listedBy[network.chainId] = await Tokens.list(network)
    }

    /// The quote is asked again whenever what would be swapped changes.
    private var quoteKey: String {
        guard verb == .swap, let with, let buy else { return "" }
        return "\(network.chainId)|\(with.id)|\(buy.id)|\(units ?? "")|\(crossTo?.chainId ?? 0)"
    }

    private func requote() async {
        quote = nil
        quoteNote = nil
        quoteFrom = nil
        guard verb == .swap, let with, let buy, YourAccountSwap.supported(network), let units, !over else { return }
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        do {
            let q: YourAccountSwap.Quote
            if let on = crossTo, let arrives = crossBuy {
                // To another network: Across's fee asked, the calls written
                // here (prd §1555).
                q = try await Chain.crossQuote(network, to: on, sell: with.token, buy: arrives, amount: units, account: account)
            } else {
                q = try await Chain.swapQuote(network, sell: with.token, buy: buy.token, amount: units, account: account)
            }
            guard !Task.isCancelled else { return }
            withAnimation(DS.Motion.standard) { quote = q }
            #if DEBUG
            // `moveSwapQuote|` (prd §1542): which pools won, in words and as a route.
            let hops = q.route?.hops.map { "\($0.from.suffix(6))>\($0.step)>\($0.to.suffix(6))" }.joined(separator: " ") ?? "-"
            NSLog("moveSwapQuote| %@ %@ %@→%@ | %@ | out=%@ min=%@ | %@ calls=%d", network.name, units, with.token.symbol, buy.token.symbol,
                  q.route.map(YourAccountSwap.words) ?? "-", q.buyAmount, q.minimumBuy, hops, q.calls.count)
            draftAddsTheSwap()
            #endif
        } catch let failure as Chain.Failure {
            guard !Task.isCancelled else { return }
            quoteNote = failure.message
            quoteFrom = failure.from
        } catch {}
    }

    /// The list's matches as you type, after a pause, on every network the
    /// list looks in; a pasted contract is read off each.
    private func lookUpPasted() async {
        if open == .merchant { await searchMerchants(); return }
        pasted = [:]
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard open == .buy || open == .arrives, !text.isEmpty else { found = [:]; return }
        try? await Task.sleep(for: .milliseconds(ENS.isHexAddress(text) ? 300 : 250))
        guard !Task.isCancelled else { return }
        // What you receive (§1470) is searched on the one network it lands on.
        let searched = open
        let nets = searched == .arrives ? [network.isTest ? Op.base : network] : searchedIn
        let isAddress = ENS.isHexAddress(text)
        var matches: [Int: [Tokens.Listed]] = [:]
        var looked: [Int: Tokens.Listed] = [:]
        await withTaskGroup(of: (Int, [Tokens.Listed], Tokens.Listed?).self) { group in
            for net in nets {
                group.addTask { @MainActor in
                    isAddress ? (net.chainId, [], await Tokens.lookUp(text, on: net))
                              : (net.chainId, await Tokens.list(net, term: text), nil)
                }
            }
            for await (id, list, one) in group {
                matches[id] = list
                if let one { looked[id] = one }
            }
        }
        guard !Task.isCancelled, open == searched, nets == (searched == .arrives ? [network.isTest ? Op.base : network] : searchedIn) else { return }
        found = matches
        pasted = looked
    }

    private func resolve() async {
        let text = to.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = resolved, r.name?.caseInsensitiveCompare(text) == .orderedSame { return }
        resolved = nil
        malformed = false
        guard !text.isEmpty else { return }
        if text.lowercased().hasPrefix("0x") {
            guard ENS.isHexAddress(text), AddressSafety.checksum(text) != .failed else {
                // Said once the typing pauses, so it never flickers mid-word.
                try? await Task.sleep(for: .milliseconds(600))
                if !Task.isCancelled { malformed = true }
                return
            }
            let address = EIP55.checksum(text)
            // Your own address says so, never a fragment of itself (§1442l).
            if WalletWatch.sameAddress(address, account) {
                withAnimation(DS.Motion.standard) {
                    resolved = Recipient(address: address, name: String(localized: "yourself"), imitates: nil)
                }
                return
            }
            let book = AddressBook.shared
            let imitates = book.name(for: address) == nil ? book.lookalikes(of: address).first?.name : nil
            withAnimation(DS.Motion.standard) {
                resolved = Recipient(address: address, name: book.name(for: address), imitates: imitates)
            }
            // A pasted address you know becomes its name with a snap; one that
            // imitates a name you know shakes once (§1438b).
            if imitates != nil {
                shake += 1
                DSHaptic.failure()
            } else if book.name(for: address) != nil {
                DSHaptic.snap()
            }
            return
        }
        // A name in your book, then a name a resolver knows.
        if let entry = AddressBook.shared.all.first(where: { $0.name.caseInsensitiveCompare(text) == .orderedSame }),
           ENS.isHexAddress(entry.address) {
            resolved = Recipient(address: EIP55.checksum(entry.address), name: entry.name, imitates: nil)
            return
        }
        guard text.contains(".") else { return }
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled, let address = await NameResolve.resolve(text), ENS.isHexAddress(address) else { return }
        // The field may have changed while the resolver answered: an old
        // name's address must never stand for what the field says now.
        guard !Task.isCancelled, text == to.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        resolved = Recipient(address: EIP55.checksum(address), name: text, imitates: nil)
    }


    // MARK: - Buy (prd §1473)

    /// The one holding Buy pays with: USDC on Base.
    static func paysBuy(_ h: Tokens.Held, on net: Op.Network) -> Bool {
        net.chainId == BitrefillX402.network.chainId && h.token.contract?.lowercased() == net.dollar.lowercased()
    }

    private var buyAccount: String? {
        if YourAccountDemo.isOn { return account }
        return YourAccountKey.address ?? (BitrefillX402.sample ? account : nil)
    }

    /// Buy's sentence: "$50 gift card for Travel at Delta with USDC on Base."
    /// — the amount is the card's value, the category and the merchant are
    /// words that open their lists, and the payment is a fact, not a choice.
    @ViewBuilder private var buyClauses: some View {
        MoveClause {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                word("$", ink: amount.isEmpty ? DS.textTertiary : DS.pickInk)
                amountField
            }
            .contentShape(Rectangle())
            .onTapGesture { if stage == nil { focus = .amount } }
            .dsCardLead(Text("Edits the amount")) { if stage == nil { focus = .amount } }
        }
        // The noun is its own clause, and so are "with USDC" and "on Base.":
        // the flow sizes the sentence by its widest clause (§1479), and one
        // unbreakable "with USDC on Base." drew Buy a size under Swap, Send
        // and Receive (prd §1481).
        MoveClause { word(buyProduct?.noun ?? String(localized: "gift card"), ink: DS.textPrimary) }
        MoveClause(glue: String(localized: "for")) {
            blank(buyGroup?.title ?? String(localized: "category"), ink: buyGroup == nil ? DS.textTertiary : DS.pickInk,
                  .group, label: Text("Pick a category"))
        }
        MoveClause(glue: String(localized: "at")) {
            blank(buyProduct.map { BitrefillBuy.shortName($0.name) } ?? String(localized: "merchant"),
                  ink: buyProduct == nil ? DS.textTertiary : DS.pickInk, .merchant, label: Text("Pick a merchant"))
        }
        MoveClause(glue: String(localized: "with")) { word("USDC", ink: DS.textPrimary) }
        MoveClause(glue: String(localized: "on")) { word(String(localized: "Base."), ink: DS.textPrimary) }
    }

    /// Bitrefill's categories folded to seven, each with the cards people
    /// know it by; a pick keeps a merchant only if it stands in the group.
    private var groupList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(BitrefillBuy.Group.allCases, id: \.self) { g in
                listRow(g.title, sub: g.examples, symbol: g.glyph, dim: buyGroup == g) {
                    pick {
                        buyGroup = g
                        if let p = buyProduct, BitrefillBuy.group(of: p) != g { buyProduct = nil }
                    }
                    Task { await seedGroup(g) }
                }
            }
        }
    }

    /// What you already pay, then Bitrefill's popular cards in the group (or
    /// every group), then what a typed word finds. Popularity is Bitrefill's
    /// own order (measured: the search answers its top 25, no paging).
    private var merchantList: some View {
        let q = search.trimmingCharacters(in: .whitespaces)
        let everything = Self.dedupe(popular + foundProducts)
        let pool = buyGroup.map { BitrefillBuy.products(in: $0, of: everything) } ?? everything.filter(\.buyable)
        let spend = q.isEmpty ? BitrefillBuy.whereYouSpend(spendNames, in: pool) : []
        let rows = (q.isEmpty ? pool : BitrefillBuy.search(q, in: everything.filter(\.buyable)))
            .filter { p in !spend.contains { $0.id == p.id } }
        return VStack(alignment: .leading, spacing: 0) {
            if !spend.isEmpty {
                listHeader(String(localized: "Where you spend"))
                ForEach(spend) { merchantRow($0) }
                listHeader(buyGroup.map { String(localized: "\($0.title) · popular") } ?? String(localized: "Popular"))
            }
            ForEach(rows.prefix(60)) { merchantRow($0) }
            if rows.isEmpty, spend.isEmpty {
                HStack(spacing: DS.Space.s2) {
                    if buyReading { DSSpinner() }
                    Text(verbatim: buyReading ? String(localized: "Asking Bitrefill")
                         : q.isEmpty ? String(localized: "Nothing here yet") : String(localized: "Nothing named \(q)"))
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                }
                .frame(minHeight: DSFeed.headHeight)
            }
        }
    }

    private func listHeader(_ text: String) -> some View {
        Text(verbatim: text)
            .dsText(.label12)
            .foregroundStyle(DS.textSecondary)
            .frame(minHeight: 32, alignment: .bottomLeading)
    }

    private func merchantRow(_ p: BitrefillBuy.Product) -> some View {
        let name = BitrefillBuy.shortName(p.name)
        return listRow(name, sub: p.packages.isEmpty ? BitrefillBuy.group(of: p).title : p.denominationsLine,
                       mark: name, brand: Self.merchantMark(name), dim: buyProduct?.id == p.id) {
            pick {}
            Task { await chooseProduct(p) }
        }
    }

    /// The mark a merchant wears: its name as Bitrefill writes it (less the
    /// country), else its first word, the company ("Delta Air Lines",
    /// "Target Canada"); a name with neither keeps its letters (prd §1481).
    static func merchantMark(_ name: String) -> String? {
        if let hit = SubscriptionFace.mark(for: name) { return hit }
        guard let first = name.split(separator: " ").first.map(String.init),
              first.count >= 3, first != name else { return nil }
        return SubscriptionFace.mark(for: first)
    }

    static func dedupe(_ products: [BitrefillBuy.Product]) -> [BitrefillBuy.Product] {
        var seen = Set<String>()
        return products.filter { seen.insert($0.id).inserted }
    }

    /// Buy picked: USDC on Base is the payment, the popular list is read,
    /// and the names Casberi knows you pay are matched against it.
    private func enterBuy() {
        inDollars = true
        if network != BitrefillX402.network { switchNetwork(BitrefillX402.network) }
        networkPicked = true
        if with.map({ Self.paysBuy($0, on: network) }) != true {
            with = held.first { Self.paysBuy($0, on: network) }
        }
        spendNames = Self.spendNames()
        guard popular.isEmpty, let account = buyAccount else { return }
        Task { @MainActor in
            buyReading = true
            defer { buyReading = false }
            do {
                popular = try await BitrefillX402.search("", account: account)
                // A place not among the popular is searched by name, a few.
                let unmatched = spendNames.filter { BitrefillBuy.whereYouSpend([$0], in: popular).isEmpty }.prefix(4)
                for name in unmatched {
                    let key = BitrefillBuy.stem(name)
                    guard key.count >= 3, let hits = try? await BitrefillX402.search(key, account: account) else { continue }
                    foundProducts = Self.dedupe(foundProducts + hits)
                }
            } catch let failure as Chain.Failure {
                say(failure.message, failure: true, seconds: 6, from: failure.from)
            } catch {}
        }
    }

    /// Spending's places, the subscriptions, and what was bought here before.
    static func spendNames() -> [String] {
        var names = SpendingReading.shared.reading.places.map(\.name)
        names += SubscriptionsReading.shared.items.map(\.name)
        if let context = SharedStore.live?.mainContext {
            names += IngestSupport.thingsByRef(context, source: "Bitrefill").values
                .filter { $0.isLive && BitrefillFetch.isOrderRef($0.sourceRef) }
                .sorted { $0.capturedAt > $1.capturedAt }
                .compactMap(\.transferCounterparty)
        }
        var seen = Set<String>()
        return names.filter { seen.insert(BitrefillBuy.stem($0)).inserted }
    }

    /// A group's seed searches, once, so the list is more than the popular
    /// cards that happen to fall in it.
    private func seedGroup(_ g: BitrefillBuy.Group) async {
        guard let account = buyAccount else { return }
        for word in g.searches {
            guard let hits = try? await BitrefillX402.search(word, account: account) else { continue }
            foundProducts = Self.dedupe(foundProducts + hits)
        }
    }

    /// Typing in the merchant list asks Bitrefill after a pause.
    private func searchMerchants() async {
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2, let account = buyAccount else { return }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        buyReading = true
        defer { buyReading = false }
        guard let hits = try? await BitrefillX402.search(text, account: account), !Task.isCancelled else { return }
        foundProducts = Self.dedupe(foundProducts + hits)
    }

    /// A merchant picked: its group follows, its packages are read, and the
    /// amount opens on a value it sells.
    private func chooseProduct(_ p: BitrefillBuy.Product) async {
        withAnimation(DS.Motion.standard) {
            buyProduct = p
            buyGroup = BitrefillBuy.group(of: p)
        }
        guard let account = buyAccount else { return }
        if let full = try? await BitrefillX402.detail(p, account: account) {
            withAnimation(DS.Motion.standard) { buyProduct = full }
            foundProducts = foundProducts.map { $0.id == full.id ? full : $0 }
            popular = popular.map { $0.id == full.id ? full : $0 }
            let typed = buyValue
            if typed.map({ full.package(for: $0) == nil }) ?? true, let v = full.suggestedValue {
                amount = BitrefillBuy.Product.valueText(v)
            }
        }
    }

    private var buyValue: Double? { Double(amount.replacingOccurrences(of: ",", with: ".")) }

    /// The USDC the card costs, in base units, once the detail priced it.
    private var buyPackage: BitrefillBuy.Product.Package? {
        guard let p = buyProduct, let v = buyValue else { return nil }
        return p.package(for: v)
    }

    private var buyReady: Bool {
        guard verb == .buy, let with, Self.paysBuy(with, on: network), let package = buyPackage,
              let cost = Op.baseUnits(BitrefillBuy.Product.valueText(package.price), decimals: with.token.decimals) else { return false }
        return Op.atMost(cost, left(with))
    }

    /// Why Buy is grey, in a sentence.
    private var buyMissing: String? {
        guard verb == .buy else { return nil }
        if !buyAvailable { return String(localized: "Make your account first") }
        if with == nil {
            if held.isEmpty && heldBy.isEmpty { return String(localized: "Reading…") }
            return unread.contains(Op.base.chainId) ? String(localized: "Couldn't read Base") : String(localized: "You have no USDC on Base")
        }
        if buyProduct == nil { return String(localized: "Pick a merchant") }
        if let p = buyProduct, let v = buyValue, let why = p.refusal(v) { return why }
        if amount.isEmpty { return String(localized: "Type an amount first") }
        if !buyReady { return String(localized: "More than you have") }
        return nil
    }

    /// "Costs $52.50 · you have 312.40 USDC": what the card costs, and what
    /// is there to pay it.
    private var buyPrint: [String] {
        var parts: [String] = []
        if let package = buyPackage, let p = buyProduct {
            parts.append(String(localized: "Costs \(BitrefillBuy.money(package.price, currency: package.currency))"))
            if p.needsPhoneNumber { parts.append(String(localized: "needs a phone number")) }
        }
        if let with { parts.append(String(localized: "you have \(Op.spoken(left(with), decimals: with.token.decimals)) \(with.token.symbol)")) }
        return parts
    }

    /// **BUY (prd §1473).** The invoice is created only now, never while
    /// browsing; the account signs the USDC authorization at Face ID; then
    /// Bitrefill delivers and the card lands in Wallet.
    private func buyNow() {
        guard stage == nil, let product = buyProduct, let value = buyValue, let package = buyPackage,
              let account = buyAccount, buyReady else {
            if let buyMissing { say(buyMissing) }
            return
        }
        guard !product.needsPhoneNumber else {
            say(String(localized: "Top-ups need a phone number: a later pass"), failure: true)
            return
        }
        let spoken = Op.spoken(Op.baseUnits(BitrefillBuy.Product.valueText(package.price), decimals: 6) ?? "0", decimals: 6)
        let reason = BitrefillBuy.faceWords(spoken: spoken, value: product.money(value), product: product)
        let net = network
        let roundUp = roundUpPlan
        stage = .preparing
        delivering = false
        Task { @MainActor in
            do {
                let invoice = try await BitrefillX402.buy(product: product, value: value, account: account, reason: reason) { s in
                    await MainActor.run { stage = s }
                }
                stage = .landing
                delivering = true
                // Paid: its change is counted, bought by a later send (prd §1561).
                if let roundUp { RoundUps.setSaved(RoundUps.savedAfter(roundUp, bought: false), on: net.chainId) }
                chrome.refreshRooms()
                let standing = await BitrefillX402.awaitDelivery(invoiceID: invoice.id, account: account)
                let landed = BitrefillX402.land(invoice: invoice, product: product, value: value, delivered: standing?.delivered == true)
                stage = nil
                delivering = false
                let made = Self.buyReceipt(product: product, value: value, invoice: invoice, net: net,
                                           delivered: standing?.delivered == true, failed: standing?.failed == true, landed: landed)
                withAnimation(DS.Motion.standard) {
                    amount = ""
                    buyProduct = nil
                    receipt = made
                }
                DSHaptic.success()
                chrome.rain(sources: ["Wallet"])
                await readNetwork()
            } catch let failure as Chain.Failure {
                stage = nil
                delivering = false
                #if DEBUG
                NSLog("moveBuy: failed %@", failure.message)
                #endif
                say(failure.message, failure: true, seconds: 6, from: failure.from)
            } catch {
                stage = nil
                delivering = false
                #if DEBUG
                NSLog("moveBuy: not paid %@", String(describing: error))
                #endif
                say(String(localized: "Not paid"), failure: true)
            }
        }
    }

    /// "Bought a $50 Delta gift card with 52.50 USDC on Base." and where it is.
    static func buyReceipt(product: BitrefillBuy.Product, value: Double, invoice: BitrefillBuy.Invoice, net: Op.Network,
                           delivered: Bool, failed: Bool, landed: Thing?) -> Receipt {
        typealias Line = Receipt.Line
        let name = BitrefillBuy.shortName(product.name)
        let lines = [Line(glue: nil, text: String(localized: "a \(product.money(value)) \(name) \(product.noun)")),
                     Line(glue: String(localized: "with"), text: Op.spoken(invoice.priceUnits, decimals: 6) + " USDC"),
                     Line(glue: String(localized: "on"), text: net.name + ".")]
        let detail = failed ? String(localized: "Bitrefill could not deliver it · it will refund the wallet that paid")
            : delivered ? String(localized: "Delivered · in Wallet")
            : String(localized: "Paid · Bitrefill is still delivering · it lands in Wallet")
        return Receipt(past: String(localized: "Bought"), lines: lines, detail: detail,
                       link: landed.map { URL(string: "casberi://thing/\($0.id.uuidString)") } ?? nil,
                       linkName: landed == nil ? nil : "Wallet",
                       linkTitle: landed == nil ? nil : String(localized: "Open the \(product.noun)"))
    }

    // MARK: - DEBUG drafts

    #if DEBUG
    /// `-moveSwapDraft "<amount>|<SELL>[|<BUY>]"` and `-moveSendDraft
    /// "<amount>|<to>"`: the sentence filled, because a `simctl`-booted
    /// simulator drops typed characters (prd §1424, §1438). Both given: the
    /// swap is Added once the pools price it, and the send fills the next sentence.
    private func draft() {
        let d = UserDefaults.standard
        // `-moveWarnProbe first|lookalike|scam|sanctioned|newContract|fails`
        // (prd §1513): a sentence that draws that warning, off the demo's
        // table (or OFAC's first address); logs `moveWarn|` once checked.
        if let probe = d.string(forKey: "moveWarnProbe"), !probe.isEmpty {
            if probe == "newContract" {
                swapDraft("50|USDC|PEPE2")
            } else {
                let to: String = switch probe {
                case "lookalike": YourAccountDemo.imitator
                case "scam": YourAccountDemo.reported
                case "fails": YourAccountDemo.refusing
                case "sanctioned": MoveChecks.sanctions()?.addresses.sorted().first ?? YourAccountDemo.stranger
                default: YourAccountDemo.stranger
                }
                verb = .send
                sendDraft("5|\(to)|USDC")
            }
            NSLog("moveWarnProbe: %@", probe)
        } else if let swap = d.string(forKey: "moveSwapDraft"), !swap.isEmpty {
            swapDraft(swap)
        } else if d.string(forKey: "moveSendDraft")?.isEmpty == false {
            verb = .send
            sendDraft()
        } else if let from = d.string(forKey: "moveReceiveFrom"), !from.isEmpty {
            verb = .receive
            receiveDraft(from)
        } else if let buyDraft = d.string(forKey: "moveBuyDraft"), !buyDraft.isEmpty {
            verb = .buy
            self.buyDraft(buyDraft)
        } else if let sweep = d.string(forKey: "moveSweepDraft"), !sweep.isEmpty {
            // `-moveSweepDraft YES|1|5[@<network>]` (prd §1537): Sweep on
            // Base, or the named network, at that line; logs `moveSweep|`
            // once the pools have priced it.
            verb = .sweep
            let parts = sweep.split(separator: "@", maxSplits: 1).map(String.init)
            if let under = Int(parts[0]), DustSweep.choices.contains(under) { sweepUnder = under }
            let named = parts.count > 1 ? Op.networks.first { $0.name.lowercased() == parts[1].lowercased() } : nil
            switchNetwork(named ?? Op.base)
            open = nil
            NSLog("moveSweepDraft: under=%d", sweepUnder)
        }
        // `-moveDetails YES|raw` (prd §1509): Details open, or Raw
        // transaction, once the draft has settled its verb.
        if let shown = d.string(forKey: "moveDetails"), !shown.isEmpty {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                details = true
                if shown == "raw" { rawOpen = true }
                NSLog("moveDetails: %@ preview=%@", shown, shownPreview == nil ? "reading" : "ready")
            }
        }
    }

    private func swapDraft(_ swap: String) {
        let parts = swap.split(separator: "|").map(String.init)
        verb = .swap
        networkPicked = true
        if parts.count > 1, let h = held.first(where: { $0.token.symbol == parts[1] }) { with = h }
        // "<BUY>@<Network>": the token arrives on another network (prd §1555).
        let target = parts.count > 2 ? parts[2].split(separator: "@", maxSplits: 1).map(String.init) : []
        let buyName = target.first ?? (with?.token.symbol == "ETH" ? "USDC" : "ETH")
        buyOn = target.count > 1 ? Op.networks.first { $0.name.lowercased() == target[1].lowercased() } : nil
        // The list's own entry first; one it does not carry only by name.
        buy = listed.first { $0.token.symbol == buyName && $0.onList }
            ?? listed.first { $0.token.symbol == buyName }
            ?? held.first { $0.token.symbol == buyName }.map { Tokens.Listed(token: $0.token, name: $0.token.symbol, onList: true) }
        // On another network the token is that network's (prd §1566), read off its list.
        if let on = buyOn, on != network {
            let from = network
            let mine = buy
            buy = mine.flatMap { equivalent($0.token, from: from, to: on) }
            Task { @MainActor in
                if listedBy[on.chainId] == nil { listedBy[on.chainId] = await Tokens.list(on) }
                let list = listedBy[on.chainId] ?? []
                if buy == nil || buy?.token.symbol != buyName {
                    buy = mine.flatMap { equivalent($0.token, from: from, to: on) }.flatMap { $0.token.symbol == buyName ? $0 : nil }
                        ?? list.first { $0.token.symbol == buyName && $0.onList } ?? list.first { $0.token.symbol == buyName }
                }
                NSLog("moveSwapDraft: %@ arrives as %@ (%@)", on.name, buy?.token.symbol ?? "-", buy?.token.contract ?? "ETH")
            }
        }
        amount = parts.first ?? ""
        inDollars = false
        NSLog("moveSwapDraft: %@ %@ for %@ on %@", amount, with?.token.symbol ?? "-", buy?.token.symbol ?? "-", buyOn?.name ?? network.name)
    }

    /// `-moveRawProbe YES`: what Raw transaction shows, line by line.
    static func logRaw(_ p: Chain.Preview?) {
        guard let p else { NSLog("moveRaw| none"); return }
        let checked: String = switch p.checked {
        case .lands: "lands"
        case .returnsAtLeast(let u, let t): "atLeast \(u) \(t.symbol)"
        case .fails(let call, let token, let reason): "fails call=\(call.map(String.init) ?? "-") token=\(token ?? "-") \(reason ?? "-")"
        case .notChecked: "notChecked"
        }
        NSLog("moveRaw| route=%@ nonce=%@ fee=%@ checked=%@", String(describing: p.route), p.nonce.map { String($0) } ?? "-",
              p.feeWei ?? "-", checked)
        NSLog("moveRaw| %@=%@ bytes=%d digest=%@ refusal=%@", p.hashKind.label, p.hash.map(YourAccountPreview.hex) ?? "-",
              p.callData.count, YourAccountPreview.hex(YourAccountPreview.calldataDigest(p.callData)), p.refusal ?? "-")
        for (n, step) in p.words.enumerated() {
            NSLog("moveRaw| %d %@%@", n + 1, step.words, step.detail.map { " — " + $0 } ?? "")
        }
    }

    /// `-moveBuyDraft "<merchant>[|<amount>]"`: Buy filled, because no
    /// headless run can make the taps (prd §1473). Logs `moveBuyDraft:`.
    private func buyDraft(_ draft: String) {
        let parts = draft.split(separator: "|").map(String.init)
        Task { @MainActor in
            for _ in 0..<60 where popular.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
            let name = parts.first ?? ""
            var pool = popular + foundProducts
            if BitrefillBuy.search(name, in: pool).isEmpty, let account = YourAccountKey.address ?? (BitrefillX402.sample ? "0x0" : nil) {
                pool += (try? await BitrefillX402.search(name, account: account)) ?? []
            }
            guard let product = BitrefillBuy.search(name, in: pool).first else {
                NSLog("moveBuyDraft: nothing named %@ among %d", name, pool.count); return
            }
            await chooseProduct(product)
            if parts.count > 1, !parts[1].isEmpty { amount = parts[1] }
            // A third part opens a list: `group` or `merchant`.
            if parts.count > 2 { open = parts[2] == "group" ? .group : .merchant }
            NSLog("moveBuyDraft: %@ %@ for %@ at %@ ready=%d missing=%@", amount, buyProduct?.noun ?? "-",
                  buyGroup?.title ?? "-", buyProduct?.name ?? "-", buyReady ? 1 : 0, buyMissing ?? "-")
        }
    }

    /// `-moveReceiveFrom "<Network>[|<COIN>[|<ARRIVES>]]"`: Receive from
    /// another network with the route taken (prd §1470) — "Arbitrum|USDT",
    /// "Polygon|USDT|ETH" — because no headless run can make the taps. Logs
    /// `moveReceiveFrom:` with the route or the refusal.
    private func receiveDraft(_ draft: String) {
        let parts = draft.split(separator: "|").map(String.init)
        Task {
            let nets = await YourAccountElsewhere.networks()
            guard let net = nets.first(where: { $0.name.caseInsensitiveCompare(parts[0]) == .orderedSame }) else {
                NSLog("moveReceiveFrom: no network named %@ among %d", parts[0], nets.count); return
            }
            elsewhereNetworks = nets
            let coin = parts.count > 1 ? net.coins.first { $0.symbol.caseInsensitiveCompare(parts[1]) == .orderedSame } : net.coin(like: nil)
            if parts.count > 2 {
                let to = network.isTest ? Op.base : network
                let list = await Tokens.list(to)
                elsewhereArrives = list.first { $0.token.symbol.caseInsensitiveCompare(parts[2]) == .orderedSame }?.token
            }
            NSLog("moveReceiveFrom: %@ coins=%@ coin=%@ arrives=%@", net.name, net.coins.map(\.symbol).joined(separator: ","),
                  coin?.symbol ?? "-", elsewhereArrives?.symbol ?? "default")
            takeRoute(from: net, token: coin)
        }
    }

    /// Lines are `;`-separated, each `<amount>|<to>[|<SYM>]`; every line but
    /// the last is Added once its recipient resolves.
    private func sendDraft(_ given: String? = nil) {
        guard let draft = given ?? UserDefaults.standard.string(forKey: "moveSendDraft"), !draft.isEmpty else { return }
        let lines = draft.split(separator: ";").map { $0.split(separator: "|").map(String.init) }
        networkPicked = true
        Task { @MainActor in
            for (n, parts) in lines.enumerated() {
                if parts.count > 2, let h = held.first(where: { $0.token.symbol == parts[2] }) { with = h }
                if with == nil { with = held.first }
                amount = parts.first ?? ""
                inDollars = false
                to = parts.count > 1 ? parts[1] : ""
                NSLog("moveSendDraft: amount=%@ %@ to=%@", amount, with?.token.symbol ?? "-", to)
                guard n < lines.count - 1 else { break }
                for _ in 0..<50 where pendingItem == nil { try? await Task.sleep(for: .milliseconds(100)) }
                add()
                NSLog("moveSendDraft: added, %d in the transaction, to %@", items.count, resolved?.name ?? "-")
            }
        }
    }

    private func draftAddsTheSwap() {
        guard !drafted, UserDefaults.standard.string(forKey: "moveSwapDraft")?.isEmpty == false,
              UserDefaults.standard.string(forKey: "moveSendDraft")?.isEmpty == false else { return }
        drafted = true
        add()
        verb = .send
        sendDraft()
        NSLog("moveSwapDraft: added, %d in the transaction", items.count)
    }
    #endif
}

// MARK: - The running sentence's parts (prd §1466)

/// **ONE SIZE, ALWAYS (prd §1501, retiring §1479's pick-by-fit; user: "it
/// can go on more than one row"; "same for move it should be same size
/// regardless").** Every Move sentence and every screen of the create flow
/// is `heading52`. A clause that fits the line it would start keeps to it;
/// one that does not hops to the next line whole, as §1466 ruled; and a
/// clause wider than a whole line — "in iCloud Keychain.", "Round up each
/// move" — wraps inside itself (`MoveClauseLayout`), so nothing steps the
/// sentence down to make it fit. A single word wider than a line shrinks,
/// that word alone (measured: the widest Move draws, "1,234,567.89", is
/// 304pt of the phone's 348).
struct MoveFlow<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        FlowLayout(spacing: MoveSentence.clauseGap, lineSpacing: 0, breakGap: DS.Space.s4, fitsWide: true) { content() }
            .environment(\.moveRung, MoveSentence.rung)
    }
}

/// The rung the sentence is drawn at, set by `MoveFlow`; the floor outside one.
private struct MoveRungKey: EnvironmentKey {
    static let defaultValue: DSTextStyle = .heading34
}

extension EnvironmentValues {
    var moveRung: DSTextStyle {
        get { self[MoveRungKey.self] }
        set { self[MoveRungKey.self] = newValue }
    }
}

/// A field or a glyph that must wear the sentence's size reads it here.
struct MoveRungReader<Content: View>: View {
    @Environment(\.moveRung) private var rung
    @ViewBuilder let content: (DSTextStyle) -> Content
    var body: some View { content(rung) }
}

/// A clause's pieces in one line when they fit the width offered, wrapped
/// inside it when they do not (prd §1501). Asked for its size with no width,
/// it answers with its one-line width, so the outer flow sees a clause as one
/// piece until the clause is wider than a whole line.
struct MoveClauseLayout: Layout {
    var spacing: CGFloat
    /// Less than a pixel: a piece measured to fit exactly still fits when
    /// a parent hands back its width rounded.
    static let slack: CGFloat = 0.5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        rows(proposal.width, subviews).size
    }

    /// Placed against the PROPOSAL it was measured for, never `bounds.width`:
    /// the bounds come back rounded to the pixel grid, a hair narrower, and
    /// a clause measured as one line then wrapped its last word under itself
    /// onto the next clause's line ("ETH" over "on Base.", prd §1511).
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, frame) in rows(proposal.width, subviews).frames {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                       anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func rows(_ width: CGFloat?, _ subviews: Subviews) -> (size: CGSize, frames: [(LayoutSubview, CGRect)]) {
        let limit = width ?? .infinity
        var frames: [(LayoutSubview, CGRect)] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            var size = view.sizeThatFits(.unspecified)
            // A piece wider than the whole line is offered the line: a word
            // shrinks, a phrase wraps.
            if size.width > limit + Self.slack { size = view.sizeThatFits(ProposedViewSize(width: limit, height: nil)) }
            if x > 0, x + size.width > limit + Self.slack {
                x = 0; y += rowH; rowH = 0
            }
            frames.append((view, CGRect(x: x, y: y, width: size.width, height: size.height)))
            widest = max(widest, x + size.width)
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return (CGSize(width: widest, height: y + rowH), frames)
    }
}

/// One word or phrase of the sentence, at the sentence's size; digits roll.
/// A phrase is its words, so a phrase wider than a line can wrap between
/// them (prd §1501); VoiceOver reads it as one phrase.
struct MoveWord: View {
    let text: String
    var ink: Color = DS.textPrimary
    @Environment(\.moveRung) private var rung
    init(_ text: String, ink: Color = DS.textPrimary) { self.text = text; self.ink = ink }
    var body: some View {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        if words.count > 1 {
            MoveClauseLayout(spacing: rung.size * MoveSentence.wordSpace) {
                ForEach(Array(words.enumerated()), id: \.offset) { _, word in piece(word) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: text))
        } else {
            piece(text)
        }
    }

    private func piece(_ word: String) -> some View {
        Text(verbatim: word)
            .dsText(rung)
            .foregroundStyle(ink)
            .monospacedDigit()
            .contentTransition(.numericText())
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

/// One clause: its small word (white, the sentence's), then its value, and
/// a comma when a list needs one — one piece that keeps to one line, and
/// wraps inside itself only when it is wider than a whole line (§1501).
struct MoveClause<Value: View>: View {
    var glue: String? = nil
    var glueInk: Color = DS.textPrimary
    var trail: String? = nil
    @ViewBuilder let value: () -> Value
    var body: some View {
        MoveClauseLayout(spacing: MoveSentence.clauseGap) {
            if let glue { MoveWord(glue, ink: glueInk) }
            if let trail {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    value()
                    MoveWord(trail)
                }
            } else {
                value()
            }
        }
    }
}

/// A phrase as clauses: split at its commas (each kept on its piece), an
/// "and" or "or" riding the piece after it, so a line never ends on one.
struct MovePhrase: View {
    let text: String
    var glue: String? = nil
    var glueInk: Color = DS.textPrimary
    var ink: Color = DS.textPrimary
    /// Starts a new line: a second sentence's first piece (prd §1494).
    var breaks = false
    init(_ text: String, glue: String? = nil, glueInk: Color = DS.textPrimary, ink: Color = DS.textPrimary,
         breaks: Bool = false) {
        self.text = text; self.glue = glue; self.glueInk = glueInk; self.ink = ink; self.breaks = breaks
    }
    var body: some View {
        let pieces = Self.pieces(text)
        ForEach(Array(pieces.enumerated()), id: \.offset) { i, piece in
            MoveClause(glue: i == 0 ? (glue ?? piece.glue) : piece.glue, glueInk: i == 0 ? glueInk : ink) {
                MoveWord(piece.words, ink: ink)
            }
            .layoutValue(key: FlowBreak.self, value: breaks && i == 0)
        }
    }

    static func pieces(_ text: String) -> [(glue: String?, words: String)] {
        let raw = text.components(separatedBy: ", ")
        return raw.enumerated().map { i, part in
            let piece = i < raw.count - 1 ? part + "," : part
            for word in [String(localized: "and"), String(localized: "or")] where piece.hasPrefix(word + " ") {
                return (word, String(piece.dropFirst(word.count + 1)))
            }
            return (nil, piece)
        }
    }
}
