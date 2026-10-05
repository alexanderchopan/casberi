import SwiftUI
import SwiftData

/// ONE SUBSCRIPTION (prd §1105): what it costs and what changed, the facts,
/// and the door to the provider's own billing page. Casberi cancels nothing
/// and changes no plan (acts-by-seat are declined); a hand-added one can be
/// removed from the list, which is the only write here.
///
/// It composes `SubscriptionPage`, the anatomy Day's `MailSubscriptionSheet`
/// composes too, and its first doors are this service's other pages when it
/// has them (`ServiceLinks`): the app's feed, and the list that mails you.
struct SubscriptionSheet: View {
    let id: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Environment(ShellChrome.self) private var chrome
    @State private var confirmingRemove = false

    private var item: Subscriptions.Item? {
        SubscriptionsReading.shared.items.first { $0.id == id }
    }

    var body: some View {
        ScrollView {
            if let item {
                content(item)
            }
        }
        // Solid, and as tall as its page (no see-through sheets, prd §886).
        .subscriptionSheet()
        // The other pages this service has, read once the sheet is up (§628).
        .task(id: id) {
            await ServiceLinks.shared.refresh(modelContext, seats: store.bridges.map(\.name))
        }
        .confirmationDialog(Text("Remove \(item?.name ?? "")?"), isPresented: $confirmingRemove,
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let manualID = item?.manualID { SubscriptionStore.shared.remove(manualID) }
                dismiss()
            }
        } message: {
            Text("Only what you added goes. A charge a card shows stays.")
        }
    }

    private func money(_ amount: Double, _ code: String, _ mask: String?) -> String {
        mask ?? CardSpendRoom.money(amount, code: code)
    }

    private func content(_ item: Subscriptions.Item) -> some View {
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        return SubscriptionPage(name: item.name,
                                statement: statement(item, mask: mask),
                                facts: facts(item, mask: mask),
                                doors: doors(item))
    }

    private func statement(_ item: Subscriptions.Item, mask: String?) -> SubscriptionStatement? {
        guard let amount = item.amount else { return nil }
        return SubscriptionStatement(figure: money(amount, item.currency, mask),
                                     word: cadenceWord(item),
                                     note: item.was.map { Text("Up from \(money($0, item.currency, mask))") })
    }

    /// When · since · so far · who · found in — the order Day's sheet keeps.
    private func facts(_ item: Subscriptions.Item, mask: String?) -> [SubscriptionFact] {
        var out: [SubscriptionFact] = []
        if let next = item.next {
            out.append(.init(item.cadenceDays == nil ? String(localized: "Next charge") : String(localized: "Renews"),
                             next.formatted(.dateTime.month(.wide).day().year())))
        }
        if let monthly = item.monthly, item.isYearly {
            out.append(.init(String(localized: "A month"), money(monthly, item.currency, mask)))
        }
        if let since = item.since {
            out.append(.init(String(localized: "Since"), since.formatted(.dateTime.month(.wide).year())))
        }
        if let paid = item.paid {
            out.append(.init(String(localized: "Paid so far"), money(paid, item.currency, mask)))
        }
        if let pays = item.paysWith { out.append(.init(String(localized: "Pays with"), pays)) }
        out.append(.init(String(localized: "Found in"),
                         ListFormatter.localizedString(byJoining: item.foundIn.map(foundName))))
        return out
    }

    /// This service's other pages, then the way out, then the one write.
    /// Each is drawn only while its destination exists (prd §83).
    private func doors(_ item: Subscriptions.Item) -> [SubscriptionDoor] {
        var out: [SubscriptionDoor] = []
        let link = ServiceLinks.shared.byPlan[item.id]
        if let app = link?.app {
            out.append(.init(id: "app", icon: SubscriptionWords.appGlyph, title: Text("Open \(app)")) {
                dismiss()
                chrome.openApp(app)
            })
        }
        if let listID = link?.listID,
           let list = MailSubscriptionsReading.shared.items.first(where: { $0.id == listID }) {
            out.append(.init(id: "list", icon: SubscriptionWords.listGlyph,
                             title: Text(verbatim: MailSubscriptions.writesWords(list.cadenceDays))) {
                dismiss()
                chrome.open(.list(listID))
            })
        }
        if let site = item.site, let url = URL(string: "https://\(site)") {
            out.append(.init(id: "manage", icon: SubscriptionWords.wayOutGlyph,
                             title: Text("Manage on \(site)")) { openURL(url) })
        }
        if item.manualID != nil {
            out.append(.init(id: "stop", icon: "trash", title: Text("Stop tracking"), role: .destructive) {
                confirmingRemove = true
            })
        }
        return out
    }

    private func cadenceWord(_ item: Subscriptions.Item) -> String? {
        guard let days = item.cadenceDays else { return nil }
        if item.isYearly { return String(localized: "a year") }
        if (25...35).contains(days) { return String(localized: "a month") }
        if (6...8).contains(days) { return String(localized: "a week") }
        return String(localized: "every \(days) days")
    }

    /// "You" reads as what it is in a list of places.
    private func foundName(_ source: String) -> String {
        source == Subscriptions.byYou ? String(localized: "Added by you") : source
    }
}

/// TRACK A SUBSCRIPTION (prd §1105, the verb since §1117): for anything no card, account or bill
/// reading can see. A name, a price, monthly or yearly, the next renewal, and
/// what pays it. When the same name later shows up as a charge a card names,
/// the two merge by name (`Subscriptions.compose`) and are counted once.
struct SubscriptionAddTray: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var price = ""
    @State private var yearly = false
    @State private var renews = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    @State private var paysWith: String? = nil
    @State private var site = ""
    @FocusState private var focus: Field?

    private enum Field { case name, price, site }

    var body: some View {
        DSTray(title: SubscriptionWords.track, height: 640, detents: [.large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    well(String(localized: "Name"), text: $name, field: .name)
                        .textInputAutocapitalization(.words)
                    row(String(localized: "Price")) {
                        TextField(String(localized: "0.00"), text: $price)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .dsText(.body17)
                            .focused($focus, equals: .price)
                    }
                    row(String(localized: "Every")) {
                        HStack(spacing: DS.Space.s2) {
                            cadenceChip(String(localized: "Month"), on: !yearly) { yearly = false }
                            cadenceChip(String(localized: "Year"), on: yearly) { yearly = true }
                        }
                    }
                    row(String(localized: "Next renewal")) {
                        DatePicker("", selection: $renews, displayedComponents: .date)
                            .labelsHidden()
                    }
                    row(String(localized: "Pays with")) {
                        Menu {
                            Button(String(localized: "Not set")) { paysWith = nil }
                            ForEach(payers, id: \.self) { payer in
                                Button(payer) { paysWith = payer }
                            }
                        } label: {
                            HStack(spacing: DS.Space.s1) {
                                Text(paysWith ?? String(localized: "Not set"))
                                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .dsGlyph(.caption).foregroundStyle(DS.textTertiary)
                            }
                        }
                    }
                    well(String(localized: "Website, for the billing page (optional)"), text: $site, field: .site)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    DSSlabButton(title: addTitle, enabled: amount != nil && !trimmed.isEmpty) {
                        guard let amount else { return }
                        SubscriptionStore.shared.add(name: trimmed, amount: amount, yearly: yearly,
                                                     anchor: renews, paysWith: paysWith, site: site)
                        dismiss()
                    }
                }
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s6)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear { focus = .name }
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var amount: Double? {
        let cleaned = price.replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    private var addTitle: String {
        trimmed.isEmpty ? String(localized: "Track") : String(localized: "Track \(trimmed)")
    }

    /// What already pays a subscription here — the cards and accounts the
    /// Wallet read, never a list typed for the occasion.
    private var payers: [String] {
        var seen: [String] = []
        for item in SubscriptionsReading.shared.items {
            if let p = item.paysWith, !seen.contains(p) { seen.append(p) }
        }
        return seen
    }

    private func well(_ prompt: String, text: Binding<String>, field: Field) -> some View {
        TextField(prompt, text: text)
            .dsText(.body17)
            .focused($focus, equals: field)
            .padding(.horizontal, DS.Space.s3)
            .frame(minHeight: DS.Hit.min)
            .background(RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous)
                .fill(DS.fillFaint))
    }

    private func row<Trailing: View>(_ label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: DS.Space.s3) {
            Text(verbatim: label).dsText(.body17).foregroundStyle(DS.textPrimary)
            Spacer(minLength: DS.Space.s2)
            trailing()
        }
        .frame(minHeight: DS.Hit.min)
    }

    private func cadenceChip(_ word: String, on: Bool, pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            Chip(text: word, selected: on)
        }
        .buttonStyle(PressSpring())
    }
}
