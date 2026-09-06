import SwiftUI

/// Watching Ethereum validators by index (2026-07-27) — see
/// `EthValidatorWatch.swift` for why this asks for the index directly rather
/// than deriving it from a wallet (there's no free way to). Keyless, via a
/// public beacon-node REST API. Read-only: nothing here stakes, exits, or
/// moves a validator's balance — the same "watching can never move funds"
/// promise every wallet-adjacent bridge here keeps.
struct EthValidatorScreen: View {
    @Environment(BridgeStore.self) private var store
    @Bindable private var validatorStore = EthValidatorStore.shared
    @State private var indexField = ""
    @State private var working = false
    @State private var result: BridgeProof?
    @State private var positions: [Int: EthValidatorRead.Position] = [:]
    @FocusState private var fieldFocused: Bool

    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "ETH Validators", seatID: "ethvalidator", source: "ETH Validators",
            state: AccountPageState.of(name: "ETH Validators", seatID: "ethvalidator",
                                       connected: !validatorStore.watched.isEmpty, store: store),
            intro: "An index is public, so there's nothing to sign in to. Balance, status and rewards land as they change.",
            mode: .noAccount,
            // A VALIDATOR LANDS NOTHING (§484's rowless nine): its balance
            // folds into the combined total and no row reaches the feed, so
            // the Activity count and "Who may read it" are absent rather than
            // reading zero about a seat that is working.
            lands: false,
            rows: rows,
            query: indexField,
            onRemoveRow: unwatch,
            // Every watched index goes, so the next foreground can't
            // re-register the seat off a list the person just disconnected.
            teardown: {
                for index in validatorStore.watched.map(\.index) {
                    validatorStore.remove(index: index)
                }
            },
            sheet: $sheet,
            act: { addBlock },
            more: { EmptyView() },
            keySheet: { EmptyView() }
        )
        .onAppear {
            if !validatorStore.watched.isEmpty { Task { await refresh() } }
        }
    }

    // MARK: - The roster

    /// One row per watched validator — its label or index, its status, and
    /// what it holds where the beacon chain answered. No figure where it did
    /// not: unreachable is a fact we don't have.
    private var rows: [AccountPageShape.Row] {
        validatorStore.watched.map { row in
            let position = positions[row.index]
            let held = position.map { WalletValue.token($0.eth, "ETH") }
            let status = statusLine(position)
            return AccountPageShape.Row(
                id: String(row.index),
                title: row.label.isEmpty ? String(localized: "Validator #\(row.index)") : row.label,
                subline: held.map { "\(status) · \($0)" } ?? status,
                weekCount: 0, hasNew: false, isYou: false, avatarURL: nil)
        }
    }

    private func unwatch(_ id: String) {
        guard let index = Int(id) else { return }
        validatorStore.remove(index: index)
        EthValidatorRead.registerBridge(store: store)
        DSHaptic.tap()
    }


    // MARK: - Sections

    @ViewBuilder private var addBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            DSSlabField(placeholder: String(localized: "Validator index"),
                        text: $indexField, actionLabel: String(localized: "Watch"),
                        focus: $fieldFocused, action: watch)
            BridgeSyncStatusRows(syncing: working,
                                 syncingLine: String(localized: "Checking the validator…"),
                                 proof: result)
            // The what-lands sentence added here earlier the same day is
            // gone again with the arrival of the header above, whose
            // tagline — "Your validator balance, in your total" — says it
            // in primary type (the same edit `SteamScreen` took; a fix and
            // a duplication can be one line). What survives is the part
            // the tagline can't carry: WHERE it shows, where to find the
            // index, and the promise.
            DSSlabNote(text: "It shows under ETH; your staking client shows the index. Nothing stakes, exits, or moves a balance.", plain: true)
        }
    }

    private func statusLine(_ position: EthValidatorRead.Position?) -> String {
        guard let position else { return String(localized: "Reading…") }
        switch position.status {
        case .active:      return String(localized: "Active")
        case .activating:  return String(localized: "Activating")
        case .exiting:     return String(localized: "Exiting")
        case .exited:      return String(localized: "Exited")
        case .unknown:     return String(localized: "Unknown status")
        }
    }


    // MARK: - Actions

    private func watch() {
        let text = indexField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = Int(text), index >= 0, !working else {
            result = .failed(String(localized: "That doesn't look like a validator index."))
            return
        }
        DSHaptic.tap()
        working = true
        result = nil
        Task {
            let found = await EthValidatorRead.positions(indices: [index])
            working = false
            guard let found, let position = found.first(where: { $0.index == index }) else {
                result = .failed(String(localized: "Couldn't find validator #\(index)."))
                return
            }
            guard validatorStore.add(index: index) else {
                // Already watching is NOT a failure — it's the thing you asked
                // for, already done, so it doesn't get the red, the sideways
                // shake and the failure haptic `BridgeSyncStatusRows` fires on
                // an error. The same condition was classified three different
                // ways across the family (red here and in RSS, green in
                // PostHog/Stocktwits, gray in Open Food Facts); settled as
                // not-an-error, 2026-07-31.
                result = .says(String(localized: "Already watching validator #\(index)."))
                return
            }
            positions[index] = position
            result = .says(String(localized: "Watching validator #\(index) — \(WalletValue.token(position.eth, "ETH"))"))
            indexField = ""
            EthValidatorRead.registerBridge(store: store)
        }
    }

    private func refresh() async {
        let indices = validatorStore.watched.map(\.index)
        guard let found = await EthValidatorRead.positions(indices: indices) else { return }
        for position in found { positions[position.index] = position }
    }
}
