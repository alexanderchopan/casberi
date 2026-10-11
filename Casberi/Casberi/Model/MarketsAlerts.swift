import Foundation
import Observation
import SwiftData

/// The price alerts you set (prd §1081), on this device and, since §1250, on
/// your others through iCloud key-value storage (`KeyValueMirror`, behind the
/// same iCloud toggle as the address book). Each device still checks them on
/// its own reads — there is no server — so the merge is what keeps two
/// devices honest: by alert id, an alert that went off stands against a copy
/// still on (`PriceAlert.merged`), so a sync never re-arms a fired level, and
/// a move's day travels so the second device does not fire it again that
/// day. Two devices reading the same crossing before either syncs can each
/// tell you once; that is the ceiling of checking on the phone.
@MainActor
@Observable
final class PriceAlertStore {
    static let shared = PriceAlertStore()
    private static let key = "markets.priceAlerts.v1"

    private(set) var alerts: [PriceAlert]

    private init() {
        alerts = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([PriceAlert].self, from: $0) } ?? []
        // `attach` reads the singleton, which does not exist until this
        // initializer returns (`MailSubscriptionStore`'s shape).
        DispatchQueue.main.async { Self.shared.attach() }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(alerts) else { return }
        DefaultsWrite.set(data, forKey: Self.key)
        mirror.push()
    }

    // MARK: - Mirror

    @ObservationIgnored private lazy var mirror = KeyValueMirror<PriceAlert>(
        entriesKey: "markets.priceAlerts.mirror.v1",
        tombstonesKey: "markets.priceAlerts.tombstones.v1",
        localTombstonesKey: "markets.priceAlerts.tombstones.local.v1",
        snapshot: { [weak self] in
            Dictionary((self?.alerts ?? []).map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
        },
        newer: { incoming, standing in
            guard let standing else { return incoming }
            let merged = PriceAlert.merged(incoming, standing)
            return merged == standing ? nil : merged
        },
        apply: { [weak self] merged in
            guard let self else { return }
            let next = merged.values.sorted { $0.createdAt < $1.createdAt }
            guard next != self.alerts else { return }
            self.alerts = next
            guard let data = try? JSONEncoder().encode(next) else { return }
            DefaultsWrite.set(data, forKey: Self.key)
        })

    func attach() { mirror.attach() }

    func alerts(for ref: String) -> [PriceAlert] { alerts.filter { $0.ref == ref } }

    /// The alert that names a row's line ("Alert at $45"): a level still on,
    /// else a move or a volume alert.
    func lineAlert(for ref: String) -> PriceAlert? {
        let on = alerts.filter { $0.ref == ref && $0.on }
        return on.first { $0.kind == .above || $0.kind == .below } ?? on.first
    }

    func add(_ alert: PriceAlert) {
        // One alert per level: setting the same one twice is one alert.
        guard !alerts.contains(where: {
            $0.ref == alert.ref && $0.kind == alert.kind && abs($0.target - alert.target) < alert.target * 1e-6
        }) else { return }
        alerts.append(alert)
        persist()
    }

    /// A switch by hand. It stamps `changedAt`, which is what lets a re-armed
    /// alert win the sync over the copy that fired (`PriceAlert.merged`).
    func set(_ id: UUID, on: Bool) {
        guard let i = alerts.firstIndex(where: { $0.id == id }) else { return }
        alerts[i].on = on
        alerts[i].changedAt = .now
        if on { alerts[i].firedAt = nil }
        persist()
    }

    func remove(_ id: UUID) {
        mirror.noteRemoval(id.uuidString)
        alerts.removeAll { $0.id == id }
        persist()
    }

    /// Unwatching a row takes its alerts with it: an alert on something you
    /// no longer watch has no row to name and no price that is read.
    func removeAll(ref: String) {
        guard alerts.contains(where: { $0.ref == ref }) else { return }
        for alert in alerts where alert.ref == ref { mirror.noteRemoval(alert.id.uuidString) }
        alerts.removeAll { $0.ref == ref }
        persist()
    }

    /// The launch sweep renamed followed rows (prd §1250, `CoinWatch.converge`):
    /// their alerts follow the new refs.
    func rewriteRefs(_ map: [String: String]) {
        let next = CoinFollow.rewrite(alerts: alerts, map: map, now: .now)
        guard next != alerts else { return }
        alerts = next
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
        // A row pinned to the Lock Screen (prd §1250) is read here too, so the
        // background task brings its price up to date with no alert set.
        let pinned = PriceActivityDriver.isPinned
        guard alerts.contains(where: \.on) || pinned else { return }
        await TokenPulse.shared.refresh(context: context)
        let source = TokenWatch.source
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == source })
        let watched = ((try? context.fetch(descriptor)) ?? []).filter { $0.isLive && !Self.isAlertRow($0) }
        let stockCompanies = watched.compactMap { thing in
            StockWatch.symbol(of: thing).map {
                CompanyPacks.Company(name: thing.title, listing: .stock($0), seats: [])
            }
        }
        // A volume alert's token, by the pair route its row carries — read
        // here, before any wait, so only values cross the suspensions.
        let volumeRefs = Set(alerts.filter { $0.on && $0.kind == .volume }.map(\.ref))
        let volumeRoutes: [(ref: String, chain: String, address: String)] = watched.compactMap { thing in
            guard let ref = thing.sourceRef, volumeRefs.contains(ref),
                  let route = TokenChart.route(from: thing.content) else { return nil }
            return (ref: ref, chain: route.chain, address: route.address)
        }
        if !stockCompanies.isEmpty { await CompanyQuotes.shared.load(stockCompanies) }
        var volumes: [String: Double] = [:]
        for (ref, stats) in await IngestSupport.boundedGather(volumeRoutes, maxConcurrent: 4, { item in
            (item.ref, await TokenStats.fetch(chain: item.chain, address: item.address))
        }) {
            if let volume = stats?.volume24h { volumes[ref] = volume }
        }
        if alerts.contains(where: { $0.on && $0.kind == .gasBelow }) {
            await MarketsGas.shared.load()
        }
        let byRef = Dictionary(watched.compactMap { t in t.sourceRef.map { ($0, t) } },
                               uniquingKeysWith: { a, _ in a })
        var changed = false
        let now = Date.now
        for (i, alert) in alerts.enumerated() where alert.on {
            if alert.kind == .gasBelow {
                guard let network = GasPrice.network(fromRef: alert.ref),
                      let gas = MarketsGas.shared.reading(network),
                      GasPrice.drawable(at: gas.at, now: now),
                      alert.fires(price: gas.gwei, change24h: nil, now: now) else { continue }
                landGas(alert, gwei: gas.gwei, context: context)
                alerts[i] = alert.afterFiring(at: now)
                changed = true
                continue
            }
            guard let thing = byRef[alert.ref], let read = Self.reading(for: thing),
                  alert.fires(price: read.price, change24h: read.change,
                              volume24h: volumes[alert.ref], now: now) else { continue }
            land(alert, price: read.price, change: read.change, volume: volumes[alert.ref],
                 watched: thing, context: context)
            alerts[i] = alert.afterFiring(at: now)
            changed = true
        }
        if changed {
            persist()
            context.saveHonestly()
        }
        if pinned { await PriceActivityDriver.sync(context: context) }
    }

    static let alertTag = "Alert"

    static func isAlertRow(_ thing: Thing) -> Bool {
        thing.source == TokenWatch.source && thing.tags.contains(alertTag)
    }

    private func land(_ alert: PriceAlert, price: Double, change: Double?, volume: Double?,
                      watched: Thing, context: ModelContext) {
        let priceText = TokenChartStyle.priceText(price)
        let title: String
        switch alert.kind {
        case .above: title = String(localized: "\(alert.name) crossed \(TokenChartStyle.priceText(alert.target))")
        case .below: title = String(localized: "\(alert.name) fell to \(priceText)")
        case .move:  title = String(localized: "\(alert.name) moved \(TokenChartStyle.changeText(change ?? 0)) today")
        case .volume:
            title = String(localized: "\(alert.name) traded \(TokenStats.compact(volume ?? alert.target)) today")
        case .gasBelow:
            // Never reached: a gas alert lands through `landGas`.
            title = String(localized: "\(alert.name) fell to \(GasPrice.text(price))")
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

    /// A gas alert went off (prd §1250): a Markets row tagged Alert under the
    /// same `alert:` ref, so the notify sweep sends it at once as a price
    /// alert's, and the Alerts tile lists it under Went off.
    private func landGas(_ alert: PriceAlert, gwei: Double, context: ModelContext) {
        guard let chain = GasPrice.network(fromRef: alert.ref).flatMap(GasPrice.chain) else { return }
        // No door (§912, allowed in `empty-door-audit.py`): a chain's gas has
        // no page of its own, and an explorer's gas page as a `.link` would be
        // fetched for its preview — a host this app does not read.
        let row = Thing(kind: .link,
                        title: String(localized: "Gas on \(chain.name) is \(GasPrice.text(gwei))"),
                        content: "", source: TokenWatch.source, capturedAt: .now,
                        tags: [Self.alertTag],
                        sourceRef: "alert:\(alert.id.uuidString):\(Int(Date.now.timeIntervalSince1970))")
        row.authorHandle = String(localized: "Gas")
        row.summary = String(localized: "Below \(GasPrice.text(alert.target))")
        context.insert(row)
    }
}

extension PriceAlert: KeyValueMirrored {
    var mirrorStamp: Date { stamp }
}
