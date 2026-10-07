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

    var body: some View {
        DSFeedRow(name: name, line: lineText) {
            WatchFace(url: logo, lettered: lettered, onWhite: isStock && logo != nil)
        } trailing: {
            HStack(spacing: DS.Space.s3) {
                if closes.count >= 2, let change {
                    Sparkline(closes: closes, up: change >= 0)
                }
                VStack(alignment: .trailing, spacing: 1) {
                    if let price {
                        Text(TokenChartStyle.priceText(price))
                            .dsText(.price17)
                            .foregroundStyle(DS.textPrimary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    if let change {
                        let flat = TokenChartStyle.isFlat(change)
                        Text(TokenChartStyle.changeText(change))
                            .dsText(.subhead12)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(flat ? DS.textTertiary
                                             : (change > 0 ? DS.confirmInk : DS.destructiveInk))
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken))
    }

    private var lineText: Text? {
        switch line {
        case .alert(let level):
            return Text("Alert at \(level)").foregroundStyle(DS.brandInk)
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

    var body: some View {
        ZStack {
            Circle().fill(onWhite ? Color.white : DS.tint.opacity(0.85))
            if url == nil {
                Text(verbatim: String(lettered.prefix(2)).uppercased())
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(.white)
            }
            if let url {
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
/// choices are levels computed from the price now; Custom asks for a price.
struct WatchAlertsSection: View {
    let ref: String
    let name: String
    let price: Double?

    @State private var customOpen = false
    @State private var customText = ""
    private var store: PriceAlertStore { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text("Alerts")
                .dsText(.heading17)
                .foregroundStyle(DS.textPrimary)
            ForEach(store.alerts(for: ref)) { alert in
                alertRow(alert)
            }
            addMenu
        }
        .alert(Text("Alert at a price"), isPresented: $customOpen) {
            TextField(String(localized: "Price in dollars"), text: $customText)
                .keyboardType(.decimalPad)
            Button(String(localized: "Set")) { setCustom() }
            Button(String(localized: "Cancel"), role: .cancel) { customText = "" }
        } message: {
            if let price { Text("Now \(TokenChartStyle.priceText(price))") }
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
                    Text("Custom price…")
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
        customText = ""
        guard let target = Double(cleaned), target > 0, let price else { return }
        store.add(PriceAlert(ref: ref, name: name, kind: target >= price ? .above : .below,
                             target: target))
        DSHaptic.success()
    }

    static func title(_ alert: PriceAlert) -> String {
        switch alert.kind {
        case .above: String(localized: "Rises to \(TokenChartStyle.priceText(alert.target))")
        case .below: String(localized: "Falls to \(TokenChartStyle.priceText(alert.target))")
        case .move:  String(localized: "Moves \(Int((alert.target * 100).rounded()))% in a day")
        }
    }

    static func subtitle(_ alert: PriceAlert, price: Double?) -> String? {
        if !alert.on, let fired = alert.firedAt {
            return String(localized: "Went off \(fired.formatted(.relative(presentation: .named)))")
        }
        if alert.kind == .move { return String(localized: "Up or down, once a day at most") }
        guard let price, let distance = alert.distance(from: price) else { return nil }
        return String(localized: "\(TokenChartStyle.changeText(distance)) from here")
    }

    static func choiceLabel(_ choice: PriceAlert, price: Double) -> String {
        switch choice.kind {
        case .above, .below:
            let pct = Int(((choice.distance(from: price) ?? 0) * 100).rounded())
            return String(localized: "\(title(choice)) (\(pct > 0 ? "+" : "")\(pct)%)")
        case .move:
            return title(choice)
        }
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
                        .dsText(.price17).monospacedDigit().foregroundStyle(DS.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if let change = quote.change {
                        let flat = TokenChartStyle.isFlat(change)
                        Text(TokenChartStyle.changeText(change))
                            .dsText(.subhead12).fontWeight(.semibold).monospacedDigit()
                            .foregroundStyle(flat ? DS.textTertiary : (change > 0 ? DS.confirmInk : DS.destructiveInk))
                    }
                }
            }
            if let star {
                Button(action: star) {
                    Image(systemName: watched ? "star.fill" : "star")
                        .dsGlyph(.title, weight: .regular)
                        .foregroundStyle(watched ? DS.brand : DS.textTertiary)
                        .symbolEffect(.bounce, value: watched)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressSpring())
                .accessibilityLabel(Text(watched ? String(localized: "Stop following \(company.name)")
                                                 : String(localized: "Follow \(company.name)")))
                .accessibilityAddTraits(watched ? .isSelected : [])
            }
        }
        .frame(minHeight: 56)
    }
}
