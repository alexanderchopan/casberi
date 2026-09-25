import Foundation

/// web3.bio — one keyless lookup that answers "who is this?" across the name
/// services (prd §916, 2026-09-24; `docs/addresses-spec.md` step 1).
///
/// `api.web3.bio/ns/{query}` takes an address or a name and returns every
/// record it links: ENS, Basenames, Linea Name Service, Farcaster, Lens, SNS.
/// `api.ensideas.com` (the resolver `ENS` has used since 2026-07-09) answers
/// ENS alone, one name per call, and could not say whether `jesse.base.eth`
/// is on Base or whether an address is `@jesse` on Farcaster. This is the
/// resolver behind `ENS` now — ensideas stays as the fallback, so a web3.bio
/// outage costs nothing that worked before.
///
/// **MEASURED 2026-09-24**, and every rule below is one of these facts:
///
///   • `/ns/{name}` and `/ns/{address}` both answer a JSON ARRAY of records,
///     each `{platform, identity, address, displayName, avatar, …}`. A 200
///     whose body is not an array is "shape not readable" (§780b), never an
///     empty answer.
///   • An unknown name is a 404 with `{"error":"Not Found"}`; an address with
///     no names is a 200 carrying one `platform: "ethereum"` row whose
///     identity IS the address — a placeholder, not a name, and dropped here.
///   • **A reverse answer names addresses that are NOT the one asked.** For
///     vitalik's `0xd8da…6045` the Farcaster row carries `0x96b6…f279` and the
///     Lens row `0xe4aa…83ff` — web3.bio's own graph joined them. §599's rule
///     stands: a name is believed for an address only when the record's
///     `address` IS that address and the forward query comes back to it.
///     `names(_:ownedBy:)` keeps the first half; `verified(_:is:)` the second.
///   • Cloudflare-cached two hours (`cache-control: max-age=7200`); no rate
///     header is sent, and the keyless limit is unpublished — a 429 is read as
///     throttled, and `AddressNames`' per-pass budget is the app's own cap.
///   • Avatars are third-party hosts (`euc.li`, `media.firefly.land`, an
///     imagekit, a vercel blob). Only a plain http(s) URL is handed back —
///     `ENS.avatar`'s rule, for its reason (an `eip155:` avatar is not an
///     image until a gateway makes it one).
///
/// The pure half (`parse`, `record`, `names(_:ownedBy:)`, `forwardAddress`)
/// compiles whole under `scripts/web3bio-selftest.sh`; the network half is
/// demo-gated at the function that reads (the `ENS.resolve` pattern) and
/// cached per launch INCLUDING misses.
enum Web3Bio {

    static let host = "api.web3.bio"

    /// The platforms a record can carry. Only the NAME services become rows;
    /// `ethereum` and `solana` are web3.bio's placeholder for a bare address.
    enum Platform: String, CaseIterable, Equatable {
        case ens, basenames, linea, farcaster, lens, sns
        case ethereum, solana

        /// The short label a reach row wears beside the name (`AddressNames`).
        var label: String {
            switch self {
            case .ens:       return String(localized: "ENS")
            case .basenames: return String(localized: "Base")
            case .linea:     return String(localized: "Linea")
            case .farcaster: return String(localized: "Farcaster")
            case .lens:      return String(localized: "Lens")
            case .sns:       return String(localized: "SNS")
            case .ethereum, .solana: return ""
            }
        }

        /// A record that names something, as opposed to restating an address.
        var isName: Bool { self != .ethereum && self != .solana }

        /// The names an EVM address can be reached by that ARE NOT ENS —
        /// what `NameResolve.primaryNames` adds beside the ENS row.
        var isLinkedEVMName: Bool {
            switch self {
            case .basenames, .linea, .farcaster, .lens: return true
            default: return false
            }
        }

        /// How the identity is spelled on a row. A Farcaster identity is a
        /// username, and the app spells usernames with the `@`
        /// (`FarcasterStore.handle(forAddress:)`); every name service's
        /// identity is already the name.
        func display(_ identity: String) -> String {
            self == .farcaster ? "@" + identity : identity
        }
    }

    struct Record: Equatable {
        let platform: Platform
        let identity: String
        /// Lowercased for EVM; base58 (case kept) for Solana.
        let address: String
        let displayName: String?
        /// A plain http(s) URL, or nil.
        let avatar: String?
    }

    enum Outcome: Equatable {
        /// A 200 array — possibly EMPTY once the placeholder rows are dropped,
        /// which is the ordinary answer for an address that set no name.
        case records([Record])
        /// A 404: web3.bio holds nothing under this query.
        case none
        /// A 429: asked too often. Not a miss — never cached as one.
        case throttled
        /// Anything else: no answer, a non-200, or a 200 that is not an array.
        case unreadable
    }

    // MARK: - Pure

    /// The URL for one query, or nil when the query cannot be a path segment.
    /// A `/` in a name would turn the one query into a PATH (`§735`'s Gmail
    /// trap), so it is refused rather than encoded.
    static func url(for query: String) -> URL? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !q.contains("/"), !q.contains("?"),
              let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "https://\(host)/ns/\(encoded)")
    }

    static func parse(_ json: Any?, status: Int) -> Outcome {
        switch status {
        case 404: return .none
        case 429: return .throttled
        case 200: break
        default:  return .unreadable
        }
        guard let rows = json as? [Any] else { return .unreadable }
        return .records(rows.compactMap { record($0 as? [String: Any]) })
    }

    /// One row, or nil for a row this app cannot use: an unknown platform,
    /// a placeholder, a missing identity or address.
    static func record(_ row: [String: Any]?) -> Record? {
        guard let row,
              let raw = row["platform"] as? String,
              let platform = Platform(rawValue: raw.lowercased()),
              platform.isName,
              let identity = row["identity"] as? String, !identity.isEmpty,
              let address = row["address"] as? String, !address.isEmpty
        else { return nil }
        let folded = platform == .sns ? address : address.lowercased()
        let avatar = (row["avatar"] as? String).flatMap { $0.hasPrefix("http") ? $0 : nil }
        let display = (row["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return Record(platform: platform, identity: identity, address: folded,
                      displayName: display, avatar: avatar)
    }

    /// The records that name THIS address — the first half of §599. The
    /// comparison folds case because EIP-55 spells one address two ways.
    static func names(_ records: [Record], ownedBy address: String) -> [Record] {
        records.filter { $0.address.caseInsensitiveCompare(address) == .orderedSame }
    }

    /// A forward answer: the address of the record whose identity IS the
    /// name asked for. A reverse-shaped array can carry other people's
    /// records beside it (measured), so the identity is matched, never the
    /// first row taken.
    static func forwardAddress(_ records: [Record], for name: String) -> String? {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return records.first { $0.identity.caseInsensitiveCompare(wanted) == .orderedSame }?.address
    }

    /// A name row as the address card lists it — the shape `NameResolve.PrimaryName`
    /// is built from, kept here so the folding rule below compiles under the
    /// harness without the router.
    struct Named: Equatable {
        var label: String
        var name: String
    }

    /// **One name, one row.** MEASURED on the first card drawn (jesse's):
    /// ensideas reverse-names `jesse.base.eth` as ENS — a Basename IS an ENS
    /// subname — and web3.bio files the same name under Basenames, so the
    /// card held it twice and, keyed by value, drew the first row twice. A
    /// later, more specific service RELABELS the row where it stands rather
    /// than adding a second; the fixed order (ENS first) is untouched, and a
    /// genuinely different name still appends.
    static func fold(_ row: Named, into rows: inout [Named]) {
        if let i = rows.firstIndex(where: { $0.name.caseInsensitiveCompare(row.name) == .orderedSame }) {
            rows[i].label = row.label
        } else {
            rows.append(row)
        }
    }

    // MARK: - Network

    /// Per launch, misses included: a nameless address must not cost a
    /// lookup on every refresh forever. A throttle or an unreadable answer is
    /// NOT stored, so the next intent asks again.
    @MainActor private static var cache: [String: Outcome] = [:]
    #if DEBUG
    @MainActor static func forgetCache() { cache = [:] }
    #endif

    @MainActor
    static func lookup(_ query: String) async -> Outcome {
        guard !DemoMode.isActive else { return .unreadable }
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let cached = cache[key] { return cached }
        guard let url = url(for: query) else { return .unreadable }
        let (json, status) = await IngestSupport.getJSONStatus(url.absoluteString)
        let outcome = parse(json, status: status)
        switch outcome {
        case .records, .none: cache[key] = outcome
        case .throttled, .unreadable: break
        }
        return outcome
    }

    /// A name's address, or nil — not known, not answered, or (for an EVM
    /// caller) not hex. The alphabet is the record's: `.sol` gives base58.
    @MainActor
    static func resolve(_ name: String) async -> String? {
        guard case .records(let records) = await lookup(name) else { return nil }
        return forwardAddress(records, for: name)
    }

    /// Every name record web3.bio holds FOR this address — the ones whose own
    /// `address` is it. Not yet forward-verified; see `verified(_:is:)`.
    @MainActor
    static func names(for address: String) async -> [Record] {
        guard case .records(let records) = await lookup(address) else { return [] }
        return names(records, ownedBy: address)
    }

    /// The second half of §599: the forward query for this record's own
    /// platform and identity comes back to the address. Fails CLOSED.
    @MainActor
    static func verified(_ record: Record, is address: String) async -> Bool {
        guard case .records(let records) = await lookup("\(record.platform.rawValue),\(record.identity)")
        else { return false }
        return names(records, ownedBy: address)
            .contains { $0.platform == record.platform
                     && $0.identity.caseInsensitiveCompare(record.identity) == .orderedSame }
    }

    /// The first http(s) avatar among the records that name this query —
    /// the ENS one first, because that is the picture people set on purpose.
    @MainActor
    static func avatar(for query: String) async -> String? {
        guard case .records(let records) = await lookup(query) else { return nil }
        let own = ENS.isHexAddress(query) ? names(records, ownedBy: query) : records
        return (own.first { $0.platform == .ens }?.avatar) ?? own.compactMap(\.avatar).first
    }

    #if DEBUG
    /// `-web3bioProbe <name|0x…>` — every record for one query, and for an
    /// address the verdict beside each: whether it names the address at all,
    /// and whether it forward-verifies. One line per fact (the `-todayProbe`
    /// truncation lesson).
    @MainActor
    static func probe(_ spec: String) async -> [String] {
        var lines = ["demo=\(DemoMode.isActive ? "ACTIVE — every read returns nil" : "off")"]
        let asked = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("query \(asked) → \(url(for: asked)?.absoluteString ?? "REFUSED (not a path segment)")")
        switch await lookup(asked) {
        case .none:       lines.append("  404 — nothing under this query")
        case .throttled:  lines.append("  429 — throttled")
        case .unreadable: lines.append("  unreadable — no answer, or not an array")
        case .records(let records):
            lines.append("  \(records.count) name record(s)")
            for r in records {
                var line = "  \(r.platform.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)) \(r.platform.display(r.identity)) → \(r.address)"
                if ENS.isHexAddress(asked) {
                    let owns = r.address.caseInsensitiveCompare(asked) == .orderedSame
                    line += owns ? " owns=yes" : " owns=NO (web3.bio's link, not this address's)"
                    if owns { line += " verified=\(await verified(r, is: asked))" }
                }
                if let a = r.avatar { line += " avatar=\(a.prefix(48))" }
                lines.append(line)
            }
        }
        return lines
    }
    #endif
}
