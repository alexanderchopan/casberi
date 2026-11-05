import SwiftUI

/// **MONEY ON ITS WAY OUT OF AZTEC, IN NEEDS YOU (prd §1700b, §1700e).** One
/// row per Shield exit this phone sent that has not reached your account on
/// Ethereum: the amber clock and "On its way · since 2:14 PM" while Aztec's
/// proof travels (an hour or more), then the pink "Ready · Finish" once it is
/// on Ethereum. Finish is the portal's withdraw from your Safe
/// (`ShieldBridge.finish`: simulated, one Face ID). A row leaves once the
/// money is withdrawn, by you or by anyone (it can only go to you). Without
/// it, Finish lived only inside Move's Aztec sentence, an hour after you left.
struct WalletAztecExitAsks: View {
    @Environment(ShellChrome.self) private var chrome
    /// The exits Aztec's proof has reached Ethereum with, by transaction.
    @State private var ready: Set<String> = []
    @State private var finishing: String?

    var body: some View {
        let exits = AztecAccountStore.shared.pendingExits
        if !exits.isEmpty {
            Section {
                ForEach(exits) { exit in row(exit) }
            }
            .task(id: exits.map(\.id)) {
                // Where each stands on Ethereum, asked again while a row stands.
                guard AztecProver.isAvailable, !DemoMode.isActive else { return }
                while !AztecAccountStore.shared.pendingExits.isEmpty, !Task.isCancelled {
                    var now: Set<String> = []
                    for exit in AztecAccountStore.shared.pendingExits {
                        switch await ShieldBridge.state(of: exit) {
                        case .ready: now.insert(exit.id)
                        case .done: AztecAccountStore.shared.markExitWithdrawn(exit.transaction, withdrawal: "consumed")
                        case .waiting: break
                        }
                    }
                    if now != ready { ready = now; chrome.refreshRooms() }
                    try? await Task.sleep(for: .seconds(60))
                }
            }
        }
    }

    private func row(_ exit: AztecAccountStore.ShieldExit) -> some View {
        let isReady = ready.contains(exit.id)
        let working = finishing == exit.id
        let figure = BalancePrivacy.shared.amount(AztecAccountStore.figure(exit), unit: exit.symbol)
        let line: Text = isReady
            ? Text("Ready on Ethereum · ") + Text("Finish").foregroundStyle(DS.pickInk)
            : Text(verbatim: String(localized: "On its way") + " · " + PrivateMoney.since(exit.at, now: .now))
        return DSPushRow(title: Text("\(figure) out of Aztec"),
                         subtitle: working ? Text("Finishing…") : line,
                         subtitleTone: DS.textSecondary, busy: working, opens: false) {
            guard isReady, !working else { return }
            finish(exit)
        } leading: {
            ZStack {
                Color.clear.frame(width: DS.Face.row, height: DS.Face.row)
                Image(systemName: isReady ? "arrow.down.circle" : "clock")
                    .dsGlyph(.body, weight: .semibold)
                    .foregroundStyle(isReady ? DS.pickInk : DS.attention)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityHint(isReady ? Text("Withdraws it to your account") : Text(""))
        .walletListRow()
    }

    private func finish(_ exit: AztecAccountStore.ShieldExit) {
        finishing = exit.id
        Task {
            defer { finishing = nil }
            do {
                try await ShieldBridge.finish(exit) { _ in }
                if AztecAccountStore.shared.pendingExits.contains(where: { $0.id == exit.id }) {
                    chrome.flash(String(localized: "Sent, not yet seen"))
                } else {
                    DSHaptic.success()
                    chrome.flash(String(localized: "In your account"), tone: .success)
                }
                ready.remove(exit.id)
                chrome.refreshRooms()
            } catch {
                DSHaptic.failure()
                chrome.flash(error.localizedDescription)
            }
        }
    }
}
