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

    @Query(walletRecentDescriptor) private var recent: [Thing]

    var body: some View {
        List {
            addSection.listRowSeparator(.hidden)
            if !wallet.addresses.isEmpty { watchingSection.listRowSeparator(.hidden) }
            // Pin leads the holdings — a watched wallet earns the toggle right
            // away, above the treemap (report 2026-07-09: below the chart it
            // fell under the fold on a real wallet, so "connect the wallet, pin
            // it to Home" had no visible switch to reach).
            if !wallet.addresses.isEmpty { pinSection.listRowSeparator(.hidden) }
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
                    BridgeSyncStatusRows(syncing: syncing, syncingLine: "Reading onchain activity…",
                                        result: result, resultIsError: resultIsError)
                }
                .listRowSeparator(.hidden)
            }
            if !recent.isEmpty { recentSection.listRowSeparator(.hidden) }
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
                result = "Couldn't reach the chain — check your connection."
                resultIsError = true
                return
            }
            resultIsError = false
            result = added > 0 ? "\(added) new" : "Connected — watching for activity."
            let proof = added > 0 ? "\(added) new" : "Synced just now"
            if store.registerConnected(id: "wallet", name: "Wallet", proof: proof,
                                       can: ["Reads your wallet's activity.",
                                             "Read-only — never trades or moves funds."]) {
                DSHaptic.success()
            }
        }
    }

    // MARK: - Pin to Home

    /// The one switch that puts the holdings treemap on Home. Shows the moment
    /// a wallet is watched (before the chart loads), stated in the same "keep
    /// this in view" voice a Thing pin uses — the swipe on an address flips the
    /// same `wallet.pinnedToHome`, so either gesture reaches it.
    private var pinSection: some View {
        Section {
            HStack(spacing: DS.Space.s3) {
                Text("Pin holdings to Home")
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(
                    get: { wallet.pinnedToHome },
                    set: { wallet.pinnedToHome = $0; DSHaptic.tap() }
                )).labelsHidden().tint(DS.tint)
            }
            .listRowBackground(DS.surfaceSheet)
        } footer: {
            Text("Shows your holdings treemap on Home, the same way a pinned thing does.")
                .dsText(.callout15).foregroundStyle(DS.textSecondary)
        }
    }

    // MARK: - Watching (add / remove / sort)

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
                }
                .listRowBackground(DS.surfaceSheet)
                // Swipe to pin reads the same everywhere in the app (Feed's
                // rows); the standing toggle below stayed easy to miss
                // (report 2026-07-09), so the expected gesture now works
                // here too — either one flips the same wallet.pinnedToHome.
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        DSHaptic.tap()
                        wallet.pinnedToHome.toggle()
                    } label: {
                        Label(wallet.pinnedToHome ? "Unpin" : "Pin",
                              systemImage: wallet.pinnedToHome ? "pin.slash" : "pin")
                    }
                    .tint(DS.tint)
                }
            }
            .onDelete { wallet.remove(at: $0) }
            .onMove { wallet.move(from: $0, to: $1) }
        } header: {
            Text("Watching").dsText(.label12)
                .foregroundStyle(DS.textSecondary)
        } footer: {
            Text("Swipe an address to pin your holdings to Home.")
                .dsText(.callout15).foregroundStyle(DS.textSecondary)
        }
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
        guard wallet.add(newAddress) else { return }
        newAddress = ""
        addressFieldFocused = false
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
                        Text(thing.content).dsText(.subhead13).foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(shortTime(thing.capturedAt))
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                }
                .listRowBackground(DS.surfaceSheet)
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

    private func shortTime(_ date: Date) -> String {
        let s = Date.now.timeIntervalSince(date)
        if s < 3600 { return "\(max(1, Int(s / 60)))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86_400))d"
    }
}
