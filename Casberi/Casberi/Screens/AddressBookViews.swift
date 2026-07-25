import SwiftUI
import SwiftData
import UIKit

/// The address book's shared pieces (prd §169, 2026-07-21): the kind mark, the
/// copy button every row carries, the name-an-address sheet, and the address
/// card behind a tap.

extension AddressBook.Entry {
    /// "0x9a2E…44b1 · Contract" — the address, plus what it turned out to be
    /// and where it came from, when either is known. A `.wallet` says nothing
    /// extra: a wallet is the unmarked case, and labelling it would put a word
    /// on every row that differentiates none of them.
    var subline: String {
        var parts = [short]
        if let label = kind.label { parts.append(label) }
        if let provenance { parts.append(provenance) }
        return parts.joined(separator: " · ")
    }
}

/// What an address IS, as a mark. A wallet is a WHO — it wears the same
/// identicon face the watched wallets and transfer stages use, so the same
/// address looks the same everywhere. Everything else is machinery and wears a
/// square glyph, which is what lets a fifty-row book separate people from
/// contracts with no grouping UI at all.
struct AddressMark: View {
    let entry: AddressBook.Entry
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let glyph = entry.kind.glyph {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(DS.fillFaint)
                    .frame(width: size, height: size)
                    .overlay {
                        Image(systemName: glyph)
                            .font(.system(size: size * 0.42, weight: .semibold))
                            .foregroundStyle(DS.textSecondary)
                    }
            } else {
                WalletFace(address: entry.address, size: size)
            }
        }
        // The kind reveal (prd §171, 2026-07-22). Detection lands
        // asynchronously — `eth_getCode` answers a beat after the row is on
        // screen — and the mark used to hard-swap from face to square glyph.
        // Now it turns over: the app worked out WHAT this address is while you
        // were looking at it, and that's a real moment, so it gets shown.
        // Keyed on the kind so nothing replays on a scroll or a rename.
        .transition(.scale(scale: 0.82).combined(with: .opacity))
        .id(entry.kind)
        .animation(DS.Motion.standard, value: entry.kind)
    }
}

/// Copy — the book's most-used verb, so it rides every row instead of hiding
/// one level down. States the outcome in place (the app's own "a control says
/// what happens, then says it happened" grammar) rather than firing a toast
/// from a list row.
struct CopyAddressButton: View {
    let address: String
    var expanded = false
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = address
            DSHaptic.success()
            withAnimation(DS.Motion.standard) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(DS.Motion.standard) { copied = false }
            }
        } label: {
            Group {
                if expanded {
                    Text(copied ? "Copied" : "Copy")
                        .dsText(.subhead13).fontWeight(.semibold)
                        .foregroundStyle(copied ? DS.confirm : DS.tint)
                } else {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(copied ? DS.confirm : DS.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(DS.fillFaint, in: RoundedRectangle(cornerRadius: 9,
                                                                       style: .continuous))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "Address copied" : "Copy address")
    }
}

/// One address's aggregate stats — count, span, and per-token net flow, built
/// once from the card's own `history` array (already the COMPLETE matching
/// set; the card's six-row list is a display slice of it, not a fetch limit).
struct HistorySummary {
    let count: Int
    let firstDate: Date?
    let lastDate: Date?
    /// Native-unit net flow, largest magnitude first. No USD figure: `Thing`
    /// carries no per-transaction USD field — only a portfolio-level snapshot
    /// exists (`WalletStore.ValueSample`) — so inventing one here would be
    /// exactly the fabricated status the honesty rule forbids.
    let netByToken: [(symbol: String, net: Double)]

    init(_ things: [Thing]) {
        count = things.count
        let dates = things.map(\.capturedAt)
        firstDate = dates.min()
        lastDate = dates.max()
        var sums: [String: Double] = [:]
        var order: [String] = []
        for thing in things {
            guard let amountText = thing.transferAmount,
                  let (magnitude, symbol) = Self.parse(amountText) else { continue }
            let signed = thing.transferDirection == "sent" ? -magnitude : magnitude
            if sums[symbol] == nil { order.append(symbol) }
            sums[symbol, default: 0] += signed
        }
        netByToken = order.map { ($0, sums[$0] ?? 0) }.sorted { abs($0.net) > abs($1.net) }
    }

    /// "0.9962 ETH" → (0.9962, "ETH") — the only shape `transferAmount`
    /// carries (a formatted display string, not a numeric+symbol pair).
    /// Unparseable strings return nil and are excluded from the net line
    /// without suppressing the count — a parse miss must never hide the rest
    /// of the summary.
    private static func parse(_ text: String) -> (Double, String)? {
        let parts = text.split(separator: " ")
        guard parts.count == 2, let value = Double(parts[0]) else { return nil }
        return (value, String(parts[1]))
    }
}

/// The address card (prd §169) — one address, everything the app honestly
/// knows about it: its name, what it is, the address itself with Copy, and
/// your own history together, pulled from the corpus. Purely informational —
/// watching lives solely on the book row's own star (prd §202), so the same
/// setting isn't a control in two places at once.
///
/// The history section is what makes this Casberi's rather than a contacts
/// app: landed transfers already carry `counterpartyAddress`, so the card can
/// show the relationship the corpus already recorded — without one extra
/// request.
/// Everything the corpus knows about one address, newest first — the shared
/// rule behind both the card's six-row preview and its "See all" screen, so
/// the two can never show different sets. Two kinds of belonging:
///   • a Wallet transaction where this address was the COUNTERPARTY (the
///     original "your history together" — someone you transacted with), and
///   • a Peer fill or Privacy Pools deposit MADE BY this address (prd §207):
///     those seats ride the watched wallets and have no separate home, so a
///     watched wallet's own fills and deposits live on its address-book card.
/// `walletAddress` is the owner both bridges stamp on every thing they land.
private func addressHistory(for address: String, in context: ModelContext) -> [Thing] {
    let key = AddressBook.key(for: address)
    let all = (try? context.fetch(FetchDescriptor<Thing>(
        predicate: #Predicate {
            $0.source == "Wallet" || $0.source == "Peer" || $0.source == "Privacy Pools"
        },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))) ?? []
    return all.filter { thing in
        if thing.source == "Wallet" {
            guard let cp = thing.counterpartyAddress else { return false }
            return AddressBook.key(for: cp) == key
        }
        guard let owner = thing.walletAddress else { return false }
        return AddressBook.key(for: owner) == key
    }
}

struct AddressCard: View {
    let entry: AddressBook.Entry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    private var book = AddressBook.shared
    @State private var renaming = false
    @State private var nameDraft = ""

    init(entry: AddressBook.Entry) { self.entry = entry }

    /// Live, so a rename or a kind landing repaints the card.
    private var current: AddressBook.Entry { book.entry(for: entry.address) ?? entry }

    /// The corpus's own record of this address — counterparty transactions
    /// plus its own Peer/Pool activity (see `addressHistory`), newest first.
    private var history: [Thing] {
        addressHistory(for: entry.address, in: modelContext)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.s3) {
                    AddressMark(entry: current, size: 64)
                        .padding(.top, DS.Space.s4)
                    Text(current.name)
                        .dsText(.heading22).foregroundStyle(DS.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(kindLine)
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)

                    addressRow
                    historySection
                    explorerRow
                }
                .padding(DS.Space.s4)
            }
            .scrollIndicators(.hidden)
            .dsAdaptiveContentWidth()
            // This address's OWN weather (prd §171, 2026-07-22). §129 kept the
            // wash exactly where the source IS the subject — the app-detail
            // page, the bridge setup header, the token quick sheet — and a
            // person's card is that case precisely: the subject of this screen
            // is an identity, so the screen wears its color. A wallet pours in
            // its face tint (the same hue its identicon, its switcher chip and
            // its band in the combined sheet already carry, so Mom looks like
            // Mom everywhere); machinery pours in Casberi's own tint, because
            // a contract has no identity of its own to borrow.
            .background(alignment: .top) {
                LinearGradient(stops: [
                    .init(color: pourHue.opacity(0.26), location: 0),
                    .init(color: pourHue.opacity(0.08), location: 0.45),
                    .init(color: pourHue.opacity(0), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                    .frame(height: 320)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            .dsPageBackground()
            .navigationTitle("Address")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Rename") {
                        nameDraft = current.name
                        renaming = true
                    }.tint(DS.tint)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(DS.tint)
                }
            }
            .alert("Name this address", isPresented: $renaming) {
                TextField("Name", text: $nameDraft)
                Button("Save") {
                    book.setName(nameDraft, for: entry.address)
                    DSHaptic.success()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("A blank name removes it from your book.")
            }
            .task { await AddressKind.detect(entry.address) }
        }
        .presentationBackground(DS.surfaceSheet)
        .dsColorScheme()
    }

    /// A wallet is a who and owns a hue; a contract or a Safe is machinery and
    /// borrows the app's. Mirrors the mark's own round-vs-square rule, so the
    /// card's color says the same thing its face does.
    private var pourHue: Color {
        switch current.kind {
        case .wallet, .unknown: return WalletFace.tint(for: current.address)
        case .contract, .safe:  return DS.tint
        }
    }

    private var kindLine: String {
        var parts: [String] = [current.kind.label ?? String(localized: "Wallet")]
        if let provenance = current.provenance { parts.append(provenance) }
        parts.append(String(localized: "named \(current.addedAt.formatted(.dateTime.month(.abbreviated).day()))"))
        return parts.joined(separator: " · ")
    }

    private var addressRow: some View {
        HStack(spacing: DS.Space.s3) {
            Text(current.address)
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                .monospaced()
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            CopyAddressButton(address: current.address, expanded: true)
        }
        .padding(DS.Space.s3)
        .dsWidgetSurface(fillOpacity: WalletCardStyle.fill)
    }

    @ViewBuilder
    private var historySection: some View {
        let things = history
        if !things.isEmpty {
            let summary = HistorySummary(things)
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text("Your history together · \(things.count)")
                    .dsText(.label12).foregroundStyle(DS.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let line = summaryLine(for: summary) {
                    Text(line)
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(Array(things.prefix(6)).keyed.enumerated()), id: \.element.id) { i, row in
                    let thing = row.thing
                    HStack(spacing: DS.Space.s3) {
                        KindGlyph(kind: thing.kind, size: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(thing.title).dsText(.subhead13)
                                .foregroundStyle(DS.textPrimary).lineLimit(1)
                            Text(thing.capturedAt.formatted(.dateTime.month(.abbreviated).day()))
                                .dsText(.label12).foregroundStyle(DS.textTertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    // The cascade (prd §171) — the app's own sheet grammar,
                    // which this card was missing: your history with someone
                    // arrives a beat at a time rather than as a slab.
                    .settleIn(delay: 0.05 + Double(i) * 0.04)
                }
                if things.count > 6 {
                    NavigationLink {
                        AddressHistoryScreen(entry: current)
                    } label: {
                        HStack(spacing: DS.Space.s2) {
                            Text("See all \(things.count)")
                                .dsText(.subhead13).fontWeight(.semibold)
                                .foregroundStyle(DS.tint)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DS.textTertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            .padding(DS.Space.s3)
            .dsWidgetSurface(fillOpacity: WalletCardStyle.fill)
        }
    }

    /// "since Mar 3 · net −0.80 ETH" — the two facts a count alone can't say.
    /// Only the fields that resolved to something real appear; a summary
    /// with nothing to add stays absent rather than printing an empty line.
    private func summaryLine(for summary: HistorySummary) -> String? {
        var parts: [String] = []
        if let first = summary.firstDate {
            parts.append(String(localized: "since \(first.formatted(.dateTime.month(.abbreviated).day()))"))
        }
        if !summary.netByToken.isEmpty {
            let shown = summary.netByToken.prefix(2).map { token -> String in
                let sign = token.net < 0 ? "−" : "+"
                return "\(sign)\(Self.formatAmount(abs(token.net))) \(token.symbol)"
            }
            var netText = "net " + shown.joined(separator: ", ")
            let remaining = summary.netByToken.count - 2
            if remaining > 0 {
                netText += " " + String(localized: "+\(remaining) more")
            }
            parts.append(netText)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func formatAmount(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 4
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.4f", value)
    }

    /// The one door out — and only for an address an explorer can actually
    /// serve (a Solana address on Etherscan would be a dead link).
    @ViewBuilder
    private var explorerRow: some View {
        if ENS.isHexAddress(current.address),
           let url = URL(string: "https://etherscan.io/address/\(current.address)") {
            Button {
                DSHaptic.tap()
                openURL(url)
            } label: {
                HStack(spacing: DS.Space.s2) {
                    Text("View on Etherscan").dsText(.callout15).foregroundStyle(DS.textSecondary)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.textTertiary)
                    Spacer(minLength: 0)
                }
                .padding(DS.Space.s3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsWidgetSurface(fillOpacity: WalletCardStyle.fill)
        }
    }
}

/// The whole of an address's history — the "See all" drill-down from the
/// card's own six-row preview (`AddressCard.historySection`). Same fetch, no
/// cap; a push, not a sheet, since it's a closer look at data the card
/// already showed a slice of, not a new top-level surface.
struct AddressHistoryScreen: View {
    let entry: AddressBook.Entry
    @Environment(\.modelContext) private var modelContext

    private var history: [Thing] {
        addressHistory(for: entry.address, in: modelContext)
    }

    var body: some View {
        List {
            // `.keyed` per the CLAUDE.md rule against keying a ForEach on a
            // derived array of raw `Thing` refs — see `ThingRowKeying.swift`.
            ForEach(history.keyed) { row in
                let thing = row.thing
                HStack(spacing: DS.Space.s3) {
                    KindGlyph(kind: thing.kind, size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(thing.title).dsText(.subhead13)
                            .foregroundStyle(DS.textPrimary).lineLimit(1)
                        Text(thing.capturedAt.formatted(.dateTime.month(.abbreviated).day().year()))
                            .dsText(.label12).foregroundStyle(DS.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
