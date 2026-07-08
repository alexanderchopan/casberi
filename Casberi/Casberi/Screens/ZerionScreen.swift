import SwiftUI
import SwiftData

/// The Zerion things already in the corpus — newest first. A @Query so the
/// list updates live and the fetch runs once per store change, not twice per
/// body pass.
private let zerionRecentDescriptor: FetchDescriptor<Thing> = {
    var d = FetchDescriptor<Thing>(
        predicate: #Predicate { $0.source == "Zerion" },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
    )
    d.fetchLimit = 12
    return d
}()

/// Zerion, connected — the wallet's home in Casberi. The person manages WHICH
/// addresses are watched (paste to add, swipe to remove, drag to reorder — the
/// first address leads) and sees what's landed (recent onchain things from the
/// corpus). Read-only, stated plainly: watching an address can never trade or
/// move funds. Live sync is honestly gated — it arrives with the server; until
/// then the shape is real and the demo things show it.
struct ZerionScreen: View {
    @Bindable private var wallet = WalletStore.shared
    @State private var newAddress = ""
    @FocusState private var addressFieldFocused: Bool
    /// Holdings render through the gen-UI engine — allocation is magnitude, so
    /// the treemap is its native shape (holdings are SYNTHESIS, not things: a
    /// swap is an event and lands in the feed; a balance is a state and paints
    /// here). Demo values until live sync; the composition shape is final.
    @State private var holdings = GenStream()

    @Query(zerionRecentDescriptor) private var recent: [Thing]

    var body: some View {
        List {
            watchingSection
            if DemoState.seedsDemoData { holdingsSection }
            addSection
            if !recent.isEmpty { recentSection }
            footerSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle("Zerion")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            // Reorder/remove live behind Edit — drag to sort, red-minus to drop.
            ToolbarItem(placement: .topBarTrailing) { EditButton().tint(DS.textPrimary) }
        }
        .onAppear {
            guard DemoState.seedsDemoData else { return }
            holdings.paint([
                "root = Stack([hold])",
                "hold = TagMap(\"Holdings\", \"By value, across your addresses\", [ETH 4210, USDC 1840, SOL 980, LINK 460])",
            ])
        }
    }

    /// The wallet's composition — the same engine that paints Home. Live
    /// values arrive with sync; demo values show the shape (and are why this
    /// section only exists in the demo build — no fake numbers for real users).
    private var holdingsSection: some View {
        Section {
            GenRender(id: "root", els: holdings.els)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
        }
    }

    // MARK: - Watching (add / remove / sort)

    private var watchingSection: some View {
        Section {
            ForEach(wallet.addresses) { addr in
                HStack(spacing: DS.Space.s3) {
                    RoundedRectangle(cornerRadius: DS.Radius.appIcon(36), style: .continuous)
                        .fill(BridgeGlyph.color(for: "Zerion").opacity(0.22))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "wallet.bifold")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(BridgeGlyph.color(for: "Zerion"))
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
            Text("WATCHING").dsText(.label12).kerning(0.7)
                .foregroundStyle(DS.textSecondary)
        } footer: {
            if wallet.addresses.isEmpty {
                Text("Paste an address below — its activity lands in your feed.")
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
            }
        }
    }

    private var addSection: some View {
        Section {
            HStack(spacing: DS.Space.s2) {
                TextField("Paste an address (0x… or ENS)", text: $newAddress)
                    .dsText(.body17)
                    .focused($addressFieldFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Watch") {
                    if wallet.add(newAddress) {
                        newAddress = ""
                        addressFieldFocused = false
                        DSHaptic.success()
                    }
                }
                .dsText(.label12).foregroundStyle(.white)
                .padding(.horizontal, DS.Space.s3).frame(height: 30)
                .background(newAddress.trimmingCharacters(in: .whitespaces).count >= 6 ? DS.tint : DS.gray300,
                            in: Capsule(style: .continuous))
                .buttonStyle(.plain)
                .disabled(newAddress.trimmingCharacters(in: .whitespaces).count < 6)
            }
            .listRowBackground(DS.surfaceSheet)
        }
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
            Text("RECENT").dsText(.label12).kerning(0.7)
                .foregroundStyle(DS.textSecondary)
        }
    }

    private var footerSection: some View {
        Section {
        } footer: {
            Text("Read-only — watching can never trade or move funds. Live sync arrives with your account; these land from your addresses.")
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
