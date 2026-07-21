import SwiftUI
import SwiftData

/// Every wallet transaction, day by day — the page behind the Wallet feed's
/// "See all" (2026-07-20, the surface split).
///
/// The feed previews five and stops; an unbounded stream at the head of a
/// screen that also carries the balance, warnings, holdings and DeFi reads
/// buried all four. So the stream got a door instead of a scroll: the feed
/// answers "anything new?", this page answers "show me everything".
///
/// Scoped by the same wallet the feed was scoped to — arriving here from a
/// wallet-scoped feed keeps that scope rather than silently widening it.
struct WalletHistoryScreen: View {
    /// nil = every watched wallet (the feed's "All" chip).
    let scope: String?

    @Environment(\.modelContext) private var modelContext
    @Bindable private var wallet = WalletStore.shared
    @State private var sheetThing: Thing?

    @Query(WalletHistoryScreen.descriptor) private var all: [Thing]

    /// Unlimited on purpose. This IS the "everything" page, and the door that
    /// opens it wears a count taken from the feed's own unlimited query — a
    /// fetchLimit here would let "See all · 700" open a page showing 500 with
    /// nothing saying so. The feed already holds every Thing in memory, so the
    /// cap bought no memory back either; the five-row preview is what keeps
    /// the common case cheap.
    private static var descriptor: FetchDescriptor<Thing> {
        FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Wallet" },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
    }

    private var visible: [Thing] {
        guard let scope else { return all }
        return all.filter { t in
            guard let a = t.walletAddress else { return false }
            return WalletWatch.sameAddress(a, scope)
        }
    }

    /// Day groups, newest first — the same grammar the feed's stream uses, so
    /// the page reads as a continuation of it rather than a different list.
    private var groups: [(String, [Thing])] {
        var order: [String] = []
        var byDay: [String: [Thing]] = [:]
        for thing in visible {
            let label = Self.dayLabel(thing.capturedAt)
            if byDay[label] == nil { order.append(label) }
            byDay[label, default: []].append(thing)
        }
        return order.map { ($0, byDay[$0] ?? []) }
    }

    private static let calendar = Calendar.current

    private static func dayLabel(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return String(localized: "Today") }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        return date.formatted(.dateTime.weekday(.wide).month().day())
    }

    private var title: String {
        guard let scope, let label = wallet.label(forAddress: scope) else {
            return String(localized: "Transactions")
        }
        return label
    }

    var body: some View {
        List {
            if visible.isEmpty {
                Section {
                    Text("Nothing here yet. Transactions land as they settle on chain.")
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowSeparator(.hidden)
                        .dsListCardRow()
                }
            } else {
                ForEach(groups, id: \.0) { label, rows in
                    Section {
                        ForEach(rows) { thing in
                            Button { sheetThing = thing } label: {
                                WalletHistoryRow(thing: thing,
                                                 walletLabel: walletLabel(thing))
                            }
                            .buttonStyle(.plain)
                            // Nothing draws a line (design law, zero
                            // exceptions) — a List hands out separators by
                            // default, so every row here opts out explicitly.
                            .listRowSeparator(.hidden)
                            .dsListCardRow()
                        }
                    } header: {
                        Text(label).dsText(.label12).foregroundStyle(DS.textSecondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftTopEdge()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $sheetThing) { ThingSheetView(thing: $0) }
    }

    /// Which watched wallet a transaction came from — only when more than one
    /// is watched AND the page isn't already scoped to one (in both other
    /// cases the answer is on the title, and repeating it per row is noise).
    private func walletLabel(_ thing: Thing) -> String? {
        guard scope == nil, wallet.addresses.count > 1 else { return nil }
        return wallet.label(forAddress: thing.walletAddress)
    }
}

/// One transaction line. Flat by construction — this page is a long list, so
/// the row stays a single shallow body rather than routing through the generic
/// widget path (the §gotchas render-depth lesson, applied by default).
private struct WalletHistoryRow: View {
    let thing: Thing
    let walletLabel: String?

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            KindGlyph(kind: thing.kind, size: 28)
                .overlay(alignment: .bottomTrailing) {
                    if thing.securityFlag == "poisoning" {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(DS.destructive)
                            .padding(3)
                            .background(Circle().fill(.black.opacity(0.55)))
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(thing.title).dsText(.body17).foregroundStyle(DS.textPrimary)
                    .lineLimit(2)
                if let walletLabel {
                    Text(walletLabel).dsText(.subhead13).foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text(shortTime(thing.capturedAt))
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
        }
        .contentShape(Rectangle())
    }

    private func shortTime(_ date: Date) -> String {
        let s = Date.now.timeIntervalSince(date)
        if s < 3600 { return "\(max(1, Int(s / 60)))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86_400))d"
    }
}
