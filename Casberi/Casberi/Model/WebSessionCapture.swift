import Foundation

/// WHAT A WEB APP ACTUALLY CALLS, measured instead of guessed (prd §777).
///
/// The session-cookie seats — Spotify §703, Instagram §726, TikTok §731, X
/// §701, Duolingo §776 — all rest on knowing which endpoints a provider's own
/// web app asks and what comes back. For those five that knowledge was public.
/// For Rocket Money, Acorns, NerdWallet, Credit Karma and Cash App it is not:
/// none publishes an API, no community project has mapped one, and a seat
/// written against an invented path is a connectable row that lands nothing —
/// §83's dead control, five times over.
///
/// So this is the measurement, and it is DEBUG-only: a capture signs in
/// through the provider's own page and records what the page then asks for.
/// It is not a seat, has no catalogue offer, and lands nothing in the corpus.
///
/// **IT RECORDS SHAPES, NEVER VALUES.** The whole subject here is a person's
/// money, so what the report may contain is bounded by construction rather
/// than by care:
///
///   · a URL keeps its scheme, host, path and query NAMES; every query VALUE
///     is replaced, and a path segment that is an id is replaced by `<id>` —
///     which also generalises the path, since `/users/8817342/recurring` is
///     only useful as `/users/<id>/recurring`;
///   · a response is reported as its SHAPE — keys, types, array lengths — and
///     never a value, so "you paid Netflix $17.99" cannot reach a log;
///   · an `Authorization` header is reported as its SCHEME (`Bearer`) and
///     never its credential;
///   · only hosts named in `targets` are recorded at all, so an ad network or
///     an analytics beacon riding the same page is never in the report.
///
/// The pure half, Foundation-only, so `web-session-selftest.sh` compiles it
/// whole — every rule above is a test rather than a promise.
enum WebSessionCapture {

    /// The five this exists to measure. A capture runs against a named target
    /// and nothing else: an open-ended "record any site" tool is a different,
    /// worse thing than a bounded measurement of five known providers.
    struct Target: Equatable, Identifiable {
        var id: String { key }
        var key: String
        var name: String
        var signInURL: String
        /// The hosts whose traffic is recorded. Everything else the page
        /// touches is ignored, not merely redacted.
        var apiHosts: [String]
    }

    static let targets: [Target] = [
        Target(key: "rocketmoney", name: "Rocket Money",
               signInURL: "https://app.rocketmoney.com/",
               apiHosts: ["api.rocketmoney.com", "app.rocketmoney.com"]),
        Target(key: "acorns", name: "Acorns",
               signInURL: "https://app.acorns.com/",
               apiHosts: ["api.acorns.com", "app.acorns.com"]),
        Target(key: "nerdwallet", name: "NerdWallet",
               signInURL: "https://www.nerdwallet.com/login",
               apiHosts: ["www.nerdwallet.com", "api.nerdwallet.com"]),
        Target(key: "creditkarma", name: "Credit Karma",
               signInURL: "https://www.creditkarma.com/auth/logon",
               apiHosts: ["www.creditkarma.com", "api.creditkarma.com"]),
        Target(key: "cashapp", name: "Cash App",
               signInURL: "https://cash.app/account",
               apiHosts: ["cash.app", "api.cash.app"]),
    ]

    static func target(_ key: String) -> Target? {
        let wanted = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return targets.first { $0.key == wanted }
    }

    /// Is this host one the named target's report may mention? Suffix-matched
    /// on a DOT boundary, so `evil-cash.app` is not `cash.app`.
    static func records(host: String?, in target: Target) -> Bool {
        guard let host = host?.lowercased(), !host.isEmpty else { return false }
        return target.apiHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    // MARK: - One call

    struct Call: Equatable {
        var method: String
        /// Already redacted — `redactedURL` is the only way one is built.
        var url: String
        var status: Int
        /// `Bearer`, `Basic`, … — the scheme alone, never the credential.
        var authScheme: String?
        /// The response body's shape, or nil where there was nothing to read.
        var shape: String?

        /// A GET is the only thing a seat could ever replay, and the only
        /// thing this report recommends. A POST the page made is still worth
        /// SEEING (it is how a session is minted), so it is recorded — it is
        /// simply never offered as something to repeat.
        var replayable: Bool { method == "GET" && status == 200 }

        /// What a report line looks like, and what dedupes two calls to the
        /// same endpoint with different query values.
        var signature: String { "\(method) \(url)" }
    }

    // MARK: - Redaction

    /// Scheme, host, path and query NAMES. Every query value goes; every path
    /// segment that is an id becomes `<id>`.
    static func redactedURL(_ raw: String) -> String {
        guard var parts = URLComponents(string: raw), let host = parts.host else {
            return "<unreadable url>"
        }
        parts.fragment = nil
        parts.user = nil
        parts.password = nil
        let path = parts.path.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : (looksLikeID(String($0)) ? "<id>" : String($0)) }
            .joined(separator: "/")
        let names = (parts.queryItems ?? []).map { "\($0.name)=‹v›" }
        let scheme = parts.scheme ?? "https"
        let query = names.isEmpty ? "" : "?" + names.joined(separator: "&")
        return "\(scheme)://\(host)\(path)\(query)"
    }

    /// A path segment carrying an account rather than naming an endpoint: a
    /// run of digits, a UUID, or anything long enough and mixed enough to be
    /// a token. Replaced because the PATH is what the report is for, and
    /// `/users/8817342/recurring` is more useful as `/users/<id>/recurring`
    /// anyway.
    static func looksLikeID(_ segment: String) -> Bool {
        if segment.count >= 4, segment.allSatisfy(\.isNumber) { return true }
        if segment.count == 36, segment.filter({ $0 == "-" }).count == 4 { return true }
        if segment.count >= 20,
           segment.contains(where: \.isNumber), segment.contains(where: \.isLetter) { return true }
        return false
    }

    /// `Authorization: Bearer eyJ…` → `Bearer`. Nil for a header that names no
    /// scheme, because reporting the whole value is the one thing this must
    /// never do.
    static func authScheme(_ header: String?) -> String? {
        guard let first = header?.split(separator: " ").first else { return nil }
        let scheme = String(first)
        return scheme.isEmpty ? nil : scheme
    }

    // MARK: - Shape

    /// Depth and width bounds. A dashboard response can be a megabyte of
    /// nested objects, and an unbounded sketch of one is a log nobody reads.
    static let maxDepth = 4
    static let maxKeys = 24

    /// The SHAPE of a JSON body: keys, types and array lengths, never a
    /// value. `{amount: number, merchant: string, nextDate: string}` is
    /// everything a parser needs and nothing about anyone's money.
    static func shape(_ any: Any?, depth: Int = 0) -> String {
        guard depth < maxDepth else { return "…" }
        // Unwrapped FIRST, so no pattern below has to cast through an
        // Optional — `Any?` matched against an `as` pattern is a dynamic cast
        // that quietly does two things at once.
        guard let any, !(any is NSNull) else { return "null" }
        switch any {
        case let dict as [String: Any]:
            let keys = dict.keys.sorted()
            let shown = keys.prefix(maxKeys)
                .map { "\($0): \(shape(dict[$0], depth: depth + 1))" }
            let more = keys.count > maxKeys ? ", +\(keys.count - maxKeys) more" : ""
            return "{" + shown.joined(separator: ", ") + more + "}"
        case let array as [Any]:
            // The FIRST element's shape, and the count. Every element's shape
            // would be the same sketch repeated, and the count is the fact
            // that matters (an empty array is why a seat lands nothing).
            guard let first = array.first else { return "[0]" }
            return "[\(array.count) × \(shape(first, depth: depth + 1))]"
        case is String: return "string"
        case let number as NSNumber:
            // `true` IS an `NSNumber` in a parsed body, and `1 as? Bool`
            // succeeds — so the two cannot be told apart by a Swift cast.
            // The CoreFoundation type id is the only test that answers, and
            // getting it wrong sketches every count in the body as a bool.
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return "bool" }
            return floor(number.doubleValue) == number.doubleValue ? "int" : "number"
        default: return "unknown"
        }
    }

    // MARK: - The report

    /// One line per DISTINCT endpoint, replayable GETs first — those are the
    /// ones a seat could be written against. Deduped on the redacted
    /// signature, so a dashboard paging the same endpoint twenty times is one
    /// line.
    static func report(_ calls: [Call]) -> [String] {
        var seen = Set<String>()
        var unique: [Call] = []
        for call in calls where seen.insert(call.signature).inserted {
            unique.append(call)
        }
        let ordered = unique.sorted {
            $0.replayable == $1.replayable ? $0.signature < $1.signature : $0.replayable
        }
        return ordered.map { call in
            let auth = call.authScheme.map { " auth=\($0)" } ?? " auth=none"
            let shape = call.shape.map { " \($0)" } ?? " (no readable body)"
            return "\(call.replayable ? "GET*" : call.method) \(call.url) → \(call.status)\(auth)\(shape)"
        }
    }

    /// What the capture says when a page made no recordable call at all — a
    /// real outcome (the sign-in never completed, or the dashboard is server
    /// rendered), and one that must not read as a broken tool.
    static let nothingRecorded =
        "no calls to this target's own hosts — either the sign-in did not complete, "
        + "or its dashboard is rendered on the server and has no API to replay"
}
