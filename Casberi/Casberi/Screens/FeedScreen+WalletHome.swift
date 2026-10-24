import SwiftUI

/// The Wallet's shared row parts: the accounts list's rows and its Rename,
/// the ways in, a subscription's and a place's row, the moves filter.
///
/// **HOME'S FIVE SHORT LISTS ARE DELETED (prd §1480, retiring §1232's):**
/// Home is the overview, six doors (`FeedScreen+WalletPages.swift`); the
/// transactions are Activity's, Subscriptions and the places Spending's,
/// Cards' asks Needs you's, and the accounts Following's.
extension FeedScreen {

    /// Rows a Home section shows before its door.
    static let walletHomeCap = 5

    /// What happened, without the states (`MoneyReceipt.isState`): the one
    /// filter Transactions and the history behind its door share (§837).
    static func walletMoves(_ things: [Thing]) -> [Thing] {
        things.filter { !MoneyReceipt.isState(source: $0.source, ref: $0.sourceRef) }
    }

    /// Home's lists in order, for the pill (prd §1219, §1232).
    static var walletHomeNames: [String] {
        [overviewName, accountsName, needsYouGroup, subscriptionsName, spendingName, cardsName, transactionsName]
    }

    static func walletHomeGlyph(_ name: String) -> String {
        switch name {
        // The pinned copy of Overview's name asks here too, so it wears the
        // card's own glyph, not the default.
        case overviewName: return ScopeTileGlyph.home
        case accountsName: return ScopeTileGlyph.accounts
        case needsYouGroup: return ScopeTileGlyph.alerts
        case subscriptionsName: return ScopeTileGlyph.subscriptions
        case spendingName: return ScopeTileGlyph.spending
        case cardsName: return ScopeTileGlyph.cards
        default: return ScopeTileGlyph.activity
        }
    }

    static var accountsName: String { String(localized: "Accounts") }
    static var subscriptionsName: String { String(localized: "Subscriptions") }
    static var spendingName: String { String(localized: "Spending") }
    static var cardsName: String { String(localized: "Cards") }
    static var transactionsName: String { String(localized: "Transactions") }

    // MARK: - Overview (prd §1257)

    // MARK: - Accounts (prd §1410)

    /// **THE WALLET ADDS ACCOUNTS WHERE THE FEED ADDS FOLLOWS (prd §1410,
    /// user: "we need a way while in wallet to be able to add accounts there
    /// same way like in feed you can add stuff to follow").** Until now the
    /// one door was the accounts menu's first row, which on the phone lives
    /// in the tray behind the face. Accounts is a list on Home like the
    /// others: the accounts menu's rows — the addresses you follow, then the
    /// apps folded in — five then a door, and its header wears the Feed's +
    /// (`walletAccountAdds`). A tap scopes the Wallet to one as the menu does,
    /// the one showing ticked, a second tap back to All; a hold on an address
    /// offers Stop following (§1302's rule) and on an app its settings.
    @ViewBuilder
    func walletAccountsSection(_ slots: [DSAccountSlot]) -> some View {
        let open = walletOpenSections.contains("accounts")
        let shown = open ? slots : Array(slots.prefix(Self.walletHomeCap))
        walletPanel(Self.accountsName, glyph: Self.walletHomeGlyph(Self.accountsName), things: []) {
            ForEach(shown) { slot in walletAccountRow(slot) }
            walletHomeDoor("accounts", total: slots.count)
        }
        .alert(String(localized: "Name this account"),
               isPresented: Binding(get: { walletNaming != nil }, set: { if !$0 { walletNaming = nil } })) {
            TextField(String(localized: "Name"), text: $walletNameDraft)
            Button(String(localized: "Save")) { saveWalletName() }
            Button(String(localized: "Cancel"), role: .cancel) { walletNaming = nil }
        } message: {
            Text(walletNaming.map(Self.isYourAccount) == true
                 ? String(localized: "Blank names it Your account.")
                 : String(localized: "Blank shows the address instead."))
        }
    }

    /// This phone's own account, or the demo's while the demo is on.
    static func isYourAccount(_ address: String) -> Bool {
        [YourAccountKey.address, YourAccountDemo.shownAddress].compactMap { $0 }
            .contains { WalletWatch.sameAddress($0, address) }
    }

    /// Through the watched wallet's own rename, which names the address in
    /// the book too, so the name is the name everywhere it is drawn. Your
    /// own account's blank goes back to "Your account"; any other's to the
    /// short address.
    func saveWalletName() {
        guard let address = walletNaming else { return }
        let draft = walletNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = draft.isEmpty && Self.isYourAccount(address) ? String(localized: "Your account") : draft
        if let watched = wallet.addresses.first(where: { WalletWatch.sameAddress($0.address, address) }) {
            wallet.rename(watched.id, to: name)
        } else if !name.isEmpty {
            AddressBook.shared.setName(name, for: address)
        }
        walletNaming = nil
    }

    /// One account: its face, its name over the line the menu gives it, the
    /// pick ticked in the pick's ink.
    @ViewBuilder
    func walletAccountRow(_ slot: DSAccountSlot) -> some View {
        let picked = slot.isShowing(chrome.walletScope)
        DSPushRow(title: Text(verbatim: slot.name),
                  subtitle: slot.sub.map { Text(verbatim: $0) },
                  fact: picked ? Text(Image(systemName: "checkmark")) : nil,
                  factTone: DS.pickInk, opens: false) {
            DSHaptic.selection()
            withAnimation(DS.Motion.standard) { chrome.walletScope = picked ? nil : slot.id }
        } leading: {
            // A face keeps its own ramp, centred in the Feed's column (§1170).
            Group {
                switch slot.faces.first {
                case .wallet(let address)?:
                    WalletFace(address: address, size: DS.Face.row, circular: true)
                case .mark(_, let source)?, .avatar(_, let source)?:
                    BridgeIcon(name: source, size: DS.Face.row)
                case nil:
                    BridgeIcon(name: slot.name, size: DS.Face.row)
                }
            }
            .frame(width: DS.Mark.row, height: DS.Mark.row)
        }
        .accessibilityLabel(Text(verbatim: picked ? "\(slot.name), showing" : slot.name))
        // The air the Subscriptions rows take, so the two lists read alike.
        .listRowInsets(EdgeInsets(top: Self.rowAir, leading: DSRoomChassis.rowInset,
                                  bottom: Self.rowAir, trailing: DSRoomChassis.rowInset))
        .feedRowBackground()
        .listRowSeparator(.hidden)
        .contextMenu {
            if case .wallet(let address)? = slot.faces.first {
                // Any account takes a name (user: "should be able to name
                // your account").
                Button {
                    walletNameDraft = slot.name == WalletStore.shortAddress(address) ? "" : slot.name
                    walletNaming = address
                } label: {
                    Label(String(localized: "Rename"), systemImage: "pencil")
                }
                // What you follow goes from a hold on its row (prd §1302),
                // through the book row's own unwatch, Undo included. Never
                // your own account: it holds this phone's keys.
                if !Self.isYourAccount(address), let entry = AddressBook.shared.entry(for: address) {
                    Button(role: .destructive) {
                        WalletUnwatch.perform(entry, context: modelContext, chrome: chrome)
                    } label: {
                        Label(String(localized: "Stop following"), systemImage: "trash")
                    }
                }
            } else {
                // An app's page, as the tray's hold offers it (prd §1159).
                Button { openAppPage(slot.name) } label: {
                    Label(String(localized: "Settings"), systemImage: "slider.horizontal.3")
                }
            }
        }
    }

    /// The two ways in, on the Accounts header and the Feed's Wallet section
    /// alike (prd §1410; §1347's one row grew): the tray that follows an
    /// address, and the catalogue landed on its Wallet card — 24 apps, too
    /// many for a menu, so the one door to the catalogue (§1234) as Social's
    /// More social apps is (§1303).
    ///
    /// **Create an account leads (prd §1422 item 4, §1433)** while this phone
    /// has no account of its own: Move, where it is made — or, when iCloud
    /// Keychain holds one's recovery key, taken back.
    var walletAccountAdds: [SectionAdd] {
        var adds: [SectionAdd] = []
        if YourAccountDemo.shownAddress == nil {
            adds.append(SectionAdd(label: String(localized: "Create an account"),
                                   glyph: ScopeTileGlyph.move) { chrome.moveTray = true })
        }
        return adds + [SectionAdd(label: String(localized: "Follow an account"),
                    glyph: ScopeTileGlyph.wallets) { feedSheet = .walletFollow },
         SectionAdd(label: String(localized: "Connect an app"),
                    glyph: ScopeTileGlyph.apps) {
            route.openCategory = CategoryFold.walletRoom
            route.present(.apps)
        }]
    }

    static var overviewName: String { String(localized: "Overview") }
    // MARK: - Subscriptions

    // MARK: - Cards

    static func cardOffersWords(_ count: Int) -> String {
        count == 1 ? String(localized: "1 offer") : String(localized: "\(count) offers")
    }

    /// One line per card: what it owes and when, its offers and when the
    /// first ends, else how many purchases this month.
    static func cardLine(_ card: WalletCardRoll.Card, mask: String?) -> String {
        var parts: [String] = []
        if let due = card.due {
            if let owed = card.owed {
                parts.append(String(localized: "\(mask ?? CardSpendRoom.money(owed, code: card.owedCurrency)) due \(WalletSubscriptionRow.day(due))"))
            } else {
                parts.append(String(localized: "Due \(WalletSubscriptionRow.day(due))"))
            }
        } else if let owed = card.owed {
            parts.append(String(localized: "\(mask ?? CardSpendRoom.money(owed, code: card.owedCurrency)) owed"))
        }
        if card.offers > 0 {
            if let ends = card.offerEnds {
                parts.append(String(localized: "\(cardOffersWords(card.offers)), first ends \(WalletSubscriptionRow.day(ends))"))
            } else {
                parts.append(cardOffersWords(card.offers))
            }
        }
        if parts.isEmpty {
            parts.append(card.purchases == 0 ? String(localized: "Nothing this month")
                                             : spendingTimes(card.purchases))
        }
        return parts.joined(separator: " · ")
    }

    /// The live things behind a list's rows, in order.
    static func things(_ rows: [FeedRow]) -> [Thing] {
        rows.compactMap { row in
            if case .single(let item) = row.kind { return item.live }
            return nil
        }
    }

    /// A Home list on the Feed's panel, under an identity the list knows
    /// before its rows are laid out — the Feed's own `sectionID` — so a
    /// tile can scroll to a list still off screen.
    func walletPanel<Rows: View>(_ name: String, glyph: String, things: [Thing],
                                 @ViewBuilder rows: @escaping () -> Rows) -> some View {
        ForEach([Self.sectionID(name)], id: \.self) { _ in
            panelSection(name, glyph: glyph, things: things, rows: rows)
        }
    }

    /// A tile's press: its list's name comes to the top, where the pill
    /// takes it over, and brightens once — the Feed's landing (prd §1208l),
    /// the section's identity first, then its name, as `settleFeedJump` does.
    func walletHomeJump(_ name: String) {
        Task { @MainActor in
            // The Feed's landing: at once, settled over a few passes.
            for pass in 0..<Self.landingPasses {
                if pass > 0 { try? await Task.sleep(for: .milliseconds(70)) }
                panelScrollTarget = Self.sectionID(name)
                await Task.yield()
            }
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(DS.Motion.standard) { landedSection = name }
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeOut(duration: 0.6)) { landedSection = nil }
        }
    }

    /// "See all 9" under a capped section, "Show fewer" once it is open; no
    /// door when the cap already shows everything.
    @ViewBuilder
    func walletHomeDoor(_ key: String, total: Int, noun: String? = nil) -> some View {
        if total > Self.walletHomeCap {
            let open = walletOpenSections.contains(key)
            Section {
                // The one More row (prd §1386): at the rows' inset, grey,
                // a chevron; never centred.
                DSMoreRow(title: open ? Text("Show fewer")
                                      : Text(verbatim: noun ?? String(localized: "See all \(total)")),
                          opens: !open) {
                    withAnimation(DS.Motion.standard) {
                        if open { walletOpenSections.remove(key) } else { walletOpenSections.insert(key) }
                    }
                }
                .listRowInsets(.init(top: Self.rowAir, leading: DSRoomChassis.rowInset,
                                     bottom: Self.rowAir, trailing: DSRoomChassis.rowInset))
                .listRowSeparator(.hidden)
                .feedRowBackground()
            }
        }
    }

    // MARK: - Spending

    /// Re-read when the room's rows change or the demo flips.
    var walletSpendingKey: String { "\(DemoMode.isActive)|\(walletSubscriptionsKey)" }

    /// "$3,410 in October · $280 less than this point in September"; on the
    /// week window (prd §1468) "$612 this week · $80 less than this point
    /// last week".
    static func spendingLine(_ reading: Spending.Reading, window: Spending.Window = .month,
                             now: Date = .now, mask: String?) -> String {
        let total = spendingTotal(reading, window: window, now: now, mask: mask)
        guard let compare = spendingCompare(reading, window: window, now: now, mask: mask) else { return total }
        return "\(total) · \(compare)"
    }

    /// "$3,410 in October" / "$612 this week".
    static func spendingTotal(_ reading: Spending.Reading, window: Spending.Window = .month,
                              now: Date = .now, mask: String?) -> String {
        let money = mask ?? AppleWalletRoom.money(reading.total, "USD")
        switch window {
        case .month: return String(localized: "\(money) in \(now.formatted(.dateTime.month(.wide)))")
        case .week:  return String(localized: "\(money) this week")
        }
    }

    /// "$280 less than this point in September", or nil under Hide balances
    /// or with nothing read last window.
    static func spendingCompare(_ reading: Spending.Reading, window: Spending.Window = .month,
                                now: Date = .now, mask: String?) -> String? {
        guard mask == nil, let earlier = reading.earlier else { return nil }
        return spendingAgainst(reading.total, earlier: earlier, window: window, now: now,
                               point: true)
    }

    /// The last window's name as the lines say it: "September" / "last week".
    static func spendingLastWindow(_ window: Spending.Window, now: Date = .now) -> String {
        switch window {
        case .month:
            let last = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
            return last.formatted(.dateTime.month(.wide))
        case .week:
            return String(localized: "last week")
        }
    }

    /// "$64 more than September" / "$12 less than this point in September"
    /// / "about the same as September" (within `spendingSameShare`, §83: a
    /// change that rounds to nothing has no word). `point` adds "this point
    /// in", the reading's own clause; a place's row leaves it out.
    static func spendingAgainst(_ now_: Double, earlier: Double, window: Spending.Window,
                                now: Date = .now, point: Bool) -> String {
        let last = spendingLastWindow(window, now: now)
        let name = point && window == .month ? String(localized: "this point in \(last)")
                 : point ? String(localized: "this point \(last)") : last
        let diff = now_ - earlier
        if abs(diff) < 1 || abs(diff) <= max(now_, earlier) * spendingSameShare {
            return String(localized: "about the same as \(name)")
        } else if diff < 0 {
            return String(localized: "\(AppleWalletRoom.money(-diff, "USD")) less than \(name)")
        } else {
            return String(localized: "\(AppleWalletRoom.money(diff, "USD")) more than \(name)")
        }
    }

    /// Within a tenth, the two read as the same (prd §1468).
    static let spendingSameShare = 0.10

    /// A place's line (prd §1468): how many times, then how it compares with
    /// the last window — more, less, about the same, "first time" when it
    /// had nothing then, "recurring" for a plan or a bill. Under Hide
    /// balances the count alone.
    static func spendingPlaceLine(_ place: Spending.Place, window: Spending.Window,
                                  now: Date = .now, mask: String?) -> String {
        let times = spendingTimes(place.count)
        guard mask == nil else { return times }
        if place.recurring { return "\(times) · \(String(localized: "recurring"))" }
        guard let earlier = place.earlier, earlier > 0 else {
            return "\(times) · \(String(localized: "first time"))"
        }
        return "\(times) · \(spendingAgainst(place.usd, earlier: earlier, window: window, now: now, point: false))"
    }

    /// One place's row, on Home and on the tile.
    func spendingPlaceRow(_ place: Spending.Place, window: Spending.Window, mask: String?) -> some View {
        SubscriptionRow(name: place.name,
                        line: Text(verbatim: Self.spendingPlaceLine(place, window: window, mask: mask))) {
            Text(verbatim: mask ?? AppleWalletRoom.money(place.usd, "USD"))
                .dsText(.price17).monospacedDigit().foregroundStyle(DS.textPrimary)
        }
        .listRowInsets(EdgeInsets(top: Self.rowAir, leading: DSRoomChassis.rowInset,
                                  bottom: Self.rowAir, trailing: DSRoomChassis.rowInset))
        .feedRowBackground()
        .listRowSeparator(.hidden)
    }

    static func spendingTimes(_ count: Int) -> String {
        count == 1 ? String(localized: "Once") : String(localized: "\(count) times")
    }
}
