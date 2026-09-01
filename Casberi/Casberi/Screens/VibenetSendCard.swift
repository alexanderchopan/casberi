import SwiftUI
import SwiftData

/// **VIBENET'S HOME IS ONE VERB, AND THAT IS A FINDING RATHER THAN A TRIM
/// (prd §551, 2026-09-01).**
///
/// The sibling room draws a split panel — Send above, Top up below — and this
/// one deliberately does not, because **vibenet has nothing to top up from.**
/// Its faucet is a PAYER: `VibenetSend.payerEndpoint` sponsors the gas on a
/// transaction somebody else composed. There is no endpoint an address can
/// claim funds from, and the console this room links to elsewhere
/// (`VibenetIdentity.console`) is documented in its own source as "the door for
/// everything this app deliberately does not do" — session keys and
/// sub-accounts, not a faucet.
///
/// So a Top up half here would open, say what it was for, and be unable to do
/// it: the dead control §83 bans, on the one screen where believing it is
/// expensive. The half is absent until there is something behind it.
///
/// Everything else is `HegotaSendCard`'s shape exactly — see
/// `DevnetSendConsole` for the panel, the sheet and the keypad, and that file's
/// header for why Home stopped holding a form.
struct VibenetSendCard: View {
    /// The account this card spends from — an established one whose actor list
    /// names this phone's key, resolved by `FeedScreen` before the card mounts.
    let account: Data
    /// Raise the send sheet. Owned by the screen: a `.sheet` attached to a view
    /// inside a `List` row resolves to the same presenting controller as the
    /// screen's own and half-opens then closes.
    var onSend: () -> Void = {}

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")

    var body: some View {
        DevnetSendPanel(tint: Self.mark, topUp: nil, onSend: onSend)
    }
}
