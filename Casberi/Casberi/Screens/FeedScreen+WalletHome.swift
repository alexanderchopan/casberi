import SwiftUI

/// **HOME IS FOUR SHORT LISTS (user, 2026-10-08): Needs you, Coming up,
/// Spending, Transactions — five rows each, then a door.** Needs you, Coming
/// up and Spending open in place (they are bounded: what waits, what is
/// dated, the places this month); Transactions keeps its history screen.
extension FeedScreen {

    /// Rows a Home section shows before its door.
    static let walletHomeCap = 5

    @ViewBuilder
    func walletHomeSections(upcoming: [Thing], all: [Thing], nextEventID: UUID?) -> some View {
        let groups = walletComingUpDays(upcoming)
        let needs = groups.first { $0.0 == Self.needsYouGroup }?.1 ?? []
        let dated = groups.filter { $0.0 != Self.needsYouGroup }.flatMap(\.1)

        if !needs.isEmpty {
            let open = walletOpenSections.contains("needs")
            walletDaySections([(Self.needsYouGroup, open ? needs : Array(needs.prefix(Self.walletHomeCap)))],
                              boundary: nil, named: [Self.needsYouGroup], nextEventID: nextEventID)
            walletHomeDoor("needs", total: needs.count)
        }

        if !dated.isEmpty {
            let open = walletOpenSections.contains("coming")
            walletHomeTitle(String(localized: "Coming up"))
            walletDaySections(walletRowDays(open ? dated : Array(dated.prefix(Self.walletHomeCap))),
                              boundary: nil, nextEventID: nextEventID)
            walletHomeDoor("coming", total: dated.count)
        }

        // Spending reads every card and wallet together, so it stands on All.
        if selectedSeat == nil, selectedWallet == nil {
            walletSpendingSection
        }

        if !all.isEmpty {
            // The Spending reading starts here: this title stands whenever
            // Home has rows, and Spending's own section may not exist yet.
            walletHomeTitle(String(localized: "Transactions"))
                .task(id: walletSpendingKey) { await SpendingReading.shared.refresh(modelContext) }
            let stream = walletStream(all)
            walletStreamSections(stream.rows, ownMoves: stream.ownMoves, nextEventID: nextEventID)
            walletSeeAllSection(total: all.count)
        }
    }

    /// The due rows under the day each falls due, in the order given.
    func walletRowDays(_ rows: [FeedRow]) -> [(String, [FeedRow])] {
        var order: [String] = []
        var groups: [String: [FeedRow]] = [:]
        for row in rows {
            guard case .single(let item) = row.kind, let due = item.live?.dueAt else { continue }
            let label = dayLabel(due)
            if groups[label] == nil { order.append(label) }
            groups[label, default: []].append(row)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    /// A section's name, in the primary ramp: a section is named by what it
    /// is, and only a day wears the brand hue (prd §740).
    func walletHomeTitle(_ title: String) -> some View {
        Section {
            Text(verbatim: title).dsText(.heading20).foregroundStyle(DS.textPrimary)
                .padding(.leading, DS.Space.s4)
                .padding(.top, DS.Space.s6)
                .padding(.bottom, DS.Space.s1)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    /// "See all 9" under a capped section, "Show fewer" once it is open; no
    /// door when the cap already shows everything.
    @ViewBuilder
    func walletHomeDoor(_ key: String, total: Int, noun: String? = nil) -> some View {
        if total > Self.walletHomeCap {
            let open = walletOpenSections.contains(key)
            Section {
                DSMoreLink(title: open ? Text("Show fewer")
                                       : Text(verbatim: noun ?? String(localized: "See all \(total)"))) {
                    withAnimation(DS.Motion.standard) {
                        if open { walletOpenSections.remove(key) } else { walletOpenSections.insert(key) }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.s1)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: - Spending

    /// What left your accounts this month, by place (`Spending`): a line
    /// against last month to the same day, then the places, largest first.
    @ViewBuilder
    var walletSpendingSection: some View {
        let reading = SpendingReading.shared.reading
        if !reading.places.isEmpty {
                let open = walletOpenSections.contains("spending")
                let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Spending").dsText(.heading20).foregroundStyle(DS.textPrimary)
                        Text(verbatim: Self.spendingLine(reading, mask: mask))
                            .dsText(.label12).foregroundStyle(DS.textSecondary)
                    }
                    .padding(.leading, DS.Space.s4)
                    .padding(.top, DS.Space.s6)
                    .padding(.bottom, DS.Space.s1)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    ForEach(open ? reading.places : Array(reading.places.prefix(Self.walletHomeCap)),
                            id: \.name) { place in
                        SubscriptionRow(name: place.name, line: Text(verbatim: Self.spendingTimes(place.count))) {
                            Text(verbatim: mask ?? AppleWalletRoom.money(place.usd, "USD"))
                                .dsText(.price17).monospacedDigit().foregroundStyle(DS.textPrimary)
                        }
                        .listRowInsets(EdgeInsets(top: Self.rowAir, leading: DSRoomChassis.rowInset,
                                                  bottom: Self.rowAir, trailing: DSRoomChassis.rowInset))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                walletHomeDoor("spending", total: reading.places.count,
                               noun: String(localized: "All \(reading.places.count) places"))
        }
    }

    /// Re-read when the room's rows change or the demo flips.
    var walletSpendingKey: String { "\(DemoMode.isActive)|\(walletSubscriptionsKey)" }

    /// "$3,410 in October · $280 less than this point in September".
    static func spendingLine(_ reading: Spending.Reading, now: Date = .now, mask: String?) -> String {
        let month = now.formatted(.dateTime.month(.wide))
        let total = String(localized: "\(mask ?? AppleWalletRoom.money(reading.total, "USD")) in \(month)")
        guard mask == nil, let earlier = reading.earlier,
              let last = Calendar.current.date(byAdding: .month, value: -1, to: now) else { return total }
        let lastMonth = last.formatted(.dateTime.month(.wide))
        let diff = reading.total - earlier
        let compare: String
        if abs(diff) < 1 {
            compare = String(localized: "about the same as this point in \(lastMonth)")
        } else if diff < 0 {
            compare = String(localized: "\(AppleWalletRoom.money(-diff, "USD")) less than this point in \(lastMonth)")
        } else {
            compare = String(localized: "\(AppleWalletRoom.money(diff, "USD")) more than this point in \(lastMonth)")
        }
        return "\(total) · \(compare)"
    }

    static func spendingTimes(_ count: Int) -> String {
        count == 1 ? String(localized: "Once") : String(localized: "\(count) times")
    }
}
