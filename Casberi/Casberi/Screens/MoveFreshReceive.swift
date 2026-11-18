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
/// for approval), then the address in groups of five, as public Receive
/// shows yours (a tap copies the whole; no QR, user: "i don't know why we
/// need the qr code"), and the foot: "New address" grey at the leading
/// edge, "Share" pink at the trailing. No helper text.
///
/// While it shows, every fresh address is looked at every 15 s
/// (`FreshReceive.check`); what arrived moves into your private balance by
/// itself. Sepolia only, DEBUG builds only (`PrivateMove.available`).
struct MoveFreshSentence<Head: View>: View {
    var inTray = false
    /// "your private balance" tapped: back to Receive's "on" list.
    var leave: () -> Void = {}
    /// Pay the gas (prd §1779): Send, filled with this address and the ETH
    /// it is short of. Nil where no account of yours can pay (Move with no
    /// account yet): the row is not drawn, never a dead control (§83).
    var payGas: ((_ address: String, _ eth: String) -> Void)? = nil
    @ViewBuilder let head: () -> Head

    @State private var copied = false
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
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                // **MOVE'S LAYOUT (prd §1803, as §1794, §1801):** the verb is
                // the title, the rows and the address stand under it, and the
                // sentence stands over the button.
                head()
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    // Its one network, said as a row and fixed (prd §1802).
                    MoveChoiceRows(rows: [MoveChoiceRow(id: "network", name: String(localized: "Network"), value: network.name,
                                                        mark: MoveSentence.networkMark(chainId: 1).map { MoveRowMark(network: $0) },
                                                        fixed: true) {}],
                                   open: .constant(nil)) { _ in EmptyView() }
                    if let entry {
                        // Named for what it is (prd §1803): good once.
                        VStack(alignment: .leading, spacing: DS.Space.s2) {
                            Text("One-time address").dsText(.body17).foregroundStyle(DS.textSecondary)
                            code(entry.address)
                        }
                        VStack(alignment: .leading, spacing: 0) {
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
                            ShareLink(item: entry.address) {
                                MoveVerbRowLabel(title: String(localized: "Share"), glyph: "square.and.arrow.up")
                            }
                            .buttonStyle(RowPress())
                        }
                    }
                    // One line, only when there is something to say.
                    line
                    // **A WAY ON FROM "NEEDS A LITTLE PRIVATE ETH" (prd §1779; user,
                    // of a tester's 1,000 USDC: "do 1 and 2 before we ship").** A
                    // new account has no private ETH to pay with, so the line was
                    // a dead end. Your account can pay it: one send, yours to
                    // confirm, and the line under it says what that costs you.
                    // A failed token move short of gas takes the same row (prd
                    // §1823): its private ETH could not pay, your account can.
                    if let entry, let payGas, waitsForGas(entry), !DemoMode.isActive {
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
                .padding(.top, DS.Space.s6)
            }
            .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
            .padding(.top, inTray ? DS.Space.s2 : DS.Space.s6)
            .padding(.bottom, DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { foot }
        .animation(DS.Motion.standard, value: entry)
        // The rows, the address and the sentence need the tall sheet.
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
            // tried again); then every 15 s while the sentence shows.
            // The ASP is asked too, so "being checked" turns to
            // "private now" here as it does in Holdings (the store spaces
            // its asks 20 s).
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

    /// The address in groups of five, as public Receive shows yours; a tap
    /// copies the whole (prd §1719: no QR).
    private func code(_ address: String) -> some View {
        Button { copy(address) } label: { AddressGroupsGrid(address: address) }
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
        } else if let entry, let said = words(entry.state, symbol: entry.token) {
            Text(verbatim: said.0).dsText(.body17).foregroundStyle(said.1)
                .fixedSize(horizontal: false, vertical: true)
        } else if entry != nil {
            // Before anything arrives (prd §1779): the address is a plain
            // one, good on every network of its kind, and only this network
            // is watched. And a token cannot pay its own gas: sent alone it
            // waits (a tester's 1,000 USDC, 2026-11-13).
            Text("On the \(network.name) network only. Any token but ETH needs a little ETH sent with it.")
                .dsText(.body17).foregroundStyle(DS.attentionInk)
                .fixedSize(horizontal: false, vertical: true)
        }
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

    /// The sentence over the button (prd §1794, §1803), then Back and the
    /// one act, Copy address; "New address" and "Share" are rows above.
    private var foot: some View {
        VStack(spacing: 0) {
            MoveFlow {
                MoveWord(String(localized: "Receive"), ink: DS.textPrimary)
                MovePhrase(String(localized: "your private balance"), glue: String(localized: "to"), ink: DS.textPrimary)
                MovePhrase(network.name, glue: String(localized: "on"))
                if let entry {
                    MovePhrase(YourAccount.short(entry.address) + ".", glue: String(localized: "at"), ink: DS.textPrimary)
                }
            }
            // The sentence is no control (prd §1781).
            .allowsHitTesting(false)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, DS.Space.s3)
            HStack(alignment: .center, spacing: DS.Space.s2) {
                // Back to where it was picked, never Move's menu (prd §1803).
                MoveBackCard(act: leave, disabled: moving)
                if let entry {
                    Button { copy(entry.address) } label: {
                        MoveSentence.actCard(copied ? String(localized: "Copied") : String(localized: "Copy address"), on: true)
                    }
                    .buttonStyle(PressSpring())
                } else {
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
        .padding(.bottom, DS.Space.s2)
        .background { if inTray { DS.surfaceSheet } else { DSPageBackground() } }
    }
}
