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
    /// Use the scoped `source:` overload below whenever a single bridge's
    /// items all carry one source string — this one stays for the bridges
    /// that genuinely dedupe ACROSS sources (Health's Strava/Apple Health
    /// split shares one ref namespace on purpose).
    static func existingSourceRefs(_ context: ModelContext) -> Set<String> {
        var descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef != nil })
        descriptor.propertiesToFetch = [\.sourceRef]
        return Set(((try? context.fetch(descriptor)) ?? []).compactMap(\.sourceRef))
    }

    /// Same as above, scoped to one source string — every foreground refresh
    /// otherwise rebuilds this set from the WHOLE corpus regardless of which
    /// bridge is asking (2026-07-21: ~25 bridges each did this on every
    /// activation). A Farcaster refresh only ever collides with `fc:` refs,
    /// never a wallet transfer or an RSS entry, so scoping to the bridge's
    /// own `source` shrinks the fetch to just that bridge's rows.
    static func existingSourceRefs(_ context: ModelContext, source: String) -> Set<String> {
        var descriptor = FetchDescriptor<Thing>(predicate: #Predicate {
            $0.source == source && $0.sourceRef != nil
        })
        descriptor.propertiesToFetch = [\.sourceRef]
        return Set(((try? context.fetch(descriptor)) ?? []).compactMap(\.sourceRef))
    }

    /// A single already-landed? check, scoped to one source — for a one-off
    /// "is this already watched" gate (TokenWatch/KalshiWatch's Watch button)
    /// where building a whole dedupe Set for one membership test was pure
    /// waste. `fetchLimit = 1` short-circuits at the first match.
    static func hasSourceRef(_ context: ModelContext, source: String, ref: String) -> Bool {
        var descriptor = FetchDescriptor<Thing>(predicate: #Predicate {
            $0.source == source && $0.sourceRef == ref
        })
        descriptor.fetchLimit = 1
        descriptor.propertiesToFetch = [\.sourceRef]
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    /// One source's things still missing a row thumbnail, keyed by sourceRef —
    /// the dict an ingest patches when an item it already landed (skipped by
    /// the ref dedupe) now carries an image. Without this, rows that landed
    /// before their bridge learned artwork would stay glyph-only forever
    /// (the Apple Music pattern, 2026-07-10).
    /// Every landed thing for a source, keyed by ref — for backfilling fields
    /// onto rows that already exist (an avatar the first sync didn't carry).
    /// Every landed thing's `content` for one source — a stable identity
    /// (`chain.explorer + hash` for a wallet transfer) INDEPENDENT of
    /// whatever `sourceRef` scheme landed it. Added 2026-07-19 for the
    /// Zerion/Alchemy wallet-activity cutover: a transfer Alchemy already
    /// landed under its own opaque `uniqueId`-based ref must not re-land a
    /// second time under a new Zerion-sourced ref the day Zerion becomes
    /// primary — the ref sets differ by construction, but the permalink
    /// they'd both produce for the same real transaction doesn't.
    static func existingContent(_ context: ModelContext, source: String) -> Set<String> {
        var descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == source })
        descriptor.propertiesToFetch = [\.content]
        return Set(((try? context.fetch(descriptor)) ?? []).map(\.content))
    }

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

    /// Same shape as `artlessThings`, for a row whose identity slot is empty
    /// — no avatar stored, so the leading slot is drawing the app glyph where
    /// a face belongs (2026-08-14). Read by `ArtlessBackfill.patch(face:)`.
    static func facelessThings(_ context: ModelContext, source: String) -> [String: Thing] {
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate {
            $0.source == source && $0.authorAvatarURL == nil
        })
        var faceless: [String: Thing] = [:]
        for thing in (try? context.fetch(descriptor)) ?? [] {
            if let ref = thing.sourceRef { faceless[ref] = thing }
        }
        return faceless
    }

    /// Same shape as `artlessThings`, for a row that landed with no per-track
    /// URL (a library play whose `Song.url` was nil at ingest time) — the
    /// "Open in Apple Music" verb falls back to the bare app scheme for these
    /// until a later catalog match heals `content`.
    static func contentlessThings(_ context: ModelContext, source: String) -> [String: Thing] {
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate {
            $0.source == source && $0.content == ""
        })
        var contentless: [String: Thing] = [:]
        for thing in (try? context.fetch(descriptor)) ?? [] {
            if let ref = thing.sourceRef { contentless[ref] = thing }
        }
        return contentless
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

    // MARK: - ERC-20 ABI decoding

    /// Decodes an `eth_call` return for `symbol()`/`name()` — ERC-20 has no
    /// enforced return type, and two encodings appear in the wild: the
    /// standard ABI dynamic `string` (an offset word, a length word, then the
    /// UTF8 payload) and, on some pre-standard tokens, a raw `bytes32` (ASCII,
    /// right-padded with zero bytes, no length prefix at all). Tries the
    /// dynamic decode first — assumes the near-universal single-return-value
    /// offset of 0x20, true for every real compiler's output — and falls back
    /// to reading the first word as padded ASCII when that doesn't parse.
    /// Added 2026-07-19 for the keyless symbol/decimals read that replaced
    /// `alchemy_getTokenMetadata` in the approvals and Peer bridges. nil on a
    /// reverted call, malformed data, or an empty result — a token whose name
    /// can't be read falls back to its short hex, never a guess.
    static func decodeABIString(_ hex: String) -> String? {
        var s = hex.lowercased(); if s.hasPrefix("0x") { s.removeFirst(2) }
        guard s.count >= 128 else { return abiWord0AsASCII(s) }
        let lenStart = s.index(s.startIndex, offsetBy: 64)
        let lenEnd = s.index(lenStart, offsetBy: 64)
        if let len = Int(s[lenStart..<lenEnd], radix: 16), len > 0, len < 200 {
            let available = s.distance(from: lenEnd, to: s.endIndex)
            let dataEnd = s.index(lenEnd, offsetBy: min(len * 2, available))
            if dataEnd > lenEnd, let bytes = hexBytes(String(s[lenEnd..<dataEnd])),
               let str = String(bytes: bytes, encoding: .utf8), !str.isEmpty {
                return str
            }
        }
        return abiWord0AsASCII(s)
    }

    /// The bytes32 fallback: the call's first 32-byte word, trimmed at the
    /// first zero byte (right-padding) and decoded as UTF8.
    private static func abiWord0AsASCII(_ s: String) -> String? {
        guard s.count >= 64, let bytes = hexBytes(String(s.prefix(64))) else { return nil }
        let trimmed = bytes.prefix { $0 != 0 }
        guard let str = String(bytes: trimmed, encoding: .utf8), !str.isEmpty else { return nil }
        return str
    }

    private static func hexBytes(_ hex: String) -> [UInt8]? {
        guard hex.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            guard let b = UInt8(hex[idx..<next], radix: 16) else { return nil }
            bytes.append(b)
            idx = next
        }
        return bytes
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

    /// The reverse of `isoDate` — for a caller that needs to hand a `Date`
    /// back into a raw-dictionary shape another parser expects as an ISO
    /// string (the Zerion→Alchemy-shaped transfer mapping, 2026-07-19).
    static func isoString(_ date: Date) -> String { iso.string(from: date) }

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

    /// `titleLine`'s inverse, for a row that draws BOTH (prd §398, 2026-08-17):
    /// the body with the line the title was made from taken off the front, or
    /// nil when nothing else is left.
    ///
    /// It exists because of a defect visible in every notes room and invisible
    /// in the code: an importer that takes its title from the body's first line
    /// — Day One, Apple Journal, Obsidian, a shared Apple Note — stores the
    /// WHOLE body on `content`, and `ExcerptRow` drew the title at body size and
    /// then the content underneath it at subhead size. So the first line of
    /// every multi-line entry was printed twice, one above the other, and the
    /// three lines of excerpt a journal row affords spent one of them saying
    /// what the row had just said.
    ///
    /// The comparison is on the NORMALISED line rather than a string equality
    /// with `content`, which is what the old guard did and why it never fired:
    /// `title` is this function's namesake output — flattened, clamped to 80
    /// with an ellipsis, and (for the journal importers) stripped of leading
    /// markdown heading marks — so a raw body almost never equals it, and an
    /// entry whose first line ran past 80 characters could never match at all.
    static func bodyBelowTitle(_ text: String, title: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed != title else { return nil }
        var lines = trimmed.components(separatedBy: .newlines)
        // The first line that says anything — the same line every one of these
        // importers built its title out of, heading marks and all.
        guard let head = lines.firstIndex(where: {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }) else { return nil }
        let headline = lines[head]
            .trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard titleLine(headline) == title else { return trimmed }
        lines.removeSubrange(...head)
        let rest = lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : rest
    }

    /// One session for every bridge call, instead of `URLSession.shared`'s
    /// 60s default timeout (2026-07-21). A single stalled endpoint used to
    /// hold a connection up to a full minute during the foreground sweep;
    /// callers that already knew better (LinkTitle, ProductMeta, AgentAnswer)
    /// set their own short timeouts, but the shared JSON layer — the path
    /// most bridges ride — never did.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    // MARK: - JSON over HTTP (200 with a JSON body, or nil)

    /// `service` names the caller for the receipts screen, and is needed
    /// only where the HOST comes from the person's own input — a Shopify
    /// store they named, their own self-hosted PostHog, the domain in a
    /// Nostr name. Every other caller leaves it nil and is matched against
    /// `NetworkReach` by host, which is the stronger check. See
    /// `NetworkLedger.Entry.service`.
    static func getJSON(_ url: String, auth: String? = nil,
                        headers: [String: String] = [:],
                        service: String? = nil) async -> Any? {
        guard let u = URL(string: url) else { return nil }
        return await getJSON(u, auth: auth, headers: headers, service: service)
    }

    static func getJSON(_ url: URL, auth: String? = nil,
                        headers: [String: String] = [:],
                        service: String? = nil) async -> Any? {
        var request = URLRequest(url: url)
        apply(auth: auth, headers: headers, to: &request)
        return await run(request, service: service)
    }

    /// A 200 with a UTF-8 TEXT body, or nil.
    ///
    /// For a public document that is structured but is not JSON — Walletbeat's registry
    /// entries are TypeScript object literals (prd §419), the shape `XArchiveImport`
    /// already parses in a file rather than over the wire. It rides the same `send`
    /// funnel as every other read on purpose: a second door past that funnel is a
    /// request the receipts screen can never account for (prd §289).
    static func getText(_ url: URL, headers: [String: String] = [:],
                        service: String? = nil) async -> String? {
        var request = URLRequest(url: url)
        apply(auth: nil, headers: headers, to: &request)
        guard let (data, http) = await send(request, service: service) else { return nil }
        guard http.statusCode == 200 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func postJSON(_ url: String, auth: String? = nil, body: [String: Any],
                         headers: [String: String] = [:],
                         service: String? = nil) async -> Any? {
        guard let u = URL(string: url),
              let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var request = URLRequest(url: u)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        apply(auth: auth, headers: headers, to: &request)
        return await run(request, service: service)
    }

    /// Like `getJSON`, but also hands back the HTTP status — for a caller
    /// that needs to tell "genuinely not found" (404) from "unreachable" (a
    /// transport failure, 0) apart, the same distinction `postJSONStatus`
    /// draws for a POST (2026-07-20, the Safe multisig bridge's "is this
    /// address a Safe at all" detection, which must never cache a transient
    /// outage as a permanent "no").
    static func getJSONStatus(_ url: String, auth: String? = nil,
                              headers: [String: String] = [:],
                              service: String? = nil) async -> (json: Any?, status: Int) {
        guard let u = URL(string: url) else { return (nil, 0) }
        var request = URLRequest(url: u)
        apply(auth: auth, headers: headers, to: &request)
        guard let (data, http) = await send(request, service: service) else { return (nil, 0) }
        guard http.statusCode == 200 else { return (nil, http.statusCode) }
        return (try? JSONSerialization.jsonObject(with: data), http.statusCode)
    }

    /// Like `getJSONStatus`, but ALSO hands back the raw `HTTPURLResponse` —
    /// for a caller that needs a response HEADER, not just the status or the
    /// body (2026-08-09: GitHub's `X-RateLimit-Remaining`/`X-RateLimit-Limit`,
    /// which every authenticated response carries and no endpoint of its own
    /// exposes). The response comes back even on a non-200, since a header
    /// can be worth reading off a failed call too; the body stays nil unless
    /// the status was 200, exactly like `getJSONStatus`.
    static func getJSONResponse(_ url: String, auth: String? = nil,
                                headers: [String: String] = [:],
                                service: String? = nil)
        async -> (json: Any?, status: Int, response: HTTPURLResponse?) {
        guard let u = URL(string: url) else { return (nil, 0, nil) }
        var request = URLRequest(url: u)
        apply(auth: auth, headers: headers, to: &request)
        guard let (data, http) = await send(request, service: service) else { return (nil, 0, nil) }
        guard http.statusCode == 200 else { return (nil, http.statusCode, http) }
        return (try? JSONSerialization.jsonObject(with: data), http.statusCode, http)
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
                               headers: [String: String] = [:],
                               service: String? = nil) async -> (json: Any?, status: Int) {
        guard let u = URL(string: url),
              let payload = try? JSONSerialization.data(withJSONObject: body) else { return (nil, 0) }
        var request = URLRequest(url: u)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        apply(auth: auth, headers: headers, to: &request)
        guard let (data, http) = await send(request, service: service) else { return (nil, 0) }
        guard http.statusCode == 200 else { return (nil, http.statusCode) }
        return (try? JSONSerialization.jsonObject(with: data), http.statusCode)
    }

    /// **The body EVEN WHEN THE STATUS IS NOT 200** (prd §530, 2026-08-30).
    ///
    /// Every other helper here drops a non-200 body, which is right when the
    /// body is the ANSWER — a failed read has nothing to say. It is wrong when
    /// the body is the REFUSAL, and this app has two such callers: a faucet
    /// that answers `{"msg":"invalid address"}` and a JSON-RPC node that
    /// answers `{"error":{"message":"nonce too low"}}`. Through `postJSON`
    /// both of those reach the screen as the same shrug, which is exactly the
    /// class §530 exists to end — the reason was on the wire and was thrown
    /// away one layer below the person who needed it.
    ///
    /// `status` is 0 on a transport error (no response at all), the same
    /// convention `postJSONStatus` uses. The body is whatever parsed, at any
    /// status, and nil when nothing did.
    static func postJSONAnyStatus(_ url: String, auth: String? = nil, body: [String: Any],
                                  headers: [String: String] = [:],
                                  service: String? = nil) async -> (json: Any?, status: Int) {
        guard let u = URL(string: url),
              let payload = try? JSONSerialization.data(withJSONObject: body) else { return (nil, 0) }
        var request = URLRequest(url: u)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        apply(auth: auth, headers: headers, to: &request)
        guard let (data, http) = await send(request, service: service) else { return (nil, 0) }
        return (try? JSONSerialization.jsonObject(with: data), http.statusCode)
    }

    /// A JSON-RPC BATCH: an ARRAY of calls in one request, answered with an
    /// array of results (2026-07-16, Solana activity). `postJSON` above takes a
    /// dictionary body and so can't express this — and the batch is the whole
    /// reason a Solana wallet costs two requests rather than eleven: ten
    /// `getTransaction` calls come back in a single ~0.4s round trip.
    static func postJSONArray(_ url: String, auth: String? = nil, body: [[String: Any]],
                              headers: [String: String] = [:],
                              service: String? = nil) async -> [[String: Any]]? {
        guard let u = URL(string: url),
              let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var request = URLRequest(url: u)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        apply(auth: auth, headers: headers, to: &request)
        return await run(request, service: service) as? [[String: Any]]
    }

    private static func apply(auth: String?, headers: [String: String],
                              to request: inout URLRequest) {
        if let auth { request.setValue(auth, forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
    }

    private static func run(_ request: URLRequest, service: String? = nil) async -> Any? {
        guard let (data, http) = await send(request, service: service),
              http.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// The ONE transport every helper above rides (prd §277). It exists so
    /// there is a single place that sees every bridge request — `run`,
    /// `getJSONStatus` and `postJSONStatus` each used to call
    /// `session.data(for:)` themselves, which meant no single point could
    /// observe the host. Nothing about the request or the response is
    /// recorded except which host was contacted; see `NetworkLedger`.
    private static func send(_ request: URLRequest,
                             service: String? = nil) async -> (Data, HTTPURLResponse)? {
        NetworkLedger.shared.record(request, as: service)
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        // Whether the bridge is still being let in (2026-08-10). This funnel
        // already held the status and handed it only to the immediate caller,
        // who almost always maps it to nil and loses it — so a revoked key was
        // indistinguishable from a quiet week anywhere outside this line.
        // Costs no request: the response is already in hand.
        BridgeHealth.record(host: request.url?.host, status: http.statusCode,
                            named: service)
        return (data, http)
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
///
/// It patches the FACE on the same terms since 2026-08-14, and that half is
/// what makes a new avatar reach a room that is already full. Dedupe never
/// revisits a known ref, so a bridge that starts stamping `authorAvatarURL`
/// today otherwise reaches only rows landed from today on — which for
/// GitHub's stars and watched repos, where the same thirty rows sit there for
/// months, is very nearly nothing at all. The two fetches are separate and
/// each lazy: a row can have its picture and want a face, or the reverse.
@MainActor
final class ArtlessBackfill {
    private let context: ModelContext
    private let source: String
    private var artless: [String: Thing]?
    private var faceless: [String: Thing]?
    /// True once anything was patched — joins the caller's save condition.
    private(set) var any = false

    init(_ context: ModelContext, source: String) {
        self.context = context
        self.source = source
    }

    /// Patches the stored row for an already-landed ref, when the incoming
    /// item carries a usable image and the row has none.
    ///
    /// `face`/`handle` are the identity half: the avatar the leading slot
    /// draws, and the name beside it. Passing them is opt-in per caller, so a
    /// bridge that has never had a face pays nothing for the second fetch.
    func patch(_ ref: String, image: String?, face: String? = nil, handle: String? = nil) {
        patchArt(ref, image: image)
        patchFace(ref, face: face, handle: handle)
    }

    private func patchArt(_ ref: String, image: String?) {
        guard let image = IngestSupport.imageURL(image) else { return }
        if artless == nil { artless = IngestSupport.artlessThings(context, source: source) }
        guard let thing = artless?[ref], thing.previewImageURL == nil else { return }
        thing.previewImageURL = image
        any = true
    }

    private func patchFace(_ ref: String, face: String?, handle: String?) {
        guard let face = IngestSupport.imageURL(face) else { return }
        if faceless == nil { faceless = IngestSupport.facelessThings(context, source: source) }
        guard let thing = faceless?[ref], (thing.authorAvatarURL ?? "").isEmpty else { return }
        thing.authorAvatarURL = face
        if let handle, !handle.isEmpty, (thing.authorHandle ?? "").isEmpty {
            thing.authorHandle = handle
        }
        // The SAME picture cannot be both the identity and the row's art —
        // it would draw twice on one row, once in the leading circle and once
        // beside the title (`artRidesBesideIdentity`). This is not a
        // hypothetical: GitHub's stars and watched-repos feeds filed the repo
        // owner's avatar as `previewImageURL` from the day they shipped until
        // this field existed for them, so every such row on every install is
        // carrying it right now. Clearing it here is what makes the move a
        // move rather than a duplication.
        if thing.previewImageURL == face { thing.previewImageURL = nil }
        any = true
    }
}

/// Unfollowing takes its things with it — the general form (prd §286, user
/// ruling 2026-08-02: "all things if you unfollow them should remove from
/// your all b/c you are no longer following them").
///
/// Every removal verb in the app edited its own list and left the corpus
/// alone, so an unwatched wallet's whole transaction history, an unfollowed
/// channel's casts and a disabled deal source's deals all stayed forever,
/// clearable only by Delete everything. This is the one place that removes
/// them, so a new bridge's unfollow is a one-liner rather than a new chance
/// to forget.
///
/// **This overturns the older reading for FOLLOWS.** The 2026-07-13 "two
/// verbs" ruling (delete things and delete access are separate choices) is
/// still right about ACCESS — disconnecting a bridge doesn't erase what it
/// brought — but a follow is different in kind: its rows are a mirror of an
/// upstream you chose to watch, and once you stop watching, nothing explains
/// them. `StocktwitsBridge.unwatchAll` was the one place that had already
/// reasoned about this and landed on keeping the posts; it now matches.
enum FollowPrune {
    /// Deletes the things of `source` that `matches` claims, saving and
    /// de-indexing once. Returns how many went.
    ///
    /// `matches` runs in Swift, not a `#Predicate` — the source equality has
    /// already narrowed the fetch, and a `#Predicate` reaching into an array
    /// attribute crashes at runtime (see CLAUDE.md). Rows are liveness-checked
    /// here so every caller doesn't have to.
    @MainActor
    @discardableResult
    static func remove(source: String, context: ModelContext,
                       matching: (Thing) -> Bool) -> Int {
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == source })
        var removedIDs: [UUID] = []
        for thing in (try? context.fetch(descriptor)) ?? [] where thing.isLive {
            guard matching(thing) else { continue }
            removedIDs.append(thing.id)
            context.delete(thing)
        }
        guard !removedIDs.isEmpty else { return 0 }
        context.saveHonestly()
        SpotlightIndex.remove(ids: removedIDs)
        return removedIDs.count
    }

    /// Unwatching a wallet takes every row attributed to it — deliberately
    /// NOT scoped to one source. `walletAddress` is stamped by sixteen
    /// different files (plain transfers and approvals, but also Peer fills,
    /// Privacy Pools deposits, Gnosis Pay spends, Aerodrome locks, Uniswap
    /// positions, EtherFi, Bitcoin), so a source-scoped prune would leave
    /// most of an unwatched wallet's history sitting in the feed.
    ///
    /// `stillWatched` is checked first: removing one entry must not clear a
    /// wallet the list still holds.
    @MainActor
    @discardableResult
    static func removeWallet(address: String, stillWatched: [String],
                             context: ModelContext) -> Int {
        let target = address.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return 0 }
        guard !stillWatched.contains(where: { sameAddress($0, target) }) else { return 0 }

        let descriptor = FetchDescriptor<Thing>()
        var removedIDs: [UUID] = []
        for thing in (try? context.fetch(descriptor)) ?? [] where thing.isLive {
            guard sameAddress(thing.walletAddress, target) else { continue }
            removedIDs.append(thing.id)
            context.delete(thing)
        }
        guard !removedIDs.isEmpty else { return 0 }
        context.saveHonestly()
        SpotlightIndex.remove(ids: removedIDs)
        return removedIDs.count
    }

    /// One watched address, compared the way its own chain spells addresses:
    /// EVM is case-insensitive (EIP-55 case is a checksum, not identity),
    /// while base58 (Solana) and bech32 are CASE-SENSITIVE — lowercasing
    /// those folds distinct wallets together (the `heldPricedContracts`
    /// lesson, CLAUDE.md).
    static func sameAddress(_ a: String?, _ b: String) -> Bool {
        guard let a else { return false }
        if a.hasPrefix("0x") && b.hasPrefix("0x") {
            return a.caseInsensitiveCompare(b) == .orderedSame
        }
        return a == b
    }
}
