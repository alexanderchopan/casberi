import SwiftUI

/// **TOR, SAID WHERE THE KEYS ARE (prd §1495).** Not a setting and not optional
/// (user: "it shouldn't be optional it should be default"), and said in Your
/// account as a thing already on (user: "i DO want something in Your account
/// to say Tor tho, but can be like it's already on"): the row is named Tor,
/// its state word trails where a setting's would, and nothing presses — a
/// switch that cannot turn off would be the fake control §83 bans. Where Tor
/// cannot connect, the wallets wait on their last readings, stamped (prd
/// §825), and the row says so. The proof is What this app reaches, which
/// counts per service what actually went through Tor.
struct TorFactRow: View {
    private var status: TorStatus { TorStatus.shared }

    var body: some View {
        let state = status.state
        HStack(spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Tor").dsText(.body17).foregroundStyle(DS.textPrimary)
                Text(verbatim: Self.line(state))
                    .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DS.Space.s2)
            Text(verbatim: Self.word(state))
                .dsText(.body17)
                .foregroundStyle(Self.ink(state))
                .lineLimit(1).fixedSize()
                .layoutPriority(1)
        }
        .walletRowPitch()
        .accessibilityElement(children: .combine)
    }

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

    static func line(_ state: TorStatus.State) -> String {
        switch state {
        case .unavailable:
            String(localized: "On this Mac, wallets are read directly · Tor isn't here yet")
        case .idle, .ready:
            String(localized: "Your wallets are read through Tor, so no service learns where you are or that they're yours")
        case .connecting(let progress):
            String(localized: "Your wallets are read once it connects · \(progress)%")
        case .failed:
            String(localized: "Your wallets show their last reading until it connects")
        }
    }
}
