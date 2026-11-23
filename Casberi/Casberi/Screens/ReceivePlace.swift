import SwiftData
import SwiftUI

/// **ONE PLACE ON RECEIVE (prd §1945).** Its name, Copy at the end (the head
/// is the copy's whole target), then its labelled lines (`ReceiveWords.Fact`)
/// in Move's receipt column, so every place on the page reads the same way
/// and none needs a page or an ⓘ of its own. Aztec's words wear its ink.
struct ReceivePlace<Extra: View>: View {
    let name: String
    let facts: [ReceiveWords.Fact]
    var ink: Color = DS.textPrimary
    var copied = false
    /// Nil draws no Copy: an address the account cannot follow (§1442k).
    var copy: (() -> Void)?
    @ViewBuilder var extra: () -> Extra

    static var lineHeight: CGFloat { 30 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                copy?()
            } label: {
                HStack(spacing: DS.Space.s2) {
                    Text(verbatim: name)
                        .dsText(.heading17)
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    Spacer(minLength: DS.Space.s2)
                    if copy != nil {
                        (copied ? Text("Copied") : Text("Copy"))
                            .dsText(.body17)
                            .foregroundStyle(copied ? DS.confirmInk : ink == DS.textPrimary ? DS.pickInk : ink)
                            .contentTransition(.opacity)
                    }
                }
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            .disabled(copy == nil)
            .accessibilityLabel(Text("Copy the \(name) address"))
            ForEach(facts, id: \.self) { fact in
                ReceiveFactLine(label: fact.label, value: fact.value,
                                ink: fact.quiet ? DS.textSecondary : ink == DS.textPrimary ? DS.textPrimary : ink)
            }
            extra()
        }
        .padding(.bottom, DS.Space.s3)
    }
}

extension ReceivePlace where Extra == EmptyView {
    init(name: String, facts: [ReceiveWords.Fact], ink: Color = DS.textPrimary, copied: Bool = false,
         copy: (() -> Void)?) {
        self.init(name: name, facts: facts, ink: ink, copied: copied, copy: copy) { EmptyView() }
    }
}

/// A labelled line under a place: its word grey in the receipt's column,
/// its value beside it, wrapping rather than shrinking.
struct ReceiveFactLine<Trailing: View>: View {
    let label: String
    let value: String
    var ink: Color = DS.textPrimary
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: label)
                .dsText(.fact15)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: MoveReceipt.labelWidth, alignment: .leading)
            Text(verbatim: value)
                .dsText(.fact15)
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .frame(minHeight: ReceivePlace<EmptyView>.lineHeight)
        .accessibilityElement(children: .combine)
    }
}

extension ReceiveFactLine where Trailing == EmptyView {
    init(label: String, value: String, ink: Color = DS.textPrimary) {
        self.init(label: label, value: value, ink: ink) { EmptyView() }
    }
}

/// The demo's private address: nothing is opened.
enum ReceiveDemo {
    static var privateAddress: String { "0zk1qyqrw8a5h9mc0tk3n6fz2l4s7vxj9uq8e5pd3rjkm6g2wa0tyz4h7cxs9ld3unv8kq2fe6mrx5pa4w0jg7t3yhs9cvz2lm8dq6rkue0xan5tw3pfy8hg4jv7f3a" }
}

/// **PRIVACY POOLS ON RECEIVE, WITH WHAT ARRIVED (prd §1945, retiring its
/// page, user: "if we already have the receive page, why do we need another
/// privacy pools page").** The place's lines, then one Status line for each
/// one-time address money has reached and not yet finished with: what
/// arrived and where it is, in its state's ink, with Try again where a move
/// failed and Pay the gas where it waits for ETH (prd §1779, §1823). Copy
/// copies an address never used (`unusedCurrent`): a new one once money
/// has reached the last.
///
/// While it shows, every one-time address is looked at at once, then every
/// 15 s (`FreshReceive.check`), and the ASP is asked, as the page did.
struct ReceivePoolsPlace: View {
    let facts: [ReceiveWords.Fact]
    /// Pay the gas: Send, filled with the address and the ETH it is short
    /// of. Nil where no account of yours can pay: the verb is not drawn (§83).
    var payGas: ((_ address: String, _ eth: String) -> Void)? = nil

    @State private var copied = false
    @State private var reading: String?
    /// Failed token moves whose address is short of gas (prd §1823), read
    /// after each look, never in a body.
    @State private var shortOfGas: Set<String> = []
    @Environment(\.modelContext) private var context
    @Environment(ShellChrome.self) private var chrome
    private var book: FreshReceive { .shared }

    /// The addresses with something to say, newest first, three at most.
    private var live: [FreshAddress.Entry] {
        let chain = book.network?.chainId
        return book.entries
            .filter { chain == nil || $0.network == chain }
            .filter { entry in
                switch entry.state {
                case .waiting: return false
                case .moved(_, let tx):
                    return PrivateMoneyStore.shared.notes.first(where: { $0.tx == tx })?.status != .approved
                default: return true
                }
            }
            .sorted { ($0.made, $0.index) > ($1.made, $1.index) }
            .prefix(3)
            .map { $0 }
    }

    var body: some View {
        ReceivePlace(name: ReceiveWords.name(.pools), facts: facts, copied: copied, copy: copy) {
            if let failure = book.failure {
                ReceiveFactLine(label: String(localized: "Status"), value: failure, ink: DS.attentionInk)
            }
            ForEach(live) { entry in
                statusLine(entry)
                if payGas != nil, waitsForGas(entry), !DemoMode.isActive {
                    // What paying costs in privacy, said where it is offered (prd §1779).
                    DSFootnote("From your account, in the open. It links this address to you.")
                        .padding(.leading, MoveReceipt.labelWidth)
                }
            }
        }
        .task {
            guard !DemoMode.isActive else { return }
            // Opened, every address is looked at at once (a failed move is
            // tried again); then every 15 s while Receive shows.
            await book.check(context: context, force: true)
            await readShortOfGas()
            await PrivateMoneyStore.shared.refresh(force: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                await book.check(context: context)
                await readShortOfGas()
                await PrivateMoneyStore.shared.refresh()
            }
        }
    }

    @ViewBuilder private func statusLine(_ entry: FreshAddress.Entry) -> some View {
        let said = Self.status(entry, book: book)
        ReceiveFactLine(label: String(localized: "Status"), value: said.words, ink: said.ink) {
            if case .failed = entry.state, !shortOfGas.contains(entry.id) {
                verb(String(localized: "Try again")) {
                    Task { await book.check(context: context, force: true); await readShortOfGas() }
                }
            } else if let payGas, waitsForGas(entry), !DemoMode.isActive {
                verb(reading == entry.id ? String(localized: "Reading the fee…") : String(localized: "Pay the gas")) {
                    guard reading == nil else { return }
                    reading = entry.id
                    Task {
                        let eth = await book.gasToPay(entry)
                        reading = nil
                        if let eth { payGas(entry.address, eth) } else { shortOfGas.remove(entry.id) }
                    }
                }
            }
        }
    }

    private func verb(_ word: String, _ act: @escaping () -> Void) -> some View {
        Button {
            DSHaptic.selection()
            act()
        } label: {
            Text(verbatim: word)
                .dsText(.fact15)
                .foregroundStyle(DS.pickInk)
                .fixedSize()
                .padding(.leading, DS.Space.s2)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .padding(.vertical, -(DS.Hit.min - ReceivePlace<EmptyView>.lineHeight) / 2)
    }

    private func copy() {
        guard !DemoMode.isActive else { chrome.flash(YourAccountDemo.actsLater); return }
        guard let entry = book.unusedCurrent() else {
            chrome.flash(book.failure ?? String(localized: "No new address could be made"), tone: .failure)
            return
        }
        DSPasteboard.copy(entry.address)
        DSHaptic.tap()
        chrome.flash(String(localized: "Copied · new address each time"), tone: .success)
        withAnimation(DS.Motion.standard) { copied = true }
        Task {
            try? await Task.sleep(for: .milliseconds(1200))
            withAnimation(DS.Motion.standard) { copied = false }
        }
    }

    /// A token waiting for gas, or a failed token move whose address is
    /// short of it (prd §1823).
    private func waitsForGas(_ entry: FreshAddress.Entry) -> Bool {
        switch entry.state {
        case .needsGas: true
        case .failed: entry.symbol != nil && shortOfGas.contains(entry.id)
        default: false
        }
    }

    private func readShortOfGas() async {
        guard payGas != nil else { shortOfGas = []; return }
        var short: Set<String> = []
        for entry in live {
            guard case .failed = entry.state, entry.symbol != nil else { continue }
            if await book.gasToPay(entry) != nil { short.insert(entry.id) }
        }
        shortOfGas = short
    }

    /// What arrived at one address and where it is, as the Status line says it.
    static func status(_ entry: FreshAddress.Entry, book: FreshReceive) -> (words: String, ink: Color) {
        if let waiting = book.homeNeedsGas[entry.id] {
            // A dollar paid on Base or Robinhood with no ETH there for its move (prd §1880).
            let parts = waiting.split(separator: "|").map(String.init)
            let (symbol, place) = (parts.first ?? "USDC", parts.count > 1 ? parts[1] : "Base")
            return parts.count > 2
                // Across gave it back twice (prd §1882).
                ? (String(localized: "\(symbol) on \(place) couldn't move to Ethereum. It stays at this address."), DS.attentionInk)
                : (String(localized: "\(symbol) on \(place) needs a little ETH sent there to move."), DS.attentionInk)
        }
        if let from = book.homeMoving[entry.id] {
            // Paid on Base or Robinhood, on its way to Ethereum (prd §1878).
            return (String(localized: "On its way from \(from) to Ethereum."), DS.textSecondary)
        }
        let symbol = entry.token
        let railgun = FreshTx.railgunToken(symbol: symbol)
        // A dollar at cents, a coin at four places (prd §1944).
        func figure(_ amount: String) -> String {
            let dollar = symbol == "USDC" || symbol == "USDG"
            let decimals = railgun?.decimals ?? (symbol == "USDC" ? 6 : 18)
            guard let n = PrivateMoney.number(amount, decimals: decimals, places: dollar ? 2 : 4) else { return symbol }
            return "\(n) \(symbol)"
        }
        switch entry.state {
        case .waiting:
            return ("", DS.textSecondary)
        // A transaction out and not yet seen reads as the move under way it is.
        case .moving(let amount), .sent(let amount, _, _, _, _):
            return (String(localized: "\(figure(amount)) arrived, moving in…"), DS.textSecondary)
        // Railgun's screening lists a shield in about an hour (§1713 item 5).
        case .moved(let amount, _) where railgun != nil:
            return (String(localized: "\(figure(amount)) moving in · private in about an hour"), DS.textSecondary)
        // What went in once 0xBow's fee and the gas were paid, and who it
        // waits on, in grey: nobody waits on you (prd §1841).
        case .moved(let amount, let tx):
            let note = PrivateMoneyStore.shared.notes.first(where: { $0.tx == tx })
            let held = note.map { PrivateMoney.Ask(note: $0).figure }
            switch note?.status {
            case .approved: return (String(localized: "\(held ?? figure(amount)) private now"), DS.confirmInk)
            case .rejected: return (String(localized: "\(held ?? figure(amount)) not approved"), DS.destructiveInk)
            default: return (String(localized: "\(held ?? figure(amount)) being checked by Privacy Pools"), DS.textSecondary)
            }
        case .tooLittle(let amount):
            return (String(localized: "\(figure(amount)) arrived, too little to move"), DS.textSecondary)
        case .failed(let amount):
            return (String(localized: "\(figure(amount)) not moved"), DS.attentionInk)
        // USDC with no ETH for its gas, and too little private ETH to pay it (prd §1567).
        case .needsGas(let amount):
            return (String(localized: "\(figure(amount)) needs a little private ETH to move"), DS.attentionInk)
        }
    }
}

/// Where Privacy Pools' one-time address is watched: Base, Ethereum and
/// Robinhood on Ethereum's home chain (prd §1878), else its one network.
enum ReceivePools {
    /// The same, one name each, for a sentence ("On Base, Ethereum and Robinhood").
    static var names: [String] {
        let net = PrivacyNetwork.current(debugAsks: PrivateMove.debugNetwork)
        return net?.chainId == FreshTx.homeChain || net == nil
            ? ["Base", "Ethereum", "Robinhood"] : [net?.name ?? ""]
    }

    static var networks: String {
        let net = PrivacyNetwork.current(debugAsks: PrivateMove.debugNetwork)
        return net?.chainId == FreshTx.homeChain || net == nil
            ? String(localized: "Base, Ethereum, Robinhood") : net?.name ?? ""
    }
}

/// **RECEIVE WITH NO ACCOUNT YET (prd §1945):** Privacy Pools alone, which
/// never needs your account (prd §1560): the page's name, then the place
/// as Receive draws it. No Pay the gas: no account of yours can pay.
struct ReceiveWithoutAccount: View {
    var inTray = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Receive")
                    .dsText(.heading34)
                    .foregroundStyle(DS.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, DS.Space.s2)
                Text("Private")
                    .dsText(.heading24)
                    .foregroundStyle(DS.textPrimary)
                    .frame(minHeight: DS.Hit.min, alignment: .bottomLeading)
                    .accessibilityAddTraits(.isHeader)
                ReceivePoolsPlace(facts: ReceiveWords.facts(.pools, networks: "", poolsNetworks: ReceivePools.networks,
                                                            pools: .current))
            }
            .padding(.horizontal, MoveSentence.sideInset(inTray))
            .padding(.top, inTray ? DS.Space.s2 : DS.Space.s6)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .task {
            if PrivateMove.available, !DemoMode.isActive {
                await PrivateMoneyStore.shared.readYield(including: .ethereum)
            }
        }
    }
}
