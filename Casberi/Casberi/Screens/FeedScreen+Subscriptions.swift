import SwiftUI
import SwiftData

/// THE WALLET'S SUBSCRIPTIONS TILE (prd §1105): the box says what they cost
/// a month and when each renews over the next five weeks; the list is every
/// one, most expensive first, under an Add row for anything no card, account
/// or bill reading can see.
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

    @ViewBuilder
    var walletSubscriptionsFigure: some View {
        let reading = SubscriptionsReading.shared
        let items = reading.items(in: walletSubscriptionSources)
        Group {
            if !items.isEmpty {
                WalletSubscriptionsFigure(items: items, total: reading.total(of: items))
                    .modifier(rowEntrance(2))
            } else if reading.read {
                WalletScopeEmptyFigure(section: .subscriptions)
            } else {
                Color.clear
            }
        }
        .task(id: walletSubscriptionsKey) {
            await reading.refresh(modelContext)
            subscriptionsProbe()
        }
    }

    /// `-subscriptionsSheet add|<name>` — raise the add tray, or one
    /// subscription's sheet by name, once the tile has read (DEBUG; NSLogs
    /// `subscriptionsSheet:`), because a `simctl`-launched capture has no tap.
    private func subscriptionsProbe() {
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

    @ViewBuilder
    var walletSubscriptionsSections: some View {
        let items = SubscriptionsReading.shared.items(in: walletSubscriptionSources)
        Section {
            DSDoorRow(icon: "plus", label: "Add a subscription") {
                feedSheet = .subscriptionAdd
            }
            .listRowInsets(EdgeInsets(top: 0, leading: DSRoomChassis.rowInset,
                                      bottom: 0, trailing: DSRoomChassis.rowInset))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
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
        if items.isEmpty, SubscriptionsReading.shared.read {
            walletSkeletonRowsSection
        }
    }
}

/// The box: what the subscriptions cost a month, then the five weeks.
struct WalletSubscriptionsFigure: View {
    let items: [Subscriptions.Item]
    let total: Subscriptions.Total

    var body: some View {
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text("\(mask ?? CardSpendRoom.money(total.monthly, code: "USD")) a month")
                .dsText(.heading24).foregroundStyle(DS.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(line(mask: mask))
                .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                .lineLimit(1)
            Spacer(minLength: DS.Space.s1)
            WalletCalendar(marks: items.compactMap { item in
                item.next.map { .init(id: item.id, day: $0, face: item.name, attention: item.was != nil) }
            })
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private func line(mask: String?) -> String {
        var parts = [items.count == 1 ? String(localized: "1 subscription")
                                      : String(localized: "\(items.count) subscriptions")]
        if total.counted > 0 {
            parts.append(String(localized: "\(mask ?? CardSpendRoom.money(total.yearly, code: "USD")) a year"))
        }
        if !total.uncounted.isEmpty {
            parts.append(String(localized: "not counted: \(ListFormatter.localizedString(byJoining: total.uncounted))"))
        }
        return parts.joined(separator: " · ")
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
