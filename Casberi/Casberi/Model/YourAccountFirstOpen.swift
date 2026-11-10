import UIKit

/// **YOUR ACCOUNT IS MADE WHEN YOU FIRST OPEN THE WALLET (prd §1741, user:
/// "we could also create account automatically for the user"; of the walk:
/// "behind the door is good").** A new person opened the Wallet onto a page
/// with nothing in it and a verb, and had to walk four steps before owning
/// an address. Now the first open of an EMPTY Wallet makes the account, as
/// `MoveScreen.create` does (`YourAccountKey.create` reaches no network, so
/// the account can receive at once and exists on chain at its first send),
/// and Home's door says "Finish setup" until the walk has been taken.
///
/// **Only on a Wallet with nothing in it, and once.** Someone who already
/// follows an account and never made their own chose that, so their door
/// stays "Create an account". An account waiting in iCloud Keychain to be
/// brought back is theirs to bring: nothing is made over it. And a phone
/// that cannot make the key (no passcode) is asked once, not at every open;
/// the door's verb still makes one by hand.
@MainActor
enum YourAccountFirstOpen {
    private static let triedKey = "yourAccount.firstOpen.tried.v1"
    private static func pendingKey(_ account: String) -> String {
        "yourAccount.firstOpen.setupPending." + account.lowercased()
    }

    /// Make the account if this is the first open of an empty Wallet.
    /// Returns the address made, nil when nothing was.
    @discardableResult
    static func makeIfFresh() -> String? {
        guard !DemoMode.isActive,
              YourAccountKey.address == nil,
              WalletStore.shared.addresses.isEmpty,
              !UserDefaults.standard.bool(forKey: triedKey),
              // Before the first unlock nothing saved can be read, so an
              // empty read proves nothing (prd §1361).
              UIApplication.shared.isProtectedDataAvailable,
              YourAccountRecovery.accounts().isEmpty
        else { return nil }
        UserDefaults.standard.set(true, forKey: triedKey)
        do {
            let made = try YourAccountKey.create()
            // Followed in the Wallet from the start, as a made account is.
            WalletStore.shared.add(made, label: WalletStore.yourAccountName)
            UserDefaults.standard.set(true, forKey: pendingKey(made))
            #if DEBUG
            NSLog("yourAccountFirstOpen| made %@", AddressTail.short(made))
            #endif
            return made
        } catch {
            #if DEBUG
            NSLog("yourAccountFirstOpen| failed: %@", String(describing: error))
            #endif
            return nil
        }
    }

    /// The walk has not been taken for an account made here: Home's door
    /// says "Finish setup" and opens the walk.
    static func setupPending(_ account: String) -> Bool {
        UserDefaults.standard.bool(forKey: pendingKey(account))
    }

    /// The walk ended, on Done or on Receive, or was put away unfinished
    /// (prd §1741b): the door is Your account again, and its word says what
    /// is still missing.
    static func walked(_ account: String) {
        UserDefaults.standard.removeObject(forKey: pendingKey(account))
    }
}
