import Foundation

/// **THE TOKEN MARKS THE HOLDINGS READ ALREADY CARRIES (prd §931).**
///
/// Zerion's positions answer names an icon for nearly every real token
/// (`fungible_info.icon.url`, measured 2026-09-26: 8 of 12 rows on a busy
/// wallet, the four without being unlisted junk), and the app was dropping
/// the field at the parser. So the wallet's pack wore a bundled mark for the
/// dozen symbols `BrandMark` ships and a two-letter monogram for everything
/// else — half a pack of real coins beside half a pack of initials, on a
/// figure whose whole job is to be recognised at a glance (user: *"we aren't
/// fetching all the icons and we have access to them"*).
///
/// This is the book those URLs land in: symbol → URL, written by the ingest
/// once per holdings read, read by `AssetMark` as its middle rung — bundled
/// mark first (offline, shipped, never wrong), the book's picture second, the
/// monogram last. **No new request is made to learn a mark**: the URL rides
/// the read the wallet already pays for, and only the picture itself is
/// fetched, through `RemoteImageLoader`'s cache, from the one host the read
/// names (`cdn.zerion.io`, declared in `NetworkReach`). A URL on any other
/// host is dropped at the parser, so the book can never send the app
/// somewhere a receipt does not resolve.
///
/// Bounded and ordered: the newest 600 symbols, oldest forgotten first, so a
/// wallet that has touched ten thousand airdrops does not grow a defaults
/// blob forever. Persisted through `DefaultsWrite` (§721 — never a defaults
/// write under a lock the main thread can contend).
enum TokenIconBook {
    static let key = "tokenIconBook.v1"
    static let capacity = 600
    /// The one host a book entry may name — the host Zerion's own CDN
    /// answers from. Anything else is refused at `note`, not at fetch time.
    static let host = "cdn.zerion.io"

    private static let lock = NSLock()
    /// Ordered oldest-first; a re-noted symbol moves to the end.
    private static var pairs: [[String]]? = nil

    private static func loaded() -> [[String]] {
        if let pairs { return pairs }
        let stored = (UserDefaults.standard.data(forKey: key))
            .flatMap { try? JSONDecoder().decode([[String]].self, from: $0) } ?? []
        pairs = stored
        return stored
    }

    /// The symbol's key: the ingest's cleaned symbol, case-folded, so "usdc"
    /// and "USDC" are one entry and a pack cell keyed either way finds it.
    static func normalized(_ symbol: String) -> String {
        symbol.trimmingCharacters(in: .whitespaces).uppercased()
    }

    /// Whether a URL may enter the book: https, on `host`, nothing else.
    static func accepts(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString), url.scheme == "https",
              url.host?.lowercased() == host else { return false }
        return true
    }

    /// The picture for a symbol, or nil — the caller then draws its monogram.
    static func url(for symbol: String) -> String? {
        let k = normalized(symbol)
        guard !k.isEmpty else { return nil }
        lock.lock(); defer { lock.unlock() }
        return loaded().last { $0.count == 2 && $0[0] == k }?[1]
    }

    /// Record what a read named. Pairs on a foreign host or with an empty
    /// symbol are skipped; the defaults write happens OUTSIDE the lock.
    static func note(_ found: [(symbol: String, url: String)]) {
        let clean = found.compactMap { pair -> [String]? in
            let k = normalized(pair.symbol)
            guard !k.isEmpty, accepts(pair.url) else { return nil }
            return [k, pair.url]
        }
        guard !clean.isEmpty else { return }
        lock.lock()
        var current = loaded()
        // A read lists positions biggest first, and the cap evicts the
        // OLDEST entry — so the batch is walked backwards, leaving its first
        // row the newest. The first build kept 600 of 928 and evicted the
        // wallet's five largest holdings; the pack drew monograms.
        for pair in clean.reversed() {
            current.removeAll { $0.first == pair[0] }
            current.append(pair)
        }
        if current.count > capacity { current.removeFirst(current.count - capacity) }
        pairs = current
        let snapshot = current
        lock.unlock()
        if let data = try? JSONEncoder().encode(snapshot) {
            DefaultsWrite.set(data, forKey: key)
        }
    }

    /// Everything, for the probe and the harness.
    static func all() -> [(symbol: String, url: String)] {
        lock.lock(); defer { lock.unlock() }
        return loaded().compactMap { $0.count == 2 ? (symbol: $0[0], url: $0[1]) : nil }
    }

    #if DEBUG
    static func forget() {
        lock.lock(); pairs = []; lock.unlock()
        DefaultsWrite.remove(key)
    }
    #endif
}
