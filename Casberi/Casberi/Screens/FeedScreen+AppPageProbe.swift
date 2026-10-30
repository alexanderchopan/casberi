import SwiftUI

/// **THE APP-PAGE SWEEP'S EYES (prd §1622, user: "Yes, add it" to a nightly
/// sweep of every app page).** `-appPageProbe YES` logs one line per page
/// once it settles — which app it is, which tile actually showed, how many
/// rows it holds, whether Holdings stands empty — so
/// `scripts/app-pages-sweep.sh` can fail a page that landed wrong or empty
/// without anyone looking at a screenshot. The Wallet's app pages regressed
/// for four weeks because no check ever opened one (§1618).
///
/// `appPage| <room> | pick=<app> | tile=<raw> | rows=<n> | held=<empty|full|->`
extension FeedScreen {
    @ViewBuilder
    func appPageProbe(_ visible: [Thing]) -> some View {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "appPageProbe") {
            let line = appPageLine(visible)
            Color.clear
                .frame(width: 0, height: 0)
                .task(id: line) {
                    // The line as the page settles, not as it mounts.
                    try? await Task.sleep(for: .seconds(2))
                    NSLog("[Casberi] appPage| %@", line)
                }
        }
        #endif
    }

    #if DEBUG
    private func appPageLine(_ visible: [Thing]) -> String {
        let pick = selectedSeat?.name ?? roomPick ?? "-"
        var tile = "-"
        var held = "-"
        if source == CategoryFold.walletRoom {
            let inert: Set<WalletSection> = selectedSeat != nil
                ? walletInertSections(visible: visible, upcoming: walletUpcoming(visible)) : []
            let shown = chrome.walletSection.flatMap { inert.contains($0) ? nil : $0 } ?? .home
            tile = shown.rawValue
            if shown == .holdings {
                held = walletScopeIsEmpty(.holdings) && walletSeatHeld(visible).isEmpty ? "empty" : "full"
            }
        }
        return "\(source) | pick=\(pick) | tile=\(tile) | rows=\(visible.live.count) | held=\(held)"
    }
    #endif
}
