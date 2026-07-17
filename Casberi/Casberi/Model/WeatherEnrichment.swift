import Foundation
import CoreLocation
import WeatherKit

/// A live "Today" enrichment for the Coming Up card (2026-07-17) — asks for
/// today's forecast at the device's current location. Nothing here persists:
/// no new `Thing` field, no schema change (see CLAUDE.md's schema-versioning
/// rule) — this is a live fetch at render time, cached briefly in memory so
/// a recompose doesn't re-hit WeatherKit. Denial or a failed fetch leaves the
/// Today label plain, never a fake status (honesty rule).
enum WeatherEnrichment {

    private static var cached: (summary: String, at: Date)?
    private static let cacheLifetime: TimeInterval = 30 * 60

    /// A short summary ("72°, partly cloudy") for today, or nil when location
    /// is denied/unavailable or the forecast fetch fails.
    static func todaySummary() async -> String? {
        if let cached, Date.now.timeIntervalSince(cached.at) < cacheLifetime {
            return cached.summary
        }
        guard let location = await currentLocation() else { return nil }
        guard let weather = try? await WeatherService.shared.weather(for: location, including: .current) else {
            return nil
        }
        let temp = Int(weather.temperature.converted(to: .fahrenheit).value.rounded())
        let summary = "\(temp)°, \(weather.condition.description.lowercased())"
        cached = (summary, .now)
        return summary
    }

    /// One current-location read — "When In Use" only, no background access,
    /// no CLVisit-style tracking. `CLLocationUpdate.liveUpdates()` (iOS 17+)
    /// triggers the authorization prompt itself on first call and yields
    /// until it can answer or is denied; the loop exits after the first
    /// usable fix, so nothing keeps listening after this call returns.
    /// Bounded — same shape as `HomeManagerBridge.waitForHomes`: if the
    /// stream never yields a location, a denial, or a restriction (platform
    /// silence, not just a slow human), a 20s race timeout wins instead of
    /// leaving the caller's `.task` suspended forever.
    private static func currentLocation() async -> CLLocation? {
        await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates(.default) {
                        if let loc = update.location { return loc }
                        if update.authorizationDenied || update.authorizationRestricted { return nil }
                    }
                } catch {}
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(20))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }
}
