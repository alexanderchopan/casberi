import Foundation

/// **WHERE THIS PHONE CAN USE THE ACCOUNT (prd §1442k).** The account's
/// address comes from its first key, and only that key can sign the
/// operation that first brings the account into existence on a network. So:
///
/// - The phone that made the account (`YourAccountKey.holdsOrigin`) can open
///   it on any network; every one is usable.
/// - A phone the account was recovered to can use only the networks where it
///   already exists. Money sent to it anywhere else waits on the first phone,
///   and is gone if that phone is (measured 2026-10-20: a recovered simulator
///   was refused on Robinhood Chain, "only the iPhone that made it can put it
///   there", with $1 sitting at the address).
/// - Before recovering, the recovery key can move the account only where it
///   is one of the account's keys.
///
/// Receive, the network list and the account screens say only these, so the
/// app never tells anyone to receive where the account cannot follow.
enum YourAccountReach {
    typealias Op = YourAccountOp

    private static var live: [Op.Network] { Op.networks.filter { !$0.isTest } }

    /// The networks this phone can use the account on.
    @MainActor
    static func usable(_ account: String) async -> [Op.Network] {
        // The demo's account is on every network, read off no node (§1475).
        if YourAccountDemo.isDemo(account) { return live }
        if YourAccountKey.holdsOrigin { return live }
        return await everyNetwork { (try? await YourAccountChain.isDeployed($0, account)) == true }
    }

    /// The networks `holds` is true of, asked at once (prd §1601), in order.
    private static func everyNetwork(_ holds: @escaping @Sendable (Op.Network) async -> Bool) async -> [Op.Network] {
        let nets = live
        let yes = await withTaskGroup(of: (Int, Bool).self) { group in
            for (i, net) in nets.enumerated() { group.addTask { (i, await holds(net)) } }
            var out: Set<Int> = []
            for await (i, ok) in group where ok { out.insert(i) }
            return out
        }
        return nets.indices.filter(yes.contains).map { nets[$0] }
    }

    /// The networks the recovery key can bring the account to this phone on.
    @MainActor
    static func recoverable(_ account: String) async -> [Op.Network] {
        guard let key = YourAccountRecovery.publicKey(for: account),
              let signer = try? await YourAccountChain.recoverySigner(x: key.x, y: key.y) else { return [] }
        return await everyNetwork { (try? await YourAccountChain.recoveryState($0, account, signer: signer)) == .added }
    }

    /// Whether this is every network the account is on.
    static func isAll(_ networks: [Op.Network]) -> Bool { networks.count >= live.count }

    /// "Base, Ethereum and Robinhood Chain."
    static func words(_ networks: [Op.Network]) -> String {
        networks.map(\.name).formatted(.list(type: .and)) + "."
    }
}
