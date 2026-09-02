import SwiftUI
import SwiftData

/// **VIBENET'S HOME IS TWO VERBS, AND BOTH OF THEM ACT HERE NOW
/// (prd §553b, 2026-09-01).**
///
/// This card has been wrong about its own faucet twice, in the same shape both
/// times, and the shape is worth naming before the code: **absence of a thing
/// where we happened to look was read as absence of the thing.**
///
/// §553 shipped the room with a Send half alone, on the finding that vibenet
/// "has nothing to top up from" — its faucet is a PAYER
/// (`VibenetSend.payerEndpoint`) that sponsors gas on a transaction somebody
/// else composed, and no endpoint in our bridge funds an address. True of our
/// bridge, false about the chain.
///
/// §553's amendment fixed that half — reported by the user in one line ("but
/// vibenet website does have a top up feature") — and shipped the verb as a
/// HAND-OFF that opened the faucet's own page, on a second finding: the page
/// is client-rendered, so nothing in its markup names the endpoint it calls.
/// True of the served HTML, false about the app, which is what the user
/// reported next: *"the top up redirects me to a new page in their explorer,
/// it doesn't top up in the app like hegota and frames do."*
///
/// The endpoint was in the page's own JS bundle, and one `curl` away on both
/// occasions: `POST api.vibes.base.org/api/vibenet/faucet/drip` with
/// `{"address": …}` — the same host this seat already posts to, so **no new
/// host joins the app's reach**. Measured against the live service the same
/// day; see `VibenetSend.claimFaucet` for the wire and
/// `HegotaFaucetVerdict.ofDrip` for what its three answers mean.
///
/// So the tile claims in place, exactly as Hegotá's and Frames' do, and
/// `DevnetSendPanel.TopUp.handsOff` — the outward-arrow flag §553's amendment
/// added for this one tile — is deleted with it, since a flag no caller can
/// set is a branch that cannot happen. Everything else is `HegotaSendCard`'s
/// shape exactly: see `DevnetSendConsole` for the panel, the sheet and the
/// keypad, and that file's header for why Home stopped holding a form.
///
/// **THE TILE IS NO LONGER GATED ON THE CONFIG'S `faucetAddress`.** §553's
/// amendment gated it there so a devnet that stopped running a faucet would
/// lose the half rather than keep a door onto a dead page — right about a
/// DOOR, wrong about a claim: the drip endpoint is the API's and has nothing
/// to do with the contract map, so the gate could only ever hide a working
/// verb on a sweep whose config read had not landed yet. A faucet that stops
/// answering now says so on tap, in its own words, which is the same thing
/// this tile does about every other refusal.
struct VibenetSendCard: View {
    /// The account this card spends from — an established one whose actor list
    /// names this phone's key, resolved by `FeedScreen` before the card mounts.
    /// It is also the address the faucet funds: the money has to land where
    /// the send spends from, or the crown moves and the form still cannot act.
    let account: Data
    /// Raise the send sheet. Owned by the screen: a `.sheet` attached to a view
    /// inside a `List` row resolves to the same presenting controller as the
    /// screen's own and half-opens then closes.
    var onSend: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(ShellChrome.self) private var chrome

    @State private var topUpBusy = false
    /// Only ever set by a tap. **Not pre-populated**, in the demo or anywhere
    /// else: a tile wearing a permanent grey sentence explains itself before
    /// anybody has asked, which is the standing helper-text ruling (§553 — a
    /// line survives only if it changes what someone would DO), and Hegotá
    /// says its own refusals ON TAP.
    @State private var topUpNote: String?

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")

    var body: some View {
        DevnetSendPanel(
            tint: Self.mark,
            topUp: .init(busy: topUpBusy, note: topUpNote, action: topUp),
            onSend: onSend)
    }

    // MARK: - Top up

    /// **THREE ENDINGS, AND ONLY ONE IS A FAULT** (§553's ruling for Hegotá,
    /// which holds here for the same reason). The cooldown and the unreachable
    /// case read the same way on purpose: no red, no alarm mark, a plain
    /// sentence in the tile's own empty top — because whichever it is, the next
    /// step is identical and it is to tap again.
    private func topUp() {
        // **THE TOUR DOES NOT LEAVE THE TOUR, AND IT DOES NOT SPEND EITHER.**
        // A claim here would put a real transaction on a public devnet from a
        // screen whose own banner reads "Demo — none of this is yours", and it
        // would spend the network's cooldown doing it. The tile stays present
        // and says why rather than vanishing: a half that disappears in the
        // demo makes the tour a different shape from the room it is a tour of.
        guard !DemoMode.isActive else {
            topUpNote = String(localized: "The faucet isn't asked in the demo.")
            return
        }
        topUpBusy = true
        topUpNote = nil
        Task { @MainActor in
            defer { topUpBusy = false }
            do {
                let claimed = try await VibenetSend.claimFaucet(for: account)
                VibenetSend.landClaimReceipt(txHash: claimed.transactionHash,
                                             account: account, in: modelContext)
                DSHaptic.success()
                // The pour IS the confirmation (§553) — `BerryRain` is mounted
                // once in `MainSurface` and driven by this counter, so a
                // success costs a bump rather than a view of its own. The
                // crown is the proof, and the pulse is what re-reads it: money
                // that arrived while the screen went on saying what it said
                // before is a top up that looks like it failed.
                chrome.refreshHue = Self.mark
                chrome.refreshPulse &+= 1
            } catch let refusal as VibenetSend.FaucetRefusal {
                topUpNote = Self.faucetNote(refusal.verdict)
            } catch {
                topUpNote = String(localized: "The faucet didn't answer. Tap to try again.")
            }
        }
    }

    /// **THE SENTENCES ARE THIS ROOM'S, NOT THE VERDICT'S.**
    /// `HegotaFaucetVerdict.sentence` words `rateLimited` as *"already claimed
    /// this hour"*, which is measured and correct for Hegotá and Frames and
    /// simply false here: vibenet's `faucet/status` reports a **ten-second**
    /// cooldown on the IP and on the address (measured 2026-09-01), so the
    /// shared sentence would send somebody away for an hour over a wait they
    /// could sit through. Sharing the CASE SET across three devnets is what
    /// keeps them saying the same four things; sharing the prose is what would
    /// make one of them lie.
    private static func faucetNote(_ verdict: HegotaFaucetVerdict) -> String {
        switch verdict {
        case .sent:
            return String(localized: "Claimed.")
        case .rateLimited:
            return String(localized: "Just claimed \u{2014} wait a few seconds and tap again.")
        case .refused(let why):
            return String(localized: "The faucet said no: \(why)")
        case .unreachable:
            return String(localized: "The faucet didn't answer. Tap to try again.")
        }
    }
}
