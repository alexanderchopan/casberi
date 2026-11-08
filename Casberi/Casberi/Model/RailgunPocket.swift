import Foundation

/// **YOUR RAILGUN POCKET (prd §1713).** The private balance for any token
/// on Ethereum other than ETH and USDC: a Railgun wallet that belongs to your
/// account (the Safe on this phone), opened in `RailgunEngine`.
///
/// **One root, as the rest of private money (prd §1562).** The wallet's
/// phrase is made from 32 bytes of your private root (`.railgunWallet`) and
/// the SDK's encryption key from another 32 (`.railgunDatabase`), so a new
/// phone with the root in iCloud Keychain gets the same wallet back. They are
/// read without Face ID, as the pool seed is, so the balance reads in the
/// background (user, 2026-11-07: "view freely"); what spends asks for you
/// first (`PrivateRootKey.unlock`), then your account's Face ID.
///
/// **Your account sends both doors.** In: the token's approval to Railgun's
/// proxy and the shield, ONE operation (`YourAccountChain.privateCalls`:
/// simulated against Ethereum's real state, then Face ID; a call that would
/// fail signs nothing). Out: the proxy call carrying the unshield proof, as a
/// plain call from your account, never the EIP-7702 form Railgun's SDK
/// writes for a plain wallet (`forSafe`). Your account pays both doors' gas,
/// as every move of yours does.
///
/// Nothing here draws: Move and Holdings read it (built next); a DEBUG build
/// drives it with `-railgunPocket`.
@MainActor
enum RailgunPocket {

    static var accountNetwork: YourAccountOp.Network { YourAccountOp.ethereum }

    /// Railgun's proxy on Ethereum: the shield's and the unshield's one door.
    static let proxy = "0xfa7093cdd9ee6932b4eb2c9e1cde7ce00b1fa4b9"

    /// The checkpoint's first block (tree 4): a wallet whose creation is not
    /// known scans from here, so nothing sent to it is ever missed.
    static let checkpointBlock = 25_849_756

    enum Failure: Error, Equatable {
        case noAccount, noRoot, curve
        /// A sync the roots did not confirm: nothing is spent from it.
        case untrusted
        /// A prepared call that is not your account's plain call to Railgun.
        case notRailgun
        case nothingSpendable
        case notWritten
    }

    // MARK: - Opening

    private static func walletKey(_ root: String) -> String { "railgun.wallet." + root }

    /// Opens your wallet in the engine, made from root `id`. `reason` asks
    /// for the device owner first (what spends); nil only reads.
    @discardableResult
    static func open(reason: String?) async throws -> RailgunEngineWire.Opened {
        guard YourAccountKey.address != nil else { throw Failure.noAccount }
        let id = try PrivateRootKey.ensure()
        if let reason { try await PrivateRootKey.unlock(reason: reason) }
        guard var root = PrivateRootKey.root(id) else { throw Failure.noRoot }
        defer { for i in root.indices { root[i] = 0 } }
        guard var entropy = PrivateRoot.derive(root, .railgunWallet),
              var key = PrivateRoot.derive(root, .railgunDatabase) else { throw Failure.curve }
        defer { for i in entropy.indices { entropy[i] = 0 }; for i in key.indices { key[i] = 0 } }
        let engine = RailgunEngine.shared
        if engine.isOpen { return try await engine.open(entropy: hex(entropy, prefix: true), encryptionKey: hex(key),
                                                         walletID: UserDefaults.standard.string(forKey: walletKey(id))) }
        let opened = try await engine.open(entropy: hex(entropy, prefix: true), encryptionKey: hex(key),
                                           walletID: UserDefaults.standard.string(forKey: walletKey(id)),
                                           creationBlock: checkpointBlock)
        UserDefaults.standard.set(opened.walletID, forKey: walletKey(id))
        return opened
    }

    private static func hex(_ bytes: [UInt8], prefix: Bool = false) -> String {
        (prefix ? "0x" : "") + bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Reads the pool and your wallet, every root checked. Throws `untrusted`
    /// when a root does not match: the balance it read is not shown as yours.
    static func sync() async throws -> RailgunEngineWire.Synced {
        let synced = try await RailgunEngine.shared.sync()
        guard RailgunEngineWire.trusted(synced) else { throw Failure.untrusted }
        return synced
    }

    // MARK: - In

    /// Moves `amount` (base units, decimal) of `token` from your account into
    /// your Railgun wallet: approve and shield, one Face ID operation.
    /// Returns the transaction's hash, or nil while it is not yet seen.
    static func shield(token: String, amount: String,
                       stage: @escaping @Sendable (YourAccountChain.Stage) async -> Void) async throws -> String? {
        guard let hexAmount = PrivateMoney.hex(amount) else { throw Failure.notWritten }
        try await open(reason: nil)
        let prepared = try await RailgunEngine.shared.prepareShield(token: token, amount: hexAmount)
        guard prepared.tx.to.lowercased() == proxy, let approve = prepared.approve,
              approve.to.lowercased() == token.lowercased(),
              approve.data.lowercased() == approveCall(amount: hexAmount) else { throw Failure.notRailgun }
        let calls = [(to: approve.to, data: approve.data, value: "0"),
                     (to: prepared.tx.to, data: prepared.tx.data, value: PrivateMoney.decimal(hex: prepared.tx.value))]
        let sent = try await YourAccountChain.privateCalls(calls, on: accountNetwork,
                                                           reason: String(localized: "Move to private"), stage: stage)
        let hash = landed(sent)
        NSLog("railgunPocket| shielded | %@ | %@ of %@", hash ?? "not yet seen", amount, token)
        return hash
    }

    /// `approve(proxy, amount)`, exactly: the only approval a shield may ask.
    static func approveCall(amount hexAmount: String) -> String {
        let digits = hexAmount.lowercased().hasPrefix("0x") ? String(hexAmount.dropFirst(2)) : hexAmount
        let padded = String(repeating: "0", count: max(0, 64 - digits.count)) + digits.lowercased()
        return "0x095ea7b3" + String(repeating: "0", count: 24) + String(proxy.dropFirst(2)) + padded
    }

    // MARK: - Out

    /// Sends `amount` (base units, decimal) of `token` from your Railgun
    /// wallet to `to`: the proof made on this phone, the proxy call sent by
    /// your account. Asks for the device owner first, then Face ID.
    static func send(token: String, amount: String, to: String,
                     stage: @escaping @Sendable (YourAccountChain.Stage) async -> Void) async throws -> String? {
        guard PrivateMoney.isAddress(to), let hexAmount = PrivateMoney.hex(amount) else { throw Failure.notWritten }
        try await open(reason: String(localized: "Send from your private balance"))
        let synced = try await sync()
        guard let held = synced.balances.first(where: { $0.token.lowercased() == token.lowercased() }),
              let spendable = Decimal(string: PrivateMoney.decimal(hex: held.spendable)),
              let wanted = Decimal(string: amount), wanted <= spendable, wanted > 0 else { throw Failure.nothingSpendable }
        let u = try await RailgunEngine.shared.prepareUnshield(token: token, amount: hexAmount, to: to, forSafe: true)
        guard u.tx.to.lowercased() == proxy, u.type != 4, u.delegate == nil, u.to.lowercased() == to.lowercased() else {
            throw Failure.notRailgun
        }
        let sent = try await YourAccountChain.privateCalls([(to: u.tx.to, data: u.tx.data, value: PrivateMoney.decimal(hex: u.tx.value))],
                                                           on: accountNetwork,
                                                           reason: String(localized: "Send from your private balance"), stage: stage)
        let hash = landed(sent)
        NSLog("railgunPocket| unshielded | %@ | %@ of %@ to %@ | proof %d ms", hash ?? "not yet seen", amount, token, YourAccount.short(to), u.proofMs)
        return hash
    }

    private static func landed(_ sent: YourAccountChain.Sent) -> String? {
        switch sent.outcome {
        case .landed(let tx, _): tx
        case .pending, .dryRun: nil
        }
    }
}
