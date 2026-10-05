import Foundation

/// Whether the App Store has a newer Casberi than this copy (prd §1104). Old
/// TestFlight builds can be expired; an App Store install never can, so a
/// person who never updates keeps asking about a build that is long fixed.
/// This asks Apple's public lookup which version is live and lets the shell
/// say so once, and Settings say so for as long as it is true.
///
/// Keyless, and the request carries only the app's own id. At most one
/// lookup every 12 hours; between them the last answer stands. The lookup is
/// CDN-cached and trails a release by hours, which only ever makes the nudge
/// late, never wrong.
enum StoreVersion {

    static let appID = "6788637831"

    /// The Mac's version lives on the desktop record: the plain lookup answers
    /// with the iPhone's (measured 2026-10-04: iOS 2.0.1, Mac 2.0.2).
    static var lookupURL: URL {
        #if targetEnvironment(macCatalyst)
        URL(string: "https://itunes.apple.com/lookup?id=\(appID)&entity=desktopSoftware")!
        #else
        URL(string: "https://itunes.apple.com/lookup?id=\(appID)")!
        #endif
    }

    /// The store's own page, opened in the App Store app.
    static var storeURL: URL {
        #if targetEnvironment(macCatalyst)
        URL(string: "macappstore://apps.apple.com/app/id\(appID)")!
        #else
        URL(string: "itms-apps://apps.apple.com/app/id\(appID)")!
        #endif
    }

    static var installed: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Dotted versions compared number by number, a missing part as 0, so
    /// 2.0 equals 2.0.0 and 2.0.10 is above 2.0.9.
    static func isNewer(_ store: String, than installed: String) -> Bool {
        let a = store.split(separator: ".").map { Int($0) ?? 0 }
        let b = installed.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private struct Memo: Codable {
        var latest: String?
        var checkedAt: Date
        /// The store version the shell has already announced, so the toast
        /// says each release once.
        var announced: String?
    }

    private static let key = "storeVersion.memo"

    private static func memo() -> Memo? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Memo.self, from: data)
    }

    private static func save(_ m: Memo) {
        if let data = try? JSONEncoder().encode(m) { DefaultsWrite.set(data, forKey: key) }
    }

    /// The newer store version from the last answer, or nil. No request: a
    /// screen reads this in `onAppear`.
    static func cachedNewer() -> String? {
        #if DEBUG
        if let fake = UserDefaults.standard.string(forKey: "storeVersionProbe") { return fake }
        #endif
        guard let latest = memo()?.latest, isNewer(latest, than: installed) else { return nil }
        return latest
    }

    /// Asks the store (unless it answered in the last 12 hours) and returns a
    /// newer version the shell has NOT announced yet, marking it announced.
    /// nil when up to date, already said, or the store did not answer.
    @MainActor
    static func unannouncedNewer() async -> String? {
        #if DEBUG
        // Debug builds are never on the store; only the probe speaks.
        if let fake = UserDefaults.standard.string(forKey: "storeVersionProbe") {
            NSLog("storeVersion: probe %@ over installed %@", fake, installed)
            return fake
        }
        return nil
        #else
        var m = memo() ?? Memo(latest: nil, checkedAt: .distantPast, announced: nil)
        if Date.now.timeIntervalSince(m.checkedAt) > 12 * 3600,
           let latest = await fetch() {
            m.latest = latest
            m.checkedAt = .now
        }
        guard let latest = m.latest, isNewer(latest, than: installed),
              m.announced != latest else {
            save(m)
            return nil
        }
        m.announced = latest
        save(m)
        return latest
        #endif
    }

    private static func fetch() async -> String? {
        var request = URLRequest(url: lookupURL, timeoutInterval: 10)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        NetworkLedger.shared.record(request)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (json["results"] as? [[String: Any]])?.first,
              let version = first["version"] as? String else { return nil }
        return version
    }
}
