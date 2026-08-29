import SwiftUI

/// Ethrex Hegotá, connected — watch an address on the frame-transaction devnet.
///
/// **This screen is the CONNECT ACT and nothing else (prd §465).** It keeps
/// what you do ONCE — the first address, the disconnect — and the room keeps
/// what you do repeatedly. Watching the first address lands you in the room,
/// because that paste IS the connection; only the FIRST one routes, so a second
/// watch tapped a moment later cannot yank the list out from under the thumb
/// still using it.
///
/// **The worked examples are not decoration.** Measured on chain 2026-08-27:
/// only 11 addresses own coins and only a handful have ever sent on a non-zero
/// nonce — and, decisively, **no address does both**. A pasted address will
/// most often show Home and Activity and nothing else, which is a correct blank
/// that reads as a broken feature. So the screen offers two, one for each half
/// of the room, and says what each will show rather than presenting them as
/// interchangeable.
struct HegotaScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(ShellChrome.self) private var chrome
    @Environment(HomeRoute.self) private var route

    @Bindable private var watch = HegotaWatch.shared
    private var connected: Bool { watch.connected }

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "Ethrex Hegotá",
                mode: .noAccount,
                // ACTION, not a re-pitch: you reach this from the product page,
                // which has just said what Hegotá is. The mode chip carries the
                // cost. What is left is what to do here.
                intro: "Paste an address, or open one of the examples below.",
                connected: connected)

            if connected {
                RoomDoor(name: "Ethrex Hegotá", source: HegotaIdentity.source)
                    .listRowSeparator(.hidden)
            }

            Section { HegotaWatchField(onWatched: connected ? {} : openRoom) }
                .dsSlabSection()
                .listRowSeparator(.hidden)

            // THE EXAMPLES SURVIVE THE CONNECT. Gating them on `!connected` —
            // the shape every other setup screen uses — was wrong here and was
            // reported from a device: "when you select one of the addresses to
            // watch you can't select the other, no way back to it". These two
            // are not one onboarding nicety you consume once, they are the
            // room's only two halves (coins and nonces) and NOBODY on this
            // chain has both, so watching one and losing the other leaves you
            // permanently unable to see half the room. They disappear only
            // when there is genuinely nothing left to offer.
            if !unwatchedExamples.isEmpty {
                Section { examples }
                    .dsSlabSection()
                    .listRowSeparator(.hidden)
            }

            if connected {
                Section { roster }
                    .dsSlabSection()
                    .listRowSeparator(.hidden)

                Section {
                    DSSlabDoor(title: String(localized: "Get test ETH"),
                               detail: String(localized: "Opens the faucet")) {
                        DSHaptic.selection()
                        if let url = URL(string: HegotaIdentity.faucet) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: DS.Space.s6, leading: DS.Space.s4,
                                          bottom: 0, trailing: DS.Space.s4))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                BridgeDisconnectSection(
                    bridgeID: HegotaIdentity.seatID, name: HegotaIdentity.source,
                    teardown: { HegotaBridge.disconnect(store: store) }
                ).listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Ethrex Hegotá")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Ethrex Hegotá")
    }

    /// The two doors. Each names what it will SHOW rather than pitching itself,
    /// because the honest difference between them is which half of the room
    /// they fill — and nothing on this chain fills both.
    /// The examples still worth offering. An already-watched one is not an
    /// offer, it is a row in the roster below.
    private var unwatchedExamples: [HegotaExample] {
        HegotaExample.all.filter { !watch.isWatching($0.address) }
    }

    @ViewBuilder private var examples: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text(connected ? String(localized: "Watch another")
                           : String(localized: "No address to hand?"))
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
            ForEach(unwatchedExamples) { example in
                Button {
                    DSHaptic.selection()
                    if watch.add(example.address) {
                        HegotaBridge.registerBridge(store: store)
                        // READ IT NOW. The room reads for itself on appear too,
                        // but starting here means the sweep is usually done by
                        // the time the room draws rather than after it.
                        Task { await HegotaLiveState.shared.refresh() }
                        openRoom()
                    }
                } label: {
                    HStack(spacing: DS.Space.s3) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(example.title).dsText(.callout15).foregroundStyle(DS.textPrimary)
                            Text(example.detail).dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        }
                        Spacer(minLength: 0)
                        Text(WalletStore.shortAddress(example.address))
                            .dsText(.label12).foregroundStyle(DS.textTertiary)
                        // WHAT THE TAP DOES, said on the row. Reported from a
                        // screenshot: two titled rows with an address beside
                        // them read as a list of facts, not as two buttons —
                        // "what's interactive should look interactive", and
                        // the verb is the cheapest way to say it.
                        Text(String(localized: "Watch"))
                            .dsText(.label12).foregroundStyle(DS.tint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var roster: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            ForEach(watch.addresses, id: \.self) { address in
                HStack(spacing: DS.Space.s3) {
                    Text(watch.name(for: address) ?? WalletStore.shortAddress(address))
                        .dsText(.callout15).foregroundStyle(DS.textPrimary)
                    Spacer(minLength: 0)
                    Button {
                        DSHaptic.selection()
                        watch.remove(address)
                        HegotaBridge.registerBridge(store: store)
                    } label: {
                        Text(String(localized: "Remove"))
                            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// CLOSE, POP, ASK — `RoomDoor`'s order (vibenet's own lesson, plus the
    /// close it was missing). This screen is RAISED as the connect sheet, so
    /// `route.path` is the stack behind it and `sourceRequest` moves a room
    /// the form is still covering; without the close the tap does nothing
    /// anyone can see. Nil-write when nothing is raised.
    private func openRoom() {
        route.closeConnectForm()
        route.path = []
        chrome.sourceRequest = HegotaIdentity.source
    }
}

/// The worked examples, measured rather than picked.
///
/// **`0x8b54b456…` holds the most coins on the chain (7 unspent across 10
/// moves)** — seven discs is a real drawing where three is thin — and
/// **`0x8943545177…` is the only address that has sent on two different
/// non-zero nonce keys**, `0xbeef01` and `0x1234`, which is what makes its
/// Nonces scope show more than one row. Measured 2026-08-27; if the chain moves
/// on, these become ordinary addresses rather than broken ones, which is why
/// the copy says what they showed rather than promising what they will.
struct HegotaExample: Identifiable {
    let address: String
    let title: String
    let detail: String
    var id: String { address }

    static let all: [HegotaExample] = [
        HegotaExample(address: "0x8b54b45663b4af65d51d7f98c20f533965e0a013",
                      title: String(localized: "An address holding coins"),
                      detail: String(localized: "Shows the vault's unspent pieces")),
        HegotaExample(address: "0x8943545177806ed17b9f23f0a21ee5948ecaa776",
                      title: String(localized: "An address sending in parallel"),
                      detail: String(localized: "Shows two named nonce keys")),
    ]
}

/// The address field. Its own type rather than a shared one, because the shared
/// `VibenetWatchField` is bound to `VibenetWatch` and a field writing the wrong
/// watch list is the silent kind of wrong.
struct HegotaWatchField: View {
    @Environment(BridgeStore.self) private var store
    var onWatched: () -> Void

    @State private var field = ""
    @State private var result: String?
    @State private var resultIsError = false
    @Bindable private var watch = HegotaWatch.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            BridgeFieldRow(placeholder: String(localized: "0x…"),
                           text: $field,
                           buttonLabel: String(localized: "Watch")) { watchTyped() }
            if let result {
                Text(result)
                    .dsText(.subhead13)
                    .foregroundStyle(resultIsError ? DS.destructive : DS.textTertiary)
            }
        }
    }

    private func watchTyped() {
        let address = field.trimmingCharacters(in: .whitespacesAndNewlines)
        guard HegotaWatch.isValidAddress(address) else {
            result = String(localized: "That isn't an address — it should be 0x and 40 more characters.")
            resultIsError = true
            return
        }
        guard !watch.isWatching(address) else {
            result = String(localized: "Already watching that one.")
            resultIsError = false
            return
        }
        _ = watch.add(address)
        HegotaBridge.registerBridge(store: store)
        Task { await HegotaLiveState.shared.refresh() }
        field = ""
        result = nil
        DSHaptic.success()
        onWatched()
    }
}
