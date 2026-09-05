import SwiftUI

/// Ethrex Privacy, connected — chain 8141, the third ethrex devnet (prd §593).
///
/// **ONE ANATOMY WITH ITS THREE SIBLINGS (user, 2026-09-04).** Header, room
/// door, the accounts slab — paste field at the top, examples under it — the
/// screen's one sentence, the explorer, Disconnect. What differs between the
/// four devnet seats is the data: the mark, the measured examples and the
/// claim each makes, the sentence. `DevnetAccounts.swift` carries the whole
/// argument.
///
/// **The examples are load-bearing here in a way they are not on the siblings.**
/// This chain holds 14 type-`0x6` transactions across ~14,000 blocks, and only
/// FOUR of them reference a root. So a pasted stranger's address shows a
/// correct blank that reads exactly like a broken feature, and the honest fix
/// is to hand somebody an address that has something to show. Both below are
/// real and were read off `rpc1.privacy.ethrex.xyz` on 2026-09-04.
///
/// **THE SEAT MAKES A KEY AND SENDS SINCE §593c, AND THE ACTS ARE NOT HERE.**
/// This paragraph said the opposite until §593d — that the envelope was
/// unreproduced so there was no account act to offer — which stopped being
/// true the day the node taught us its field order. The acts live in the
/// ROOM, on Home, because §594's line is that an act which WRITES to the chain
/// moves to Home and an act that changes WHAT YOU ARE LOOKING AT stays with
/// the view. Watching an address changes the roster, not the chain, so it
/// stays here.
///
/// **This screen is the CONNECT ACT and nothing else (prd §465)** — what you do
/// ONCE. The room keeps what you do repeatedly.
struct PrivacyDevnetScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(HomeRoute.self) private var route
    @Environment(ShellChrome.self) private var chrome

    @Bindable private var watch = PrivacyDevnetWatch.shared

    private static let mark = DS.brandHue(for: PrivacyDevnetIdentity.source) ?? DS.tint

    private var connected: Bool { watch.connected }

    var body: some View {
        BridgeSetupPage(name: PrivacyDevnetIdentity.source, computedTitle: PrivacyDevnetIdentity.source) {
            BridgeSetupHeader(
                name: PrivacyDevnetIdentity.source,
                mode: .noAccount,
                // ACTION, not a re-pitch: you reach this from the product page,
                // which has just said what the chain is. One sentence, §315.
                intro: "Paste an address to watch, or start with one that already has something to show.",
                connected: connected)

            if connected {
                RoomDoor(name: PrivacyDevnetIdentity.source,
                         source: PrivacyDevnetIdentity.source)
                    .listRowSeparator(.hidden)
            }

            Section {
                DevnetAccountsSlab(
                    watch: watch,
                    tint: Self.mark,
                    examples: PrivacyDevnetExample.all,
                    idleNote: watch.addresses.isEmpty
                        ? String(localized: "Nothing is watched yet.") : nil,
                    register: { PrivacyDevnetBridge.registerBridge(store: store) },
                    onWatched: watched)
            }
            .dsSlabSection()
            .listRowSeparator(.hidden)

            if !watch.addresses.isEmpty {
                Section { DevnetWatchingSection(watch: watch) {
                    PrivacyDevnetBridge.registerBridge(store: store)
                } }
                .dsSlabSection()
                .listRowSeparator(.hidden)
            }

            // The seat's one §315 gray sentence, and it is spent on the thing
            // somebody would otherwise assume. "Privacy devnet" invites the
            // reading that watching here is private; it is not, and the chain
            // itself is the reason rather than any choice of ours.
            Section {
                DSSlabNote(text: String(localized: "Addresses on this chain are public — watching one is a read, and it hides nothing about you. Test ETH has no value, and the network may be reset without notice."))
            }
            .dsSlabSection()
            .listRowSeparator(.hidden)

            DevnetExplorerRow(url: PrivacyDevnetIdentity.explorer)
                .listRowSeparator(.hidden)

            if connected {
                BridgeDisconnectSection(
                    bridgeID: PrivacyDevnetIdentity.seatID,
                    name: PrivacyDevnetIdentity.source,
                    teardown: { PrivacyDevnetBridge.disconnect(store: store) }
                ).listRowSeparator(.hidden)
            }
        }
    }

    /// **ONLY THE FIRST WATCH ROUTES.** The room is a new place then, and going
    /// there is the point; on the second you are adding to a list you can see,
    /// and yanking it away is the 2026-08-28 vibenet report ("after you follow
    /// one address you can't choose any of the others").
    ///
    /// CLOSE, POP, ASK — `RoomDoor`'s order. This screen is RAISED as the
    /// connect sheet, so `route.path` is the stack behind it and a bare
    /// `sourceRequest` moves a room the form is still covering.
    private func watched(_ address: String) {
        guard watch.addresses.count == 1 else { return }
        route.closeConnectForm()
        route.path = []
        chrome.sourceRequest = PrivacyDevnetIdentity.source
    }
}

/// **THE TWO ADDRESSES THAT HAVE SOMETHING TO SHOW (prd §593d).**
///
/// Lifted out of `PrivacyDevnetScreen` because three surfaces need them now —
/// the connect screen's example rows, the send picker (which otherwise opens on
/// nothing to send TO, the dead end §83 bans wearing a picker's clothes), and
/// the ROOM'S OWN quiet state, which until §593d dead-ended somebody who
/// pasted an address of their own into "Nothing on this chain from the address
/// you watch, yet." with no next step anywhere on screen.
///
/// **Each is here for a DIFFERENT reading and both are MEASURED.** The pool
/// participant is the only one of the two whose transactions reference a root,
/// so watching it is the only way to see the Roots scope at all without waiting
/// for somebody else to use the chain. Read off `rpc1.privacy.ethrex.xyz` on
/// 2026-09-04, and re-confirmed the same day when the root storage derivation
/// was checked against live state.
enum PrivacyDevnetExample {
    static let all: [DevnetExample] = [
        DevnetExample(address: "0x062901d23f7e2d3bf9949c8a8cfd2c7a5ae3f980",
                      title: String(localized: "An address that used the pool"),
                      detail: String(localized: "One-time spend keys, and a proof")),
        DevnetExample(address: "0x248ac8584135c94469a90fbb02ba053b17f1cc60",
                      title: String(localized: "An address that sent early"),
                      detail: String(localized: "The chain's first hour")),
    ]
}
