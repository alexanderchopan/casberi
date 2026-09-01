import SwiftUI

/// The Frames devnet, connected — chain 81410, the reference test network for
/// EIP-8141 frame transactions (prd §548).
///
/// **THE ACCOUNT BLOCK LEADS, AND THAT IS A MEASUREMENT RATHER THAN A TASTE.**
/// `HegotaScreen` opens on "paste an address" because Hegotá has months of
/// history to look at. This chain opened on 2026-08-28 and holds **18 distinct
/// addresses**, most of them genesis fixtures (`0x…dead`, `0x…42`) and faucet
/// recipients — so a pasted stranger's address shows almost nothing, which is
/// a correct blank that reads as a broken feature. What this chain is FOR is
/// sending a frame transaction, which nothing else can do: EIP-8141 is a
/// draft, so no wallet and no released library can encode one. Making an
/// account is therefore the common path, not the advanced one.
///
/// **This screen is the CONNECT ACT and nothing else (prd §465).** It keeps
/// what you do ONCE — make the account, claim once, watch the first address,
/// disconnect — and the room keeps what you do repeatedly.
struct FramesScreen: View {
    @Environment(BridgeStore.self) private var store
    @Environment(ShellChrome.self) private var chrome
    @Environment(HomeRoute.self) private var route

    @Bindable private var watch = FramesWatch.shared

    @State private var keyAddress: String? = FramesKey.address()
    @State private var busy = false
    @State private var note: String?
    @State private var noteIsError = false

    private var connected: Bool { watch.connected || keyAddress != nil }

    var body: some View {
        List {
            BridgeSetupHeader(
                name: FramesIdentity.source,
                mode: .noAccount,
                // ACTION, not a re-pitch: you reach this from the product
                // page, which has just said what the chain is.
                intro: "Make an account the faucet will fund, or paste an address to watch.",
                connected: connected)

            if connected {
                RoomDoor(name: FramesIdentity.source, source: FramesIdentity.source)
                    .listRowSeparator(.hidden)
            }

            Section { accountBlock }
                .dsSlabSection()
                .listRowSeparator(.hidden)

            if keyAddress == nil {
                Section { accountDoors }
                    .listRowInsets(EdgeInsets(top: DS.Space.s3, leading: DS.Space.s4,
                                          bottom: 0, trailing: DS.Space.s4))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section { FramesWatchField(onWatched: watch.addresses.count == 1 ? openRoom : {}) }
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
                               detail: String(localized: "Opens dora.frames.ethrex.xyz")) {
                        DSHaptic.selection()
                        if let url = URL(string: FramesIdentity.explorer) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: DS.Space.s6, leading: DS.Space.s4,
                                          bottom: 0, trailing: DS.Space.s4))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                BridgeDisconnectSection(
                    bridgeID: FramesIdentity.seatID, name: FramesIdentity.source,
                    teardown: { FramesBridge.disconnect(store: store) }
                ).listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: FramesIdentity.source)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle(FramesIdentity.source)
    }

    // MARK: - The account

    /// Make a key, then claim once. Two acts, in the order they have to
    /// happen — the faucet needs an address to fund, so "Claim" cannot exist
    /// before the key does, and a Claim button sitting inert above a Create
    /// button is the dead control §83 bans.
    @ViewBuilder private var accountBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(keyAddress == nil ? String(localized: "No account yet")
                                       : String(localized: "Your account"))
                    .dsText(.callout15).foregroundStyle(DS.textPrimary)
                Text(keyAddress.map(WalletStore.shortAddress)
                     ?? String(localized: "A key made on this phone, for signing here"))
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            }
            if let note {
                Text(note)
                    .dsText(.subhead13)
                    .foregroundStyle(noteIsError ? DS.destructive : DS.textTertiary)
            }
            // THE ONE GRAY SENTENCE (§315's budget), spent on the fact that
            // changes what somebody would DO rather than on the pitch: this
            // network says of itself that it may be reset without notice, so
            // an account here is not somewhere to keep anything.
            DSSlabNote(text: String(localized: "Test ETH has no value, and the network may be reset without notice."))
        }
    }

    /// **ONE VERB, and only before there is an account.** The claim door was
    /// here too and is gone (user, 2026-09-01: *"i don't think we need to say
    /// get test eth here b/c it is on the home screen"*) — §553 gives the room
    /// a Top up tile, so a faucet door here was the same verb in two places,
    /// which is the shape §190 and §83 both push against: two controls for one
    /// consequence teach that neither is the real one.
    ///
    /// What is left is the act this screen genuinely owns, and it disappears
    /// once done rather than sitting there inert.
    @ViewBuilder private var accountDoors: some View {
        if keyAddress == nil {
            DSSlabDoor(title: String(localized: "Make an account"),
                       detail: String(localized: "A key made on this phone")) {
                DSHaptic.selection()
                makeKey()
            }
        }
    }

    private func makeKey() {
        do {
            let made = try FramesKey.create()
            keyAddress = made
            note = String(localized: "Made. Ask the faucet for test ETH to send with.")
            noteIsError = false
            FramesBridge.registerBridge(store: store)
        } catch {
            // The keychain's own answer, never a bare "it failed" — §531's
            // whole reason: a code with no remedy is a dead end.
            note = String(localized: "Couldn't make a key: \(String(describing: error))")
            noteIsError = true
        }
    }

    private func claim(for address: String) {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let claimed = try await FramesSend.claimFaucet(for: address)
                note = String(localized: "The faucet sent 1 test ETH. \(WalletStore.shortAddress(claimed.transactionHash))")
                noteIsError = false
            } catch let failure as FramesSend.Failure {
                // The service's OWN words, carried whole (§531). The hourly
                // rate limit is the refusal this faucet makes on an ordinary
                // day and must not read as a fault.
                if case .faucet(let verdict) = failure {
                    note = verdict.sentence
                    noteIsError = {
                        if case .rateLimited = verdict { return false }
                        return true
                    }()
                } else {
                    note = String(localized: "The faucet didn't answer.")
                    noteIsError = true
                }
            } catch {
                note = String(localized: "The faucet didn't answer.")
                noteIsError = true
            }
        }
    }

    // MARK: - Watching

    private var unwatchedExamples: [FramesExample] {
        FramesExample.all.filter { !watch.isWatching($0.address) }
    }

    @ViewBuilder private var examples: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text(watch.connected ? String(localized: "Watch another")
                                 : String(localized: "No address to hand?"))
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
            ForEach(unwatchedExamples) { example in
                Button {
                    DSHaptic.selection()
                    if watch.add(example.address) {
                        FramesBridge.registerBridge(store: store)
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
                        // WHAT THE TAP DOES, said on the row — two titled rows
                        // with an address beside them read as facts, not
                        // buttons (HegotaScreen's own report).
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
                        FramesBridge.registerBridge(store: store)
                    } label: {
                        Text(String(localized: "Remove"))
                            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// CLOSE, POP, ASK — `RoomDoor`'s order. This screen is RAISED as the
    /// connect sheet, so `route.path` is the stack behind it and a bare
    /// `sourceRequest` moves a room the form is still covering.
    private func openRoom() {
        route.closeConnectForm()
        route.path = []
        chrome.sourceRequest = FramesIdentity.source
    }
}

/// The addresses worth offering, and there are only two worth offering.
///
/// **Measured 2026-09-01 across the chain's whole history**: 5 type-`0x06`
/// transactions from 4 senders. These two are the only addresses that have
/// sent more than one thing, so they are the only ones whose room has more
/// than a single row in it. Everything else on this chain is a genesis
/// fixture or an address the faucet paid once.
struct FramesExample: Identifiable {
    let address: String
    let title: String
    let detail: String
    var id: String { address }

    static let all: [FramesExample] = [
        FramesExample(address: "0x80cfe5da326d0ab7a1d2ffc61745c57885dc2e32",
                      title: String(localized: "An address that sent twice"),
                      detail: String(localized: "Two frame transactions, on nonces 0 and 1")),
        FramesExample(address: "0x333ea8dfbb78bf478c52fd6e1a8aa659db873a0d",
                      title: String(localized: "A two-frame transfer"),
                      detail: String(localized: "Shows a verify frame and a sender frame")),
    ]
}

/// The address field. Its own type rather than a shared one, because a field
/// bound to the wrong watch list is the silent kind of wrong.
struct FramesWatchField: View {
    @Environment(BridgeStore.self) private var store
    var onWatched: () -> Void

    @State private var field = ""
    @State private var result: String?
    @State private var resultIsError = false
    @Bindable private var watch = FramesWatch.shared

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
        guard FramesWatch.isValidAddress(address) else {
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
        FramesBridge.registerBridge(store: store)
        field = ""
        result = nil
        onWatched()
    }
}
