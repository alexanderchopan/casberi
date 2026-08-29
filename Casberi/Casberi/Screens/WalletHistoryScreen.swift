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
        // Through the resolution cache, not a raw compare — things carry the
        // resolved hex, the scope is the watched spelling (2026-07-20).
        return all.filter { wallet.scopeMatches($0.walletAddress, scope: scope) }
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
                        .listRowBackground(Color.clear)
                }
            } else {
                ForEach(groups, id: \.0) { label, rows in
                    Section {
                        ForEach(rows.keyed) { row in
                            // Corollary 3 (build 176) — see `ThingRowKeying`.
                            if let thing = row.live {
                                Button { sheetThing = thing } label: {
                                    WalletHistoryRow(thing: thing,
                                                     walletLabel: walletLabel(thing))
                                }
                                .buttonStyle(.plain)
                                // Nothing draws a line (design law, zero
                                // exceptions) — a List hands out separators by
                                // default, so every row here opts out explicitly.
                                .listRowSeparator(.hidden)
                                // No card per row (prd §212, 2026-07-25). This page
                                // is the room's longest list, and `dsListCardRow`
                                // gave all 128 transactions an opaque surface and a
                                // shadow each — a stack of parcels where the day
                                // header is already doing the grouping. The rows sit
                                // on the page now; the header separates them.
                                .listRowBackground(Color.clear)
                                // The insets go WITH the cards. A List sizes its
                                // default row insets for a card's own body, so
                                // keeping them over a bare row left ~95pt of air
                                // per transaction and the page read as a list of
                                // ghosts. `WalletRow`'s own vertical padding is the
                                // rhythm now.
                                .listRowInsets(EdgeInsets(top: 0, leading: DS.Space.s4,
                                                          bottom: 0, trailing: DS.Space.s4))
                            }
                        }
                    } header: {
                        WalletSectionLabel(title: label)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle(title)
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

/// One transaction line — the room's shared row anatomy (prd §212), with the
/// thing's own `KindGlyph` as its mark. Flat by construction: this page is a
/// long list, so the row stays a single shallow body rather than routing
/// through the generic widget path (the §gotchas render-depth lesson, applied
/// by default) — `WalletRow` is itself a plain HStack, so it costs no depth.
///
/// The title WRAPS here (unlike the room's label-ish rows): a transaction
/// title is a sentence — "Received 0.42 ETH from coinbase.eth" — and the tail
/// of it is the part worth reading.
private struct WalletHistoryRow: View {
    let thing: Thing
    let walletLabel: String?

    /// Liveness guard (build 188 — see `ThingRowKeying.swift`). SwiftUI
    /// re-evaluates a LEAF view's body on the model's own observation,
    /// independent of the parent that made it, so a guard in the parent's
    /// `ForEach` closure cannot protect a row already in the tree. The
    /// original body moved to `liveBody`; everything it reads now sits behind
    /// this check.
    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
        WalletRow(mark: .kind(thing.kind, flagged: thing.isFlagged,
                              // What this row DID, not what kind it is (prd
                              // §516). Every row on this page is
                              // `.transaction`, so the kind's own `⇄` was a
                              // column of one repeated glyph — see
                              // `WalletActionMark` for what it may read and
                              // what it refuses to guess.
                              symbol: WalletActionMark.symbol(
                                        direction: thing.transferDirection,
                                        sourceRef: thing.sourceRef)),
                  title: WalletValue.title(thing), subtitle: walletLabel, titleWraps: true) {
            Text(shortTime(thing.capturedAt))
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .monospacedDigit()
        }
    }

    private func shortTime(_ date: Date) -> String {
        let s = Date.now.timeIntervalSince(date)
        if s < 3600 { return "\(max(1, Int(s / 60)))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86_400))d"
    }
}
