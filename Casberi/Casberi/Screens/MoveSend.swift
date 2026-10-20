import LocalAuthentication
import SwiftUI

/// **SEND (prd §1424): the Move page's first module**, from the 2026-10-18
/// canvas: an amount over the token it is in, the person it goes to, and one
/// slab that says the whole send in words. Add puts it in this transaction
/// and clears the fields for the next; the slab then signs every one at once
/// ("Sign 2 in one transaction"), because one user operation carries them all.
///
/// **Swap (prd §1430)** is the header's other word: the same amount over
/// what is sold, "For ≈" what comes back, the least it can be after CoW's
/// slippage, and the slab saying the whole swap. A swap is one CoW order
/// (`YourAccountSwap`), on Base and Ethereum, and Add batches it with sends
/// and other swaps alike (prd §1436): one operation carries them all.
///
/// The token picker lists what the account holds, each with its network,
/// read from the chain on open; a send says what it needs in words when the
/// balance is short, before any prompt.
struct MoveSend: View {
    let account: String
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.openURL) private var openURL

    typealias Op = YourAccountOp
    typealias Chain = YourAccountChain

    struct Holding: Identifiable, Hashable {
        let network: Op.Network
        let token: Op.Token
        let units: String
        var id: String { "\(network.chainId):\(token.symbol)" }
        static func == (a: Holding, b: Holding) -> Bool { a.id == b.id }
        func hash(into h: inout Hasher) { h.combine(id) }
    }

    @State private var holdings: [Holding] = []
    @State private var pick: Holding?
    @State private var amount = ""
    @State private var to = ""
    @State private var resolved: Recipient?
    /// To holds something shaped like an address that is not one: too short,
    /// a stray character, or a mixed-case checksum one letter off.
    @State private var malformed = false
    @FocusState private var toFocused: Bool
    /// What Add put in this transaction: sends and swaps, one network.
    @State private var items: [Chain.Item] = []
    @State private var stage: YourAccountChain.Stage?
    /// Swap, not Send (the header's second word).
    @State private var swapping = false
    @State private var quote: YourAccountSwap.Quote?
    /// Why there is no quote, in CoW's words or ours.
    @State private var quoteNote: String?
    #if DEBUG
    @State private var swapDrafted = false
    #endif

    struct Recipient: Equatable {
        let address: String
        let name: String?
        /// A book entry this raw address imitates (address poisoning).
        let imitates: String?
    }

    /// What the picker offers: every holding to send, the ones on a network
    /// CoW settles on to swap — and, once something is in the transaction,
    /// only its network's.
    private var offered: [Holding] {
        holdings.filter { h in
            (!swapping || YourAccountSwap.supported(h.network))
                && items.first.map { $0.network == h.network } ?? true
        }
    }

    private var chosen: Holding {
        if let pick, offered.contains(pick) { return pick }
        return offered.first ?? Holding(network: Op.networks[0], token: Op.eth, units: "0")
    }

    /// What a swap buys: the other token on the same network.
    private var buyToken: Op.Token? {
        Op.tokens(on: chosen.network).first { $0 != chosen.token }
    }

    /// The payment the fields describe, when they describe one.
    private var pending: Op.Payment? {
        guard let units = Op.baseUnits(amount, decimals: chosen.token.decimals),
              let r = resolved, r.imitates == nil else { return nil }
        return Op.Payment(network: chosen.network, token: chosen.token, amount: units, to: r.address, toName: r.name)
    }

    /// The swap the fields describe, once CoW has priced it.
    private var pendingSwap: Chain.Swap? {
        guard swapping, let quote, let buy = buyToken,
              let units = Op.baseUnits(amount, decimals: chosen.token.decimals) else { return nil }
        return Chain.Swap(network: chosen.network, sell: chosen.token, buy: buy, amount: units, quote: quote)
    }

    private var pendingItem: Chain.Item? {
        swapping ? pendingSwap.map(Chain.Item.swap) : pending.map(Chain.Item.send)
    }

    private var all: [Chain.Item] { items + (pendingItem.map { [$0] } ?? []) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The Wallet's section head (§1436): the glyph, then the two
            // words at the section's rung, the picked one in the head's ink.
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Image(systemName: ScopeTileGlyph.send)
                    .dsGlyph(.body)
                    .foregroundStyle(DS.brandInk)
                    .accessibilityHidden(true)
                mode(String(localized: "Send"), on: !swapping) { swapping = false }
                Text(verbatim: "·").dsText(.heading28).foregroundStyle(DS.textTertiary)
                mode(String(localized: "Swap"), on: swapping) { swapping = true }
                Spacer(minLength: DS.Space.s2)
                Button("Add") { add() }
                    .dsText(.body17)
                    .foregroundStyle(pendingItem == nil || stage != nil ? DS.textTertiary : DS.pickInk)
                    .buttonStyle(RowPress())
                    .disabled(pendingItem == nil || stage != nil)
                    .accessibilityHint(Text("Adds this to the transaction and starts another"))
            }
            .frame(minHeight: 44)

            HStack(spacing: DS.Space.s2) {
                TextField("0", text: $amount)
                    .keyboardType(.decimalPad)
                    .disabled(stage != nil)
                    .dsText(.price40)
                    .foregroundStyle(DS.textPrimary)
                    .accessibilityLabel(Text("Amount"))
                tokenMenu
            }
            .frame(minHeight: 64)

            // The whole address, end to end (user, 2026-10-19: "we should be
            // able to see it end to end"): the field wraps instead of
            // truncating, and the hint stands under it.
            if swapping {
                swapRows
            } else {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                Text("To").dsText(.body17).foregroundStyle(DS.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    TextField("a name or address", text: $to, axis: .vertical)
                        .lineLimit(1...3)
                        .focused($toFocused)
                        .submitLabel(.done)
                        // Return is Done in a wrapping field; no address holds a line break.
                        .onChange(of: to) { _, text in
                            guard text.contains("\n") else { return }
                            to = text.replacingOccurrences(of: "\n", with: "")
                            toFocused = false
                        }
                        .disabled(stage != nil)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                    if let hint {
                        Text(verbatim: hint.text)
                            .dsText(.subhead12)
                            .foregroundStyle(hint.warns ? DS.attentionInk : DS.textSecondary)
                    }
                }
            }
            .padding(.vertical, DS.Space.s3)
            .task(id: to) { await resolve() }
            }

            Button { send() } label: {
                Text(verbatim: slab)
                    .dsText(.heading17)
                    .foregroundStyle(slabOn ? DS.pickInk : DS.textTertiary)
                    .frame(minHeight: 48, alignment: .leading)
            }
            .buttonStyle(RowPress())
            .disabled(!slabOn)

            if !items.isEmpty { batch }
        }
        .task(id: swapKey) { await requote() }
        .task {
            #if DEBUG
            // `-moveSwapDraft "<amount>[|<SYMBOL>]"`: Swap with the amount filled; once
            // CoW prices it the swap is Added and `-moveSendDraft` fills the
            // send under it, so a batch of both can be driven on a simulator.
            if let draft = UserDefaults.standard.string(forKey: "moveSwapDraft"), amount.isEmpty {
                let parts = draft.split(separator: "|", maxSplits: 1).map(String.init)
                swapping = true
                amount = parts[0]
                NSLog("moveSwapDraft: amount=%@ token=%@", amount, parts.count > 1 ? parts[1] : "first")
                await readHoldings()
                if parts.count > 1 { pick = holdings.first { $0.token.symbol == parts[1] } }
                return
            }
            sendDraft()
            #endif
            await readHoldings()
        }
    }

    #if DEBUG
    /// `-moveSendDraft "<amount>|<to>"`: the fields filled, because a
    /// `simctl`-booted simulator drops typed characters (prd §1424).
    private func sendDraft() {
        guard let draft = UserDefaults.standard.string(forKey: "moveSendDraft"), amount.isEmpty, to.isEmpty else { return }
        let parts = draft.split(separator: "|", maxSplits: 1).map(String.init)
        amount = parts.first ?? ""
        to = parts.count > 1 ? parts[1] : ""
        NSLog("moveSendDraft: amount=%@ to=%@", amount, to)
    }
    #endif

    // MARK: - The token

    private var tokenMenu: some View {
        Menu {
            ForEach(offered) { h in
                Button {
                    pick = h
                } label: {
                    Text(verbatim: "\(h.token.symbol) · \(h.network.name)  \(Op.display(h.units, decimals: h.token.decimals))")
                }
            }
        } label: {
            HStack(spacing: DS.Space.s1) {
                Text(verbatim: "\(chosen.token.symbol) · \(chosen.network.name)")
                    .dsText(.heading17)
                    .foregroundStyle(DS.textPrimary)
                Image(systemName: "chevron.up.chevron.down")
                    .dsGlyph(.caption, weight: .semibold)
                    .foregroundStyle(DS.textSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
        }
        .disabled(offered.isEmpty || stage != nil)
        .accessibilityLabel(Text("Token \(chosen.token.symbol) on \(chosen.network.name)"))
    }

    /// Every network and token, read at once; the ones held lead, by network.
    private func readHoldings() async {
        let pairs = Op.networks.flatMap { n in Op.tokens(on: n).map { (n, $0) } }
        var found: [Holding] = []
        await withTaskGroup(of: Holding?.self) { group in
            for (n, t) in pairs {
                group.addTask {
                    guard let units = await YourAccountChain.balance(n, t, of: account), units != "0" else { return nil }
                    return Holding(network: n, token: t, units: units)
                }
            }
            for await h in group { if let h { found.append(h) } }
        }
        let order = Op.networks.map(\.chainId)
        holdings = found.sorted {
            ($0.network.isTest ? 1 : 0, order.firstIndex(of: $0.network.chainId) ?? 0, $0.token.symbol)
                < ($1.network.isTest ? 1 : 0, order.firstIndex(of: $1.network.chainId) ?? 0, $1.token.symbol)
        }
        if let p = pick, !holdings.contains(p) { pick = nil }
    }

    // MARK: - The recipient

    private var hint: (text: String, warns: Bool)? {
        if malformed { return (String(localized: "Check the address"), true) }
        guard let r = resolved else { return nil }
        if let imitates = r.imitates { return (String(localized: "Looks like \(imitates)'s — check it"), true) }
        if let name = r.name, name.caseInsensitiveCompare(to.trimmingCharacters(in: .whitespaces)) != .orderedSame {
            return (name, false)
        }
        return r.name == nil ? nil : (YourAccount.short(r.address), false)
    }

    private func resolve() async {
        let text = to.trimmingCharacters(in: .whitespacesAndNewlines)
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
            resolved = Recipient(address: address, name: book.name(for: address), imitates: imitates)
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

    // MARK: - The batch

    private var batch: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("In this transaction")
                    .dsText(.heading17)
                    .foregroundStyle(DS.headInk)
                Spacer()
                Text(verbatim: "\(items.count)")
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
            }
            .frame(minHeight: 44)
            .padding(.top, DS.Space.s4)
            ForEach(items) { item in
                HStack(spacing: DS.Space.s3) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: words(item)).dsText(.body17).foregroundStyle(DS.textPrimary)
                        Text(verbatim: line(item))
                            .dsText(.subhead12)
                            .foregroundStyle(DS.textSecondary)
                    }
                    Spacer(minLength: DS.Space.s2)
                    Button {
                        withAnimation(DS.Motion.standard) { items.removeAll { $0.id == item.id } }
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
                .frame(minHeight: 60)
            }
        }
    }

    private func add() {
        guard let item = pendingItem else { return }
        if let first = items.first, first.network != item.network {
            chrome.flash(String(localized: "One transaction sends on one network"), tone: .failure)
            return
        }
        withAnimation(DS.Motion.standard) { items.append(item) }
        DSHaptic.tap()
        amount = ""
        to = ""
    }

    // MARK: - The slab

    private func words(_ p: Op.Payment) -> String {
        let howMuch = Op.spoken(p.amount, decimals: p.token.decimals)
        let who = p.toName ?? YourAccount.short(p.to)
        return String(localized: "\(howMuch) \(p.token.symbol) to \(who)")
    }

    /// "0.001 ETH to Hardware" / "0.001 ETH for ≈ 2.4 USDC".
    private func words(_ item: Chain.Item) -> String {
        switch item {
        case .send(let p): return words(p)
        case .swap(let s):
            let sold = Op.spoken(s.amount, decimals: s.sell.decimals)
            let back = Op.spoken(s.quote.buyAmount, decimals: s.buy.decimals)
            return String(localized: "\(sold) \(s.sell.symbol) for ≈ \(back) \(s.buy.symbol)")
        }
    }

    private func line(_ item: Chain.Item) -> String {
        switch item {
        case .send(let p): YourAccount.short(p.to) + " · " + p.network.name
        case .swap(let s): "CoW · " + s.network.name
        }
    }

    /// The whole transaction in one sentence, for the slab and the prompt.
    private func sentence(_ items: [Chain.Item]) -> String {
        if items.count > 1 { return String(localized: "Sign \(items.count) in one transaction") }
        switch items.first {
        case .send(let p): return String(localized: "Send \(words(p))")
        case .swap(let s): return String(localized: "Swap \(words(s))")
        case nil: return ""
        }
    }

    private func words(_ s: Chain.Swap) -> String { words(.swap(s)) }

    private var slab: String {
        switch stage {
        case .preparing: return String(localized: "Preparing…")
        case .signing: return String(localized: "Confirm with Face ID")
        case .sending: return String(localized: "Sending…")
        case .landing: return String(localized: "Waiting for \(all.first?.network.name ?? "")…")
        case nil: break
        }
        if !all.isEmpty { return sentence(all) }
        if swapping { return swapSlab }
        if holdings.isEmpty { return String(localized: "Nothing to send yet") }
        return Op.baseUnits(amount, decimals: chosen.token.decimals) == nil
            ? String(localized: "Enter an amount") : String(localized: "Enter who it goes to")
    }

    private var slabOn: Bool { stage == nil && !all.isEmpty }

    private func send() {
        // One send at a time: a second tap before the slab redraws is not a
        // second payment.
        guard stage == nil else { return }
        let batch = all
        guard !batch.isEmpty else { return }
        let reason = sentence(batch)
        let swaps = batch.contains { if case .swap = $0 { true } else { false } }
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
                // page, so it cannot be paid again by a second tap.
                items = []
                amount = ""
                to = ""
                switch sent.outcome {
                case .landed(let tx, _) where !swaps:
                    let link = tx.flatMap { Self.explorer($0, on: sent.network) }
                    chrome.flash(String(localized: "Sent on \(sent.network.name)"), tone: .success,
                                 action: link.map { url in .init(label: String(localized: "View")) { openURL(url) } },
                                 seconds: 4)
                case .landed where done.orders.allSatisfy({ $0 == "fulfilled" }):
                    chrome.flash(String(localized: "Swapped on \(sent.network.name)"), tone: .success, seconds: 4)
                case .landed:
                    chrome.flash(String(localized: "Order placed. CoW fills it at the best price it finds"), seconds: 5)
                case .pending:
                    chrome.flash(String(localized: "Sent, and not yet seen on \(sent.network.name). Check before sending again"),
                                 seconds: 6)
                case .dryRun:
                    break
                }
                await readHoldings()
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

    // MARK: - Swap (prd §1430)

    private func mode(_ word: String, on: Bool, _ pick: @escaping () -> Void) -> some View {
        Button {
            guard !on else { return }
            withAnimation(DS.Motion.standard) { pick() }
            DSHaptic.selection()
        } label: {
            Text(verbatim: word)
                .dsText(.heading28)
                .foregroundStyle(on ? DS.headInk : DS.textTertiary)
        }
        .buttonStyle(RowPress())
        .disabled(stage != nil)
        .accessibilityAddTraits(on ? [.isHeader, .isSelected] : .isHeader)
    }

    /// What comes back, and the least it can be.
    @ViewBuilder private var swapRows: some View {
        let buy = buyToken
        HStack(spacing: DS.Space.s3) {
            Text("For").dsText(.body17).foregroundStyle(DS.textSecondary)
            Text(verbatim: quote.map { "≈ " + Op.spoken($0.buyAmount, decimals: buy?.decimals ?? 18) } ?? "—")
                .dsText(.body17)
                .foregroundStyle(DS.textPrimary)
            Spacer(minLength: DS.Space.s2)
            Text(verbatim: buy?.symbol ?? "")
                .dsText(.heading17)
                .foregroundStyle(DS.textPrimary)
        }
        .frame(minHeight: 44)
        Text(verbatim: swapLine)
            .dsText(.subhead12)
            .foregroundStyle(quoteNote == nil ? DS.textSecondary : DS.attentionInk)
            .frame(minHeight: 24, alignment: .leading)
    }

    private var swapLine: String {
        if let quoteNote { return quoteNote }
        guard let quote, let buy = buyToken else { return String(localized: "Through CoW, at the best price its solvers find") }
        let least = Op.spoken(quote.minimumBuy, decimals: buy.decimals)
        let fee = Op.spoken(quote.fee, decimals: chosen.token.decimals)
        return String(localized: "At least \(least) \(buy.symbol) · fee ≈ \(fee) \(chosen.token.symbol) · CoW")
    }

    /// The slab with no swap priced yet.
    private var swapSlab: String {
        if offered.isEmpty { return String(localized: "Nothing to swap yet") }
        if quoteNote != nil { return String(localized: "No price yet") }
        return Op.baseUnits(amount, decimals: chosen.token.decimals) == nil
            ? String(localized: "Enter an amount") : String(localized: "Pricing…")
    }

    /// The quote is asked again whenever what would be swapped changes.
    private var swapKey: String { swapping ? "\(chosen.id)|\(amount)" : "" }

    private func requote() async {
        quote = nil
        quoteNote = nil
        guard swapping, let buy = buyToken, YourAccountSwap.supported(chosen.network),
              let units = Op.baseUnits(amount, decimals: chosen.token.decimals) else { return }
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        do {
            let q = try await YourAccountChain.swapQuote(chosen.network, sell: chosen.token, buy: buy,
                                                         amount: units, account: account)
            guard !Task.isCancelled else { return }
            quote = q
            #if DEBUG
            if UserDefaults.standard.string(forKey: "moveSwapDraft") != nil, !swapDrafted {
                swapDrafted = true
                add()
                swapping = false
                sendDraft()
                NSLog("moveSwapDraft: added, %d in the transaction", items.count)
            }
            #endif
        } catch let failure as YourAccountChain.Failure {
            guard !Task.isCancelled else { return }
            quoteNote = failure.message
        } catch {}
    }
}
