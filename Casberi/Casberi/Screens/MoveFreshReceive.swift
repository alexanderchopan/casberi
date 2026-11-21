import SwiftData
import SwiftUI

/// **RECEIVE TO YOUR PRIVATE BALANCE: A FRESH ADDRESS (prd §1560, §1719).**
/// Picked as "Your private balance · Ethereum" in Receive's "on" list (no
/// switch since §1719), the sentence
///
///     Receive to your private balance on Ethereum at …e07a.
///
/// ("your private balance" goes back to the list; the tail copies), one line
/// only when there is something to say (what arrived, moving in, waiting
/// for approval), then the address in one quiet line, as public Receive
/// shows yours (a tap copies the whole; no QR, user: "i don't know why we
/// need the qr code"), and the foot: "New address" grey at the leading
/// edge, "Share" pink at the trailing. No helper text.
///
/// While it shows, every fresh address is looked at every 15 s
/// (`FreshReceive.check`); what arrived moves into your private balance by
/// itself. Sepolia only, DEBUG builds only (`PrivateMove.available`).
struct MoveFreshSentence<Head: View>: View {
    /// **PRIVACY POOLS' PAGE (prd §1929).** Receive copies the address in
    /// place; this page is where a waiting row in Holdings lands, to say what
    /// arrived at its address.
    var inTray = false
    /// "your private balance" tapped: back to Receive's "on" list.
    var leave: () -> Void = {}
    /// Pay the gas (prd §1779): Send, filled with this address and the ETH
    /// it is short of. Nil where no account of yours can pay (Move with no
    /// account yet): the row is not drawn, never a dead control (§83).
    var payGas: ((_ address: String, _ eth: String) -> Void)? = nil
    @ViewBuilder let head: () -> Head

    @State private var copied = false
    /// The demo's private address: nothing is opened.
    static var demoPrivateAddress: String { "0zk1qyqrw8a5h9mc0tk3n6fz2l4s7vxj9uq8e5pd3rjkm6g2wa0tyz4h7cxs9ld3unv8kq2fe6mrx5pa4w0jg7t3yhs9cvz2lm8dq6rkue0xan5tw3pfy8hg4jv7f3a" }
    @State private var reading = false
    /// A failed token move whose address is short of gas (prd §1823), read
    /// after each look, never in a body.
    @State private var shortOfGas = false
    @Environment(\.modelContext) private var context
    @Environment(ShellChrome.self) private var chrome
    private var book: FreshReceive { .shared }
    /// **THE ADDRESS THE MONEY IS AT (prd §1823).** A waiting row in
    /// Holdings opens Receive on its own address (`chrome.moveFreshEntry`);
    /// before, Receive drew the newest, so after New address the one holding
    /// a tester's 1,000 USDC was on no screen. Otherwise the newest.
    private var entry: FreshAddress.Entry? {
        if let pinned = chrome.moveFreshEntry, let held = book.entries.first(where: { $0.id == pinned }) { return held }
        return book.current
    }

    private var moving: Bool {
        if case .moving = entry?.state { true } else { false }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // **THE SENTENCE ON TOP, THE DECK UNDER IT (prd §1928, as
                // Move's other pages, §1927).**
                MoveFlow {
                    // The tokens, the place and the networks are the sentence's
                    // (prd §1929); the plate holds the address.
                    MoveWord(String(localized: "Receive ETH, USDC"), ink: DS.textPrimary)
                    MovePhrase("USDG", glue: String(localized: "or"))
                    MovePhrase("Privacy Pools", glue: String(localized: "to"))
                    MovePhrase(Self.poolsNetworksSaid + ".", glue: String(localized: "on"))
                }
                .allowsHitTesting(false)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                // One line, only when there is something to say.
                line.padding(.top, DS.Space.s4)
            }
            .padding(.horizontal, MoveSentence.sideInset(inTray))
            .padding(.top, inTray ? DS.Space.s2 : DS.Space.s6)
            .padding(.bottom, DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { deck }
        .animation(DS.Motion.standard, value: entry)
        .onAppear { chrome.moveTall = true }
        .onChange(of: beat) { was, now in
            if now > was { DSHaptic.success() }
        }
        .task {
            book.ensureCurrent()
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "freshAddressNew") { book.make() }
            NSLog("[Casberi] moveFreshReceive: %@ | %d addresses", entry.map { YourAccount.short($0.address) } ?? "none", book.entries.count)
            #endif
            // Opened, every address is looked at at once (a failed move is
            // tried again); then every 15 s while the page shows. The ASP is
            // asked too, so "being checked" turns to "private now" here as it
            // does in Holdings (the store spaces its asks 20 s).
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

    @Environment(\.horizontalSizeClass) private var sizeClass

    /// **TWO WAYS IN, NAMED FOR WHO PAYS (prd §1928, user: "theya re both
    /// private balance"):** from any wallet, a one-time address whose money
    /// moves in by itself; from Railgun, your 0zk address.
    private var deck: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        if let entry {
                            Button { copy(entry.address) } label: { AddressGroups(address: entry.address) }
                                .buttonStyle(RowPress())
                                .accessibilityLabel(Text(verbatim: entry.address))
                                .accessibilityHint(Text("Copies the address"))
                            // A token cannot pay its own gas (prd §1779).
                            Text("Send a little ETH with USDC or USDG")
                                .dsText(.body17).foregroundStyle(DS.attentionInk)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("New address each time").dsText(.body17).foregroundStyle(DS.textSecondary)
                            Button {
                                DSHaptic.selection()
                                withAnimation(DS.Motion.standard) {
                                    copied = false
                                    chrome.moveFreshEntry = nil
                                    book.make()
                                }
                            } label: { MoveVerbRowLabel(title: String(localized: "New address"), glyph: "arrow.clockwise") }
                                .buttonStyle(RowPress())
                                .disabled(moving || DemoMode.isActive)
                            // **A WAY ON FROM "NEEDS A LITTLE PRIVATE ETH" (prd §1779,
                            // §1823).** Your account can pay it: one send, yours to confirm.
                            if let payGas, waitsForGas(entry), !DemoMode.isActive {
                                DSDoorRow(icon: "fuelpump", title: Text(reading ? "Reading the fee…" : "Pay the gas")) {
                                    guard !reading else { return }
                                    reading = true
                                    Task {
                                        let eth = await book.gasToPay(entry)
                                        reading = false
                                        if let eth { payGas(entry.address, eth) } else { shortOfGas = false }
                                    }
                                }
                                DSFootnote("From your account, in the open. It links this address to you.")
                            }
                        }
                    }
                    .padding(.vertical, DS.Space.s2)
                }
                .scrollIndicators(.hidden)
                .contentMargins(.bottom, MoveDeck.fade, for: .scrollContent)
                .safeAreaPadding(.bottom, MoveDeck.footHeight)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: MoveDeck.bodyHeight + MoveDeck.stepsHeight + MoveDeck.footHeight
                       + MoveFootClearance.bar(inTray: inTray, sizeClass: sizeClass, chrome: chrome)
                       + MoveFootClearance.gained(inTray: inTray), alignment: .top)
                .deckUnderFoot()
                MoveDeckFoot(backDisabled: moving, back: leave) {
                    if let shown = entry?.address {
                        // Share beside the copy (prd §1928).
                        HStack(spacing: DS.Space.s3) {
                            if !DemoMode.isActive { MoveShareDisc(item: shown) }
                            MoveFootWord(word: copied ? String(localized: "Copied") : String(localized: "Copy address")) { copy(shown) }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, MoveSentence.sideInset(inTray))
        .padding(.top, HomePanelMetrics.cap)
        .modifier(MoveFootClearance(inTray: inTray, intoBody: true))
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Group { if inTray { DS.surfaceSheet } else { DSPageBackground() } }
                HomePanelSurface()
            }
            .padding(.horizontal, inTray ? -DS.Space.s4 : 0)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    /// The beats a person feels (prd §1586): money arrived at the address,
    /// then approved, private now. 0 is nothing yet.
    private var beat: Int {
        guard let entry else { return 0 }
        switch entry.state {
        case .waiting: return 0
        case .moved(_, let tx):
            return PrivateMoneyStore.shared.notes.first(where: { $0.tx == tx })?.status == .approved ? 2 : 1
        default: return 1
        }
    }

    /// Whether Pay the gas stands under the line: a token waiting for gas,
    /// or a token whose move failed while its address is short (prd §1823).
    private func waitsForGas(_ entry: FreshAddress.Entry) -> Bool {
        switch entry.state {
        case .needsGas: true
        case .failed: entry.symbol != nil && shortOfGas
        default: false
        }
    }

    /// Reads whether a failed token move's address is short of gas.
    private func readShortOfGas() async {
        guard payGas != nil, let entry, case .failed = entry.state, entry.symbol != nil else {
            shortOfGas = false
            return
        }
        let short = await book.gasToPay(entry) != nil
        if self.entry?.id == entry.id { shortOfGas = short }
    }

    /// Where the address is shown: Ethereum, or Sepolia in a DEBUG build (prd §1567).
    private var network: PrivacyNetwork { book.network ?? .ethereum }


    /// Where Privacy Pools' one-time address is watched: Base, Ethereum and
    /// Robinhood on Ethereum's home chain (prd §1878), else its one network.
    static var poolsNetworks: String {
        let net = PrivacyNetwork.current(debugAsks: PrivateMove.debugNetwork)
        return net?.chainId == FreshTx.homeChain || net == nil
            ? String(localized: "Base, Ethereum, Robinhood") : net?.name ?? ""
    }

    /// The same, as the sentence says it: "Base, Ethereum, or Robinhood".
    static var poolsNetworksSaid: String {
        let net = PrivacyNetwork.current(debugAsks: PrivateMove.debugNetwork)
        return net?.chainId == FreshTx.homeChain || net == nil
            ? String(localized: "Base, Ethereum, or Robinhood") : net?.name ?? ""
    }

    /// The address in one quiet line, as public Receive shows yours; a tap
    /// copies the whole (prd §1719: no QR).
    private func code(_ address: String) -> some View {
        Button { copy(address) } label: { AddressLine(address: address) }
            .buttonStyle(RowPress())
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(Text(verbatim: address))
            .accessibilityHint(Text("Copies the address"))
    }

    private func copy(_ address: String) {
        DSPasteboard.copy(address)
        DSHaptic.tap()
        withAnimation(DS.Motion.standard) { copied = true }
    }

    /// One line, only when there is something to say.
    @ViewBuilder private var line: some View {
        if DemoMode.isActive {
            Text(verbatim: YourAccountDemo.actsLater).dsText(.body17).foregroundStyle(DS.textSecondary)
        } else if let failure = book.failure {
            Text(verbatim: failure).dsText(.body17).foregroundStyle(DS.attentionInk)
                .fixedSize(horizontal: false, vertical: true)
        } else if let entry, let waiting = book.homeNeedsGas[entry.id] {
            // A dollar paid on Base or Robinhood with no ETH there for its move (prd §1880).
            let parts = waiting.split(separator: "|").map(String.init)
            let (symbol, place) = (parts.first ?? "USDC", parts.count > 1 ? parts[1] : "Base")
            Group {
                if parts.count > 2 {
                    // Across gave it back twice (prd §1882).
                    Text("\(symbol) on \(place) couldn't move to Ethereum. It stays at this address.")
                } else {
                    Text("\(symbol) on \(place) needs a little ETH sent there to move.")
                }
            }
                .dsText(.body17).foregroundStyle(DS.attentionInk)
                .fixedSize(horizontal: false, vertical: true)
        } else if let entry, let from = book.homeMoving[entry.id] {
            // Paid on Base or Robinhood, on its way to Ethereum (prd §1878).
            Text("On its way from \(from) to Ethereum.").dsText(.body17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if let entry, let said = words(entry.state, symbol: entry.token) {
            Text(verbatim: said.0).dsText(.body17).foregroundStyle(said.1)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Before anything arrives, the sentence names the tokens and the
        // networks, and the plate says the ETH a token needs (prd §1929).
    }

    private func words(_ state: FreshAddress.State, symbol: String) -> (String, Color)? {
        let railgun = FreshTx.railgunToken(symbol: symbol)
        func figure(_ amount: String) -> String {
            PrivateMoney.figure(amount, decimals: railgun?.decimals ?? (symbol == "USDC" ? 6 : 18), symbol: symbol)
        }
        switch state {
        case .waiting:
            return nil
        // A transaction out and not yet seen reads as the move under way it is.
        case .moving(let amount), .sent(let amount, _, _, _, _):
            return (String(localized: "\(figure(amount)) arrived, moving in…"), DS.textSecondary)
        // Railgun's screening lists a shield in about an hour (§1713 item 5).
        case .moved(let amount, _) where railgun != nil:
            return (String(localized: "\(figure(amount)) moving in · private in about an hour"), DS.textSecondary)
        // What arrived, then what went in once 0xBow's fee and the gas were
        // paid, and who it waits on, in grey: nobody waits on you (prd §1841).
        case .moved(let amount, let tx):
            let note = PrivateMoneyStore.shared.notes.first(where: { $0.tx == tx })
            let held = note.map { PrivateMoney.Ask(note: $0).figure }
            switch note?.status {
            case .approved: return (String(localized: "\(held ?? figure(amount)) private now"), DS.confirmInk)
            case .rejected: return (String(localized: "\(held ?? figure(amount)) not approved"), DS.destructiveInk)
            default:
                if let held, held != figure(amount) {
                    return (String(localized: "\(figure(amount)) arrived · \(held) being checked by Privacy Pools"), DS.textSecondary)
                }
                return (String(localized: "\(figure(amount)) being checked by Privacy Pools"), DS.textSecondary)
            }
        case .tooLittle(let amount):
            return (String(localized: "\(figure(amount)) arrived, too little to move"), DS.textSecondary)
        case .failed(let amount):
            return (String(localized: "\(figure(amount)) arrived, not moved yet"), DS.attentionInk)
        // USDC with no ETH for its gas, and too little private ETH to pay it (prd §1567).
        case .needsGas(let amount):
            return (String(localized: "\(figure(amount)) arrived; needs a little private ETH to move"), DS.attentionInk)
        }
    }


}
