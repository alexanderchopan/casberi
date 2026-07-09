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
    @Environment(ShellChrome.self) private var chrome
    @State private var syncing = false
    @State private var holdings = GenStream()

    @Query(walletRecentDescriptor) private var recent: [Thing]

    var body: some View {
        List {
            addSection.listRowSeparator(.hidden)
            if !wallet.addresses.isEmpty { watchingSection.listRowSeparator(.hidden) }
            if !holdings.els.isEmpty {
                Section {
                    GenRender(id: "root", els: holdings.els)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                }
            }
            if syncing {
                Section {
                    HStack(spacing: DS.Space.s2) {
                        ProgressView().controlSize(.small)
                        Text("Reading onchain activity…")
                            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    }
                    .listRowBackground(DS.surfaceSheet)
                }
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

    /// `announce` speaks the outcome as a toast — set when the person just
    /// added an address, so following a wallet ends in proof (or an honest
    /// "nothing reached") instead of silence. The passive onAppear sync stays
    /// quiet.
    private func sync(announce: Bool = false) {
        guard !syncing else { return }
        syncing = true
        Task {
            let added = await WalletIngest.refresh(context: modelContext)
            if let doc = await WalletIngest.holdingsChart() { holdings.paint(doc) }
            syncing = false
            let n = wallet.addresses.count
            let proof = n == 1 ? "1 address" : "\(n) addresses"
            store.registerConnected(id: "wallet", name: "Wallet", proof: proof,
                                    can: ["Reads your wallet's activity.",
                                          "Read-only — never trades or moves funds."])
            guard announce else { return }
            switch added {
            case .none:
                // nil = not one chain answered — offline, or the address isn't
                // a readable 0x address (ENS names aren't resolved yet).
                chrome.flash("Couldn't reach the chains — check the address is a 0x address.")
            case .some(0):
                chrome.flash("Watching — no recent onchain activity to land yet.")
            case .some(let count):
                chrome.flash("\(count) onchain \(count == 1 ? "thing" : "things") landed in your feed.")
            }
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
            }
            .onDelete { wallet.remove(at: $0) }
            .onMove { wallet.move(from: $0, to: $1) }
        } header: {
            Text("Watching").dsText(.label12)
                .foregroundStyle(DS.textSecondary)
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
        sync(announce: true)
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
