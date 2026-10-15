import SwiftUI
import SwiftData

// MARKETS, FIND IT IN ONE TAP AND KEEP IT IN ONE MORE (prd §1081).
//
// The room's own parts: the heat map in the box, the watchlist's row, the
// Add sheet, and the alerts a watched row's page carries. Rows and sheets
// stand on nothing (no grey under a control, prd §782): a pick is the tint,
// a choice a checkmark, a saved thing the brand's star.

// MARK: - One watched row

/// A watched token or stock in the watchlist: its face, its name over the one
/// line worth saying (`WatchLine`), the day's shape, its price and the move
/// for the span the box is on.
struct WatchRow: View {
    let name: String
    let logo: String?
    let lettered: String
    let price: Double?
    let change: Double?
    let closes: [Double]
    let line: WatchLine.Line?
    var isStock = false
    /// A system symbol standing for the company's mark (`WatchFace.systemMark`).
    var glyph: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DSFeedRow(name: name, line: lineText, trailingBesideLine: true) {
            WatchFace(url: logo, lettered: lettered, onWhite: isStock && (logo != nil || glyph != nil),
                      symbol: glyph)
        } trailing: {
            HStack(spacing: DS.Space.s3) {
                // Every row keeps the line's column, so the prices stand in
                // one column whether or not a line has been read yet.
                if closes.count >= 2, let change {
                    Sparkline(closes: closes, up: change >= 0)
                } else {
                    Color.clear.frame(width: 46, height: 14)
                }
                VStack(alignment: .trailing, spacing: 1) {
                    if let price {
                        Text(TokenChartStyle.priceText(price))
                            .dsText(.price17)
                            .dsPriceRoll(price)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .dsFigureArrives()
                    }
                    if let change {
                        let flat = TokenChartStyle.isFlat(change)
                        Text(TokenChartStyle.changeText(change))
                            .dsText(.subhead12)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(flat ? DS.textTertiary
                                             : (change > 0 ? DS.confirmInk : DS.destructiveInk))
                            .contentTransition(.numericText(value: change))
                    }
                }
                // One price column (wide enough for "$3,180.00"), so every
                // row's line stands at the same x; a wider price still widens it.
                .frame(minWidth: 84, alignment: .trailing)
                .animation(reduceMotion ? nil : DS.Motion.standard, value: price == nil)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken))
    }

    private var lineText: Text? {
        switch line {
        case .alert(let level):
            return Text("Alert at \(level)").foregroundStyle(DS.textPrimary)
        case .holding(let value):
            return Text("You hold \(value)")
        case .sinceWatched(let move):
            // Grey, as every line is: the row's one coloured figure is
            // today's move, beside the price.
            return Text("\(TokenChartStyle.changeText(move)) since followed")
        case .facts(let facts):
            return Text(verbatim: facts)
        case nil:
            return nil
        }
    }

    private var spoken: String {
        var parts = [name]
        if let price { parts.append(TokenChartStyle.priceText(price)) }
        if let change { parts.append(TokenChartStyle.changeText(change)) }
        return parts.joined(separator: ", ")
    }
}

/// A watched thing's face: its logo, else its first letters on the tint.
/// A stock's logo is drawn on white, because company marks are made for a
/// light ground and a black one vanishes on the dark page.
struct WatchFace: View {
    let url: String?
    let lettered: String
    var size: CGFloat = DS.Face.rowCircle
    var onWhite = false
    /// A system symbol drawn in place of the logo — Apple's, which no third
    /// party may draw as a picture (`systemMark`).
    var symbol: String? = nil

    /// The company whose mark is a system symbol, by ticker: Apple wears
    /// `apple.logo`, the glyph an Apple charge wears (prd §1202), never a
    /// fetched or drawn copy of its logo.
    static func systemMark(forTicker ticker: String) -> String? {
        ticker.uppercased() == "AAPL" ? BridgeGlyph.symbol(for: "Apple") : nil
    }

    var body: some View {
        ZStack {
            Circle().fill(onWhite ? Color.white : DS.tint.opacity(0.85))
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(onWhite ? Color.black : Color.white)
            } else if url == nil {
                Text(verbatim: String(lettered.prefix(2)).uppercased())
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(.white)
            }
            if symbol == nil, let url {
                RemoteThumb(urlString: url, size: onWhite ? size * 0.72 : size,
                            fallback: TokenWatch.source, circular: !onWhite)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

// MARK: - A watched row's alerts, on its page

/// The alerts a watched token or stock carries, on its page: each one you
/// set with its switch, then Add an alert (prd §1081). A row and Add both
/// open `WatchAlertTray`: one field under a Price · Day move · Volume choice,
/// and, on an alert you set, Delete (prd §1289 replaced the menu and the
/// two-field dialog, user: "unable to delete old alerts in markets. and the
/// custom menu is confusing"). Volume is a DEX token's only — Dexscreener's
/// pair states a token's, nothing states a coin's or a stock's here.
struct WatchAlertsSection: View {
    let ref: String
    let name: String
    let price: Double?
    /// Whether a volume alert can be read for this row (a DEX token).
    var volume = false

    @State private var tray: WatchAlertTray.Route?
    /// Inside the thing sheet's stack, the alert tray pushes (prd §1315).
    @Environment(\.dsInSheetStack) private var inSheetStack
    private var store: PriceAlertStore { .shared }

    var body: some View {
        // The Feed's card (prd §1268).
        SheetCard(name: String(localized: "Alerts"), glyph: "bell") {
            ForEach(store.alerts(for: ref)) { alert in
                alertRow(alert)
            }
            addRow
        }
        // The tray reads no Observable environment, so the thing sheet's Mac
        // presentation cannot trap on it (prd §872's two halves).
        // Pushes inside the thing sheet's stack (prd §1315).
        .dsOneSheet(item: $tray, pushes: { _ in inSheetStack }) { route in
            WatchAlertTray(route: route, ref: ref, name: name, price: price, volume: volume)
        }
    }

    private func alertRow(_ alert: PriceAlert) -> some View {
        HStack(spacing: DS.Space.s3) {
            Button {
                tray = .edit(alert)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(Self.title(alert))
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                    if let sub = Self.subtitle(alert, price: price) {
                        Text(sub).dsText(.subhead12).foregroundStyle(DS.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            .accessibilityHint(Text("Edit or delete"))
            Toggle(isOn: Binding(get: { alert.on },
                                 set: { store.set(alert.id, on: $0); DSHaptic.selection() })) {
                Text(Self.title(alert))
            }
            .labelsHidden()
        }
        .frame(minHeight: 52)
        .contextMenu {
            Button(role: .destructive) {
                store.remove(alert.id)
            } label: {
                Label("Delete alert", systemImage: "trash")
            }
        }
    }

    /// A price is what every level is measured from, so Add waits for one.
    @ViewBuilder private var addRow: some View {
        if price != nil {
            Button {
                tray = .new
            } label: {
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: ScopeTileGlyph.alerts)
                        .dsGlyph(.body)
                    Text("Add an alert").dsText(.body17)
                }
                .foregroundStyle(DS.tint)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
        }
    }

    static func title(_ alert: PriceAlert) -> String {
        switch alert.kind {
        case .above:    String(localized: "Rises to \(TokenChartStyle.priceText(alert.target))")
        case .below:    String(localized: "Falls to \(TokenChartStyle.priceText(alert.target))")
        case .move:     String(localized: "Moves \(movePercentText(alert.target)) in a day")
        case .volume:   String(localized: "Trades over \(TokenStats.compact(alert.target)) in a day")
        case .gasBelow: String(localized: "Gas below \(GasPrice.text(alert.target))")
        }
    }

    /// "10%", "7.5%": a typed move keeps its half.
    static func movePercentText(_ fraction: Double) -> String {
        let pct = fraction * 100
        return pct.rounded() == pct ? "\(Int(pct))%" : String(format: "%.1f%%", pct)
    }

    static func subtitle(_ alert: PriceAlert, price: Double?) -> String? {
        if !alert.on, let fired = alert.firedAt {
            return String(localized: "Went off \(fired.formatted(.relative(presentation: .named)))")
        }
        switch alert.kind {
        case .move:     return String(localized: "Up or down, once a day at most")
        case .volume:   return String(localized: "The last 24 hours, once a day at most")
        case .gasBelow:
            let chain = GasPrice.network(fromRef: alert.ref).flatMap(GasPrice.chain)?.name
            return chain.map { String(localized: "On \($0), once") }
        case .above, .below:
            guard let price, let distance = alert.distance(from: price) else { return nil }
            return String(localized: "\(TokenChartStyle.changeText(distance)) from here")
        }
    }

}

// MARK: - One alert's tray (prd §1289)

/// Add an alert, or change or delete one you set: what it measures (Price ·
/// Day move · Volume), ONE field for it, the sentence the field makes, and
/// quick levels from the price now. A price above now rises to it, below
/// falls to it, so there is no direction to pick. It reads no Observable
/// environment and presents nothing, so it is safe raised from the thing
/// sheet on the Mac (prd §872).
struct WatchAlertTray: View {
    enum Route: Identifiable {
        case new
        case edit(PriceAlert)
        var id: String {
            switch self {
            case .new: "new"
            case .edit(let alert): alert.id.uuidString
            }
        }
    }

    enum Measure: Hashable {
        case price, move, volume

        var word: String {
            switch self {
            case .price:  String(localized: "Price")
            case .move:   String(localized: "Day move")
            case .volume: String(localized: "Volume")
            }
        }
    }

    let route: Route
    let ref: String
    let name: String
    let price: Double?
    let volume: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var measure: Measure
    @State private var text: String
    @FocusState private var focused: Bool
    private var store: PriceAlertStore { .shared }

    init(route: Route, ref: String, name: String, price: Double?, volume: Bool) {
        self.route = route
        self.ref = ref
        self.name = name
        self.price = price
        self.volume = volume
        switch route {
        case .new:
            _measure = State(initialValue: .price)
            _text = State(initialValue: "")
        case .edit(let alert):
            // A gas alert watches a chain and is never on a row's page.
            let measure: Measure = switch alert.kind {
            case .above, .below, .gasBelow: .price
            case .move: .move
            case .volume: .volume
            }
            _measure = State(initialValue: measure)
            _text = State(initialValue: Self.fieldText(alert.target, measure: measure))
        }
    }

    private var editing: PriceAlert? {
        if case .edit(let alert) = route { return alert }
        return nil
    }

    private var measures: [Measure] { volume ? [.price, .move, .volume] : [.price, .move] }

    /// The alert the field makes, or nil while it makes none.
    private var made: PriceAlert? {
        switch measure {
        case .price:
            guard let target = PriceAlert.price(text), let price else { return nil }
            return PriceAlert(ref: ref, name: name, kind: target >= price ? .above : .below, target: target)
        case .move:
            guard let move = PriceAlert.movePercent(text) else { return nil }
            return PriceAlert(ref: ref, name: name, kind: .move, target: move)
        case .volume:
            guard let dollars = PriceAlert.dollars(text) else { return nil }
            return PriceAlert(ref: ref, name: name, kind: .volume, target: dollars)
        }
    }

    var body: some View {
        DSTray(title: editing == nil ? String(localized: "New alert") : String(localized: "Edit alert"),
               height: 640, detents: [.large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    if let price {
                        Text("\(name) is \(TokenChartStyle.priceText(price)) now")
                            .dsText(.body17).foregroundStyle(DS.textSecondary)
                    }
                    HStack(spacing: DS.Space.s2) {
                        ForEach(measures, id: \.self) { each in
                            Button { pick(each) } label: {
                                Chip(text: each.word, selected: measure == each)
                            }
                            .buttonStyle(PressSpring())
                        }
                    }
                    field
                    Text(verbatim: sentence)
                        .dsText(.body17)
                        .foregroundStyle(made == nil ? DS.textTertiary : DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: DS.Space.s2) {
                        ForEach(quick, id: \.self) { level in
                            Button {
                                DSHaptic.selection()
                                text = level.text
                            } label: {
                                Chip(text: level.word, selected: text == level.text)
                            }
                            .buttonStyle(PressSpring())
                        }
                    }
                    DSSlabButton(title: editing == nil ? String(localized: "Set alert") : String(localized: "Save"),
                                 enabled: made != nil) { commit() }
                    if let editing {
                        DSDoorRow(icon: "trash", label: "Delete alert", role: .destructive) {
                            store.remove(editing.id)
                            DSHaptic.selection()
                            dismiss()
                        }
                    }
                }
                .padding(.bottom, DS.Space.s6)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear { if editing == nil { focused = true } }
    }

    private var field: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if measure != .move {
                Text(verbatim: "$").dsText(.price40).foregroundStyle(DS.textPrimary)
            }
            TextField(String(localized: "0"), text: $text)
                // Volume takes "5M", so its keypad has letters.
                .keyboardType(measure == .volume ? .numbersAndPunctuation : .decimalPad)
                .dsText(.price40).monospacedDigit()
                .foregroundStyle(DS.textPrimary)
                .focused($focused)
                .fixedSize()
            if measure == .move {
                Text(verbatim: "%").dsText(.price40).foregroundStyle(DS.textPrimary)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: DS.Hit.min)
    }

    /// What the alert will do, in the row's own words; before the field
    /// makes one, what this measure listens for.
    private var sentence: String {
        if let made {
            let title = WatchAlertsSection.title(made)
            guard let sub = WatchAlertsSection.subtitle(made, price: price) else { return title }
            return "\(title) · \(sub)"
        }
        switch measure {
        case .price:  return String(localized: "Higher than now alerts on the way up, lower on the way down. Once.")
        case .move:   return String(localized: "Up or down, once a day at most")
        case .volume: return String(localized: "When the last 24 hours trade more than this, once a day at most.")
        }
    }

    /// A level one tap away: its chip's word, and the field as it reads it.
    struct Level: Hashable {
        let word: String
        let text: String
    }

    private var quick: [Level] {
        switch measure {
        case .price:
            guard let price else { return [] }
            return [(0.10, "+10%"), (0.25, "+25%"), (-0.10, "−10%"), (-0.25, "−25%")].map { step, word in
                Level(word: word, text: Self.fieldText(price * (1 + step), measure: .price))
            }
        case .move:
            return [0.05, 0.10, 0.20].map {
                Level(word: WatchAlertsSection.movePercentText($0), text: Self.fieldText($0, measure: .move))
            }
        case .volume:
            return ["1M", "5M", "10M"].map { Level(word: $0, text: $0) }
        }
    }

    private func pick(_ next: Measure) {
        guard next != measure else { return }
        DSHaptic.selection()
        measure = next
        text = ""
        focused = true
    }

    private func commit() {
        guard let made else { return }
        if let editing { store.remove(editing.id) }
        store.add(made)
        DSHaptic.success()
        dismiss()
    }

    /// A target as the field types it: no "$", no "%", no grouping.
    static func fieldText(_ target: Double, measure: Measure) -> String {
        switch measure {
        case .price:
            return TokenChartStyle.priceText(target).replacingOccurrences(of: "$", with: "")
        case .move:
            return WatchAlertsSection.movePercentText(target).replacingOccurrences(of: "%", with: "")
        case .volume:
            return TokenStats.compact(target).replacingOccurrences(of: "$", with: "")
        }
    }
}

// MARK: - Gas (prd §1250)

/// Gas at the head of the Watchlist: what a send costs on Ethereum and Base
/// now, in gwei, on one line, stamped with its age past `GasPrice.stampAfter`
/// and gone past `dropAfter` (a reading, as a price is, §1223). The line is
/// the door to the gas alerts: "below N gwei" on a chain, once.
struct MarketsGasHead: View {
    static let glyph = "fuelpump"

    let gas: MarketsGas
    @State private var customNetwork: String?
    @State private var customText = ""

    var body: some View {
        let now = Date.now
        let shown: [(chain: GasPrice.Chain, reading: MarketsGas.Reading)] = GasPrice.chains.compactMap { chain in
            guard let reading = gas.reading(chain.network),
                  GasPrice.drawable(at: reading.at, now: now) else { return nil }
            return (chain: chain, reading: reading)
        }
        if !shown.isEmpty {
            Menu {
                ForEach(shown, id: \.chain.network) { item in
                    Section(item.chain.name) {
                        ForEach(GasPrice.choices(now: item.reading.gwei), id: \.self) { level in
                            Button {
                                add(network: item.chain.network, level: level)
                            } label: {
                                Text("Alert below \(GasPrice.text(level))")
                            }
                        }
                        Button {
                            customNetwork = item.chain.network
                        } label: {
                            Text("Custom level…")
                        }
                    }
                }
            } label: {
                label(shown, now: now)
            }
            .accessibilityLabel(Text(spoken(shown)))
            .alert(Text("Alert when gas is below"), isPresented: Binding(
                get: { customNetwork != nil },
                set: { if !$0 { customNetwork = nil } })) {
                TextField(String(localized: "Gwei"), text: $customText)
                    .keyboardType(.decimalPad)
                Button(String(localized: "Set")) { setCustom() }
                Button(String(localized: "Cancel"), role: .cancel) { customText = "" }
            } message: {
                if let network = customNetwork, let chain = GasPrice.chain(network),
                   let current = gas.reading(network) {
                    Text("\(chain.name) is \(GasPrice.text(current.gwei)) now.")
                }
            }
        }
    }

    private func label(_ shown: [(chain: GasPrice.Chain, reading: MarketsGas.Reading)],
                       now: Date) -> some View {
        let line = shown.map { "\($0.chain.name) \(GasPrice.text($0.reading.gwei))" }
            .joined(separator: " · ")
        let oldest = shown.map(\.reading.at).min()
        return HStack(spacing: DS.Space.s2) {
            Image(systemName: Self.glyph)
                .dsGlyph(.subhead)
                .foregroundStyle(DS.textTertiary)
            Text(verbatim: line)
                .dsText(.subhead12)
                .monospacedDigit()
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if let oldest, GasPrice.stamped(at: oldest, now: now) {
                Text("as of \(oldest.formatted(.relative(presentation: .named)))")
                    .dsText(.subhead12)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func spoken(_ shown: [(chain: GasPrice.Chain, reading: MarketsGas.Reading)]) -> String {
        let line = shown.map { "\($0.chain.name) \(GasPrice.text($0.reading.gwei))" }.joined(separator: ", ")
        return String(localized: "Gas: \(line). Opens gas alerts.")
    }

    private func add(network: String, level: Double) {
        guard let chain = GasPrice.chain(network) else { return }
        PriceAlertStore.shared.add(PriceAlert(ref: GasPrice.ref(network),
                                              name: String(localized: "\(chain.name) gas"),
                                              kind: .gasBelow, target: level))
        DSHaptic.success()
    }

    private func setCustom() {
        let typed = customText.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        customText = ""
        guard let network = customNetwork, let level = Double(typed), level > 0 else { return }
        customNetwork = nil
        add(network: network, level: level)
    }
}

// MARK: - The index (prd §1082)

/// One company in the index: the app you know it by, its name and ticker over
/// the apps it makes, its price and day, and the star.
struct IndexRow: View {
    let company: CompanyPacks.Company
    let apps: [String]
    let quote: CompanyQuote?
    let watched: Bool
    let star: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            BridgeIcon(name: company.seats.first ?? company.name, size: DS.Mark.row)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: company.name)
                    .dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(1)
                Text(verbatim: ([company.listing.ticker].compactMap(\.self) + [apps.joined(separator: ", ")])
                        .joined(separator: " · "))
                    .dsText(.subhead12).foregroundStyle(DS.textTertiary).lineLimit(1)
            }
            Spacer(minLength: DS.Space.s2)
            if let quote {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(TokenChartStyle.priceText(quote.price))
                        .dsText(.price17).monospacedDigit().dsPriceRoll(quote.price)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if let change = quote.change {
                        let flat = TokenChartStyle.isFlat(change)
                        Text(TokenChartStyle.changeText(change))
                            .dsText(.subhead12).fontWeight(.semibold).monospacedDigit()
                            .foregroundStyle(flat ? DS.textTertiary : (change > 0 ? DS.confirmInk : DS.destructiveInk))
                            .contentTransition(.numericText(value: change))
                    }
                }
                .dsFigureArrives()
            }
            if let star {
                Button(action: star) {
                    DSFollowMark(on: watched, bounce: watched)
                }
                .buttonStyle(PressSpring())
                .accessibilityLabel(Text(watched ? String(localized: "Stop following \(company.name)")
                                                 : String(localized: "Follow \(company.name)")))
                .accessibilityAddTraits(watched ? .isSelected : [])
            }
        }
        .frame(minHeight: 56)
        // Each company's quote lands as its own answer comes back (prd §1199).
        .animation(reduceMotion ? nil : DS.Motion.standard, value: quote == nil)
    }
}
