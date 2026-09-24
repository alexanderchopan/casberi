import SwiftUI
import SwiftData

/// The Frames devnet, on the account page — chain 81410, the reference test
/// network for EIP-8141 frame transactions (prd §548).
///
/// **ON `AccountPage` SINCE §639 (2026-09-06)**, with its three siblings —
/// one anatomy, and it is the chassis's now rather than four screens agreeing.
/// What is still this file's is the data: the measured examples, the RPC, and
/// this phone's own key row.
///
/// **THE ACCOUNT ACT MOVED TO THE ROOM (2026-09-04).** This screen made the
/// key, on the measurement that a chain four days old holds 18 addresses and
/// so a pasted stranger shows almost nothing, making "create an account" the
/// common path. That measurement stands and the placement no longer follows
/// from it: §553 gives the room a permanent Send half, §594 moved vibenet's
/// four acts to Home for the same reason, and the faucet door left this screen
/// on 2026-09-01 because Top up already lives there — so keeping Create here
/// left ONE of a chain's three acts on the setup page, which is the split that
/// makes neither place read as the real one (§190). What remains is a row that
/// offers to WATCH the key once it exists, which is this page's own verb.
struct FramesScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(\.modelContext) private var modelContext

    @Bindable private var watch = FramesWatch.shared
    @State private var keyAddress: String? = FramesKey.address()

    /// The read that follows a watch, reported here (prd §618). Reached = the
    /// sweep stamped a new `readAt`; the demo reaches nothing and is not a
    /// failure.
    @State private var reader = DevnetReader(name: FramesIdentity.source) {
        guard !DemoMode.isActive else { return true }
        let before = FramesLiveState.shared.readAt
        await FramesLiveState.shared.refresh()
        return FramesLiveState.shared.readAt != before
    }

    /// The page's one bar (§639 amendment) — adds an address, filters the
    /// roster underneath.
    @State private var typed = ""
    @State private var sheet: AccountPageSheet?
    @State private var roster = DevnetRosterReader(seatID: FramesIdentity.seatID,
                                                   source: FramesIdentity.source)

    private static let mark = DS.brandHue(for: FramesIdentity.source) ?? DS.tint

    // WATCHING, not owning a key (prd §618). `|| keyAddress != nil` made the
    // header pour and the room door open an EMPTY room for somebody who had
    // made a key and watched nothing — a door onto nothing worth seeing (§83).
    // Disconnect never touched the key, so nothing else needed the key to
    // count as connected.
    private var connected: Bool { watch.connected }

    var body: some View {
        AccountPage(
            name: FramesIdentity.source, seatID: FramesIdentity.seatID,
            source: FramesIdentity.source,
            state: AccountPageState.of(name: FramesIdentity.source,
                                       seatID: FramesIdentity.seatID,
                                       connected: connected, store: store),
            mode: .noAccount,
            rows: roster.rows,
            query: typed,
            onRemoveRow: unwatch,
            teardown: { FramesBridge.disconnect(store: store) },
            sheet: $sheet,
            act: {
                DevnetAccountsAct(
                    watch: watch,
                    tint: Self.mark,
                    examples: Self.examples,
                    // Offered only once the key exists — making one is the
                    // room's act now, so this is never a door onto a first
                    // step that is somewhere else.
                    mine: keyAddress,
                    mineDetail: String(localized: "The key that signs here"),
                    peek: { await DevnetPeek.read($0, via: FramesRPC.call(method:params:)) },
                    reader: reader,
                    register: { FramesBridge.registerBridge(store: store) },
                    typed: $typed,
                    onWatched: { _ in readRows() })
            },
            more: {
                // THE ONE GRAY SENTENCE (§315's budget), spent on the fact that
                // changes what somebody would DO rather than on the pitch: this
                // network says of itself that it may be reset without notice,
                // so an account here is not somewhere to keep anything.
                // **THE PASSKEY ACCOUNT (prd §728d)** — the one account this
                // seat can make whose key never exists as bytes.
                FramesPasskeyRow(onChange: {
                    FramesBridge.registerBridge(store: store)
                    readRows()
                })
                DSSlabNote(text: String(localized: "Test ETH has no value, and the network may be reset without notice."), plain: true)
                DevnetExplorerRow(url: FramesIdentity.explorer, plain: true)
            },
            keySheet: { EmptyView() }
        )
        .onAppear { readRows() }
        .onChange(of: watch.addresses) { _, _ in readRows() }
    }

    private func readRows() {
        Task {
            await roster.refresh(watch: watch, context: modelContext,
                                 peek: { await DevnetPeek.read($0, via: FramesRPC.call(method:params:)) })
        }
    }

    /// ONE verb, "Remove" (§639), replacing `DevnetWatchingSection`'s own.
    private func unwatch(_ address: String) {
        watch.remove(address)
        roster.forget(address)
        FramesBridge.registerBridge(store: store)
        readRows()
    }

    private static let examples = FramesExample.all

    // NO ROUTE ON A WATCH (prd §618) — the Activity row is the way on, and the
    // read reports here, on the page the person is still looking at.
}

/// The addresses worth offering, and there are only two worth offering.
///
/// **Measured 2026-09-01 across the chain's whole history**: 5 type-`0x06`
/// transactions from 4 senders. These two are the only addresses that have
/// sent more than one thing, so they are the only ones whose room has more
/// than a single row in it. Everything else on this chain is a genesis
/// fixture or an address the faucet paid once.
///
/// A namespace rather than a type of its own since 2026-09-04 — the row shape
/// is `DevnetExample` now, shared with the three sibling devnets. The name
/// survives because `FeedScreen` reads this table to title a frame
/// transaction's counterparty.
enum FramesExample {
    static let all: [DevnetExample] = [
        DevnetExample(address: "0x80cfe5da326d0ab7a1d2ffc61745c57885dc2e32",
                      title: String(localized: "An address that sent twice"),
                      detail: String(localized: "Two frame transactions")),
        DevnetExample(address: "0x333ea8dfbb78bf478c52fd6e1a8aa659db873a0d",
                      title: String(localized: "A two-frame transfer"),
                      detail: String(localized: "A verify frame and a sender frame")),
    ]
}

/// **A PASSKEY ACCOUNT (prd §728d)** — make one, see its address, delete its key.
///
/// It is an ACCOUNT rather than a second key for the account you have: an
/// ordinary address can only be authorised by secp256k1, so a P-256 key needs
/// an account whose code accepts it (`FramesPasskeyAccount`). Making it costs
/// nothing on chain — the address is fixed before the code exists — so this
/// row makes the key, names the address and watches it; the code goes on with
/// its first send.
///
/// **Disabled with its reason, never hidden, on a device with no Secure
/// Enclave** — every simulator. A control that does nothing there is §83's
/// dead control; a row that vanished would leave nobody able to learn the
/// seat can do this.
struct FramesPasskeyRow: View {
    let onChange: () -> Void

    @State private var address: String? = FramesPasskey.accountAddress()
    @State private var errorText: String?
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if let address {
                HStack(spacing: DS.Space.s3) {
                    WalletFace(address: address, size: DS.Face.list, circular: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Passkey account"))
                            .dsText(.body17)
                            .foregroundStyle(DS.textPrimary)
                        Text(WalletStore.shortAddress(address))
                            .dsText(.label12).foregroundStyle(DS.textTertiary)
                    }
                    Spacer(minLength: DS.Space.s2)
                    Menu {
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Text(String(localized: "Delete the passkey"))
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .dsGlyph(.subhead, weight: .semibold)
                            .foregroundStyle(DS.textSecondary)
                            .frame(width: DS.Hit.min, height: DS.Hit.min)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(Text(String(localized: "Passkey account options")))
                }
                DSFootnote(prose: String(localized: "Pick it on the room's face rail and Send signs with Face ID. Its code goes on-chain with its first send."))
            } else {
                Button {
                    DSHaptic.selection()
                    create()
                } label: {
                    HStack(spacing: DS.Space.s2) {
                        Image(systemName: "person.badge.key")
                            .dsGlyph(.subhead, weight: .semibold)
                            .accessibilityHidden(true)
                        Text(String(localized: "Create a passkey account"))
                    }
                    .dsText(.body17)
                    .foregroundStyle(FramesPasskey.enclaveAvailable ? DS.tint : DS.textTertiary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!FramesPasskey.enclaveAvailable)
                DSFootnote(prose: FramesPasskey.enclaveAvailable
                     ? String(localized: "Signed by a key in this phone's Secure Enclave, which never leaves it.")
                     : String(localized: "Needs a device with a Secure Enclave. This one has none."))
            }
            if let errorText {
                Text(errorText)
                    .dsText(.label12).foregroundStyle(DS.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .confirmationDialog(String(localized: "Delete the passkey?"),
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(String(localized: "Delete the passkey"), role: .destructive) {
                FramesPasskey.delete()
                address = nil
                onChange()
            }
        } message: {
            Text(String(localized: "The account keeps its address and its test ETH, and nothing can sign for it again."))
        }
    }

    private func create() {
        do {
            let made = try FramesPasskey.create()
            // Named BEFORE it is watched, so the watch list keeps the name
            // rather than writing the short address over it.
            AddressBook.shared.setName(String(localized: "Passkey account"), for: made,
                                       networks: [AddressBook.Network.frames])
            FramesWatch.shared.add(made)
            address = made
            errorText = nil
            onChange()
            Task { await FramesLiveState.shared.refresh() }
        } catch let failure as FramesPasskey.Failure {
            switch failure {
            case .noEnclave:     errorText = String(localized: "This device has no Secure Enclave.")
            case .noBiometry:    errorText = String(localized: "Set up Face ID or Touch ID first — the key needs it to sign.")
            case .alreadyExists: errorText = String(localized: "There is already a passkey on this phone.")
            default:             errorText = String(localized: "Couldn't make the key.")
            }
        } catch {
            errorText = String(localized: "Couldn't make the key.")
        }
    }
}
