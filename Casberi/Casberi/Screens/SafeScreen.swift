import SwiftUI
import SwiftData

/// Safe, connected — the pending signature queue for any Safe you watch
/// directly, or any Safe that watches one of your own wallets as a signer
/// (2026-07-30). A Safe multisig has no account of its own to sign into —
/// signing happens in the person's own Safe app — so the seat rides the
/// watched wallets the way Peer/0xBow do, and connecting is one switch.
/// Unlike those two, this seat is gated on an ACTUAL detected Safe
/// (`SafeBridge.detectedCount()`), not on a wallet merely being watched:
/// most wallets are neither a Safe nor a Safe signer, and a seat claiming
/// otherwise would be fake status (the same divergence Gnosis Pay's seat
/// makes for the same reason).
struct SafeScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    // This window's stack (per-window since `SceneState`).
    @Environment(HomeRoute.self) private var route
    @State private var syncing = false
    @State private var lastResult: String?
    /// Whether `lastResult` is a failure — see `PrivacyPoolsScreen` (audit,
    /// 2026-07-31): hardcoding `false` painted "Couldn't reach Safe" in
    /// confirm green with the count-up animation.
    @State private var lastResultIsError = false

    private var hasWallets: Bool { !WalletStore.shared.addresses.isEmpty }
    private var walletCount: Int { WalletStore.shared.addresses.count }
    private var safeCount: Int { SafeBridge.detectedCount() }

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "Safe",
                mode: .watchedWallets,
                intro: "No account here — it reads the wallets you already watch, so you're told when a transaction is waiting on your signature, and when an owner, threshold or module changes. Signing always happens in your own Safe app.",
                connected: safeCount > 0)
            connectSection.listRowSeparator(.hidden)
            coSignersSection.listRowSeparator(.hidden)
            if hasWallets {
                ChipLiveNote(name: "Safe", verb: "for your Safe's signature queue.")
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Safe")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("Safe")
        .onAppear {
            // Watching is consent (prd §207): keep the catalog seat honest on
            // appear, and refresh the queue if a wallet's watched.
            store.reconcileWalletSeats()
            if hasWallets { Task { await sync() } }
        }
    }

    // MARK: - Connect (automatic — no switch, prd §207)

    /// No toggle: a Safe has no account to sign into, so watching a wallet —
    /// either the Safe itself, or one of its signers — IS the consent to
    /// read its queue. With wallets watched, the row states the fact and
    /// doors to the wallet manager; with none, it's the invitation to watch
    /// one.
    private var connectSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if hasWallets {
                    DSSlabDoor(title: String(localized: "Watching \(walletCount) wallet"),
                               detail: String(localized: "Manage")) {
                        route.pushBridge(.wallet)
                    }
                } else {
                    DSSlabDoor(title: "Watch a wallet") {
                        route.pushBridge(.wallet)
                    }
                }
                BridgeSyncStatusRows(syncing: syncing,
                                     syncingLine: String(localized: "Reading your Safe's queue…"),
                                     result: lastResult, resultIsError: lastResultIsError)
                // The bare "Read-only." left this note (duplication audit,
                // 2026-07-31): it was in one branch only, and the footer's
                // lede says the same thing with the part that matters — where
                // signing actually happens — in both states.
                DSSlabNote(text: safeCount > 0
                    ? String(localized: "Watching \(safeCount) Safe — a pending signature lands in your feed the moment it's proposed.")
                    : String(localized: "Watch a Safe, or a wallet that signs for one."))
            }
        }
        .dsSlabSection()
    }


    // MARK: - Who you sign with

    /// The people, not the addresses (2026-07-30). A Safe is the one place in
    /// this app where others act on your behalf, and the co-signers are the
    /// part of it worth recognising at a glance — so the screen shows their
    /// faces the same way the wallet manager shows a roster of wallets. Named
    /// from the address book / Farcaster where possible; short hex otherwise,
    /// never a guessed identity. Absent entirely when no Safe is detected, so
    /// nothing claims a roster that isn't there.
    @ViewBuilder private var coSignersSection: some View {
        if !coSigners.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text("Who you sign with")
                        .dsText(.callout15).foregroundStyle(DS.textPrimary)
                    ForEach(coSigners, id: \.self) { address in
                        HStack(spacing: DS.Space.s2) {
                            WalletFace(address: address, size: 26, circular: true)
                            Text(verbatim: WalletIngest.knownLabel(for: address)
                                 ?? WalletStore.shortAddress(address))
                                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .dsSlabSection()
        }
    }

    /// Every OTHER owner across the detected Safes — your own watched wallets
    /// filtered out, since "who you sign with" means the other people.
    private var coSigners: [String] {
        let mine = Set(WalletStore.shared.addresses.map { $0.address.lowercased() })
        return SafeBridge.knownCoSigners().filter { !mine.contains($0.lowercased()) }
    }

    // MARK: - Actions

    /// Refresh the queue for the watched wallets. The catalog seat is kept
    /// honest by `store.reconcileWalletSeats()`, not here.
    private func sync() async {
        guard hasWallets, !syncing else { return }
        syncing = true
        defer { syncing = false }
        let added = await SafeBridge.syncNow(context: modelContext)
        if let added {
            lastResult = added > 0 ? String(localized: "\(added) new")
                                   : String(localized: "Up to date")
            lastResultIsError = false
        } else {
            lastResult = String(localized: "Couldn't reach Safe — check your connection.")
            lastResultIsError = true
        }
    }
}
