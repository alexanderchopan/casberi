import SwiftUI
import SwiftData

/// Logos, connected (prd §988). Paste a public LEZ account id and what it
/// receives, sends and calls lands from then on, with its balance on the
/// roster.
///
/// No account, no key: the LEZ sequencer answers anyone, so there is nothing
/// to mint and nothing a leak could spend. A PRIVATE account is refused here
/// by name, never watched — its state is encrypted to its owner, and the
/// sequencer answers it as an empty public account, which a watch would draw
/// as a confident zero.
struct LogosScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Bindable private var logos = LogosStore.shared
    @State private var field = ""
    @State private var syncing = false
    @State private var syncPending = false
    @State private var lastResult: BridgeProof?
    @FocusState private var fieldFocused: Bool
    @State private var sheet: AccountPageSheet?
    @State private var weekly: [String: (week: Int, new: Bool)] = [:]

    var body: some View {
        AccountPage(
            name: "Logos", seatID: "logos", source: "Logos",
            state: AccountPageState.of(name: "Logos", seatID: "logos",
                                       connected: logos.connected, store: store),
            mode: .noAccount,
            rows: rows,
            query: field,
            onRemoveRow: unwatch,
            teardown: { LogosStore.shared.disconnect() },
            sheet: $sheet,
            act: { addBlock },
            more: { EmptyView() },
            keySheet: { EmptyView() }
        )
        .onAppear {
            countWeek()
            if logos.connected { Task { await sync() } }
        }
        .onChange(of: logos.accounts) { _, _ in countWeek() }
    }

    // MARK: - The roster

    /// One row per watched account: its short id, and its balance where the
    /// sequencer has answered — test coins, named as such by the symbol.
    private var rows: [AccountPageShape.Row] {
        logos.accounts.map { id in
            // `AccountWeek` keys its counts lowercased; base58 is case-sensitive,
            // but two ids differing only in case are not a real collision here.
            let counted = weekly[id.lowercased()] ?? (week: 0, new: false)
            let nouns = logos.balance(for: id)
                .map { String(localized: "Balance \(LogosWire.amount($0))") }
                ?? String(localized: "Transfers")
            return AccountPageShape.Row(
                id: id, title: LogosWire.short(id),
                subline: AccountPageShape.subline(nouns: nouns, weekCount: counted.week),
                weekCount: counted.week, hasNew: counted.new,
                isYou: false, avatarURL: nil)
        }
    }

    private func countWeek() {
        let watched = logos.accounts
        weekly = AccountWeek.counts(source: "Logos", seatID: "logos",
                                    context: modelContext) { thing in
            guard let ref = thing.sourceRef else { return nil }
            return watched.first { ref.contains(":\($0):") }
        }
    }

    @ViewBuilder private var addBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            DSSlabField(placeholder: String(localized: "LEZ account id"),
                        text: $field,
                        actionLabel: String(localized: "Watch"),
                        focus: $fieldFocused,
                        isArmed: LogosWire.parseAccountID(field) != nil,
                        action: watch)
            BridgeSyncStatusRows(syncing: syncing,
                                 syncingLine: String(localized: "Reading the testnet…"),
                                 proof: lastResult)
        }
    }

    // MARK: - Actions

    private func watch() {
        switch logos.add(field) {
        case .invalid:
            lastResult = .failed(String(localized: "That isn't an LEZ account id."))
            return
        case .privateAccount:
            // Not a typo: a real account this door cannot read.
            lastResult = .says(String(localized: "A private account is readable only with its owner's consent."))
            return
        case .alreadyWatching:
            lastResult = .says(String(localized: "Already watching that account."))
            field = ""
            return
        case .added:
            break
        }
        field = ""
        fieldFocused = false
        DSHaptic.tap()
        Task { await sync() }
    }

    private func unwatch(_ id: String) {
        logos.remove(id)
        // Its rows leave with it (prd §286); every ref carries the id.
        FollowPrune.remove(source: "Logos", context: modelContext) {
            $0.sourceRef?.contains(":\(id):") == true
        }
        lastResult = .says(String(localized: "Stopped watching \(LogosWire.short(id))."))
        DSHaptic.tap()
        countWeek()
        Task { await sync() }
    }

    private func sync() async {
        guard logos.connected else {
            store.remove("logos")
            return
        }
        if syncing { syncPending = true; return }
        syncing = true
        defer { syncing = false }
        repeat {
            syncPending = false
            let outcome = await LogosIngest.refresh(context: modelContext)
            guard logos.connected else { store.remove("logos"); return }
            if let outcome {
                lastResult = outcome.stalled
                    ? .says(String(localized: "The testnet changed its block format, so activity is paused. Balances still update."))
                    : outcome.skipped > 0
                        ? .says(String(localized: "Skipped \(outcome.skipped) blocks from while you were away."))
                    : outcome.added > 0 ? .landed(outcome.added) : .upToDate
                let proof = outcome.added > 0
                    ? String(localized: "\(outcome.added) in")
                    : String(localized: "Synced just now")
                store.registerConnected(
                    id: "logos", name: "Logos", proof: proof,
                    can: ["Reads the balance and activity of the public LEZ accounts you watch, on the Logos testnet.",
                          "Read-only — no key, and nothing it could send."])
            } else {
                lastResult = .failed(String(localized: "Couldn't reach the Logos testnet — check your connection."))
            }
        } while syncPending && logos.connected
    }
}
