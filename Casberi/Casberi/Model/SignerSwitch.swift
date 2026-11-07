import Foundation

/// **ANOTHER WALLET FOR THE CO-SIGNER (prd §1644, user: "rainbow isn't
/// loading signature for my co-signer … i can't change wallet and so am
/// stuck").** The pure half of the Signer sheet's way out of one wallet:
/// which wallet doors a pairing gets, what a kept session's ending does to
/// it, and the signal the sheet sends the request waiting on the wallet.
/// Foundation only, so `signer-switch-selftest.sh` compiles it whole.
enum SignerSwitch {
    /// A wallet with its own WalletConnect deep link (item 3). Each scheme
    /// is in `LSApplicationQueriesSchemes`, so `canOpenURL` can answer.
    /// `path` sits between the scheme and `wc?uri=` (OKX's `main/`).
    struct Wallet: Equatable, Sendable {
        let name: String
        let scheme: String
        var path: String = ""
    }

    /// The user's seven, in the user's order (2026-11-03: "doesn't give
    /// option to open walletconnect and pick. so i get stuck"; "Base, Ambire,
    /// MetaMask, Rabby, Zerion, Rainbow, OKX"). The links are each wallet's
    /// `mobile_link` in WalletConnect's own registry (api.web3modal.org
    /// `getWallets`, read 2026-11-03) with `wc?uri=` after it, as AppKit's
    /// modal opens them. Two are not in that form there: Base (formerly
    /// Coinbase Wallet) lists no link, and opens over Coinbase's documented
    /// `cbwallet://wc?uri=`; OKX lists `okex://main` (the OKX app) and
    /// `okxwallet://main` (OKX Wallet), one row whichever is installed.
    /// UNMEASURED (§780b): whether each opens onto the pairing is settled on
    /// a phone.
    static let wallets = [Wallet(name: "Base", scheme: "cbwallet"),
                          Wallet(name: "Ambire", scheme: "ambire"),
                          Wallet(name: "MetaMask", scheme: "metamask"),
                          Wallet(name: "Rabby", scheme: "rabby"),
                          Wallet(name: "Zerion", scheme: "zerion"),
                          Wallet(name: "Rainbow", scheme: "rainbow"),
                          Wallet(name: "OKX", scheme: "okxwallet", path: "main/"),
                          Wallet(name: "OKX", scheme: "okex", path: "main/")]

    /// The wallet a session's peer names itself as ("MetaMask Wallet",
    /// "Coinbase Wallet", "Rainbow"), so the co-signer's own wallet can be
    /// opened onto a fresh pairing with no tap (prd §1700l item 12); nil for
    /// one not in `wallets`.
    static func wallet(peerName: String) -> Wallet? {
        let name = peerName.lowercased()
        return wallets.first { name.contains($0.name.lowercased()) }
    }

    /// A door onto a pairing: a named wallet's own link, or (`wallet` nil)
    /// the bare `wc:` link whichever app claims the scheme takes.
    struct Door: Equatable, Sendable {
        let wallet: Wallet?
        let url: URL
    }

    /// `<scheme>://wc?uri=<the pairing, percent-encoded whole>`.
    static func link(_ wallet: Wallet, pairing: URL) -> URL? {
        var unreserved = CharacterSet.alphanumerics
        unreserved.insert(charactersIn: "-._~")
        guard let uri = pairing.absoluteString.addingPercentEncoding(withAllowedCharacters: unreserved) else { return nil }
        return URL(string: "\(wallet.scheme)://\(wallet.path)wc?uri=\(uri)")
    }

    /// One door per installed wallet, in `wallets`' order, one per name (the
    /// first installed OKX); none installed,
    /// the one `wc:` door as before (item 3).
    static func doors(pairing: URL, installed: (Wallet) -> Bool) -> [Door] {
        var named: [Door] = []
        for w in wallets where installed(w) && !named.contains(where: { $0.wallet?.name == w.name }) {
            if let url = link(w, pairing: pairing) { named.append(Door(wallet: w, url: url)) }
        }
        return named.isEmpty ? [Door(wallet: nil, url: pairing)] : named
    }

    /// How an ask of a paired wallet ended without a signature.
    enum End: Equatable, Sendable {
        /// The wallet deleted the session, or the SDK no longer holds it.
        case gone
        /// The wait ran out with no answer.
        case timedOut
        /// Use another wallet (item 1).
        case switched
        /// Cancel or the sheet pulled down; `sent` once the request had
        /// gone to the wallet.
        case cancelled(sent: Bool)
    }

    /// Whether the session is torn down: a wallet that never answered this
    /// ask is not asked again next time (item 2), and one the person moved
    /// off is let go (item 1). A Cancel before the request went keeps it.
    static func closes(_ end: End) -> Bool {
        switch end {
        case .gone, .timedOut, .switched: true
        case .cancelled(let sent): sent
        }
    }

    /// Whether the same ask goes on over a fresh pairing in the same sheet:
    /// the person chose another wallet, or a session kept from before is
    /// gone (prd §1601). A fresh pairing that is gone at once is not chased.
    static func pairsAfresh(_ end: End, kept: Bool) -> Bool {
        switch end {
        case .switched: true
        case .gone: kept
        case .timedOut, .cancelled: false
        }
    }
}

/// A signal any number of waiters each get their own stream of (prd §1609's
/// Ask again, §1644's Use another wallet). An `AsyncStream` is single-use:
/// cancelling the task iterating it FINISHES it, so the second request of
/// one ask (a kept session gone, then a fresh pairing) heard nothing.
final class SignerSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var over = false

    init() {}

    /// A fresh stream of every `fire` from now until `finish`.
    func stream() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        lock.lock()
        let isOver = over
        if !isOver { waiting[id] = continuation }
        lock.unlock()
        if isOver { continuation.finish(); return stream }
        continuation.onTermination = { [weak self] _ in self?.drop(id) }
        return stream
    }

    func fire() {
        lock.lock()
        let all = Array(waiting.values)
        lock.unlock()
        for c in all { c.yield() }
    }

    func finish() {
        lock.lock()
        over = true
        let all = Array(waiting.values)
        waiting.removeAll()
        lock.unlock()
        for c in all { c.finish() }
    }

    private func drop(_ id: UUID) {
        lock.lock()
        waiting[id] = nil
        lock.unlock()
    }
}
