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
        DSFeedRow(name: name, line: lineText) {
            WatchFace(url: logo, lettered: lettered, onWhite: isStock && (logo != nil || glyph != nil),
                      symbol: glyph)
        } trailing: {
            HStack(spacing: DS.Space.s3) {
                if closes.count >= 2, let change {
                    Sparkline(closes: closes, up: change >= 0)
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
            return Text("\(TokenChartStyle.changeText(move)) since you followed")
                .foregroundStyle(move > 0 ? DS.confirmInk : DS.destructiveInk)
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
/// set with its switch, then one menu to add another (prd §1081). The
/// choices are levels computed from the price now; Custom asks for a price
/// or a day's move in percent (prd §1250), and a token's menu asks for a day
/// volume too — Dexscreener's pair states a token's, nothing states a coin's
/// or a stock's here.
struct WatchAlertsSection: View {
    let ref: String
    let name: String
    let price: Double?
    /// Whether a volume alert can be read for this row (a DEX token).
    var volume = false

    @State private var customOpen = false
    @State private var customText = ""
    @State private var customPercent = ""
    @State private var volumeOpen = false
    @State private var volumeText = ""
    private var store: PriceAlertStore { .shared }

    var body: some View {
        // The Feed's card (prd §1268).
        SheetCard(name: String(localized: "Alerts"), glyph: "bell") {
            ForEach(store.alerts(for: ref)) { alert in
                alertRow(alert)
            }
            addMenu
        }
        .alert(Text("Alert at a price or a move"), isPresented: $customOpen) {
            TextField(String(localized: "Price in dollars"), text: $customText)
                .keyboardType(.decimalPad)
            TextField(String(localized: "Or a move in a day, in %"), text: $customPercent)
                .keyboardType(.numbersAndPunctuation)
            Button(String(localized: "Set")) { setCustom() }
            Button(String(localized: "Cancel"), role: .cancel) { customText = ""; customPercent = "" }
        } message: {
            if let price { Text("Now \(TokenChartStyle.priceText(price)). A move listens up and down.") }
        }
        .alert(Text("Alert on a day's volume"), isPresented: $volumeOpen) {
            TextField(String(localized: "Dollars, like 5M"), text: $volumeText)
                .keyboardType(.numbersAndPunctuation)
            Button(String(localized: "Set")) { setVolume() }
            Button(String(localized: "Cancel"), role: .cancel) { volumeText = "" }
        } message: {
            Text("When the last 24 hours trade more than this, once a day at most.")
        }
    }

    private func alertRow(_ alert: PriceAlert) -> some View {
        HStack(spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.title(alert))
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                if let sub = Self.subtitle(alert, price: price) {
                    Text(sub).dsText(.subhead12).foregroundStyle(DS.textTertiary)
                }
            }
            Spacer(minLength: 0)
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

    @ViewBuilder private var addMenu: some View {
        if let price {
            Menu {
                ForEach(PriceAlert.choices(ref: ref, name: name, price: price)) { choice in
                    Button {
                        store.add(choice)
                        DSHaptic.success()
                    } label: {
                        Text(Self.choiceLabel(choice, price: price))
                    }
                }
                Button {
                    customOpen = true
                } label: {
                    Text("Custom price or move…")
                }
                if volume {
                    Button {
                        volumeOpen = true
                    } label: {
                        Text("Day volume above…")
                    }
                }
            } label: {
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: ScopeTileGlyph.alerts)
                        .dsGlyph(.body)
                    Text("Add an alert").dsText(.body17)
                }
                .foregroundStyle(DS.tint)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
        }
    }

    private func setCustom() {
        let cleaned = customText.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        let typedPercent = customPercent
        customText = ""
        customPercent = ""
        var added = false
        if let target = Double(cleaned), target > 0, let price {
            store.add(PriceAlert(ref: ref, name: name, kind: target >= price ? .above : .below,
                                 target: target))
            added = true
        }
        if let move = PriceAlert.movePercent(typedPercent) {
            store.add(PriceAlert(ref: ref, name: name, kind: .move, target: move))
            added = true
        }
        if added { DSHaptic.success() }
    }

    private func setVolume() {
        let typed = volumeText
        volumeText = ""
        guard volume, let target = PriceAlert.dollars(typed) else { return }
        store.add(PriceAlert(ref: ref, name: name, kind: .volume, target: target))
        DSHaptic.success()
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

    static func choiceLabel(_ choice: PriceAlert, price: Double) -> String {
        switch choice.kind {
        case .above, .below:
            let pct = Int(((choice.distance(from: price) ?? 0) * 100).rounded())
            return String(localized: "\(title(choice)) (\(pct > 0 ? "+" : "")\(pct)%)")
        case .move, .volume, .gasBelow:
            return title(choice)
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
