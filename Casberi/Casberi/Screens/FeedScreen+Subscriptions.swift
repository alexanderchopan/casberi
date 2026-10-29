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

    /// `-delegationSheet YES|unknown|<0x…>` — with `-openRoom Wallet -openSection
    /// permissions`, raise the first delegation's sheet (or the named
    /// contract's) once the read has landed (DEBUG; NSLogs `delegationSheet:`
    /// with every delegation), because a `simctl`-launched capture has no tap
    /// (prd §1594).
    func delegationSheetProbe() {
        #if DEBUG
        guard !Self.delegationSheetProbed,
              let raw = UserDefaults.standard.string(forKey: "delegationSheet"), !raw.isEmpty else { return }
        let all = WalletDelegation.all(walletLive.acting)
        guard !all.isEmpty else { return }
        Self.delegationSheetProbed = true
        NSLog("[Casberi] delegationSheet: %@ (%d: %@)", raw, all.count,
              all.map { "\($0.name ?? "unknown") \($0.delegate) \($0.networks.joined(separator: ",")) app=\($0.app?.scheme ?? "-")" }
                .joined(separator: " | "))
        // `unknown` draws the red sheet over the first one's accounts: the
        // demo's only delegate is MetaMask's, and nothing names this contract.
        if raw == "unknown" {
            feedSheet = .delegation(WalletDelegation(delegate: "0x5e1d0c7a2b9f4e3d8c6a1b0f7e2d9c4a3b8f9f2c",
                                                     name: nil, vendor: nil,
                                                     networks: all[0].networks, accounts: all[0].accounts))
            return
        }
        feedSheet = .delegation(all.first { $0.delegate == raw.lowercased() } ?? all[0])
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
        Self.subscriptionsTiles(reading, width: subscriptionsMapWidth)
    }

    /// The same layout at any measured width: Day's map has its own (§1117).
    static func subscriptionsTiles(_ reading: SubscriptionCategories.Reading,
                                   width: CGFloat) -> [HoldingsTreemapLayout.Tile] {
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
            DSDoorRow(icon: "plus", title: Text(SubscriptionWords.track)) {
                feedSheet = .subscriptionAdd
            }
            .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset,
                                      bottom: 0, trailing: DSRoomChassis.rowInset))
            .feedRowBackground()
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
                .walletListRow()
            }
            ForEach(items) { item in
                Button {
                    feedSheet = .subscription(item.id)
                } label: {
                    WalletSubscriptionRow(item: item, writes: Self.walletSubscriptionWrites(item))
                        .contentShape(Rectangle())
                        // Just tracked: one pink pass as it lands (prd §1199).
                        .arrivalWash(SubscriptionStore.shared.justTracked(item.id), hue: DS.brand)
                }
                .buttonStyle(RowPress())
                .contextMenu { stopTrackingMenu(item) }
                .dsHover()
                .walletListRow()
            }
        }
    }

    static var subscriptionsOther: String { String(localized: "Other") }

    /// A plan's name as the row says it: the catalogue app's own name when
    /// the merchant is one (§1113's rule), else the merchant's name without
    /// its web suffix when that is a service we draw a mark for ("Netflix.com"
    /// is Netflix), else the name as the card wrote it.
    static func shownName(_ raw: String) -> String {
        if let offer = ServiceIdentity.offer(forPlan: raw, in: ServiceLinks.catalogue) { return offer }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex,
              name[name.index(after: dot)...].allSatisfy(\.isLetter) else { return raw }
        let base = String(name[..<dot])
        return BridgeIcon.hasMark(base) ? base : raw
    }

    /// The list this plan's service mails you from, as its row says it
    /// (§1113's join, read by `ServiceLinks` from the tile's `.task`).
    static func walletSubscriptionWrites(_ item: Subscriptions.Item) -> String? {
        guard let listID = ServiceLinks.shared.byPlan[item.id]?.listID,
              let list = MailSubscriptionsReading.shared.items.first(where: { $0.id == listID })
        else { return nil }
        return MailSubscriptions.writesWords(list)
    }
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
    /// Day's map (prd §1117): the measure is mails a month, not dollars.
    var mails = false
    let onPick: (String?) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// ONE SHORT ROW (user, 2026-10-10: the map was the biggest thing on
    /// the page and said the least): the split at a glance, the list a
    /// screen higher. Too short for two rows, so the layout lays one.
    static let mapHeight: CGFloat = 64

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
                    .monospacedDigit()
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Agents · $20.00 a month · 1 subscription"; Day's, "Work · 3 mails a
    /// month · 2 subscriptions".
    private func caption(_ pick: String, monthly: Double, count n: Int) -> String {
        let name = Self.name(pick)
        if mails {
            return [name, MailSubscriptionsFigure.statement(Int(monthly.rounded())),
                    String(localized: "\(n) subscriptions")].joined(separator: " · ")
        }
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
        // A narrow tile keeps its words and gives up its glyph.
        let roomy = tile.rect.width >= 112
        // …and its side pad (2026-10-22 nightly, `walk-wallet-subscriptions.png`):
        // a tile near `minSide` lost 24 of its 44pt to the s3 pad and drew
        // its share as "1…".
        let narrow = tile.rect.width < 72
        Button {
            DSHaptic.selection()
            withAnimation(reduceMotion ? nil : DS.Motion.standard) {
                onPick(isLit ? nil : tile.id)
            }
        } label: {
            HStack(spacing: DS.Space.s2) {
                if roomy {
                    Image(systemName: isOther ? "ellipsis" : CategoryFold.glyph(for: tile.id))
                        .dsGlyph(.body)
                        .foregroundStyle(isLit ? Color.white : DS.textPrimary)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: HoldingsTreemapLayout.percent(tile.share))
                        .dsText(.price17)
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
                Spacer(minLength: 0)
            }
            .padding(.horizontal, narrow ? DS.Space.s1 : DS.Space.s3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isLit ? DS.pickInk : DS.fillFaint))
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
    static func log(_ reading: SubscriptionCategories.Reading, tiles: [HoldingsTreemapLayout.Tile],
                    mails: Bool = false) {
        #if DEBUG
        // Day's map logs its own lines (prd §1117): mails are no balance, so
        // Hide balances does not withhold them.
        if mails {
            for slice in reading.slices {
                NSLog("[Casberi] mailSubscriptionsMap| %@ | %d | %@", name(slice.key),
                      Int(slice.monthly.rounded()), HoldingsTreemapLayout.percent(slice.share))
            }
            let other = tiles.first { $0.id == SubscriptionCategories.otherKey }
            NSLog("[Casberi] mailSubscriptionsMap| %d tiles%@%@", tiles.count,
                  tiles.isEmpty ? " (no map)" : "",
                  other.map { " · Other tile \(HoldingsTreemapLayout.percent($0.share))" } ?? "")
            return
        }
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
    /// How often this service's list writes, when §1113's identity found one
    /// ("Writes every two weeks"): the row names the other room (prd §1117).
    var writes: String? = nil

    var body: some View {
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        // The app's own name when the card's merchant is a catalogue app
        // ("Netflix.com" is Netflix, §1113's rule), else the merchant's.
        SubscriptionRow(name: FeedScreen.shownName(item.name),
                        line: Self.line(item, mask: mask, writes: writes)) {
            if item.amount == 0 {
                Text(verbatim: SubscriptionWords.free)
                    .dsText(.price17).foregroundStyle(DS.textSecondary)
            } else if let monthly = item.monthly {
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

    /// "Price rise · was $10.00 · Renews Oct 24 · Apple Card · Writes about
    /// monthly".
    static func line(_ item: Subscriptions.Item, mask: String?, writes: String? = nil) -> Text {
        var rest: [String] = []
        if item.isYearly, let amount = item.amount, amount > 0 {
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
        if let writes { rest.append(writes) }
        let tail = Text(verbatim: rest.joined(separator: " · "))
        guard let was = item.was else { return tail }
        let word = Text("Price rise · was \(mask ?? CardSpendRoom.money(was, code: item.currency))")
            .foregroundStyle(DS.attentionInk).fontWeight(.semibold)
        return rest.isEmpty ? word : word + Text(verbatim: " · ") + tail
    }
}

// MARK: - Stop tracking from the row (prd §1301)

extension FeedScreen {
    /// A plan you track by hand stops from its row's hold, the sheet's act one
    /// step nearer (user, 2026-10-14: "yes do all", of "let a hold on the row
    /// offer Stop tracking, skipping the sheet"). Choosing it from the menu is
    /// the consent, so no second dialog; the notice says what happened, and
    /// tracking it again is the tray's one tap. A card's plan draws no menu:
    /// what a card shows stays (the sheet's own rule).
    @ViewBuilder
    func stopTrackingMenu(_ item: Subscriptions.Item) -> some View {
        StopMenus.plan(item, context: modelContext, chrome: chrome)
    }

    /// A mail list you added (prd §1115), the same way.
    @ViewBuilder
    func stopTrackingMenu(_ item: MailSubscriptions.Item) -> some View {
        StopMenus.list(item, context: modelContext, chrome: chrome)
    }
}

/// **A ROW'S HOLD STOPS IT, WHEREVER THE ROW STANDS (prd §1301, §1317)**:
/// its room's list and Sources' list under the box draw the same menu, so a
/// change to what stopping does reaches both.
@MainActor
enum StopMenus {
    /// A plan you track by hand; a card's plan draws no menu.
    @ViewBuilder
    static func plan(_ item: Subscriptions.Item, context: ModelContext, chrome: ShellChrome) -> some View {
        if let manualID = item.manualID {
            Button(role: .destructive) {
                SubscriptionStore.shared.remove(manualID)
                // The list reads its own fetch, so it is read again now.
                Task { await SubscriptionsReading.shared.refresh(context) }
                chrome.flash(String(localized: "Stopped tracking \(item.name)"))
            } label: {
                Label(String(localized: "Stop tracking"), systemImage: "trash")
            }
        }
    }

    /// A mail list you added (prd §1115), the same way.
    @ViewBuilder
    static func list(_ item: MailSubscriptions.Item, context: ModelContext, chrome: ShellChrome) -> some View {
        if item.byYou, let address = item.address {
            Button(role: .destructive) {
                MailSubscriptionStore.shared.remove(address: address)
                MailSubscriptionsReading.shared.refresh(context)
                chrome.flash(String(localized: "Stopped tracking \(item.name)"))
            } label: {
                Label(String(localized: "Stop tracking"), systemImage: "trash")
            }
        }
    }

    /// What you follow (§1301). Where stopping also takes what it brought in
    /// (`FollowingReading.prunes`), the menu asks once more inside itself,
    /// since that removal cannot be taken back.
    @ViewBuilder
    static func follow(_ item: Following.Item, _ room: Following.Room,
                       context: ModelContext, chrome: ShellChrome) -> some View {
        let stop = {
            FollowingReading.shared.stop(item, context: context)
            FollowingReading.shared.refresh(room, context: context)
            chrome.flash(String(localized: "Stopped following \(item.name)"))
        }
        if item.removable {
            if FollowingReading.prunes(item.seat) {
                Menu {
                    Button(role: .destructive, action: stop) {
                        Text("\(room.stopWord) and remove what it brought in")
                    }
                } label: {
                    Label(room.stopWord, systemImage: "trash")
                }
            } else {
                Button(role: .destructive, action: stop) {
                    Label(room.stopWord, systemImage: "trash")
                }
            }
        }
    }
}
