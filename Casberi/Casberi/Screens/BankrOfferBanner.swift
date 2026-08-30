import SwiftUI

/// "ANY AGENT OFFCHAIN. BANKR ONCHAIN." (prd §529, 2026-08-29) — the one
/// sentence that says out loud there is a choice of agent, and the only place
/// this app promotes a single seat.
///
/// ## WHY A BANNER AND NOT A CATALOG TILE
///
/// Bankr already has a seat sixty-odd deep in the Agent group, and that is the
/// wrong shape for the one provider whose difference is a CAPABILITY rather
/// than a price: every other agent seat answers better, Bankr answers about
/// your wallet and — once you turn it on (§529) — acts. Somebody who never
/// opens the catalog can never learn that from the catalog.
///
/// ## ONE VIEW, TWO PLACEMENTS, ONE DISMISSAL
///
/// It draws in the risen agent (where "which agent am I talking to?" is the
/// live question) and at the head of the Wallet room (where an onchain agent
/// is the obvious next thing). **The dismissal is SHARED** — one
/// `@AppStorage` key read by every instance — because "not now" is an answer
/// about Bankr, not about a screen, and a banner that reappears somewhere else
/// after being waved off was never really dismissed.
///
/// Extracted rather than written twice for this project's standing reason: two
/// copies of one piece of copy drift, and then two surfaces make slightly
/// different promises about the same thing.
///
/// ## THREE WAYS IT RETIRES ITSELF
///
/// Chrome is priced by frequency of use (`AgentBar`'s rest ruling), and a
/// banner inside a surface you open to do something else is expensive. It goes
/// when Bankr is connected, when the person says Not now, and — by its
/// callers — when there is nothing for its door to open.
///
/// ## THE ON-DEVICE CLAUSE IS CONDITIONAL, AND THAT IS §83
///
/// Apple Intelligence is absent on most of the fleet, and "answers run on this
/// iPhone" printed over a device with no model is a fake status in the app's
/// own voice. When it is unavailable the sentence does not make the claim —
/// and the offer still stands on its own, because Bankr's pitch was never
/// "better than the local model", it was "reaches your wallet".
struct BankrOfferBanner: View {
    /// Opens Bankr's setup screen. Required, not optional: a banner whose CTA
    /// does nothing is the dead control §83 bans, so a caller with no door
    /// must not draw one.
    let onConnect: () -> Void

    @AppStorage(BankrOfferBanner.dismissedKey) private var dismissed = false

    /// The shared dismissal, as one string rather than three literals — the
    /// property wrapper above, `offers` below, and any future caller all name
    /// the same key by construction. A second spelling of it is a banner that
    /// is dismissed on one surface and not on another, which is precisely the
    /// thing this view exists as one copy to prevent.
    static let dismissedKey = "agent.bankrOfferDismissed"

    /// Whether this view would draw anything at all.
    ///
    /// **A CALLER IN A `List` MUST ASK BEFORE EMITTING A `Section`**, because
    /// a view that renders nothing is not a section that takes no room: an
    /// empty `Section` still takes the list's own spacing, so the Wallet room
    /// would keep a banner-shaped gap above its crown for everybody who had
    /// already waved the offer off. (That is this room's own lesson, recorded
    /// on the scope-visual slot: "an empty `Section` still takes list spacing,
    /// so a zero-height box is not an absent one.")
    ///
    /// It reads the SAME two facts the body does, in the same order, so the
    /// two can never disagree about whether there is anything to show.
    static var offers: Bool {
        !UserDefaults.standard.bool(forKey: dismissedKey)
            && !AgentKey.isConfigured(.bankr)
    }

    var body: some View {
        if !dismissed, !AgentKey.isConfigured(.bankr) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack(spacing: DS.Space.s2) {
                    // The mark, because the sentence names a product most
                    // people have not heard of. The seat's own bundled brand
                    // asset, so this claims nothing the catalog doesn't.
                    // `DS.Face.row`, not `DS.Mark.row` — the two are the same
                    // 26pt by construction, but `circular: true` makes this a
                    // FACE (it stands in the slot an avatar would), and the
                    // face ramp is the one that governs it. Not `rowCircle`:
                    // that rung is optical compensation for a circle in a
                    // MIXED column of squircle marks, and this one is alone
                    // beside a heading.
                    BridgeIcon(name: "Bankr", size: DS.Face.row, circular: true)
                    Text("Any agent offchain. Bankr onchain.")
                        .dsText(.heading17).foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(OnDeviceModel.isAvailable
                     ? "Answers run on \(DS.device), on your own things. Bankr reads your wallet and live markets — and acts onchain when you tell it to."
                     : "Bankr reads your wallet and live markets — and acts onchain when you tell it to.")
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: DS.Space.s3) {
                    Button {
                        DSHaptic.tap()
                        onConnect()
                    } label: {
                        Text("Set up Bankr")
                            .dsText(.subhead13).fontWeight(.semibold)
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, DS.Space.s4)
                            .padding(.vertical, DS.Space.s2)
                            .background(Capsule().fill(DS.tint))
                    }
                    .buttonStyle(.plain)
                    Button {
                        DSHaptic.tap()
                        dismissed = true
                    } label: {
                        Text("Not now")
                            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                            .padding(.vertical, DS.Space.s2)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
            .animation(DS.Motion.standard, value: dismissed)
        }
    }
}
