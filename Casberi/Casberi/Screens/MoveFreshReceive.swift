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
    /// it is short of.
    var payGas: (_ address: String, _ eth: String) -> Void = { _, _ in }
    @ViewBuilder let head: () -> Head

    @State private var copied = false
    @State private var reading = false
    @Environment(\.modelContext) private var context
    private var book: FreshReceive { .shared }
    private var entry: FreshAddress.Entry? { book.current }

    private var moving: Bool {
        if case .moving = entry?.state { true } else { false }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                // Receive is Move's verb word (`head`), the sentence's first
                // (prd §1681).
                MoveFlow {
                    head()
                    MoveWordsClause(glue: String(localized: "to"), words: String(localized: "your private balance"),
                                    ink: moving ? DS.textPrimary : DS.pickInk,
                                    action: { if !moving { leave() } },
                                    hint: Text("Picks where it lands"))
                    MovePhrase(network.name, glue: String(localized: "on"))
                    if let entry {
                        MoveClause(glue: String(localized: "at")) {
                            Button { copy(entry.address) } label: {
                                MoveWord(copied ? String(localized: "Copied") : YourAccount.short(entry.address) + ".", ink: DS.textPrimary)
                            }
                            .buttonStyle(RowPress())
                            .accessibilityLabel(Text("The new address, \(entry.address)"))
                            .accessibilityHint(Text("Copies the address"))
                        }
                    }
                }
                // The line stands over the code, where it is seen: under
                // it, a phone's foot covers it until scrolled.
                line
                    .padding(.top, DS.Space.s2)
                // **A WAY ON FROM "NEEDS A LITTLE PRIVATE ETH" (prd §1779; user,
                // of a tester's 1,000 USDC: "do 1 and 2 before we ship").** A
                // new account has no private ETH to pay with, so the line was
                // a dead end. Your account can pay it: one send, yours to
                // confirm, and the line under it says what that costs you.
                if let entry, case .needsGas = entry.state, !DemoMode.isActive {
                    DSDoorRow(icon: "fuelpump", title: Text(reading ? "Reading the fee…" : "Pay the gas")) {
                        guard !reading else { return }
                        reading = true
                        Task {
                            let eth = await book.gasToPay(entry)
                            reading = false
                            if let eth { payGas(entry.address, eth) }
                        }
                    }
                    .padding(.top, DS.Space.s2)
                    DSFootnote("From your account, in the open. It links this address to you.")
                }
                if let entry {
                    code(entry.address)
                        .padding(.top, DS.Space.s4)
                }
            }
            .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
            .padding(.top, inTray ? DS.Space.s2 : DS.Space.s6)
            .padding(.bottom, DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { foot }
        .animation(DS.Motion.standard, value: entry)
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
            // The ASP is asked too, so "Waiting for approval" turns to
            // "private now" here as it does in Holdings (the store spaces
            // its asks 20 s).
            await book.check(context: context, force: true)
            await PrivateMoneyStore.shared.refresh(force: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                await book.check(context: context)
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
            Text("On \(network.name) only. Any token but ETH needs a little ETH sent with it.")
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
        case .moved(let amount, let tx):
            switch PrivateMoneyStore.shared.notes.first(where: { $0.tx == tx })?.status {
            case .approved: return (String(localized: "\(figure(amount)) private now"), DS.confirmInk)
            case .rejected: return (String(localized: "\(figure(amount)) not approved"), DS.destructiveInk)
            default: return (String(localized: "\(figure(amount)) moving in · Waiting for approval"), DS.attentionInk)
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

    /// "New address" grey, leading; "Share" pink, trailing.
    private var foot: some View {
        HStack(alignment: .firstTextBaseline) {
            Button {
                DSHaptic.selection()
                withAnimation(DS.Motion.standard) {
                    copied = false
                    book.make()
                }
            } label: {
                Text("New address").dsText(.heading24).foregroundStyle(DS.textSecondary).frame(minHeight: 48)
            }
            .buttonStyle(RowPress())
            .disabled(moving || DemoMode.isActive)
            Spacer(minLength: DS.Space.s3)
            if let entry {
                ShareLink(item: entry.address) {
                    Text("Share")
                        .dsText(.heading34)
                        .foregroundStyle(DS.pickInk)
                        .frame(minHeight: 48, alignment: .trailing)
                }
                .buttonStyle(RowPress())
            }
        }
        .padding(.horizontal, inTray ? DSRoomChassis.leadInset - DS.Space.s4 : DSRoomChassis.leadInset)
        .padding(.bottom, DS.Space.s2)
        .background { if inTray { DS.surfaceSheet } else { DSPageBackground() } }
    }
}
