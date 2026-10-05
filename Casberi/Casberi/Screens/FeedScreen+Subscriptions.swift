import SwiftUI
import SwiftData

/// THE WALLET'S SUBSCRIPTIONS (prd §1105), a tile again since §1111 (a group
/// of Coming up from §1107): each renewal stands on its calendar and their
/// monthly cost is the statement; the list is Add, then every one, most
/// expensive first.
extension FeedScreen {

    /// The seats a scoped room reads subscriptions from: every one on All
    /// (nil), the picked app's on an app pick, none on an address — a wallet
    /// address pays no subscription a reading here can see.
    var walletSubscriptionSources: Set<String>? {
        if let seat = selectedSeat { return seat.source.map { [$0] } ?? [] }
        return chrome.walletScope == nil ? nil : []
    }

    /// What re-reads the tile: a refresh, or a change to the hand-added list.
    var walletSubscriptionsKey: String {
        let stamp = SubscriptionStore.shared.entries.values.map(\.at).max()?.timeIntervalSince1970 ?? 0
        return "\(chrome.refreshPulse):\(SubscriptionStore.shared.entries.count):\(stamp)"
    }

    /// `-subscriptionsSheet add|<name>` — raise the add tray, or one
    /// subscription's sheet by name, once the tile has read (DEBUG; NSLogs
    /// `subscriptionsSheet:`), because a `simctl`-launched capture has no tap.
    func subscriptionsProbe() {
        #if DEBUG
        guard !Self.subscriptionsProbed,
              let raw = UserDefaults.standard.string(forKey: "subscriptionsSheet"), !raw.isEmpty else { return }
        Self.subscriptionsProbed = true
        let items = SubscriptionsReading.shared.items
        NSLog("[Casberi] subscriptionsSheet: %@ (%d items: %@)", raw, items.count,
              items.map { "\($0.name) \($0.monthly ?? -1)" }.joined(separator: ", "))
        if raw == "add" {
            feedSheet = .subscriptionAdd
        } else if let item = items.first(where: { $0.name.localizedCaseInsensitiveCompare(raw) == .orderedSame }) {
            feedSheet = .subscription(item.id)
        }
        #endif
    }

    /// `-subscriptionsCategory "<Category>"` — press that category's tile on
    /// the Subscriptions map once the tile has read ("Other" for the one
    /// Other tile), because a `simctl`-launched capture has no tap (DEBUG;
    /// NSLogs `subscriptionsCategory:`).
    func subscriptionsCategoryProbe() {
        #if DEBUG
        guard !Self.subscriptionsCategoryProbed,
              let raw = UserDefaults.standard.string(forKey: "subscriptionsCategory"), !raw.isEmpty else { return }
        Self.subscriptionsCategoryProbed = true
        let all = SubscriptionsReading.shared.items(in: walletSubscriptionSources)
        let keys = subscriptionsReading(all).slices.map(\.key)
        let tile: String
        if raw.localizedCaseInsensitiveCompare("Other") == .orderedSame
            || raw.localizedCaseInsensitiveCompare(Self.subscriptionsOther) == .orderedSame {
            tile = SubscriptionCategories.otherKey
        } else {
            tile = keys.first { $0.localizedCaseInsensitiveCompare(raw) == .orderedSame } ?? raw
        }
        NSLog("[Casberi] subscriptionsCategory: %@ -> %@ (categories: %@)", raw, tile, keys.joined(separator: ", "))
        subscriptionsPick = SubscriptionsPick(tile: tile, over: SubscriptionCategories.signature(all))
        #endif
    }

    /// Items → categories, in dollars at the last read's rates; the
    /// catalogue's fallback reads as Other.
    func subscriptionsReading(_ items: [Subscriptions.Item]) -> SubscriptionCategories.Reading {
        let rates = SubscriptionsReading.shared.rates
        return SubscriptionCategories.read(items, usd: { WalletCash.usd($0, $1, rates: rates) },
                                           category: { BillersSource.category(ofMerchant: $0) },
                                           fallback: BillersSource.fallbackCategory)
    }

    /// The map's tiles at the group's measured width: the Holdings treemap's
    /// layout (true area, squarified, the tail folded into the one Other).
    func subscriptionsTiles(_ reading: SubscriptionCategories.Reading) -> [HoldingsTreemapLayout.Tile] {
        let width = subscriptionsMapWidth
        guard width > 0, reading.slices.count >= SubscriptionCategories.minTiles else { return [] }
        let tiles = HoldingsTreemapLayout.layout(
            reading.slices.map { (id: $0.key, share: $0.share) },
            in: CGRect(x: 0, y: 0, width: width, height: SubscriptionsSummary.mapHeight),
            gap: HoldingsTreemap.gap, minSide: HoldingsTreemap.minSide)
        return SubscriptionCategories.drawsMap(tiles: tiles.count) ? tiles : []
    }

    /// **THE SUBSCRIPTIONS TILE'S LIST (prd §1111).** Add first, for anything
    /// no card, account or bill reading can see — it stands even with none,
    /// because it is how the first one gets here — then every one, most
    /// expensive first.
    ///
    /// Between Add and the rows, a map of where the monthly cost goes, by
    /// the catalogue category of the app each bills for (prd §1112). The map
    /// is a FILTER: a pressed category narrows the rows under it and names
    /// what it costs, and a second press clears it. The box above already
    /// states the whole, so the map draws no total of its own.
    @ViewBuilder
    var walletSubscriptionsSections: some View {
        let all = SubscriptionsReading.shared.items(in: walletSubscriptionSources)
        let reading = subscriptionsReading(all)
        let tiles = subscriptionsTiles(reading)
        let drawn = tiles.map(\.id)
        let signature = SubscriptionCategories.signature(all)
        // A pick stands only over the set it was made on, and only while a
        // map is drawn to clear it from.
        let pick = subscriptionsPick.flatMap { $0.over == signature && !tiles.isEmpty ? $0.tile : nil }
        let items = SubscriptionCategories.items(all, in: pick, drawn: drawn, slices: reading.slices,
                                                 category: { BillersSource.category(ofMerchant: $0) },
                                                 fallback: BillersSource.fallbackCategory)
        Section {
            // The tile names the list (prd §1111), so no group header; Add
            // leads, because the list is the person's to build up.
            DSDoorRow(icon: "plus", label: "Add a subscription") {
                feedSheet = .subscriptionAdd
            }
            .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset,
                                      bottom: 0, trailing: DSRoomChassis.rowInset))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            // Only what has a monthly cost is totalled (§83): with none, the
            // list is Add and its rows, as before.
            if reading.counted > 0 {
                SubscriptionsSummary(reading: reading, tiles: tiles, pick: pick) { tile in
                    subscriptionsPick = tile.map { SubscriptionsPick(tile: $0, over: signature) }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { subscriptionsMapWidth = $0 }
                .task(id: SubscriptionsSummary.logKey(reading, tiles: drawn) + "|\(subscriptionsMapWidth > 0)") {
                    // Not before the width is measured: the map has not
                    // composed yet, and "no map" would be a false line.
                    guard subscriptionsMapWidth > 0 else { return }
                    SubscriptionsSummary.log(reading, tiles: tiles)
                }
                .listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DSRoomChassis.rowInset,
                                          bottom: DS.Space.s2, trailing: DSRoomChassis.rowInset))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            ForEach(items) { item in
                Button {
                    feedSheet = .subscription(item.id)
                } label: {
                    WalletSubscriptionRow(item: item)
                        .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .dsHover()
                .listRowInsets(EdgeInsets(top: Self.rowAir, leading: DSRoomChassis.rowInset,
                                          bottom: Self.rowAir, trailing: DSRoomChassis.rowInset))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
    }

    static var subscriptionsOther: String { String(localized: "Other") }
}

/// The Subscriptions group's pressed category, and the set it was pressed over.
struct SubscriptionsPick: Equatable {
    let tile: String
    let over: String
}

/// The Subscriptions tile's map (prd §1112), from two categories up: where
/// the monthly cost goes, and with a pick, what that part costs.
/// The map is the Holdings treemap's layout with categories for tokens:
/// true area, grey, a pressed tile lit in the tint and the rest quieted.
struct SubscriptionsSummary: View {
    let reading: SubscriptionCategories.Reading
    /// Empty when there is no map to draw (fewer than two tiles).
    let tiles: [HoldingsTreemapLayout.Tile]
    let pick: String?
    let onPick: (String?) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let mapHeight: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if !tiles.isEmpty {
                ZStack(alignment: .topLeading) {
                    ForEach(tiles, id: \.id) { tile in
                        tileView(tile)
                            .frame(width: tile.rect.width, height: tile.rect.height)
                            .offset(x: tile.rect.minX, y: tile.rect.minY)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: Self.mapHeight, maxHeight: Self.mapHeight, alignment: .topLeading)
            }
            // The box states the whole; a pick names its own part.
            if let pick {
                let figure = SubscriptionCategories.picked(pick, drawn: tiles.map(\.id), reading: reading)
                Text(verbatim: caption(pick, monthly: figure.monthly, count: figure.counted))
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Agents · $20.00 a month · 1 subscription".
    private func caption(_ pick: String, monthly: Double, count n: Int) -> String {
        let name = Self.name(pick)
        let money = BalancePrivacy.shared.withheld ? BalancePrivacy.mask
                                                   : CardSpendRoom.money(monthly, code: "USD")
        return n == 1 ? String(localized: "\(name) · \(money) a month · 1 subscription")
                      : String(localized: "\(name) · \(money) a month · \(n) subscriptions")
    }

    /// A tile's name: the category's own, Other for the one Other.
    static func name(_ key: String) -> String {
        key == SubscriptionCategories.otherKey ? FeedScreen.subscriptionsOther : key
    }

    @ViewBuilder
    private func tileView(_ tile: HoldingsTreemapLayout.Tile) -> some View {
        let isOther = tile.id == SubscriptionCategories.otherKey
        let isLit = pick == tile.id
        let small = min(tile.rect.width, tile.rect.height) < 72
        Button {
            DSHaptic.selection()
            withAnimation(reduceMotion ? nil : DS.Motion.standard) {
                onPick(isLit ? nil : tile.id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                if !isOther {
                    Image(systemName: CategoryFold.glyph(for: tile.id))
                        .dsGlyph(small ? .body : .title)
                        .foregroundStyle(isLit ? Color.white : DS.textPrimary)
                }
                Spacer(minLength: 0)
                Text(verbatim: HoldingsTreemapLayout.percent(tile.share))
                    .dsText(small ? .label12 : .price17)
                    .monospacedDigit()
                    .foregroundStyle(isLit ? Color.white : DS.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(verbatim: Self.name(tile.id))
                    .dsText(.label12)
                    .foregroundStyle(isLit ? Color.white : DS.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(small ? DS.Space.s2 : DS.Space.s3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: small ? 12 : 14, style: .continuous)
                .fill(isLit ? DS.tint : DS.fillFaint))
            .opacity(pick != nil && !isLit ? 0.35 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(Text(verbatim: "\(Self.name(tile.id)), \(HoldingsTreemapLayout.percent(tile.share))"))
        .accessibilityAddTraits(isLit ? .isSelected : [])
    }

    /// What re-logs the map: its slices, what it drew, and Hide balances.
    static func logKey(_ reading: SubscriptionCategories.Reading, tiles: [String]) -> String {
        reading.slices.map { "\($0.key)=\($0.monthly)" }.joined(separator: ",")
            + "|" + tiles.joined(separator: ",") + "|\(BalancePrivacy.shared.withheld)"
    }

    /// `subscriptionsMap| <Category> | <monthly> | <share>`, one line per
    /// category (DEBUG): how much of a real phone's spend lands in Other.
    /// Hide balances logs shares only.
    static func log(_ reading: SubscriptionCategories.Reading, tiles: [HoldingsTreemapLayout.Tile]) {
        #if DEBUG
        let hidden = BalancePrivacy.shared.withheld
        for slice in reading.slices {
            let share = HoldingsTreemapLayout.percent(slice.share)
            if hidden {
                NSLog("[Casberi] subscriptionsMap| %@ | %@", name(slice.key), share)
            } else {
                NSLog("[Casberi] subscriptionsMap| %@ | %@ | %@", name(slice.key),
                      String(format: "%.2f", slice.monthly), share)
            }
        }
        let other = tiles.first { $0.id == SubscriptionCategories.otherKey }
        NSLog("[Casberi] subscriptionsMap| %d tiles%@%@", tiles.count,
              tiles.isEmpty ? " (no map)" : "",
              other.map { " · Other tile \(HoldingsTreemapLayout.percent($0.share))" } ?? "")
        #endif
    }
}

/// One subscription in the list: its face, its name, what it costs a month,
/// and one line — a word when it carries one, then when it renews and what
/// pays it.
struct WalletSubscriptionRow: View {
    let item: Subscriptions.Item

    var body: some View {
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        DSFeedRow(name: item.name, line: Self.line(item, mask: mask)) {
            SubscriptionFace(name: item.name)
        } trailing: {
            if let monthly = item.monthly {
                Text(verbatim: mask ?? CardSpendRoom.money(monthly, code: item.currency))
                    .dsText(.price17).monospacedDigit().foregroundStyle(DS.textPrimary)
            } else if let amount = item.amount {
                Text(verbatim: mask ?? CardSpendRoom.money(amount, code: item.currency))
                    .dsText(.price17).monospacedDigit().foregroundStyle(DS.textTertiary)
            }
        }
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "Price rise · was $10.00 · Renews Oct 24 · Apple Card".
    static func line(_ item: Subscriptions.Item, mask: String?) -> Text {
        var rest: [String] = []
        if item.isYearly, let amount = item.amount {
            rest.append(String(localized: "\(mask ?? CardSpendRoom.money(amount, code: item.currency)) yearly"))
        }
        if let next = item.next {
            if next < Calendar.current.startOfDay(for: .now) {
                rest.append(String(localized: "Expected \(day(next))"))
            } else if item.cadenceDays == nil {
                rest.append(String(localized: "Next charge \(day(next))"))
            } else {
                rest.append(String(localized: "Renews \(day(next))"))
            }
        }
        if let pays = item.paysWith { rest.append(pays) }
        let tail = Text(verbatim: rest.joined(separator: " · "))
        guard let was = item.was else { return tail }
        let word = Text("Price rise · was \(mask ?? CardSpendRoom.money(was, code: item.currency))")
            .foregroundStyle(DS.attentionInk).fontWeight(.semibold)
        return rest.isEmpty ? word : word + Text(verbatim: " · ") + tail
    }
}
