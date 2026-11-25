import Foundation

/// **THE MAC CARRIES NO WALLET (prd §1893, user, 2026-11-18: "remove wallet
/// from mac").** The Mac's last build is a reader of what syncs from the
/// phone — Activity, Apps, Notes, Settings — and nothing that holds, reads or
/// moves money: no Home, no Move, no wallet app, row, sheet act, widget,
/// notification or background read. Apple keeps the Mac version on the store
/// with the iPhone's (one record, builds uploaded), and a frozen build's money
/// acts would start and fail as keys and services drift, so the Mac has none.
///
/// One fact, fixed per build, read wherever a wallet door or job lives. Not a
/// switch: no build turns it back on (App Review 2.3.1).
enum WalletHere {
    static let isOn: Bool = {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return true
        #endif
    }()

    /// A source that stands in the wallet: the Wallet room, Markets, or any app
    /// the catalogue files under Wallet.
    @MainActor static func isWalletSource(_ source: String) -> Bool {
        if source == CategoryFold.walletRoom || HomeScope.isMarkets(source) { return true }
        guard let category = BridgeCatalog.category(forSource: source) else { return false }
        return category == CategoryFold.walletCategory
    }
}
