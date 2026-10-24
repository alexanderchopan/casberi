import SwiftUI

/// **TOR, SAID WHERE THE KEYS ARE (prd §1495; a Keys row since §1496).** Not a setting and not optional
/// (user: "it shouldn't be optional it should be default"), and said in Your
/// account as a thing already on (user: "i DO want something in Your account
/// to say Tor tho, but can be like it's already on"): a Keys row named Tor
/// (`MoveSecurity`), its state word trailing where a setting's would, no
/// line (§1496: the page's rows carry none), and nothing presses — a switch
/// that cannot turn off would be the fake control §83 bans. Where Tor
/// cannot connect, the wallets wait on their last readings, stamped (prd
/// §825), and the row says so. The proof is What this app reaches, which
/// counts per service what actually went through Tor.
enum TorFact {
    /// The state, where a setting's value stands.
    static func word(_ state: TorStatus.State) -> String {
        switch state {
        case .idle, .ready: String(localized: "On")
        case .connecting: String(localized: "Connecting")
        case .failed: String(localized: "Can't connect")
        case .unavailable: String(localized: "Not on Mac")
        }
    }

    /// A status word takes the ink (prd §1004): on is confirmed, a failure
    /// asks for attention, the rest are plain.
    static func ink(_ state: TorStatus.State) -> Color {
        switch state {
        case .idle, .ready: DS.confirmInk
        case .failed: DS.attentionInk
        case .connecting, .unavailable: DS.textSecondary
        }
    }
}
