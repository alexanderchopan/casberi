import Foundation
import SwiftData

/// The shared plumbing of every remote ingest (fetch → parse → dedupe →
/// things): the dedupe set, ISO 8601 dates with and without fractional
/// seconds, the one-line title clamp, and the JSON calls.
enum IngestSupport {

    /// A Safari-shaped User-Agent, shared by the callers that reach store
    /// pages behind a bot-WAF (Shopify catalogs, product-page price parsing) —
    /// a phone fetch that looks like the phone's own browser gets through more
    /// often. One copy so a version bump can't drift between callers.
    static let safariUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"

    /// Alchemy read-only key, restricted to reads, shared by every caller
    /// (wallet transfers, token charts) so a rotation touches one line — not
    /// one per file. If it ever leaks, the worst case is quota use on public
    /// data — rotate at dashboard.alchemy.com.
    static let alchemyKey = "8ilcJd0_tmnF-IPrI3CRl"

    /// Every sourceRef already in the corpus — the set incoming items
    /// dedupe against. Runs on the caller's context, like the fetches it
    /// replaced. A partial fetch: the predicate skips the many rows with no
    /// ref (notes, approvals), and propertiesToFetch faults in only the
    /// sourceRef column, so a refresh no longer hydrates the whole corpus.
    static func existingSourceRefs(_ context: ModelContext) -> Set<String> {
        var descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef != nil })
        descriptor.propertiesToFetch = [\.sourceRef]
        return Set(((try? context.fetch(descriptor)) ?? []).compactMap(\.sourceRef))
    }

    /// One source's things still missing a row thumbnail, keyed by sourceRef —
    /// the dict an ingest patches when an item it already landed (skipped by
    /// the ref dedupe) now carries an image. Without this, rows that landed
    /// before their bridge learned artwork would stay glyph-only forever
    /// (the Apple Music pattern, 2026-07-10).
    /// Every landed thing for a source, keyed by ref — for backfilling fields
    /// onto rows that already exist (an avatar the first sync didn't carry).
    static func thingsByRef(_ context: ModelContext, source: String) -> [String: Thing] {
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == source })
        var map: [String: Thing] = [:]
        for thing in (try? context.fetch(descriptor)) ?? [] {
            if let ref = thing.sourceRef { map[ref] = thing }
        }
        return map
    }

    static func artlessThings(_ context: ModelContext, source: String) -> [String: Thing] {
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate {
            $0.source == source && $0.previewImageURL == nil
        })
        var artless: [String: Thing] = [:]
        for thing in (try? context.fetch(descriptor)) ?? [] {
            if let ref = thing.sourceRef { artless[ref] = thing }
        }
        return artless
    }

    /// Normalizes a candidate row-thumbnail URL into something RemoteThumb
    /// can actually fetch — https only (ATS blocks cleartext, and every
    /// image CDN speaks TLS), protocol-relative "//host" upgraded, relative
    /// paths and empty strings rejected. A bad URL stored is worse than
    /// none: a non-nil previewImageURL takes the row out of the artless set
    /// for good.
    /// HTML entities in ingested text — the five named ones titles actually
    /// use PLUS numeric character references ("&#8217;" landed raw in feed
    /// titles, caught in a mockup 2026-07-10). &amp; decodes LAST so a
    /// double-encoded reference resolves in one pass.
    static func decodeHTMLEntities(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
        while let r = out.range(of: "&#[xX]?[0-9a-fA-F]+;", options: .regularExpression) {
            let body = out[r].dropFirst(2).dropLast()
            let scalar: UInt32? = (body.hasPrefix("x") || body.hasPrefix("X"))
                ? UInt32(body.dropFirst(), radix: 16)
                : UInt32(body)
            if let scalar, let u = Unicode.Scalar(scalar) {
                out.replaceSubrange(r, with: String(Character(u)))
            } else {
                out.replaceSubrange(r, with: "")   // malformed — drop, never loop
            }
        }
        return out.replacingOccurrences(of: "&amp;", with: "&")
    }

    static func imageURL(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else { return nil }
        if s.hasPrefix("//") { s = "https:" + s }
        if s.hasPrefix("http://") { s = "https://" + s.dropFirst("http://".count) }
        guard s.hasPrefix("https://"), URL(string: s) != nil else { return nil }
        return s
    }

    /// A token logo from a market API (GeckoTerminal/Dexscreener), minus its
    /// "no logo here" sentinels — the flow serves a literal "missing" or a
    /// shared `dexscreener-icon.png` placeholder for a token with no real face,
    /// and a wrong mark is worse than none. Normalizes the survivor to https.
    /// Shared by GeckoTrending's trending feed and TokenWatch's logo fallback.
    static func tokenLogoURL(_ raw: Any?) -> String? {
        guard let s = raw as? String, !s.isEmpty, s != "missing",
              !s.contains("dexscreener-icon.png") else { return nil }
        return imageURL(s)
    }

    // MARK: - Dates

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Some APIs (Readwise, Bluesky) send fractional seconds.
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func isoDate(_ raw: Any?) -> Date? {
        guard let s = raw as? String else { return nil }
        return iso.date(from: s) ?? isoFractional.date(from: s)
    }

    // MARK: - Titles

    /// Thing titles are one line: newlines flatten and 80 chars is the cap.
    static func titleLine(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count > 80 ? String(flat.prefix(80)) + "…" : flat
    }

    // MARK: - JSON over HTTP (200 with a JSON body, or nil)

    static func getJSON(_ url: String, auth: String? = nil,
                        headers: [String: String] = [:]) async -> Any? {
        guard let u = URL(string: url) else { return nil }
        return await getJSON(u, auth: auth, headers: headers)
    }

    static func getJSON(_ url: URL, auth: String? = nil,
                        headers: [String: String] = [:]) async -> Any? {
        var request = URLRequest(url: url)
        apply(auth: auth, headers: headers, to: &request)
        return await run(request)
    }

    static func postJSON(_ url: String, auth: String? = nil, body: [String: Any],
                         headers: [String: String] = [:]) async -> Any? {
        guard let u = URL(string: url),
              let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var request = URLRequest(url: u)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        apply(auth: auth, headers: headers, to: &request)
        return await run(request)
    }

    /// Like `postJSON`, but hands back the HTTP status alongside the decoded
    /// body so a caller can back off on a 429 (rate limit) or a transient 5xx
    /// instead of treating every non-200 as a permanent failure (2026-07-17:
    /// the shipped Alchemy key is shared across all users on the free tier, so
    /// the holdings fetch needs to distinguish "rate-limited, retry" from
    /// "unreachable, give up"). `status` is 0 on a transport error (no
    /// response at all — offline, DNS, connection reset). The body is nil
    /// unless the status was 200, exactly like `postJSON`.
    static func postJSONStatus(_ url: String, auth: String? = nil, body: [String: Any],
                               headers: [String: String] = [:]) async -> (json: Any?, status: Int) {
        guard let u = URL(string: url),
              let payload = try? JSONSerialization.data(withJSONObject: body) else { return (nil, 0) }
        var request = URLRequest(url: u)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        apply(auth: auth, headers: headers, to: &request)
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return (nil, 0) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { return (nil, status) }
        return (try? JSONSerialization.jsonObject(with: data), status)
    }

    /// A JSON-RPC BATCH: an ARRAY of calls in one request, answered with an
    /// array of results (2026-07-16, Solana activity). `postJSON` above takes a
    /// dictionary body and so can't express this — and the batch is the whole
    /// reason a Solana wallet costs two requests rather than eleven: ten
    /// `getTransaction` calls come back in a single ~0.4s round trip.
    static func postJSONArray(_ url: String, auth: String? = nil, body: [[String: Any]],
                              headers: [String: String] = [:]) async -> [[String: Any]]? {
        guard let u = URL(string: url),
              let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var request = URLRequest(url: u)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        apply(auth: auth, headers: headers, to: &request)
        return await run(request) as? [[String: Any]]
    }

    private static func apply(auth: String?, headers: [String: String],
                              to request: inout URLRequest) {
        if let auth { request.setValue(auth, forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
    }

    private static func run(_ request: URLRequest) async -> Any? {
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    // MARK: - Bounded concurrent fan-out

    /// Runs `work` across `items` with at most `maxConcurrent` in flight at
    /// once, returning results in `items`' ORIGINAL order (not completion
    /// order) — the shape every ingest's fetch-then-sequential-bookkeeping
    /// split needs. A wallet/RSS/feed-follow refresh used to fetch one item
    /// at a time; firing every item at once instead can out-burst a
    /// provider's rate limit (Alchemy's key, Reddit's `.rss` endpoint) in a
    /// way the old serial pacing never did. Capping keeps the concurrency
    /// win without the burst (2026-07-13).
    static func boundedGather<Item, Output>(
        _ items: [Item], maxConcurrent: Int, _ work: @escaping (Item) async -> Output
    ) async -> [Output] {
        guard !items.isEmpty else { return [] }
        return await withTaskGroup(of: (Int, Output).self) { group in
            var results = [Output?](repeating: nil, count: items.count)
            var nextIndex = 0
            func submitNext() {
                guard nextIndex < items.count else { return }
                let i = nextIndex
                let item = items[i]
                group.addTask { (i, await work(item)) }
                nextIndex += 1
            }
            for _ in 0..<min(maxConcurrent, items.count) { submitNext() }
            while let (i, output) = await group.next() {
                results[i] = output
                submitNext()
            }
            return results.map { $0! }
        }
    }
}


/// The backfill half of an ingest's dedupe loop (2026-07-10): when an
/// incoming item's ref already landed but the stored row is still wearing
/// the bridge glyph, the item's image patches it in place. The artless
/// fetch is LAZY — in the steady state (every row already has its art, or
/// the duplicates carry no image) a refresh never pays for it.
@MainActor
final class ArtlessBackfill {
    private let context: ModelContext
    private let source: String
    private var artless: [String: Thing]?
    /// True once anything was patched — joins the caller's save condition.
    private(set) var any = false

    init(_ context: ModelContext, source: String) {
        self.context = context
        self.source = source
    }

    /// Patches the stored row for an already-landed ref, when the incoming
    /// item carries a usable image and the row has none.
    func patch(_ ref: String, image: String?) {
        guard let image = IngestSupport.imageURL(image) else { return }
        if artless == nil { artless = IngestSupport.artlessThings(context, source: source) }
        guard let thing = artless?[ref], thing.previewImageURL == nil else { return }
        thing.previewImageURL = image
        any = true
    }
}
