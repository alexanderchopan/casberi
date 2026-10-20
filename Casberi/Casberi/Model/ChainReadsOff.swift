#if DEBUG
import Foundation

/// A DEBUG build reaches neither Alchemy nor Zerion unless asked (2026-10-20).
///
/// Both keys are shipped and SHARED by every install, and UI testing was
/// spending them: every `-onboarded YES` launch pours the dev seed's watched
/// wallets and reads them all, Zerion's demo tier (300 a day, 1 a second)
/// overflows onto Alchemy's per-wallet × per-chain fan-out, and Alchemy
/// reported 10% of an hour's requests rate limited. A screen being looked at
/// does not need a live balance; a wallet that cannot be reached stands on its
/// last reading (prd §825), and the demo carries its own money.
///
/// Blocked at the network boundary, as the demo is, because 17 files build
/// these URLs. A blocked request fails as a dropped connection, status 0 — an
/// outage, never a 4xx, so `WalletIngest.RefusedNetworks` learns nothing and
/// no chain is marked refused for a week (prd §827b).
///
/// `-liveChains YES` puts the reads back, for work that needs a real answer
/// (`-holdingsProbe`, `-portfolioProbe`, a new chain), for that launch only.
/// Every blocked host logs `chainReadsOff: blocked <host>` once a process.
final class ChainReadsOff: URLProtocol {
    static let blockedSuffixes = ["alchemy.com", "zerion.io"]

    static var isOn: Bool { !UserDefaults.standard.bool(forKey: "liveChains") }

    /// Registers for `URLSession.shared`; sessions built from a configuration
    /// add `ChainReadsOff.self` to their `protocolClasses` themselves.
    static func install() {
        guard isOn else { NSLog("chainReadsOff: off (-liveChains YES)"); return }
        URLProtocol.registerClass(ChainReadsOff.self)
        NSLog("chainReadsOff: on — Alchemy and Zerion are not reached (-liveChains YES to read)")
    }

    static func blocks(_ host: String?) -> Bool {
        guard isOn, let host = host?.lowercased() else { return false }
        return blockedSuffixes.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    override class func canInit(with request: URLRequest) -> Bool { blocks(request.url?.host) }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    nonisolated(unsafe) private static var logged = Set<String>()
    private static let logLock = NSLock()

    override func startLoading() {
        if let host = request.url?.host {
            let first = Self.logLock.withLock { Self.logged.insert(host).inserted }
            if first { NSLog("chainReadsOff: blocked %@", host) }
        }
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
#endif
