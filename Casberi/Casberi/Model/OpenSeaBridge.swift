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
        /// The chain it was read from. Passed in because the listing payload
        /// doesn't repeat it, and STORED because a landed row that can't say
        /// which chain it came from can't be narrowed to one — and the watch
        /// is a list of chains, so that's the first narrowing anyone wants.
        let chain: String
        /// OpenSea's own blurb, when the collection wrote one.
        let description: String?
        /// When the collection was created. This endpoint is literally SORTED
        /// by it, so it is the row's real news moment — a new drop's creation
        /// IS the event, the way `HuggingFaceIngest` stamps a release with its
        /// own `createdAt` so a backfill sorts back to where it happened.
        let created: Date?
        /// OpenSea's own verified badge (`safelist_status == "verified"`) —
        /// their judgement, not ours. Every other value the field carries
        /// (`not_requested`, `requested`, `approved`, …) says nothing we'd
        /// stand behind, so only the literal word lands and everything else
        /// is simply untagged. Silence is the honest failure here: a wrong
        /// "Verified" on an NFT row is exactly the fake status §83 bans.
        let verified: Bool

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
            self.chain = chain
            self.description = Self.blurb(json["description"])
            self.created = Self.createdDate(json["created_date"])
            self.verified = (json["safelist_status"] as? String)?
                .lowercased() == "verified"
            self.url = (json["opensea_url"] as? String)
                ?? "https://opensea.io/collection/\(slug)"
        }

        /// "NFT", the chain, and the badge when there is one. `Thing.init`
        /// prepends the type tag and de-dupes, so this is only the
        /// differentiating half. The chain gets its display spelling
        /// ("Ethereum", not "ethereum") — an unknown slug falls through as
        /// itself rather than being dropped, since a chain we stopped
        /// recognising is still where the row came from.
        var tags: [String] {
            var out = ["NFT", OpenSeaChain.from(chain)?.display ?? chain]
            if verified { out.append("Verified") }
            return out
        }

        /// A name that's really just the contract address (`0x83f2…`) is a
        /// nameless contract wearing its address — not a drop worth a row.
        private static func looksLikeAddress(_ name: String) -> Bool {
            let t = name.lowercased()
            guard t.hasPrefix("0x"), t.count >= 8 else { return false }
            return t.dropFirst(2).allSatisfy { $0.isHexDigit }
        }

        /// The collection's own description, trimmed and bounded. Display copy
        /// (`summary`), because OpenSea handed it to us in its own payload —
        /// the 2026-07-22 split — but bounded because this is the one text
        /// field on the spammiest endpoint in the catalog: the quality filter
        /// above screens for a name and artwork, neither of which stops a real
        /// collection from pasting an essay. 600 characters is a paragraph,
        /// which is what the sheet's summary block is shaped for.
        private static func blurb(_ raw: Any?) -> String? {
            guard let s = (raw as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty
            else { return nil }
            return s.count > 600 ? String(s.prefix(600)) + "…" : s
        }

        /// `created_date` as a real date, or nil when nothing reads it.
        ///
        /// `IngestSupport.isoDate` first, then a zoneless fallback, and the
        /// fallback is the point: OpenSea has served this stamp both with and
        /// without a timezone designator, and `ISO8601DateFormatter` refuses
        /// the zoneless form outright. Trusting the shared helper alone would
        /// leave every row quietly falling back to `.now` — a silent no-op
        /// that looks exactly like the bug this parse exists to fix.
        /// UNMEASURED against the live API (no egress to api.opensea.io from
        /// the build host); nil keeps the old `.now` behaviour, so it fails
        /// safe either way.
        private static func createdDate(_ raw: Any?) -> Date? {
            if let date = IngestSupport.isoDate(raw) { return date }
            guard var s = (raw as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty
            else { return nil }
            // Fractional seconds are DROPPED, not parsed: OpenSea writes six
            // digits where `.withFractionalSeconds` expects three, and a
            // sub-second on a creation date buys nothing. Cutting to the next
            // non-digit keeps a trailing `Z`/offset if one is there, so the
            // zoned-but-six-digit shape re-reads through `isoDate` below.
            if let dot = s.firstIndex(of: ".") {
                let tail = s[s.index(after: dot)...]
                let end = tail.firstIndex(where: { !$0.isNumber }) ?? s.endIndex
                s.removeSubrange(dot..<end)
            }
            return IngestSupport.isoDate(s) ?? zoneless.date(from: s)
        }

        /// The zoneless form, read as UTC — which is what OpenSea documents
        /// its timestamps to be. `en_US_POSIX` because a device locale would
        /// reinterpret the digits (the Snapchat export lesson).
        private static let zoneless: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            return f
        }()
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
                    // The collection's OWN creation moment, which is the
                    // moment this row is news about — not when a sync
                    // happened to notice it. Falls back to `.now` only when
                    // the stamp can't be read at all, which is the old
                    // behaviour and the honest one: a date we couldn't parse
                    // must not become a date we invented.
                    capturedAt: c.created ?? .now,
                    tags: c.tags,
                    sourceRef: ref
                )
                thing.previewImageURL = c.image
                thing.summary = c.description
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
