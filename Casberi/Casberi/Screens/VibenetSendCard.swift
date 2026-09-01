import SwiftUI
import SwiftData

/// **VIBENET'S HOME IS TWO VERBS TOO, AND THE SECOND ONE LEAVES THE APP
/// (prd §553 amendment, 2026-09-01).**
///
/// §553 shipped this room with a Send half alone, on the finding that vibenet
/// "has nothing to top up from": its faucet is a PAYER
/// (`VibenetSend.payerEndpoint`) that sponsors gas on a transaction somebody
/// else composed, and no endpoint funds an address. **That was true of the API
/// and false about the chain** — reported by the user in one line ("but vibenet
/// website does have a top up feature"), and it does: the devnet runs a faucet
/// page, and its own account console describes itself as *"fund them from the
/// faucet"*.
///
/// The mistake is worth naming because it is a shape, not a slip: absence of an
/// endpoint in OUR bridge was read as absence of the capability on the chain.
/// The app already knew better in two places — `VibenetAccountDetail` and
/// `VibenetRoomCard` have both offered a "Devnet faucet" door since this seat
/// shipped.
///
/// So the half is a HAND-OFF rather than a claim, which is exactly what
/// `DevnetSendPanel.TopUp.handsOff` was built for and what its outward arrow
/// says. Hegotá's claims in place because Hegotá has an endpoint; this one
/// opens the page because that is the whole of what can honestly happen. An
/// in-app claim stays unbuilt on purpose: the faucet page is client-rendered,
/// so nothing in its markup names the endpoint it calls, and guessing at one is
/// how a write path gets built against a shape nobody measured.
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

    @Environment(\.openURL) private var openURL

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")

    var body: some View {
        DevnetSendPanel(tint: Self.mark, topUp: topUp, onSend: onSend)
    }

    /// Only where the live config actually NAMED a faucet — the same gate the
    /// room's other two faucet doors already use. A devnet that stops running
    /// one should lose the half rather than keep a door onto a page that no
    /// longer funds anything.
    private var topUp: DevnetSendPanel.TopUp? {
        guard VibenetConfig.cached()?.faucetAddress != nil,
              let url = URL(string: VibenetExplorer.faucet) else { return nil }
        // **THE TOUR DOES NOT LEAVE THE TOUR (prd §553 amendment).** The demo's
        // own config fixture carries a `faucetAddress`, so this half draws there
        // — correctly, it is part of the room. But the ACTION would open a live
        // devnet faucet in Safari from a screen whose banner reads "Demo — none
        // of this is yours", and `HegotaSendCard` already refuses its own claim
        // in a demo with a sentence. Two rooms answering the same tap two
        // different ways is the gap; this closes it on Hegotá's terms.
        //
        // The tile stays present and says why rather than vanishing: a half
        // that disappears in the demo makes the tour a different shape from the
        // room it is a tour of, which is the whole thing demo parity is for.
        if DemoMode.isActive {
            return .init(note: String(localized: "The faucet isn't opened in the demo."),
                         handsOff: true) { }
        }
        return .init(handsOff: true) { openURL(url) }
    }
}
