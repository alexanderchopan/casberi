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
/// the sentence — what you hold, CoW's list, your addresses — and typing only
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
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass

    typealias Op = YourAccountOp
    typealias Chain = YourAccountChain
    typealias Tokens = YourAccountTokens

    enum Verb: CaseIterable { case swap, send, receive }
    enum Blank: Equatable { case with, buy, to, network }
    enum Field: Hashable { case amount, search, to }

    struct Recipient: Equatable {
        let address: String
        let name: String?
        /// A book entry this raw address imitates (address poisoning).
        let imitates: String?
    }

    @State private var verb: Verb = .swap
    @State private var network: Op.Network = Op.base
    @State private var heldBy: [Int: [Tokens.Held]] = [:]
    @State private var listed: [Tokens.Listed] = []
    @State private var with: Tokens.Held?
    @State private var buy: Tokens.Listed?
    @State private var amount = ""
    @State private var inDollars = false
    @State private var to = ""
    @State private var resolved: Recipient?
    @State private var malformed = false
    @State private var open: Blank?
    @State private var search = ""
    @State private var pasted: Tokens.Listed?
    @State private var items: [Chain.Item] = []
    @State private var quote: YourAccountSwap.Quote?
    @State private var quoteNote: String?
    @State private var stage: Chain.Stage?
    /// What a signed transaction became, said in the sentence's place (§1438b).
    @State private var receipt: Receipt?
    /// Bumped to shake the To word once: an address that imitates a book entry.
    @State private var shake = 0
    @FocusState private var focus: Field?

    /// The sentence in the past tense, and how it went.
    struct Receipt: Equatable {
        let past: String
        let lines: [String]
        let detail: String
        var link: URL? = nil
        var linkName: String? = nil
    }
    #if DEBUG
    @State private var drafted = false
    #endif

    // MARK: - What the sentence says

    private var held: [Tokens.Held] { heldBy[network.chainId] ?? [] }

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

    private var pendingItem: Chain.Item? {
        guard let with, let units else { return nil }
        switch verb {
        case .swap:
            guard let buy, let quote else { return nil }
            return .swap(Chain.Swap(network: network, sell: with.token, buy: buy.token, amount: units, quote: quote))
        case .send:
            guard let r = resolved, r.imitates == nil else { return nil }
            return .send(Op.Payment(network: network, token: with.token, amount: units, to: r.address, toName: r.name))
        case .receive:
            return nil
        }
    }

    private var all: [Chain.Item] { items + (pendingItem.map { [$0] } ?? []) }

    // MARK: - The page

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !items.isEmpty { kept }
                sentence
                    .padding(.top, items.isEmpty ? 0 : DS.Space.s4)
                space
                    .padding(.top, DS.Space.s6)
            }
            .padding(.horizontal, DSRoomChassis.leadInset)
            .padding(.top, DS.Space.s6)
            .padding(.bottom, DS.Space.s8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { foot }
        .task(id: network.chainId) { await readNetwork() }
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
        .onChange(of: focus) { _, field in
            // A field left by the hand closes its list.
            if field == nil, open == .with || open == .buy || open == .to {
                withAnimation(DS.Motion.standard) { open = nil }
            }
        }
    }

    // MARK: - The sentence

    private var sentence: some View {
        VStack(alignment: .leading, spacing: 0) {
            verbs
                .padding(.bottom, DS.Space.s3)
            if let receipt {
                receiptLines(receipt)
            } else if emptyEverywhere, verb != .receive {
                FlowLayout(spacing: 10, lineSpacing: 0) {
                    ForEach(Array((verb == .swap ? String(localized: "Nothing to swap yet.") : String(localized: "Nothing to send yet."))
                        .split(separator: " ").enumerated()), id: \.offset) { _, w in
                        word(String(w), ink: DS.textSecondary)
                    }
                }
            } else {
            switch verb {
            case .swap, .send:
                FlowLayout(spacing: 10, lineSpacing: 0) {
                    if inDollars { word("$", ink: amount.isEmpty ? DS.textTertiary : DS.textPrimary) }
                    amountField
                    if inDollars { word(String(localized: "of"), ink: DS.textPrimary) }
                    withWord
                }
                FlowLayout(spacing: 10, lineSpacing: 0) {
                    if verb == .swap {
                        word(String(localized: "for"), ink: DS.textPrimary)
                        buyWord
                    } else {
                        word(String(localized: "to"), ink: DS.textPrimary)
                        toWord
                    }
                }
                FlowLayout(spacing: 10, lineSpacing: 0) {
                    word(String(localized: "on"), ink: DS.textPrimary)
                    networkWord
                }
            case .receive:
                FlowLayout(spacing: 10, lineSpacing: 0) {
                    word(String(localized: "at"), ink: DS.textPrimary)
                    Button { copy() } label: { word(YourAccount.short(account), ink: DS.textPrimary) }
                        .buttonStyle(RowPress())
                        .accessibilityLabel(Text("Your address, \(account)"))
                        .accessibilityHint(Text("Copies your address"))
                }
                // A line of words, so it wraps between them.
                FlowLayout(spacing: 10, lineSpacing: 0) {
                    ForEach(Array(String(localized: "on Base and Ethereum.").split(separator: " ").enumerated()), id: \.offset) { _, w in
                        word(String(w), ink: DS.textPrimary)
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
    private func receiptLines(_ r: Receipt) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FlowLayout(spacing: 10, lineSpacing: 0) {
                word(r.past, ink: DS.textSecondary)
                if let first = r.lines.first { word(first, ink: DS.textPrimary) }
            }
            ForEach(Array(r.lines.dropFirst().enumerated()), id: \.offset) { _, line in
                FlowLayout(spacing: 10, lineSpacing: 0) {
                    ForEach(Array(line.split(separator: " ").enumerated()), id: \.offset) { _, w in
                        word(String(w), ink: DS.textPrimary)
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .offset(y: 8)))
    }

    private func word(_ text: String, ink: Color) -> some View {
        Text(verbatim: text)
            .dsText(.heading40)
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
                chrome.flash(String(localized: "One transaction is one network. Sign this one first"))
                return
            }
            withAnimation(DS.Motion.standard) {
                if open == which { open = nil } else {
                    open = which
                    search = ""
                    focus = which == .with || which == .buy ? .search : which == .to ? .to : nil
                }
            }
            DSHaptic.selection()
        } label: {
            word(text, ink: open == which ? DS.pickInk : ink)
        }
        .buttonStyle(RowPress())
        .disabled(stage != nil)
        .accessibilityLabel(label)
        // A pick rises into its blank from the list under it (§1438b).
        .transition(.asymmetric(insertion: .offset(y: 28).combined(with: .opacity), removal: .opacity))
    }

    /// The three verbs on their own line, the picked one bright (user:
    /// "send swap receive should be its own line user chooses which"). The
    /// sentence under it is what that verb does.
    private var verbs: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
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
                        .dsText(.heading28)
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
        return TextField("0", text: $amount)
            .keyboardType(.decimalPad)
            .focused($focus, equals: .amount)
            .dsText(.heading40)
            // Not typing, the figure is drawn over the field so its digits
            // roll as the slider moves (§1438b); the field still takes the tap.
            .foregroundStyle(typing || amount.isEmpty ? DS.textPrimary : .clear)
            .overlay(alignment: .leading) {
                if !typing, !amount.isEmpty {
                    Text(verbatim: amount)
                        .dsText(.heading40)
                        .foregroundStyle(DS.textPrimary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .fixedSize()
                        .allowsHitTesting(false)
                }
            }
            .fixedSize()
            .disabled(stage != nil || with == nil)
            .accessibilityLabel(Text(inDollars ? "Amount in dollars" : "Amount"))
            .onChange(of: amount) { _, _ in if open != nil, focus == .amount { open = nil } }
    }

    @ViewBuilder private var withWord: some View {
        if open == .with {
            searchField(String(localized: "a token you have"))
        } else {
            blank(with?.token.symbol ?? String(localized: "a token"), ink: with == nil ? DS.pickInk : DS.textPrimary,
                  .with, label: Text("Spend \(with?.token.symbol ?? ""), change"))
        }
    }

    @ViewBuilder private var buyWord: some View {
        if open == .buy {
            searchField(String(localized: "a token"))
        } else if let buy {
            let back = quote.map { "≈ " + Op.spoken($0.buyAmount, decimals: buy.token.decimals) + " " }
            let word = blank((back ?? "") + buy.token.symbol, ink: DS.textPrimary, .buy, label: Text("For \(buy.token.symbol), change"))
            if pricing {
                // While CoW thinks, the word breathes: working, not stuck.
                word.phaseAnimator([1.0, 0.4]) { content, phase in content.opacity(phase) } animation: { _ in .easeInOut(duration: 0.9) }
            } else {
                word
            }
        } else {
            blank(String(localized: "a token"), ink: DS.pickInk, .buy, label: Text("Pick what you want"))
        }
    }

    /// A swap is being priced: everything is there but CoW's answer.
    private var pricing: Bool {
        verb == .swap && buy != nil && units != nil && quote == nil && quoteNote == nil
    }

    @ViewBuilder private var toWord: some View {
        if open == .to {
            TextField(String(localized: "someone"), text: $to)
                .focused($focus, equals: .to)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { withAnimation(DS.Motion.standard) { open = nil } }
                .dsText(.heading40)
                .foregroundStyle(DS.textPrimary)
                .frame(minWidth: 120)
                .fixedSize()
                .accessibilityLabel(Text("Who it goes to"))
        } else {
            let shown = resolved?.name ?? (resolved.map { YourAccount.short($0.address) })
                ?? (to.isEmpty ? String(localized: "someone") : to)
            blank(shown, ink: resolved?.imitates != nil ? DS.attentionInk : resolved == nil ? DS.pickInk : DS.textPrimary,
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
    }

    private var networkWord: some View {
        blank(network.name + ".", ink: DS.textSecondary, .network, label: Text("On \(network.name), change"))
    }

    private func searchField(_ prompt: String) -> some View {
        TextField(prompt, text: $search)
            .focused($focus, equals: .search)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .dsText(.heading40)
            .foregroundStyle(DS.textPrimary)
            .frame(minWidth: 160)
            .fixedSize()
            .task(id: search) { await lookUpPasted() }
    }

    // MARK: - The space under it

    private var space: some View {
        Group {
            switch open {
            case .with: withList
            case .buy: buyList
            case .to: toList
            case .network: networkList
            case nil: line
            }
        }
        .id(open)
        // A list rises into the space and sinks away as its pick lands.
        .transition(.asymmetric(insertion: .offset(y: 24).combined(with: .opacity),
                                removal: .offset(y: 40).combined(with: .opacity)))
    }

    /// The other unit (tap to type in it), what you have, the fee.
    @ViewBuilder private var line: some View {
        if let receipt {
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
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text(verbatim: account)
                    .dsText(.mono12)
                    .foregroundStyle(DS.textSecondary)
                    .textSelection(.enabled)
                Menu {
                    Button { addFrom("https://www.coinbase.com") } label: { Text(verbatim: "Coinbase") }
                    Button { addFrom("https://www.kraken.com") } label: { Text(verbatim: "Kraken") }
                    Button("Another wallet") { copy() }
                } label: {
                    Text("From an exchange")
                        .dsText(.body17)
                        .foregroundStyle(DS.textSecondary)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(RowPress())
            }
        } else if let note = lineNote {
            Text(verbatim: note).dsText(.body17).foregroundStyle(DS.attentionInk)
        } else if let with {
            HStack(spacing: 0) {
                if let other = otherUnit(with) {
                    Button {
                        withAnimation(DS.Motion.standard) { flipUnit(with) }
                        DSHaptic.selection()
                    } label: {
                        Text(verbatim: other).dsText(.body17).foregroundStyle(DS.pickInk)
                    }
                    .buttonStyle(RowPress())
                    .accessibilityHint(Text(inDollars ? "Type in \(with.token.symbol) instead" : "Type in dollars instead"))
                    Text(verbatim: " · ").dsText(.body17).foregroundStyle(DS.textSecondary)
                }
                // What you have is a door: a tap spends all of it.
                Button {
                    shareBinding(with).wrappedValue = 100
                    DSHaptic.snap()
                } label: {
                    Text(verbatim: haveLine(with)).dsText(.body17).foregroundStyle(DS.textSecondary)
                }
                .buttonStyle(RowPress())
                .accessibilityHint(Text("Fills in all of it"))
                if let fee = feeLine(with) {
                    Text(verbatim: " · " + fee).dsText(.body17).foregroundStyle(DS.textSecondary)
                }
                // A test network says so wherever it is picked (prd §1439).
                if network.isTest {
                    Text(verbatim: " · " + String(localized: "test coins")).dsText(.body17).foregroundStyle(DS.attentionInk)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        } else if heldBy.isEmpty {
            Text("Reading…").dsText(.body17).foregroundStyle(DS.textSecondary)
        } else {
            Text("Nothing on \(network.name) yet").dsText(.body17).foregroundStyle(DS.textSecondary)
        }
    }

    private var lineNote: String? {
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
            return Op.spoken(u, decimals: h.token.decimals) + " " + h.token.symbol
        }
        return Self.money(Op.dollars(units ?? "0", decimals: h.token.decimals, price: price))
    }

    private func haveLine(_ h: Tokens.Held) -> String {
        let have = inDollars && h.price != nil
            ? Self.money(Op.dollars(left(h), decimals: h.token.decimals, price: h.price!))
            : Op.spoken(left(h), decimals: h.token.decimals)
        return String(localized: "of \(have)")
    }

    /// A swap's fee; under a cent it says so rather than a string of zeros.
    private func feeLine(_ h: Tokens.Held) -> String? {
        guard verb == .swap, let quote else { return nil }
        if let price = h.price, Op.dollars(quote.fee, decimals: h.token.decimals, price: price) < 0.01 {
            return String(localized: "fee under a cent")
        }
        return String(localized: "fee ≈ \(Op.spoken(quote.fee, decimals: h.token.decimals)) \(h.token.symbol)")
    }

    private func flipUnit(_ h: Tokens.Held) {
        guard let price = h.price else { return }
        let current = units
        inDollars.toggle()
        guard let current else { amount = ""; return }
        amount = inDollars
            ? String(format: "%.2f", Op.dollars(current, decimals: h.token.decimals, price: price))
            : Op.display(current, decimals: h.token.decimals, places: min(h.token.decimals, 8))
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
                         mark: String? = nil, dim: Bool = false, act: @escaping () -> Void) -> some View {
        Button(action: act) {
            HStack(spacing: DS.Space.s3) {
                if let mark { AssetMark(name: mark, size: DS.Face.list) }
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
        let rows = held.filter { q.isEmpty || $0.token.symbol.lowercased().hasPrefix(q) }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { h in
                listRow(h.token.symbol, sub: h.usd.map { Self.money($0) },
                        trailing: Op.spoken(left(h), decimals: h.token.decimals), mark: h.token.symbol) {
                    pick { choose(h) }
                }
            }
            if rows.isEmpty {
                Text(heldBy.isEmpty ? "Reading…" : "Nothing on \(network.name) yet")
                    .dsText(.body17).foregroundStyle(DS.textSecondary).frame(minHeight: 44)
            }
        }
    }

    private var buyList: some View {
        var rows = Tokens.matches(search, in: listed, held: held)
        if let pasted, !rows.contains(where: { $0.id == pasted.id }) { rows.insert(pasted, at: 0) }
        rows.removeAll { $0.token == with?.token }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { l in
                let mine = held.first { $0.id == l.id }
                listRow(l.token.symbol,
                        sub: l.onList ? (l.name == l.token.symbol ? nil : l.name) : String(localized: "Not on CoW's list"),
                        trailing: mine.map { Op.spoken($0.units, decimals: $0.token.decimals) },
                        mark: l.token.symbol, dim: !l.onList) {
                    pick { buy = l }
                    if amount.isEmpty { focus = .amount }
                }
            }
            if !YourAccountSwap.supported(network) {
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
        return VStack(alignment: .leading, spacing: 0) {
            if let r = resolved, r.imitates == nil, !book.contains(where: { WalletWatch.sameAddress($0.address, r.address) }) {
                listRow(r.name ?? YourAccount.short(r.address), sub: r.name == nil ? nil : YourAccount.short(r.address)) {
                    pick {}
                }
            }
            ForEach(Array(book.prefix(20)), id: \.address) { e in
                listRow(e.name, sub: YourAccount.short(e.address), mark: e.name) {
                    to = e.name
                    resolved = Recipient(address: EIP55.checksum(e.address), name: e.name, imitates: nil)
                    pick {}
                }
            }
            pasteRow { to = $0 }
        }
    }

    private var networkList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Op.networks) { n in
                let total = (heldBy[n.chainId] ?? []).compactMap(\.usd).reduce(0, +)
                listRow(n.name, sub: n.isTest ? String(localized: "Test network · its coins have no value") : nil,
                        trailing: total > 0 ? Self.money(total) : nil, dim: n == network) {
                    pick { switchNetwork(n) }
                }
            }
        }
    }

    private func pasteRow(_ put: @escaping (String) -> Void) -> some View {
        Button {
            guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                chrome.flash(String(localized: "Nothing to paste"))
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

    private func choose(_ h: Tokens.Held) {
        if with?.id != h.id { amount = ""; if h.price == nil { inDollars = false } }
        with = h
        if buy?.token == h.token { buy = nil }
        focus = .amount
    }

    private func switchNetwork(_ n: Op.Network) {
        guard n != network else { return }
        network = n
        with = nil
        buy = nil
        amount = ""
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
                case .send(let p): return Op.spoken(p.amount, decimals: p.token.decimals) + " " + p.token.symbol
                case .swap(let s): return Op.spoken(s.amount, decimals: s.sell.decimals) + " " + s.sell.symbol
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
                words = String(localized: "\(spent) for ≈ \(Op.spoken(back, decimals: s.buy.decimals)) \(s.buy.symbol)")
            case nil:
                words = ""
            }
            return (key, words, group.map(\.id))
        }
    }

    private var kept: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(keptLines, id: \.id) { line in
                HStack(spacing: DS.Space.s3) {
                    Text(verbatim: line.words)
                        .dsText(.heading20)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: DS.Space.s2)
                    Button {
                        withAnimation(DS.Motion.standard) { items.removeAll { line.ids.contains($0.id) } }
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
                .frame(minHeight: 44)
            }
        }
    }

    // MARK: - The foot

    private var foot: some View {
        VStack(spacing: DS.Space.s2) {
            if verb != .receive, open == nil, receipt == nil, let with {
                DSShareSlider(percent: shareBinding(with), enabled: stage == nil)
            }
            if receipt != nil {
                HStack {
                    Button {
                        withAnimation(DS.Motion.standard) { receipt = nil }
                        DSHaptic.selection()
                    } label: {
                        Text("Done").dsText(.heading28).foregroundStyle(DS.textSecondary).frame(minHeight: 48, alignment: .leading)
                    }
                    .buttonStyle(RowPress())
                    Spacer()
                }
            } else {
            HStack(alignment: .firstTextBaseline) {
                Button { verb == .receive ? copy() : sign() } label: {
                    Text(verbatim: footVerb)
                        .dsText(.heading28)
                        .foregroundStyle(footOn ? DS.pickInk : DS.textTertiary)
                        .frame(minHeight: 48, alignment: .leading)
                }
                .buttonStyle(RowPress())
                .disabled(!footOn)
                Spacer(minLength: DS.Space.s3)
                if verb != .receive {
                    Button { add() } label: {
                        Text("Add")
                            .dsText(.heading20)
                            .foregroundStyle(pendingItem != nil && stage == nil ? DS.textSecondary : DS.textTertiary)
                            .frame(minHeight: 48)
                    }
                    .buttonStyle(RowPress())
                    .disabled(pendingItem == nil || stage != nil)
                    .accessibilityHint(Text("Keeps this in the transaction and starts the next one"))
                }
            }
            }
        }
        .padding(.horizontal, DSRoomChassis.leadInset)
        .padding(.bottom, footClearance)
        // The page's own ground, so a long list scrolls under the foot.
        .background { DSPageBackground() }
    }

    /// The phone's tab bar floats over the page's bottom edge and reserves
    /// nothing, so the foot clears it by the bar's own geometry; a keyboard
    /// covers the bar (prd §865), and the foot rides on the keys.
    private var footClearance: CGFloat {
        guard sizeClass == .compact, !chrome.keyboardUp else { return DS.Space.s2 }
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

    private func add() {
        guard let item = pendingItem else { return }
        if let first = items.first, first.network != item.network {
            chrome.flash(String(localized: "One transaction sends on one network"), tone: .failure)
            return
        }
        withAnimation(DS.Motion.standard) { items.append(item) }
        DSHaptic.tap()
        // The next sentence keeps what it is for or who it is to, and the
        // network; it moves to the next token with something left.
        amount = ""
        quote = nil
        if let next = held.first(where: { $0.id != with?.id && left($0) != "0" && $0.token != buy?.token }) {
            with = next
            if next.price == nil { inDollars = false }
        }
        focus = .amount
    }

    private func sign() {
        guard stage == nil else { return }
        let batch = all
        guard !batch.isEmpty else { return }
        let reason = faceIDWords(batch)
        let net = network
        stage = .preparing
        Task {
            do {
                let done = try await Chain.transact(batch, reason: reason) { s in
                    await MainActor.run { stage = s }
                }
                let sent = done.sent
                stage = nil
                chrome.refreshRooms()
                // Landed or still on its way, the transaction is gone from the
                // page, so a second tap cannot pay it twice. The sentence
                // turns past tense in its place (§1438b): no toast.
                let made = Self.receipt(for: batch, done: done, on: net)
                withAnimation(DS.Motion.standard) {
                    items = []
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
                chrome.flash(failure.message, tone: .failure, seconds: 5)
            } catch {
                stage = nil
                // Face ID cancelled, or the Enclave refused: nothing left the phone.
                chrome.flash(String(localized: "Not sent"), tone: .failure)
            }
        }
    }

    /// The sentence in the past tense: what was sent or swapped, what a filled
    /// order actually paid out, and how it went.
    static func receipt(for batch: [Chain.Item], done: Chain.Transacted, on net: Op.Network) -> Receipt {
        let sent = done.sent
        let tx: String? = { if case .landed(let t, _) = sent.outcome { return t } else { return nil } }()
        let link = tx.flatMap { explorer($0, on: net) }
        let linkName: String? = net.chainId == 1 ? "Etherscan" : "Basescan"
        let on = String(localized: "on \(net.name).")
        if case .pending = sent.outcome {
            return Receipt(past: String(localized: "Sent,"), lines: [String(localized: "not yet seen"), on],
                           detail: String(localized: "Check before sending again"))
        }
        let swaps = batch.compactMap { if case .swap(let s) = $0 { s } else { nil } }
        let filled = !swaps.isEmpty && done.orders.allSatisfy { $0 == "fulfilled" }
        var detail: [String] = []
        if !swaps.isEmpty {
            if filled, let seconds = done.filledIn {
                detail.append(String(localized: "Filled in \(Int(seconds.rounded())) seconds"))
            } else if !filled {
                detail.append(String(localized: "Order placed. CoW fills it at the best price it finds"))
            }
        }
        if batch.count == 1, let item = batch.first {
            switch item {
            case .send(let p):
                let who = p.toName ?? YourAccount.short(p.to)
                return Receipt(past: String(localized: "Sent"),
                               lines: [Op.spoken(p.amount, decimals: p.token.decimals) + " " + p.token.symbol,
                                       String(localized: "to \(who)"), on],
                               detail: detail.joined(separator: " · "), link: link, linkName: link == nil ? nil : linkName)
            case .swap(let s):
                let bought = done.bought.first.flatMap { $0 }
                let back = bought.map { Op.spoken($0, decimals: s.buy.decimals) }
                    ?? "≈ " + Op.spoken(s.quote.buyAmount, decimals: s.buy.decimals)
                // More than quoted is the honest surprise: CoW's solvers found it.
                if let bought, Op.atMost(s.quote.buyAmount, bought), bought != s.quote.buyAmount {
                    let more = Op.spoken(Op.difference(bought, s.quote.buyAmount), decimals: s.buy.decimals)
                    detail.append(String(localized: "\(more) \(s.buy.symbol) more than quoted"))
                }
                return Receipt(past: filled ? String(localized: "Swapped") : String(localized: "Swapping"),
                               lines: [Op.spoken(s.amount, decimals: s.sell.decimals) + " " + s.sell.symbol,
                                       String(localized: "for \(back) \(s.buy.symbol)"), on],
                               detail: detail.joined(separator: " · "), link: link, linkName: link == nil ? nil : linkName)
            }
        }
        return Receipt(past: String(localized: "Signed"),
                       lines: [String(localized: "\(batch.count) in one transaction"), on],
                       detail: detail.joined(separator: " · "), link: link, linkName: link == nil ? nil : linkName)
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
        case 84532: host = "sepolia.basescan.org"
        default: return nil
        }
        return URL(string: "https://\(host)/tx/\(transaction)")
    }

    private func copy() {
        UIPasteboard.general.string = account
        DSHaptic.tap()
        chrome.flash(String(localized: "Address copied"))
    }

    /// The address on the clipboard, then the exchange: paste it as the
    /// destination of a withdrawal there, on Base or Ethereum.
    private func addFrom(_ site: String) {
        copy()
        if let url = URL(string: site) { openURL(url) }
    }

    // MARK: - Reads

    /// Every network's holdings at once; the sentence starts on the one
    /// holding the most, and spends its biggest token.
    private func readAll() async {
        var found: [Int: [Tokens.Held]] = [:]
        for net in Op.networks {
            found[net.chainId] = await Tokens.held(account, on: net)
        }
        heldBy = found
        func worth(_ n: Op.Network) -> Double { (found[n.chainId] ?? []).compactMap(\.usd).reduce(0, +) }
        // The most dollars; with none priced (test coins), the first network
        // holding anything at all.
        if items.isEmpty, with == nil {
            if let best = Op.networks.max(by: { worth($0) < worth($1) }), worth(best) > 0 {
                network = best
            } else if let any = Op.networks.first(where: { !(found[$0.chainId] ?? []).isEmpty }) {
                network = any
            }
        }
        if with == nil { with = held.first }
        // CoW settles on neither test network: there the sentence starts on Send.
        if verb == .swap, items.isEmpty, !YourAccountSwap.supported(network) { verb = .send }
        listed = await Tokens.list(network)
    }

    private func readNetwork() async {
        let now = await Tokens.held(account, on: network)
        heldBy[network.chainId] = now
        if let w = with { with = now.first { $0.id == w.id } ?? now.first } else { with = now.first }
        listed = await Tokens.list(network)
    }

    /// The quote is asked again whenever what would be swapped changes.
    private var quoteKey: String {
        guard verb == .swap, let with, let buy else { return "" }
        return "\(network.chainId)|\(with.id)|\(buy.id)|\(units ?? "")"
    }

    private func requote() async {
        quote = nil
        quoteNote = nil
        guard verb == .swap, let with, let buy, YourAccountSwap.supported(network), let units else { return }
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
        } catch {}
    }

    private func lookUpPasted() async {
        pasted = nil
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard open == .buy, ENS.isHexAddress(text) else { return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        pasted = await Tokens.lookUp(text, on: network)
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
    /// swap is Added once CoW prices it, and the send fills the next sentence.
    private func draft() {
        let d = UserDefaults.standard
        if let swap = d.string(forKey: "moveSwapDraft"), !swap.isEmpty {
            let parts = swap.split(separator: "|").map(String.init)
            verb = .swap
            if parts.count > 1, let h = held.first(where: { $0.token.symbol == parts[1] }) { with = h }
            let buyName = parts.count > 2 ? parts[2] : (with?.token.symbol == "ETH" ? "USDC" : "ETH")
            buy = listed.first { $0.token.symbol == buyName && $0.onList }
                ?? held.first { $0.token.symbol == buyName }.map { Tokens.Listed(token: $0.token, name: $0.token.symbol, onList: true) }
            amount = parts.first ?? ""
            NSLog("moveSwapDraft: %@ %@ for %@", amount, with?.token.symbol ?? "-", buy?.token.symbol ?? "-")
        } else if d.string(forKey: "moveSendDraft")?.isEmpty == false {
            verb = .send
            sendDraft()
        }
    }

    private func sendDraft() {
        guard let draft = UserDefaults.standard.string(forKey: "moveSendDraft"), !draft.isEmpty else { return }
        let parts = draft.split(separator: "|", maxSplits: 1).map(String.init)
        amount = parts.first ?? ""
        to = parts.count > 1 ? parts[1] : ""
        NSLog("moveSendDraft: amount=%@ to=%@", amount, to)
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
