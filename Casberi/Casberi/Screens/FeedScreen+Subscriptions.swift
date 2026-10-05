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

    /// **THE SUBSCRIPTIONS TILE'S LIST (prd §1111).** Add first, for anything
    /// no card, account or bill reading can see — it stands even with none,
    /// because it is how the first one gets here — then every one, most
    /// expensive first.
    @ViewBuilder
    var walletSubscriptionsSections: some View {
        let items = SubscriptionsReading.shared.items(in: walletSubscriptionSources)
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
