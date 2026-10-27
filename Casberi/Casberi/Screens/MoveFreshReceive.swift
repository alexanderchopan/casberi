import SwiftData
import SwiftUI

/// **RECEIVE, PRIVATELY: A FRESH ADDRESS (prd §1560; the board "Fresh").**
/// Receive's Private switch, on: the sentence
///
///     Receive on Sepolia privately.
///
/// over the switch (on, off returns to Receive), one line only when there is
/// something to say (what arrived, moving in, waiting for approval), then
/// the newest fresh address as a code and by its tail ("...e07a", a tap
/// copies the whole), and the foot: "New address" grey at the leading
/// edge, "Share" pink at the trailing. No helper text.
///
/// While it shows, every fresh address is looked at every 15 s
/// (`FreshReceive.check`); what arrived moves into your private balance by
/// itself. Sepolia only, DEBUG builds only (`PrivateMove.available`).
struct MoveFreshSentence<Head: View>: View {
    var inTray = false
    /// The switch turned off: back to Receive.
    var leave: () -> Void = {}
    @ViewBuilder let head: () -> Head

    @State private var copied = false
    @Environment(\.modelContext) private var context
    private var book: FreshReceive { .shared }
    private var entry: FreshAddress.Entry? { book.current }

    private var moving: Bool {
        if case .moving = entry?.state { true } else { false }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                head()
                    .padding(.bottom, DS.Space.s4)
                MoveFlow {
                    MovePhrase(String(localized: "Receive"))
                    MovePhrase(network.name, glue: String(localized: "on"))
                    MovePhrase(String(localized: "privately."), ink: DS.pickInk)
                }
                MovePrivateSwitch(isOn: Binding(get: { true }, set: { on in if !on { leave() } }))
                    .padding(.top, DS.Space.s4)
                    .disabled(moving)
                // The line stands over the code, where it is seen: under
                // it, a phone's foot covers it until scrolled.
                line
                    .padding(.top, DS.Space.s2)
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

    /// Where the address is shown: Ethereum, or Sepolia in a DEBUG build (prd §1567).
    private var network: PrivacyNetwork { book.network ?? .ethereum }

    /// The address as a code (EIP-681, naming its network, so a wallet that
    /// reads it pays on the right one) and by its tail.
    private func code(_ address: String) -> some View {
        VStack(spacing: DS.Space.s4) {
            if let image = SignerRequestSheet.code("ethereum:\(address)@\(network.chainId)") {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 156, height: 156)
                    .padding(DS.Space.s3)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: DS.Radius.widget))
                    .accessibilityLabel(Text("Code for the new address"))
            }
            Button {
                DSPasteboard.copy(address)
                DSHaptic.tap()
                withAnimation(DS.Motion.standard) { copied = true }
            } label: {
                Text(verbatim: copied ? String(localized: "Copied") : YourAccount.short(address))
                    .dsText(.body17)
                    .monospaced()
                    .foregroundStyle(DS.textPrimary)
                    .frame(minHeight: 44)
            }
            .buttonStyle(RowPress())
            .accessibilityLabel(Text("The new address, \(address)"))
            .accessibilityHint(Text("Copies the address"))
        }
        .frame(maxWidth: .infinity)
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
        }
    }

    private func words(_ state: FreshAddress.State, symbol: String) -> (String, Color)? {
        func figure(_ amount: String) -> String { PrivateMoney.figure(amount, decimals: symbol == "USDC" ? 6 : 18, symbol: symbol) }
        switch state {
        case .waiting:
            return nil
        case .moving(let amount):
            return (String(localized: "\(figure(amount)) arrived, moving in…"), DS.textSecondary)
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
