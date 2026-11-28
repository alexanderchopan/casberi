import SwiftUI

/// **A TACIT FARM YOU ARE IN STOPS PAYING (prd §2006),** in Needs you: the
/// pair, when its rewards end, and Withdraw, which opens the farm's own
/// Withdraw in Move. A week ahead, and after, while you are still in.
struct WalletFarmAsks: View {
    @Environment(ShellChrome.self) private var chrome

    var body: some View {
        let asks = TacitAccount.shared.farmAsks
        if !asks.isEmpty {
            Section {
                ForEach(asks) { ask in
                    DSPushRow(title: Text("\(ask.pair) farm"),
                              subtitle: Text(verbatim: TacitFarms.askLine(ask) + " · ") + Text("Withdraw").foregroundStyle(DS.pickInk),
                              subtitleTone: DS.textSecondary) {
                        DSHaptic.selection()
                        chrome.moveTacitFarm = ask.lpAsset
                        chrome.moveTray = true
                    } leading: {
                        AssetMark(name: ask.pair, size: DS.Mark.row)
                    }
                    .walletListRow()
                }
            }
        }
    }
}
