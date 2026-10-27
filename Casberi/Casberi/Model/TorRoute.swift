import Foundation

/// **WHICH REQUESTS GO THROUGH TOR (prd §1495).**
///
/// Every request that names a wallet — yours or one you follow — is sent
/// through Tor, so no service learns where you are, and none can tell that
/// the wallets you look at belong to one person. The rule is read off
/// `NetworkReach`: an entry marked `throughTor` routes its hosts, except the
/// hosts measured refusing every Tor exit (`refusesTor`), which go direct and
/// are listed as such where the app states what it reaches. The Feed's apps
/// never go through Tor: a signed-in session met from a new exit every few
/// minutes reads as a hijacked account, and none of them carries an address.
///
/// One circuit per wallet: the isolation key is the first address the request
/// names, so two wallets you follow never share an exit (Tor's
/// `IsolateSOCKSAuth`, keyed by the SOCKS username). A request naming no
/// address shares its host's circuit.
///
/// Not a setting and not optional (prd §1495 item 1): where Tor cannot
/// connect, the wallets stand on their last readings, stamped (prd §825), and
/// nothing reads them another way.
enum TorRoute {

    enum Way: Equatable {
        /// Through Tor, on the circuit for this key.
        case tor(isolation: String)
        /// Not a wallet request, or Tor is not part of this build (the Mac).
        case direct
        /// A wallet host measured refusing every Tor exit; read directly and
        /// listed as such (`NetworkReach.Endpoint.refusesTor`).
        case refusesTor
    }

    /// Whether this build can run Tor at all. The release carries no Mac
    /// Catalyst slice (`Vendor/TorKit/Package.swift`), so the Mac reads
    /// directly and says so.
    static var available: Bool {
        #if canImport(TorShim)
        true
        #else
        false
        #endif
    }

    static func way(for request: URLRequest) -> Way {
        way(host: request.url?.host(), url: request.url?.absoluteString ?? "",
            body: request.httpBody)
    }

    /// The pure rule, for `tor-route-selftest.sh`.
    static func way(host: String?, url: String, body: Data?) -> Way {
        guard let host = host?.lowercased(), !host.isEmpty else { return .direct }
        guard let endpoint = endpoint(forHost: host), endpoint.throughTor else { return .direct }
        if endpoint.refusesTor.contains(where: { NetworkReach.matches(host: host, declared: $0) }) {
            return .refusesTor
        }
        guard available else { return .direct }
        return .tor(isolation: isolationKey(url: url, body: body, host: host))
    }

    /// Whether `host` may be read directly once Tor refused it
    /// (`NetworkReach.Endpoint.directWhenRefused`).
    static func fallsBack(host: String?) -> Bool {
        guard let host = host?.lowercased(), let endpoint = endpoint(forHost: host) else { return false }
        return endpoint.directWhenRefused.contains { NetworkReach.matches(host: host, declared: $0) }
    }

    /// The entry that owns `host`, longest declared host first — the
    /// receipts' own rule (`NetworkReach.service(forHost:)`).
    static func endpoint(forHost host: String) -> NetworkReach.Endpoint? {
        NetworkReach.service(forHost: host).flatMap(NetworkReach.endpoint(forService:))
    }

    /// The first wallet the request names — an EVM address, a Solana or
    /// Bitcoin one in the path — lowercased where case carries nothing; else
    /// the host.
    static func isolationKey(url: String, body: Data?, host: String) -> String {
        let text = url + " " + (body.flatMap { String(data: $0, encoding: .utf8) } ?? "")
        if let evm = text.range(of: #"0x[0-9a-fA-F]{40}(?![0-9a-fA-F])"#, options: .regularExpression) {
            return String(text[evm]).lowercased()
        }
        if let btc = url.range(of: #"/address/(bc1[02-9ac-hj-np-z]{8,87}|[13][1-9A-HJ-NP-Za-km-z]{25,34})"#,
                               options: .regularExpression) {
            return String(url[btc].dropFirst("/address/".count))
        }
        return host
    }
}

/// When a host was last reached directly after Tor refused it, so the move
/// that used it can say "not through Tor" (prd §1495's one fallback).
final class TorFallback: @unchecked Sendable {
    static let shared = TorFallback()
    private let lock = NSLock()
    private var at: [String: Date] = [:]

    func note(_ host: String) {
        lock.lock(); defer { lock.unlock() }
        at[host.lowercased()] = Date()
    }

    func happened(_ host: String, since: Date) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return (at[host.lowercased()] ?? .distantPast) >= since
    }
}
