import Foundation
import Observation
import SwiftData

/// The price alerts you set (prd §1081), kept on this device. Not synced: an
/// alert is checked by THIS phone's reads, so another device holding it
/// would fire a second notification for the same crossing.
@MainActor
@Observable
final class PriceAlertStore {
    static let shared = PriceAlertStore()
    private static let key = "markets.priceAlerts.v1"

    private(set) var alerts: [PriceAlert]

    private init() {
        alerts = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([PriceAlert].self, from: $0) } ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(alerts) else { return }
        DefaultsWrite.set(data, forKey: Self.key)
    }

    func alerts(for ref: String) -> [PriceAlert] { alerts.filter { $0.ref == ref } }

    /// The alert that names a row's line ("Alert at $45"): the nearest level
    /// still on, else a move alert.
    func lineAlert(for ref: String) -> PriceAlert? {
        let on = alerts.filter { $0.ref == ref && $0.on }
        return on.first { $0.kind != .move } ?? on.first
    }

    func add(_ alert: PriceAlert) {
        // One alert per level: setting the same one twice is one alert.
        guard !alerts.contains(where: {
            $0.ref == alert.ref && $0.kind == alert.kind && abs($0.target - alert.target) < alert.target * 1e-6
        }) else { return }
        alerts.append(alert)
        persist()
    }

    func set(_ id: UUID, on: Bool) {
        guard let i = alerts.firstIndex(where: { $0.id == id }) else { return }
        alerts[i].on = on
        if on { alerts[i].firedAt = nil }
        persist()
    }

    func remove(_ id: UUID) {
        alerts.removeAll { $0.id == id }
        persist()
    }

    /// Unwatching a row takes its alerts with it: an alert on something you
    /// no longer watch has no row to name and no price that is read.
    func removeAll(ref: String) {
        guard alerts.contains(where: { $0.ref == ref }) else { return }
        alerts.removeAll { $0.ref == ref }
        persist()
    }

    // MARK: - Checking

    /// The price and day move this app last read for a watched row, and when
    /// it read them (the Watchlist widget stamps an old price, §1223).
    static func reading(for thing: Thing) -> (price: Double, change: Double?, at: Date)? {
        if let pulse = TokenPulse.shared.pulse(for: thing) {
            return (pulse.price, pulse.change24h, pulse.fetchedAt)
        }
        if let symbol = StockWatch.symbol(of: thing),
           let quote = CompanyQuotes.shared.quote(.stock(symbol)) {
            return (quote.price, quote.change, quote.at)
        }
        return nil
    }

    /// Checks every alert that is on against the newest reads, after reading
    /// fresh prices for the rows that carry one. A crossing lands as a Markets
    /// row tagged Alert, which the notify sweep sends at once (`priceAlert`
    /// stands alone, prd §1081) and the Alerts tile lists.
    func check(context: ModelContext) async {
        guard alerts.contains(where: \.on) else { return }
        await TokenPulse.shared.refresh(context: context)
        let source = TokenWatch.source
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == source })
        let watched = ((try? context.fetch(descriptor)) ?? []).filter { $0.isLive && !Self.isAlertRow($0) }
        let stockCompanies = watched.compactMap { thing in
            StockWatch.symbol(of: thing).map {
                CompanyPacks.Company(name: thing.title, listing: .stock($0), seats: [])
            }
        }
        if !stockCompanies.isEmpty { await CompanyQuotes.shared.load(stockCompanies) }
        let byRef = Dictionary(watched.compactMap { t in t.sourceRef.map { ($0, t) } },
                               uniquingKeysWith: { a, _ in a })
        var changed = false
        let now = Date.now
        for (i, alert) in alerts.enumerated() where alert.on {
            guard let thing = byRef[alert.ref], let read = Self.reading(for: thing),
                  alert.fires(price: read.price, change24h: read.change, now: now) else { continue }
            land(alert, price: read.price, change: read.change, watched: thing, context: context)
            alerts[i] = alert.afterFiring(at: now)
            changed = true
        }
        if changed {
            persist()
            context.saveHonestly()
        }
    }

    static let alertTag = "Alert"

    static func isAlertRow(_ thing: Thing) -> Bool {
        thing.source == TokenWatch.source && thing.tags.contains(alertTag)
    }

    private func land(_ alert: PriceAlert, price: Double, change: Double?,
                      watched: Thing, context: ModelContext) {
        let priceText = TokenChartStyle.priceText(price)
        let title: String
        switch alert.kind {
        case .above: title = String(localized: "\(alert.name) crossed \(TokenChartStyle.priceText(alert.target))")
        case .below: title = String(localized: "\(alert.name) fell to \(priceText)")
        case .move:  title = String(localized: "\(alert.name) moved \(TokenChartStyle.changeText(change ?? 0)) today")
        }
        let row = Thing(kind: .link, title: title, content: watched.content,
                        source: TokenWatch.source, capturedAt: .now,
                        tags: [Self.alertTag],
                        sourceRef: "alert:\(alert.id.uuidString):\(Int(Date.now.timeIntervalSince1970))")
        row.previewImageURL = watched.previewImageURL
        row.authorHandle = watched.authorHandle
        row.summary = change.map { String(localized: "\(TokenChartStyle.changeText($0)) today") }
        context.insert(row)
    }
}
