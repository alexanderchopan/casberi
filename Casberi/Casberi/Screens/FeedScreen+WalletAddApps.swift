import SwiftUI

/// **ADD TO WALLET, AT HOLDINGS' FOOT (prd §1974 item 3, user: "not on home,
/// perhaps on holdings at the bottom. home already has an 'apps' link", then
/// "a row that looks just like it does in the apps section is better").**
/// A crypto user should not have to find the Wallet in Apps to learn what
/// the Wallet can hold. Under what you hold, one row as Apps draws a
/// category: "Add to Wallet", then the Wallet apps you have not added, A–Z,
/// as many as the line holds, "+N" for the rest. A tap opens Apps on the
/// Wallet folder, as the account menu's Connect an app does. Nothing is
/// drawn once every one is yours.
extension FeedScreen {
    /// The Wallet apps you could add, A–Z: the Wallet folder's, less yours.
    var walletAddableApps: [String] {
        let yours = Set(bridges.bridges.filter { $0.status != .paused }.map(\.name))
        return BridgeCatalog.offers
            .filter { BridgeCatalog.category(of: $0) == CategoryFold.walletCategory }
            .filter { SettingsHome.inLibrary($0) && !yours.contains($0.name) }
            .map(\.name)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    @ViewBuilder
    var walletAddApps: some View {
        let apps = walletAddableApps
        if !apps.isEmpty {
            Section {
                // Every icon lit: the row's words already say none is yours.
                SourcesCategoryRow(folder: .init(category: CategoryFold.walletCategory, apps: apps, have: 0),
                                   has: { _ in true }, needs: { _ in false },
                                   title: String(localized: "Add to Wallet"), nameColumn: 116) {
                    route.openCategory = CategoryFold.walletRoom
                    route.present(.apps)
                }
                .walletListRow()
            }
        }
    }
}
