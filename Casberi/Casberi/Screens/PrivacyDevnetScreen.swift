import SwiftUI

/// Ethrex Privacy, connected — chain 8141, the third ethrex devnet (prd §593).
///
/// **THE WATCH FIELD LEADS, and that is a measurement rather than a taste.**
/// `FramesScreen` opens on "create an account" because its chain is days old
/// and holds almost nothing to look at. This screen cannot: the seat makes no
/// key at all while its type-`0x6` envelope is unreproduced (§593a), so there
/// is no account act to lead with. What it leads with instead is the two
/// addresses that really carry the reading — measured, not invented.
///
/// **The examples are load-bearing here in a way they are not on the siblings.**
/// This chain holds 14 type-`0x6` transactions across ~14,000 blocks, and only
/// FOUR of them reference a root. So a pasted stranger's address shows a
/// correct blank that reads exactly like a broken feature, and the honest fix
/// is to hand somebody an address that has something to show. Both below are
/// real and were read off `rpc1.privacy.ethrex.xyz` on 2026-09-04.
///
/// **This screen is the CONNECT ACT and nothing else (prd §465)** — what you do
/// ONCE. The room keeps what you do repeatedly.
struct PrivacyDevnetScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(HomeRoute.self) private var route
    @Environment(ShellChrome.self) private var chrome

    @Bindable private var watch = PrivacyDevnetWatch.shared

    @State private var typed = ""
    @State private var note: String?
    @State private var noteIsError = false

    private var connected: Bool { watch.connected }

    var body: some View {
        List {
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

            Section { watchField }
                .dsSlabSection()
                .listRowSeparator(.hidden)

            if !unwatchedExamples.isEmpty {
                Section { examples }
                    .dsSlabSection()
                    .listRowSeparator(.hidden)
            }

            if !watch.addresses.isEmpty {
                Section { roster }
                    .dsSlabSection()
                    .listRowSeparator(.hidden)
            }

            if connected {
                Section {
                    DSSlabDoor(title: String(localized: "Open the explorer"),
                               detail: String(localized: "Opens dora.privacy.ethrex.xyz")) {
                        DSHaptic.selection()
                        if let url = URL(string: PrivacyDevnetIdentity.explorer) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: DS.Space.s6, leading: DS.Space.s4,
                                          bottom: 0, trailing: DS.Space.s4))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                BridgeDisconnectSection(
                    bridgeID: PrivacyDevnetIdentity.seatID,
                    name: PrivacyDevnetIdentity.source,
                    teardown: { PrivacyDevnetBridge.disconnect(store: store) }
                ).listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: PrivacyDevnetIdentity.source)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle(PrivacyDevnetIdentity.source)
    }

    // MARK: - Watching

    @ViewBuilder private var watchField: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            BridgeFieldRow(placeholder: String(localized: "0x…"),
                           text: $typed,
                           buttonLabel: String(localized: "Watch")) { watchTyped() }
            if let note {
                Text(note)
                    .dsText(.subhead13)
                    .foregroundStyle(noteIsError ? DS.destructive : DS.textSecondary)
            }
            // The seat's one §315 gray sentence, and it is spent on the thing
            // somebody would otherwise assume. "Privacy devnet" invites the
            // reading that watching here is private; it is not, and the chain
            // itself is the reason rather than any choice of ours.
            DSSlabNote(text: String(localized: "Test ETH has no value, and the network may be reset without notice. Addresses on this chain are public — watching one is a read, and it hides nothing about you."))
        }
    }

    private func watchTyped() {
        let raw = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        guard PrivacyDevnetWatch.isValidAddress(raw) else {
            note = String(localized: "That doesn't look like an address. It should be 0x and 40 more characters.")
            noteIsError = true
            return
        }
        guard !watch.isWatching(raw) else {
            note = String(localized: "Already watching that one.")
            noteIsError = false
            return
        }
        let wasFirst = watch.addresses.isEmpty
        watch.add(raw)
        PrivacyDevnetBridge.registerBridge(store: store)
        typed = ""
        note = nil
        DSHaptic.success()
        // Only on the FIRST watch: the room is a new place then, and going
        // there is the point. On the second, staying put is — you are adding
        // to a list you can see.
        if wasFirst { openRoom() }
    }

    private func openRoom() {
        route.closeConnectForm()
        route.path = []
        chrome.sourceRequest = PrivacyDevnetIdentity.source
    }

    // MARK: - Examples

    /// The shared list — see `PrivacyDevnetSuggestions`, which the empty room
    /// reads too. A second copy here is how two screens end up suggesting
    /// different addresses.
    private var unwatchedExamples: [PrivacyDevnetSuggestions.Entry] {
        PrivacyDevnetSuggestions.unwatched
    }

    @ViewBuilder private var examples: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text(String(localized: "Start with one of these"))
                .dsText(.heading17)
            ForEach(unwatchedExamples) { example in
                DSSlabDoor(title: example.title, detail: example.detail) {
                    DSHaptic.selection()
                    let wasFirst = watch.addresses.isEmpty
                    watch.add(example.address)
                    PrivacyDevnetBridge.registerBridge(store: store)
                    if wasFirst { openRoom() }
                }
            }
        }
    }

    // MARK: - The roster

    @ViewBuilder private var roster: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text(watch.addresses.count == 1
                 ? String(localized: "Watching")
                 : String(localized: "Watching \(watch.addresses.count)"))
                .dsText(.heading17)
            ForEach(watch.addresses, id: \.self) { address in
                HStack(spacing: DS.Space.s3) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(watch.name(for: address) ?? WalletStore.shortAddress(address))
                            .dsText(.body17)
                        Text(WalletStore.shortAddress(address))
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textTertiary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        DSHaptic.selection()
                        watch.remove(address)
                        PrivacyDevnetBridge.registerBridge(store: store)
                    } label: {
                        Text(String(localized: "Remove"))
                            .dsText(.label12)
                            .foregroundStyle(DS.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
