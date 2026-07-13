import SwiftUI
import SwiftData

/// The wallet things already in the corpus — newest first. A @Query so the
/// list updates live and the fetch runs once per store change, not twice per
/// body pass.
private let walletRecentDescriptor: FetchDescriptor<Thing> = {
    var d = FetchDescriptor<Thing>(
        predicate: #Predicate { $0.source == "Wallet" },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
    )
    d.fetchLimit = 12
    return d
}()

/// Wallet, connected — the wallet's home in Casberi. The person manages WHICH
/// addresses are watched (paste to add, swipe to remove, drag to reorder — the
/// first address leads), sees a live holdings treemap (top 5 by USD value), and
/// sees what's landed (recent onchain things from the corpus). Read-only,
/// stated plainly: watching an address can never trade or move funds. Both the
/// holdings and the activity are live from Alchemy, read on this iPhone — no
/// server.
struct WalletScreen: View {
    @Bindable private var wallet = WalletStore.shared
    @State private var newAddress = ""
    @FocusState private var addressFieldFocused: Bool
    /// Holdings render through the gen-UI engine — allocation is magnitude, so
    /// the treemap is its native shape (holdings are SYNTHESIS, not things).
    /// Both holdings and activity are live from Alchemy — no server.
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var syncing = false
    @State private var holdings = GenStream()
    @State private var result: String?
    @State private var resultIsError = false
    /// The one swipe lesson, shared across every screen that pins by swipe
    /// (2026-07-11) — whichever screen a person meets the gesture on first
    /// retires it everywhere.
    @AppStorage("coach.swipe.done") private var swipeCoachDone = false

    @Query(walletRecentDescriptor) private var recent: [Thing]

    var body: some View {
        List {
            addSection.listRowSeparator(.hidden)
            // The pin lives on each address row now (2026-07-09) — one
            // switch per wallet, right where you'd reach for it, instead of
            // a single toggle below that couldn't say WHICH wallet it meant
            // once more than one was watched.
            if !wallet.addresses.isEmpty { watchingSection.listRowSeparator(.hidden) }
            if !wallet.addresses.isEmpty, !holdings.els.isEmpty {
                Section {
                    GenRender(id: "root", els: holdings.els)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                }
                .listRowSeparator(.hidden)
            }
            if syncing || result != nil {
                Section {
                    BridgeSyncStatusRows(syncing: syncing, syncingLine: String(localized: "Reading onchain activity…"),
                                        result: result, resultIsError: resultIsError)
                }
                .listRowSeparator(.hidden)
            }
            if !recent.isEmpty { recentSection.listRowSeparator(.hidden) }
            if !wallet.addresses.isEmpty {
                BridgeDisconnectSection(
                    bridgeID: "wallet", name: "Wallet",
                    teardown: { WalletStore.shared.addresses = [] }
                ).listRowSeparator(.hidden)
            }
            footerSection.listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle("Wallet")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            // Reorder/remove live behind Edit — drag to sort, red-minus to drop.
            ToolbarItem(placement: .topBarTrailing) { EditButton().tint(DS.textPrimary) }
        }
        .onAppear { if !wallet.addresses.isEmpty { sync() } }
    }

    private func sync() {
        guard !syncing else { return }
        syncing = true
        Task {
            let added = await WalletIngest.refresh(context: modelContext)
            if let doc = await WalletIngest.holdingsChart() { holdings.paint(doc) }
            syncing = false
            // A bridge only registers "connected" once it actually reached
            // Alchemy — a bad key or offline device must never claim success
            // (review 2026-07-08: this fired unconditionally, so a dead key
            // showed "connected" in Apps with nothing ever landing in Feed).
            guard let added else {
                result = String(localized: "Couldn't reach the chain — check your connection.")
                resultIsError = true
                return
            }
            resultIsError = false
            result = added > 0 ? String(localized: "\(added) new") : String(localized: "Connected — watching for activity.")
            let proof = added > 0 ? "\(added) new" : "Synced just now"
            if store.registerConnected(id: "wallet", name: "Wallet", proof: proof,
                                       can: ["Reads your wallet's activity.",
                                             "Read-only — never trades or moves funds."]) {
                DSHaptic.success()
            }
        }
    }

    // MARK: - Watching (add / remove / sort / pin)

    /// Each watched address carries its own pin now (ruling 2026-07-09): a
    /// wallet's holdings show on Home and Feed only when THAT wallet is
    /// pinned — watching more than one is usually two different purposes
    /// (main vs. cold), and a shared switch couldn't say which one it meant.
    /// Pin lives on the swipe alone now (2026-07-11) — the row briefly also
    /// carried an inline toggle, but a second control for the exact same
    /// verb read as two different actions rather than one (user: "confusing
    /// which is which"); the row shows its pin state passively instead
    /// (Feed's grammar), and the swipe hint nudge covers discoverability.
    private var watchingSection: some View {
        Section {
            ForEach(wallet.addresses) { addr in
                HStack(spacing: DS.Space.s3) {
                    RoundedRectangle(cornerRadius: DS.Radius.appIcon(36), style: .continuous)
                        .fill(BridgeGlyph.color(for: "Wallet").opacity(0.22))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "wallet.bifold")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(BridgeGlyph.color(for: "Wallet"))
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(addr.label.isEmpty ? addr.short : addr.label)
                            .dsText(.body17).foregroundStyle(DS.textPrimary)
                        if !addr.label.isEmpty {
                            Text(addr.short).dsText(.subhead13).foregroundStyle(DS.textSecondary)
                        }
                    }
                    Spacer()
                    if addr.pinnedToHome {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.tint)
                    }
                }
                .dsListCardRow()
                .modifier(SwipeHintNudge(active: addr.id == hintAddressID) { swipeCoachDone = true })
                // The pin swipe is the SAME GESTURE everywhere (2026-07-10,
                // user: it was leading here, trailing in Feed — one verb,
                // two directions): trailing edge, Feed's edge.
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    // Full swipe = pin (Feed's grammar). An explicit trailing
                    // group replaces the system delete, so Remove rides here
                    // too — Edit mode's red minus still works.
                    Button {
                        DSHaptic.tap()
                        wallet.togglePin(addr.id)
                    } label: {
                        Label(addr.pinnedToHome ? "Unpin" : "Pin",
                              systemImage: addr.pinnedToHome ? "pin.slash" : "pin")
                    }
                    .tint(DS.tint)
                    Button(role: .destructive) {
                        if let i = wallet.addresses.firstIndex(where: { $0.id == addr.id }) {
                            wallet.remove(at: IndexSet(integer: i))
                        }
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
            .onDelete { wallet.remove(at: $0) }
            .onMove { wallet.move(from: $0, to: $1) }
        } header: {
            Text("Watching").dsText(.label12)
                .foregroundStyle(DS.textSecondary)
        } footer: {
            Text("Swipe a wallet to pin its holdings to Home and Feed.")
                .dsText(.callout15).foregroundStyle(DS.textSecondary)
        }
    }

    /// The row that plays the swipe demo — the first watched address, once
    /// ever, retiring the moment any screen's demo (or a real swipe) does.
    private var hintAddressID: WalletStore.WatchedAddress.ID? {
        guard !swipeCoachDone else { return nil }
        return wallet.addresses.first?.id
    }

    private var addSection: some View {
        Section {
            BridgeFieldRow(placeholder: "Address (0x… or ENS)", text: $newAddress,
                           buttonLabel: "Watch", keyboard: .default,
                           focus: $addressFieldFocused, action: watch)
        } header: {
            Text("Watch an address").dsText(.label12)
                .foregroundStyle(DS.textSecondary)
        } footer: {
            if wallet.addresses.isEmpty {
                Text("Paste a wallet address or ENS name — its holdings and activity land in your feed.")
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
            }
        }
    }

    private func watch() {
        let input = newAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        // An ENS name (vitalik.eth) resolves to hex now — the address is what
        // the APIs read; the name rides along as the row's label.
        if ENS.looksLikeName(input) {
            Task {
                guard let hex = await ENS.resolve(input) else {
                    resultIsError = true
                    result = String(localized: "Couldn't resolve \(input) — check the name or paste a 0x address.")
                    return
                }
                addWatched(address: hex, label: input)
            }
        } else {
            addWatched(address: input, label: "")
        }
    }

    private func addWatched(address: String, label: String) {
        guard wallet.add(address, label: label) else {
            resultIsError = true
            result = String(localized: "Already watching that address.")
            return
        }
        newAddress = ""
        addressFieldFocused = false
        resultIsError = false
        DSHaptic.success()
        sync()
    }

    // MARK: - What's landed

    private var recentSection: some View {
        Section {
            ForEach(recent) { thing in
                HStack(spacing: DS.Space.s3) {
                    KindGlyph(kind: thing.kind, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(thing.title).dsText(.body17).foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        Text(walletLabel(thing) ?? thing.content)
                            .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(shortTime(thing.capturedAt))
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                }
                .dsListCardRow()
            }
        } header: {
            Text("Recent").dsText(.label12)
                .foregroundStyle(DS.textSecondary)
        }
    }

    private var footerSection: some View {
        Section {
        } footer: {
            Text("Read-only — watching can never trade or move funds. Activity is public, read across chains directly on this iPhone.")
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
        }
    }

    /// Which watched wallet a landed transaction came from, when more than
    /// one is watched — falls back to nil (the explorer link shows instead)
    /// rather than guessing.
    private func walletLabel(_ thing: Thing) -> String? {
        wallet.label(forAddress: thing.walletAddress)
    }

    private func shortTime(_ date: Date) -> String {
        let s = Date.now.timeIntervalSince(date)
        if s < 3600 { return "\(max(1, Int(s / 60)))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86_400))d"
    }
}
