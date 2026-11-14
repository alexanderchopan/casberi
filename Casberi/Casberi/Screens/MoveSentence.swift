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
/// The foot holds two words: the
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
         privately: PrivateMove.Mode? = nil, receivePrivately: Bool = false, lending: LendMove.Mode? = nil,
         aztecPrivately: AztecMove.Mode? = nil, railgunPrivately: RailgunMove.Opening? = nil) {
        self.account = account
        self.inTray = inTray
        self.arrival = arrival
        let mode = PrivateMove.available ? privately : nil
        // Holdings' Aztec placeholder opens Send onto your private account
        // on Aztec (prd §1718), as `privately` opens it onto Privacy Pools.
        let aztec = AztecProver.isAvailable && mode == nil ? aztecPrivately : nil
        // A Railgun row in Holdings opens Send onto taking it back (prd §1721).
        let railgun = RailgunPocket.available && mode == nil && aztec == nil ? railgunPrivately : nil
        let toFresh = PrivateMove.freshAvailable && receivePrivately && mode == nil && aztec == nil && railgun == nil
        let lends = AaveLend.on && lending != nil && mode == nil && aztec == nil && railgun == nil && !toFresh
        _verb = State(initialValue: mode != nil || aztec != nil || railgun != nil ? .send : toFresh ? .receive : lends ? .lend : opening ?? (arrival == nil ? .swap : .receive))
        _lendMove = State(initialValue: LendMove(mode: lending ?? .lend, opens: lends))
        _freshReceive = State(initialValue: toFresh)
        _fresh = State(initialValue: arrival != nil)
        _privateMode = State(initialValue: mode)
        _privateMove = State(initialValue: PrivateMove(mode: mode ?? .deposit))
        _aztecMode = State(initialValue: aztec)
        // A send still going, or failed, behind its sheet is the sentence
        // Move opens on (prd §1777).
        let aztecMove = (aztec == .send ? AztecMove.kept : nil) ?? AztecMove()
        aztecMove.mode = aztec ?? .deposit
        _aztecMove = State(initialValue: aztecMove)
        let railgunMove = RailgunMove()
        railgunMove.mode = railgun?.takeBack == true ? .takeBack : .deposit
        railgunMove.wanted = railgun?.contract
        railgunMove.recipient = railgun?.recipient
        _railgunMove = State(initialValue: railgunMove)
        _railgunOpen = State(initialValue: railgun != nil)
        picksUpDraft = mode == nil && aztec == nil && railgun == nil && !toFresh && opening == nil && arrival == nil && !lends
    }

    /// **LEND (prd §1674): a verb.** Picked, `MoveLendSentence` draws under
    /// these verbs over the account's sentence, which stays as it was.
    @State private var lendMove: LendMove

    /// **SEND, PRIVATELY (prd §1554): a recipient and a switch, never a
    /// verb.** "Your private balance" leads Send's recipients (`.deposit`);
    /// the Private switch under any other recipient sends from it (`.send`).
    /// Either draws `MovePrivateSentence` under these verbs, over the
    /// account's sentence, which stays as it was. Never remembered on.
    @State private var privateMode: PrivateMove.Mode?
    /// Your private balance on Aztec, in (`.deposit`) or from (`.send`): its
    /// own sentence, as 0xBow's is (prd §1700f items 11–14).
    @State private var aztecMode: AztecMove.Mode?
    @State private var aztecMove: AztecMove
    @State private var privateMove = PrivateMove()

    /// **RECEIVE, PRIVATELY (prd §1560): a fresh address.** Receive's Private
    /// switch draws `MoveFreshSentence` under these verbs, over the
    /// account's sentence. Off on every arrival, never remembered on.
    @State private var freshReceive = false
    /// Receive to your private balance on Aztec: your Aztec address (prd §1719).
    @State private var aztecReceive = false
    /// Your private balance on Ethereum for any token but ETH and USDC:
    /// Railgun's sentence, in or back (prd §1713, §1721).
    @State private var railgunOpen = false
    @State private var railgunMove: RailgunMove

    /// `recipient`: out to someone else through a broadcaster (prd §1721
    /// item 3); nil or your own account is taking it back.
    private func goRailgun(_ mode: RailgunMove.Mode, contract: String?, recipient: String? = nil) {
        railgunMove.mode = mode
        railgunMove.wanted = contract
        railgunMove.recipient = mode == .takeBack ? recipient : nil
        withAnimation(DS.Motion.standard) { open = nil; railgunOpen = true }
        DSHaptic.selection()
        Task { await railgunMove.read() }
    }

    private func goPrivate(_ mode: PrivateMove.Mode) {
        privateMove.mode = mode
        privateMove.recipient = mode == .send ? resolved?.address : nil
        withAnimation(DS.Motion.standard) { open = nil; privateMode = mode }
        DSHaptic.selection()
    }

    /// Into your private balance on Aztec, or from it to `recipient`.
    private func goAztec(_ mode: AztecMove.Mode, recipient: String? = nil) {
        if mode == .send, let kept = AztecMove.kept {
            // The one behind its sheet, as it stands (prd §1777).
            aztecMove = kept
        } else {
            aztecMove.mode = mode
            aztecMove.recipient = mode == .send ? recipient : nil
        }
        withAnimation(DS.Motion.standard) { open = nil; aztecMode = mode }
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

    /// `buy` is Bitrefill's gift cards, drawn **Spend**; `deposit` is a card
    /// buying crypto, drawn **Buy** (prd §1599: money in is Buy, money out
    /// is Spend). The cases keep their first names.
    enum Verb: CaseIterable { case swap, send, receive, buy, sweep, deposit, lend }
    enum Blank: Equatable { case verb, with, buy, to, network, destination, elsewhere, elsewhereCoin, arrives, group, merchant, depositCoin, depositNetwork, when, until, from, amount }
    enum Field: Hashable { case amount, search, to, price }

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
    /// Across's "about N seconds" for the move being watched, counted
    /// against on the receipt (prd §1586).
    @State private var crossingSeconds: Int?
    /// The receipt the watched move wrote: the count goes on that one only.
    @State private var crossingReceipt: UUID?
    /// The address the receipt's "Name …a3f1" is naming, and the name typed.
    @State private var naming: String?
    @State private var nameDraft = ""
    /// The pairs priced once this visit: the first price lands with a tick.
    @State private var pricedPairs: Set<String> = []
    /// The figure For showed before a re-price, kept breathing until the
    /// new one lands so the sentence never re-wraps mid-slide (prd §1586).
    @State private var staleBack: (id: String, text: String)?
    /// Who To held when it opened: opening it to look and closing it again
    /// gives them back (prd §1586).
    @State private var toBefore: (text: String, resolved: Recipient?)?
    /// To's Paste put the field's text there: once it resolves, the list
    /// closes on its own.
    @State private var pastedTo = false
    /// The clipboard looks like it holds a link (prd §1752): asked of the
    /// system as a pattern, never read, so nothing is taken before the tap.
    @State private var clipboardLink = false
    /// The last people this account sent to, newest first (prd §1752).
    @State private var recentTo: [String] = []
    @State private var people: [ToPerson] = []
    /// A name in To being asked of its resolver, or one none answered for:
    /// said under the sentence, never a grey word left to guess (prd §1586).
    enum Lookup: Equatable { case looking(String), missing(String), refused(String) }
    @State private var lookup: Lookup?
    /// **PAY A zk.money TAG (prd §1692).** The deposit addresses zk.money's
    /// resolver proved for a tag this visit, lowercased: each is single-use
    /// (a second payment to one is marked recoverable and never arrives), so
    /// one a kept or sent line took is `zkMoneyUsed`, and To asks for a
    /// fresh one (`zkMoneyFresh` re-runs `resolve`).
    @State private var zkMoneyDeposits: Set<String> = []
    @State private var zkMoneyUsed: Set<String> = []
    @State private var zkMoneyFresh = 0
    @State private var amount = ""
    /// Dollars first (§1442a, user: "user may want to say a dollar value
    /// before they choose token"): the amount can be typed before anything
    /// is picked, and the token it buys is worked out once one is.
    @State private var inDollars = true
    @State private var to = ""
    @State private var resolved: Recipient?
    @State private var malformed = false
    @State private var open: Blank?
    /// A pick just closed its list (prd §1782): the next row still to be
    /// filled opens by itself, once. A list closed by hand sets nothing.
    @State private var advances = false
    /// A row's menu is on screen (prd §1784).
    @State private var menuUp = false
    @State private var search = ""
    @State private var pasted: [Int: Tokens.Listed] = [:]
    @State private var items: [Chain.Item] = []
    /// Where the line being filled stands among the kept swaps (§1442g): a
    /// kept line tapped to edit takes its own place, not the bottom.
    @State private var slot = 0
    @State private var quote: YourAccountSwap.Quote?
    @State private var quoteNote: String?
    /// The swap a zk.money tag's payment makes first (prd §1768): what you
    /// send, into USDC, in the same transaction.
    @State private var tagSwap: YourAccountSwap.Quote?
    @State private var tagSwapNote: String?
    /// Whose words `quoteNote` is, drawn as its mark (§1442n), when they are
    /// a service's rather than the app's.
    @State private var quoteFrom: String?
    @State private var stage: Chain.Stage?
    /// Face ID, asked at the tap, has passed (prd §1687): the foot no longer
    /// says "Confirm with Face ID" once preparing is done.
    @State private var faceIDPassed = false
    /// Which send `faceIDPassed` is about: a Face ID answering late for a
    /// send that already ended never marks the next one.
    @State private var faceIDSend: UUID?
    /// Where this send's time is going, from the tap (prd §1602), and its
    /// requests (prd §1605).
    @State private var clock: MoveClock?
    @State private var trips: IngestSupport.TripLog?
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
    struct Hint: Equatable {
        let text: String; let failure: Bool; var from: String? = nil
        /// A refusal with a way forward carries its door (prd §1586):
        /// over the limit with no co-signer opens Your account's keys.
        var opensKeys = false
        let id = UUID()
    }
    @State private var hint: Hint?

    // MARK: - When (prd §1673)

    /// Swap's last word: Now, or a price CoW fills at. Nothing is signed
    /// until it is answered, and it is answered for one pair of tokens on
    /// one network (`whenFor`): another pair asks again.
    enum WhenPick: Equatable { case now, price }
    @State private var whenPick: WhenPick?
    @State private var whenFor = ""
    /// The price typed, in dollars, or the percent from today's when
    /// `priceInPercent` (the grey line's pink figure and the list's % | $
    /// trade them). Percent first, as the presets are (prd §1683).
    @State private var priceText = ""
    @State private var priceInPercent = true
    /// The priced token's dollars now, and the sold one's when neither is a
    /// dollar (the rate a price for the bought token is turned into).
    @State private var nowPrice: Double?
    @State private var sellDollars: Double?
    /// The order a receipt is following, until it fills, expires or is cancelled.
    @State private var orderShown: YourAccountOrders.Placed?
    /// How long the order waits to fill: a week unless "Until" is changed
    /// (prd §1673 item 5).
    @State private var orderSeconds: UInt32 = YourAccountOrder.defaultSeconds
    #if DEBUG
    @State private var whenDraftPending: String?
    #endif

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
    /// What a card buys on Buy (prd §1599).
    @State private var depositCoin: CardOnramp.Coin = .usdc
    @State private var buyGroup: BitrefillBuy.Group?
    @State private var buyProduct: BitrefillBuy.Product?
    /// Bitrefill's 25 most popular in the country, read once per visit.
    @State private var popular: [BitrefillBuy.Product] = []
    /// What searches found: a group's seed words, a typed word, a place's name.
    @State private var foundProducts: [BitrefillBuy.Product] = []
    @State private var buyReading = false
    /// Why the catalogue could not be read (the sign-in refused, the account
    /// not on Base, Bitrefill silent), drawn in the merchant list in place of
    /// "Nothing here yet", with Try again; nil once a read answers.
    @State private var buyFailure: String?
    /// The popular read in flight, so a category's seed searches wait on its
    /// sign-in instead of starting a second one.
    @State private var catalogueRead: Task<Void, Never>?
    /// The names Casberi already knows you pay: Spending's places,
    /// Subscriptions, what you bought here before.
    @State private var spendNames: [String] = []
    /// After the payment: Bitrefill delivering, said at the foot.
    @State private var delivering = false
    /// Before it: the swap into USDC on Base landing there (prd §1666).
    @State private var toppingUp = false

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
        let h = Hint(text: text, failure: failure, from: from, opensKeys: text == Self.needsCoSigner)
        withAnimation(DS.Motion.standard) { hint = h }
        // A refusal is felt as well as read (prd §1586).
        if failure { DSHaptic.failure() }
        Task {
            // A door stays long enough to be taken.
            try? await Task.sleep(for: .seconds(h.opensKeys ? max(seconds, 12) : seconds))
            if hint?.id == h.id { withAnimation(DS.Motion.standard) { hint = nil } }
        }
    }

    /// The marks a swap's lines wear, by the name the line says (prd §1675).
    /// Sushi has none here, so its line stands on its words.
    static let exchangeMarks: [String: String] = [
        "Uniswap": "brand-uniswap",
        "Aerodrome": "brand-aerodrome",
        "Across": "brand-across",
    ]

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
        } else if service == "Stripe" {
            Image("brand-stripe")
                .resizable()
                .scaledToFill()
                .frame(width: 16, height: 16)
                .clipShape(Circle())
                .accessibilityLabel(Text(verbatim: service))
        } else if service == "CoW Swap" {
            Image("brand-cowswap")
                .resizable()
                .scaledToFill()
                .frame(width: 16, height: 16)
                .clipShape(Circle())
                .accessibilityLabel(Text(verbatim: service))
        } else if let asset = exchangeMarks[service] {
            // The exchanges and Across, on the swap's own lines (prd §1675).
            Image(asset)
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
        } else if let mark = ProtocolMark.mark(forVenue: service), let image = BrandMark.image(for: mark) {
            // Every other protocol whose mark ships (Aave, 0xBow, prd §1685).
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 16, height: 16)
                .clipShape(Circle())
                .accessibilityLabel(Text(verbatim: service))
        }
    }

    private func hintText(_ h: Hint) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                if let from = h.from { Self.mark(of: from) }
                Text(verbatim: h.text)
                    .dsText(.body17)
                    .foregroundStyle(h.failure ? DS.attentionInk : DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if h.opensKeys {
                Button {
                    DSHaptic.selection()
                    chrome.moveTray = false
                    chrome.openYourAccount(at: FeedScreen.SecurityAnchor.account.id)
                } label: {
                    Text("Add a co-signer").dsText(.body17).foregroundStyle(DS.pickInk).frame(minHeight: 44)
                }
                .buttonStyle(RowPress())
            }
        }
        .transition(.opacity)
    }

    /// Over the limit with no co-signer (`spend`): said with a door to it.
    static let needsCoSigner = String(localized: "Add a signer first: over the limit, a send waits on it")

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
        /// Addresses this landed send paid that have no name yet: the
        /// receipt offers to name each (prd §1586).
        var names: [String] = []
        /// The zk.money tags this send paid that are not yet a contact
        /// (prd §1767): each gets a Save row, as an unnamed address gets Name.
        var tags: [String] = []
        /// Which move this receipt is: two alike sentences are two receipts,
        /// and a watch writes only on its own.
        var id = UUID()
    }

    /// **"SWEPT 3 TOKENS FOR 0.0004 ETH ON BASE." (prd §1586).** A sweep's
    /// receipt counts what it took; the tokens are the list it just showed.
    static func swept(_ r: Receipt, count: Int) -> Receipt {
        let back = r.lines.first { $0.glue == String(localized: "for") }
        let on = r.lines.last
        let n = count == 1 ? String(localized: "1 token") : String(localized: "\(count) tokens")
        return Receipt(past: String(localized: "Swept"),
                       lines: [Receipt.Line(glue: nil, text: n)] + [back, on].compactMap { $0 },
                       detail: r.detail, link: r.link, linkName: r.linkName, linkTitle: r.linkTitle)
    }

    /// What Round-ups did with this send, on its receipt (prd §1586, §1690):
    /// "+$0.40 to Round-ups · $6.60 of $10", the change waiting for the next
    /// send when it could not go with this one, and a move into your private
    /// balance. nil when there is nothing to say.
    static func roundUpWords(_ step: RoundUpsPot.Step, setAside: Bool, pot: String, target: String, moved: String?) -> String? {
        var parts: [String] = []
        if step.change != "0" {
            let change = money(RoundUpsPot.dollars(step.change))
            parts.append(setAside
                ? String(localized: "+\(change) to Round-ups · \(money(RoundUpsPot.dollars(pot))) of \(RoundUpsPot.figure(target))")
                : String(localized: "\(change) rounded up, to Round-ups with your next send"))
        }
        if let moved {
            parts.append(String(localized: "\(money(RoundUpsPot.dollars(moved))) of Round-ups moved to your private balance"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The addresses a batch sent to that your book has no name for.
    /// The tags a batch paid that are not saved contacts yet, as `bob.zk.money`.
    static func unsavedTags(_ batch: [Chain.Item]) -> [String] {
        var out: [String] = []
        for item in batch {
            let named: String? = { switch item { case .send(let p): p.toName; case .swap(let s): s.payeeName } }()
            guard let bare = named.flatMap({ ZkMoneyWire.tag($0) }) else { continue }
            let tag = ZkMoneyWire.display(bare)
            if !out.contains(tag), !ContactBook.shared.has(Identity.key(.zkMoney, tag)) { out.append(tag) }
        }
        return out
    }

    /// The tags a batch paid and the one-time address each was paid at, for
    /// Activity to name the person (prd §1767).
    static func paidTags(_ batch: [Chain.Item]) -> [(address: String, tag: String)] {
        batch.compactMap { item in
            switch item {
            case .send(let p):
                guard let name = p.toName, ZkMoneyWire.tag(name) != nil else { return nil }
                return (p.to, name)
            case .swap(let s):
                // Paid from another network (prd §1770).
                guard let to = s.payee, let name = s.payeeName, ZkMoneyWire.tag(name) != nil else { return nil }
                return (to, name)
            }
        }
    }

    static func unnamed(_ batch: [Chain.Item]) -> [String] {
        var out: [String] = []
        for item in batch {
            guard case .send(let p) = item, p.toName == nil, AddressBook.shared.name(for: p.to) == nil,
                  !out.contains(where: { WalletWatch.sameAddress($0, p.to) }) else { continue }
            out.append(p.to)
        }
        return out
    }
    #if DEBUG
    @State private var drafted = false
    #endif

    /// **A SWIPE DOWN IS NOT A CANCEL (prd §1586).** What the tray held when
    /// it closed, picked up by the next open within five minutes: the line
    /// being filled only, since a kept line's quote goes stale.
    struct Draft {
        let verb: Verb
        let network: Op.Network
        let networkPicked: Bool
        let amount: String
        let inDollars: Bool
        let withID: String?
        let buy: Tokens.Listed?
        let buyOn: Op.Network?
        let to: String
        let at: Date
        /// The zk.money request Pay wrote this draft for (prd §1745).
        var request: PayingRequest? = nil
        /// Again (prd §1752): the token a sent row names, by its symbol; it
        /// is matched to one you hold once the holdings land.
        var symbol: String? = nil
        /// The blank that stands open when the sentence appears: Add money's
        /// To, where your private balances lead (prd §1776).
        var opens: Blank? = nil
        /// The sentence Move itself kept when its sheet closed, as against
        /// one a door wrote (Pay, Again, Add money): it comes back under the
        /// verbs, never in place of them (prd §1779).
        var kept = false
    }

    /// **ADD MONEY (prd §1776).** Send with To open, for someone with two
    /// private balances: the list leads with both, told apart by network
    /// (§1719), and one tap picks. With one balance the door goes straight
    /// to its sentence and no draft is written.
    static func privateDraft() -> Draft {
        Draft(verb: .send, network: Op.ethereum, networkPicked: true, amount: "", inDollars: true,
              withID: nil, buy: nil, buyOn: nil, to: "", at: Date(), opens: .to)
    }

    /// **PAY A zk.money REQUEST (prd §1745).** The saved row Pay opened Send
    /// for: its tag in To, the amount asked plus the deposit's fee, the
    /// token asked for. The line says the fee was added while the amount
    /// and To still stand as written; the row is marked paid when a send
    /// to an address resolved for that tag is taken (`settleRequest`).
    struct PayingRequest: Equatable {
        /// The saved row, when Pay opened this; nil for a link pasted into To.
        let thing: UUID?
        let to: String
        let amount: String
        /// "20.5 DAI"; nil when the request named no amount, so nothing was added.
        let asked: String?
    }

    /// Send written for a saved request: on Ethereum, in the token's own
    /// units. A short link's row hands its link to To, which reads it there
    /// (prd §1748).
    static func payDraft(_ payable: ZkMoney.Payable, thing: UUID) -> Draft {
        switch payable {
        case .written(let pay, let symbol):
            return Draft(verb: .send, network: Op.ethereum, networkPicked: true, amount: pay.amount, inDollars: pay.token == nil,
                         withID: pay.token, buy: nil, buyOn: nil, to: pay.to, at: Date(),
                         request: paying(pay, symbol: symbol, thing: thing))
        case .link(let url):
            return Draft(verb: .send, network: Op.ethereum, networkPicked: true, amount: "", inDollars: true,
                         withID: nil, buy: nil, buyOn: nil, to: url, at: Date(),
                         request: PayingRequest(thing: thing, to: "", amount: "", asked: nil))
        }
    }

    /// "20.5 DAI", or "$0.01" for a request that names no token: that one is
    /// written in dollars and you pick which token pays.
    static func paying(_ pay: ZkMoneyWire.RequestPayment, symbol: String?, thing: UUID?) -> PayingRequest {
        let asked = pay.asked.map { a in symbol.map { "\(a) \($0.uppercased())" } ?? "$\(a)" }
        return PayingRequest(thing: thing, to: pay.to, amount: pay.amount, asked: asked)
    }

    /// **A REQUEST LINK IN To WRITES THE SENTENCE (prd §1748; user,
    /// 2026-11-11: "we need to be able to paste it in to").** Pasted or
    /// typed, long or short: the tag takes To, the amount asked plus the
    /// deposit's fee takes the amount, the token is picked when you hold it.
    /// A short link is looked up on Aztec first. True when `text` was a
    /// request link, read or not: To then holds the tag (or says why not).
    private func takeRequestLink(_ text: String) async -> Bool {
        var link = ZkMoneyLink.link(text)
        if case .shortRequest(let seed)? = link {
            withAnimation(DS.Motion.standard) { lookup = .looking(String(localized: "this request")) }
            link = await ZkMoney.request(short: ZkMoneyLink.Short(kind: ZkMoneyLink.Short.request, seed: seed))
            guard !Task.isCancelled, text == to.trimmingCharacters(in: .whitespacesAndNewlines) else { return true }
            if link == nil {
                withAnimation(DS.Motion.standard) {
                    lookup = .refused(String(localized: "This request link could not be read. Open it in zk.money."))
                }
                return true
            }
        }
        guard case .request(let tag, let asked, let symbol, _, let expires)? = link else { return false }
        guard ZkMoneyWire.requestOpen(expires: expires, now: .now) else {
            withAnimation(DS.Motion.standard) { lookup = .refused(String(localized: "This request has expired.")) }
            return true
        }
        let pay = ZkMoneyWire.requestPayment(tag: tag, amount: asked, symbol: symbol)
        // **THE TOKEN IS PICKED, AND NEVER LEFT FROM ANOTHER NETWORK (prd
        // §1749; user, on build 980, of a request pasted with Base's token
        // still picked: "it doesn't show the token just the address
        // resolved", then, DAI picked by hand, "it still didn't say how
        // much").** The request is paid on Ethereum, so the token Send held
        // for another network goes; the one asked for is picked when you
        // hold it there, and a request in dollars takes the deposit token
        // you hold (USDC, then DAI, then USDT). Each of the three is a
        // dollar, so with one picked the amount is its own units, and it is
        // in dollars only while none is.
        let onEthereum = heldBy[Op.ethereum.chainId] ?? []
        // The token asked for first; holding none of it, another a deposit
        // takes (zk.money swaps USDC and USDT to DAI on the way in).
        let wanted = (pay.token.map { [$0] } ?? []) + ZkMoneyWire.payOrder
        let pick = wanted.lazy.compactMap { id in onEthereum.first { $0.id == id && left($0) != "0" } }.first
        withAnimation(DS.Motion.standard) {
            lookup = nil
            if network != Op.ethereum {
                network = Op.ethereum
                buy = nil
                buyOn = nil
                quote = nil
            }
            networkPicked = true
            with = pick
            inDollars = pick == nil
            if !pay.amount.isEmpty { amount = pay.amount }
            payingRequest = Self.paying(pay, symbol: symbol, thing: payingRequest?.thing)
            // The tag in To is resolved as a typed one is (prd §1692).
            to = pay.to
        }
        NSLog("zkMoneyPay| link read | %@ | %@ | %@", pay.to, pay.amount.isEmpty ? "-" : pay.amount, pick?.token.symbol ?? "no token picked")
        return true
    }

    /// Opened plainly, from the tab: no arrival, no private mode, no verb
    /// asked for. Only such an open picks a draft up.
    private let picksUpDraft: Bool
    @State private var draftWithID: String?
    @State private var draftSymbol: String?
    @State private var payingRequest: PayingRequest?
    /// The deposit addresses resolved for the request's tag this visit.
    @State private var requestDeposits: Set<String> = []

    private var keptDraft: Draft? {
        guard receipt == nil, stage == nil, privateMode == nil, !freshReceive, !fresh else { return nil }
        // Only what was filled in is a sentence to come back to (prd §1779):
        // a verb picked and nothing else kept Move on that verb for five
        // minutes, and a tester took it for stuck ("it opens on send every
        // time", "restart app to access anything else").
        let filled = !amount.isEmpty || with != nil || buy != nil || !to.isEmpty
        guard filled else { return nil }
        var draft = Draft(verb: verb, network: network, networkPicked: networkPicked, amount: amount, inDollars: inDollars,
                          withID: with?.id, buy: buy, buyOn: buyOn, to: to, at: Date(), request: payingRequest)
        draft.kept = true
        return draft
    }

    /// A Send with To filled, for "Send" on a transfer's sheet (prd §1587).
    static func sendDraft(to address: String, on network: Op.Network? = nil) -> Draft {
        Draft(verb: .send, network: network ?? Op.base, networkPicked: network != nil, amount: "", inDollars: true,
              withID: nil, buy: nil, buyOn: nil, to: address, at: Date())
    }

    /// **SEND AGAIN (prd §1752).** A transfer your own account sent, on a
    /// network Move sends on: the same person, the same amount, the same
    /// token. nil for any other row, which keeps Send with To alone. The
    /// row's amount is the one it shows, so it is only taken under 1,000,
    /// where the row writes every digit it rounds to.
    static func againDraft(_ thing: Thing) -> Draft? {
        guard thing.transferDirection == "sent", let to = sendableCounterparty(thing), let net = network(of: thing),
              let account = YourAccountDemo.shownAddress, WalletWatch.sameAddress(thing.walletAddress ?? "", account) else { return nil }
        let (amount, symbol) = WalletFlow.parseAmount(thing.transferAmount ?? "")
        guard let amount, amount > 0, amount < 1_000, !symbol.isEmpty else { return nil }
        return Draft(verb: .send, network: net, networkPicked: true, amount: againAmount(amount), inDollars: false,
                     withID: nil, buy: nil, buyOn: nil, to: to, at: Date(), symbol: symbol)
    }

    /// "25", "0.0123": the amount field's own text, no grouping, no trailing zeros.
    static func againAmount(_ amount: Double) -> String {
        var text = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), amount)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// **SEND OR SWAP FROM A HOLDING'S LONG PRESS (prd §1609).** The token on
    /// the network where `account` holds the most of it, picked, the amount
    /// left blank; nil when `account` holds none of it on a network Move
    /// signs on, so a holding Move cannot spend offers no verb (§83).
    static func holdingDraft(_ verb: Verb, symbol: String, parts: [WalletPortfolio.Part], account: String?) -> Draft? {
        guard let account, verb == .send || verb == .swap else { return nil }
        for part in parts.filter({ WalletWatch.sameAddress($0.holder, account) }).sorted(by: { $0.usd > $1.usd }) {
            let bits = part.key.split(separator: ":", maxSplits: 1).map(String.init)
            guard bits.count == 2,
                  let net = Op.networks.first(where: { !$0.isTest && Op.appName($0)?.lowercased() == bits[0] }) else { continue }
            // `Tokens.Held.id`: a contract, lowercased, or the coin's symbol.
            let withID = bits[1] == "native" ? symbol : bits[1].lowercased()
            return Draft(verb: verb, network: net, networkPicked: true, amount: "", inDollars: true,
                         withID: withID, buy: nil, buyOn: nil, to: "", at: Date())
        }
        return nil
    }

    /// The network a wallet row moved on, read off its explorer link; nil
    /// when the row names none Move sends on, so the sentence asks.
    static func network(of thing: Thing) -> Op.Network? {
        guard let host = Capture.detectURL(in: thing.content)?.host?.lowercased() else { return nil }
        let id: Int? = host.hasSuffix("basescan.org") && !host.hasPrefix("sepolia") ? 8453
            : host.hasSuffix("etherscan.io") && !host.contains("sepolia") ? 1
            : host.hasPrefix("robinhoodchain") ? 4663 : nil
        return id.flatMap { id in Op.networks.first { $0.chainId == id } }
    }

    /// The other side of a wallet transfer you could send to: an address,
    /// not yours, not flagged, with an account on this phone to send from.
    static func sendableCounterparty(_ thing: Thing) -> String? {
        // **A TAG YOU PAID IS SOMEONE TO PAY AGAIN (prd §1767).** The row
        // went to a one-time address nobody may send to twice, so the door
        // names the tag, and Send resolves a fresh address for it.
        if thing.source == "Wallet", !thing.isFlagged, thing.transferDirection == "sent",
           YourAccountDemo.shownAddress != nil, let tag = ZkMoney.paidTag(at: thing.counterpartyAddress ?? "") {
            return tag
        }
        // A plain transfer only: a swap's router, an approval's spender or a
        // grant's contract is a counterparty too, and money sent there is lost.
        guard thing.source == "Wallet", !thing.isFlagged, YourAccountDemo.shownAddress != nil,
              thing.transferDirection == "sent" || thing.transferDirection == "received",
              SwapStage(thing) == nil, thing.grantedAt == nil,
              // A round-up's buy went to a Relay deposit address and a zk.money
              // move to a one-time address or a portal (prd §1752): nobody to pay.
              SpendingSource.roundUp(of: thing) == nil, ZkMoney.knownName(for: thing.counterpartyAddress ?? "") == nil,
              !WalletIngest.isWorldGrantHolder(thing.counterpartyAddress),
              !WalletFlow.parseAmount(thing.transferAmount ?? "").symbol.isEmpty,
              // A pool the app names by address, or a book entry known to be a
              // contract, is no one to send to; Move still warns on any other
              // contract before Face ID (prd §1513).
              !Tacit.pools.contains(where: { WalletWatch.sameAddress($0, thing.counterpartyAddress ?? "") }),
              AddressBook.shared.entry(for: thing.counterpartyAddress ?? "")?.kind != .contract,
              let address = thing.counterpartyAddress, ENS.isHexAddress(address),
              !WalletStore.shared.addresses.contains(where: { WalletWatch.sameAddress($0.address, address) }),
              !(YourAccountDemo.shownAddress.map { WalletWatch.sameAddress($0, address) } ?? false) else { return nil }
        return address
    }

    private func pickUpDraft() {
        guard picksUpDraft, let d = chrome.moveDraft else { return }
        chrome.moveDraft = nil
        guard Date().timeIntervalSince(d.at) < 5 * 60 else { return }
        verb = d.verb
        network = d.network
        networkPicked = d.networkPicked
        inDollars = d.inDollars
        // The token is matched once the holdings land (`readHoldings`).
        draftWithID = d.withID
        draftSymbol = d.symbol
        buy = d.buy
        buyOn = d.buyOn
        amount = d.amount
        to = d.to
        payingRequest = d.request
        if let which = d.opens { open = which }
    }

    /// "20.5 DAI asked, plus zk.money's $0.35 fee": said while the sentence
    /// still pays the request as Pay wrote it (prd §1745).
    private var requestPrint: String? {
        guard verb == .send, let request = payingRequest, let asked = request.asked,
              amount == request.amount, to.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == request.to else { return nil }
        return String(localized: "\(asked) asked, plus zk.money's $0.35 fee")
    }

    /// The fee is more than the amount asked (prd §1752): amber, over the
    /// line, while the sentence pays the request as written.
    private var requestFeeWarning: String? {
        guard requestPrint != nil, let request = payingRequest else { return nil }
        return ZkMoneyWire.feeWarning(total: request.amount)
    }

    /// A request Pay wrote this send for is paid once a send to an address
    /// resolved for its tag is taken (prd §1745): landed, or taken and not
    /// yet seen, never a dry run. Its row is marked done and undated, so Pay
    /// leaves it and it leaves what's ahead, and its body says the day.
    private func settleRequest(_ lines: [Chain.Item], outcome: Chain.Sent.Outcome) {
        guard let request = payingRequest, outcome != .dryRun else { return }
        let paid = lines.contains { item in
            if case .send(let p) = item { return requestDeposits.contains(p.to.lowercased()) }
            if case .swap(let s) = item, let to = s.payee { return requestDeposits.contains(to.lowercased()) }
            return false
        }
        guard paid else { return }
        payingRequest = nil
        // A link pasted into To has no row to mark.
        guard let id = request.thing else { return }
        guard let thing = try? context.fetch(FetchDescriptor<Thing>(predicate: #Predicate { $0.id == id })).first else { return }
        thing.mark = .done
        thing.dueAt = nil
        thing.enrichedText = [thing.enrichedText, ZkMoneyLink.paidNote(on: .now)].compactMap { $0 }.joined(separator: "\n")
        // **A PAID REQUEST SAYS PAID (prd §1752):** its title leads with the
        // word, in the Feed and on its sheet, and a send seen on chain
        // leaves its explorer page as the row's door.
        thing.title = ZkMoneyLink.paidTitle(thing.title, asked: request.asked, to: request.to)
        if case .landed(let transaction?, _) = outcome {
            thing.externalLink = "https://etherscan.io/tx/\(transaction)"
        }
        context.saveHonestly()
        NSLog("zkMoneyPay| request paid | %@", thing.title)
    }

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
        if open == .buy, crossesInFor { return destinations }
        return lookIn
    }

    /// **FOR LISTS EVERY NETWORK IT CAN ARRIVE ON (user, on picking the
    /// token, then the sentence's last word: "too confusing"; "yes we need
    /// the other networks' token in for").** Once what is sold is picked,
    /// For lists this network's tokens, then each other network's that
    /// Across reaches, named by network; picking one sets where it arrives.
    /// A network picked for it to arrive on counts as well (prd §1600).
    private var crossesInFor: Bool { verb == .swap && networkPicked && (with != nil || buyOn != nil) }

    /// Read, and nothing anywhere: there is nothing to spend yet. A network
    /// no node answered for is not nothing, so it never says so.
    private var emptyEverywhere: Bool {
        heldEverywhere && unread.isEmpty && heldBy.values.allSatisfy(\.isEmpty)
    }

    /// Every network has answered or been given up on: networks fill in
    /// one by one (prd §1586), and one answered is not all.
    private var heldEverywhere: Bool {
        Op.networks.allSatisfy { heldBy[$0.chainId] != nil }
    }

    /// Nothing found, because a read failed: the line says which networks
    /// and offers the read again, never "Receive something first".
    private var readFailed: Bool {
        heldEverywhere && !unread.isEmpty && heldBy.values.allSatisfy(\.isEmpty)
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
        // **EVERY NETWORK AT ONCE IS TOR'S CIRCUIT (prd §1597, user: "but
        // why").** Tor said ready and every node failed together; each
        // answers over ten circuits from a desk (360 of 360, measured
        // 2026-10-28), so naming the three networks blamed the wrong thing.
        // Try again builds new circuits. A network on your own node is not
        // read through Tor and keeps its name.
        default: unreadThroughTor ? String(localized: "Tor couldn't get through: try again")
                                  : String(localized: "Couldn't read \(unreadNames): try again")
        }
    }

    /// Every network went unread, and every one is read through Tor.
    private var unreadThroughTor: Bool {
        TorRoute.available && Op.networks.allSatisfy {
            unread.contains($0.chainId) && OwnNodeStore.settings.address(for: $0.chainId) == nil
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
            // **THE NETWORK'S DOLLAR IS A DOLLAR (user: "fix the usdc make it
            // exact").** $1.30 of USDC is 1.30 USDC, never 1.300712 off a
            // price a hair under $1, which also made its round-up $0.6993.
            if with.token.contract?.lowercased() == Op.dollar(on: network).contract?.lowercased() {
                return Op.baseUnits(amount, decimals: with.token.decimals)
            }
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
            guard let r = resolved, stands(r), !zkMoneyUsed.contains(r.address.lowercased()),
                  zkMoneyRefusal == nil else { return nil }
            // A tag paid from a token a deposit does not take (prd §1768):
            // the line is the swap into USDC, and `tagTail` pays the tag.
            if tagConverts {
                guard let q = tagSwap, q.sellAmount == units else { return nil }
                return .swap(Chain.Swap(network: network, sell: with.token, buy: Op.dollar(on: network), amount: units, quote: q))
            }
            // A tag paid from another network (prd §1770): the line is the
            // crossing, Across paying the tag's address on Ethereum.
            if tagCrosses {
                guard let q = tagSwap, q.sellAmount == units, q.across?.payee?.lowercased() == r.address.lowercased() else { return nil }
                return .swap(Chain.Swap(network: network, sell: with.token, buy: Op.dollar(on: Op.ethereum), amount: units, quote: q,
                                        to: Op.ethereum, payee: r.address, payeeName: r.name))
            }
            return .send(Op.Payment(network: network, token: with.token, amount: units, to: r.address, toName: r.name))
        case .receive, .buy, .sweep, .deposit, .lend:
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

    private var all: [Chain.Item] { items + (pendingItem.map { [$0] } ?? []) + (tagTail.map { [$0] } ?? []) }

    /// **PAY A TAG FROM ANY TOKEN ON ETHEREUM (prd §1768, user: "and or
    /// paying from eth or other network?").** A deposit takes DAI, USDC or
    /// USDT; ETH, or any other token Swap sells on Ethereum, was refused.
    /// Now the one transaction swaps it into USDC and pays the tag: the swap
    /// first, then exactly the USDC the swap must return (its minimum) to the
    /// tag's address. What the pool pays over that minimum stays yours, as
    /// USDC. It goes alone: no kept lines, and Add is refused.
    private var tagConverts: Bool {
        guard verb == .send, paysZkMoney, items.isEmpty, network == Op.ethereum, YourAccountSwap.supported(network),
              let with else { return false }
        return !ZkMoneyWire.payTokens.contains(with.id)
    }

    /// The payment a converted tag payment ends with.
    private var tagTail: Chain.Item? {
        guard tagConverts, pendingItem != nil, let q = tagSwap, let r = resolved else { return nil }
        return .send(Op.Payment(network: network, token: Op.dollar(on: network), amount: q.minimumBuy, to: r.address, toName: r.name))
    }

    /// **PAY A TAG FROM ANOTHER NETWORK (prd §1770, user: "ok lets do the
    /// pay a tag from another network").** A tag is paid on Ethereum; most
    /// money here is on Base. From a network Across carries the dollar from,
    /// the one transaction is the crossing (what you send swapped into that
    /// network's dollar first, if it is not it), with the tag's one-time
    /// address as the recipient on Ethereum: a relayer pays the tag exactly
    /// what Across quoted. It goes alone, as every crossing does, and a
    /// crossing nobody fills comes back to you.
    private var tagCrosses: Bool {
        guard verb == .send, paysZkMoney, items.isEmpty, network != Op.ethereum, !network.isTest, with != nil,
              YourAccountAcross.carries(.dollar, from: network.chainId, to: Op.ethereum.chainId) else { return false }
        return true
    }

    private var tagSwapKey: String {
        guard tagConverts || tagCrosses, let with else { return "" }
        return "\(network.chainId)|\(with.id)|\(units ?? "")|\(resolved?.address ?? "")"
    }

    private func requoteTag() async {
        tagSwap = nil
        tagSwapNote = nil
        let crossing = tagCrosses
        guard tagConverts || crossing, let with, let units, units != "0", !over, let payee = resolved?.address else { return }
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        do {
            let q = crossing
                ? try await Chain.crossQuote(network, to: Op.ethereum, sell: with.token, buy: Op.dollar(on: Op.ethereum), amount: units,
                                             account: account, payee: payee)
                : try await Chain.swapQuote(network, sell: with.token, buy: Op.dollar(on: network), amount: units, account: account)
            guard !Task.isCancelled else { return }
            withAnimation(DS.Motion.standard) { tagSwap = q }
            NSLog("zkMoneyPay| %@ | %@ %@ | min %@ USDC | calls=%d", crossing ? "from \(network.name)" : "swapped first", units,
                  with.token.symbol, q.minimumBuy, q.calls.count)
        } catch let failure as Chain.Failure {
            if !Task.isCancelled { tagSwapNote = failure.message }
        } catch {}
    }

    /// To holds a deposit address zk.money's resolver proved for a tag.
    private var paysZkMoney: Bool {
        verb == .send && resolved.map { zkMoneyDeposits.contains($0.address.lowercased()) } == true
    }

    /// A deposit's own limits, said before the tap (DAI, USDC or USDT on
    /// Ethereum, over the $0.35 fee, under $5,000); nil once a token is
    /// picked and they pass.
    private var zkMoneyRefusal: String? {
        guard paysZkMoney, let with else { return nil }
        // Swapped into USDC first (prd §1768): the limits are the deposit's
        // own, checked on what the swap must return.
        if tagConverts || tagCrosses {
            let usd = tagSwap.map { Op.dollars($0.minimumBuy, decimals: 6, price: 1) }
            return ZkMoneyWire.payRefusal(chainId: Op.ethereum.chainId, token: ZkMoneyWire.usdc, usd: usd)
        }
        // The three tokens it takes are dollars: with no price read, a token
        // is a dollar, so the cap never goes unchecked.
        let usd = units.map { Op.dollars($0, decimals: with.token.decimals, price: with.price ?? 1) }
        return ZkMoneyWire.payRefusal(chainId: network.chainId, token: with.token.contract, usd: usd)
    }

    /// The deposit addresses `lines` pay are spent: To asks for a fresh one
    /// if it holds one of them.
    ///
    /// **A TYPED TAG SETS UP ITS OWN PAYMENT (prd §1767).** A tag is paid in
    /// DAI, USDC or USDT on Ethereum and nowhere else. A pasted request moved
    /// Send there and picked the dollar you hold (§1749); a typed tag left
    /// whatever stood, Base's USDC by default, and then refused it. Now a
    /// tag that resolves does the same: Ethereum, the dollar you hold (USDC,
    /// then DAI, then USDT). Only when what stands could not pay it, so a
    /// token you picked that a deposit takes is left alone; an amount in
    /// dollars or in a dollar token stands, any other is cleared.
    private func setUpTagPayment() {
        // A request Pay wrote has set itself up (§1749), and a draft whose
        // own dollar is still being matched to a holding (Again) keeps it.
        guard verb == .send, payingRequest == nil else { return }
        if network == Op.ethereum {
            if let symbol = draftSymbol?.uppercased(), ["USDC", "USDT", "DAI"].contains(symbol) { return }
            if let id = draftWithID, ZkMoneyWire.payTokens.contains(id) { return }
        }
        // Any token picked on Ethereum stands: one a deposit takes is sent
        // as it is, another is swapped into USDC first (prd §1768). So does
        // one picked on a network Across carries the dollar from: the tag is
        // paid from where your money is (prd §1770).
        let fits = with != nil && (network == Op.ethereum
            || (!network.isTest && YourAccountAcross.carries(.dollar, from: network.chainId, to: Op.ethereum.chainId)))
        guard !fits else { return }
        let onEthereum = heldBy[Op.ethereum.chainId] ?? []
        // The dollar you hold; with none, the most of anything you hold
        // there, which the same transaction swaps.
        let pick = ZkMoneyWire.payOrder.lazy.compactMap { id in onEthereum.first { $0.id == id && self.left($0) != "0" } }.first
            ?? onEthereum.filter { self.left($0) != "0" }.max { ($0.usd ?? 0) < ($1.usd ?? 0) }
        let dollars = inDollars || ["USDC", "USDT", "DAI"].contains(with?.token.symbol.uppercased() ?? "")
        if network != Op.ethereum {
            network = Op.ethereum
            buy = nil
            buyOn = nil
            quote = nil
        }
        networkPicked = true
        if !dollars { amount = "" }
        with = pick
        // An amount that stood was dollars; a token that is not a dollar
        // keeps it as dollars, or loses it where the token has no price.
        let pickIsDollar = pick.map { ZkMoneyWire.payTokens.contains($0.id) } ?? false
        if pick != nil, !pickIsDollar, pick?.price == nil { amount = "" }
        inDollars = pick == nil || (!pickIsDollar && pick?.price != nil)
        // The list of what you hold opened because nothing was picked
        // (§1534); with the dollar picked it steps aside for the amount.
        if pick != nil, open == .with { open = nil }
        NSLog("zkMoneyPay| tag set up | %@", pick?.token.symbol ?? "no token held")
    }

    private func spendZkMoney(_ lines: [Chain.Item]) {
        let paid = lines.compactMap { item -> String? in
            if case .send(let p) = item, zkMoneyDeposits.contains(p.to.lowercased()) { return p.to.lowercased() }
            if case .swap(let s) = item, let to = s.payee?.lowercased(), zkMoneyDeposits.contains(to) { return to }
            return nil
        }
        guard !paid.isEmpty else { return }
        zkMoneyUsed.formUnion(paid)
        if let r = resolved, zkMoneyUsed.contains(r.address.lowercased()) { zkMoneyFresh += 1 }
    }

    // MARK: - Round-ups (prd §1452, §1690)

    /// **ROUND-UPS, SET ASIDE AS YOU GO (prd §1690).** This act's round-up:
    /// its change to the next dollar, what it sets aside with what was owed,
    /// and whether Round-ups already holds enough to move into your private
    /// balance with it. nil when round-ups are off or nothing here is dollars.
    private var roundUpStep: RoundUpsPot.Step? {
        // A price's order is CoW's to fill later: nothing rides it, so no
        // round-up or total is said (prd §1673, §83).
        if limiting { return nil }
        guard RoundUps.setting.on, !network.isTest else { return nil }
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
        return RoundUpsPot.step(change: RoundUps.change(sent, step: 1), owed: RoundUpsPot.owed, pot: RoundUpsPot.shown,
                                moveAt: RoundUpsPot.moveAt(poolMinimum: PrivateMoneyStore.shared.roundUpsMinimum))
    }

    /// Whether this act's operation can carry the change into Round-ups.
    private var roundUpCarries: Bool {
        guard let step = roundUpStep else { return false }
        return RoundUps.carriesBuy(roundUpAct) && RoundUpsPot.carries(step.carry, from: network.chainId)
    }

    /// What rounds up here, for whether its transaction can set the change aside: one
    /// that spends the dollar (a send of it, a swap selling it); a Buy never.
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

    /// Whether Relay carries this move (prd §1512, §1539, §1545): a send
    /// whose round-up buys a token on another network now, money arriving
    /// from another network. A round-up on the send's own network is bought
    /// on the exchanges, through Tor like a swap. Relay refuses
    /// every Tor exit, key or no key, so each says it on the foot. A swap and
    /// a sweep go straight to the pools through the account's own node, so
    /// through Tor (measured 2026-10-26), and are not Relay's.
    private var relayCarries: Bool {
        switch verb {
        case .swap, .send: false
        case .receive: elsewhere != nil
        case .buy, .deposit, .lend: false
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
    ///
    /// **EACH LINE WEARS ITS EXCHANGE'S MARK (prd §1675, user: "should we
    /// have their logos there").** One line per leg, the marks of the
    /// services it names before its words, as Relay's and CoW Swap's credits
    /// carry theirs.
    private var exchangeCredit: [CreditLine] {
        // A price's order credits CoW Swap with its mark, in `foot` (prd §1673).
        if limiting { return [] }
        guard verb == .swap || verb == .sweep || tagConverts || tagCrosses else { return [] }
        // **"THROUGH ACROSS · 0.06% FEE · ABOUT 10 SECONDS" (prd §1555).**
        // A swap to another network: Across's fee, rounded as a pool's is,
        // and its time; under the pool's words when a token is swapped first.
        // "Unwraps WETH · no fee" (prd §1559): one for one through the
        // network's WETH, no pool and no fee but the network's.
        if signing.count == 1, case .swap(let s) = signing[0], let w = s.quote.wrap {
            return [CreditLine(marks: [], text: YourAccountSwap.words(w))]
        }
        for item in signing {
            guard case .swap(let s) = item, let leg = s.quote.across else { continue }
            let across = [YourAccountAcross.words(leg), YourAccountAcross.about(leg.seconds)].compactMap { $0 }.joined(separator: " · ")
            // In the order it happens: the pools here, Across, the pools
            // there (prd §1566: "On Uniswap · 0.05% pool fee on Ethereum").
            var lines = s.quote.route.map { CreditLine.of([$0]) } ?? []
            lines.append(CreditLine(marks: ["Across"], text: across))
            if let words = YourAccountAcross.arrivalWords(leg), let there = leg.swap?.route {
                lines.append(CreditLine(marks: [there.venue.exchange], text: words))
            }
            return lines
        }
        let routes = signing.compactMap { item -> YourAccountSwap.Route? in
            if case .swap(let s) = item { return s.quote.route }
            return nil
        }
        return CreditLine.of(routes)
    }

    /// The most any swap here moves its pools' price, in words, from 1%
    /// (prd §1683); a price's order fills at its price, so says nothing.
    private var impactWarning: String? {
        guard !limiting, verb == .swap || verb == .sweep else { return nil }
        let worst = signing.compactMap { item -> Double? in
            if case .swap(let s) = item { return s.quote.impact }
            return nil
        }.max()
        return YourAccountSwap.impactWords(worst)
    }

    /// One line of the swap's credit: its words and the services they name,
    /// whose marks lead it (prd §1675).
    struct CreditLine: Hashable {
        let marks: [String]
        let text: String
        /// The pools' own credit: its row is "Through" and the exchanges'
        /// names (prd §1754); every other line keeps its words.
        var pools = false

        /// The pools' credit as one line, every exchange it names marked.
        static func of(_ routes: [YourAccountSwap.Route]) -> [CreditLine] {
            guard let text = YourAccountSwap.credit(routes) else { return [] }
            return [CreditLine(marks: YourAccountSwap.exchanges(routes), text: text, pools: true)]
        }
    }

    /// The small print's word on Round-ups (prd §1690): what it holds after
    /// this send, toward the move, or that this send moves it.
    private var roundUpPrint: [String] {
        guard let step = roundUpStep else { return [] }
        let target = RoundUpsPot.targetWords
        if step.moves {
            return [String(localized: "Moves \(Self.money(RoundUpsPot.dollars(RoundUpsPot.shown))) of Round-ups to your private balance")]
        }
        let after = roundUpCarries ? RoundUpsPot.sum(RoundUpsPot.shown, step.carry) : RoundUpsPot.shown
        return [String(localized: "Round-ups \(Self.money(RoundUpsPot.dollars(after))) of \(target)")]
    }

    // MARK: - The page

    var body: some View {
        // The verbs open on the account page over any verb's own sentence
        // (Lend, Send privately, a fresh Receive), so every verb word opens
        // the one list (prd §1681).
        let ownSentence = (privateMode != nil || freshReceive || aztecReceive || aztecMode != nil || railgunOpen || verb == .lend) && open != .verb
        ZStack {
            accountPage
                .opacity(ownSentence ? 0 : 1)
                .allowsHitTesting(!ownSentence)
                .accessibilityHidden(ownSentence)
            if verb == .lend, privateMode == nil, !freshReceive, open != .verb {
                MoveLendSentence(move: lendMove, account: account, inTray: inTray) { verbWord(lendWord) }
                    .transition(.opacity)
            }
            if freshReceive, privateMode == nil, open != .verb {
                // "your private balance" goes back to where it lands.
                MoveFreshSentence(inTray: inTray, leave: {
                    withAnimation(DS.Motion.standard) { freshReceive = false; open = .elsewhere }
                }, payGas: { address, eth in
                    // **PAY THE GAS (prd §1779).** Send's own sentence, filled:
                    // a little ETH from your account to the address that is
                    // waiting, yours to confirm like any send.
                    withAnimation(DS.Motion.standard) {
                        freshReceive = false
                        verb = .send
                        network = Op.ethereum
                        networkPicked = true
                        to = address
                        inDollars = false
                        amount = eth
                        open = nil
                    }
                    Task {
                        await readNetwork()
                        with = (heldBy[Op.ethereum.chainId] ?? []).first { $0.token.symbol.caseInsensitiveCompare("ETH") == .orderedSame }
                    }
                }) { verbWord(title(.receive)) }
                .transition(.opacity)
            }
            if railgunOpen, privateMode == nil, open != .verb {
                MoveRailgunSentence(move: railgunMove, inTray: inTray, leave: { why in
                    withAnimation(DS.Motion.standard) {
                        railgunOpen = false
                        switch why {
                        // Under $10: get more of it (prd §1728 item 2).
                        case .receive: verb = .receive
                        case .swap: verb = .swap
                        case .pickRecipient, .switchOff:
                            open = why == .pickRecipient ? .to : .with
                            if why == .pickRecipient { search = "" }
                        }
                    }
                }) { verbWord(title(.send)) }
                .transition(.opacity)
            }
            if aztecReceive, privateMode == nil, open != .verb {
                MoveAztecReceive(inTray: inTray, leave: {
                    withAnimation(DS.Motion.standard) { aztecReceive = false; open = .elsewhere }
                }, addMoney: {
                    // Money on Ethereum comes in through Send's sentence to
                    // your private balance on Aztec (prd §1779).
                    withAnimation(DS.Motion.standard) { aztecReceive = false; verb = .send }
                    goAztec(.deposit)
                }) { verbWord(title(.receive)) }
                .transition(.opacity)
            }
            if aztecMode != nil, privateMode == nil, open != .verb {
                MoveAztecPrivateSentence(move: aztecMove, inTray: inTray, leave: { why in
                    withAnimation(DS.Motion.standard) {
                        aztecMode = nil
                        open = why == .pickRecipient ? .to : .with
                        if why == .pickRecipient { search = "" }
                    }
                }) { verbWord(title(.send)) }
                .transition(.opacity)
            }
            if privateMode != nil, open != .verb {
                MovePrivateSentence(move: privateMove, inTray: inTray, leave: { why in
                    withAnimation(DS.Motion.standard) {
                        privateMode = nil
                        // Its recipient opens Send's recipients; its "from"
                        // opens the token list, where private money is one
                        // of the rows (prd §1719).
                        open = why == .pickRecipient ? .to : .with
                        if why == .pickRecipient { search = "" }
                    }
                }) { verbWord(title(.send)) }
                .transition(.opacity)
            }
        }
        // Every sentence Move mounts leads its foot with the way back to
        // the menu (prd §1781): the verb in the sentence no longer opens it.
        .environment(\.moveBack, {
            withAnimation(DS.Motion.standard) {
                open = .verb
                focus = nil
            }
        })
        .animation(DS.Motion.standard, value: privateMode)
        .animation(DS.Motion.standard, value: aztecMode)
        .animation(DS.Motion.standard, value: freshReceive)
        .animation(DS.Motion.standard, value: aztecReceive)
        .animation(DS.Motion.standard, value: railgunOpen)
        .animation(DS.Motion.standard, value: verb)
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
                            // The menu stands under Move's own name (prd
                            // §1781): a sentence over it read as a thing to
                            // tap. What was being filled is kept, and its
                            // verb's row goes back to it.
                            if open == .verb {
                                word(String(localized: "Move"), ink: DS.textPrimary)
                                    .accessibilityAddTraits(.isHeader)
                            } else {
                                sentence
                            }
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sentenceHeight = $0 }
                        .onPreferenceChange(MoveSentenceBlanksKey.self) { sentenceBlanks = $0 }
                        // An open list runs to the tray's bottom edge, under
                        // the home bar (prd §1616 item 5): with no card, a box
                        // ending above it clipped a row in mid-air.
                        space(room: geo.size.height, inset: listReach(geo))
                            .padding(.top, inlineOpen == nil ? DS.Space.s6 : DS.Space.s4)
                    }
                }
                .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
                .padding(.top, inTray ? DS.Space.s2 : DS.Space.s6)
                // Scrolled to the end, the last line clears the foot's fade;
                // an open list has no foot and runs to the edge itself.
                .padding(.bottom, inlineOpen == nil ? DS.Space.s4 + Self.footFade : 0)
                .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .topLeading)
            }
        }
        // An open list reaches the sheet's bottom edge: past the tray's own
        // air and under the home bar (prd §1616 item 5).
        .ignoresSafeArea(.container, edges: reachesEdge ? .bottom : [])
        .padding(.bottom, reachesEdge ? -DSTray<EmptyView>.bottomPadding : 0)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        // While a blank is open the foot steps aside: its verb cannot sign a
        // half-picked sentence, and the list takes its room (§1442a).
        .safeAreaInset(edge: .bottom, spacing: 0) { if inlineOpen == nil, !rawOpen { foot.transition(.opacity) } }
        // A network picked is read again; the first pass is `readHoldings`'
        // (prd §1586: Base was read twice on every open).
        .task(id: network.chainId) { if !heldBy.isEmpty { await readNetwork() } }
        // Never closed by a swipe while Face ID or the network has it.
        .interactiveDismissDisabled(stage != nil)
        // Two heights (prd §1681, §1681b): short when Move opens; the first
        // word's choices or the keys make it whole, and it stays whole —
        // coming back down at every pick was the jitter. Dragged short, what
        // was open closes, so a list never stands cut off in the short sheet.
        .onChange(of: open) { _, now in if now != nil { chrome.moveTall = true } }
        .onChange(of: focus) { _, now in if now != nil { chrome.moveTall = true } }
        // A price typed over is no longer the preset it started as (prd §1683).
        .onChange(of: priceText) { if focus == .price { whenPreset = nil } }
        .onChange(of: chrome.moveTall) { _, tall in
            guard !tall, open != nil || focus != nil else { return }
            focus = nil
            withAnimation(DS.Motion.standard) { open = nil }
        }
        // EVERY Move opens on the verbs (prd §1736, amending §1681 item 4's
        // "once"): the menu of what Move does is seen each time, Swap's
        // sentence live above it, so a tap on a blank still goes straight on.
        // Only a plain open from the tab: a verb asked for, an arrival or a
        // private move has its verb already, and so has a draft a door
        // carried in. **A sentence Move kept comes back UNDER the verbs
        // (prd §1779, amending §1736's "or a sentence left half-filled"):**
        // it stands above the menu as Swap's does, a tap on any of its words
        // goes on with it, and every other verb is one tap away. Reopening
        // straight onto it hid the menu behind a word nobody knew to tap.
        .onAppear {
            guard picksUpDraft, receipt == nil, stage == nil else { return }
            if let d = chrome.moveDraft, Date().timeIntervalSince(d.at) < 5 * 60, !d.kept { return }
            open = .verb
        }
        .onDisappear { chrome.moveDraft = keptDraft }
        // **THE NEXT LIST OPENS BY ITSELF (prd §1782).** After a pick, the
        // first row still saying "Choose" opens its list, so a send is pick,
        // pick, pick with no row tapped in between. Only after a pick: a
        // list closed by its name, the keys raised, or a sheet made short
        // leaves the rows as they are.
        .onChange(of: open) { _, now in
            // A menu's pick waits for the menu to be gone (`menuGone`): the
            // next one cannot rise while it is still leaving (prd §1784).
            guard now == nil, advances, !menuUp else { return }
            advances = false
            Task { @MainActor in
                // The rows are read off the sentence, which draws the pick first.
                try? await Task.sleep(for: .milliseconds(280))
                advance()
            }
        }
        .alert("Name this address", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: $nameDraft)
                .textInputAutocapitalization(.words)
            Button("Save") {
                let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let address = naming, !name.isEmpty else { return }
                AddressBook.shared.setName(name, for: address)
                CounterpartyRetitle.applyCurrentName(for: address, in: context)
                withAnimation(DS.Motion.standard) {
                    receipt?.names.removeAll { WalletWatch.sameAddress($0, address) }
                }
                DSHaptic.success()
                say(String(localized: "Named \(name)"))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Next time it is one tap in To.")
        }
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
            if now == .deposit { enterDeposit() }
            if now == .sweep { enterSweep() }
            // Back from Receive: what was sent meanwhile is spendable.
            if was == .receive { Task { await readHoldings() } }
            // Details stays open across edits of the sentence, and closes
            // when the verb changes (prd §1509).
            details = false
            rawOpen = false
        }
        .onChange(of: open) { was, now in
            guard was == .to, now != .to else { return }
            if to.isEmpty, let before = toBefore {
                to = before.text
                resolved = before.resolved
            }
            toBefore = nil
            pastedTo = false
        }
        .onChange(of: resolved) { _, now in
            // A pasted address that resolved is the pick (prd §1586).
            guard pastedTo, open == .to, let now, now.imitates == nil else { return }
            pastedTo = false
            pick {}
        }
        .onChange(of: scenePhase) { _, now in
            // Face ID's own sheet passes through here (prd §1687: it rises at
            // the tap now): while the send prepares and signs it reads its own
            // balances, so nothing competes with it; back from the Signer's
            // wallet the page reads as before.
            if now == .active { Task { await readClipboard() } }
            if now == .active, stage != .preparing, stage != .signing, !heldBy.isEmpty {
                Task { await readHoldings() }
                if !YourAccountDemo.isDemo(account) { Task { [account, network] in await Chain.readAhead(account, on: network) } }
            }
        }
        // Tor connecting late reads what failed again, unasked (prd §1549).
        .onChange(of: TorStatus.shared.state) { _, now in
            if case .ready = now, !unread.isEmpty { Task { await readHoldings() } }
        }
        .task(id: quoteKey) { await requote() }
        .task(id: tagSwapKey) { await requoteTag() }
        .task(id: limitKey) { await readLimitPrices() }
        .task(id: orderShown?.uid) { await followOrder() }
        // What the account is on this network, read before the tap (prd §1602).
        .task(id: "\(network.chainId)|\(account)") {
            guard !YourAccountDemo.isDemo(account) else { return }
            await Chain.readAhead(account, on: network)
            // Kept fresh while Move is open, a minute before they would
            // lapse, never mid-send (prd §1610).
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Chain.factsLife - 60))
                guard !Task.isCancelled else { return }
                if stage == nil { await Chain.refreshFacts(account, on: network) }
            }
        }
        .task(id: crossingWatch?.id) { await watchCrossing() }
        .task(id: sweepKey) { await resweep() }
        .task(id: previewKey) { await repreview() }
        .task(id: checkKey) { await recheck() }
        .task(id: "\(to)|\(zkMoneyFresh)") { await resolve() }
        // A deposit address's proof holds for its day, and how long the
        // operator watches one is unmeasured: one left standing ten minutes
        // is spent and asked for afresh (prd §1692).
        .task(id: paysZkMoney ? resolved?.address : nil) {
            guard paysZkMoney, let address = resolved?.address.lowercased() else { return }
            try? await Task.sleep(for: .seconds(600))
            guard !Task.isCancelled, resolved?.address.lowercased() == address else { return }
            zkMoneyUsed.insert(address)
            zkMoneyFresh += 1
        }
        .task {
            // What you hold opens the first list; Uniswap's lists, which only
            // For and a pasted contract need, follow (prd §1586).
            pickUpDraft()
            readRecentTo()
            Task { await readClipboard() }
            await readHoldings(shared: true)
            if with == nil, let id = draftWithID {
                with = heldBy[network.chainId]?.first { $0.id == id }
            }
            draftWithID = nil
            // Again (prd §1752): the row names its token by symbol alone, so
            // it is picked only when one token you hold there wears it; with
            // none or two, the amount goes too and the sentence asks.
            if let symbol = draftSymbol {
                let named = (heldBy[network.chainId] ?? []).filter { $0.token.symbol.caseInsensitiveCompare(symbol) == .orderedSame }
                if with == nil, named.count == 1 {
                    with = named[0]
                } else if with == nil {
                    amount = ""
                    inDollars = true
                }
            }
            draftSymbol = nil
            #if DEBUG
            if Self.drafting {
                await readLists()
                draft()
            }
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
            if listedBy.isEmpty { await readLists() }
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
            // What Add kept of the other verb stands over the sentence,
            // numbered, quieter than the sentence being filled (§1442c) —
            // on Receive and Buy; Swap and Send say it as a sentence of
            // its own (prd §1494).
            if receipt == nil, verb == .receive || verb == .buy || verb == .sweep, !keptLines.filter(showsKept).isEmpty {
                kept
                    .padding(.bottom, DS.Space.s4)
            }
            MoveFlow {
                // The verb is the sentence's first word (prd §1681): pink, it
                // opens the verbs as any word opens its choices. An arrival's
                // sentence has none until it has finished itself (§1442j); a
                // sentence after one Add kept leads with "Then swap" instead.
                if receipt == nil, thenWord == nil, !fresh || arrived {
                    // **THE VERB CHANGES TENSE WHERE IT STANDS (prd §1754):**
                    // "Send", "Sending" while it goes, then the receipt's
                    // "Sent", the last two in the pick's pink.
                    verbWord(stage == nil ? title(verb) : going(verb), ink: stage == nil ? MoveSentence.settledInk : DS.pickInk)
                        .contentTransition(.interpolate)
                }
                if let receipt {
                    receiptClauses(receipt)
                } else if emptyEverywhere, verb != .receive, verb != .deposit {
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
                    case .deposit: depositClauses
                    // Lend draws its own sentence over this one (prd §1674).
                    case .lend: EmptyView()
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
            // No Private switch in Send (prd §1700f item 11): the network list
            // is where the money is, the two private balances among it.
            // No Private switch in Receive either (prd §1719, retiring
            // §1560's): your private balance is a place in Receive's "on"
            // list, on Ethereum (a fresh address) and on Aztec.
            // The change and the total are rows of the ledger under the
            // sentence (prd §1754): `ledgerRows`.
            // The sentence says the move and is no control (prd §1781): no
            // word, figure or kept line in it takes a touch. The rows under
            // it do; the amount's field is focused from its row.
            .allowsHitTesting(false)
        }
        .animation(DS.Motion.standard, value: verb)
        .animation(DS.Motion.standard, value: receipt)
    }

    /// Everything that can change where the flow breaks a line.
    private var layoutKey: String {
        [amount, with?.token.symbol ?? "", buy?.token.symbol ?? "", String(network.chainId),
         String(items.count), String(slot), to, resolved?.name ?? "", inDollars ? "$" : "",
         quote?.buyAmount ?? staleBack?.text ?? "", String(reach?.count ?? -1), elsewhere?.token.symbol ?? "",
         buyGroup?.rawValue ?? "", buyProduct?.id ?? "", stage == nil ? "" : "going"].joined(separator: "|")
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
        // "Swap 0.01 ETH on Ethereum for USDC on Base." (prd §1555): both
        // networks are words, the first the one it leaves — always, so a
        // swap to another network is a choice you can see (prd §1600).
        // **THE NETWORK IS SAID ONCE (prd §1754, amending §1600's "always"):**
        // "Swap 0.005 ETH for 19.2 USDC on Base." The network it leaves is a
        // word only when it differs from the one it arrives on; the token
        // you pick names where it comes from, and the last word still opens
        // "Get <token> on". Before anything is picked the sentence is
        // "Swap token for token." and "now" is the ledger's When row.
        if networkPicked, buyHome != network { MoveClause(glue: String(localized: "on")) { originWord } }
        MoveClause(glue: String(localized: "for")) { buyWord }
        if networkPicked { MoveClause(glue: String(localized: "on")) { destinationWord } }
        if whenSpoken { whenClause }
    }

    /// "when ETH is $4,042." ends the sentence only once a price is picked
    /// (prd §1754): at rest the sentence says nothing of when.
    private var whenSpoken: Bool { whenDrawn && when == .price }

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
                    word(group.name ?? "", ink: MoveSentence.settledInk)
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
            MoveClause(glue: piece.glue, glueInk: n == 0 ? DS.textSecondary : MoveSentence.glueInk) {
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
        case .swap, .buy, .sweep: String(localized: "needs money first.")
        case .send, .receive, .deposit, .lend: String(localized: "needs money first.")
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
            sweepUnderMenu { MoveWord("$\(sweepUnder)", ink: MoveSentence.settledInk) }
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
                ledger(door: offersDetails)
                if let note = failNote ?? shownPreview?.refusal ?? sweepFeeNote {
                    Text(verbatim: note).dsText(.body17).foregroundStyle(DS.attentionInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if heldBy[network.chainId] == nil {
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
        case .roundUps: String(localized: "Your round-ups wait in \(symbol) until your next send sets them aside")
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

    /// What this sweep sells, in dollars: the ledger's Total (prd §1754).
    private var sweepSoldUSD: Double? {
        guard let plan = sweepPlan else { return nil }
        let ids = Set(sweepItems.compactMap { item -> String? in
            if case .swap(let s) = item { return s.sell.contract?.lowercased() ?? s.sell.symbol }
            return nil
        })
        let usd = plan.sweeps.filter { ids.contains($0.id) }.compactMap(\.usd).reduce(0, +)
        return usd > 0 ? usd : nil
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
        let waiting = RoundUps.setting.on && DustSweep.isPositive(RoundUpsPot.owed)
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
                blank(route.token.symbol, ink: MoveSentence.settledInk, .elsewhereCoin, label: Text("Picks what they send"))
            }
            // Where the sender's money is (user: "'on' arbitrum would be better").
            MoveClause(glue: String(localized: "on")) {
                blank(route.from.name, ink: MoveSentence.settledInk, .elsewhere, label: Text("On \(route.from.name), change"))
            }
            // What arrives is your pick (prd §1470): Relay swaps on the way.
            MoveClause(glue: String(localized: "as")) {
                blank(route.arrives.symbol, ink: MoveSentence.settledInk, .arrives, label: Text("Picks what you receive"))
            }
            // Its own clause, so "on Base." moves to the next line whole
            // rather than hanging under "as" (prd §1586).
            MoveClause(glue: String(localized: "on")) {
                word(route.to.name + ".", ink: DS.textPrimary)
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
                        // A word (prd §1781): the foot's Copy asks for the
                        // network, and opens its list.
                        word(YourAccount.short(account), ink: DS.textPrimary)
                            .accessibilityLabel(Text("Your address, \(account)"))
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
                // A word (prd §1781): the foot's Copy copies it, and the
                // Network row picks where.
                word(YourAccount.short(account), ink: networkPicked ? MoveSentence.settledInk : DS.textPrimary)
                    .accessibilityLabel(Text("Your address, \(account)"))
            }
            MoveClause(glue: String(localized: "on")) { receiveNetworkWord }
        }
    }

    /// **THE ADDRESS, READABLE (prd §1586, user: "five digits per section
    /// that doesn't lead to a wrap").** "0x" stands apart; the forty
    /// characters are eight groups of five, two rows of four, the first and
    /// last bright — the ones a person checks. A tap copies it, as the foot does.
    private func addressBlock(_ address: String) -> some View {
        Button { copy() } label: { AddressGroupsGrid(address: address) }
        .buttonStyle(RowPress())
        .accessibilityLabel(Text(verbatim: address))
        .accessibilityHint(Text("Copies the address"))
    }

    /// An EVM address's forty characters in eight groups of five; empty for
    /// anything else.
    static func addressGroups(_ address: String) -> [String] {
        guard address.count == 42, address.lowercased().hasPrefix("0x") else { return [] }
        let hex = Array(address.dropFirst(2))
        return stride(from: 0, to: 40, by: 5).map { String(hex[$0..<$0 + 5]) }
    }

    /// Receive's one blank (prd §1486): the list it opens is your own
    /// networks, then every network Relay takes deposits on.
    private var receiveNetworkWord: some View {
        Group {
            if networkPicked {
                blank(network.name + ".", ink: MoveSentence.settledInk, .elsewhere, label: Text("On \(network.name), change"))
            } else {
                blank(String(localized: "network."), ink: DS.textTertiary, .elsewhere, empty: true, label: Text("Pick a network"))
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
                       // The past tense wears the pick's pink (prd §1754).
                       glueInk: n == 0 ? DS.pickInk : line.starts ? DS.textSecondary : MoveSentence.glueInk, ink: DS.textPrimary,
                       breaks: line.starts)
                .transition(.opacity.combined(with: .offset(y: 8)))
        }
    }

    /// **THE SENTENCE'S ONE SIZE (prd §1501).** Every word of every Move
    /// sentence, and of the create flow, wears it; nothing picks another.
    /// `heading34` since prd §1679 (was `heading52`): the verbs, the sentence,
    /// its choices and the foot are one size, a screen's name in the app.
    /// **THREE INKS (prd §1731):** a word you have settled is white, the
    /// one being asked is `DS.pickInk`, and what is still to come — an
    /// empty blank, a small word — is grey. Nothing dims: the open word is
    /// the only pink one, so it needs no help standing out (retires
    /// §1616's step-back).
    static var settledInk: Color { DS.textPrimary }
    static var glueInk: Color { DS.textSecondary }
    static let rung: DSTextStyle = .heading34
    /// A choice is the Wallet's own row (prd §1731, retiring §1681's
    /// heading24): the name at `body17` over its line at `subhead12`, the
    /// figure at `price17`, so a token reads here as it does in Holdings.
    static let choiceRung: DSTextStyle = .body17
    /// A choice's mark: the Wallet's list size (prd §1681, was 44).
    static let listMark: CGFloat = DS.Face.list
    /// A choice's row, at least: the word and its line with air (prd §1681).
    static let listRowHeight: CGFloat = 52
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
    /// `lit` is the blank whose list lights the word; a word that opens
    /// another's list (an unanswerable "when") stays its own colour.
    /// A blank's tap, the word's in the sentence and its row's under it (prd
    /// §1779): the same refusals, the same list.
    private func tapBlank(_ which: Blank) {
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
        // Nowhere else to arrive: the word says so rather than opening a
        // list of one (prd §83, §1600).
        if which == .destination, destinations.count < 2 {
            say(String(localized: "Swaps on \(network.name) stay on \(network.name)"))
            return
        }
        if which == .buy, lockedBuy != nil {
            say(String(localized: "One token for the whole swap"))
            return
        }
        // The amount's rows are sums of a token: with none picked yet, or a
        // verb whose amount is typed alone, its row raises the keys.
        if which == .amount, with == nil || !(verb == .send || verb == .swap) {
            focus = .amount
            DSHaptic.selection()
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
                    toBefore = (to, resolved)
                    to = ""
                    resolved = nil
                }
                // Every list opens with the keyboard down, so it has the
                // room to the foot; its search row raises the keys (§1442b).
                focus = nil
            }
        }
        DSHaptic.selection()
    }

    /// **A WORD OF THE SENTENCE THAT CAN CHANGE (prd §1781, amending §1438:
    /// user, 2026-11-13, "i don't think anything in the sentence should be
    /// tappable", "the user has to choose from the stuff below it").** It is
    /// drawn as a word and is no control. What it would have opened is a row
    /// under the sentence instead: every such word reports itself here
    /// (`MoveSentenceBlanksKey`), and `choiceRowList` draws one row for each,
    /// so a sentence can never hold a choice that has no row.
    private func blank(_ text: String, ink: Color, _ which: Blank, lit: Blank? = nil, empty: Bool = false, label: Text) -> some View {
        let lit = lit ?? which
        return word(text, ink: open == lit ? DS.pickInk : ink)
            // `empty` is said by the caller: two tertiary inks made apart do
            // not compare equal, and the To row read "address" for it.
            .preference(key: MoveSentenceBlanksKey.self,
                        value: [MoveSentenceBlank(opens: which, names: lit, text: text, empty: empty)])
            // A pick rises into its blank from the list under it (§1438b).
            .transition(.asymmetric(insertion: .offset(y: 28).combined(with: .opacity), removal: .opacity))
    }

    /// The amount's word, reported as a blank is: its row is Amount.
    private func amountBlank(dollars: Bool) -> some View {
        let shown = dollars ? "$" + amount : [amount, with?.token.symbol ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        return Color.clear.preference(key: MoveSentenceBlanksKey.self,
                                      value: [MoveSentenceBlank(opens: .amount, names: .amount, text: shown, empty: amount.isEmpty)])
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
        case .receive, .buy, .sweep, .deposit, .lend: true
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
        MoveClause(glue: glue, glueInk: leads ? DS.textSecondary : MoveSentence.glueInk, trail: inDollars ? nil : trail) {
            // The figure and its token wrap between them when the two are
            // wider than a line ("1234567.89" over "USDC"), never truncate.
            MoveClauseLayout(spacing: 8) {
                // Nothing picked, nothing typed: the clause is the token's
                // blank alone, "Swap token for token." (prd §1754). The
                // figure appears with the token, or the moment it is typed.
                if !sellBare {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        if inDollars { word("$", ink: amount.isEmpty ? DS.textTertiary : MoveSentence.settledInk) }
                        amountField
                    }
                }
                if !inDollars || sellBare { withWord }
            }
            .background { amountBlank(dollars: inDollars) }
            .dsCardLead(Text("Edits the amount")) { if stage == nil { focus = .amount } }
        }
        .layoutValue(key: FlowBreak.self, value: leads)
        if inDollars, !sellBare {
            MoveClause(glue: String(localized: "of"), trail: trail) { withWord }
        }
    }

    /// The line being filled has no token, no figure and no cursor: it is
    /// drawn as the token's blank alone (prd §1754).
    private var sellBare: Bool { with == nil && amount.isEmpty && focus != .amount }

    /// A kept line: tap it to edit it in place, hold it to remove it.
    @ViewBuilder private func keptSellClause(_ id: UUID, glue: String?, trail: String?, leads: Bool = false) -> some View {
        let line: (amount: String, token: Op.Token)? = {
            if let s = keptSwaps.first(where: { $0.id == id }) { return (s.amount, s.sell) }
            if let p = keptSends.first(where: { $0.id == id }) { return (p.amount, p.token) }
            return nil
        }()
        if let s = line {
            MoveClause(glue: glue, glueInk: leads ? DS.textSecondary : MoveSentence.glueInk, trail: trail) {
                word(Self.figure(s.amount, decimals: s.token.decimals) + " " + s.token.symbol, ink: MoveSentence.settledInk)
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
                // Its deposit address was never paid: the line holds it again.
                zkMoneyUsed.remove(sent.to.lowercased())
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

    /// The verbs Move offers here, A–Z in the reader's language (prd §1547).
    private var offeredVerbs: [Verb] {
        Verb.allCases.filter { ($0 != .buy || buyAvailable) && ($0 != .lend || AaveLend.on) }
            .sorted { title($0).localizedStandardCompare(title($1)) == .orderedAscending }
    }

    /// **THE VERB IS THE SENTENCE'S FIRST WORD (prd §1681, retiring the
    /// verbs' own line, §1438a, and its scroll, §1679 item 2).** Pink, as
    /// every word that changes is; a tap opens the verbs under the sentence.
    /// The verb while its move is under way (prd §1754).
    private func going(_ v: Verb) -> String {
        switch v {
        case .swap: String(localized: "Swapping")
        case .send: String(localized: "Sending")
        case .sweep: String(localized: "Sweeping")
        case .buy: String(localized: "Spending")
        case .receive, .deposit, .lend: title(v)
        }
    }

    private func verbWord(_ text: String, ink: Color = MoveSentence.settledInk) -> some View {
        blank(text, ink: ink, .verb, label: Text("\(text), change what Move does"))
            .disabled(stage != nil || privateMove.acting || lendMove.acting)
    }

    /// Lend's own word, which its sentence leads with (prd §1674).
    private var lendWord: String {
        let done = if case .done = lendMove.stage { true } else { false }
        return switch (lendMove.mode, done) {
        case (.lend, false): String(localized: "Lend")
        case (.lend, true): String(localized: "Lent")
        case (.takeBack, false): String(localized: "Take back")
        case (.takeBack, true): String(localized: "Took back")
        }
    }

    /// The verbs as Move's list rows (prd §1681): a glyph and the verb, no
    /// line under it (a verb says what it does); the current one pink.
    /// **THE WHOLE MENU, A–Z, AT ONE SIZE (prd §1781, restoring §1547 and
    /// retiring §1779's ranking and its Make private; user, 2026-11-13:
    /// "the row of move verbs needs to stay alphabetical. it's confusing if
    /// not", "we want to see that entire menu", and of Make private, "its
    /// still confusing").** Private is a place, not a verb: Send's To leads
    /// with your private balance and your private account, and From offers
    /// them where money is.
    private var verbList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(offeredVerbs, id: \.self) { v in
                listRow(title(v), symbol: glyph(v), bareSymbol: true, rung: .heading34) { pickVerb(v) }
            }
        }
    }

    private func pickVerb(_ v: Verb) {
        withAnimation(DS.Motion.standard) {
            open = nil
            guard v != verb || receipt != nil || privateMode != nil || freshReceive || aztecReceive || aztecMode != nil || railgunOpen else { return }
            privateMode = nil
            railgunOpen = false
            aztecMode = nil
            freshReceive = false
            aztecReceive = false
            verb = v
            receipt = nil
        }
        DSHaptic.selection()
    }

    private func glyph(_ v: Verb) -> String {
        switch v {
        case .swap: "arrow.up.arrow.down"
        case .send: "arrow.up"
        case .receive: "arrow.down"
        case .buy: "creditcard"
        case .sweep: "tray.and.arrow.down"
        case .deposit: "plus"
        case .lend: "building.columns"
        }
    }

    private func title(_ v: Verb) -> String {
        switch v {
        case .swap: String(localized: "Swap")
        case .send: String(localized: "Send")
        case .receive: String(localized: "Receive")
        case .buy: String(localized: "Spend")
        case .sweep: String(localized: "Sweep")
        case .deposit: String(localized: "Buy")
        case .lend: String(localized: "Lend")
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
            // roll as an amount row is picked (§1438b); the field still takes the tap.
            .foregroundStyle(typing || amount.isEmpty ? DS.pickInk : .clear)
            .overlay(alignment: .leading) {
                if !typing, !amount.isEmpty {
                    Text(verbatim: amount)
                        .dsText(rung)
                        .foregroundStyle(MoveSentence.settledInk)
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
        blank(with?.token.symbol ?? String(localized: "token"), ink: with == nil ? DS.textTertiary : MoveSentence.settledInk,
              .with, empty: with == nil, label: Text("Spend \(with?.token.symbol ?? ""), change"))
    }

    @ViewBuilder private var buyWord: some View {
        if let buy {
            // Short in the sentence, the ≈ and the exact figure in the
            // print (§1479), so the clause stays whole at the biggest rung.
            // A price's order states what it gets in the line, never the pools' figure.
            let back = limiting ? nil : buyTotal.map { Self.short($0, decimals: buy.token.decimals) + " " }
                ?? (pricing && staleBack?.id == buy.id ? staleBack?.text : nil)
            // The whole swap's result, pink like every value; locked by a
            // kept swap (§1442c), a tap says so (§1442g).
            let symbol = crossBuy?.symbol ?? buy.token.symbol
            let word = blank((back ?? "") + symbol + (networkPicked ? "" : "."), ink: MoveSentence.settledInk,
                             .buy, label: Text("For \(symbol), change"))
            if pricing {
                // While the pools price it, the word breathes: working, not stuck.
                word.phaseAnimator([1.0, 0.4]) { content, phase in content.opacity(phase) } animation: { _ in .easeInOut(duration: 0.9) }
            } else {
                word
            }
        } else {
            // The sentence's last word until a network is picked (prd §1754).
            blank(networkPicked ? String(localized: "token") : String(localized: "token."),
                  ink: DS.textTertiary, .buy, empty: true, label: Text("Pick what you want"))
        }
    }

    /// A swap is being priced: everything is there but the pools' answer.
    private var pricing: Bool {
        verb == .swap && buy != nil && units != nil && !over && quote == nil && quoteNote == nil
    }

    private var toWord: some View {
        // A request link being read is named, never spelled (prd §1751;
        // user, of a short link's minute on Aztec: "doesn't say accountless
        // says the https address").
        let shown = resolved?.name ?? (resolved.map { YourAccount.short($0.address) })
            ?? (to.isEmpty ? String(localized: "address")
                : ZkMoneyLink.spellsLink(to) ? String(localized: "zk.money request")
                : to.contains(where: { ".@ ".contains($0) }) ? to : AddressTail.short(to))   // a pasted address waits as its tail (§1553)
        let missing: Bool = { if case .missing = lookup { true } else { false } }()
        return blank(shown, ink: toWarningInk ?? (resolved?.imitates != nil || missing ? DS.attentionInk : resolved == nil ? DS.textTertiary : MoveSentence.settledInk),
                  .to, empty: resolved == nil && to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  label: Text("To \(shown), change"))
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
            if networkPicked {
                blank(network.name + ".", ink: MoveSentence.settledInk, .network, label: Text("On \(network.name), change"))
            } else {
                blank(String(localized: "network."), ink: DS.textTertiary, .network, empty: true, label: Text("Pick a network"))
            }
        }
    }

    /// The network a swap leaves (prd §1555, §1600).
    private var originWord: some View {
        Group {
            if networkPicked {
                blank(network.name, ink: MoveSentence.settledInk, .network, label: Text("From \(network.name), change"))
            } else {
                blank(String(localized: "network"), ink: DS.textTertiary, .network, empty: true, label: Text("Pick a network"))
            }
        }
    }

    /// The network it arrives on, the sending one until another is picked:
    /// opens "Get <token> on" (prd §1600). Before a network is picked it is
    /// the same blank as the first.
    private var destinationWord: some View {
        Group {
            if networkPicked {
                blank(buyHome.name + (whenSpoken ? "" : "."), ink: MoveSentence.settledInk, .destination, label: Text("Get it on \(buyHome.name), change"))
            } else {
                // A price's clause carries the full stop while it stands (prd §1683, §1754).
                blank(whenSpoken ? String(localized: "network") : String(localized: "network."),
                      ink: DS.textTertiary, .network, empty: true, label: Text("Pick a network"))
            }
        }
    }

    /// A token list's search, its first row: the sentence's word never turns
    /// into a field, so the line never reflows (§1442b).
    private func searchRow(for which: Blank) -> some View {
        HStack(spacing: DS.Space.s3) {
            Image(systemName: "magnifyingglass")
                .dsGlyph(.body, weight: .semibold)
                .foregroundStyle(DS.textSecondary)
                .frame(width: Self.listMark)
                .accessibilityHidden(true)
            if which == .to {
                // To opens like a token list (§1442b, §1442h): keyboard down,
                // the book in reach, and this row for a name, an ENS name or
                // an address; Done takes what resolved.
                wordField(String(localized: "Name, ENS or address"), text: to) {
                    TextField(String(localized: "Name, ENS or address"), text: $to, prompt: Text(verbatim: ""))
                        .focused($focus, equals: .to)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { if resolved != nil { pick {} } }
                }
            } else {
                // A contract pasted here is read off each network
                // (`lookUpPasted`), so the field says so and the list keeps no
                // paste row at its foot (prd §1533, user: "inside search bar
                // say search or paste").
                let prompt = open == .buy || open == .arrives
                    ? String(localized: "Search or paste an address")
                    : String(localized: "Search")
                wordField(prompt, text: search) {
                    TextField(prompt, text: $search, prompt: Text(verbatim: ""))
                        .focused($focus, equals: .search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .task(id: search) { await lookUpPasted() }
                }
            }
        }
        .frame(minHeight: Self.listRowHeight)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { searchHeight = $0 }
    }

    /// The search row's own height, which the box under the sentence keeps
    /// for it (§1679: its prompt may take two lines).
    @State private var searchHeight: CGFloat = 0

    /// A search field at a choice's size (prd §1681): what you type wears
    /// the choice's rung, and so does the prompt, drawn here because a field's own
    /// placeholder can neither wrap nor shrink — two lines, then smaller,
    /// never cut ("Search or paste an address" keeps §1533's words).
    private func wordField<Field: View>(_ prompt: String, text: String,
                                        @ViewBuilder _ field: () -> Field) -> some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(verbatim: prompt)
                    .dsText(Self.choiceRung)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            field()
                .dsText(Self.choiceRung)
                .foregroundStyle(DS.textPrimary)
        }
    }

    // MARK: - The space under it

    /// The sentence's own height, so the list under it takes what is left.
    @State private var sentenceHeight: CGFloat = 0

    /// The words of the sentence on screen that can change, in its order.
    @State private var sentenceBlanks: [MoveSentenceBlank] = []

    /// Under the sentence: the line, or a blank's choices. One box for every
    /// blank, the same size whichever is open, its lists crossfading inside
    /// it — so moving between blanks moves nothing (§1442a, user: "it is very
    /// jittery. needs to be stable"). Line and box overlap while they swap,
    /// rather than stacking for the length of the animation.
    private func space(room: CGFloat, inset: CGFloat = 0) -> some View {
        ZStack(alignment: .topLeading) {
            if let open = inlineOpen {
                choices(room: choicesRoom(room), inset: inset, searches: Self.searches(open), which: open) {
                    ZStack(alignment: .topLeading) {
                        list(for: open)
                            .id(open)
                            .transition(.opacity)
                    }
                }
                // The box rises into the space and fades as its pick lands.
                .transition(.asymmetric(insertion: .offset(y: 24).combined(with: .opacity), removal: .opacity))
            } else {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    choiceRows
                    line
                    if offersPasteLink { pasteLinkRow }
                }
                .transition(.opacity)
            }
        }
    }

    /// The lists that lead with a search field.
    static func searches(_ which: Blank) -> Bool {
        which == .with || which == .buy || which == .to || which == .arrives || which == .merchant
    }

    /// One blank's list, wherever it is drawn.
    @ViewBuilder private func list(for which: Blank) -> some View {
        switch which {
        case .verb: verbList
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
        case .depositCoin: depositCoinList
        case .depositNetwork: depositNetworkList
        case .when: whenList
        case .until: untilList
        case .from: fromList
        case .amount: amountList
        }
    }

    /// **A LIST IS A MENU ON ITS ROW (prd §1784, user, of a mock that opened
    /// one under each row: "ya that is so much better").** A row's choices
    /// open as a menu attached to it: the rows stay where they are, the
    /// sentence over them, the foot under them. The lists themselves are the
    /// ones the page drew (their search, their marks, "Another amount"). The
    /// verbs' menu is the page and stays whole; a list with no row on screen
    /// to hang from still opens in the page.
    private var menuOpen: Blank? {
        guard let open, open != .verb, choiceRowList.contains(where: { $0.opens == open }) else { return nil }
        return open
    }

    /// The list drawn in the page: the verbs', or one with no row to hang from.
    private var inlineOpen: Blank? { menuOpen == nil ? open : nil }

    /// Whether this row's menu is up; closed by a tap outside it, the list
    /// closes with no pick.
    private func menuShown(_ which: Blank?) -> Binding<Bool> {
        Binding(get: { which != nil && menuOpen == which },
                set: { shown in if !shown, open == which { open = nil } })
    }

    /// A row's list as its menu: as wide as a menu, as tall as its rows up
    /// to `menuRoom`, on the system's own popover ground.
    private func menu(_ which: Blank) -> some View {
        choices(room: Self.menuRoom, searches: Self.searches(which), which: which, named: false) {
            list(for: which)
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s4)
        .padding(.bottom, DS.Space.s2)
        .frame(width: Self.menuWidth)
        // As tall as its rows: the popover is sized by what it holds.
        .fixedSize(horizontal: false, vertical: true)
        .environment(chrome)
        .onAppear { menuUp = true }
        .onDisappear { menuGone() }
        .presentationCompactAdaptation(.popover)
        // Thick enough that the foot's act does not read through the rows.
        .presentationBackground(.ultraThickMaterial)
    }

    /// A menu has left the screen: after a pick, the next row still to be
    /// filled opens its own (prd §1782, §1784).
    private func menuGone() {
        menuUp = false
        guard advances else { return }
        advances = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            advance()
        }
    }

    static let menuWidth: CGFloat = 320
    static let menuRoom: CGFloat = 300

    /// **ROWS CHANGE IT, THE SENTENCE SAYS IT (prd §1781, completing §1779;
    /// a tester, 2026-11-13: "I had no idea words are tappable"; the user:
    /// "the sentence itself is not tappable and the user has to choose from
    /// the stuff below it").** One row for every word of the sentence that
    /// can change, in every verb: its name grey, what is picked in white, a
    /// chevron because a list opens. A row not filled in says "Choose", and
    /// the first of those is in the pick's pink: where to go next. The rows
    /// are read off the sentence on screen, so none is listed by hand.
    private var choiceRowList: [LedgerRow] {
        guard receipt == nil, stage == nil else { return [] }
        let pick = String(localized: "Choose")
        var rows: [(rank: Int, row: LedgerRow)] = []
        // Where the money leaves from (prd §1779): the one visible place to
        // step into your private balance or your private account.
        if verb == .send, sendsPrivately || sendsFromAztec {
            rows.append((Self.rowRank(.from), LedgerRow(id: "choiceFrom", name: Self.rowName(.from, verb: verb),
                                                        value: String(localized: "Public"), opens: .from)))
        }
        var seen: Set<String> = []
        for b in sentenceBlanks {
            // The verb is the foot's back button's; the network rides its
            // token's row in Send and Swap, where a token is on one network.
            guard b.names != .verb else { continue }
            let folds = verb == .send || verb == .swap
            if b.names == .network, folds { continue }
            // A swap that can only stay where it is has no row to say so.
            if b.names == .destination, destinations.count < 2 { continue }
            let id = "choice\(b.names)"
            guard seen.insert(id).inserted else { continue }
            var value = b.empty ? pick : Self.rowValue(b.text)
            if !b.empty, b.names == .with, folds, networkPicked { value += " · " + network.name }
            if !b.empty, b.names == .amount, inDollars, let with, units != nil, let other = otherUnit(with) { value += " · " + other }
            rows.append((Self.rowRank(b.names), LedgerRow(id: id, name: Self.rowName(b.names, verb: verb), value: value, opens: b.opens)))
        }
        var sorted = rows.enumerated().sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }.map(\.element.row)
        if let next = sorted.firstIndex(where: { $0.value == pick }) { sorted[next].valueInk = DS.pickInk }
        return sorted
    }

    /// Opens the list of the first row still to be filled (prd §1782). The
    /// amount's list is sums of a token, so with no token picked the token
    /// is asked first; nothing opens while a figure is being typed.
    private func advance() {
        guard verb == .send || verb == .swap, open == nil, focus == nil, receipt == nil, stage == nil else { return }
        let pick = String(localized: "Choose")
        guard let next = choiceRowList.first(where: { $0.value == pick })?.opens else { return }
        tapBlank(next == .amount && with == nil ? .with : next)
    }

    /// A word of the sentence as its row's value: without the full stop the
    /// sentence ends on.
    static func rowValue(_ text: String) -> String {
        text.hasSuffix(".") ? String(text.dropLast()) : text
    }

    /// What a row is called, by the word it changes.
    static func rowName(_ which: Blank, verb: Verb) -> String {
        switch which {
        case .verb: String(localized: "Move")
        case .from: String(localized: "From")
        case .to: String(localized: "To")
        case .amount: String(localized: "Amount")
        case .with: verb == .buy ? String(localized: "Pay with") : String(localized: "Token")
        case .buy: String(localized: "For")
        case .network, .elsewhere, .depositNetwork: String(localized: "Network")
        case .destination: String(localized: "Arrives on")
        case .arrives: String(localized: "Arrives as")
        case .elsewhereCoin, .depositCoin: String(localized: "Token")
        case .group: String(localized: "Category")
        case .merchant: String(localized: "Merchant")
        case .when: String(localized: "When")
        case .until: String(localized: "Until")
        }
    }

    /// The rows' order, the same in every verb: who, how much, of what.
    static func rowRank(_ which: Blank) -> Int {
        let order: [Blank] = [.from, .to, .group, .merchant, .amount, .with, .depositCoin, .elsewhereCoin, .buy,
                              .network, .elsewhere, .depositNetwork, .destination, .arrives, .when, .until, .verb]
        return order.firstIndex(of: which) ?? order.count
    }

    /// What Add kept, in Send and Swap: lines of the sentence, each a row
    /// that opens it again and a mark that removes it (prd §1781: the
    /// sentence's own lines took the tap and the long press before).
    private var keptRowLines: [(id: UUID, words: String)] {
        guard receipt == nil, stage == nil else { return [] }
        switch verb {
        case .send: return keptSends.map { ($0.id, Self.figure($0.amount, decimals: $0.token.decimals) + " " + $0.token.symbol) }
        case .swap: return keptSwaps.map { ($0.id, Self.figure($0.amount, decimals: $0.sell.decimals) + " " + $0.sell.symbol) }
        default: return []
        }
    }

    /// Send can leave from your private balance, or your private account.
    private var sendsPrivately: Bool { PrivateMove.available }
    private var sendsFromAztec: Bool { AztecProver.isAvailable && AztecAccountStore.shared.shown.address != nil }

    /// **FROM (prd §1779).** Three places at most, each named as the Wallet
    /// names it. Picking a private one opens its own sentence, which is
    /// where its rules are said; an Aztec address already typed goes along.
    private var fromList: some View {
        VStack(alignment: .leading, spacing: 0) {
            listRow(String(localized: "Public"), sub: network.name, symbol: "chart.pie", picked: true) {
                withAnimation(DS.Motion.standard) { open = nil }
                DSHaptic.selection()
            }
            if sendsPrivately {
                listRow(String(localized: "Your private balance"),
                        sub: (PrivacyNetwork.current(debugAsks: PrivateMove.debugNetwork) ?? .ethereum).name, symbol: "eye.slash") {
                    goPrivate(.send)
                }
            }
            if sendsFromAztec {
                listRow(String(localized: "Your private account"), sub: Self.aztecRule, symbol: "diamond") {
                    let typed = to.trimmingCharacters(in: .whitespaces)
                    goAztec(.send, recipient: AztecAddressText.isAztec(typed) ? typed.lowercased() : nil)
                }
            }
        }
    }

    @ViewBuilder private var choiceRows: some View {
        let rows = choiceRowList
        let kept = keptRowLines
        if !rows.isEmpty || !kept.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { r in
                    Button { if let which = r.opens { tapBlank(which) } } label: {
                        MoveChoiceRowLabel(name: r.name, value: r.value, ink: r.valueInk ?? DS.textPrimary)
                    }
                    .buttonStyle(RowPress())
                    .accessibilityHint(Text("Changes it"))
                    // No edge named: the system opens it toward the room there is.
                    .popover(isPresented: menuShown(r.opens), attachmentAnchor: .rect(.bounds)) {
                        if let which = r.opens { menu(which) }
                    }
                }
                ForEach(kept, id: \.id) { line in
                    HStack(spacing: 0) {
                        Button { edit(line.id) } label: {
                            MoveChoiceRowLabel(name: String(localized: "Added"), value: line.words)
                        }
                        .buttonStyle(RowPress())
                        .accessibilityHint(Text("Edits this line"))
                        Button { remove(line.id) } label: {
                            Image(systemName: "xmark")
                                .dsGlyph(.caption, weight: .semibold)
                                .foregroundStyle(DS.textSecondary)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(PressSpring())
                        .accessibilityLabel(Text("Remove"))
                    }
                }
                // **ADD IS A ROW (prd §1781, amending §1755's card):** the
                // foot holds the way back and the act; keeping this line and
                // starting the next is a row among the others, there once
                // the line can be kept and not before.
                if verb == .send || verb == .swap, !nothingToMove, pendingItem != nil {
                    Button { add() } label: {
                        ledgerRow(LedgerRow(id: "add", name: String(localized: "Add another"), ink: DS.textPrimary), chevron: "plus")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(RowPress())
                    .accessibilityHint(Text("Keeps this in the transaction and starts the next one"))
                }
            }
        }
    }

    /// **AMOUNT'S LIST (prd §1781).** The sums its row opens: dollars in
    /// steps, half, all, and a row that raises the keys for any other. A
    /// pick closes the list, as every list's does.
    @ViewBuilder private var amountList: some View {
        if let with {
            VStack(alignment: .leading, spacing: 0) {
                amountPicks(with, closes: true)
                listRow(String(localized: "Another amount"), rung: .heading24) {
                    withAnimation(DS.Motion.standard) { open = nil }
                    focus = .amount
                    DSHaptic.selection()
                }
            }
        }
    }

    // MARK: - Paste from the sentence (prd §1752)

    /// **A LINK ON THE CLIPBOARD IS OFFERED UNDER THE SENTENCE (prd §1752).**
    /// Send with To still blank and something to send: one word pastes a
    /// zk.money request without opening To's list. The system says only
    /// whether the clipboard looks like a link, so the word is "Paste link",
    /// never what the link is; the clipboard is read at the tap.
    private var offersPasteLink: Bool {
        clipboardLink && verb == .send && hint == nil && receipt == nil && stage == nil
            && privateMode == nil && !freshReceive && !fresh && !emptyEverywhere && !readFailed
            && to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var pasteLinkRow: some View {
        Button { pasteLink() } label: {
            Text("Paste link")
                .dsText(.body17)
                .foregroundStyle(DS.pickInk)
                .frame(minHeight: 44, alignment: .leading)
        }
        .buttonStyle(RowPress())
    }

    private func pasteLink() {
        let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Only a request link is taken from here: any other link has no
        // address to send to, and To's own list pastes an address.
        guard ZkMoneyLink.spellsLink(text) else {
            withAnimation(DS.Motion.standard) { clipboardLink = false }
            say(text.isEmpty ? String(localized: "Nothing to paste") : String(localized: "That link is not a payment request"))
            return
        }
        DSHaptic.snap()
        withAnimation(DS.Motion.standard) { to = text }
    }

    /// Whether the clipboard looks like a link: a pattern the system
    /// answers without showing it to the app, so no paste notice rises.
    private func readClipboard() async {
        let link = \UIPasteboard.DetectedValues.probableWebURL
        let found = (try? await UIPasteboard.general.detectedPatterns(for: [link])) ?? []
        let has = found.contains(link)
        if has != clipboardLink { withAnimation(DS.Motion.standard) { clipboardLink = has } }
    }

    // MARK: - Recent recipients (prd §1752)

    /// **RECENT LEADS To (prd §1752).** The last three people Send sent to
    /// from this account, kept on this phone as each send is taken. Send's
    /// own record and never the Wallet's rows: a round-up's buy, a deposit
    /// and a card's payment are sent rows too, and their one-time addresses
    /// are nobody to pay again. A zk.money tag is kept as the tag, so it is
    /// looked up afresh each time (prd §1692); anyone else as an address.
    enum RecentTo {
        static func key(_ account: String) -> String { "move.recentTo.\(account.lowercased())" }
        static func read(_ account: String) -> [String] {
            UserDefaults.standard.stringArray(forKey: key(account)) ?? []
        }
        /// What a taken batch adds, newest first: each plain send's tag or address.
        static func entries(_ batch: [Chain.Item]) -> [String] {
            batch.reversed().compactMap { item in
                // A tag paid from another network is a tag paid (prd §1770).
                if case .swap(let s) = item, let name = s.payeeName, ZkMoneyWire.tag(name) != nil { return name.lowercased() }
                guard case .send(let p) = item else { return nil }
                if let name = p.toName, ZkMoneyWire.tag(name) != nil { return name.lowercased() }
                return ZkMoney.knownName(for: p.to) == nil ? p.to : nil
            }
        }
        static func remember(_ batch: [Chain.Item], account: String) {
            let sent = entries(batch)
            guard !sent.isEmpty else { return }
            UserDefaults.standard.set(MoveSentence.recent(sent + read(account)), forKey: key(account))
        }
    }

    private func readRecentTo() {
        recentTo = RecentTo.read(account)
        readPeople()
    }

    /// **TO READS YOUR CONTACTS (prd §1773).** Someone in Contacts with a
    /// wallet Send can reach, found by any name they go by: the card's, a
    /// handle, an ENS name, a note. The index's last build, or one build
    /// here on the sentence's first open; never in a body.
    struct ToPerson: Identifiable, Equatable {
        let id: String
        let name: String
        let address: String
        /// Everything a search may hit, lowercased.
        let terms: String
    }

    private func readPeople() {
        let built = ContactIndexSources.contacts.isEmpty
            ? ContactIndexSources.rebuild(context: context) : ContactIndexSources.contacts
        people = MoveSentence.people(from: built.filter(ContactIndexSources.isListed)) { address in
            let kind = AddressBook.shared.entry(for: address)?.kind
            return kind != .contract && kind != .key
        }
    }

    /// One row per contact with a 0x wallet `allowed` passes: their first.
    static func people(from contacts: [Contact], allowed: (String) -> Bool) -> [ToPerson] {
        contacts.compactMap { c in
            guard !c.isUnnamed,
                  let wallet = c.identities.first(where: { $0.kind == .wallet && ENS.isHexAddress($0.body) && allowed($0.body) })
            else { return nil }
            let terms = ([c.name] + c.identities.map(\.body) + c.keywords).joined(separator: " ").lowercased()
            return ToPerson(id: c.id, name: c.name, address: wallet.body, terms: terms)
        }
    }

    /// Each one once, in the order given, three at most.
    static func recent(_ addresses: [String], cap: Int = 3) -> [String] {
        var out: [String] = []
        for address in addresses where !out.contains(where: { $0.caseInsensitiveCompare(address) == .orderedSame }) {
            out.append(address)
            if out.count == cap { break }
        }
        return out
    }

    /// Everything under the sentence, down to the edge (or the keys).
    private func choicesRoom(_ room: CGFloat) -> CGFloat {
        max(140, room - sentenceHeight - DS.Space.s4 - (inTray ? DS.Space.s2 : DS.Space.s6))
    }

    /// An open list in the tray, keys down (with them up they are the edge).
    private var reachesEdge: Bool { inTray && inlineOpen != nil && !chrome.keyboardUp }

    /// The home bar's inset an open list's last row clears at the end.
    private func listReach(_ geo: GeometryProxy) -> CGFloat {
        reachesEdge ? geo.safeAreaInsets.bottom : 0
    }

    /// The rows' own height, so a short list draws a short box (§1442b).
    @State private var rowsHeight: CGFloat = 0

    /// A blank's choices, standing on the tray in the sentence's column
    /// with no surface of their own (prd §1616, retiring the glass card it
    /// borrowed from the rooms tray, §1203: over the tray's solid ground the
    /// glass had nothing to show through, so it drew as a plate). As tall as its rows, up to the room under the
    /// sentence, then they scroll. It grows downward only: the sentence
    /// above never moves (§1442b). A token list leads with its search.
    private func choices<Rows: View>(room: CGFloat, inset: CGFloat = 0, searches: Bool, which: Blank,
                                     named: Bool = true, @ViewBuilder _ rows: () -> Rows) -> some View {
        // Every list but the verbs' leads with its own name, which closes it
        // (prd §1781): the sentence's word no longer does.
        // A menu closes by a tap outside it and needs no name (prd §1784).
        let named = named && which != .verb
        let head: CGFloat = (searches ? max(searchHeight, Self.listRowHeight) : 0) + (named ? Self.listRowHeight : 0)
        return VStack(alignment: .leading, spacing: 0) {
            if named { MoveListBack(name: Self.rowName(which, verb: verb)) { tapBlank(which) } }
            if let hint {
                hintText(hint)
                    .padding(.top, DS.Space.s3)
            }
            if searches { searchRow(for: which) }
            ScrollView {
                rows()
                    .padding(.vertical, DS.Space.s2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowsHeight = $0 }
            }
            .scrollIndicators(.hidden)
            // Scrolled to the end, the last row clears the home bar.
            .contentMargins(.bottom, inset, for: .scrollContent)
            .frame(height: max(56, min(rowsHeight + inset, room - head)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The other unit (tap to type in it), what you have, the fee.
    @ViewBuilder private var line: some View {
        if let hint {
            hintText(hint)
        } else if let receipt {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                // One fact a row, as the ledger before it (prd §1754).
                ForEach(receipt.detail.components(separatedBy: " · ").filter { !$0.isEmpty }, id: \.self) { fact in
                    Text(verbatim: Self.lineCase(fact)).dsText(.body17).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let link = receipt.link, let name = receipt.linkName {
                    Button { openURL(link) } label: {
                        Text(verbatim: receipt.linkTitle ?? String(localized: "View on \(name)")).dsText(.body17).foregroundStyle(DS.pickInk).frame(minHeight: 44)
                    }
                    .buttonStyle(RowPress())
                }
                // A first send to an unnamed address: name it here, and the
                // next send is a pick from your book (prd §1586).
                ForEach(receipt.names, id: \.self) { address in
                    DSDoorRow(icon: "person.crop.circle.badge.plus", title: Text("Name \(AddressTail.short(address))")) {
                        nameDraft = ""
                        naming = address
                    }
                    .transition(.opacity)
                }
                // A tag you paid and have not saved: one tap keeps it as a
                // contact, under the tag's own name (prd §1767). Contacts
                // renames it.
                ForEach(receipt.tags, id: \.self) { tag in
                    DSDoorRow(icon: "person.crop.circle.badge.plus", title: Text("Save \(tag)")) {
                        let name = tag
                        ContactBook.shared.save(Identity.make(.zkMoney, tag), name: name)
                        withAnimation(DS.Motion.standard) { self.receipt?.tags.removeAll { $0 == tag } }
                        DSHaptic.success()
                        say(String(localized: "Saved \(name)"))
                    }
                    .transition(.opacity)
                }
            }
        } else if verb == .deposit {
            depositLine
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
                        addressBlock(route.address)
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
                            addressBlock(account)
                            // The network the sentence names (prd §1486).
                            // In the door rows' column, with "Private" and
                            // "From another wallet" (prd §1616 item 7).
                            Text("Any token on \(network.name).")
                                .dsText(.body17).foregroundStyle(DS.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, DSDoorRowLabel.textColumn)
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
                    // **THE PRIVATE DOORS, VISIBLE (prd §1779; a tester:
                    // "when user hits receive they can't see private balance
                    // either", "it always goes back to main").** §1719 put
                    // both behind the network's word, which nobody knew to
                    // tap. Rows, as "Private" was a row before it.
                    if PrivateMove.freshAvailable {
                        DSDoorRow(icon: "eye.slash", label: "Receive privately") { goFresh() }
                    }
                    if AztecProver.isAvailable, AztecAccountStore.shared.shown.address != nil {
                        DSDoorRow(icon: "diamond", label: "Receive on Aztec") {
                            withAnimation(DS.Motion.standard) { open = nil; aztecReceive = true }
                            DSHaptic.selection()
                        }
                        .aztecDoor()
                    }
                    DSDoorRow(icon: "arrow.down.left", label: "From another wallet") {
                        ReceiveFromWalletSheet.present(account: account, sample: YourAccountDemo.isDemo(account))
                    }
                }
            }
        } else if limiting, let with {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                limitLine(with)
                ledger(door: false)
            }
        } else if let warning = leadWarning {
            // A warning takes the grey line's place (prd §1509 item 2): red
            // when reported or refused, amber to check; one line, and Details
            // lists every finding. A refusal dims the verb (canvas figure 9).
            VStack(alignment: .leading, spacing: 0) {
                detailsToggle(Text(verbatim: warningLine(warning) + " ")
                    .foregroundStyle(warning.red ? DS.destructiveInk : DS.attentionInk))
                if details { moveDetails }
                ledger(door: false).padding(.top, DS.Space.s2)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else if let note = lineNote {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    if note == quoteNote, let quoteFrom { Self.mark(of: quoteFrom) }
                    Text(verbatim: note).dsText(.body17).foregroundStyle(DS.attentionInk)
                }
                ledger(door: false)
            }
        } else if let with {
            // One line of small print (§1442f): the other unit and the fee.
            // The exchange's credit is the foot's, and the amount's own rows
            // stand under it here rather than stranded at the foot.
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                if verb == .send, let lookup { lookupLine(lookup) }
                if let words = requestFeeWarning {
                    Text(verbatim: words).dsText(.body17).foregroundStyle(DS.attentionInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // **MORE THAN YOU HAVE, WITH THE FIX (prd §1586):** the amount's
                // rows stay, and the note is a door to all of it.
                if verb == .send || verb == .swap, over {
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        Text("More than you have").dsText(.body17).foregroundStyle(DS.attentionInk)
                        Button {
                            // In the token's units: dollars round, and could
                            // land a cent over what is there.
                            inDollars = false
                            shareBinding(with).wrappedValue = 100
                            DSHaptic.snap()
                        } label: {
                            Text("Use all \(Op.spoken(left(with), decimals: with.token.decimals)) \(with.token.symbol)")
                                .dsText(.body17).foregroundStyle(DS.pickInk).frame(minHeight: 44)
                        }
                        .buttonStyle(RowPress())
                        .disabled(stage != nil)
                    }
                }
                // The amount's rows are a list its row opens (prd §1781,
                // amending §1442g): `amountList`.
                // **ONE LEDGER (prd §1754, retiring §1509's "$25.00 · Fee up
                // to $0.01 · Details"):** a grey name and its figure, a row
                // each; the last row opens this exact operation under it.
                ledger(door: offersDetails)
                // A test network says so wherever it is picked (prd §1439).
                if network.isTest {
                    Text("test tokens").dsText(.body17).foregroundStyle(DS.attentionInk)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        } else if !networkPicked {
            EmptyView()
        } else if heldBy[network.chainId] == nil {
            Text("Reading…").dsText(.body17).foregroundStyle(DS.textSecondary)
        } else if held.isEmpty, unread.contains(network.chainId) {
            Text("Couldn't read \(network.name)").dsText(.body17).foregroundStyle(DS.attentionInk)
        } else if held.isEmpty {
            Text("Nothing on \(network.name) yet").dsText(.body17).foregroundStyle(DS.textSecondary)
        }
    }

    /// "Looking up uma.eth", or "No address answers to uma.eth" with a way
    /// on: paste one (prd §1586).
    @ViewBuilder private func lookupLine(_ l: Lookup) -> some View {
        switch l {
        case .looking(let name):
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                DSSpinner()
                Text("Looking up \(name)").dsText(.body17).foregroundStyle(DS.textSecondary)
            }
        case .missing(let name):
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text("No address for \(name)").dsText(.body17).foregroundStyle(DS.attentionInk)
                    .fixedSize(horizontal: false, vertical: true)
                pasteRow { to = $0 }
            }
        case .refused(let words):
            Text(verbatim: words).dsText(.body17).foregroundStyle(DS.attentionInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var lineNote: String? {
        // With a token picked, "More than you have" stands over its own fix
        // in the token's block (prd §1586).
        if verb != .receive, over, with == nil || !(verb == .send || verb == .swap) { return String(localized: "More than you have") }
        if verb == .swap, let quoteNote { return quoteNote }
        if verb == .send {
            if malformed { return String(localized: "Check the address") }
            if let zkMoneyRefusal { return zkMoneyRefusal }
            if tagConverts || tagCrosses, let tagSwapNote { return tagSwapNote }
        }
        // What signing would refuse, said before the tap: a fee the account
        // cannot pay, a node that would not price it (prd §1509).
        if verb == .send || verb == .swap, let refusal = shownPreview?.refusal { return refusal }
        return nil
    }

    // MARK: - The ledger (prd §1754)

    /// One row of the ledger: a grey name, its figure trailing. With no
    /// figure the name is the whole line (a credit in its service's words).
    struct LedgerRow: Identifiable {
        let id: String
        let name: String
        var value: String = ""
        var marks: [String] = []
        var ink: Color?
        var strong = false
        var opens: Blank?
        /// The figure's own ink, when it differs from the name's.
        var valueInk: Color?
    }

    /// **ONE LEDGER UNDER THE SENTENCE (prd §1754, user: "the part that
    /// worries me is where we have smaller font and what the text says that
    /// it is too wordy").** Every small fact about the move is a row in one
    /// shape at one size, `body17`: When, what you get, Round-ups, the fee,
    /// the exchange, the total. The pool's fee is in the price and is
    /// Details' to say; the foot keeps the acts alone.
    private var ledgerRows: [LedgerRow] {
        guard receipt == nil else { return [] }
        var rows: [LedgerRow] = []
        if verb == .swap, whenDrawn, !limiting {
            // "now" left the sentence; this row is the door to a price.
            rows.append(LedgerRow(id: "when", name: String(localized: "When"), value: String(localized: "Now"),
                                  opens: when == nil ? whenWaitsOn : .when))
        }
        if verb == .swap, !limiting, let back = quotePrint {
            rows.append(LedgerRow(id: "get", name: String(localized: "You get"), value: back))
        }
        if verb == .send {
            if let words = requestPrint { rows.append(LedgerRow(id: "request", name: words)) }
            // Swapped into USDC first (prd §1768): what reaches the tag,
            // exactly, before zk.money's own fee.
            if tagConverts || tagCrosses, let q = tagSwap, pendingItem != nil {
                rows.append(LedgerRow(id: "tagGets", name: String(localized: "They get"),
                                      value: Self.figure(q.minimumBuy, decimals: 6) + " USDC"))
            }
            if peopleCount > 1 { rows.append(LedgerRow(id: "people", name: String(localized: "To"), value: String(localized: "\(peopleCount) people"))) }
        }
        if verb == .buy {
            for (n, words) in buyPrint.enumerated() { rows.append(LedgerRow(id: "buy\(n)", name: Self.lineCase(words))) }
        }
        // Round-ups: this move's change, and the one time it moves the pot
        // to your private balance (prd §1690).
        let rounds = verb == .send || verb == .swap || (verb == .buy && buySells == nil)
        let change: Double? = rounds ? roundUpStep.flatMap { $0.change != "0" ? RoundUpsPot.dollars($0.change) : nil } : nil
        if rounds, roundUpStep?.moves == true, let words = roundUpPrint.first {
            rows.append(LedgerRow(id: "roundsMove", name: words))
        }
        if let change { rows.append(LedgerRow(id: "rounds", name: String(localized: "Round-ups"), value: Self.money(change))) }
        if verb == .send || verb == .swap || verb == .sweep, !limiting, let fee = feeFigure {
            rows.append(LedgerRow(id: "fee", name: String(localized: "Fee"), value: fee))
        }
        for (n, line) in exchangeCredit.enumerated() {
            rows.append(line.pools
                ? LedgerRow(id: "through\(n)", name: String(localized: "Through"), value: line.marks.formatted(.list(type: .and)), marks: line.marks)
                : LedgerRow(id: "through\(n)", name: line.text, marks: line.marks))
        }
        if let impact = impactWarning { rows.append(LedgerRow(id: "impact", name: impact, ink: DS.attentionInk)) }
        let sold: Double? = verb == .sweep ? sweepSoldUSD : (verb == .send || verb == .swap ? soldDollarsTotal : nil)
        if let sold {
            rows.append(LedgerRow(id: "total", name: String(localized: "Total"), value: Self.money(sold + (change ?? 0)), strong: true))
        }
        return rows
    }

    /// **NO SLIDER (prd §1754, user, shown four ways to set the amount:
    /// "probably D no slider"; every verb and the limit order since prd §1776,
    /// user: "no sliders", "Yes, everywhere").** The amount's choices are rows under the
    /// sentence, as every other word's are: the round dollar amounts you can
    /// cover, then Half and All with what each comes to; the one that is the
    /// amount wears the pick's pink. A tap on the figure still types any
    /// other, and the $ · token switch ends the first row's line.
    static let amountSteps: [Int] = [20, 50, 100]

    @ViewBuilder private func amountPicks(_ h: Tokens.Held, closes: Bool = false) -> some View {
        let share = shareBinding(h)
        let now = share.wrappedValue
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: DS.Space.s2) {
                // Its list is named at its head already (prd §1781).
                if !closes { Text("Amount").dsText(.body17).foregroundStyle(DS.textSecondary) }
                Spacer(minLength: DS.Space.s2)
                unitSwitch
            }
            .frame(minHeight: 44)
            if let usd = h.usd, h.price != nil {
                ForEach(Self.amountSteps.filter { Double($0) <= usd }, id: \.self) { step in
                    listRow(Self.money(Double(step)).replacingOccurrences(of: ".00", with: ""),
                            picked: currentDollars.map { abs($0 - Double(step)) < 0.005 } ?? false, rung: .heading24) {
                        withAnimation(DS.Motion.standard) {
                            inDollars = true
                            amount = "\(step)"
                            if closes { advances = true; open = nil }
                        }
                        DSHaptic.selection()
                    }
                }
            }
            listRow(String(localized: "Half"), trailing: h.usd.map { Self.money($0 / 2) },
                    picked: now == 50, rung: .heading24) {
                withAnimation(DS.Motion.standard) {
                    share.wrappedValue = 50
                    if closes { advances = true; open = nil }
                }
                DSHaptic.selection()
            }
            listRow(String(localized: "All"), trailing: h.usd.map { Self.money($0) },
                    picked: now == 100, rung: .heading24) {
                // In the token's units: dollars round, and could land a
                // cent over what is there (prd §1586).
                withAnimation(DS.Motion.standard) {
                    inDollars = false
                    share.wrappedValue = 100
                    if closes { advances = true; open = nil }
                }
                DSHaptic.snap()
            }
        }
        .disabled(stage != nil)
    }

    /// The fee's figure for its row: "up to $0.01", "under a cent".
    private var feeFigure: String? {
        guard let wei = shownPreview?.feeWei else { return nil }
        // Taken from your USDC (prd §1780): its own dollars, and it says so.
        if let units = shownPreview?.gasUSDC {
            return String(localized: "up to $\(YourAccountGas.spoken(units)) from your USDC")
        }
        if let usd = networkFeeUSD {
            return usd < 0.01 ? String(localized: "under a cent") : String(localized: "up to \(Self.money(usd))")
        }
        return String(localized: "up to \(YourAccountPreview.coin(wei)) ETH")
    }

    /// The ledger drawn. With `door`, its last row opens Details under it
    /// (a chevron after the figure), and a second tap closes it.
    @ViewBuilder private func ledger(door: Bool) -> some View {
        let rows = ledgerRows.isEmpty && door ? [LedgerRow(id: "details", name: String(localized: "Details"))] : ledgerRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { n, r in
                    if door, n == rows.count - 1 {
                        Button {
                            withAnimation(DS.Motion.standard) { details.toggle() }
                            DSHaptic.selection()
                        } label: { ledgerRow(r, chevron: details ? "chevron.up" : "chevron.down") }
                        .buttonStyle(RowPress())
                        .accessibilityHint(details ? Text("Hides the details") : Text("Shows what this transaction does"))
                    } else if let which = r.opens {
                        Button {
                            withAnimation(DS.Motion.standard) { open = which; search = ""; focus = nil }
                            DSHaptic.selection()
                        } label: { ledgerRow(r, chevron: "chevron.right") }
                        .buttonStyle(RowPress())
                        .disabled(stage != nil)
                    } else {
                        ledgerRow(r)
                    }
                }
                if door, details { moveDetails }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func ledgerRow(_ r: LedgerRow, chevron: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            if r.value.isEmpty { ForEach(r.marks, id: \.self) { Self.mark(of: $0).accessibilityHidden(true) } }
            Text(verbatim: r.name)
                .dsText(r.strong ? .heading17 : .body17)
                .foregroundStyle(r.ink ?? (r.strong ? DS.textPrimary : DS.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
            // The chevron follows the name, so every figure stands on the
            // page's own right edge, with the rows above it (user: "make
            // sure your indents match").
            if let chevron {
                Image(systemName: chevron).dsGlyph(.subhead, weight: .semibold)
                    .foregroundStyle(DS.textSecondary)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: DS.Space.s2)
            if !r.value.isEmpty {
                ForEach(r.marks, id: \.self) { Self.mark(of: $0).accessibilityHidden(true) }
                Text(verbatim: r.value)
                    .dsText(r.strong ? .heading17 : .body17)
                    .foregroundStyle(r.valueInk ?? r.ink ?? DS.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .frame(minHeight: 32)
        .contentShape(Rectangle())
    }

    // MARK: - Details (prd §1509)

    /// The preview of the sentence as it stands now; nil while it is read.
    private var shownPreview: Chain.Preview? {
        !previewKey.isEmpty && previewFor == previewKey ? preview : nil
    }

    /// Details is offered once there is a transaction to show.
    private var offersDetails: Bool { (verb == .send || verb == .swap || verb == .sweep) && !signing.isEmpty && !limiting }

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
            let demo = YourAccountDemo.findings(to: to.filter { !zkMoneyDeposits.contains($0.lowercased()) }, token: token)
            found += demo.findings
            with += demo.checkedWith
        } else {
            let sent = MoveChecks.sentTo(account, context: context)
            let named = MoveChecks.named()
            let own = Set([account.lowercased()] + [YourAccountKey.address?.lowercased()].compactMap { $0 })
            // A zk.money deposit address is new by design and proven to be
            // the tag's on chain: "never sent here" would be true of every one.
            for a in to where !zkMoneyDeposits.contains(a.lowercased())
                && !MoveWarnings.isKnown(a, sentTo: sent, named: Set(named.keys), own: own) {
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
        if let units = shownPreview?.gasUSDC, let u = Double(units) { return u / 1_000_000 }
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
        return ([account, String(network.chainId)] + lines).joined(separator: ";")
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
            let p = await Chain.preview(signing, account: account, roundUp: nil)
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

    /// The private account's line wherever a list offers it (prd §1779: the
    /// rule in view whenever Aztec is).
    static var aztecRule: String { String(localized: "Aztec to Aztec only") }

    private func listRow(_ title: String, sub: String? = nil, trailing: String? = nil,
                         mark: String? = nil, image: String? = nil, brand: String? = nil,
                         remote: String? = nil, symbol: String? = nil, face: String? = nil, dim: Bool = false,
                         picked: Bool = false, bareSymbol: Bool = false, rung: DSTextStyle = MoveSentence.choiceRung,
                         act: @escaping () -> Void) -> some View {
        // A choice is a word a step under the sentence (prd §1681): the
        // mark, the word and its line under it, the figure trailing. The current
        // pick wears the pick's ink, the sentence's word in the list (prd
        // §1616); `dim` is for a row left out.
        return Button(action: act) {
            HStack(spacing: DS.Space.s3) {
                if let face {
                    // A person: the face the Wallet draws for that address
                    // (its ENS avatar, else its tinted mark), never initials
                    // or an empty column (prd §1534).
                    WalletFace(address: face, size: Self.listMark, circular: true)
                        .accessibilityHidden(true)
                } else if let brand {
                    // An app's or a company's own mark (`BridgeIcon`), not a
                    // token's (`AssetMark` reads token art only, prd §1481).
                    BridgeIcon(name: brand, size: Self.listMark, circular: true)
                        .accessibilityHidden(true)
                } else if let image {
                    Image(image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: Self.listMark, height: Self.listMark)
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                } else if let remote {
                    // A picture the read named (Relay's network icon), over
                    // the letters until it lands (prd §1534).
                    RemoteAssetMark(urlString: remote, size: Self.listMark,
                                    monogram: String((mark ?? title).prefix(2)).uppercased())
                } else if let symbol, bareSymbol {
                    // A VERB'S GLYPH STANDS BARE (prd §1737): in the glyph's
                    // pink in the mark's column, as a Wallet door's and a
                    // Feed section's does. The grey disc was the one plate
                    // under a glyph in the app.
                    Image(systemName: symbol).dsGlyph(.title, weight: .semibold)
                        .foregroundStyle(DS.brandInk)
                        .frame(width: Self.listMark, height: Self.listMark)
                        .accessibilityHidden(true)
                } else if let symbol {
                    // A glyph for what has no logo of its own (Buy's
                    // categories, a person with no face, prd §1534).
                    Circle().fill(DS.fillStrong)
                        .frame(width: Self.listMark, height: Self.listMark)
                        .overlay(Image(systemName: symbol).dsGlyph(.body, weight: .semibold)
                            .foregroundStyle(DS.textSecondary))
                        .accessibilityHidden(true)
                } else if let mark {
                    AssetMark(name: mark, size: Self.listMark)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).dsText(rung)
                        .foregroundStyle(picked ? DS.pickInk : DS.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    if let sub {
                        Text(verbatim: sub).dsText(.subhead12)
                            .foregroundStyle(sub == Self.aztecRule ? DS.aztecInk : DS.textSecondary).lineLimit(2)
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: DS.Space.s2)
                if let trailing {
                    // One line, always: a long name shrinks instead.
                    Text(verbatim: trailing).dsText(.price17).foregroundStyle(DS.textPrimary).monospacedDigit()
                        .lineLimit(1).fixedSize()
                }
            }
            .frame(minHeight: Self.listRowHeight)
            .contentShape(Rectangle())
            .opacity(dim ? 0.55 : 1)
        }
        .buttonStyle(RowPress())
    }

    private var withList: some View {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        // Spend looks on every network (prd §1666): what pays is turned into
        // USDC on Base first, wherever it is.
        let rows: [(key: String, net: Op.Network, held: Tokens.Held)] = (verb == .buy ? networksByWorth : lookIn).flatMap { n in
            (heldBy[n.chainId] ?? []).map { ("\(n.chainId)|\($0.id)", n, $0) }
        }
        .filter { q.isEmpty || $0.held.token.symbol.lowercased().hasPrefix(q) }
        // What the whole swap buys is never also what it sells.
        .filter { row in lockedBuy.map { row.held.token != $0 || verb != .swap } ?? true }
        // Spend pays with ETH or USDC on Base or Ethereum (prd §1666).
        .filter { row in verb != .buy || SpendTopUp.pays(row.held.token, on: row.net) }
        // Biggest first, whichever network it is on.
        .sorted { ($0.held.usd ?? -1) > ($1.held.usd ?? -1) }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(rows, id: \.key) { row in
                let h = row.held
                let worth = h.usd.map { Self.money($0) }
                // Holdings' grammar (prd §1719): the network, then the
                // amount; the dollars trail, as every Wallet row's do.
                listRow(h.token.symbol,
                        sub: "\(row.net.name) · \(Op.spoken(left(h), decimals: h.token.decimals))",
                        trailing: worth, mark: h.token.symbol) {
                    pick {
                        if !networkPicked || row.net != network { switchNetwork(row.net) }
                        // Spend's amount is the card's value in dollars, whatever pays.
                        if verb == .buy { with = h } else { choose(h) }
                    }
                }
            }
            // **PRIVATE MONEY IS ROWS HERE (prd §1719).** Send's "what" lists
            // your private tokens under one "Private" header, after the
            // public ones: picking one is the whole choice ("Send 0.1 ETH
            // from your private balance to …"). No switch, no network to
            // pick first; network and token pin down the one place.
            if verb == .send, !privateWithRows(q).isEmpty {
                listHeader(String(localized: "Private"))
                ForEach(privateWithRows(q), id: \.key) { p in
                    listRow(p.symbol, sub: "\(p.network) · \(p.amount)", trailing: p.usd.map { Self.money($0) },
                            mark: p.symbol) {
                        pick {}
                        p.act()
                    }
                }
            }
            if rows.isEmpty, verb != .send || privateWithRows(q).isEmpty {
                Text(verbatim: !heldEverywhere && (!networkPicked || heldBy[network.chainId] == nil) ? String(localized: "Reading…")
                     : !q.isEmpty ? String(localized: "You have no \(search.trimmingCharacters(in: .whitespaces).uppercased())")
                     : networkPicked && unread.contains(network.chainId) ? String(localized: "Couldn't read \(network.name)")
                     : networkPicked ? String(localized: "Nothing on \(network.name) yet")
                     : String(localized: "Nothing to spend yet"))
                    .dsText(.body17).foregroundStyle(DS.textSecondary).frame(minHeight: 44)
            }
        }
    }

    /// Your private tokens as Send's "what" rows (prd §1719): what your
    /// private balance holds on Ethereum (Privacy Pools' approved notes, by
    /// token) and on Aztec, biggest first, filtered as the list is.
    private func privateWithRows(_ q: String) -> [(key: String, symbol: String, network: String, amount: String, usd: Double?, act: () -> Void)] {
        var out: [(key: String, symbol: String, network: String, amount: String, usd: Double?, act: () -> Void)] = []
        if PrivateMove.available {
            let pools = PrivateMoneyStore.shared
            // By token and by the network the money is on (the row's own,
            // never the build's test network).
            var byToken: [String: (symbol: String, network: String, amount: Decimal, usd: Double?)] = [:]
            for r in pools.rows where r.kind == .held {
                let units = (Decimal(string: r.amount) ?? 0) / pow(10, r.decimals)
                let usd = PrivateMoney.rowUSD(r, prices: pools.shownPrices)
                let key = "\(r.chainId)|\(r.symbol)"
                let was = byToken[key]
                byToken[key] = (r.symbol, PrivateMoney.network(r.chainId), (was?.amount ?? 0) + units,
                                usd.map { $0 + (was?.usd ?? 0) } ?? was?.usd)
            }
            for (key, v) in byToken {
                let symbol = v.symbol, net = v.network
                let amount = NSDecimalNumber(decimal: v.amount).doubleValue
                    .formatted(.number.precision(.significantDigits(1...4)))
                out.append(("pools|" + key, symbol, net, amount, v.usd, { [self] in
                    privateMove.symbol = symbol
                    goPrivate(.send)
                }))
            }
        }
        // Railgun's tokens (prd §1721): picking one sends it to the recipient
        // already in the sentence through a broadcaster, or takes it back to
        // your account when there is none (§1721 item 3).
        let railgun = RailgunHoldings.shared
        for h in railgun.spendableShown {
            out.append(("railgun|" + h.id, h.symbol, "Ethereum", RailgunHoldings.figure(h.spendable, decimals: h.decimals),
                        railgun.usd(h, units: h.spendable), { [self] in
                goRailgun(.takeBack, contract: h.contract, recipient: resolved?.address)
            }))
        }
        if AztecProver.isAvailable, YourAccountKey.address != nil || DemoMode.isActive {
            let aztec = AztecAccountStore.shared
            if aztec.isShown {
                for h in aztec.privateHeld {
                    out.append(("aztec|" + h.name, h.name, "Aztec", FeedScreen.aztecFigure(h, units: h.privateUnits),
                                aztec.usd(h, units: h.privateUnits), { [self] in
                        aztecMove.symbol = h.name
                        goAztec(.send, recipient: resolved?.address)
                    }))
                }
            }
        }
        return out.filter { q.isEmpty || $0.symbol.lowercased().hasPrefix(q) }
            .sorted { ($0.usd ?? -1) > ($1.usd ?? -1) }
    }

    /// What For offers, on the picked network or on each: what you hold
    /// there, then its ETH and USDC, until something is typed (prd §1617).
    private var buyRows: [(key: String, net: Op.Network, listed: Tokens.Listed)] {
        let typed = !search.trimmingCharacters(in: .whitespaces).isEmpty
        var out: [(key: String, net: Op.Network, listed: Tokens.Listed)] = []
        var seen: Set<String> = []
        // This network, then each other it can arrive on (prd §1566): what
        // can arrive there, its ETH and USDC until something is typed (§1617).
        if crossesInFor {
            // The network picked to arrive on leads (prd §1600).
            for n in [buyHome] + destinations.filter({ $0 != buyHome }) {
                let pool = (typed ? (found[n.chainId] ?? []) : []) + (listedBy[n.chainId] ?? [])
                var rows = Tokens.matches(search, in: pool, held: heldBy[n.chainId] ?? [], shows: Tokens.offeredUnasked)
                if let p = pasted[n.chainId], !rows.contains(where: { $0.id == p.id }) { rows.insert(p, at: 0) }
                if n == network {
                    rows = rows.filter { $0.token != with?.token }
                } else {
                    // Never its WETH: ETH is ETH there (prd §1559).
                    let weth = YourAccountSwap.book(n.chainId)?.weth
                    rows = rows.filter { Self.arrives($0.token, from: network, on: n) && $0.token.contract?.lowercased() != weth }
                }
                for l in rows {
                    let key = "\(n.chainId)|\(l.id)"
                    if seen.insert(key).inserted { out.append((key, n, l)) }
                }
            }
            return out
        }
        for n in lookIn {
            let pool = (typed ? (found[n.chainId] ?? []) : []) + (listedBy[n.chainId] ?? [])
            var rows = Tokens.matches(search, in: pool, held: heldBy[n.chainId] ?? [], shows: Tokens.offeredUnasked)
            if let p = pasted[n.chainId], !rows.contains(where: { $0.id == p.id }) { rows.insert(p, at: 0) }
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
                        sub: networkPicked && row.net == network ? about : [about, row.net.name].compactMap { $0 }.joined(separator: " · "),
                        trailing: mine.map { Op.spoken($0.units, decimals: $0.token.decimals) },
                        mark: l.token.symbol, dim: !l.onList) {
                    pick {
                        if crossesInFor {
                            // Picked on another network: it arrives there, and
                            // what is sold stays where it is (prd §1566).
                            buyOn = row.net == network ? nil : row.net
                        } else if row.net != buyHome || !networkPicked {
                            switchNetwork(row.net)
                        }
                        buy = l
                    }
                }
            }
            if networkPicked, !YourAccountSwap.supported(network) {
                Text("Swaps are not on \(network.name)").dsText(.body17).foregroundStyle(DS.textSecondary).frame(minHeight: 44)
            }
        }
        // The lists of the networks it can arrive on, read once (prd §1566).
        .task(id: crossesInFor ? destinations.map(\.chainId) : []) {
            for n in (crossesInFor ? destinations : []) where listedBy[n.chainId] == nil { listedBy[n.chainId] = await Tokens.list(n) }
        }
    }

    private var toList: some View {
        let q = to.trimmingCharacters(in: .whitespaces).lowercased()
        // No contract and no key (prd §1773): machinery in the book is not
        // someone to send to. A name typed in full still resolves, and Move
        // warns on a contract before Face ID (§1513).
        let book = AddressBook.shared.all.filter { e in
            ENS.isHexAddress(e.address) && e.kind != .contract && e.kind != .key
                && (q.isEmpty || e.name.lowercased().contains(q) || e.address.lowercased().hasPrefix(q))
        }
        // People the book's own names did not find: a contact whose card,
        // handle or ENS name matches, or one whose wallet is not in the book.
        let found = people.filter { p in
            !book.contains { WalletWatch.sameAddress($0.address, p.address) }
                && (q.isEmpty ? AddressBook.shared.entry(for: p.address) == nil : p.terms.contains(q))
        }
        // The person the line above goes to leads, said so (§1442h).
        let above = keptSends.last.flatMap { p in WalletWatch.sameAddress(p.to, resolved?.address ?? "") ? nil : p }
        return VStack(alignment: .leading, spacing: 0) {
            // **RECENT (prd §1752):** the last people Send sent to from here,
            // at the top of the list, above Private and your book; typing searches
            // the book, so the three stand only while the field is blank.
            let recent = q.isEmpty ? recentTo.filter { a in
                !(above.map { WalletWatch.sameAddress($0.to, a) || $0.toName?.caseInsensitiveCompare(a) == .orderedSame } ?? false)
            } : []
            if !recent.isEmpty {
                listHeader(String(localized: "Recent"))
                ForEach(recent, id: \.self) { entry in
                    if ZkMoneyWire.tag(entry) != nil {
                        // A tag is resolved as a typed one is: To looks it up.
                        // One you saved wears the name you gave it (prd §1767).
                        let saved = ContactBook.shared.name(for: Identity.key(.zkMoney, entry))
                        listRow(saved ?? entry, sub: saved == nil ? "zk.money" : entry, mark: entry) {
                            to = entry
                            pick {}
                        }
                    } else {
                        let name = AddressBook.shared.name(for: entry)
                        listRow(name ?? YourAccount.short(entry), sub: name == nil ? nil : YourAccount.short(entry),
                                mark: name, face: name.map(AssetMark.hasAsset) == true ? nil : entry) {
                            to = name ?? entry
                            resolved = Recipient(address: EIP55.checksum(entry), name: name, imitates: nil)
                            pick {}
                        }
                    }
                }
            }
            // **YOUR PRIVATE BALANCE, ONE NOUN, TOLD APART BY NETWORK (prd
            // §1719, amending §1718 item 6 and §1700g item 2).** Two rows
            // under one "Private" header, both "Your private balance", the
            // line its network — as two USDC rows are told apart. No
            // protocol is ever picked: on Ethereum the token decides
            // (ETH and USDC to Privacy Pools, any other token to Railgun),
            // named only in the sentence's foot. One tap, never typed.
            let balanceWord = String(localized: "Your private balance")
            let privateNet = (PrivacyNetwork.current(debugAsks: PrivateMove.debugNetwork) ?? .ethereum).name
            let poolsHere = PrivateMove.available
                && (q.isEmpty || balanceWord.lowercased().contains(q) || privateNet.lowercased().contains(q))
            let aztecHere = (YourAccountKey.address != nil || DemoMode.isActive) && AztecProver.isAvailable
                && (q.isEmpty || balanceWord.lowercased().contains(q) || "aztec".contains(q))
            if poolsHere || aztecHere {
                listHeader(String(localized: "Private"))
            }
            if poolsHere {
                listRow(balanceWord, sub: privateNet, symbol: "eye.slash") {
                    // The token decides (prd §1713 item 1): ETH and USDC to
                    // Privacy Pools, any other token on Ethereum to Railgun.
                    if RailgunPocket.available, let held = with, network == Op.ethereum,
                       RailgunRouting.goesToRailgun(symbol: held.token.symbol, contract: held.token.contract, chainId: network.chainId) {
                        goRailgun(.deposit, contract: held.token.contract)
                    } else {
                        goPrivate(.deposit)
                    }
                }
            }
            if aztecHere {
                // Two nouns (prd §1779, reversing §1719's one): your private
                // balance is Ethereum's, your private account is Aztec.
                listRow(String(localized: "Your private account"), sub: Self.aztecRule, symbol: "diamond") {
                    goAztec(.deposit)
                }
            }
            // An Aztec address typed: a private send from Aztec (prd §1700f item 14).
            if AztecAddressText.isAztec(to), AztecProver.isAvailable {
                listRow(AddressTail.short(to.trimmingCharacters(in: .whitespaces)), sub: String(localized: "Aztec · Private"), symbol: "eye.slash") {
                    goAztec(.send, recipient: to.trimmingCharacters(in: .whitespaces).lowercased())
                }
            }
            // Your book under its own word once Recent stands over it, so no
            // row of the book reads as someone you just paid.
            // **THE TAGS YOU SAVED (prd §1767).** A zk.money tag in Contacts
            // is someone to pay, so it stands in the book beside the
            // addresses, found by its name, its tag or `@name`.
            let tags = ZkMoneyWire.savedTags(ContactBook.shared.all.map { ($0.id, $0.name) }, query: q)
                .filter { saved in !recent.contains { $0.caseInsensitiveCompare(saved.tag) == .orderedSame } }
            if !recent.isEmpty, !(book.isEmpty && tags.isEmpty && found.isEmpty) {
                listHeader(String(localized: "Addresses"))
            }
            ForEach(Array(tags.prefix(8)), id: \.tag) { saved in
                listRow(saved.name, sub: saved.name.lowercased() == saved.tag ? "zk.money" : saved.tag, mark: saved.tag) {
                    to = saved.tag
                    pick {}
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
            ForEach(Array(book.filter { e in
                (above.map { !(q.isEmpty && WalletWatch.sameAddress($0.to, e.address)) } ?? true)
                    && !recent.contains { WalletWatch.sameAddress($0, e.address) }
            }.prefix(20)), id: \.address) { e in
                // A company in the book (Uniswap, Coinbase) wears its logo; a
                // person, their face (prd §1534).
                listRow(e.name, sub: YourAccount.short(e.address), mark: e.name,
                        face: AssetMark.hasAsset(e.name) ? nil : e.address) {
                    to = e.name
                    resolved = Recipient(address: EIP55.checksum(e.address), name: e.name, imitates: nil)
                    pick {}
                }
            }
            ForEach(Array(found.prefix(8))) { p in
                // The line is the name the book has for the address, when it
                // is another word than the person's; else its tail.
                let bookName = AddressBook.shared.name(for: p.address)
                listRow(p.name, sub: bookName.flatMap { $0.caseInsensitiveCompare(p.name) == .orderedSame ? nil : $0 }
                            ?? YourAccount.short(p.address), face: p.address) {
                    to = p.name
                    resolved = Recipient(address: EIP55.checksum(p.address), name: p.name, imitates: nil)
                    pick {}
                }
            }
            pasteRow { to = $0; pastedTo = true }
        }
    }

    /// Where the money is (prd §1453, Receive's one network list since
    /// §1486): the account's own networks take your own address; every other
    /// network Relay takes deposits on goes through Relay, to your account on
    /// this network.
    private var elsewhereList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(networksByWorth) { n in
                listRow(n.name, sub: n.isTest ? String(localized: "Test network · its tokens have no value") : String(localized: "your own address"),
                        image: Self.networkMark(n), picked: elsewhere == nil && networkPicked && n == network) {
                    pick {
                        elsewhere = nil
                        switchNetwork(n)
                        // A pick ends the arrival (prd §1488).
                        if fresh { fresh = false; arrived = true }
                    }
                }
            }
            // **YOUR PRIVATE BALANCE, WHERE IT LANDS (prd §1719).** The same
            // two rows as Send › To: on Ethereum a one-time fresh address
            // whose money moves in by itself (§1560); on Aztec your Aztec
            // address, the same every time.
            let receivesPools = PrivateMove.freshAvailable
            let receivesAztec = AztecProver.isAvailable && AztecAccountStore.shared.shown.address != nil
            if receivesPools || receivesAztec {
                listHeader(String(localized: "Private"))
            }
            if receivesPools {
                listRow(String(localized: "Your private balance"),
                        sub: (PrivacyNetwork.current(debugAsks: PrivateMove.debugNetwork) ?? .ethereum).name,
                        symbol: "eye.slash", picked: freshReceive) {
                    pick {}
                    if fresh { fresh = false; arrived = true }
                    goFresh()
                }
            }
            if receivesAztec {
                listRow(String(localized: "Your private account"), sub: Self.aztecRule, symbol: "diamond", picked: aztecReceive) {
                    pick {}
                    if fresh { fresh = false; arrived = true }
                    withAnimation(DS.Motion.standard) { open = nil; aztecReceive = true }
                    DSHaptic.selection()
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
                    listRow(c.symbol, sub: c.isNative ? String(localized: "\(route.from.name)'s own token") : nil,
                            mark: c.symbol, picked: c == route.token) {
                        pick {}
                        if c != route.token { takeRoute(from: route.from, token: c) }
                    }
                }
            }
        }
    }

    /// What you receive (prd §1470): what you hold on your network, then its
    /// ETH and USDC, until you type (prd §1617); then any token on Uniswap's
    /// list. Relay
    /// brings what you pick, and says so if it cannot.
    private var arrivesList: some View {
        let to = network.isTest ? Op.base : network
        let typed = !search.trimmingCharacters(in: .whitespaces).isEmpty
        let pool = (typed ? (found[to.chainId] ?? []) : []) + (listedBy[to.chainId] ?? [])
        let rows = Tokens.matches(search, in: pool, held: heldBy[to.chainId] ?? [], shows: Tokens.offeredUnasked)
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
                listRow(n.name, sub: n.isTest ? String(localized: "Test network · its tokens have no value") : nil,
                        trailing: total > 0 ? Self.money(total) : nil, image: Self.networkMark(n),
                        picked: networkPicked && n == network) {
                    pick { switchNetwork(n) }
                }
            }
            // Real networks only (prd §1719, retiring §1700f item 11's
            // "Ethereum · Private" and "Aztec · Private" rows): private money
            // is picked as its tokens, in the token list (`withList`).
        }
    }

    /// **"GET USDC ON" (prd §1555, the user's design).** Where what Swap
    /// buys arrives: this network ("Same network"), or another the account
    /// is on that Across carries it to. Only ETH and the dollar cross, so a
    /// token that cannot never opens this list.
    private var destinationList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Before a token is picked the list is just the networks; For then
            // opens on the one picked (prd §1600).
            listHeader(buy.map { String(localized: "Get \($0.token.symbol) on") } ?? String(localized: "Get it on"))
            ForEach(destinations) { n in
                // The same token there, or none: For then opens on that
                // network's list (prd §1566).
                let there = buy.flatMap { b in n == buyHome ? b : equivalent(b.token, from: buyHome, to: n) }
                let sub: String? = n == network ? String(localized: "Same network")
                    : there.flatMap { t in buy.flatMap { t.token.symbol != $0.token.symbol ? String(localized: "As \(t.token.symbol)") : nil } }
                listRow(n.name, sub: sub, image: Self.networkMark(n), picked: buyHome == n) {
                    pick {
                        self.buy = there
                        buyOn = n == network ? nil : n
                    }
                    if there == nil { open = .buy }
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
        advances = true
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
            if let request = payingRequest, amount == request.amount, ZkMoneyWire.payTokens.contains(h.id) {
                // Paying a request (prd §1749): each token a deposit takes
                // is a dollar, so the amount asked stands in whichever is
                // picked. It was cleared: an unpriced DAI took the dollars
                // with it, and one deposit token's units never carried to
                // the next.
                inDollars = false
            } else if inDollars, h.price != nil {
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

    // MARK: - When (prd §1673)

    /// The pair "when" is asked for: another network or token asks again.
    private var limitPair: String {
        "\(network.chainId)|\(with?.token.symbol ?? "")|\(buy?.token.contract ?? buy?.token.symbol ?? "")"
    }

    /// Swap ends "when": one network CoW settles on, a price to state, one
    /// swap alone (an order is never batched).
    private var whenOffered: Bool {
        guard verb == .swap, receipt == nil, items.isEmpty, let with, let buy, buyHome == network else { return false }
        return YourAccountOrder.offersWhen(sell: with.token, buy: buy.token, from: network, to: buyHome)
    }

    /// The word stands at rest, before the tokens and network are picked
    /// (prd §1673 item 2: "swap token on network for token on network
    /// when"), and leaves only once the sentence rules it out: two
    /// networks (item 6), a network CoW does not settle on, or a pair with
    /// no price to state.
    private var whenDrawn: Bool {
        guard verb == .swap, receipt == nil, items.isEmpty else { return false }
        if whenOffered { return true }
        guard buyHome == network, !networkPicked || YourAccountOrder.supported(network) else { return false }
        return with == nil || buy == nil
    }

    /// An unanswerable "when" opens the blank it waits on: the network,
    /// then the token bought, then the token sold.
    private var whenWaitsOn: Blank {
        if !networkPicked { return .network }
        return buy == nil ? .buy : .with
    }

    /// The answer, for this pair only; Now until a price is picked (prd
    /// §1683: the sentence at rest ends "now.", whole and signable).
    private var when: WhenPick? {
        guard whenOffered else { return nil }
        return whenFor == limitPair ? (whenPick ?? .now) : .now
    }

    /// A price was picked: the sentence is a CoW order.
    private var limiting: Bool { when == .price }

    /// "when ETH is …": the token the price is of.
    private var pricedToken: Op.Token? {
        guard let with, let buy else { return nil }
        return YourAccountOrder.priced(sell: with.token, buy: buy.token, on: network)
    }

    /// The price the order is placed at: typed in dollars, or a percent
    /// from today's turned into dollars now (CoW holds a price).
    private var limitPrice: YourAccountOrder.Decimal? {
        guard limiting, let typed = YourAccountOrder.Decimal.parse(priceText, signed: priceInPercent) else { return nil }
        if priceInPercent { return nowPrice.flatMap { YourAccountOrder.price(percent: typed, from: $0) } }
        return typed.isZero || typed.negative ? nil : typed
    }

    /// At least this much comes back at that price.
    private var limitBuyUnits: String? {
        guard let with, let buy, let units, let p = limitPrice else { return nil }
        return YourAccountOrder.buyUnits(sellUnits: units, sell: with.token, buy: buy.token, on: network,
                                         price: p, sellDollars: sellDollars)
    }

    private var limitDraft: YourAccountOrders.Draft? {
        guard limiting, let with, let buy, let units, units != "0", let b = limitBuyUnits,
              let p = limitPrice, let v = YourAccountOrder.value(p), let priced = pricedToken else { return nil }
        return .init(network: network, sell: with.token, buy: buy.token, sellUnits: units, buyUnits: b,
                     pricedSymbol: priced.symbol, priceWords: Self.priceWords(v, places: p.places), seconds: orderSeconds)
    }

    private var limitKey: String { "\(limitPair)|\(whenOffered)" }

    /// "$2,248", "$41.20", "$0.8512": a price as people say it.
    static func dollarWords(_ v: Double) -> String {
        if v >= 1000 { return v.formatted(.currency(code: "USD").precision(.fractionLength(0))) }
        if v >= 1 { return v.formatted(.currency(code: "USD").precision(.fractionLength(2))) }
        return v.formatted(.currency(code: "USD").precision(.significantDigits(1...4)))
    }

    /// A typed price as typed, grouped: "$2,400", "$2,400.5".
    static func priceWords(_ v: Double, places: Int) -> String {
        v.formatted(.currency(code: "USD").precision(.fractionLength(min(places, 8))))
    }

    /// The day a week from now, the order's expiry.
    private var untilWords: String { Self.untilDay(orderSeconds) }

    /// The day an order placed now stops waiting: "Nov 9".
    static func untilDay(_ seconds: UInt32) -> String {
        Date.now.addingTimeInterval(TimeInterval(seconds)).formatted(.dateTime.month(.abbreviated).day())
    }

    /// "now." or "when ETH is $2,400." — Swap's last word, inside the
    /// sentence, before its full stop (prd §1683).
    @ViewBuilder private var whenClause: some View {
        switch when {
        case nil:
            // Until the pair is known there is no price to ask for: the
            // word opens the blank it waits on (prd §83, no dead control).
            MoveClause { blank(String(localized: "now."), ink: MoveSentence.settledInk, whenWaitsOn, lit: .when, label: Text("Now, change")) }
        case .now:
            MoveClause { blank(String(localized: "now."), ink: MoveSentence.settledInk, .when, label: Text("Now, change")) }
        case .price:
            MoveClause(glue: String(localized: "when \(pricedToken?.symbol ?? "") is")) { priceWord }
        }
    }

    /// The price, a field while it is typed or empty, else a word that
    /// opens the two rows again (prd §1673a).
    @ViewBuilder private var priceWord: some View {
        if focus == .price || limitPrice == nil {
            priceField
        } else if let p = YourAccountOrder.Decimal.parse(priceText, signed: priceInPercent), let v = YourAccountOrder.value(p) {
            let words = priceInPercent
                ? (v < 0 ? "−" : "+") + String(priceText.drop { $0 == "-" || $0 == "+" || $0 == "−" }) + "%"
                : Self.priceWords(v, places: p.places)
            blank(words + ".", ink: MoveSentence.settledInk, .when, label: Text("When \(pricedToken?.symbol ?? "") is \(words), change"))
        }
    }

    private var priceField: some View {
        MoveRungReader { rung in
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if !priceInPercent { Text(verbatim: "$").dsText(rung).foregroundStyle(DS.pickInk) }
                TextField(text: $priceText, prompt: Text(verbatim: "0").foregroundStyle(DS.textTertiary)) { Text(verbatim: "0") }
                    // A percent may fall: the minus is on the punctuation keys.
                    .keyboardType(priceInPercent ? .numbersAndPunctuation : .decimalPad)
                    .focused($focus, equals: .price)
                    .dsText(rung)
                    .monospacedDigit()
                    .foregroundStyle(DS.pickInk)
                    .fixedSize()
                if priceInPercent { Text(verbatim: "%").dsText(rung).foregroundStyle(DS.pickInk) }
                Text(verbatim: ".").dsText(rung).foregroundStyle(DS.textPrimary)
            }
        }
        .accessibilityLabel(Text(priceInPercent ? "Percent from today's price" : "Price in dollars"))
    }

    /// The presets a price is picked from, in percent from today's (prd §1683).
    static let whenPresets = [5, 10, 25]

    /// A preset picked, until the price is typed over.
    @State private var whenPreset: Int?

    /// Selling the priced token waits for it to rise, buying it for it to
    /// fall: the presets carry that sign.
    private var presetSign: Int { with?.token.symbol == pricedToken?.symbol ? 1 : -1 }

    /// "when"'s choices, Move's list rows (prd §1683, amending §1673a): Now,
    /// the three presets, Custom; a header with today's price and the unit
    /// the presets read in, % or $ (the price is the same either way).
    private var whenList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.s2) {
                if let nowPrice, let t = pricedToken {
                    Text("\(t.symbol) now").dsText(.body17).foregroundStyle(DS.textSecondary).lineLimit(1)
                    Text(verbatim: Self.dollarWords(nowPrice)).dsText(.body17).foregroundStyle(DS.textPrimary).monospacedDigit().lineLimit(1)
                }
                Spacer(minLength: DS.Space.s2)
                HStack(spacing: DS.Space.s1) {
                    unitChip("%", on: priceInPercent, label: Text("Prices in percent")) { setPriceUnit(percent: true) }
                    unitChip("$", on: !priceInPercent, label: Text("Prices in dollars")) { setPriceUnit(percent: false) }
                }
            }
            .frame(minHeight: DSFeed.headHeight)
            let figure: String? = buy.flatMap { b in buyTotal.map { "≈ " + Self.short($0, decimals: b.token.decimals) + " " + b.token.symbol } }
            listRow(String(localized: "Now"), trailing: figure, symbol: "bolt.fill", picked: when == .now) {
                pick {
                    whenPick = .now
                    whenFor = limitPair
                }
            }
            ForEach(Self.whenPresets, id: \.self) { pct in
                let signed = pct * presetSign
                let percentWords = (signed < 0 ? "−" : "+") + "\(pct)%"
                let dollarWords = nowPrice.map { Self.dollarWords($0 * (1 + Double(signed) / 100)) }
                listRow(priceInPercent ? percentWords : (dollarWords ?? percentWords),
                        trailing: priceInPercent ? dollarWords : percentWords,
                        symbol: "clock", picked: limiting && whenPreset == signed) { pickPreset(signed) }
            }
            listRow(String(localized: "Custom"), symbol: "pencil", picked: limiting && whenPreset == nil) {
                pick {
                    whenPick = .price
                    whenFor = limitPair
                    whenPreset = nil
                    priceText = ""
                }
                focus = .price
            }
        }
    }

    /// A preset: the price it names, in the unit the list reads in.
    private func pickPreset(_ signed: Int) {
        pick {
            whenPick = .price
            whenFor = limitPair
            whenPreset = signed
            if !priceInPercent, let nowPrice {
                priceText = Self.plainPrice(nowPrice * (1 + Double(signed) / 100))
            } else {
                priceInPercent = true
                priceText = String(signed)
            }
        }
    }

    /// % or $: the same price in the other unit, or only the unit while
    /// none is set.
    private func setPriceUnit(percent: Bool) {
        guard percent != priceInPercent else { return }
        if limitPrice != nil { tradePriceUnit() } else {
            withAnimation(DS.Motion.standard) { priceInPercent = percent }
            DSHaptic.selection()
        }
    }

    /// A price as typed into the field: "2473.6", "0.8512".
    static func plainPrice(_ v: Double) -> String {
        var t = v >= 1 ? String(format: "%.2f", v) : String(format: "%.6f", v)
        while t.contains("."), t.last == "0" || t.last == "." { t.removeLast() }
        return t
    }

    /// "+6.8% · Now $2,248 · At least 2,400 USDC · Until Nov 9": the pink
    /// figure trades dollars and percent (prd §1673 item 3), and Until is
    /// a word that opens how long it waits (item 5); the rest is grey.
    private var limitPrint: (pink: String, rest: String) {
        var rest: [String] = []
        var pink = ""
        if let price = limitPrice.flatMap(YourAccountOrder.value), let nowPrice {
            pink = priceInPercent ? Self.dollarWords(price) : (YourAccountOrder.percentWords(price, from: nowPrice) ?? "")
        }
        if let nowPrice { rest.append(String(localized: "Now \(Self.dollarWords(nowPrice))")) }
        if let buy, let b = limitBuyUnits {
            rest.append(String(localized: "At least \(Self.figure(b, decimals: buy.token.decimals)) \(buy.token.symbol)"))
        }
        return (pink, rest.joined(separator: " · "))
    }

    @ViewBuilder private func limitLine(_ with: Tokens.Held) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            if over {
                Text("More than you have").dsText(.body17).foregroundStyle(DS.attentionInk)
            }
            // One line, two words in it that act: the pink figure and Until.
            Text(limitLineText)
                .dsText(.body17)
                .tint(DS.pickInk)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.openURL, OpenURLAction { url in
                    switch url.host() {
                    case "unit": tradePriceUnit()
                    case "until":
                        withAnimation(DS.Motion.standard) { open = .until }
                        DSHaptic.selection()
                    default: break
                    }
                    return .handled
                })
            // The amount's rows, as every other sentence's (prd §1776).
            if receipt == nil {
                amountPicks(with)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var limitLineText: AttributedString {
        let print = limitPrint
        // The acting words carry their pink themselves: a colour set on the
        // whole line would grey them over the link tint.
        func grey(_ s: String) -> AttributedString {
            var a = AttributedString(s)
            a.foregroundColor = DS.textSecondary
            return a
        }
        func act(_ s: String, _ host: String) -> AttributedString {
            var a = AttributedString(s)
            a.link = URL(string: "casberi-move://" + host)
            a.foregroundColor = DS.pickInk
            return a
        }
        var line = AttributedString()
        if !print.pink.isEmpty { line += act(print.pink, "unit") + grey(" · ") }
        if !print.rest.isEmpty { line += grey(print.rest + " · ") }
        line += act(String(localized: "Until \(untilWords)"), "until")
        return line
    }

    /// A day, a week, a month: how long CoW may fill it (prd §1673 item 5).
    private var untilList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(YourAccountOrder.expiries, id: \.self) { seconds in
                listRow(YourAccountOrder.expiryWords(seconds), sub: String(localized: "Until \(Self.untilDay(seconds))"),
                        symbol: "calendar", picked: orderSeconds == seconds) {
                    pick { orderSeconds = seconds }
                }
            }
        }
    }

    /// The pink figure tapped: the price is typed in the other unit, the
    /// same price either way.
    private func tradePriceUnit() {
        guard let nowPrice, let v = limitPrice.flatMap(YourAccountOrder.value) else { return }
        withAnimation(DS.Motion.standard) {
            if priceInPercent {
                priceText = Self.plainPrice(v)
                priceInPercent = false
            } else {
                let pct = (v / nowPrice - 1) * 100
                priceText = String(format: "%.1f", pct)
                if priceText.hasSuffix(".0") { priceText.removeLast(2) }
                if priceText == "-0" { priceText = "0" }
                priceInPercent = true
            }
        }
        DSHaptic.selection()
    }

    /// Today's dollars for the priced token (and the sold one when neither
    /// is a dollar), off the pools as every price here is (prd §1542 item 7).
    private func readLimitPrices() async {
        nowPrice = nil
        sellDollars = nil
        guard whenOffered, let with, let buy, let priced = pricedToken else { return }
        #if DEBUG
        if let draft = whenDraftPending {
            whenDraftPending = nil
            whenFor = limitPair
            // "<price>|until" lands on the Until rows (prd §1673 item 5).
            let parts = draft.split(separator: "|").map(String.init)
            let w = parts.first ?? ""
            if parts.count > 1, parts[1] == "until" { open = .until }
            switch w {
            case "open": open = .when
            case "now": whenPick = .now
            default:
                whenPick = .price
                priceInPercent = w.hasSuffix("%")
                priceText = String(w.drop { $0 == "+" }).replacingOccurrences(of: "%", with: "")
            }
            NSLog("moveWhenDraft: %@ for %@", draft, limitPair)
        }
        #endif
        let net = network
        nowPrice = await Chain.exchangePrice(net, priced)
        if !YourAccountOrder.isDollar(with.token, on: net), !YourAccountOrder.isDollar(buy.token, on: net) {
            sellDollars = await Chain.exchangePrice(net, with.token)
        }
        #if DEBUG
        NSLog("moveWhen| now %@ %@ | sell %@", priced.symbol, nowPrice.map { String($0) } ?? "-", sellDollars.map { String($0) } ?? "-")
        #endif
    }

    /// Place the order: CoW must name back the id this phone built, then one
    /// Face ID pre-signs it (prd §1673 items 5, 7).
    private func placeOrder() {
        if YourAccountDemo.isDemo(account) { say(YourAccountDemo.actsLater); return }
        guard let draft = limitDraft else {
            say(limitPrice == nil ? String(localized: "Type a price first") : String(localized: "Pick an amount first"))
            if limitPrice == nil { focus = .price }
            return
        }
        focus = nil
        let net = network
        let sold = Op.spoken(draft.sellUnits, decimals: draft.sell.decimals)
        let reason = String(localized: "Swap \(sold) \(draft.sell.symbol) for \(draft.buy.symbol) when \(draft.pricedSymbol) is \(draft.priceWords)")
        stage = .preparing
        Task {
            do {
                let (sent, placed) = try await Chain.placeOrder(draft, reason: reason) { s in
                    await MainActor.run { advance(to: s) }
                }
                stage = nil
                chrome.refreshRooms()
                let made = Self.orderReceipt(placed, sent: sent, on: net)
                withAnimation(DS.Motion.standard) {
                    amount = ""
                    quote = nil
                    whenPick = nil
                    priceText = ""
                    priceInPercent = false
                    orderSeconds = YourAccountOrder.defaultSeconds
                    receipt = made
                    if case .landed = sent.outcome { orderShown = placed }
                }
                if case .landed = sent.outcome {
                    DSHaptic.success()
                    chrome.rain(sources: ["Wallet"])
                }
            } catch let failure as Chain.Failure {
                stage = nil
                #if DEBUG
                NSLog("moveOrder: failed %@", failure.message)
                #endif
                say(failure.message, failure: true, seconds: 6, from: failure.from)
            } catch {
                stage = nil
                say(String(localized: "Not sent"), failure: true)
            }
        }
    }

    /// "Waiting to swap 1 ETH on Base for USDC on Base when ETH is $2,400."
    static func orderReceipt(_ p: YourAccountOrders.Placed, sent: Chain.Sent, on net: Op.Network) -> Receipt {
        typealias Line = Receipt.Line
        if case .pending = sent.outcome {
            return Receipt(past: String(localized: "Sent,"),
                           lines: [Line(glue: nil, text: String(localized: "not yet seen")), Line(glue: String(localized: "on"), text: net.name + ".")],
                           detail: String(localized: "Check before placing it again"))
        }
        let tx: String? = { if case .landed(let t, _) = sent.outcome { return t } else { return nil } }()
        let link = tx.flatMap { explorer($0, on: net) }
        let linkName: String? = net.chainId == 1 ? "Etherscan" : "Basescan"
        let until = p.expires.formatted(.dateTime.month(.abbreviated).day())
        return Receipt(past: String(localized: "Waiting to swap"),
                       lines: [Line(glue: nil, text: figure(p.sellUnits, decimals: p.sellDecimals) + " " + p.sellSymbol),
                               Line(glue: String(localized: "on"), text: net.name),
                               Line(glue: String(localized: "for"), text: p.buySymbol),
                               Line(glue: String(localized: "on"), text: net.name),
                               Line(glue: String(localized: "when \(p.pricedSymbol) is"), text: p.priceWords + ".")],
                       detail: String(localized: "Order placed · Until \(until) · CoW Swap"),
                       link: link, linkName: link == nil ? nil : linkName)
    }

    /// "Swapped 1 ETH on Base for 2,401.2 USDC on Base." once CoW filled it.
    static func filledReceipt(_ p: YourAccountOrders.Placed, on net: Op.Network) -> Receipt {
        typealias Line = Receipt.Line
        let paid = p.paidUnits ?? p.buyUnits
        var detail = [String(localized: "Filled by CoW Swap")]
        let more = Op.difference(paid, p.buyUnits)
        if more != "0", Op.atMost(p.buyUnits, paid) {
            detail.append(String(localized: "\(figure(more, decimals: p.buyDecimals)) \(p.buySymbol) more than asked"))
        }
        return Receipt(past: String(localized: "Swapped"),
                       lines: [Line(glue: nil, text: figure(p.sellUnits, decimals: p.sellDecimals) + " " + p.sellSymbol),
                               Line(glue: String(localized: "on"), text: net.name),
                               Line(glue: String(localized: "for"), text: figure(paid, decimals: p.buyDecimals) + " " + p.buySymbol),
                               Line(glue: String(localized: "on"), text: net.name + ".")],
                       detail: detail.joined(separator: " · "))
    }

    /// While its receipt is up, the order is asked after every ten seconds.
    private func followOrder() async {
        guard let shown = orderShown, let net = shown.network else { return }
        while !Task.isCancelled, orderShown?.uid == shown.uid {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, orderShown?.uid == shown.uid else { return }
            await Chain.refreshOrders()
            guard let now = YourAccountOrders.all.first(where: { $0.uid == shown.uid }), now.state != .open else { continue }
            withAnimation(DS.Motion.standard) {
                switch now.state {
                case .filled: receipt = Self.filledReceipt(now, on: net)
                case .expired: receipt?.detail = String(localized: "Expired · nothing was swapped")
                case .cancelled: receipt?.detail = String(localized: "Cancelled · nothing was swapped")
                case .open: break
                }
                orderShown = nil
            }
            if now.state == .filled {
                DSHaptic.success()
                chrome.rain(sources: ["Wallet"])
                chrome.refreshRooms()
            }
            return
        }
    }

    /// Cancel: `invalidateOrder`, one Face ID (prd §1673 item 7).
    private func cancelOrder(_ p: YourAccountOrders.Placed) {
        guard stage == nil else { return }
        if YourAccountDemo.isDemo(account) { say(YourAccountDemo.actsLater); return }
        stage = .preparing
        Task {
            do {
                let sent = try await Chain.cancelOrder(p, reason: String(localized: "Cancel your order: \(YourAccountOrders.title(p))")) { s in
                    await MainActor.run { advance(to: s) }
                }
                stage = nil
                withAnimation(DS.Motion.standard) {
                    if case .landed = sent.outcome {
                        receipt?.detail = String(localized: "Cancelled · nothing was swapped")
                        orderShown = nil
                    } else {
                        receipt?.detail = String(localized: "Cancel sent, not yet seen · check before cancelling again")
                    }
                }
                chrome.refreshRooms()
            } catch let failure as Chain.Failure {
                stage = nil
                say(failure.message, failure: true, seconds: 6, from: failure.from)
            } catch {
                stage = nil
                say(String(localized: "Not cancelled"), failure: true)
            }
        }
    }

    /// **BACK TO THE MENU (prd §1781).** The verb in the sentence opened the
    /// verbs; now nothing in the sentence does, so the way back is a card
    /// in the foot's leading corner, the size of Add beside it.
    private var backCard: some View {
        MoveBackCard(act: {
            withAnimation(DS.Motion.standard) {
                open = .verb
                focus = nil
            }
        }, disabled: stage != nil)
    }

    private var foot: some View {
        VStack(spacing: DS.Space.s2) {
            if receipt != nil {
                HStack {
                    // An order still waiting can be withdrawn here (prd §1673 item 7).
                    if let order = orderShown, order.state == .open {
                        Button { cancelOrder(order) } label: {
                            Text(verbatim: stage == nil ? String(localized: "Cancel order") : footVerb)
                                .dsText(.heading34)
                                .contentTransition(.interpolate)
                                .foregroundStyle(stage == nil ? DS.destructiveInk : DS.textSecondary)
                                .frame(minHeight: 48, alignment: .leading)
                        }
                        .buttonStyle(RowPress())
                        .disabled(stage != nil)
                    }
                    Spacer()
                    Button {
                        withAnimation(DS.Motion.standard) { receipt = nil; orderShown = nil }
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
            HStack(alignment: .center, spacing: DS.Space.s2) {
                backCard
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
                    } label: { actCard(footVerb, on: ready) }
                    .buttonStyle(PressSpring())
                    .accessibilityHint(ready ? Text("Copies your address") : Text("Pick a network first"))
                } else if verb == .deposit {
                    // **Buy's one act opens the seller's page (prd §1599).**
                    Spacer(minLength: 0)
                    let seller = depositSeller
                    Button { deposit() } label: { actCard(footVerb, on: seller != nil) }
                    .buttonStyle(PressSpring())
                    .accessibilityHint(seller != nil ? Text("Opens \(seller?.name ?? "")'s page") : Text("Pick a network first"))
                } else if nothingToMove {
                    // Nothing to swap, send or pay with: the sentence says so
                    // and offers Receive (prd §1518); no Add, no verb.
                    EmptyView()
                }
                if verb != .receive, verb != .deposit, !nothingToMove {
                    Button { sign() } label: {
                        // **THE ACT WEARS FACE ID'S GLYPH (prd §1754):** the
                        // tap asks Face ID (§1687), and the word says so
                        // before it; once a stage has it, the glyph is gone.
                        actCard(footVerb, on: footOn,
                                fill: warned && stage == nil ? (leadWarning?.red == true ? DS.destructiveInk : DS.attentionInk) : DS.pickInk,
                                faceID: stage == nil && !limiting,
                                figure: stage == nil ? ledgerRows.first { $0.id == "total" }?.value : nil)
                            // Each stage's words morph into the next (prd §1586).
                            .animation(DS.Motion.standard, value: footVerb)
                    }
                    .buttonStyle(PressSpring())
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
                        .dsText(.body17)
                        .foregroundStyle(DS.textTertiary)
                    Self.mark(of: "Relay")
                    // Relay refuses every Tor exit (measured, prd §1495): the
                    // one wallet act that leaves Tor says so where it happens.
                    if TorRoute.available {
                        Text("· not through Tor")
                            .dsText(.body17)
                            .foregroundStyle(DS.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, DS.Space.s1)
            }
            // A swap's or a sweep's exchange signs the foot in the same
            // place (prd §1539): "On Uniswap · 0.05% pool fee". It is a fact
            // about this swap, so it carries no "powered by".
            // **POWERED BY COW SWAP (prd §1673, user: "it needs to say powered
            // by CoW Swap"):** a price's order is CoW's to fill, credited as
            // Relay's and Bitrefill's are, its mark beside the name, the fee after.
            if limiting, receipt == nil {
                HStack(spacing: DS.Space.s1) {
                    Text("Powered by CoW Swap")
                        .dsText(.body17)
                        .foregroundStyle(DS.textTertiary)
                    Self.mark(of: "CoW Swap")
                    Text(verbatim: "· " + String(localized: "\(YourAccountOrder.feeWords) fee"))
                        .dsText(.body17)
                        .foregroundStyle(DS.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, DS.Space.s1)
            }
            // The exchange's credit and "Moves the price" are rows of the
            // ledger under the sentence (prd §1754).
            // Both keys sign this one (prd §1456): said before the tap, not
            // when the Signer's sheet rises.
            // Read off the preview's own co-signer (user: "it doesn't say your
            // signer signs this too"): the limit's route missed an account
            // that already needs both keys on this network.
            if shownPreview?.signerSigns == true, receipt == nil, !nothingToMove {
                Text("Your Signer signs this too")
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, DS.Space.s1)
            }
            // The seller signs Buy's foot (prd §1599): its page is where
            // the card is typed.
            if verb == .deposit, let seller = depositSeller {
                HStack(spacing: DS.Space.s1) {
                    Text("Powered by \(seller.name)")
                        .dsText(.body17)
                        .foregroundStyle(DS.textTertiary)
                    Self.mark(of: seller.name)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, DS.Space.s1)
            }
            // Bitrefill's credit signs Buy's foot the same way (§1473, user:
            // "put bitrefill logo like we do w/ relay").
            if verb == .buy, receipt == nil {
                HStack(spacing: DS.Space.s1) {
                    Text("Powered by Bitrefill")
                        .dsText(.body17)
                        .foregroundStyle(DS.textTertiary)
                    Self.mark(of: "Bitrefill")
                }
                .frame(maxWidth: .infinity)
                .padding(.top, DS.Space.s1)
            }
        }
        .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
        .modifier(MoveFootClearance(inTray: inTray))
        // The page's own ground, so a long list scrolls under the foot. It
        // fades in over `footFade` above the foot, so a line passing under
        // it goes soft instead of being cut in half, which read as a fault
        // (prd §1610, user: "makes it look like an error").
        .background {
            Group { if inTray { DS.surfaceSheet } else { DSPageBackground() } }
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: Self.footFade)
                        Color.black
                    }
                }
                .padding(.top, -Self.footFade)
                .allowsHitTesting(false)
        }
    }

    /// The act's card, and Add's square beside it (prd §1755).
    static let actHeight: CGFloat = 76

    /// **THE ACT IS A PINK CARD (prd §1755, user: "i'm wondering if the
    /// buttons at the bottom should be more delightful maybe one is on a pink
    /// card", "they could take up more space"; shown three: "A, pink card").**
    /// The foot's act fills the row: Face ID's glyph, the verb, and what the
    /// move comes to at its trailing edge, white on the pick's pink; grey
    /// when it cannot act, amber or red when a warning stands. The one plate
    /// in Move, and it is the control (§759's exception).
    static func actCard(_ word: String, on: Bool, fill: Color = DS.pickInk, faceID: Bool = false, figure: String? = nil) -> some View {
        HStack(spacing: DS.Space.s2) {
            if faceID {
                Image(systemName: "faceid").dsGlyph(.title, weight: .semibold)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .accessibilityHidden(true)
            }
            Text(verbatim: word)
                .dsText(.heading24)
                .contentTransition(.interpolate)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: DS.Space.s2)
            if let figure {
                Text(verbatim: figure).dsText(.heading17).monospacedDigit().lineLimit(1)
                    .transition(.opacity)
            }
        }
        .foregroundStyle(on ? Color.white : DS.textTertiary)
        .padding(.horizontal, DS.Space.s6)
        .frame(maxWidth: .infinity, minHeight: actHeight)
        .background(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous).fill(on ? fill : DS.fillStrong))
        .contentShape(Rectangle())
    }

    private func actCard(_ word: String, on: Bool, fill: Color = DS.pickInk, faceID: Bool = false, figure: String? = nil) -> some View {
        Self.actCard(word, on: on, fill: fill, faceID: faceID, figure: figure)
    }

    /// How far above the foot its ground fades in.
    static let footFade: CGFloat = 32

    /// Read, nothing anywhere, and nothing under way: the foot has no act
    /// to draw (prd §1518). A move landing keeps its foot.
    private var nothingToMove: Bool {
        verb != .receive && verb != .deposit && emptyEverywhere && stage == nil && all.isEmpty
    }

    private var footOn: Bool {
        if limiting { return stage == nil && limitDraft != nil && !over }
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
        // Passed at the tap (prd §1687), Face ID is not asked for again.
        case .signing: return faceIDPassed ? String(localized: "Preparing…") : String(localized: "Confirm with Face ID")
        case .cosigning: return String(localized: "Waiting for your Signer…")
        case .sending: return String(localized: "Sending…")
        case .landing:
            if delivering { return String(localized: "Waiting for Bitrefill…") }
            return toppingUp ? String(localized: "Waiting for USDC on Base…") : String(localized: "Waiting for \(network.name)…")
        case nil: break
        }
        if verb == .receive { return String(localized: "Copy address") }
        if verb == .deposit { return String(localized: "Buy") }
        if verb == .buy { return String(localized: "Spend") }
        if verb == .sweep {
            return sweepItems.count < 2 ? String(localized: "Sweep") : String(localized: "Sweep all \(sweepItems.count)")
        }
        if limiting { return String(localized: "Place order") }
        // A warning makes it a second tap (prd §1509 item 2).
        if warned { return verb == .swap ? String(localized: "Swap anyway") : String(localized: "Send anyway") }
        // A tag paid from another token is one send to the person, whatever
        // it takes to make (prd §1768).
        if tagConverts || tagCrosses { return title(.send) }
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
        case .receive, .buy, .sweep, .deposit, .lend:
            break
        }
        return nil
    }

    private func add() {
        if limiting {
            say(String(localized: "An order goes alone"))
            return
        }
        if tagConverts || tagCrosses {
            say(tagCrosses ? String(localized: "A tag paid from another network goes alone")
                           : String(localized: "A tag paid from another token goes alone"))
            return
        }
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
        spendZkMoney([item])
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
        // A price places a CoW order (prd §1673); Now swaps (prd §1683).
        if limiting { placeOrder(); return }
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
        let roundUp = roundUpStep
        let carries = roundUpCarries
        let moveTarget = RoundUpsPot.shownTarget
        stage = .preparing
        clock = MoveClock()
        let tripLog = IngestSupport.TripLog()
        trips = tripLog
        // **FACE ID AT THE TAP (prd §1687, user: "the preparing stage is
        // where it lags").** Asked now, beside the reads; the operation's
        // signature takes what it passed. Turned down, the send stops at once.
        let unlock = YourAccountKey.unlockAhead(reason: reason)
        let thisSend = UUID()
        faceIDSend = thisSend
        faceIDPassed = false
        let work = Task {
            // Done either way: a Face ID still up for a send that already
            // ended is taken down, and a passed one signs nothing more.
            defer {
                if faceIDSend == thisSend { faceIDPassed = false; faceIDSend = nil }
                unlock?.context.invalidate()
            }
            do {
                // The pool's minimum decides the move; unread this launch, it
                // is read before the send is written (prd §1690).
                var roundUp = roundUp
                if let r = roundUp, PrivateMoneyStore.shared.roundUpsMinimum == nil {
                    await PrivateMoneyStore.shared.readYield(including: .ethereum)
                    roundUp = RoundUpsPot.step(change: r.change, owed: RoundUpsPot.owed, pot: RoundUpsPot.shown,
                                               moveAt: RoundUpsPot.moveAt(poolMinimum: PrivateMoneyStore.shared.roundUpsMinimum))
                }
                // **ROUND-UPS RIDE THIS OPERATION (prd §1690).** On Base, a
                // move that is due (Aave's withdrawal, then the Across deposit
                // into your private balance) and the change set aside; on
                // Ethereum or Robinhood, the change carried to Round-ups on
                // Base. One list, simulated with the send: one that does not
                // check out is dropped, never the send, and the change is
                // owed to the next one.
                var ride: RoundUpsPot.Calls = []
                var setAside = false
                var move: RoundUpsPot.Move?
                if let roundUp {
                    if roundUp.moves, net.chainId == RoundUpsPot.home {
                        do {
                            let m = try await RoundUpsPot.move(account: account)
                            move = m
                            ride += m.calls
                        } catch {
                            NSLog("roundUps| move waits | %@", String(describing: error))
                        }
                    }
                    if carries, let calls = await RoundUpsPot.setAside(roundUp.carry, on: net, account: account) {
                        ride += calls
                        setAside = true
                    }
                }
                // The operation is followed by its own id, so one still on its
                // way can be told landed or failed later (the review of
                // 2026-10-26, findings 2 and 3).
                let followed = Chain.Followed()
                let done = try await IngestSupport.$tripLog.withValue(tripLog) {
                    try await Chain.$following.withValue(followed) {
                        try await YourAccountKey.$ahead.withValue(unlock) {
                            try await Self.spend(batch, on: net, account: account, roundUp: nil, ride: ride, reason: reason,
                                                 said: { line in await MainActor.run { say(line) } }) { s in
                                await MainActor.run { advance(to: s) }
                            }
                        }
                    }
                }
                // **WHAT ROUND-UPS HOLDS, ONCE THE SEND HAS GONE.** Landed or
                // on its way, a ride counts as made (a pending one keeps its
                // note through `PrivatePending`); Round-ups is held to the
                // chain at its next read (`RoundUpsPot.healed`).
                var moved: String?
                var rodeAside = false
                if let roundUp {
                    let rode = done.rode && !ride.isEmpty
                    rodeAside = rode && setAside
                    switch done.sent.outcome {
                    case .landed, .pending:
                        let made = rode ? move : nil
                        let after = RoundUpsPot.after(roundUp, pot: RoundUpsPot.pot, setAside: rodeAside, moved: made?.moved)
                        RoundUpsPot.pot = after.pot
                        RoundUpsPot.owed = after.owed
                        if rodeAside, net.chainId != RoundUpsPot.home { RoundUpsPot.carriedAt = Date() }
                        if let made {
                            moved = made.moved
                            // The pool's minimum, read again for the next move's threshold.
                            Task { await PrivateMoneyStore.shared.readYield(including: .ethereum) }
                            Self.keepRoundUpsMove(made, outcome: done.sent.outcome, followed: followed, chainId: net.chainId,
                                                  account: account, context: context)
                        }
                    case .dryRun:
                        break
                    }
                    // **A SEND ON ANOTHER NETWORK MOVES IT TOO:** that same
                    // operation on Base, under this send's Face ID. Refused or
                    // unpaid for (no ETH on Base), Round-ups stays, earning,
                    // and the next send tries again.
                    if roundUp.moves, net.chainId != RoundUpsPot.home, case .landed = done.sent.outcome {
                        do {
                            // The tap's Face ID signs it too: one more hand on it (prd §1690).
                            let alone = try await YourAccountKey.$ahead.withValue(unlock?.again()) {
                                try await RoundUpsPot.moveAlone(account: account,
                                                                reason: String(localized: "Move Round-ups to your private balance"))
                            }
                            if case .dryRun = alone.sent.outcome {} else {
                                RoundUpsPot.pot = RoundUpsPot.after(RoundUpsPot.Step(change: "0", carry: "0", moves: true),
                                                                    pot: RoundUpsPot.pot, setAside: false, moved: alone.move.moved).pot
                                moved = alone.move.moved
                                Self.keepRoundUpsMove(alone.move, outcome: alone.sent.outcome, followed: alone.followed,
                                                      chainId: RoundUpsPot.home, account: account, context: context)
                            }
                        } catch {
                            NSLog("roundUps| move waits | %@", String(describing: error))
                        }
                    }
                }
                let sent = done.sent
                stage = nil
                let took = timed(sent.outcome)
                chrome.refreshRooms()
                // Landed or still on its way, the transaction is gone from the
                // page, so a second tap cannot pay it twice. The sentence
                // turns past tense in its place (§1438b): no toast.
                var made = Self.receipt(for: batch, done: done, on: net)
                if sweeping { made = Self.swept(made, count: batch.count) }
                // What Round-ups did, said on the receipt it rode (prd §1586, §1690).
                if case .landed = sent.outcome, let roundUp,
                   let said = Self.roundUpWords(roundUp, setAside: rodeAside, pot: RoundUpsPot.pot, target: moveTarget, moved: moved) {
                    made.detail = [made.detail, said].filter { !$0.isEmpty }.joined(separator: " · ")
                }
                // A first send to an address with no name offers one (prd §1586).
                if case .landed = sent.outcome, !sweeping { made.names = Self.unnamed(batch); made.tags = Self.unsavedTags(batch) }
                if let took { made.detail = [made.detail, took].filter { !$0.isEmpty }.joined(separator: " · ") }
                // A token a swap just bought is spendable now, not when the
                // Wallet next reads the account (§1442l).
                if case .landed = sent.outcome {
                    for item in batch { if case .swap(let x) = item { Tokens.remember(x.buy, on: net) } }
                }
                settleRequest(batch, outcome: sent.outcome)
                // Who Send sent to leads To next time (prd §1752): a send taken,
                // never a dry run, a sweep or the demo's.
                if verb == .send, !sweeping, sent.outcome != .dryRun, !YourAccountDemo.isDemo(account) {
                    RecentTo.remember(batch, account: account)
                    readRecentTo()
                    // Who each one-time address was for, so Activity names
                    // the person and not "zk.money" (prd §1767).
                    ZkMoney.notePaid(Self.paidTags(batch))
                }
                spendZkMoney(batch)
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
                        whenPick = nil
                    }
                    receipt = made
                }
                if case .landed = sent.outcome {
                    DSHaptic.success()
                    chrome.rain(sources: ["Wallet"])
                }
                // A swap to another network: its arrival is read (prd §1555).
                if let crossing = done.crossing, crossing.tx != nil {
                    crossingSeconds = batch.lazy.compactMap { item -> Int? in
                        if case .swap(let x) = item { return x.quote.across?.seconds } else { return nil }
                    }.first
                    crossingReceipt = made.id
                    crossingWatch = crossing
                }
                // Not seen yet is followed for two minutes more, and the
                // receipt turns past tense by itself (prd §1586).
                if case .pending = sent.outcome, let id = followed.id {
                    let key = followed.nonceKey, nonce = followed.nonce, account = account
                    Task { @MainActor in
                        for _ in 0..<24 {
                            try? await Task.sleep(for: .seconds(5))
                            guard receipt?.id == made.id else { return }
                            let f = await Chain.followup(id: id, nonceKey: key, nonce: nonce, account: account, on: net)
                            if f.receipt == false {
                                withAnimation(DS.Motion.standard) {
                                    receipt?.detail = String(localized: "It reached \(net.name) and failed: nothing moved but the fee")
                                }
                                DSHaptic.failure()
                                return
                            }
                            // The nonce moving alone could be a revert: said as
                            // "can't tell", never as landed (§83).
                            if f.receipt == nil, f.nonceMoved == true {
                                withAnimation(DS.Motion.standard) {
                                    receipt?.detail = String(localized: "Went through · check your activity before sending again")
                                }
                                return
                            }
                            guard f.receipt == true else { continue }
                            var landed = Self.receipt(for: batch, done: Chain.Transacted(sent: .init(outcome: .landed(transaction: f.tx, rotated: false), network: net)), on: net)
                            if sweeping { landed = Self.swept(landed, count: batch.count) }
                            if !sweeping { landed.names = Self.unnamed(batch); landed.tags = Self.unsavedTags(batch) }
                            withAnimation(DS.Motion.standard) { receipt = landed }
                            // A swap to another network that landed late is watched to its arrival.
                            if var c = done.crossing, let tx = f.tx {
                                c.tx = tx
                                crossingSeconds = batch.lazy.compactMap { item -> Int? in
                                    if case .swap(let x) = item { return x.quote.across?.seconds } else { return nil }
                                }.first
                                crossingReceipt = landed.id
                                crossingWatch = c
                            }
                            DSHaptic.success()
                            chrome.rain(sources: ["Wallet"])
                            chrome.refreshRooms()
                            return
                        }
                    }
                }
                await readNetwork()
            } catch let failure as Chain.Failure {
                stage = nil
                _ = timed(nil)
                // Face ID turned down at the tap stopped the reads (prd §1687):
                // whatever they threw, nothing was signed.
                if unlock?.refused == true { say(String(localized: "Not sent"), failure: true); return }
                // A stale fact could explain it (prd §1602): read afresh.
                Task { await Chain.forgetFacts(net, account); await Chain.readAhead(account, on: net) }
                #if DEBUG
                NSLog("moveSign: failed %@", failure.message)
                #endif
                say(failure.message, failure: true, seconds: 6, from: failure.from)
            } catch {
                stage = nil
                _ = timed(nil)
                #if DEBUG
                NSLog("moveSign: not sent %@", String(describing: error))
                #endif
                // Face ID cancelled, or the Enclave refused: nothing left the phone.
                say(String(localized: "Not sent"), failure: true)
            }
        }
        // Face ID's answer, as it comes: passed is felt and changes the foot's
        // words; turned down ends the send where it is.
        if let unlock {
            Task { @MainActor in
                if await unlock.passed() {
                    if faceIDSend == thisSend, stage != nil { faceIDPassed = true; DSHaptic.tap() }
                } else {
                    work.cancel()
                }
            }
        }
    }

    /// **FACE ID PASSING IS FELT (prd §1586).** One light tap as the foot's
    /// words turn from "Confirm with Face ID" to "Sending…"; Face ID asked at
    /// the tap is felt as it passes instead (prd §1687).
    private func advance(to s: Chain.Stage) {
        if stage == .signing, s == .sending || s == .cosigning, !faceIDPassed { DSHaptic.tap() }
        stage = s
        clock?.enter(Self.clockMark(s))
    }

    static func clockMark(_ s: Chain.Stage) -> MoveClock.Mark {
        switch s {
        case .preparing: .preparing
        case .signing: .faceID
        case .cosigning: .signer
        case .sending: .sending
        case .landing: .landing
        }
    }

    /// **THE PHONE'S OWN NUMBER (prd §1602).** The send's stages, kept in
    /// `PerfReadings` and logged however it ended; on a landed or pending
    /// receipt in a pre-release build, "Took 12s: preparing 2.1s, …".
    private func timed(_ outcome: Chain.Sent.Outcome?) -> String? {
        defer { clock = nil; trips = nil }
        let counted = trips?.read ?? (trips: [], retries: [])
        let ended: String = switch outcome {
        case .landed?: "landed"
        case .pending?: "pending"
        case .dryRun?: "dry run"
        case nil: "not sent"
        }
        guard let words = clock?.words(until: .now, trips: counted.trips, retries: counted.retries),
              let total = clock?.total(until: .now) else { return nil }
        NSLog("moveClock| %@ | %@ | %@", network.name, ended, words)
        PerfReadings.record("MoveSend", ms: total * 1000, note: "\(ended) on \(network.name) · \(words)")
        if BuildChannel.isPreRelease, outcome != nil {
            return String(localized: "Took \(words)")
        }
        return nil
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
        // The Signer is read beside the limit (prd §1601), not after it, and
        // only where a limit can be on: this phone set its plan.
        func signersIfLimited() async throws -> [String] { Chain.plan(net) == nil ? [] : try await Chain.knownSigners(net, account) }
        async let signers = signersIfLimited()
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
        guard let signer = try await signers.first else {
            throw Chain.Failure(message: needsCoSigner)
        }
        return try await Chain.transact(batch, reason: reason, coSigner: SignerRequestSheet.coSigner(owner: signer, chainId: net.chainId),
                                        roundUp: roundUp, renew: true, ride: ride, stage: stage)
    }

    /// What this operation's own sends and swaps take of `token`, so a
    /// round-up's ride knows what is left of it (prd §1578).
    static func leaving(_ batch: [Chain.Item], _ token: Op.Token) -> String {
        batch.reduce("0") { sum, item in
            switch item {
            case .send(let p) where p.token == token: Op.sum(sum, p.amount)
            case .swap(let s) where s.sell == token: Op.sum(sum, s.amount)
            default: sum
            }
        }
    }

    /// Round-ups that rode a landed operation (prd §1567): the note kept
    /// waiting for approval, its Activity row with no verb.
    /// Kept whether or not the transaction is named (finding 2): a ride that
    /// landed with only the nonce moved, or one still on its way, is kept by
    /// its commitment; the row lands once a hash is known (`PrivatePending`).
    @MainActor
    static func landPrivateRoundUps(_ ride: PrivateOnEthereum.Ride, tx: String?, context: ModelContext?) {
        let n = ride.keep
        PrivateMoneyStore.shared.add(.init(commitment: n.commitment, label: n.label, labelHash: n.labelHash, symbol: n.symbol,
                                           amount: n.amount, decimals: n.decimals, chainId: n.chainId, tx: tx ?? "", at: Date(),
                                           status: .waiting, root: n.root, share: n.share))
        if let tx, let context {
            PrivateActivity.land(hash: tx, title: PrivateMoney.roundUpsTitle(figure: ride.figure), chainId: n.chainId, context: context)
        }
        NSLog("roundUpsPrivate| moved | %@ | %@", tx ?? "not yet seen", ride.figure)
    }

    /// A Round-ups move that went (prd §1690): its note kept waiting for
    /// approval and its Activity row, as round-ups always landed (§1567);
    /// one still on its way is followed by its operation's id, and its note
    /// kept by its commitment until the pool shows it (finding 2).
    @MainActor
    static func keepRoundUpsMove(_ move: RoundUpsPot.Move, outcome: Chain.Sent.Outcome, followed: Chain.Followed, chainId: Int,
                                 account: String, context: ModelContext?) {
        switch outcome {
        case .landed(let tx, _):
            landPrivateRoundUps(move.ride, tx: tx, context: context)
        case .pending:
            landPrivateRoundUps(move.ride, tx: nil, context: nil)
            guard let id = followed.id else { return }
            PrivatePending.shared.add(.init(id: id, chainId: chainId, account: account, nonceKey: SafeABI.hex(followed.nonceKey),
                                            nonce: followed.nonce, at: Date(), commitment: move.ride.keep.commitment,
                                            title: PrivateMoney.roundUpsTitle(figure: move.ride.figure),
                                            reserved: nil, toPrivate: true))
        case .dryRun:
            break
        }
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
            let waiting = [String(localized: "Moving to \(dest.name)"), YourAccountAcross.about(x.quote.across?.seconds)]
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
    private var receiveAddress: String { verb == .deposit ? account : elsewhere?.address ?? account }

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
        let start = Date()
        let until = start.addingTimeInterval(15 * 60)
        var tick = 0
        while !Task.isCancelled, Date() < until {
            // The receipt counts while it moves (prd §1586): "Moving to
            // Ethereum · 6 of about 10 seconds", then the seconds alone.
            let elapsed = Int(Date().timeIntervalSince(start))
            if receipt?.id == crossingReceipt, elapsed > 0 {
                let counted = crossingSeconds.map { about in
                    elapsed <= about ? String(localized: "\(elapsed) of about \(about) seconds") : String(localized: "\(elapsed) seconds")
                } ?? String(localized: "\(elapsed) seconds")
                receipt?.detail = String(localized: "Moving to \(name)") + " · " + counted
            }
            tick += 1
            // Asked every four seconds; the count moves every one.
            guard tick % 4 == 1 else { try? await Task.sleep(for: .seconds(1)); continue }
            if await Chain.acrossFill(c) == .filled {
                YourAccountAcross.update(c.id) { x in
                    if x.state == .waiting { x.state = .filled; x.settledAt = .now }
                }
                #if DEBUG
                NSLog("moveAcross| filled %@ → %@", YourAccountAcross.networkName(c.from), name)
                #endif
                let took = Int(Date().timeIntervalSince(start))
                if receipt?.id == crossingReceipt {
                    withAnimation(DS.Motion.standard) {
                        receipt?.detail = String(localized: "Arrived on \(name)") + " · " + String(localized: "\(took) seconds")
                    }
                } else {
                    // Done was tapped while it moved: said in place all the same.
                    say(String(localized: "Arrived on \(name)"))
                }
                DSHaptic.success()
                chrome.rain(sources: ["Wallet"])
                chrome.refreshRooms()
                crossingWatch = nil
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    // MARK: - Reads

    /// What the account holds, everywhere, read again whenever money may
    /// have arrived since (user: "i have money in my account but casberi
    /// says i can't receive or swap"): the app coming back and leaving
    /// Receive (another tab unmounts Move, so its return reads anew). A
    /// token being spent keeps up.
    /// `shared`: Move's opening read joins the Wallet's warm-up or takes
    /// its reading (`MoveWarm`, prd §1610); every later read is its own.
    private func readHoldings(shared: Bool = false) async {
        // Every network at once: one slow node holds none of the others.
        var found: [Int: [Tokens.Held]] = [:]
        var failed: Set<Int> = []
        await withTaskGroup(of: (Int, [Tokens.Held]?).self) { group in
            for net in Op.networks {
                group.addTask { @MainActor in
                    (net.chainId, shared ? await Tokens.readShared(account, on: net) : await Tokens.read(account, on: net))
                }
            }
            for await (id, held) in group {
                found[id] = held ?? []
                if held == nil { failed.insert(id) }
                // Each network's tokens show as it answers (prd §1586): the
                // fast ones never wait on the slowest.
                if let held { heldBy[id] = held }
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
        // The send forgot what the account is; read again for the next one.
        Task { [account, network] in await Chain.readAhead(account, on: network) }
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
        if let total = buyTotal, let buy { staleBack = (buy.id, Self.short(total, decimals: buy.token.decimals) + " ") }
        quote = nil
        quoteNote = nil
        quoteFrom = nil
        guard verb == .swap, let with, let buy, YourAccountSwap.supported(network), let units, !over else { staleBack = nil; return }
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
            withAnimation(DS.Motion.standard) { quote = q; staleBack = nil }
            // A pair's first price lands with one tick; a re-price is silent.
            let pair = "\(network.chainId)|\(with.id)|\(buy.id)"
            if !pricedPairs.contains(pair) {
                pricedPairs.insert(pair)
                DSHaptic.selection()
            }
            #if DEBUG
            // `moveSwapQuote|` (prd §1542): which pools won, in words and as a route.
            let hops = q.route?.hops.map { "\($0.from.suffix(6))>\($0.step)>\($0.to.suffix(6))" }.joined(separator: " ") ?? "-"
            NSLog("moveSwapQuote| %@ %@ %@→%@ | %@ | out=%@ min=%@ | %@ calls=%d", network.name, units, with.token.symbol, buy.token.symbol,
                  q.route.map(YourAccountSwap.words) ?? "-", q.buyAmount, q.minimumBuy, hops, q.calls.count)
            draftAddsTheSwap()
            #endif
        } catch let failure as Chain.Failure {
            guard !Task.isCancelled else { return }
            staleBack = nil
            quoteNote = failure.message
            quoteFrom = failure.from
        } catch {
            if !Task.isCancelled { staleBack = nil }
        }
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
        if let r = resolved, r.name?.caseInsensitiveCompare(text) == .orderedSame,
           !zkMoneyUsed.contains(r.address.lowercased()) { lookup = nil; return }
        resolved = nil
        malformed = false
        lookup = nil
        guard !text.isEmpty else { return }
        // A zk.money request link writes the whole sentence (prd §1748).
        if await takeRequestLink(text) { return }
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
        // `@bob` is zk.money's own spelling of a tag (prd §1767): To reads
        // it as bob.zk.money, unless a name in your book is spelled so.
        if let full = ZkMoneyWire.atTag(text),
           !AddressBook.shared.all.contains(where: { $0.name.caseInsensitiveCompare(text) == .orderedSame }) {
            to = full
            return
        }
        // A zk.money tag is paid at a fresh deposit address its resolver
        // proves on chain, never at the account the tag names (prd §1692),
        // and is read before your book: a name there may hold a deposit
        // address already paid.
        if let tag = ZkMoneyWire.tag(text) {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            withAnimation(DS.Motion.standard) { lookup = .looking(text) }
            let paid = YourAccountDemo.isDemo(account) ? ZkMoney.PayAnswer.address(ZkMoney.demoDeposit)
                : await ZkMoney.depositAddress(tag: tag)
            guard !Task.isCancelled, text == to.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            withAnimation(DS.Motion.standard) {
                switch paid {
                case .address(let address):
                    zkMoneyDeposits.insert(address.lowercased())
                    // An address proven for the request's own tag pays it (prd §1745).
                    if text.lowercased() == payingRequest?.to { requestDeposits.insert(address.lowercased()) }
                    lookup = nil
                    resolved = Recipient(address: EIP55.checksum(address), name: text, imitates: nil)
                    setUpTagPayment()
                case .notOnV6:
                    lookup = .refused(String(localized: "\(ZkMoneyWire.display(tag)) hasn't moved to Aztec's new network yet"))
                case .unclaimed:
                    lookup = .missing(text)
                case .unreachable:
                    lookup = .refused(String(localized: "zk.money's resolver didn't answer. Try again in a minute."))
                }
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
        guard !Task.isCancelled else { return }
        withAnimation(DS.Motion.standard) { lookup = .looking(text) }
        let answer = await NameResolve.resolve(text)
        // The field may have changed while the resolver answered: an old
        // name's address must never stand for what the field says now.
        guard !Task.isCancelled, text == to.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        guard let address = answer, ENS.isHexAddress(address) else {
            withAnimation(DS.Motion.standard) { lookup = .missing(text) }
            return
        }
        withAnimation(DS.Motion.standard) {
            lookup = nil
            resolved = Recipient(address: EIP55.checksum(address), name: text, imitates: nil)
        }
    }


    // MARK: - Buy (prd §1473)

    /// The holding Spend pays with as it is: USDC on Base. Anything else
    /// that pays is turned into it first (prd §1666, `SpendTopUp`).
    static func paysBuy(_ h: Tokens.Held, on net: Op.Network) -> Bool {
        SpendTopUp.direct(h.token, on: net)
    }

    private var buyAccount: String? {
        if YourAccountDemo.isOn { return account }
        return YourAccountKey.address ?? (BitrefillX402.sample ? account : nil)
    }

    /// Buy's sentence: "$50 gift card for Travel at Delta with USDC on Base."
    /// — the amount is the card's value, the category and the merchant are
    /// words that open their lists, and the payment is a fact, not a choice.
    // MARK: - Buy with a card (prd §1599)

    /// **BUY IS A SENTENCE (prd §1599):** "$50 of USDC on Ethereum." A
    /// card buys it on the network's one seller's page (`CardOnramp`): Stripe
    /// on Ethereum, Ramp on Base. Only networks a card can buy on are
    /// offered, so the act never opens a page that cannot sell.
    @ViewBuilder private var depositClauses: some View {
        MoveClause {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                word("$", ink: amount.isEmpty ? DS.textTertiary : MoveSentence.settledInk)
                amountField
            }
            .background { amountBlank(dollars: true) }
            .dsCardLead(Text("Edits the amount")) { focus = .amount }
        }
        MoveClause(glue: String(localized: "of")) {
            blank(depositCoin.symbol, ink: MoveSentence.settledInk, .depositCoin, label: Text("\(depositCoin.symbol), change"))
        }
        MoveClause(glue: String(localized: "on")) {
            if depositSeller != nil {
                blank(network.name + ".", ink: MoveSentence.settledInk, .depositNetwork, label: Text("On \(network.name), change"))
            } else {
                blank(String(localized: "network."), ink: DS.textTertiary, .depositNetwork, empty: true, label: Text("Pick a network"))
            }
        }
    }

    /// The seller for the picked network; nil until one a card can buy on is picked.
    private var depositSeller: CardOnramp.Seller? {
        // Only where this phone can use the account (§1442k): a network
        // carried over from another verb may not be one.
        networkPicked && depositNetworks.contains(network) ? CardOnramp.seller(chainId: network.chainId) : nil
    }

    /// Your networks a card can buy on, most held first.
    private var depositNetworks: [Op.Network] {
        networksByWorth.filter { !$0.isTest && CardOnramp.seller(chainId: $0.chainId) != nil }
    }

    private var depositCoinList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(CardOnramp.Coin.allCases, id: \.self) { coin in
                listRow(coin.symbol, sub: coin == .usdc ? String(localized: "Dollars") : String(localized: "Ether"),
                        mark: coin.symbol, picked: coin == depositCoin) {
                    pick { depositCoin = coin }
                }
            }
        }
    }

    private var depositNetworkList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(depositNetworks) { n in
                if let seller = CardOnramp.seller(chainId: n.chainId) {
                    listRow(n.name, sub: String(localized: "with \(seller.name)"), image: Self.networkMark(n),
                            picked: depositSeller != nil && n == network) {
                        // One transaction is one network, as the network blank says.
                        if n != network, !items.isEmpty {
                            say(String(localized: "One transaction is one network. Sign this one first"))
                        } else {
                            pick { switchNetwork(n) }
                        }
                    }
                }
            }
        }
    }

    /// Under the sentence: the whole address, to check against the seller's
    /// page, and the one line saying what that page does.
    @ViewBuilder private var depositLine: some View {
        if let seller = depositSeller {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                addressBlock(account)
                Text(seller.takesAddress
                     ? "\(seller.name)'s page shows its fee before you pay, with this address filled in."
                     : "\(seller.name)'s page shows its fee before you pay. This address is copied to paste there.")
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Dollars, and the one network a card can buy on picked when there is
    /// only one.
    private func enterDeposit() {
        if !inDollars { amount = "" }
        inDollars = true
        if depositSeller == nil, items.isEmpty, depositNetworks.count == 1, let only = depositNetworks.first { switchNetwork(only) }
    }

    /// The seller's page (prd §1599). Stripe's cannot take the address, so it
    /// is copied first and the hint says where it goes; Ramp's is handed it.
    private func deposit() {
        guard let seller = depositSeller else {
            say(String(localized: "Pick a network first"))
            withAnimation(DS.Motion.standard) { open = .depositNetwork }
            return
        }
        // The demo's address holds no key (§1475), so nothing is bought into it.
        if YourAccountDemo.isDemo(account) { say(YourAccountDemo.actsLater); return }
        guard let url = CardOnramp.url(depositCoin, chainId: network.chainId, address: account, dollars: amount) else { return }
        focus = nil
        DSHaptic.tap()
        if !seller.takesAddress {
            UIPasteboard.general.string = account
            say(String(localized: "Address copied. Paste it on \(seller.name)'s page."), seconds: 6)
        }
        #if DEBUG
        NSLog("moveDeposit| %@ | %@ on %@ | %@", seller.name, depositCoin.symbol, network.name, url.absoluteString)
        #endif
        // The page covers Move, so the hint is read first.
        Task { @MainActor in
            if !seller.takesAddress { try? await Task.sleep(for: .milliseconds(1200)) }
            CardOnrampDoor.open(url)
        }
    }

    @ViewBuilder private var buyClauses: some View {
        MoveClause {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                word("$", ink: amount.isEmpty ? DS.textTertiary : MoveSentence.settledInk)
                amountField
            }
            .contentShape(Rectangle())
            .background { amountBlank(dollars: true) }
            .dsCardLead(Text("Edits the amount")) { if stage == nil { focus = .amount } }
        }
        // The noun is its own clause, and so are "with USDC" and "on Base.":
        // the flow sizes the sentence by its widest clause (§1479), and one
        // unbreakable "with USDC on Base." drew Buy a size under Swap, Send
        // and Receive (prd §1481).
        MoveClause { word(buyProduct?.noun ?? String(localized: "gift card"), ink: DS.textPrimary) }
        MoveClause(glue: String(localized: "for")) {
            blank(buyGroup?.title ?? String(localized: "category"), ink: buyGroup == nil ? DS.textTertiary : MoveSentence.settledInk,
                  .group, empty: buyGroup == nil, label: Text("Pick a category"))
        }
        MoveClause(glue: String(localized: "at")) {
            blank(buyProduct.map { BitrefillBuy.shortName($0.name) } ?? String(localized: "merchant"),
                  ink: buyProduct == nil ? DS.textTertiary : MoveSentence.settledInk, .merchant, empty: buyProduct == nil, label: Text("Pick a merchant"))
        }
        // What pays is a choice (prd §1666): USDC on Base as it is, ETH or
        // USDC on Base or Ethereum swapped into it first.
        MoveClause(glue: String(localized: "with")) {
            blank(with?.token.symbol ?? String(localized: "coin"), ink: with == nil ? DS.textTertiary : MoveSentence.settledInk,
                  .with, empty: with == nil, label: Text("Pick what pays"))
        }
        MoveClause(glue: String(localized: "on")) { word(network.name + ".", ink: DS.textPrimary) }
    }

    /// Bitrefill's categories folded to seven, each with the cards people
    /// know it by; a pick keeps a merchant only if it stands in the group.
    private var groupList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(BitrefillBuy.Group.allCases, id: \.self) { g in
                listRow(g.title, sub: g.examples, symbol: g.glyph, picked: buyGroup == g) {
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
            if rows.isEmpty, spend.isEmpty, needsBitrefillSignIn {
                // Face ID only on this press, never on picking Spend (user,
                // 2026-11-02: "Face id happening before I press anything").
                // No Bitrefill account exists or is made: the account signs
                // once and Bitrefill answers for two hours (user, 2026-11-02:
                // "people don't create a bitrefill account").
                listRow(String(localized: "Show gift cards"),
                        sub: String(localized: "Face ID once, good for two hours"), symbol: "faceid") {
                    Task { await readCatalogue(retry: true) }
                }
            } else if rows.isEmpty, spend.isEmpty {
                HStack(spacing: DS.Space.s2) {
                    if buyReading { DSSpinner() }
                    Text(verbatim: buyReading ? String(localized: "Asking Bitrefill")
                         : buyFailure ?? (q.isEmpty ? String(localized: "Nothing here yet") : String(localized: "Nothing named \(q)")))
                        .dsText(.body17).foregroundStyle(buyFailure != nil && !buyReading ? DS.attentionInk : DS.textSecondary)
                }
                .frame(minHeight: DSFeed.headHeight)
                if buyFailure != nil, !buyReading {
                    listRow(String(localized: "Try again"), symbol: "arrow.clockwise") {
                        Task { await readCatalogue(retry: true) }
                    }
                }
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
                       mark: name, brand: Self.merchantMark(name), picked: buyProduct?.id == p.id) {
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

    /// Spend picked: USDC on Base pays when there is any, else what pays and
    /// is worth most (prd §1666); the popular list is read, and the names
    /// Casberi knows you pay are matched against it.
    private func enterBuy() {
        inDollars = true
        if with.map({ SpendTopUp.pays($0.token, on: network) }) != true {
            let payers = networksByWorth.flatMap { n in
                (heldBy[n.chainId] ?? []).filter { SpendTopUp.pays($0.token, on: n) }.map { (net: n, held: $0) }
            }
            if let pick = payers.first(where: { SpendTopUp.direct($0.held.token, on: $0.net) })
                ?? payers.max(by: { ($0.held.usd ?? 0) < ($1.held.usd ?? 0) }) {
                switchNetwork(pick.net)
                with = pick.held
            } else {
                switchNetwork(BitrefillX402.network)
            }
        }
        networkPicked = true
        spendNames = Self.spendNames()
        if bitrefillOpen { Task { await readCatalogue() } }
    }

    /// Bitrefill answers without a Face ID: the demo's catalogue, the DEBUG
    /// sample, or a sign-in still inside its two hours. Otherwise nothing
    /// asks it until the merchant list's Show gift cards row is pressed.
    private var bitrefillOpen: Bool {
        YourAccountDemo.isOn || BitrefillX402.sample || BitrefillX402.signedIn
    }

    /// The merchant list leads with Show gift cards: nothing read, nothing reading,
    /// nothing refused.
    private var needsBitrefillSignIn: Bool {
        !bitrefillOpen && popular.isEmpty && !buyReading && buyFailure == nil
    }

    /// Bitrefill's popular cards, read once per visit; the first read signs
    /// in. A refusal stays in the merchant list (`buyFailure`) with Try
    /// again: flashed and then dropped, it left every category reading
    /// "Nothing here yet" (user, 2026-11-02: "no matter which category i
    /// choose").
    private func readCatalogue(retry: Bool = false) async {
        if let running = catalogueRead { await running.value; return }
        guard popular.isEmpty, let account = buyAccount else { return }
        let read = Task { @MainActor in
            buyReading = true
            defer { buyReading = false }
            do {
                popular = try await BitrefillX402.search("", account: account)
                buyFailure = nil
                // A place not among the popular is searched by name, a few.
                let unmatched = spendNames.filter { BitrefillBuy.whereYouSpend([$0], in: popular).isEmpty }.prefix(4)
                for name in unmatched {
                    let key = BitrefillBuy.stem(name)
                    guard key.count >= 3, let hits = try? await BitrefillX402.search(key, account: account) else { continue }
                    foundProducts = Self.dedupe(foundProducts + hits)
                }
            } catch {
                let failure = error as? Chain.Failure
                buyFailure = failure?.message ?? error.localizedDescription
                if !retry { say(buyFailure ?? "", failure: true, seconds: 6, from: failure?.from) }
            }
        }
        catalogueRead = read
        await read.value
        catalogueRead = nil
        // A category tap seeds after the read; Try again seeds the one picked.
        if retry, buyFailure == nil, let group = buyGroup { await seedGroup(group) }
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
        // The popular read signs in; a seed search started beside it would
        // ask for a second Face ID, and one after its refusal would fail the
        // same way, silently.
        if let running = catalogueRead { await running.value }
        guard buyFailure == nil, bitrefillOpen, let account = buyAccount else { return }
        for word in g.searches {
            guard let hits = try? await BitrefillX402.search(word, account: account) else { continue }
            foundProducts = Self.dedupe(foundProducts + hits)
        }
    }

    /// Typing in the merchant list asks Bitrefill after a pause.
    private func searchMerchants() async {
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2, bitrefillOpen, let account = buyAccount else { return }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        buyReading = true
        defer { buyReading = false }
        do {
            let hits = try await BitrefillX402.search(text, account: account)
            guard !Task.isCancelled else { return }
            buyFailure = nil
            foundProducts = Self.dedupe(foundProducts + hits)
        } catch {
            // With no catalogue the refusal is the sign-in's, and it is the
            // list's to say; past it, a word that failed is "Nothing named".
            guard !Task.isCancelled, popular.isEmpty else { return }
            buyFailure = (error as? Chain.Failure)?.message ?? error.localizedDescription
        }
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

    /// What the card costs in USDC base units, once the detail priced it.
    private var buyCost: String? {
        buyPackage.flatMap { Op.baseUnits(BitrefillBuy.Product.valueText($0.price), decimals: 6) }
    }

    /// What Spend sells first when it does not pay in USDC on Base (prd
    /// §1666), at the token's last price with the room the swap keeps.
    private var buySells: String? {
        guard let with, let cost = buyCost, !Self.paysBuy(with, on: network) else { return nil }
        return SpendTopUp.estimate(cost: cost, held: with, on: network)
    }

    private var buyReady: Bool {
        guard verb == .buy, buyProduct?.needsPhoneNumber != true, let with, SpendTopUp.pays(with.token, on: network),
              let cost = buyCost else { return false }
        if Self.paysBuy(with, on: network) { return Op.atMost(cost, left(with)) }
        return buySells.map { Op.atMost($0, left(with)) } ?? false
    }

    /// Why Buy is grey, in a sentence.
    private var buyMissing: String? {
        guard verb == .buy else { return nil }
        if !buyAvailable { return String(localized: "Make your account first") }
        if with == nil {
            if heldBy[network.chainId] == nil { return String(localized: "Reading…") }
            return unread.contains(Op.base.chainId) ? String(localized: "Couldn't read Base")
                : String(localized: "You have no ETH or USDC on Base or Ethereum")
        }
        if buyProduct == nil { return String(localized: "Pick a merchant") }
        // Said before the tap, not refused at it (prd §1586).
        if buyProduct?.needsPhoneNumber == true { return String(localized: "Top-ups need a phone number, which Buy can't send yet") }
        if let p = buyProduct, let v = buyValue, let why = p.refusal(v) { return why }
        if amount.isEmpty { return String(localized: "Type an amount first") }
        if let with, !Self.paysBuy(with, on: network), buyCost != nil, buySells == nil {
            return String(localized: "No price for \(with.token.symbol) yet")
        }
        if !buyReady { return String(localized: "More than you have") }
        return nil
    }

    /// The grey line in sentence case: whichever part leads ("you have …"
    /// alone, before a card is picked) starts with a capital (prd §1616
    /// item 10).
    static func lineCase(_ line: String) -> String {
        guard let first = line.first else { return line }
        return first.uppercased() + line.dropFirst()
    }

    /// "Costs $52.50 · you have 312.40 USDC": what the card costs, and what
    /// is there to pay it.
    private var buyPrint: [String] {
        var parts: [String] = []
        if let package = buyPackage, let p = buyProduct {
            parts.append(String(localized: "Costs \(BitrefillBuy.money(package.price, currency: package.currency))"))
            if p.needsPhoneNumber { parts.append(String(localized: "needs a phone number")) }
        }
        // Anything but USDC on Base is swapped into it first (prd §1666).
        if let with, let sells = buySells {
            parts.append(String(localized: "swaps about \(Op.spoken(sells, decimals: with.token.decimals)) \(with.token.symbol) to USDC on Base first"))
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
            say(String(localized: "Top-ups need a phone number, which Buy can't send yet"), failure: true)
            return
        }
        let spoken = Op.spoken(Op.baseUnits(BitrefillBuy.Product.valueText(package.price), decimals: 6) ?? "0", decimals: 6)
        let reason = BitrefillBuy.faceWords(spoken: spoken, value: product.money(value), product: product)
        let net = network
        // Anything but USDC on Base is swapped into it first (prd §1666); a
        // card paid that way rounds nothing up: its dollars land on Base.
        let topUp = with.flatMap { Self.paysBuy($0, on: net) ? nil : $0 }
        // The demo's address holds no key (§1475): nothing is swapped from it.
        if topUp != nil, YourAccountDemo.isDemo(account) { say(YourAccountDemo.actsLater); return }
        let cost = buyCost
        let roundUp = topUp == nil ? roundUpStep : nil
        stage = .preparing
        delivering = false
        Task { @MainActor in
            do {
                var swapped: String?
                if let topUp, let cost {
                    toppingUp = true
                    let swap = try await SpendTopUp.swap(cost: cost, held: topUp, on: net, account: account)
                    let sold = Op.spoken(swap.amount, decimals: topUp.token.decimals) + " " + topUp.token.symbol
                    let why = String(localized: "Swap \(sold) for USDC on Base, to pay for a \(product.money(value)) \(BitrefillBuy.shortName(product.name)) \(product.noun)")
                    _ = try await Self.spend([.swap(swap)], on: net, account: account, roundUp: nil, reason: why,
                                             said: { line in await MainActor.run { say(line) } }) { s in
                        await MainActor.run { advance(to: s) }
                    }
                    stage = .landing
                    // The dollars read on Base before Bitrefill is asked: from
                    // Ethereum, Across fills in seconds to minutes.
                    guard await SpendTopUp.arrived(cost: cost, account: account) else {
                        throw Chain.Failure(message: String(localized: "Your USDC has not reached Base yet. Spend again once it has"))
                    }
                    toppingUp = false
                    Tokens.remember(Op.dollar(on: Op.base), on: Op.base)
                    swapped = String(localized: "Swapped \(sold) on \(net.name) first")
                }
                let invoice = try await BitrefillX402.buy(product: product, value: value, account: account, reason: reason) { s in
                    await MainActor.run { advance(to: s) }
                }
                stage = .landing
                delivering = true
                // Paid: its change is counted, bought by a later send (prd §1561).
                // A Buy carries no call of ours: its change is owed to the next send (prd §1690).
                if let roundUp { RoundUpsPot.owed = roundUp.carry }
                chrome.refreshRooms()
                let standing = await BitrefillX402.awaitDelivery(invoiceID: invoice.id, account: account)
                let landed = BitrefillX402.land(invoice: invoice, product: product, value: value, delivered: standing?.delivered == true)
                stage = nil
                delivering = false
                var made = Self.buyReceipt(product: product, value: value, invoice: invoice, net: Op.base,
                                           delivered: standing?.delivered == true, failed: standing?.failed == true, landed: landed)
                if let swapped { made.detail = swapped + " · " + made.detail }
                withAnimation(DS.Motion.standard) {
                    amount = ""
                    buyProduct = nil
                    receipt = made
                }
                // **SUCCESS ONLY FOR A CARD THAT ARRIVED (prd §1586, §83).** A
                // card Bitrefill could not deliver is felt as a refusal and
                // rains nothing; one still on its way is a plain tap.
                if standing?.delivered == true {
                    DSHaptic.success()
                    chrome.rain(sources: ["Wallet"])
                } else if standing?.failed == true {
                    DSHaptic.failure()
                } else {
                    DSHaptic.tap()
                }
                await readNetwork()
            } catch let failure as Chain.Failure {
                stage = nil
                delivering = false
                toppingUp = false
                #if DEBUG
                NSLog("moveBuy: failed %@", failure.message)
                #endif
                say(failure.message, failure: true, seconds: 6, from: failure.from)
            } catch {
                stage = nil
                delivering = false
                toppingUp = false
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
    /// A launch hook fills the sentence, so the lists are read before it.
    static var drafting: Bool {
        ["moveWarnProbe", "moveWhenDraft", "moveSwapDraft", "moveSendDraft", "moveReceiveFrom", "moveBuyDraft", "moveSweepDraft", "moveDepositDraft"]
            .contains { UserDefaults.standard.string(forKey: $0)?.isEmpty == false }
    }

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
            // `-moveWhenDraft open|now|<price>|<n>%` (prd §1673): answered once
            // the pair is there to answer it for.
            if let w = d.string(forKey: "moveWhenDraft"), !w.isEmpty { whenDraftPending = w }
        } else if d.string(forKey: "moveSendDraft")?.isEmpty == false {
            verb = .send
            sendDraft()
        } else if let from = d.string(forKey: "moveReceiveFrom"), !from.isEmpty {
            verb = .receive
            receiveDraft(from)
        } else if let buyDraft = d.string(forKey: "moveBuyDraft"), !buyDraft.isEmpty {
            verb = .buy
            self.buyDraft(buyDraft)
        } else if let deposit = d.string(forKey: "moveDepositDraft"), !deposit.isEmpty {
            // `-moveDepositDraft "<dollars>|<USDC|ETH>[@<network>]"` (prd §1599):
            // Buy filled; logs `moveDeposit|` with the page it would open.
            verb = .deposit
            let parts = deposit.split(separator: "@", maxSplits: 1).map(String.init)
            let fields = parts[0].split(separator: "|").map(String.init)
            inDollars = true
            amount = fields.first ?? ""
            if fields.count > 1, let coin = CardOnramp.Coin(rawValue: fields[1].lowercased()) { depositCoin = coin }
            let named = parts.count > 1 ? Op.networks.first { $0.name.lowercased() == parts[1].lowercased() } : nil
            if let n = named ?? depositNetworks.first { switchNetwork(n) }
            open = nil
            if let seller = depositSeller,
               let url = CardOnramp.url(depositCoin, chainId: network.chainId, address: account, dollars: amount) {
                NSLog("moveDeposit| %@ | %@ on %@ | %@", seller.name, depositCoin.symbol, network.name, url.absoluteString)
            } else {
                NSLog("moveDeposit| none | %@ on %@", depositCoin.symbol, network.name)
            }
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
    /// the last is Added once its recipient resolves. A trailing
    /// `@<network>` sends on that network (`20|zac.zk.money|USDC@Ethereum`).
    private func sendDraft(_ given: String? = nil) {
        guard let given = given ?? UserDefaults.standard.string(forKey: "moveSendDraft"), !given.isEmpty else { return }
        // The suffix is the LAST "@", and only when a network answers to it:
        // a recipient may be written "@zac.zk.money".
        var draft = given
        if let at = given.lastIndex(of: "@"),
           let named = Op.networks.first(where: { $0.name.lowercased() == given[given.index(after: at)...].lowercased() }) {
            draft = String(given[..<at])
            switchNetwork(named)
        }
        let lines = draft.split(separator: ";").map { $0.split(separator: "|").map(String.init) }
        networkPicked = true
        Task { @MainActor in
            for _ in 0..<50 where held.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
            for (n, parts) in lines.enumerated() {
                if parts.count > 2, let h = held.first(where: { $0.token.symbol == parts[2] }) { with = h }
                if with == nil { with = held.first }
                amount = parts.first ?? ""
                inDollars = false
                to = parts.count > 1 ? parts[1] : ""
                // Filled, so the list the first open raised steps aside.
                open = nil
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
/// is `MoveSentence.rung` (`heading34` since §1679). A clause that fits the line it would start keeps to it;
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

/// **EVERY MOVE FOOT CLEARS THE TAB BAR (prd §1731).** The phone's bar
/// floats over the page's bottom edge and reserves nothing, so a foot clears
/// it by the bar's own geometry; a keyboard covers the bar (prd §865), and
/// the foot rides on the keys. One modifier for the sentence's foot, Create's
/// and the keys walk's: the last two had a plain `s2` and stood under the bar.
struct MoveFootClearance: ViewModifier {
    let inTray: Bool
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content.padding(.bottom, clearance)
    }

    private var clearance: CGFloat {
        guard !inTray, sizeClass == .compact, !chrome.keyboardUp else { return DS.Space.s2 }
        return DSDock.agentSize(fold: chrome.fold) + DSDock.agentBottomInset(fold: chrome.fold) + DS.Space.s2
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
    var glueInk: Color = MoveSentence.glueInk
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

/// A clause whose value is words, laid out WORD BY WORD beside its glue:
/// one wider than the line wraps at the margin, never under its own first
/// word (user, on "to your private / ␣balance": "if it wraps it should be
/// smart enough to know a space isn't needed"). A nested phrase wrapped
/// inside itself, so its second line kept the glue's indent. With `action`,
/// every word is the one control, VoiceOver reading it once.
struct MoveWordsClause: View {
    var glue: String? = nil
    var glueInk: Color = MoveSentence.glueInk
    let words: String
    var ink: Color = DS.textPrimary
    var action: (() -> Void)? = nil
    var hint: Text? = nil
    @Environment(\.moveRung) private var rung
    var body: some View {
        let list = words.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        MoveClauseLayout(spacing: rung.size * MoveSentence.wordSpace) {
            if let glue { MoveWord(glue, ink: glueInk) }
            ForEach(Array(list.enumerated()), id: \.offset) { i, word in
                if let action {
                    Button(action: action) { MoveWord(word, ink: ink) }
                        .buttonStyle(RowPress())
                        .accessibilityLabel(Text(verbatim: words))
                        .accessibilityHint(hint ?? Text(verbatim: ""))
                        .accessibilityHidden(i > 0)
                } else {
                    MoveWord(word, ink: ink).accessibilityHidden(i > 0)
                        .accessibilityLabel(Text(verbatim: words))
                }
            }
        }
    }
}

/// A phrase as clauses: split at its commas (each kept on its piece), an
/// "and" or "or" riding the piece after it, so a line never ends on one.
struct MovePhrase: View {
    let text: String
    var glue: String? = nil
    var glueInk: Color = MoveSentence.glueInk
    var ink: Color = DS.textPrimary
    /// Starts a new line: a second sentence's first piece (prd §1494).
    var breaks = false
    init(_ text: String, glue: String? = nil, glueInk: Color = MoveSentence.glueInk, ink: Color = DS.textPrimary,
         breaks: Bool = false) {
        self.text = text; self.glue = glue; self.glueInk = glueInk; self.ink = ink; self.breaks = breaks
    }
    var body: some View {
        let pieces = Self.pieces(text)
        ForEach(Array(pieces.enumerated()), id: \.offset) { i, piece in
            MoveWordsClause(glue: i == 0 ? (glue ?? piece.glue) : piece.glue, glueInk: i == 0 ? glueInk : ink,
                            words: piece.words, ink: ink)
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

/// **THE WHOLE ADDRESS, READABLE (prd §1586):** "0x" apart, eight groups of
/// five in two rows of four, the first and last bright. Receive's sentence
/// and Your account's box draw it; anything not an EVM address is one line.
struct AddressGroupsGrid: View {
    let address: String

    var body: some View {
        let groups = MoveSentence.addressGroups(address)
        if groups.count == 8 {
            Grid(alignment: .leading, horizontalSpacing: DS.Space.s3, verticalSpacing: DS.Space.s1) {
                ForEach(0..<2, id: \.self) { row in
                    GridRow {
                        Text(verbatim: row == 0 ? "0x" : "").foregroundStyle(DS.textSecondary)
                        ForEach(0..<4, id: \.self) { col in
                            let n = row * 4 + col
                            Text(verbatim: groups[n]).foregroundStyle(n == 0 || n == 7 ? DS.textPrimary : DS.textSecondary)
                        }
                    }
                }
            }
            .dsText(.mono17)
        } else {
            Text(verbatim: address).dsText(.mono17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A word of Move's sentence that can change (prd §1781): which list it
/// opens, which word names its row, what it reads now, and whether it is
/// still to be filled.
struct MoveSentenceBlank: Equatable {
    let opens: MoveSentence.Blank
    let names: MoveSentence.Blank
    let text: String
    let empty: Bool
}

/// Every changing word of the sentence on screen, in the order it is read.
struct MoveSentenceBlanksKey: PreferenceKey {
    static let defaultValue: [MoveSentenceBlank] = []
    static func reduce(value: inout [MoveSentenceBlank], nextValue: () -> [MoveSentenceBlank]) {
        value += nextValue()
    }
}
