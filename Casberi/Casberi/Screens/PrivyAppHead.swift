import SwiftUI
import SwiftData

/// ONE APP'S WALLET IN THE ROOM'S FRAME (prd §803e, re-laid by §1187, the
/// design canvas "People, apps and checks, the Apple pass"): the app's name
/// is the title; the box holds its mark, when Privy made the wallet, what the
/// wallet holds and each holding with its dollars, and when you last used it;
/// then the tiles (the app and the explorer ride the sheet's verbs,
/// `ThingSheetView.privyVerbs`), then what moved.
///
/// Export keys and Add funds are NOT here (user, 2026-09-17): this seat reads.
///
/// Stores no `Thing`: the app and its balance are values out of
/// `PrivyHomeStore`.
struct PrivyAppSheet<Tiles: View>: View {
    let app: PrivyHomeFeed.App
    @ViewBuilder let tiles: () -> Tiles
    @Environment(\.modelContext) private var modelContext

    private struct Moved: Identifiable {
        let id: String
        let title: String
        let received: Bool
        let usd: Double?
        let when: Date
    }
    @State private var moved: [Moved] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSRoomTitleRow(title: app.name)
                .padding(.horizontal, DSRoomChassis.inset)
                .settleIn(delay: 0.04)
            box
                .dsRoomBox()
                .padding(.top, DS.Space.s3)
                .settleIn(delay: 0.06)
            tiles()
                .padding(.top, DSRoomChassis.leadGap)
                .settleIn(delay: 0.08)
            if !moved.isEmpty {
                activity
                    .padding(.horizontal, DSRoomChassis.leadInset)
                    .padding(.top, DS.Space.s6)
                    .settleIn(delay: 0.12)
            }
        }
        .task(id: app.id) { loadActivity() }
    }

    private var box: some View {
        let store = PrivyHomeStore.shared
        let balances = app.wallets.compactMap { store.balances[PrivyHomeFeed.key($0.address)] }
        let usd = PrivyHomeFeed.appUSD(app, balances: store.balances)
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        let holdings = balances.flatMap { $0.bySymbol }
            .reduce(into: [String: Double]()) { $0[$1.key, default: 0] += $1.value }
            .filter { $0.value >= PrivyHomeFeed.fundedFloor }
            .sorted { $0.value > $1.value }
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s3) {
                PrivyAppMark(logoURL: app.logoURL)
                    .scaleEffect(DS.Face.seat / DS.Mark.row)
                    .frame(width: DS.Face.seat, height: DS.Face.seat)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: madeLine)
                        .dsText(.label12)
                        .foregroundStyle(DS.textSecondary)
                    if let usd {
                        Text(verbatim: mask ?? PrivyHomeFeed.usd(usd))
                            .dsText(.price40)
                            .monospacedDigit()
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    } else {
                        Text("Balance not read yet")
                            .dsText(.heading20)
                            .foregroundStyle(DS.textSecondary)
                    }
                }
            }
            // Two holdings fit the box; the rest are in the app.
            ForEach(holdings.prefix(2), id: \.key) { symbol, value in
                HStack(spacing: DS.Space.s3) {
                    Text(verbatim: symbol)
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                    Spacer(minLength: DS.Space.s2)
                    Text(verbatim: mask ?? PrivyHomeFeed.usd(value))
                        .dsText(.price17)
                        .monospacedDigit()
                        .foregroundStyle(DS.textPrimary)
                }
            }
            Spacer(minLength: 0)
            if let used = PrivyHomeFeed.lastUsed(app.lastActiveAt, now: .now) {
                DSStamp(word: used)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// "Made by Privy · Jan 1, 2026", or the wallet count when there are two.
    private var madeLine: String {
        var parts = [String(localized: "Made by Privy")]
        if let made = app.createdAt {
            parts.append(made.formatted(.dateTime.month(.abbreviated).day().year()))
        }
        if app.wallets.count > 1 { parts.append(String(localized: "\(app.wallets.count) wallets")) }
        return parts.joined(separator: " · ")
    }

    private var activity: some View {
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        return VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text("What moved")
                .dsText(.heading20)
                .foregroundStyle(DS.brandInk)
            ForEach(moved) { line in
                DSFeedRow(name: line.title,
                          line: Text(line.when, format: .dateTime.month(.abbreviated).day().year())) {
                    DSGlyphLead(glyph: line.received ? "arrow.down" : "arrow.up",
                                tint: line.received ? DS.confirm : DS.textPrimary)
                } trailing: {
                    if let usd = line.usd {
                        Text(verbatim: (mask ?? PrivyHomeFeed.usd(usd)))
                            .dsText(.price17)
                            .monospacedDigit()
                            .foregroundStyle(line.received ? DS.confirmInk : DS.textPrimary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func loadActivity() {
        let source = PrivyHomeFeed.source
        let prefix = PrivyHomeFeed.txPrefix(appID: app.id)
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == source && ($0.sourceRef?.starts(with: prefix) ?? false) },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchLimit = 12
        moved = ((try? modelContext.fetch(descriptor)) ?? []).filter(\.isLive).map {
            Moved(id: $0.sourceRef ?? $0.id.uuidString, title: $0.title,
                  received: $0.transferDirection == "received", usd: $0.transferUSD,
                  when: $0.capturedAt)
        }
    }
}
