import Foundation

/// **WHAT THE ACCOUNT IS, READ ONCE (prd §1602).** Whether it is on a network,
/// which contract it answers through, its threshold, whether it has a spend
/// limit's sessions, and who its Signer is change only when an operation of
/// its own changes them (Security's), or from another device. Every send and
/// every preview asked all of them again, three to five round trips over Tor
/// each time; now they are read once, ahead (`readAhead`, when Move opens a
/// network), and kept.
///
/// **Kept until something could have changed them:** forgotten the moment any
/// operation of this account is sent and again once it settles (`submit`),
/// whenever a send fails (Move), and after `life` regardless, for a change
/// made on another device. A stale fact cannot sign the wrong thing: the
/// module's hash, the passkey factory and the Safe's own `checkSignatures`
/// are asked fresh every time, so the worst a stale one does is refuse.
extension YourAccountChain {
    static let factsLife: TimeInterval = 300

    actor Facts {
        struct Known: Sendable {
            var deployed: Bool?
            var entry: YourAccountOp.Entry?
            var threshold: Int?
            var hasSessions: Bool?
            var signers: [String]?
            let at: Date
        }

        static let shared = Facts()
        private var known: [String: Known] = [:]

        func get(_ key: String) -> Known? {
            guard let k = known[key], -k.at.timeIntervalSinceNow < YourAccountChain.factsLife else {
                known[key] = nil
                return nil
            }
            return k
        }

        func set(_ key: String, _ update: @Sendable (inout Known) -> Void) {
            var k = get(key) ?? Known(at: Date())
            update(&k)
            known[key] = k
        }

        func forget(_ key: String) { known[key] = nil }
    }

    private static func factsKey(_ net: Network, _ account: String) -> String { "\(net.chainId)|\(account.lowercased())" }

    /// Forget what is kept of `account` on `net`: an operation was sent, or a
    /// send failed in a way a stale fact could explain.
    static func forgetFacts(_ net: Network, _ account: String) async {
        await Facts.shared.forget(factsKey(net, account))
    }

    static func knownDeployed(_ net: Network, _ account: String) async throws -> Bool {
        let key = factsKey(net, account)
        if let v = await Facts.shared.get(key)?.deployed { return v }
        let v = try await isDeployed(net, account)
        // Only "on it" is kept: a node a block behind a first send would
        // otherwise keep the account off the network for minutes.
        if v { await Facts.shared.set(key) { $0.deployed = true } }
        return v
    }

    static func knownEntry(_ net: Network, _ account: String) async throws -> YourAccountOp.Entry {
        let key = factsKey(net, account)
        if let v = await Facts.shared.get(key)?.entry { return v }
        let v = try await accountEntry(net, account)
        await Facts.shared.set(key) { $0.entry = v }
        return v
    }

    static func knownThreshold(_ net: Network, _ account: String) async throws -> Int {
        let key = factsKey(net, account)
        if let v = await Facts.shared.get(key)?.threshold { return v }
        let v = try await threshold(net, account)
        await Facts.shared.set(key) { $0.threshold = v }
        return v
    }

    static func knownHasSessions(_ net: Network, _ account: String) async throws -> Bool {
        let key = factsKey(net, account)
        if let v = await Facts.shared.get(key)?.hasSessions { return v }
        let v = try await !sessionIds(net, account).isEmpty
        await Facts.shared.set(key) { $0.hasSessions = v }
        return v
    }

    static func knownSigners(_ net: Network, _ account: String) async throws -> [String] {
        let key = factsKey(net, account)
        if let v = await Facts.shared.get(key)?.signers { return v }
        let v = try await signers(net, account)
        await Facts.shared.set(key) { $0.signers = v }
        return v
    }

    /// Everything a send on `net` will ask, asked now and at once, so the tap
    /// has only the nonce, the balances and the hash left to read. The
    /// Signer is read only where both keys can be needed. Failures are
    /// left unkept, and asked again at the send.
    static func readAhead(_ account: String, on net: Network) async {
        guard (try? await knownDeployed(net, account)) == true else { return }
        async let entry = try? knownEntry(net, account)
        async let threshold = try? knownThreshold(net, account)
        async let sessions: Bool? = plan(net) == nil ? nil : try? knownHasSessions(net, account)
        let needsSigner = await threshold.map { $0 >= 2 } ?? false || plan(net) != nil
        if needsSigner { _ = try? await knownSigners(net, account) }
        _ = await (entry, sessions)
    }
}
