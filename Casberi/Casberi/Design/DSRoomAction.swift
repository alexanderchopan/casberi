import Foundation

/// **A ROOM'S ACT (prd §1107):** the Wallet's "Follow a wallet", a devnet's
/// "New account". It led the account pill's list until prd §1133 deleted the
/// pill; it leads the room's folder in the rooms tray now, first and never
/// last, because the folder can run long.
struct DSRoomAction {
    let title: String
    let symbol: String
    let run: () -> Void
}
