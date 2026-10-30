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
            var at: Date
        }

        static let shared = Facts()
        private var known: [String: Known] = [:]
        /// Bumped by every forget, so a read begun before it keeps nothing.
        private var generations: [String: Int] = [:]
        /// The reads under way, by key and fact: a second asker joins the
        /// first (prd §1610: a tap during the read-ahead asked it all again).
        private var reading: [String: Task<any Sendable, Error>] = [:]

        func get(_ key: String) -> Known? {
            guard let k = known[key], -k.at.timeIntervalSinceNow < YourAccountChain.factsLife else {
                known[key] = nil
                return nil
            }
            return k
        }

        func generation(_ key: String) -> Int { generations[key, default: 0] }

        func set(_ key: String, generation: Int, _ update: @Sendable (inout Known) -> Void) {
            guard generations[key, default: 0] == generation else { return }
            var k = get(key) ?? Known(at: Date())
            update(&k)
            known[key] = k
        }

        /// Everything read again at once: the whole record, stamped now.
        func replace(_ key: String, generation: Int, with k: Known) {
            guard generations[key, default: 0] == generation else { return }
            known[key] = k
        }

        func forget(_ key: String) {
            known[key] = nil
            generations[key, default: 0] += 1
            for id in reading.keys where id.hasPrefix(key + "#") { reading[id] = nil }
        }

        func joined<T: Sendable>(_ id: String, _ read: @escaping @Sendable () async throws -> T) async throws -> T {
            let task: Task<any Sendable, Error>
            if let running = reading[id] {
                task = running
            } else {
                task = Task { try await read() }
                reading[id] = task
            }
            defer { if reading[id] == task { reading[id] = nil } }
            guard let value = try await task.value as? T else { throw CancellationError() }
            return value
        }
    }

    private static func factsKey(_ net: Network, _ account: String) -> String { "\(net.chainId)|\(account.lowercased())" }

    /// Forget what is kept of `account` on `net`: an operation was sent, or a
    /// send failed in a way a stale fact could explain.
    static func forgetFacts(_ net: Network, _ account: String) async {
        await Facts.shared.forget(factsKey(net, account))
    }

    /// One fact: kept, else joined to a read under way, else read and kept.
    private static func known<T: Sendable>(_ net: Network, _ account: String, _ fact: String, fresh: Bool = false,
                                           kept: @Sendable (Facts.Known) -> T?,
                                           keeps: @Sendable (T) -> Bool = { _ in true },
                                           store: @escaping @Sendable (inout Facts.Known, T) -> Void,
                                           read: @escaping @Sendable () async throws -> T) async throws -> T {
        let key = factsKey(net, account)
        if !fresh, let k = await Facts.shared.get(key), let v = kept(k) { return v }
        let generation = await Facts.shared.generation(key)
        let v = try await Facts.shared.joined(key + "#" + fact, read)
        if !fresh, keeps(v) { await Facts.shared.set(key, generation: generation) { store(&$0, v) } }
        return v
    }

    static func knownDeployed(_ net: Network, _ account: String, fresh: Bool = false) async throws -> Bool {
        // Only "on it" is kept: a node a block behind a first send would
        // otherwise keep the account off the network for minutes.
        try await known(net, account, "deployed", fresh: fresh, kept: \.deployed, keeps: { $0 },
                        store: { $0.deployed = $1 }) { try await isDeployed(net, account) }
    }

    static func knownEntry(_ net: Network, _ account: String, fresh: Bool = false) async throws -> YourAccountOp.Entry {
        try await known(net, account, "entry", fresh: fresh, kept: \.entry,
                        store: { $0.entry = $1 }) { try await accountEntry(net, account) }
    }

    static func knownThreshold(_ net: Network, _ account: String, fresh: Bool = false) async throws -> Int {
        try await known(net, account, "threshold", fresh: fresh, kept: \.threshold,
                        store: { $0.threshold = $1 }) { try await threshold(net, account) }
    }

    static func knownHasSessions(_ net: Network, _ account: String, fresh: Bool = false) async throws -> Bool {
        try await known(net, account, "sessions", fresh: fresh, kept: \.hasSessions,
                        store: { $0.hasSessions = $1 }) { try await !sessionIds(net, account).isEmpty }
    }

    static func knownSigners(_ net: Network, _ account: String, fresh: Bool = false) async throws -> [String] {
        try await known(net, account, "signers", fresh: fresh, kept: \.signers,
                        store: { $0.signers = $1 }) { try await signers(net, account) }
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

    /// **KEPT FRESH WHILE MOVE IS OPEN (prd §1610: a send six minutes after
    /// the last found every fact expired and read them all on the tap).**
    /// Every fact read again at once and the record replaced whole, stamped
    /// now, so what is kept never outlives `factsLife` and never lapses
    /// while somebody is about to send. A failed read keeps the old record
    /// until it expires on its own.
    static func refreshFacts(_ account: String, on net: Network) async {
        let key = factsKey(net, account)
        let generation = await Facts.shared.generation(key)
        guard (try? await knownDeployed(net, account, fresh: true)) == true else { return }
        async let entry = knownEntry(net, account, fresh: true)
        async let threshold = knownThreshold(net, account, fresh: true)
        async let sessions: Bool? = plan(net) == nil ? nil : try await knownHasSessions(net, account, fresh: true)
        let t: Int, e: YourAccountOp.Entry, h: Bool?
        do { (t, e, h) = try await (threshold, entry, sessions) } catch { return }
        var record = Facts.Known(deployed: true, entry: e, threshold: t, hasSessions: h, at: Date())
        if t >= 2 || plan(net) != nil {
            guard let s = try? await knownSigners(net, account, fresh: true) else { return }
            record.signers = s
        }
        await Facts.shared.replace(key, generation: generation, with: record)
    }
}
