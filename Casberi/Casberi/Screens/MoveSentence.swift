import SwiftUI
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
/// the sentence — what you hold, Relay's list, your addresses — and typing only
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

    /// The account was just made, or just brought to this phone (§1442j):
    /// the sentence opens on Receive and finishes itself, "Your account"
    /// turning into "Created …3416" (or "Ready …3416"), the verbs arriving.
    enum Arrival { case created, broughtHere }
    var arrival: Arrival?

    init(account: String, inTray: Bool = false, arrival: Arrival? = nil) {
        self.account = account
        self.inTray = inTray
        self.arrival = arrival
        _verb = State(initialValue: arrival == nil ? .swap : .receive)
        _fresh = State(initialValue: arrival != nil)
    }

    /// What was chosen at Create, named, and when it turns on (user: "it's
    /// not clear what 'your keys go on with your first send' means").
    private var keysWaiting: String? {
        guard let choice = YourAccountSetup.choice(for: account) else { return nil }
        var named: [String] = []
        if choice.recovery { named.append(String(localized: "recovery key")) }
        if choice.signer != nil { named.append(String(localized: "Signer")) }
        if choice.limit != nil { named.append(String(localized: "spend limit")) }
        guard !named.isEmpty else { return nil }
        return String(localized: "Your first send activates your \(named.formatted(.list(type: .and))).")
    }

    /// Still the arrival's sentence: until a verb is picked.
    @State private var fresh = false
    /// The beat has played: the past tense is said and the verbs are in.
    @State private var arrived = false
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    typealias Op = YourAccountOp
    typealias Chain = YourAccountChain
    typealias Tokens = YourAccountTokens

    enum Verb: CaseIterable { case swap, send, receive }
    enum Blank: Equatable { case with, buy, to, network, exchange, elsewhere }
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
    /// The networks this phone can use the account on (§1442k); nil until
    /// read, and every network on the phone that made the account.
    @State private var reach: [Op.Network]?
    /// Relay's list for each network, read at once.
    @State private var listedBy: [Int: [Tokens.Listed]] = [:]
    /// Relay's matches for what is typed in For (prd §1440), per network:
    /// every network until one is picked (§1442a).
    @State private var found: [Int: [Tokens.Listed]] = [:]
    @State private var with: Tokens.Held?
    @State private var buy: Tokens.Listed?
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
    /// Whose words `quoteNote` is ("Relay"), drawn as its mark (§1442n).
    @State private var quoteFrom: String?
    @State private var stage: Chain.Stage?
    /// What a signed transaction became, said in the sentence's place (§1438b).
    @State private var receipt: Receipt?
    /// Receiving from another network (prd §1453): the route picked, the
    /// networks Relay takes deposits on, and which token.
    @State private var elsewhere: YourAccountElsewhere.Route?
    @State private var elsewhereNetworks: [YourAccountElsewhere.Network] = []
    @State private var elsewhereFinding: String?
    /// What the sentence says back for a moment — what is missing, what
    /// failed — in its own line, because a toast draws under the tray
    /// (§1442c). Cleared after a few seconds, or by the next one.
    struct Hint: Equatable { let text: String; let failure: Bool; var from: String? = nil; let id = UUID() }
    @State private var hint: Hint?

    private func say(_ text: String, failure: Bool = false, seconds: Double = 3, from: String? = nil) {
        let h = Hint(text: text, failure: failure, from: from)
        withAnimation(DS.Motion.standard) { hint = h }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if hint?.id == h.id { withAnimation(DS.Motion.standard) { hint = nil } }
        }
    }

    /// A service's mark, in place of its name before its own words (§1442n):
    /// Relay's star on its white circle, as the swap credit draws it.
    @ViewBuilder static func mark(of service: String) -> some View {
        if service == "Relay" {
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
        struct Line: Equatable { var glue: String?; var text: String }
        let past: String
        let lines: [Line]
        let detail: String
        var link: URL? = nil
        var linkName: String? = nil
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

    /// Read, and nothing anywhere: there is nothing to spend yet.
    private var emptyEverywhere: Bool {
        !heldBy.isEmpty && heldBy.values.allSatisfy(\.isEmpty)
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

    private var pendingItem: Chain.Item? {
        guard let with, let units, units != "0", !over else { return nil }
        switch verb {
        case .swap:
            guard let buy, let quote, lockedBuy.map({ $0 == buy.token }) ?? true else { return nil }
            return .swap(Chain.Swap(network: network, sell: with.token, buy: buy.token, amount: units, quote: quote))
        case .send:
            guard let r = resolved, r.imitates == nil, stands(r) else { return nil }
            return .send(Op.Payment(network: network, token: with.token, amount: units, to: r.address, toName: r.name))
        case .receive:
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
        guard verb == .send, setting.on, !network.isTest else { return nil }
        let dollar = Op.dollar(on: network)
        let sent = all.compactMap { item -> String? in
            if case .send(let p) = item, p.token == dollar { return p.amount }
            return nil
        }.reduce("0") { Op.sum($0, $1) }
        guard sent != "0" else { return nil }
        return RoundUps.plan(dollarSent: sent, saved: RoundUps.saved(on: network.chainId), step: setting.step)
    }

    /// The small print's word on round-ups: what is counted, or that this
    /// send buys with it.
    private var roundUpPrint: [String] {
        guard let plan = roundUpPlan else { return [] }
        let target = RoundUps.setting.target
        if let buy = plan.buy {
            let usd = Op.dollars(buy, decimals: RoundUps.dollarDecimals, price: 1)
            return [String(localized: "\(Self.money(usd)) of round-ups buys \(target.symbol) on \(target.network)")]
        }
        let usd = Op.dollars(plan.savedAfter, decimals: RoundUps.dollarDecimals, price: 1)
        return [String(localized: "\(Self.money(usd)) of round-ups so far, \(target.symbol) bought at $5")]
    }

    // MARK: - The page

    var body: some View {
        // The sentence stands at the top and never moves: a blank's choices
        // open under it, down toward the foot (§1442b, user: "it can't extend
        // up and then extend down ... this is just too jittery").
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        sentence
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sentenceHeight = $0 }
                    space(room: geo.size.height)
                        .padding(.top, open == nil ? DS.Space.s6 : DS.Space.s4)
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
        .safeAreaInset(edge: .bottom, spacing: 0) { if open == nil { foot.transition(.opacity) } }
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
        .onChange(of: verb) { _, _ in
            if fresh { withAnimation(DS.Motion.standard) { fresh = false; arrived = true } }
        }
        .task(id: quoteKey) { await requote() }
        .task(id: to) { await resolve() }
        .task {
            await readAll()
            #if DEBUG
            draft()
            #endif
            // No keyboard on its own: Move is a page, and a keyboard raised
            // on arrival covers the tab bar until it is swiped away (user,
            // 2026-10-19). A tap on the amount, or a token picked, raises it.
        }
    }

    // MARK: - The sentence

    /// **E (§1442f, user: "it still looks kinda ghetto ... how would you
    /// improve it"; "build E").** Three sizes: the values large, the verbs
    /// and the small words `heading17`, the small print `body17`. The small
    /// words stand in a gutter, so every value starts on one edge.
    static let gutter: CGFloat = 40

    /// One line of the sentence: its small word in the gutter, its value
    /// after it. A kept transaction numbers the line it is filling instead.
    private func row<Value: View>(_ glue: String?, ink: Color = DS.textPrimary,
                                  @ViewBuilder _ value: () -> Value) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Text(verbatim: glue ?? " ")
                .dsText(.heading17)
                .foregroundStyle(ink)
                .frame(width: Self.gutter, alignment: .leading)
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
            // What Add kept stands under the verbs, numbered, quieter than the
            // sentence being filled (§1442c, §1442f).
            if receipt == nil, !keptLines.filter(showsKept).isEmpty {
                kept
                    .padding(.bottom, DS.Space.s4)
            }
            if let receipt {
                receiptLines(receipt)
            } else if emptyEverywhere, verb != .receive {
                row(nil) {
                    FlowLayout(spacing: 7, lineSpacing: 0) {
                        ForEach(Array((verb == .swap ? String(localized: "Nothing to swap yet.") : String(localized: "Nothing to send yet."))
                            .split(separator: " ").enumerated()), id: \.offset) { _, w in
                            word(String(w), ink: DS.textSecondary)
                        }
                    }
                }
            } else {
            switch verb {
            case .swap:
                // **A RECEIPT (§1442g, user: "lets move to swapping multiple
                // tokens"; "build it").** What you sell is a list, one line a
                // token, each with its dollars at the end; what you get is
                // said once, with the sum. No "and": a stack already says it.
                ForEach(sellOrder, id: \.self) { line in
                    switch line {
                    case .kept(let id): keptSellRow(id)
                    case .current: currentSellRows
                    }
                }
                row(String(localized: "for")) {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                        FlowLayout(spacing: 7, lineSpacing: 0) { buyWord }
                        Spacer(minLength: 0)
                        if !keptSwaps.isEmpty, let total = soldDollarsTotal {
                            Text(verbatim: Self.money(total))
                                .dsText(.body17).foregroundStyle(DS.textPrimary).monospacedDigit()
                        }
                    }
                }
                row(String(localized: "on")) { FlowLayout(spacing: 7, lineSpacing: 0) { networkWord } }
            case .send:
                // **THE SAME RECEIPT, GROUPED BY WHO IT GOES TO (§1442h, user:
                // "send more than one token to a recipient"; "send multiple
                // tokens to multiple recipients").** Each person's tokens,
                // then "to <them>"; a little air between people.
                let groups = sendGroups
                ForEach(Array(groups.enumerated()), id: \.element.id) { n, group in
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        ForEach(group.lines, id: \.self) { line in
                            switch line {
                            case .kept(let id): keptSellRow(id)
                            case .current: currentSellRows
                            }
                        }
                        row(String(localized: "to")) {
                            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                                if group.hasCurrent {
                                    toWord
                                } else {
                                    word(group.name ?? "", ink: DS.pickInk)
                                }
                                Spacer(minLength: 0)
                                // One person and two lines: the sum is theirs.
                                if groups.count == 1, group.lines.count > 1, let sum = dollars(of: group) {
                                    Text(verbatim: Self.money(sum))
                                        .dsText(.body17).foregroundStyle(DS.textPrimary).monospacedDigit()
                                }
                            }
                        }
                    }
                    .padding(.top, n == 0 ? 0 : DS.Space.s3)
                }
                row(String(localized: "on")) {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                        FlowLayout(spacing: 7, lineSpacing: 0) { networkWord }
                        Spacer(minLength: 0)
                        // Several people: the whole send's total closes it.
                        if groups.count > 1, let total = soldDollarsTotal {
                            Text(verbatim: Self.money(total))
                                .dsText(.body17).foregroundStyle(DS.textPrimary).monospacedDigit()
                        }
                    }
                }
                .padding(.top, groups.count > 1 ? DS.Space.s3 : 0)
                // Round-ups (prd §1452): the change, then what the whole send
                // comes to with it (user: "needs to be clear that the 5$ is
                // the total tx").
                if let plan = roundUpPlan, plan.change != "0" {
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
            case .receive where fresh:
                row(nil) {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                        word(arrived ? (arrival == .broughtHere ? String(localized: "Ready") : String(localized: "Created"))
                                     : String(localized: "Your account"),
                             ink: arrived ? DS.textSecondary : DS.textPrimary)
                        if arrived {
                            Button { copy() } label: { word(YourAccount.short(account), ink: DS.pickInk) }
                                .buttonStyle(RowPress())
                                .accessibilityLabel(Text("Your address, \(account)"))
                                .accessibilityHint(Text("Copies your address"))
                                .transition(.asymmetric(insertion: .offset(y: 28).combined(with: .opacity), removal: .opacity))
                        }
                    }
                }
                row(String(localized: "on")) {
                    receiveNetworks
                }
            case .receive:
                if let route = elsewhere {
                    // **FROM ANOTHER NETWORK (prd §1453, user: "for z1 we
                    // wouldn't say 'send' we would say 'receive'").**
                    // The tab says Receive, as Send's amount stands with no
                    // word before it: the token leads.
                    row(nil) {
                        Button { switchElsewhereToken() } label: { word(route.token, ink: DS.pickInk) }
                            .buttonStyle(RowPress())
                            .accessibilityHint(Text("Switches between USDC and ETH"))
                    }
                    // Where the sender's money is (user: "'on' arbitrum would
                    // be better").
                    row(String(localized: "on")) {
                        Button {
                            withAnimation(DS.Motion.standard) { open = .elsewhere }
                            DSHaptic.selection()
                        } label: { word(route.from.name, ink: DS.pickInk) }
                            .buttonStyle(RowPress())
                    }
                    row(String(localized: "as")) {
                        word(String(localized: "\(route.arrives) on \(route.to.name)."), ink: DS.textPrimary)
                    }
                } else {
                    row(String(localized: "at")) {
                        Button { copy() } label: { word(YourAccount.short(account), ink: DS.pickInk) }
                            .buttonStyle(RowPress())
                            .accessibilityLabel(Text("Your address, \(account)"))
                            .accessibilityHint(Text("Copies your address"))
                    }
                    row(String(localized: "on")) {
                        // A line of words, so it wraps between them.
                        receiveNetworks
                    }
                }
            }
            }
        }
        .animation(DS.Motion.standard, value: verb)
        .animation(DS.Motion.standard, value: receipt)
    }

    /// "Swapped 0.004 USDC / for 12.3 AERO / on Base." — the verb rolls to the
    /// past, the ≈ resolves to what was paid out.
    /// The receipt in the sentence's own grammar (§1442l): its small words
    /// in the gutter, the past tense leading the first line.
    private func receiptLines(_ r: Receipt) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            ForEach(Array(r.lines.enumerated()), id: \.offset) { n, line in
                row(line.glue) {
                    FlowLayout(spacing: 7, lineSpacing: 0) {
                        if n == 0 { word(r.past, ink: DS.textSecondary) }
                        ForEach(Array(line.text.split(separator: " ").enumerated()), id: \.offset) { _, w in
                            word(String(w), ink: DS.textPrimary)
                        }
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .offset(y: 8)))
    }

    /// The sentence is the verbs' size (§1442c, user: "simpler", "less
    /// overwhelming").
    static let size: DSTextStyle = .heading28

    private func word(_ text: String, ink: Color) -> some View {
        Text(verbatim: text)
            .dsText(Self.size)
            .foregroundStyle(ink)
            // Digits roll as a figure changes: the quote landing, a slider
            // drag — tabular, so the line holds still while they do.
            .monospacedDigit()
            .contentTransition(.numericText())
            .fixedSize()
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

    /// Where this phone can receive (§1442k): only the networks it can use
    /// the account on, a line of words so it wraps between them.
    @ViewBuilder private var receiveNetworks: some View {
        if let reach {
            FlowLayout(spacing: 7, lineSpacing: 0) {
                ForEach(Array(YourAccountReach.words(reach).split(separator: " ").enumerated()), id: \.offset) { _, w in
                    word(String(w), ink: DS.textPrimary)
                }
            }
        } else {
            word("…", ink: DS.textTertiary)
        }
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
        case .receive: true
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

    /// Every swap's fee, in dollars where the sold token is priced.
    private var feeTotal: String? {
        var usd = keptSwaps.compactMap { s in price(of: s.sell).map { Op.dollars(s.quote.fee, decimals: s.sell.decimals, price: $0) } }.reduce(0, +)
        if let with, let quote, let p = with.price { usd += Op.dollars(quote.fee, decimals: with.token.decimals, price: p) }
        guard !keptSwaps.isEmpty || quote != nil else { return nil }
        return usd < 0.01 ? String(localized: "Fee under a cent") : String(localized: "Fee \(Self.money(usd))")
    }

    /// The amount, its token beside it in its own units, and what it is
    /// worth at the trailing end.
    private func amountLine(trailing: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if inDollars { word("$", ink: amount.isEmpty ? DS.textTertiary : DS.pickInk) }
            amountField
            if !inDollars {
                withWord.padding(.leading, 8)
            }
            Spacer(minLength: DS.Space.s2)
            if let trailing {
                Text(verbatim: trailing)
                    .dsText(.body17).foregroundStyle(DS.textSecondary).monospacedDigit()
            }
        }
    }

    /// The line being filled: the amount, then in dollars "of <token>".
    @ViewBuilder private var currentSellRows: some View {
        row(nil) {
            amountLine(trailing: with.flatMap { units == nil ? nil : otherUnit($0) })
        }
        .contentShape(Rectangle())
        .onTapGesture { if stage == nil { focus = .amount } }
        .dsCardLead(Text("Edits the amount")) { if stage == nil { focus = .amount } }
        if inDollars {
            row(String(localized: "of")) { withWord }
        }
    }

    /// A kept line: tap it to edit it in place, hold it to remove it.
    @ViewBuilder private func keptSellRow(_ id: UUID) -> some View {
        let line: (amount: String, token: Op.Token, usd: Double?)? = {
            if let s = keptSwaps.first(where: { $0.id == id }) { return (s.amount, s.sell, soldDollars(s)) }
            if let p = keptSends.first(where: { $0.id == id }) { return (p.amount, p.token, sentDollars(p)) }
            return nil
        }()
        if let s = line {
            row(nil) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    word(Self.figure(s.amount, decimals: s.token.decimals) + " " + s.token.symbol, ink: DS.pickInk)
                    Spacer(minLength: 0)
                    if let d = s.usd {
                        Text(verbatim: Self.money(d))
                            .dsText(.body17).foregroundStyle(DS.textSecondary).monospacedDigit()
                    }
                }
            }
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
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
            ForEach(Verb.allCases, id: \.self) { v in
                Button {
                    guard v != verb || receipt != nil else { return }
                    withAnimation(DS.Motion.standard) {
                        verb = v
                        open = nil
                        receipt = nil
                    }
                    DSHaptic.selection()
                } label: {
                    Text(verbatim: title(v))
                        .dsText(.heading17)
                        .foregroundStyle(v == verb ? DS.textPrimary
                                         : v == .receive && emptyEverywhere ? DS.pickInk : DS.textTertiary)
                }
                .buttonStyle(RowPress())
                .disabled(stage != nil)
                .accessibilityAddTraits(v == verb ? [.isSelected] : [])
            }
        }
        .frame(minHeight: 44, alignment: .leading)
    }

    private func title(_ v: Verb) -> String {
        switch v {
        case .swap: String(localized: "Swap")
        case .send: String(localized: "Send")
        case .receive: String(localized: "Receive")
        }
    }

    private var amountField: some View {
        let typing = focus == .amount
        return TextField(text: $amount, prompt: Text(verbatim: "0").foregroundStyle(DS.textTertiary)) { Text(verbatim: "0") }
            .keyboardType(.decimalPad)
            .focused($focus, equals: .amount)
            .dsText(Self.size)
            // Not typing, the figure is drawn over the field so its digits
            // roll as the slider moves (§1438b); the field still takes the tap.
            .foregroundStyle(typing || amount.isEmpty ? DS.pickInk : .clear)
            .overlay(alignment: .leading) {
                if !typing, !amount.isEmpty {
                    Text(verbatim: amount)
                        .dsText(Self.size)
                        .foregroundStyle(DS.pickInk)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .fixedSize()
                        .allowsHitTesting(false)
                }
            }
            .fixedSize()
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
            let back = buyTotal.map { "≈ " + Self.figure($0, decimals: buy.token.decimals) + " " }
            // The whole swap's result, pink like every value; locked by a
            // kept swap (§1442c), a tap says so (§1442g).
            let word = blank((back ?? "") + buy.token.symbol, ink: DS.pickInk,
                             .buy, label: Text("For \(buy.token.symbol), change"))
            if pricing {
                // While Relay prices it, the word breathes: working, not stuck.
                word.phaseAnimator([1.0, 0.4]) { content, phase in content.opacity(phase) } animation: { _ in .easeInOut(duration: 0.9) }
            } else {
                word
            }
        } else {
            blank(String(localized: "token"), ink: DS.textTertiary, .buy, label: Text("Pick what you want"))
        }
    }

    /// A swap is being priced: everything is there but Relay's answer.
    private var pricing: Bool {
        verb == .swap && buy != nil && units != nil && !over && quote == nil && quoteNote == nil
    }

    private var toWord: some View {
        let shown = resolved?.name ?? (resolved.map { YourAccount.short($0.address) })
            ?? (to.isEmpty ? String(localized: "address") : to)
        return blank(shown, ink: resolved?.imitates != nil ? DS.attentionInk : resolved == nil ? DS.textTertiary : DS.pickInk,
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
            if networkPicked {
                blank(network.name + ".", ink: DS.pickInk, .network, label: Text("On \(network.name), change"))
            } else {
                blank(String(localized: "network."), ink: DS.textTertiary, .network, label: Text("Pick a network"))
            }
        }
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
                    .onSubmit { if resolved != nil, resolved?.imitates == nil { pick {} } }
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
            } else {
                TextField(String(localized: "Search"), text: $search)
                    .focused($focus, equals: .search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .task(id: search) { await lookUpPasted() }
            }
        }
        .frame(minHeight: 52)
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
                choices(room: choicesRoom(room), searches: open == .with || open == .buy || open == .to, which: open) {
                    ZStack(alignment: .topLeading) {
                        Group {
                            switch open {
                            case .with: withList
                            case .buy: buyList
                            case .to: toList
                            case .network: networkList
                            case .exchange: exchangeList
                            case .elsewhere: elsewhereList
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
                    .padding(.leading, Self.gutter + DS.Space.s2)
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
                        Text("View on \(name)").dsText(.body17).foregroundStyle(DS.pickInk).frame(minHeight: 44)
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
        } else if verb == .receive {
            // **RECEIVE (§1442i, user: "when we show 'at' show …xxxx or complete
            // address. and somewhere on the page complete address should be
            // displayed. also with a copy button").** The sentence says
            // "…9f12"; the whole address stands here, readable, with its own
            // copy; the exchange door is a line, and opens a list like
            // every blank's (the system menu was the one control on Move that
            // matched nothing else).
            if let route = elsewhere {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    Text(verbatim: route.address)
                        .dsText(.mono12)
                        .foregroundStyle(DS.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    DSCopyRow(value: route.address, label: "Copy address", sensitive: false)
                    Text(route.feeUSD.map { fee in
                        String(localized: "Only \(route.token) on \(route.from.name) here. Relay brings it to your account in seconds, for about \(Self.money(max(fee, 0.01))).")
                    } ?? String(localized: "Only \(route.token) on \(route.from.name) here. Relay brings it to your account in seconds."))
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        withAnimation(DS.Motion.standard) { elsewhere = nil }
                        DSHaptic.selection()
                    } label: {
                        Text("Your own address")
                            .dsText(.body17)
                            .foregroundStyle(DS.pickInk)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(RowPress())
                }
            } else {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text(verbatim: account)
                    .dsText(.mono12)
                    .foregroundStyle(DS.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                DSCopyRow(value: account, label: "Copy address", sensitive: false)
                // Never an address the account cannot follow (§1442k).
                if let reach, !YourAccountReach.isAll(reach) {
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
                // The keys chosen right after Create (prd §1457, §1460): the
                // one line that stands for a summary.
                if fresh, arrived, arrival == .created, let keysWaiting {
                    Text(verbatim: keysWaiting)
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
                Button {
                    withAnimation(DS.Motion.standard) { open = .exchange }
                    DSHaptic.selection()
                } label: {
                    Text("From an exchange")
                        .dsText(.body17)
                        .foregroundStyle(DS.pickInk)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(RowPress())
                if !network.isTest {
                    Button {
                        withAnimation(DS.Motion.standard) { open = .elsewhere }
                        DSHaptic.selection()
                    } label: {
                        Text("From another network")
                            .dsText(.body17)
                            .foregroundStyle(DS.pickInk)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(RowPress())
                }
                if let elsewhereFinding {
                    Text(verbatim: elsewhereFinding).dsText(.body17).foregroundStyle(DS.attentionInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            }
        } else if let note = lineNote {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                if note == quoteNote, let quoteFrom { Self.mark(of: quoteFrom) }
                Text(verbatim: note).dsText(.body17).foregroundStyle(DS.attentionInk)
            }
        } else if let with {
            // One line of small print (§1442f): the other unit and the fee.
            // Relay's credit is the foot's, and the slider, the amount's own
            // control, stands under it here rather than stranded at the foot.
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                // Swapping, the other unit is the receipt's column; the fee is
                // the whole swap's (§1442g).
                let print: [String] = switch verb {
                case .swap: [feeTotal].compactMap { $0 }
                case .send: (peopleCount > 1 ? [String(localized: "To \(peopleCount) people")] : []) + roundUpPrint
                case .receive: []
                }
                if !print.isEmpty {
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
                        DSShareSlider(percent: shareBinding(with), enabled: stage == nil, tint: DS.textPrimary)
                        unitSwitch
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        } else if !networkPicked {
            EmptyView()
        } else if heldBy.isEmpty {
            Text("Reading…").dsText(.body17).foregroundStyle(DS.textSecondary)
        } else if held.isEmpty {
            Text("Nothing on \(network.name) yet").dsText(.body17).foregroundStyle(DS.textSecondary)
        }
    }

    private var lineNote: String? {
        if verb != .receive, over { return String(localized: "More than you have") }
        if verb == .swap, let quoteNote { return quoteNote }
        if verb == .send {
            if malformed { return String(localized: "Check the address") }
            if let imitates = resolved?.imitates { return String(localized: "Looks like \(imitates)'s — check it") }
        }
        return nil
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

    /// A swap's fee; under a cent it says so rather than a string of zeros.
    private func feeLine(_ h: Tokens.Held) -> String? {
        guard verb == .swap, let quote else { return nil }
        if let price = h.price {
            let usd = Op.dollars(quote.fee, decimals: h.token.decimals, price: price)
            return usd < 0.01 ? String(localized: "Fee under a cent") : String(localized: "Fee \(Self.money(usd))")
        }
        return String(localized: "Fee ≈ \(Self.figure(quote.fee, decimals: h.token.decimals)) \(h.token.symbol)")
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
                         mark: String? = nil, image: String? = nil, dim: Bool = false,
                         act: @escaping () -> Void) -> some View {
        Button(action: act) {
            HStack(spacing: DS.Space.s3) {
                if let image {
                    Image(image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: DS.Face.list, height: DS.Face.list)
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                } else if let mark {
                    AssetMark(name: mark, size: DS.Face.list)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: title).dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(1)
                    if let sub { Text(verbatim: sub).dsText(.subhead12).foregroundStyle(DS.textSecondary).lineLimit(1) }
                }
                Spacer(minLength: DS.Space.s2)
                if let trailing {
                    Text(verbatim: trailing).dsText(.body17).foregroundStyle(DS.textSecondary).monospacedDigit()
                }
            }
            .frame(minHeight: 56)
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
                     : networkPicked ? String(localized: "Nothing on \(network.name) yet")
                     : String(localized: "Nothing to spend yet"))
                    .dsText(.body17).foregroundStyle(DS.textSecondary).frame(minHeight: 44)
            }
        }
    }

    /// What For offers, on the picked network or on each, a network's head
    /// of five when none is picked and nothing is typed.
    private var buyRows: [(key: String, net: Op.Network, listed: Tokens.Listed)] {
        let typed = !search.trimmingCharacters(in: .whitespaces).isEmpty
        var out: [(key: String, net: Op.Network, listed: Tokens.Listed)] = []
        var seen: Set<String> = []
        for n in lookIn {
            let pool = (typed ? (found[n.chainId] ?? []) : []) + (listedBy[n.chainId] ?? [])
            var rows = Tokens.matches(search, in: pool, held: heldBy[n.chainId] ?? [])
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
                let about = l.onList ? (l.name == l.token.symbol ? nil : l.name) : String(localized: "Not verified by Relay")
                listRow(l.token.symbol,
                        sub: networkPicked ? about : [about, row.net.name].compactMap { $0 }.joined(separator: " · "),
                        trailing: mine.map { Op.spoken($0.units, decimals: $0.token.decimals) },
                        mark: l.token.symbol, dim: !l.onList) {
                    pick {
                        if !networkPicked || row.net != network { switchNetwork(row.net) }
                        buy = l
                    }
                    if amount.isEmpty { focus = .amount }
                }
            }
            if networkPicked, !YourAccountSwap.supported(network) {
                Text("Swaps are not on \(network.name)").dsText(.body17).foregroundStyle(DS.textSecondary).frame(minHeight: 44)
            }
            pasteRow { search = $0 }
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
            if let above, q.isEmpty {
                listRow(above.toName ?? YourAccount.short(above.to), sub: String(localized: "Same as above"),
                        mark: above.toName ?? "") {
                    to = above.toName ?? above.to
                    resolved = Recipient(address: above.to, name: above.toName, imitates: nil)
                    pick {}
                }
            }
            if let r = resolved, r.imitates == nil, !book.contains(where: { WalletWatch.sameAddress($0.address, r.address) }) {
                listRow(r.name ?? YourAccount.short(r.address), sub: r.name == nil ? nil : YourAccount.short(r.address)) {
                    pick {}
                }
            }
            ForEach(Array(book.filter { e in above.map { !(q.isEmpty && WalletWatch.sameAddress($0.to, e.address)) } ?? true }.prefix(20)), id: \.address) { e in
                listRow(e.name, sub: YourAccount.short(e.address), mark: e.name) {
                    to = e.name
                    resolved = Recipient(address: EIP55.checksum(e.address), name: e.name, imitates: nil)
                    pick {}
                }
            }
            pasteRow { to = $0 }
        }
    }

    /// Where the money comes from (§1442i): each row says what it does.
    /// Coinbase and any other wallet; not a directory of every exchange
    /// the app reads (user: "just use coinbase and another wallet").
    private var exchangeList: some View {
        VStack(alignment: .leading, spacing: 0) {
            listRow("Coinbase", sub: String(localized: "Copies your address, opens Coinbase"), image: "brand-coinbase") {
                pick {}
                addFrom("https://www.coinbase.com")
            }
            listRow(String(localized: "Another wallet"), sub: String(localized: "Copies your address"), mark: "W") {
                pick {}
                copy()
            }
        }
    }

    /// Where the money is (prd §1453): the account's own networks take your
    /// own address; every other network Relay takes deposits on goes
    /// through Relay, to your account on this network.
    private var elsewhereList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(networksByWorth) { n in
                listRow(n.name, sub: String(localized: "your own address"), image: Self.networkMark(n)) {
                    pick { elsewhere = nil }
                }
            }
            ForEach(elsewhereNetworks) { n in
                listRow(n.name, sub: String(localized: "through Relay"), mark: String(n.name.prefix(1))) {
                    pick {}
                    takeRoute(from: n, token: elsewhere?.token == "ETH" && n.ethNative ? "ETH" : (n.usdc != nil ? "USDC" : "ETH"))
                }
            }
            if elsewhereNetworks.isEmpty {
                HStack(spacing: DS.Space.s2) {
                    DSSpinner()
                    Text("Asking Relay").dsText(.body17).foregroundStyle(DS.textSecondary)
                }
                .frame(minHeight: 52)
            }
        }
        .task { if elsewhereNetworks.isEmpty { elsewhereNetworks = await YourAccountElsewhere.networks() } }
    }

    /// Relay's address for the route, kept per route; on the network Receive
    /// stands on, Base when that is a test network.
    private func takeRoute(from: YourAccountElsewhere.Network, token: String) {
        let to = network.isTest ? Op.base : network
        let who = account
        elsewhereFinding = nil
        Task {
            do {
                let route = try await YourAccountElsewhere.route(from: from, token: token, to: to, account: who)
                withAnimation(DS.Motion.standard) { elsewhere = route }
                DSHaptic.tap()
            } catch let failure as Chain.Failure {
                elsewhereFinding = failure.message
            } catch {
                elsewhereFinding = String(localized: "Relay did not answer")
            }
        }
    }

    /// USDC or ETH, where the route's network has both.
    private func switchElsewhereToken() {
        guard let route = elsewhere else { return }
        let other = route.token == "USDC" ? "ETH" : "USDC"
        guard other == "USDC" ? route.from.usdc != nil : route.from.ethNative else { return }
        takeRoute(from: route.from, token: other)
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

    /// Each network's own mark, from the brand set the Wallet already draws.
    static func networkMark(_ n: Op.Network) -> String? {
        switch n.chainId {
        case 8453: "brand-l2b-base"
        case 4663: "brand-l2b-robinhood"
        case 1: "brand-eth"
        default: nil
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
        if buy?.token == h.token { buy = nil }
        if amount.isEmpty { focus = .amount }
    }

    private func switchNetwork(_ n: Op.Network) {
        networkPicked = true
        guard n != network else { return }
        network = n
        with = nil
        buy = nil
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
                        Text("Done").dsText(.heading28).foregroundStyle(DS.textSecondary).frame(minHeight: 48, alignment: .trailing)
                    }
                    .buttonStyle(RowPress())
                }
            } else {
            // Add, then the verb (§1442d): the order you use them in, and the
            // act that signs at the trailing edge under the thumb, where iOS
            // puts a screen's main act.
            HStack(alignment: .firstTextBaseline) {
                if verb == .receive {
                    // Copying is beside the address (§1442i); the foot's one
                    // act hands it to someone.
                    Spacer(minLength: 0)
                    ShareLink(item: receiveAddress) {
                        Text("Share")
                            .dsText(.heading28)
                            .foregroundStyle(DS.pickInk)
                            .frame(minHeight: 48, alignment: .trailing)
                    }
                    .buttonStyle(RowPress())
                    .accessibilityHint(Text("Shares your address"))
                } else {
                    Button { add() } label: {
                        // Pink is the values' and the signing verb's alone
                        // (§1442f): Add is white when ready, grey when not.
                        Text("Add")
                            .dsText(.heading17)
                            .foregroundStyle(pendingItem != nil && stage == nil ? DS.textPrimary : DS.textSecondary)
                            .frame(minHeight: 48)
                    }
                    .buttonStyle(RowPress())
                    // Never a dead word: unready, it says what is missing (§1442c).
                    .disabled(stage != nil)
                    .accessibilityHint(Text("Keeps this in the transaction and starts the next one"))
                }
                if verb != .receive {
                    Spacer(minLength: DS.Space.s3)
                    Button { sign() } label: {
                        Text(verbatim: footVerb)
                            .dsText(.heading28)
                            .foregroundStyle(footOn ? DS.pickInk : DS.textTertiary)
                            .frame(minHeight: 48, alignment: .trailing)
                    }
                    .buttonStyle(RowPress())
                    .disabled(!footOn)
                }
            }
            }
            // Relay's credit signs the foot, small and centred, as Apple
            // Pay's does (§1442f): a credit, not a fact about this swap.
            if verb == .swap, receipt == nil {
                HStack(spacing: DS.Space.s1) {
                    Text("Powered by Relay")
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                    Self.mark(of: "Relay")
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

    private var footOn: Bool {
        verb == .receive || (stage == nil && !all.isEmpty)
    }

    private var footVerb: String {
        switch stage {
        case .preparing: return String(localized: "Preparing…")
        case .signing: return String(localized: "Confirm with Face ID")
        case .sending: return String(localized: "Sending…")
        case .landing: return String(localized: "Waiting for \(network.name)…")
        case nil: break
        }
        if verb == .receive { return String(localized: "Copy address") }
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
                    amount = p == 0 ? "" : Op.display(part, decimals: h.token.decimals, places: h.token.decimals)
                }
            })
    }

    // MARK: - Acts

    /// What the sentence still needs before Add can keep it.
    private var missing: String? {
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
            if let imitates = resolved?.imitates { return String(localized: "Looks like \(imitates)'s — check it") }
            if resolved == nil { return String(localized: "Pick who it goes to") }
        case .receive:
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
        withAnimation(DS.Motion.standard) {
            items.insert(item, at: min(slot, items.count))
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

    private func sign() {
        guard stage == nil else { return }
        let batch = all
        guard !batch.isEmpty else { return }
        let reason = faceIDWords(batch)
        let net = network
        let roundUp = roundUpPlan
        let target = RoundUps.setting.target
        stage = .preparing
        Task {
            do {
                let buy = roundUp?.buy.map { Chain.RoundUpBuy(units: $0, target: target) }
                let done = try await Self.spend(batch, on: net, account: account, roundUp: buy, reason: reason,
                                                said: { line in await MainActor.run { say(line) } }) { s in
                    await MainActor.run { stage = s }
                }
                // The change is counted once the send has landed; a buy
                // empties the count with it.
                if let roundUp, case .landed = done.sent.outcome {
                    RoundUps.setSaved(roundUp.savedAfter, on: net.chainId)
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
                    items = []
                    slot = 0
                    amount = ""
                    quote = nil
                    receipt = made
                }
                if case .landed = sent.outcome {
                    DSHaptic.success()
                    chrome.rain(sources: ["Wallet"])
                }
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
                      reason: String, said: @escaping @Sendable (String) async -> Void,
                      stage: @escaping @Sendable (Chain.Stage) async -> Void) async throws -> Chain.Transacted {
        guard case .on = (try? await Chain.limitState(net, account)) ?? .off else {
            return try await Chain.transact(batch, reason: reason, roundUp: roundUp, stage: stage)
        }
        let sends = batch.compactMap { if case .send(let p) = $0 { p } else { nil } }
        if sends.count == batch.count {
            let signed = SignedFlag()
            do {
                let sent = try await Chain.sessionSend(sends, roundUp: roundUp, reason: reason) { s in
                    if s == .signing { await signed.mark() }
                    await stage(s)
                }
                return Chain.Transacted(sent: sent)
            } catch let failure as Chain.Failure {
                guard await !signed.value else { throw failure }
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
                                        roundUp: roundUp, renew: true, stage: stage)
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

        // Swaps, one or several for one (§1442g): each sold line, then what
        // came back — measured when every swap was, else the quotes, ≈.
        if sends.isEmpty, let first = swaps.first, swaps.allSatisfy({ $0.buy == first.buy }) {
            let paid = done.bought.compactMap { $0 }
            let measured = paid.count == swaps.count
            let back = measured ? paid.reduce("0") { Op.sum($0, $1) }
                                : swaps.map(\.quote.buyAmount).reduce("0") { Op.sum($0, $1) }
            let quoted = swaps.map(\.quote.buyAmount).reduce("0") { Op.sum($0, $1) }
            var detail: [String] = []
            // More than quoted is the honest surprise: the route paid more.
            if measured, Op.atMost(quoted, back), back != quoted {
                detail.append(String(localized: "\(Self.figure(Op.difference(back, quoted), decimals: first.buy.decimals)) \(first.buy.symbol) more than quoted"))
            }
            return made(measured ? String(localized: "Swapped") : String(localized: "Swapping"),
                        swaps.map { Line(glue: nil, text: amount($0.amount, $0.sell)) }
                        + [Line(glue: String(localized: "for"), text: (measured ? "" : "≈ ") + amount(back, first.buy)), on],
                        detail)
        }
        // Sends (§1442h): each person's tokens, then "to <them>".
        if swaps.isEmpty, !sends.isEmpty {
            var lines: [Line] = []
            var at = 0
            while at < sends.count {
                let to = sends[at].to
                var end = at
                while end < sends.count, WalletWatch.sameAddress(sends[end].to, to) {
                    lines.append(Line(glue: nil, text: amount(sends[end].amount, sends[end].token)))
                    end += 1
                }
                lines.append(Line(glue: String(localized: "to"), text: sends[at].toName ?? YourAccount.short(to)))
                at = end
            }
            return made(String(localized: "Sent"), lines + [on])
        }
        return made(String(localized: "Signed"), [Line(glue: nil, text: String(localized: "\(batch.count) in one transaction")), on])
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
        UIPasteboard.general.string = receiveAddress
        DSHaptic.tap()
        say(String(localized: "Address copied"))
    }

    /// The address on the clipboard, then the exchange: paste it as the
    /// destination of a withdrawal there, on any network the account is on.
    private func addFrom(_ site: String) {
        copy()
        if let url = URL(string: site) { openURL(url) }
    }

    // MARK: - Reads

    /// Every network's holdings at once; the sentence starts on the one
    /// holding the most, and spends its biggest token.
    private func readAll() async {
        // Every network at once: one slow node holds none of the others.
        var found: [Int: [Tokens.Held]] = [:]
        await withTaskGroup(of: (Int, [Tokens.Held]).self) { group in
            for net in Op.networks {
                group.addTask { @MainActor in (net.chainId, await Tokens.held(account, on: net)) }
            }
            for await (id, held) in group { found[id] = held }
        }
        heldBy = found
        reach = await YourAccountReach.usable(account)
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
    }

    private func readNetwork() async {
        let now = await Tokens.held(account, on: network)
        heldBy[network.chainId] = now
        if let w = with { with = now.first { $0.id == w.id } }
        listedBy[network.chainId] = await Tokens.list(network)
    }

    /// The quote is asked again whenever what would be swapped changes.
    private var quoteKey: String {
        guard verb == .swap, let with, let buy else { return "" }
        return "\(network.chainId)|\(with.id)|\(buy.id)|\(units ?? "")"
    }

    private func requote() async {
        quote = nil
        quoteNote = nil
        quoteFrom = nil
        guard verb == .swap, let with, let buy, YourAccountSwap.supported(network), let units, !over else { return }
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        do {
            let q = try await Chain.swapQuote(network, sell: with.token, buy: buy.token, amount: units, account: account)
            guard !Task.isCancelled else { return }
            withAnimation(DS.Motion.standard) { quote = q }
            #if DEBUG
            draftAddsTheSwap()
            #endif
        } catch let failure as Chain.Failure {
            guard !Task.isCancelled else { return }
            quoteNote = failure.message
            quoteFrom = failure.from
        } catch {}
    }

    /// Relay's matches as you type, after a pause, on every network the list
    /// looks in; a pasted contract is read off each.
    private func lookUpPasted() async {
        pasted = [:]
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard open == .buy, !text.isEmpty else { found = [:]; return }
        try? await Task.sleep(for: .milliseconds(ENS.isHexAddress(text) ? 300 : 250))
        guard !Task.isCancelled else { return }
        let nets = lookIn
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
        guard !Task.isCancelled, nets == lookIn else { return }
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

    // MARK: - DEBUG drafts

    #if DEBUG
    /// `-moveSwapDraft "<amount>|<SELL>[|<BUY>]"` and `-moveSendDraft
    /// "<amount>|<to>"`: the sentence filled, because a `simctl`-booted
    /// simulator drops typed characters (prd §1424, §1438). Both given: the
    /// swap is Added once Relay prices it, and the send fills the next sentence.
    private func draft() {
        let d = UserDefaults.standard
        if let swap = d.string(forKey: "moveSwapDraft"), !swap.isEmpty {
            let parts = swap.split(separator: "|").map(String.init)
            verb = .swap
            networkPicked = true
            if parts.count > 1, let h = held.first(where: { $0.token.symbol == parts[1] }) { with = h }
            let buyName = parts.count > 2 ? parts[2] : (with?.token.symbol == "ETH" ? "USDC" : "ETH")
            buy = listed.first { $0.token.symbol == buyName && $0.onList }
                ?? held.first { $0.token.symbol == buyName }.map { Tokens.Listed(token: $0.token, name: $0.token.symbol, onList: true) }
            amount = parts.first ?? ""
            inDollars = false
            NSLog("moveSwapDraft: %@ %@ for %@", amount, with?.token.symbol ?? "-", buy?.token.symbol ?? "-")
        } else if d.string(forKey: "moveSendDraft")?.isEmpty == false {
            verb = .send
            sendDraft()
        }
    }

    /// Lines are `;`-separated, each `<amount>|<to>[|<SYM>]`; every line but
    /// the last is Added once its recipient resolves.
    private func sendDraft() {
        guard let draft = UserDefaults.standard.string(forKey: "moveSendDraft"), !draft.isEmpty else { return }
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
