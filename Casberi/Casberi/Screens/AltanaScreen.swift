import SwiftUI
import SwiftData

/// Altana's keystore, connected — watch an account and see which credentials
/// are allowed to sign for it.
///
/// **Why this seat has a screen at all, amending prd §465 (2026-08-28).** That
/// ruling checked, rather than assumed, which seats own an address list, and
/// answered: exactly two, Wallet's and vibenet's — "Altana, Peer, Privacy
/// Pools, Railgun … own NO addresses, read the wallets you already watch, and
/// have no setup screen at all." True when written. What changed is not the
/// architecture but the DATA: measured 2026-08-28, the registry holds **39
/// keys across 9 accounts, every one of them somebody else's**. So the seat
/// gated on evidence (§403, and still right) shows a person with no registered
/// key exactly nothing, forever, with nothing on screen to say the registry
/// simply has not reached them yet. This screen is where the examples live.
///
/// **The addresses are Altana's own, not the wallet roster** — see
/// `AltanaWatch`'s header for the two reasons, of which the sharper is that
/// `WalletIngest.allChains` has no BNB entry, so an Altana account watched as
/// a wallet would spend one of five metered slots on a read that cannot see it.
///
/// **Watching lands you in the room** (§465's rule, and `VibenetScreen`'s
/// exact sequence): read first, then route, so the room is real when you get
/// there. Only the FIRST one routes — a second tap from the list a moment
/// later must not yank the list out from under the thumb still using it.
///
/// **The list stays after connecting, deliberately diverging from §465.** That
/// ruling moved vibenet's roster off setup because a roster is what you do
/// repeatedly and it had grown to any size. Altana's is bounded by the whole
/// registry — nine accounts today — so a second screen to hold nine rows would
/// be a door onto a list shorter than the door's own explanation.
struct AltanaScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(ShellChrome.self) private var chrome
    @Environment(HomeRoute.self) private var route
    @Environment(\.modelContext) private var modelContext

    @Bindable private var watch = AltanaWatch.shared
    private var connected: Bool { watch.connected }

    @State private var addressField = ""
    @FocusState private var fieldFocused: Bool
    @State private var discovered: [AltanaDiscoveredAccount] = []
    @State private var discoveryLoading = false
    @State private var discoveryAttempted = false
    /// The keystore read the connect act waits on.
    @State private var connecting = false
    /// Set when that read could not reach a registry at all. The account IS
    /// watched (the list is written first), so this says what happened rather
    /// than pretending the watch failed — and it keeps you here instead of
    /// routing into a room with no snapshot to compose from, which is the blank
    /// page this sequence exists to stop drawing.
    @State private var connectError: BridgeProof?

    private static let mark = DS.brandHue(for: "Altana") ?? Color.fixed("#3565e3")

    private var draft: String { addressField.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        BridgeSetupPage(name: "Altana") {
            BridgeSetupHeader(
                name: "Altana",
                mode: .noAccount,
                // ACTION, not a re-pitch: the product page one tap back just
                // said what Altana is and what it reads, and the mode chip
                // carries the cost. What is left is what to do here.
                intro: "Paste an account address, or watch one of the examples below.",
                connected: connected)

            if connecting || connectError != nil {
                Section {
                    BridgeSyncStatusRows(
                        syncing: connecting,
                        syncingLine: String(localized: "Reading the keystore…"),
                        proof: connectError)
                }
                .dsSlabSection()
                .listRowSeparator(.hidden)
            }

            if connected, !connecting {
                RoomDoor(name: "Altana", source: AltanaKeystore.source)
                    .listRowSeparator(.hidden)
            }

            if !connecting {
                Section { watchField }
                    .dsSlabSection()
                    .listRowSeparator(.hidden)

                Section { discoverySection }
                    .dsSlabSection()
                    .listRowSeparator(.hidden)
            }

            if connected, !connecting {
                // Drops the EXAMPLES and nothing else. `AltanaState` is
                // deliberately NOT cleared, unlike vibenet's teardown: this
                // seat also rides the wallets you watch, so wiping the snapshot
                // would delete a real wallet's own readings to remove somebody
                // else's example. `reconcileWalletSeats` then re-registers the
                // seat on the next pass if your own wallet still has evidence,
                // which is the correct outcome rather than a bug.
                BridgeDisconnectSection(
                    bridgeID: "altana", name: AltanaKeystore.source,
                    teardown: {
                        AltanaWatch.shared.removeAll()
                        store.reconcileWalletSeats()
                    }
                ).listRowSeparator(.hidden)
            }
        }
        .onAppear { if !discoveryAttempted { Task { await loadDiscovery() } } }
    }

    // MARK: - Paste

    private var watchField: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            DSSlabField(
                placeholder: String(localized: "0x… account address"),
                text: $addressField,
                actionLabel: String(localized: "Watch"),
                focus: $fieldFocused,
                isArmed: AltanaWatch.isValidAddress(draft),
                action: { watchTyped() })

            // No ENS resolve and no debounced round-trip, unlike
            // `WalletScreen.addressPreview`: 38 of the 39 measured keys are on
            // BNB and an ENS name resolves to a MAINNET address, so resolving
            // would quietly answer a different question than the one asked
            // (`AltanaWatch.isValidAddress`'s own doc).
            if let address = AltanaWatch.isValidAddress(draft) ? draft : nil {
                HStack(spacing: DS.Space.s2) {
                    WalletFace(address: address, size: DS.Face.row, circular: true)
                    Text(WalletStore.shortAddress(address))
                        .dsText(.label12).monospaced()
                        .foregroundStyle(DS.textSecondary)
                }
                .transition(.opacity)
            }
        }
        .animation(DS.Motion.standard, value: draft)
    }

    private func watchTyped() {
        let address = draft
        guard AltanaWatch.isValidAddress(address) else { return }
        DSHaptic.tap()
        guard watch.add(address) else { return }
        addressField = ""
        fieldFocused = false
        openRoom()
    }

    // MARK: - The examples

    /// Real accounts the registry actually holds, one tap to watch. Drawn
    /// whether or not anything is watched, for the reason in the type doc: the
    /// whole list is nine rows.
    @ViewBuilder
    private var discoverySection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if discoveryLoading {
                BridgeSyncStatusRows(
                    syncing: true,
                    syncingLine: String(localized: "Looking for accounts in the keystore…"),
                    proof: nil)
            } else if discovered.isEmpty, discoveryAttempted {
                Text("Couldn't reach the explorer to list accounts — paste an address above, or watch the example below.")
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
            } else if !discovered.isEmpty {
                Text(String(localized: "Accounts in the keystore"))
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(DS.textSecondary)
                ForEach(discovered) { account in
                    row(address: account.address, subtitle: nil)
                }
            }
            // Always offered, live listing or not — a real account, always
            // watchable, so nobody is left with a paste field for a registry
            // they hold no address for (`VibenetDiscoverySection`'s rule).
            if !discovered.contains(where: { $0.id == AltanaDiscovery.peekAddress.lowercased() }) {
                row(address: AltanaDiscovery.peekAddress,
                    subtitle: String(localized: "Peek at an example account"))
            }
        }
    }

    /// One row, shared by a listed account and the fixed peek — same face, same
    /// short-address line, same trailing verb, so the peek reads as one more
    /// real account rather than a special case.
    private func row(address: String, subtitle: String?) -> some View {
        let watching = watch.isWatching(address)
        return Button {
            guard !watching else { return }
            DSHaptic.tap()
            guard watch.add(address) else { return }
            openRoom()
        } label: {
            HStack(spacing: DS.Space.s2) {
                WalletFace(address: address, size: DS.Face.row, circular: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(watch.name(for: address) ?? WalletStore.shortAddress(address))
                        .dsText(.label12).monospaced()
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .dsText(.label11)
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: DS.Space.s2)
                // NEVER a count here. The explorer lists an account; it does
                // not tell us how many credentials it holds, and asking would
                // be one keystore read per suggested row bought to decorate a
                // list nobody may tap (`VibenetBridge.reference`'s refusal).
                Text(watching ? String(localized: "Watching") : String(localized: "Watch"))
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(watching ? DS.textTertiary : Self.mark)
                    .lineLimit(1)
                    .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(watching)
    }

    private func loadDiscovery() async {
        discoveryLoading = true
        discovered = await AltanaDiscovery.recentAccounts()
        discoveryLoading = false
        discoveryAttempted = true
    }

    // MARK: - Landing

    /// Land in the room the account just made real — READ FIRST, then route,
    /// `VibenetScreen.openRoom`'s sequence and for its reason: this room
    /// composes off the `AltanaState` snapshot the sweep writes, never a live
    /// read, so routing before a read drops you into a room with nothing to
    /// compose from and it draws NOTHING over the account you just watched.
    ///
    /// Re-entrant by the `connecting` guard rather than by luck: the list stays
    /// on screen, so a second tap must not start a second read and a second
    /// route.
    private func openRoom() {
        guard !connecting else { return }
        connectError = nil
        connecting = true
        Task {
            // `sync` saves the snapshot itself (`AltanaState.save`), which is
            // what the room composes from — nothing here needs its return
            // except to tell the two silences below apart.
            let landed = await AltanaKeystore.sync(context: modelContext)
            store.reconcileWalletSeats()
            connecting = false
            // A READ THAT FOUND NOTHING MUST NOT ROUTE. Unlike vibenet's, this
            // has two silences to tell apart and only one of them is trouble:
            // an account really holding no credential is a true answer, and
            // saying "couldn't reach" over it would be the §83 wrong answer.
            // `AltanaState.readings` is written by a read that ANSWERED, so its
            // emptiness is the reachability question and `landed` is the
            // did-it-hold-anything one.
            guard !AltanaState.readings.isEmpty else {
                connectError = .failed(String(localized: "Couldn't reach the keystore just now. The account is watched — its room fills in as soon as a read lands."))
                return
            }
            guard landed > 0 || AltanaState.readings.contains(where: { !$0.keys.isEmpty }) else {
                connectError = .failed(String(localized: "The keystore holds no credentials for that account. It stays watched — anything registered later lands here."))
                return
            }
            connectError = nil
            // CLOSE, POP, ASK — `RoomDoor`'s order. This screen is raised as
            // the connect form, so `route.path` is the stack behind it and
            // `sourceRequest` would move a room the form still covers.
            route.closeConnectForm()
            route.path = []
            chrome.sourceRequest = AltanaKeystore.source
        }
    }
}
