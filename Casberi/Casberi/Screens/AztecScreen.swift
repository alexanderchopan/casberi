import SwiftUI
import SwiftData

/// Aztec, connected (2026-10-11). Logos' page grammar: ONE field, the
/// followed roster, the one sentence about test fees, and the explorer's door.
///
/// **What can be followed:** the testnet itself (the room's Home), any
/// sequencer by its L1 attester address — yours, or one you delegate to —
/// and any Aztec ACCOUNT, whose PUBLIC Fee Juice is all a keyless read can
/// see: its private notes are encrypted to its owner (`AztecWire`), and the
/// room says so beside the number.
///
/// Keyless and read-only: the testnet's node answers anyone, and nothing here
/// signs or sends.
struct AztecScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Bindable private var aztec = AztecStore.shared
    @State private var field = ""
    @State private var syncing = false
    @State private var syncPending = false
    @State private var lastResult: BridgeProof?
    @FocusState private var fieldFocused: Bool
    @State private var sheet: AccountPageSheet?
    @State private var weekly: [String: (week: Int, new: Bool)] = [:]
    @State private var namingID: String?
    @State private var nameDraft = ""
    /// A sign request pasted into the field (the Universal Clipboard path).
    @State private var pastedSign: AztecSignAsk?
    @State private var confirmRemoveKey = false
    @State private var signerKey = AztecSignerKey.publicKeyHex()

    /// The roster row for the network itself.
    private static let networkRowID = "network"

    var body: some View {
        AccountPage(
            name: "Aztec", seatID: "aztec", source: "Aztec",
            state: AccountPageState.of(name: "Aztec", seatID: "aztec",
                                       connected: aztec.connected, store: store),
            mode: .noAccount,
            rows: rows,
            query: field,
            onRemoveRow: unfollow,
            // A sequencer takes a name from the address book, the app's one
            // naming authority (prd §1091); the network row has none to take.
            rowMenu: { id in
                AnyView(Group {
                    if id != Self.networkRowID {
                        Button {
                            nameDraft = AddressBook.shared.name(for: id) ?? ""
                            namingID = id
                        } label: {
                            Label(AddressBook.shared.name(for: id) == nil ? "Name" : "Rename",
                                  systemImage: "pencil")
                        }
                    }
                })
            },
            teardown: { AztecStore.shared.disconnect() },
            sheet: $sheet,
            act: { addBlock },
            more: {
                signingRows
                DSFootnote(prose: String(localized: "Test fees have no value, and the testnet is replaced when Aztec ships a major version."))
                    .padding(.vertical, DS.Space.s3)
                DevnetExplorerRow(url: AztecIngest.network.explorer, plain: true)
            },
            keySheet: { EmptyView() }
        )
        .alert("Name this sequencer",
               isPresented: Binding(get: { namingID != nil }, set: { if !$0 { namingID = nil } })) {
            TextField("Name (e.g. My sequencer)", text: $nameDraft)
            Button("Save") {
                if let id = namingID { AddressBook.shared.setName(nameDraft, for: id) }
                namingID = nil
            }
            Button("Cancel", role: .cancel) { namingID = nil }
        } message: {
            Text("Blank shows the address instead.")
        }
        .sheet(item: $pastedSign) { ask in AztecSignTray(request: ask.request) }
        .alert("Remove the signing key?", isPresented: $confirmRemoveKey) {
            Button("Remove", role: .destructive) {
                AztecSignerKey.delete()
                signerKey = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its testnet account can never be used again.")
        }
        .onAppear {
            countWeek()
            if aztec.connected { Task { await sync() } }
        }
        .onChange(of: aztec.sequencers) { _, _ in countWeek() }
    }

    // MARK: - Roster

    private var rows: [AccountPageShape.Row] { networkRow + sequencerRows + accountRows }

    private var accountRows: [AccountPageShape.Row] {
        aztec.accounts.map { account in
            let line = aztec.publicFeeJuice(for: account)
                .map { String(localized: "\(AztecWire.tokens($0)) public Fee Juice") }
                ?? String(localized: "Reading…")
            var row = AccountPageShape.Row(
                id: account, title: AztecRoom.name(for: account),
                subline: AddressBook.shared.name(for: account) == nil ? line : "\(AztecWire.short(account)) · \(line)",
                weekCount: 0, hasNew: false, isYou: false, avatarURL: nil)
            row.faceAddress = account
            return row
        }
    }

    private var networkRow: [AccountPageShape.Row] {
        guard aztec.followsNetwork else { return [] }
        return [AccountPageShape.Row(
            id: Self.networkRowID, title: String(localized: "The Aztec testnet"),
            subline: aztec.network.map { String(localized: "Block \(AztecWire.grouped($0.tips.proposed)) · \(AztecRoomFigure.proving($0.tips))") }
                ?? String(localized: "Reading the testnet…"),
            weekCount: 0, hasNew: false, isYou: false, avatarURL: nil)]
    }

    private var sequencerRows: [AccountPageShape.Row] {
        aztec.sequencers.map { address in
            let counted = weekly[address] ?? (week: 0, new: false)
            let line = aztec.reading(for: address).map(AztecWire.line)
                ?? (aztec.readAt == nil ? String(localized: "Reading…")
                                        : String(localized: "Not seen by this node"))
            var row = AccountPageShape.Row(
                id: address, title: AztecRoom.name(for: address),
                subline: AddressBook.shared.name(for: address) == nil ? line : "\(AztecWire.short(address)) · \(line)",
                weekCount: counted.week, hasNew: counted.new, isYou: false, avatarURL: nil)
            row.faceAddress = address
            return row
        }
    }

    private func countWeek() {
        let followed = aztec.sequencers
        weekly = AccountWeek.counts(source: "Aztec", seatID: "aztec", context: modelContext) { thing in
            AztecRoom.sequencer(ofRef: thing.sourceRef).flatMap { followed.contains($0) ? $0 : nil }
        }
    }

    // MARK: - Follow

    @ViewBuilder private var addBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            DSSlabField(placeholder: String(localized: "Sequencer or account address (0x…)"),
                        text: $field,
                        actionLabel: String(localized: "Follow"),
                        keyboard: .URL,
                        focus: $fieldFocused,
                        isArmed: AztecWire.attester(field) != nil || AztecWire.account(field) != nil
                            || AztecSignRequest.request(fromLink: field) != nil,
                        paste: { pasted in
                            field = pasted
                            if AztecSignRequest.request(fromLink: pasted) != nil { return }
                            if AztecWire.attester(pasted) == nil && AztecWire.account(pasted) == nil {
                                lastResult = .failed(Self.malformed)
                            }
                        },
                        action: follow)
            if !aztec.followsNetwork {
                DSDoorRow(icon: "plus", label: "Follow the testnet") {
                    aztec.follow(network: true)
                    DSHaptic.tap()
                    Task { await sync() }
                }
            }
            BridgeSyncStatusRows(syncing: syncing,
                                 syncingLine: String(localized: "Reading the testnet…"),
                                 proof: lastResult)
        }
    }

    private static let malformed = String(localized: "That isn't a sequencer's attester address or an Aztec account.")

    /// Signing for a testnet account (2026-10-11): this phone's key, which a
    /// computer's tool builds Aztec's own account from. Testnet only.
    @ViewBuilder private var signingRows: some View {
        if let key = signerKey {
            DSCopyRow(value: key, label: "Copy signing key", sensitive: false)
            DSDoorRow(icon: "trash", label: "Remove signing key", role: .destructive) { confirmRemoveKey = true }
        } else {
            DSDoorRow(icon: "key", label: "Make a testnet signing key") {
                do {
                    try AztecSignerKey.create()
                    signerKey = AztecSignerKey.publicKeyHex()
                    lastResult = .says(String(localized: "Made. Copy the key into the signer on your computer."))
                } catch {
                    lastResult = .failed(String(localized: "Couldn't make a key: \(String(describing: error))"))
                }
            }
        }
    }

    private func follow() {
        if let request = AztecSignRequest.request(fromLink: field) {
            field = ""
            pastedSign = AztecSignAsk(request: request)
            return
        }
        switch aztec.add(field) {
        case .invalid:
            lastResult = .failed(Self.malformed)
            return
        case .addedAccount:
            lastResult = .says(String(localized: "Following its public Fee Juice. Its private balance stays private."))
        case .alreadyFollowing:
            lastResult = .says(String(localized: "Already following that address."))
            field = ""
            return
        case .added:
            break
        }
        // A sequencer is watched against the network it runs on: following
        // one follows the testnet too, so Home is never empty beside it.
        aztec.follow(network: true)
        field = ""
        fieldFocused = false
        DSHaptic.tap()
        Task { await sync() }
    }

    private func unfollow(_ id: String) {
        if id == Self.networkRowID {
            aztec.follow(network: false)
            lastResult = .says(String(localized: "Stopped following the testnet."))
        } else {
            aztec.remove(id)
            FollowPrune.remove(source: "Aztec", context: modelContext) {
                AztecRoom.sequencer(ofRef: $0.sourceRef) == id
            }
            lastResult = .says(String(localized: "Stopped following \(AztecWire.short(id))."))
        }
        DSHaptic.tap()
        countWeek()
        Task { await sync() }
    }

    private func sync() async {
        guard aztec.connected else {
            store.remove("aztec")
            return
        }
        if syncing { syncPending = true; return }
        syncing = true
        defer { syncing = false }
        repeat {
            syncPending = false
            if let outcome = await AztecIngest.refresh(context: modelContext) {
                lastResult = outcome.added > 0 ? .landed(outcome.added) : .upToDate
                store.registerConnected(
                    id: "aztec", name: "Aztec",
                    proof: outcome.added > 0 ? String(localized: "\(outcome.added) in")
                                             : String(localized: "Synced just now"),
                    can: ["Reads the Aztec testnet's blocks, proving and fees.",
                          "Reads the attestations and proposals of the sequencers you follow, and their stake, rewards and schedule on Ethereum.",
                          "Reads the public Fee Juice of the Aztec accounts you follow — never a private balance."])
            } else {
                lastResult = .failed(String(localized: "Couldn't reach the Aztec testnet — check your connection."))
            }
            countWeek()
        } while syncPending && aztec.connected
    }
}
