import Foundation
import Observation
import SwiftData

/// The OpenSea bridge (2026-07-14) — newly launched NFT collections, with
/// artwork, land in your feed as links. It reaches OpenSea's public v2 API the
/// way the feed-follow bridges reach a site's RSS: fetch → filter → dedupe →
/// things, no algorithm in between. Read-only, public marketplace data —
/// Casberi never shows a path to buy, sell, or bid.
///
/// Two things make this bridge its own shape rather than a HandleSetupScreen:
///   • It follows a list of CHAINS, not accounts — the newest collections on
///     each chain you watch. Ethereum and Base by default; more are a tap.
///   • There's no account and no paste. On connect the app mints its own free,
///     anonymous OpenSea key (`POST /auth/keys`, no signup) and keeps it. The
///     key isn't a credential — anyone can mint one — so it lives in
///     UserDefaults beside the watched chains, not the Keychain.
///
/// The spam problem is real: the absolute newest collections are mostly empty
/// test/airdrop contracts with no art. The quality filter (an image, a name,
/// not flagged) turns "every new contract" into "new drops worth seeing" — and
/// the image it requires becomes the row's thumbnail for free.

// MARK: - Chains

/// The chains Casberi watches for new collections — the popular NFT networks,
/// each a valid OpenSea v2 `chain` slug (verified against the live API). The
/// list is curated, not exhaustive: a chain with no NFT culture would only
/// pad the picker.
enum OpenSeaChain: String, CaseIterable, Identifiable {
    case ethereum, base, polygon, arbitrum, optimism, avalanche, blast

    var id: String { rawValue }

    /// The name shown in the picker and the proof line.
    var display: String {
        switch self {
        case .ethereum:  "Ethereum"
        case .base:      "Base"
        case .polygon:   "Polygon"
        case .arbitrum:  "Arbitrum"
        case .optimism:  "Optimism"
        case .avalanche: "Avalanche"
        case .blast:     "Blast"
        }
    }

    static func from(_ id: String) -> OpenSeaChain? {
        OpenSeaChain(rawValue: id.lowercased())
    }
}

// MARK: - Store (the watched chains + the minted key)

@Observable
final class OpenSeaStore {
    static let shared = OpenSeaStore()
    private static let key = "opensea.state.v1"

    private struct State: Codable {
        var chains: [String] = []
        var apiKey: String = ""
        /// When the minted key expires (OpenSea gives ~30 days). We re-mint a
        /// little early rather than let a sync fail on a just-expired key.
        var keyExpiry: Date?
    }

    private var state: State { didSet { persist() } }

    /// The default watch when someone connects with no chain chosen — the two
    /// chains with the most new-collection culture.
    static let defaultChains = ["ethereum", "base"]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(State.self, from: data) {
            state = saved
        } else {
            state = State()
        }
    }

    var chains: [String] { state.chains }
    var connected: Bool { !state.chains.isEmpty }

    var watchedChains: [OpenSeaChain] { state.chains.compactMap(OpenSeaChain.from) }

    func isWatching(_ chain: OpenSeaChain) -> Bool { state.chains.contains(chain.rawValue) }

    func add(_ chain: OpenSeaChain) {
        guard !state.chains.contains(chain.rawValue) else { return }
        state.chains.append(chain.rawValue)
    }

    func remove(_ chain: OpenSeaChain) {
        state.chains.removeAll { $0 == chain.rawValue }
    }

    /// Connect with the default chains when nothing's watched yet — the
    /// one-tap path (BridgeConnect) and the setup screen's first appearance.
    func connectDefaults() {
        guard state.chains.isEmpty else { return }
        state.chains = Self.defaultChains
    }

    func disconnect() {
        state.chains = []
        // The key is cheap to re-mint; dropping it means a reconnect starts
        // clean rather than reusing a key that may have aged out meanwhile.
        state.apiKey = ""
        state.keyExpiry = nil
    }

    // The minted key. Injectable so a headless probe (and the setup screen's
    // "use your own key" nicety) can seed a known-good key without waiting on
    // the mint endpoint's 1-per-hour limit.
    var apiKey: String { state.apiKey }

    func setKey(_ key: String, expiry: Date?) {
        state.apiKey = key
        state.keyExpiry = expiry
    }

    /// True when the stored key is present and not within a day of expiring —
    /// the signal to reuse it instead of minting.
    var keyIsFresh: Bool {
        guard !state.apiKey.isEmpty else { return false }
        guard let expiry = state.keyExpiry else { return true }   // no expiry known — trust it
        return expiry.timeIntervalSinceNow > 86_400
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

// MARK: - Key (anonymous, self-minted, cached)

enum OpenSeaKey {
    /// A valid API key, minting one if the stored key is missing or aging out.
    /// Returns nil only when there's no stored key AND the mint endpoint won't
    /// hand one over (its limit is one key per hour per IP) — the honest
    /// "couldn't connect" the setup screen words.
    @MainActor
    static func current() async -> String? {
        let store = OpenSeaStore.shared
        if store.keyIsFresh { return store.apiKey }
        if let minted = await mint() {
            store.setKey(minted.key, expiry: minted.expiry)
            return minted.key
        }
        // Mint failed (rate-limited / offline). A stored-but-stale key is still
        // worth trying — an expiry we guessed conservatively may not have hit.
        return store.apiKey.isEmpty ? nil : store.apiKey
    }

    /// `POST /api/v2/auth/keys` with no body — OpenSea's keyless self-serve
    /// mint. Returns the key only when the response actually carries one (a
    /// rate-limit reply is a 200 with an `errors` array and no `api_key`).
    private static func mint() async -> (key: String, expiry: Date?)? {
        guard let url = URL(string: "https://api.opensea.io/api/v2/auth/keys") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        NetworkLedger.shared.record(request)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = json["api_key"] as? String, !key.isEmpty
        else { return nil }
        // OpenSea gives ~30 days. When the field is missing or unparseable,
        // assume a conservative 25 rather than leaving expiry nil — a nil
        // expiry would read as "fresh forever" (keyIsFresh), so the key would
        // never re-mint proactively and could only be recovered reactively.
        let expiry = IngestSupport.isoDate(json["expires_at"])
            ?? Date(timeIntervalSinceNow: 25 * 86_400)
        return (key, expiry)
    }
}

// MARK: - Ingest

enum OpenSeaIngest {

    /// Serializes refreshes — the launch hook can race the foreground refresh,
    /// and both would read "existing" before either saved (the RSS lesson).
    @MainActor private static var running = false

    /// The newest quality collections on one chain, or nil when the fetch
    /// failed (offline, a bad/expired key). Empty (not nil) is a real answer:
    /// the chain had no NEW collection with artwork this pass.
    private static func fetch(_ chain: String, key: String) async -> [Collection]? {
        let url = "https://api.opensea.io/api/v2/collections?chain=\(chain)&order_by=created_date&limit=50"
        guard let root = await IngestSupport.getJSON(url, headers: ["x-api-key": key]) as? [String: Any],
              let raw = root["collections"] as? [[String: Any]]
        else { return nil }
        return raw.compactMap { Collection(json: $0, chain: chain) }
    }

    /// One collection worth landing — parsed and quality-filtered at the door.
    private struct Collection {
        let slug: String
        let name: String
        let url: String
        let image: String

        init?(json: [String: Any], chain: String) {
            guard let slug = json["collection"] as? String, !slug.isEmpty else { return nil }
            let name = ((json["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            // The filter that turns the new-contract firehose into new drops:
            // a real name, artwork (which becomes the row thumbnail), and not
            // flagged. Artwork is the strongest spam signal — empty test and
            // airdrop contracts almost never carry a logo.
            guard !name.isEmpty,
                  !Self.looksLikeAddress(name),
                  (json["is_nsfw"] as? Bool) != true,
                  (json["is_disabled"] as? Bool) != true,
                  let image = IngestSupport.imageURL(json["image_url"] as? String)
            else { return nil }
            self.slug = slug
            self.name = name
            self.image = image
            self.url = (json["opensea_url"] as? String)
                ?? "https://opensea.io/collection/\(slug)"
        }

        /// A name that's really just the contract address (`0x83f2…`) is a
        /// nameless contract wearing its address — not a drop worth a row.
        private static func looksLikeAddress(_ name: String) -> Bool {
            let t = name.lowercased()
            guard t.hasPrefix("0x"), t.count >= 8 else { return false }
            return t.dropFirst(2).allSatisfy { $0.isHexDigit }
        }
    }

    /// Fetches the newest collections on every watched chain and lands new ones
    /// as link things. Returns the number of NEW things, 0 when up to date, nil
    /// when nothing was reachable (offline, or no key could be had).
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        let store = OpenSeaStore.shared
        let chains = store.chains
        guard !chains.isEmpty, !running else { return running ? 0 : nil }
        running = true
        defer { running = false }

        guard let key = await OpenSeaKey.current() else { return nil }

        // Fetch every watched chain concurrently, capped — all requests share
        // one key's quota (60 reads/min on the free tier), so a burst across a
        // dozen chains could trip it where paced calls wouldn't. Key freshness
        // is handled proactively in `OpenSeaKey.current` (re-mint a day before
        // expiry): an all-chains-fail pass is almost always the network, not a
        // dead key, so we DON'T reactively discard the stored key here — doing
        // so would throw away a valid 30-day key on a transient blip and then
        // fail to replace it (offline / the 1-mint-per-hour limit).
        let results = await IngestSupport.boundedGather(chains, maxConcurrent: 4) { chain in
            await fetch(chain, key: key)
        }

        var existing = IngestSupport.existingSourceRefs(context, source: "OpenSea")
        let backfill = ArtlessBackfill(context, source: "OpenSea")
        var added = 0
        var reachedAny = false

        for chainResult in results {
            guard let collections = chainResult else { continue }
            reachedAny = true
            // Newest 12 per chain — the endpoint is a firehose; the corpus isn't.
            for c in collections.prefix(12) {
                let ref = "opensea:\(c.slug)"
                if existing.contains(ref) {
                    backfill.patch(ref, image: c.image)
                    continue
                }
                let thing = Thing(
                    kind: .link,
                    title: IngestSupport.titleLine(c.name),
                    content: c.url,
                    source: "OpenSea",
                    capturedAt: .now,
                    tags: ["NFT"],
                    sourceRef: ref
                )
                thing.previewImageURL = c.image
                context.insert(thing)
                existing.insert(ref)
                SpotlightIndex.index([thing])
                added += 1
            }
        }
        if added > 0 || backfill.any { context.saveHonestly() }
        return reachedAny ? added : nil
    }
}
