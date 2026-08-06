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
    @State private var result: String?
    @State private var resultIsError = false
    @State private var positions: [Int: EthValidatorRead.Position] = [:]
    @FocusState private var fieldFocused: Bool

    var body: some View {
        List {
            // The one setup screen in the family with no header (audit,
            // 2026-07-31), so its tagline appeared nowhere and the slab note
            // below had to carry the what-lands fact alone. NOT the §185 case:
            // Tokens and Stocktwits go headerless on purpose because their
            // omnibox leads an asset SHELF; this is a wallet seat with a
            // watchlist, and it simply never got one.
            BridgeSetupHeader(
                name: "ETH Validators",
                mode: .noAccount,
                intro: "A validator index is public — anyone can look one up. Add yours and its balance, status and rewards keep arriving.",
                connected: !validatorStore.watched.isEmpty)
            addSection.listRowSeparator(.hidden)
            if !validatorStore.watched.isEmpty {
                watchlistSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "ETH Validators")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("ETH Validators")
        .onAppear {
            if !validatorStore.watched.isEmpty { Task { await refresh() } }
        }
    }

    // MARK: - Sections

    private var addSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSSlabField(placeholder: String(localized: "Validator index"),
                            text: $indexField, actionLabel: String(localized: "WATCH"),
                            focus: $fieldFocused, action: watch)
                BridgeSyncStatusRows(syncing: working,
                                     syncingLine: String(localized: "Checking the validator…"),
                                     result: result, resultIsError: resultIsError)
                // The what-lands sentence added here earlier the same day is
                // gone again with the arrival of the header above, whose
                // tagline — "Your validator balance, in your total" — says it
                // in primary type (the same edit `SteamScreen` took; a fix and
                // a duplication can be one line). What survives is the part
                // the tagline can't carry: WHERE it shows, where to find the
                // index, and the promise.
                DSSlabNote(text: "It shows under ETH. Your staking client (or any beacon-chain explorer) shows the index. Read-only — nothing here stakes, exits, or moves a balance.")
            }
        }
        .dsSlabSection()
    }

    private var watchlistSection: some View {
        Section {
            ForEach(validatorStore.watched) { row in
                validatorRow(row)
            }
            .onDelete(perform: unwatch)
        }
        // The footer that said "Balance folds into your combined wallet total,
        // under ETH." moved UP into the add slab's note (2026-07-31), where it
        // is visible BEFORE you watch anything rather than only after — it was
        // the screen's one what-lands fact, and it lived in a section that
        // doesn't exist until the watchlist does.
    }

    private func validatorRow(_ row: EthValidatorStore.Watched) -> some View {
        let position = positions[row.index]
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label.isEmpty ? "Validator #\(row.index)" : row.label)
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                Text(statusLine(position))
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            }
            Spacer()
            if let position {
                Text("\(WalletIngest.format(position.eth)) ETH")
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
            }
        }
        .dsListCardRow()
        .swipeActions {
            Button(role: .destructive) {
                validatorStore.remove(index: row.index)
                EthValidatorRead.registerBridge(store: store)
                DSHaptic.tap()
            } label: {
                Label("Unwatch", systemImage: "trash")
            }
        }
        // A swipe has no Mac-mouse equivalent — right-click mirrors it
        // (Mac polish, 2026-07-28).
        .contextMenu {
            Button(role: .destructive) {
                validatorStore.remove(index: row.index)
                EthValidatorRead.registerBridge(store: store)
                DSHaptic.tap()
            } label: {
                Label("Unwatch", systemImage: "trash")
            }
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
            resultIsError = true
            result = String(localized: "That doesn't look like a validator index.")
            return
        }
        DSHaptic.tap()
        working = true
        result = nil
        Task {
            let found = await EthValidatorRead.positions(indices: [index])
            working = false
            guard let found, let position = found.first(where: { $0.index == index }) else {
                resultIsError = true
                result = String(localized: "Couldn't find validator #\(index).")
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
                resultIsError = false
                result = String(localized: "Already watching validator #\(index).")
                return
            }
            positions[index] = position
            resultIsError = false
            result = String(localized: "Watching validator #\(index) — \(WalletIngest.format(position.eth)) ETH")
            indexField = ""
            EthValidatorRead.registerBridge(store: store)
        }
    }

    private func unwatch(at offsets: IndexSet) {
        // Snapshot the indices to drop BEFORE removing any — `remove`
        // mutates `validatorStore.watched` in place, so reading it mid-loop
        // after an earlier removal would shift every later offset.
        let dropped = offsets.map { validatorStore.watched[$0].index }
        for index in dropped { validatorStore.remove(index: index) }
        DSHaptic.tap()
        EthValidatorRead.registerBridge(store: store)
    }

    private func refresh() async {
        let indices = validatorStore.watched.map(\.index)
        guard let found = await EthValidatorRead.positions(indices: indices) else { return }
        for position in found { positions[position.index] = position }
    }
}
