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
    /// What it costs: the Wallet's sheet says it; Settings' never does (prd
    /// §1136 item 10, §1143), so it shows when it renews and where it is from.
    var showsMoney = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Environment(ShellChrome.self) private var chrome
    @State private var confirmingRemove = false
    /// What you added, opened in the Track tray to change (user: "need a way
    /// to edit subscriptions in the thing sheet").
    @State private var editing: Subscriptions.Manual?

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
            // And what you follow, for the door to it (prd §1118): only the
            // rooms whose follows have sites; Work's never write to you.
            FollowingReading.shared.refresh(.reading, context: modelContext)
            FollowingReading.shared.refresh(.media, context: modelContext)
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
        // Renamed in the editor, the plan is under another id: this page has
        // nothing left to show, so it closes onto the list that holds it.
        .onChange(of: item == nil) { _, gone in if gone { dismiss() } }
        .sheet(item: $editing) { manual in
            SubscriptionAddTray(editing: manual)
                // A Catalyst sheet does not inherit the presenter's
                // environment (prd §872).
                .environment(chrome)
                .environment(store)
                .environment(\.modelContext, modelContext)
        }
    }

    private func money(_ amount: Double, _ code: String, _ mask: String?) -> String {
        mask ?? CardSpendRoom.money(amount, code: code)
    }

    private func content(_ item: Subscriptions.Item) -> some View {
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        return SubscriptionPage(name: item.name,
                                statement: showsMoney ? statement(item, mask: mask) : nil,
                                facts: facts(item, mask: mask),
                                doors: doors(item))
    }

    private func statement(_ item: Subscriptions.Item, mask: String?) -> SubscriptionStatement? {
        guard let amount = item.amount else { return nil }
        if amount == 0 { return SubscriptionStatement(figure: SubscriptionWords.free) }
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
        if showsMoney, let monthly = item.monthly, monthly > 0, item.isYearly {
            out.append(.init(String(localized: "A month"), money(monthly, item.currency, mask)))
        }
        if let since = item.since {
            out.append(.init(String(localized: "Since"), since.formatted(.dateTime.month(.wide).year())))
        }
        if showsMoney, let paid = item.paid {
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
        if let (followed, room) = FollowingReading.shared.followed(planID: item.id) {
            out.append(.init(id: "followed", icon: ScopeTileGlyph.subscriptions,
                             title: Text(Following.doorWords(room))) {
                dismiss()
                chrome.open(.followed(followed.id, room))
            })
        }
        if let app = link?.app {
            out.append(.init(id: "app", icon: SubscriptionWords.appGlyph, title: Text("Open \(app)")) {
                dismiss()
                chrome.openApp(app)
            })
        }
        if let listID = link?.listID,
           let list = MailSubscriptionsReading.shared.items.first(where: { $0.id == listID }) {
            out.append(.init(id: "list", icon: SubscriptionWords.listGlyph,
                             title: Text(verbatim: MailSubscriptions.writesWords(list))) {
                dismiss()
                chrome.open(.list(listID))
            })
        }
        if let site = item.site, let url = URL(string: "https://\(site)") {
            out.append(.init(id: "manage", icon: SubscriptionWords.wayOutGlyph,
                             title: Text("Manage on \(site)")) { openURL(url) })
        }
        if let manualID = item.manualID,
           let manual = SubscriptionStore.shared.entries[manualID] {
            out.append(.init(id: "edit", icon: "pencil", title: Text("Edit")) { editing = manual })
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

/// TRACK A SUBSCRIPTION (prd §1105, the verb since §1117; made one tap,
/// §1161; a list you can fill without a card, §1164). Day's tray in money:
/// rows over a search field at the bottom.
///   1. FROM YOUR CARDS — charges that look like a plan and are not tracked
///      yet (`SubscriptionsReading.suggestions`). A tap tracks one.
///   2. YOUR APPS — connected apps you can hold a plan with
///      (`SubscriptionPlans.apps`), then POPULAR, the services most people
///      hold one with. Neither needs a card or a connected app.
///   3. Typed, the catalogue's apps and the popular services that match,
///      then the words themselves.
///   4. A pick asks only the price, Free included, and Month or Year; the
///      renewal, what pays it and the website sit under More.
/// Opened from a list, tracking returns to it, the row ticked, so six plans
/// are six taps and six prices; opened on one app (`prefill`, its account
/// page or its first connect), tracking closes. When the same name later
/// shows up as a charge a card names, the two merge by name
/// (`Subscriptions.compose`) and are counted once.
struct SubscriptionAddTray: View {
    /// Opens on this pick's price instead of the list.
    let prefill: Pick?
    /// A subscription you added, opened on its form to change: Save replaces
    /// it, under its new name if you gave one.
    let editing: Subscriptions.Manual?

    init(prefill: Pick? = nil) {
        self.prefill = prefill
        self.editing = nil
        // On the price from the first frame, never the list for one.
        _picked = State(initialValue: prefill)
        _site = State(initialValue: prefill?.site ?? "")
    }

    init(editing manual: Subscriptions.Manual) {
        let pick = Pick(name: manual.name, site: manual.site)
        self.prefill = pick
        self.editing = manual
        _picked = State(initialValue: pick)
        _site = State(initialValue: manual.site ?? "")
        _price = State(initialValue: manual.amount.formatted(.number.grouping(.never).precision(.fractionLength(0...2))))
        _yearly = State(initialValue: manual.yearly)
        _renews = State(initialValue: manual.anchor)
        _renewsTouched = State(initialValue: true)
        _paysWith = State(initialValue: manual.paysWith)
        _more = State(initialValue: true)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ShellChrome.self) private var chrome
    @Environment(BridgeStore.self) private var store

    @State private var query = ""
    @State private var picked: Pick?
    /// Tracked on this visit, so a row ticks before the reading catches up.
    @State private var trackedHere: [String] = []
    @State private var price = ""
    @State private var yearly = false
    @State private var renews = SubscriptionAddTray.firstRenewal(yearly: false)
    @State private var renewsTouched = false
    @State private var paysWith: String? = nil
    @State private var site = ""
    @State private var more = false
    @FocusState private var searchFocused: Bool
    @FocusState private var focus: Field?

    private enum Field { case price, site }

    /// A name to track, and the app's website when the catalogue knows it.
    struct Pick: Equatable {
        var name: String
        var site: String?
    }

    var body: some View {
        DSTray(title: editing == nil ? SubscriptionWords.track : String(localized: "Edit"),
               height: 640, detents: [.large]) {
            if let picked { form(picked) } else { list }
        }
        .task {
            if prefill != nil, picked != nil, editing == nil { focus = .price }
            await SubscriptionsReading.shared.refresh(modelContext)
        }
    }

    /// Every name tracked: what the Wallet reads, what was added by hand, and
    /// what this visit tracked.
    private var tracked: [String] {
        SubscriptionsReading.shared.items.map(\.name) + SubscriptionStore.shared.all.map(\.name) + trackedHere
    }

    /// Connected apps you can hold a plan with, not tracked yet, A–Z.
    private var yourApps: [String] {
        let tracked = tracked
        return Set(store.bridges.filter { $0.status != .paused }.map(\.name))
            .filter { SubscriptionPlans.sells($0) && !SubscriptionPlans.isTracked($0, among: tracked) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // MARK: - 1 · 2 The list

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var list: some View {
        let typed = trimmedQuery
        let tracked = tracked
        let suggestions = Self.matching(SubscriptionsReading.shared.suggestions, query: typed)
            .filter { !SubscriptionPlans.isTracked($0.name, among: trackedHere) }
        let mine = typed.isEmpty ? yourApps : []
        // A name already offered above is not offered twice.
        let above = suggestions.map(\.name) + mine
        let apps = Self.apps(matching: typed).filter { !SubscriptionPlans.isTracked($0.name, among: above) }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // ONE IN YOUR HEAD (user: "need a way here to add a new
                // subscription. like if one is in my head"): what you typed
                // leads, so a name no list holds is the first row, not the
                // last under five apps.
                if !typed.isEmpty, !apps.contains(where: { $0.name.caseInsensitiveCompare(typed) == .orderedSame }) {
                    pickRow(typed, title: String(localized: "Track \u{201C}\(typed)\u{201D}"),
                            line: Text("Any other name")) {
                        choose(Pick(name: typed, site: nil))
                    }
                }
                if !suggestions.isEmpty {
                    DSTrayHead(String(localized: "From your cards"))
                    ForEach(suggestions) { suggestionRow($0) }
                }
                if !mine.isEmpty {
                    DSTrayHead(String(localized: "Your apps"))
                    ForEach(mine, id: \.self) { name in
                        let site = Self.siteByOffer[name]
                        pickRow(name, line: Text(verbatim: site ?? BridgeCatalog.category(forSource: name) ?? "")) {
                            choose(Pick(name: name, site: site))
                        }
                    }
                }
                if !apps.isEmpty {
                    DSTrayHead(typed.isEmpty ? String(localized: "Popular") : String(localized: "Apps"))
                    ForEach(apps, id: \.name) { app in
                        pickRow(app.name, line: Text(verbatim: app.line),
                                tracked: SubscriptionPlans.isTracked(app.name, among: tracked)) {
                            choose(Pick(name: app.name, site: app.site))
                        }
                    }
                }
            }
            .padding(.bottom, 96)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            DSTraySearchField(placeholder: String(localized: "Search, or type any name"), text: $query,
                              focus: $searchFocused, capitalization: .words, submitLabel: .next,
                              onSubmit: {
                                  guard !trimmedQuery.isEmpty else { return }
                                  let app = Self.apps(matching: trimmedQuery).first {
                                      $0.name.caseInsensitiveCompare(trimmedQuery) == .orderedSame
                                  }
                                  choose(Pick(name: app?.name ?? trimmedQuery, site: app?.site))
                              }) { EmptyView() }
        }
    }

    /// "Apple Card · Sep 14, Oct 14", and what it costs at the trailing edge.
    private func suggestionRow(_ s: Subscriptions.Suggestion) -> some View {
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        let line = ([s.paysWith] + [s.dates.map(WalletSubscriptionRow.day).joined(separator: ", ")])
            .joined(separator: " · ")
        return Button { track(s) } label: {
            SubscriptionRow(name: s.name, line: Text(verbatim: line)) {
                HStack(spacing: DS.Space.s3) {
                    Text(verbatim: mask ?? CardSpendRoom.money(s.amount, code: s.currency))
                        .dsText(.price17).monospacedDigit().foregroundStyle(DS.textPrimary)
                    Image(systemName: "plus").dsGlyph(.body).foregroundStyle(DS.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .dsHover()
        .padding(.horizontal, DS.Space.s4)
        .accessibilityLabel(Text("Track \(s.name)"))
    }

    /// A tracked row stays where it was, ticked, and opens nothing: the
    /// list is the record of what this visit did (prd §1164).
    private func pickRow(_ name: String, title: String? = nil, line: Text, tracked: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            DSFeedRow(name: title ?? name, line: line) {
                SubscriptionFace(name: name)
            } trailing: {
                Image(systemName: tracked ? "checkmark" : "plus")
                    .dsGlyph(.body)
                    .foregroundStyle(tracked ? DS.textTertiary : DS.tint)
                    .dsSymbolSwap(tracked)
            }
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .disabled(tracked)
        .dsHover()
        .padding(.horizontal, DS.Space.s4)
        .accessibilityLabel(tracked ? Text("Tracking \(name)") : Text(verbatim: title ?? name))
    }

    // MARK: - 3 The price

    private func form(_ pick: Pick) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                // The name is the way back to the list: a wrong pick is one
                // tap, never a dismissed tray.
                Button {
                    DSHaptic.selection()
                    picked = nil
                    searchFocused = true
                } label: {
                    HStack(spacing: DS.Space.s3) {
                        SubscriptionFace(name: pick.name, size: DS.Face.rowCircle)
                        Text(verbatim: pick.name)
                            .dsText(.heading24).foregroundStyle(DS.textPrimary)
                            .lineLimit(2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .accessibilityLabel(Text("Change name"))
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        // Typed in dollars, as the store keeps a hand-added price.
                        Text(verbatim: "$").dsText(.price40).foregroundStyle(DS.textPrimary)
                        TextField(String(localized: "0"), text: $price)
                            .keyboardType(.decimalPad)
                            .dsText(.price40).monospacedDigit()
                            .foregroundStyle(DS.textPrimary)
                            .focused($focus, equals: .price)
                            .fixedSize()
                    }
                    Text(yearly ? String(localized: "a year") : String(localized: "a month"))
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                    Spacer(minLength: DS.Space.s2)
                    // A plan you hold for nothing is still a plan (prd §1164).
                    Button {
                        DSHaptic.selection()
                        price = "0"
                        focus = nil
                    } label: {
                        Chip(text: String(localized: "Free"), selected: amount == 0)
                    }
                    .buttonStyle(PressSpring())
                }
                row(String(localized: "Every")) {
                    HStack(spacing: DS.Space.s2) {
                        cadenceChip(String(localized: "Month"), on: !yearly) { setYearly(false) }
                        cadenceChip(String(localized: "Year"), on: yearly) { setYearly(true) }
                    }
                }
                if more {
                    row(String(localized: "Next renewal")) {
                        DatePicker("", selection: Binding(get: { renews },
                                                          set: { renews = $0; renewsTouched = true }),
                                   displayedComponents: .date)
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
                    TextField(String(localized: "Website, for the billing page"), text: $site)
                        .dsText(.body17)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .site)
                        .padding(.horizontal, DS.Space.s3)
                        .frame(minHeight: DS.Hit.min)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous)
                            .fill(DS.fillFaint))
                } else {
                    DSMoreLink(title: Text("More")) {
                        withAnimation(DS.Motion.standard) { more = true }
                    }
                    .padding(.vertical, DS.Space.s2)
                }
                DSSlabButton(title: editing == nil ? String(localized: "Track \(pick.name)") : String(localized: "Save"),
                             enabled: amount != nil) {
                    guard let amount else { return }
                    if let editing {
                        save(over: editing, name: pick.name, amount: amount)
                        return
                    }
                    add(name: pick.name, amount: amount, currency: "USD", yearly: yearly,
                        anchor: renews, paysWith: paysWith, site: site)
                }
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.bottom, DS.Space.s6)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Acts

    private func choose(_ pick: Pick) {
        DSHaptic.selection()
        site = pick.site ?? ""
        picked = pick
        focus = .price
    }

    /// One tap: the card's own price, cadence, next charge and card.
    private func track(_ s: Subscriptions.Suggestion) {
        let site = ServiceIdentity.offer(forPlan: s.name, in: ServiceLinks.catalogue)
            .flatMap { Self.siteByOffer[$0] }
        add(name: s.name, amount: s.amount, currency: s.currency, yearly: s.yearly,
            anchor: s.next, paysWith: s.paysWith, site: site ?? "")
    }

    private func add(name: String, amount: Double, currency: String, yearly: Bool,
                     anchor: Date, paysWith: String?, site: String) {
        // Inside an animation, so the list behind the tray opens a place for
        // the row and the total rolls (prd §1199).
        let kept = withAnimation(DS.Motion.standard) {
            SubscriptionStore.shared.add(name: name, amount: amount, currency: currency, yearly: yearly,
                                         anchor: anchor, paysWith: paysWith, site: site)
        }
        guard kept != nil else { return }
        DSHaptic.selection()
        chrome.flash(String(localized: "Tracking \(name)"))
        // One app's tray is done; a list goes back to the list, ticked.
        guard prefill == nil else { dismiss(); return }
        withAnimation(DS.Motion.standard) {
            trackedHere.append(name)
            picked = nil
        }
        self.query = ""
        self.price = ""
        self.yearly = false
        self.renews = Self.firstRenewal(yearly: false)
        self.renewsTouched = false
        self.paysWith = nil
        self.site = ""
        self.more = false
        self.focus = nil
    }

    /// Replaces what you added: a new name keeps one record, not two.
    private func save(over old: Subscriptions.Manual, name: String, amount: Double) {
        if Subscriptions.key(name) != old.id { SubscriptionStore.shared.remove(old.id) }
        guard SubscriptionStore.shared.add(name: name, amount: amount, currency: old.currency, yearly: yearly,
                                           anchor: renews, paysWith: paysWith, site: site) != nil else { return }
        DSHaptic.selection()
        chrome.flash(String(localized: "Saved \(name)"))
        Task { await SubscriptionsReading.shared.refresh(modelContext) }
        dismiss()
    }

    /// Month or Year, and the renewal follows it until the person sets one.
    private func setYearly(_ on: Bool) {
        yearly = on
        if !renewsTouched { renews = Self.firstRenewal(yearly: on) }
    }

    static func firstRenewal(yearly: Bool, now: Date = .now) -> Date {
        Calendar.current.date(byAdding: yearly ? .year : .month, value: 1, to: now) ?? now
    }

    private var amount: Double? {
        let cleaned = price.replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
        // Zero is a price (a free plan, prd §1164); an empty field is none.
        guard let value = Double(cleaned), value >= 0 else { return nil }
        return value
    }

    /// What already pays a subscription here — the cards and accounts the
    /// Wallet read, never a list typed for the occasion.
    private var payers: [String] {
        var seen: [String] = []
        let reading = SubscriptionsReading.shared
        for p in reading.items.compactMap(\.paysWith) + reading.suggestions.map(\.paysWith)
        where !seen.contains(p) { seen.append(p) }
        return seen
    }

    // MARK: - Lookups

    /// Suggestions whose name holds what was typed; all of them untyped.
    static func matching(_ all: [Subscriptions.Suggestion], query: String) -> [Subscriptions.Suggestion] {
        guard !query.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// With nothing typed, the popular services (prd §1164). Typed, the
    /// catalogue's apps whose name, or a word in it, starts with it (five at
    /// most) and the popular services that do, one row a name, A–Z; each
    /// with its own website when one is known, else its category.
    static func apps(matching query: String) -> [(name: String, site: String?, line: String)] {
        let popular = SubscriptionPlans.popular(matching: query)
            .map { (name: $0.name, site: Optional($0.site), line: $0.site) }
        guard !query.isEmpty else { return popular }
        let q = query.lowercased()
        var seen: Set<String> = []
        let catalogue = BridgeCatalog.allOffers
            .filter { offer in
                let name = offer.name.lowercased()
                return name.hasPrefix(q) || name.split(separator: " ").contains { $0.hasPrefix(q) }
            }
            .filter { seen.insert($0.name).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .prefix(5)
            .map { offer in
                let site = siteByOffer[offer.name]
                return (name: offer.name, site: site, line: site ?? BridgeCatalog.category(of: offer))
            }
        return (catalogue + popular.filter { seen.insert($0.name).inserted })
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Each catalogue app's own domain, the shortest when it has several.
    static let siteByOffer: [String: String] = {
        var out: [String: String] = [:]
        for (domain, offer) in ServiceLinks.catalogue.offerByDomain {
            if let standing = out[offer], standing.count <= domain.count { continue }
            out[offer] = domain
        }
        return out
    }()

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
