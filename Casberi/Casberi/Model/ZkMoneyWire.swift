import Foundation

/// zk.money's PUBLIC edges, pure (2026-10-11). Foundation only (plus
/// `Keccak256`, also pure), so `scripts/zkmoney-selftest.sh` compiles it WHOLE
/// against replies measured off Ethereum mainnet.
///
/// **What zk.money is.** Aztec Labs' private payments wallet on Aztec mainnet
/// (relaunched September 2026): a passkey account, a public tag
/// (`bob.zk.money`), DAI/USDC/USDT in from Ethereum, DAI out, every move
/// under $2,500. Inside it everything is private. Its edges on Ethereum are
/// public by design, and those are all this reads:
///
/// - **A withdrawal** is DAI sent straight from a PORTAL contract to the
///   person's address (measured: `portal → recipient`, one Transfer).
/// - **A deposit** is a transfer to a single-use DEPOSIT ADDRESS, which a
///   relayer sweeps into the portal within a few blocks (measured: 459.58 DAI
///   in, then 459.33 to the portal and 0.25 to the relayer's executor). Once
///   swept, the deposit address is an EIP-1167 minimal proxy whose code names
///   zk.money's deposit implementation — one `eth_getCode` says so.
/// - **A tag** is public on purpose: the NameRegistry maps
///   `namehash("<tag>.zk.money")` to the account's Ethereum address, and the
///   AccountMetadataRegistry maps that account to its Aztec address. ENS
///   resolution of a tag (an offchain gateway) hands out a FRESH deposit
///   address on every lookup (measured, ~6 s each) — the payment path, which
///   this never takes.
/// - **Links** are `ZkMoneyLink` (Shared, so the share extension reads
///   them too).
enum ZkMoneyWire {

    // MARK: - Deployments (Ethereum mainnet)

    /// Every production deployment's contracts, from zk.money's public
    /// manifest (`d1ylrbyes5g693.cloudfront.net/prod.v4.json`, schema 4, read
    /// 2026-10-11): v2, v3, v4, v6 and v6-sky. Old portals keep funds people
    /// have not moved, so every one still names a withdrawal. A NEW deployment
    /// is a line here — the manifest is not fetched at runtime.
    struct Deployment: Equatable {
        let label: String
        let portal: String
        let depositImplementation: String
        let operationExecutor: String
    }

    static let deployments: [Deployment] = [
        .init(label: "v2", portal: "0x6534905c84f13af94d649706e4ec711770d3603c",
              depositImplementation: "0x6d29312301dfec9516be400739d776f1136703fd",
              operationExecutor: "0xa4dbc928012eb799fdb52829d948cd3aa002915d"),
        .init(label: "v3", portal: "0xd52f6a3c47bcbe6133471804c3bb14363de53139",
              depositImplementation: "0x509d09fae1d52e1207a58ea3ceeb5a66be39d1a0",
              operationExecutor: "0x835d6857be0cb3841690e61cad0e6838081e874a"),
        .init(label: "v4", portal: "0xeaba74e7e403617164a413ae3963c4961f92dbf2",
              depositImplementation: "0x12c3ee077640a4cc22505bb2ba08146c6f947599",
              operationExecutor: "0x835d6857be0cb3841690e61cad0e6838081e874a"),
        .init(label: "v6", portal: "0xdf410ad448a0f7165181fbdb32f8896f4a0d9449",
              depositImplementation: "0xf714d8cf287f4a410b018514074a9371bc45461b",
              operationExecutor: "0xe883686d9ec4e0430f2233a6bf12b2d226a39e19"),
        .init(label: "v6-sky", portal: "0xd7ae00b91ba0b8e0240b22cd75fe447d177c260f",
              depositImplementation: "0xf714d8cf287f4a410b018514074a9371bc45461b",
              operationExecutor: "0xe883686d9ec4e0430f2233a6bf12b2d226a39e19"),
    ]

    /// The portal deposits go to now (the docs' "current deployment").
    static let currentPortal = "0xdf410ad448a0f7165181fbdb32f8896f4a0d9449"
    static let dai = "0x6b175474e89094c44da98b954eedeac495271d0f"
    static let nameRegistry = "0xa9863b8f573d62377d987ccb9af6e0000f99d14a"
    static let metadataRegistry = "0xda79bae4485c40291363d885aae5b543d2d0efa9"
    /// Aztec mainnet's rollup versions, Alpha V5 and V6 (the rollup
    /// governance proposal 5 adds, prd §1446): a record on another is a
    /// stale one.
    static let rollupVersions: Set<Int> = [4_248_422_647, 2_070_860_440]

    static func isPortal(_ address: String) -> Bool {
        deployments.contains { $0.portal == address.lowercased() }
    }

    static func isOperator(_ address: String) -> Bool {
        deployments.contains { $0.operationExecutor == address.lowercased() }
    }

    /// The contracts that PAY a DAI withdrawal now (2026-10-17, prd §1384): the
    /// manifest's `plainWithdrawalExecutor` for v6 and v6-sky. MEASURED over
    /// 14 days: the v6 portal paid DAI to its executor 186 times and to people
    /// 9 times; the executor then paid 175 addresses. So "DAI from a portal",
    /// §1273's whole rule, named almost no withdrawal after September.
    static let withdrawalExecutors: Set<String> = ["0xc2363b7155ee8391c5395b72c46a6d22bf49151c",   // v6
                                                   "0x63e6cd9ff886cff198eaaab01cec2b707e7f5475"]   // v6-sky

    static func paysWithdrawals(_ address: String) -> Bool {
        let a = address.lowercased()
        return isPortal(a) || withdrawalExecutors.contains(a)
    }

    // MARK: - Deposit addresses

    /// An EIP-1167 minimal proxy's runtime code names its implementation
    /// right after this prefix. A swept zk.money deposit address delegates to
    /// one of the deployments' deposit implementations (measured: 173 bytes,
    /// `363d3d373d3d3d363d73` + `f714…461b` on v6).
    private static let proxyPrefix = "363d3d373d3d3d363d73"

    /// What a zk.money single-use contract is for, read off the
    /// implementation its proxy code names (2026-10-17, prd §1384). Every one is an
    /// EIP-1167 proxy, some with immutable arguments appended (205 and 269
    /// bytes, measured), so the implementation sits right after the prefix:
    /// - a DEPOSIT address, or a SAVINGS escrow (v6-sky: DAI sent to it is
    ///   converted to sUSDS and deposited into the savings portal), is where
    ///   the person's money goes IN;
    /// - a SWAP escrow is where a withdrawal comes OUT as USDC or USDT: it
    ///   swaps the person's DAI on Curve and pays them (12 of 12 sampled).
    enum Role: Equatable { case deposit, swapOut }

    static let savingsEscrowImplementations: Set<String> = ["0x5c412ba5b338f3e5e2a1332069bdd3aae6ae6b8a"]
    static let swapEscrowImplementations: Set<String> = ["0xf16fd140036925e3a0630d0f743204a4c7d8ccaf",   // v6
                                                         "0xcfaf1dfc22ce92cf3f2b534b3b5c1f116028fb95"]   // v6, second factory

    static func role(code: String?) -> Role? {
        guard let code else { return nil }
        let body = (code.hasPrefix("0x") ? String(code.dropFirst(2)) : code).lowercased()
        guard body.hasPrefix(proxyPrefix), body.count >= proxyPrefix.count + 40 else { return nil }
        let start = body.index(body.startIndex, offsetBy: proxyPrefix.count)
        let implementation = "0x" + body[start..<body.index(start, offsetBy: 40)]
        if deployments.contains(where: { $0.depositImplementation == implementation })
            || savingsEscrowImplementations.contains(implementation) { return .deposit }
        if swapEscrowImplementations.contains(implementation) { return .swapOut }
        return nil
    }

    static func isDepositAddress(code: String?) -> Bool { role(code: code) == .deposit }

    // MARK: - Tags

    /// A tag as typed — `bob`, `@bob`, `bob.zk.money`, `Bob.zk.money`, the
    /// wallet's link — folded to the bare, lowercased form the registry
    /// hashes. nil for anything that is not a tag (a bare word with no
    /// `.zk.money` is only a tag where the caller already knows it is one).
    static func tag(_ raw: String, bareAllowed: Bool = false) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`“”‘’<>()[].,;"))
            .lowercased()
        if text.hasPrefix("@") { text.removeFirst() }
        let suffix = ".zk.money"
        if text.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count))
        } else if !bareAllowed {
            return nil
        }
        let allowed = CharacterSet.lowercaseLetters.union(.decimalDigits).union(CharacterSet(charactersIn: "-_"))
        guard !text.isEmpty, text.count <= 64, text.unicodeScalars.allSatisfy(allowed.contains),
              text.unicodeScalars.allSatisfy(\.isASCII) else { return nil }
        return text
    }

    static func display(_ tag: String) -> String { ZkMoneyLink.display(tag) }

    /// ENS namehash of `<tag>.zk.money` (raw, as zk.money hashes it).
    static func nameHash(_ tag: String) -> String {
        var node = [UInt8](repeating: 0, count: 32)
        for label in display(tag).split(separator: ".").reversed() {
            node = Keccak256.hash(node + Keccak256.hash(Array(label.utf8)))
        }
        return "0x" + Keccak256.hexString(node)
    }

    /// Selectors, measured with viem off the contracts' Sourcify ABIs.
    enum Selector {
        static let ownerOf = "7dd56411"         // NameRegistry.ownerOf(bytes32)
        static let getUserRecord = "67e2efc6"   // AccountMetadataRegistry.getUserRecord(address)
        static let balanceOf = "70a08231"       // ERC-20
    }

    static func ethCall(to: String, selector: String, arg: String, id: Int) -> [String: Any] {
        let hex = arg.lowercased().hasPrefix("0x") ? String(arg.dropFirst(2)) : arg
        let word = String(repeating: "0", count: max(0, 64 - hex.count)) + hex.lowercased()
        return ["jsonrpc": "2.0", "id": id, "method": "eth_call",
                "params": [["to": to, "data": "0x" + selector + word], "latest"]]
    }

    /// The account `ownerOf` answered, or nil for an unclaimed tag (zero).
    static func account(_ result: String?) -> String? {
        guard let result else { return nil }
        let body = result.hasPrefix("0x") ? String(result.dropFirst(2)) : result
        guard body.count >= 64 else { return nil }
        let address = String(body.prefix(64).suffix(40)).lowercased()
        return address.allSatisfy { $0 == "0" } ? nil : "0x" + address
    }

    /// What a tag resolves to, publicly: its Ethereum account and its Aztec
    /// address (`getUserRecord`'s first word), with the rollup it was made on.
    struct Record: Codable, Equatable {
        let tag: String
        let account: String
        let aztec: String?
        let rollupVersion: Int?
        var onMainnet: Bool { rollupVersion.map(ZkMoneyWire.rollupVersions.contains) ?? false }
    }

    static func record(tag: String, account: String, userRecord: String?) -> Record {
        guard let userRecord else { return Record(tag: tag, account: account, aztec: nil, rollupVersion: nil) }
        let body = userRecord.hasPrefix("0x") ? String(userRecord.dropFirst(2)) : userRecord
        guard body.count >= 128 else { return Record(tag: tag, account: account, aztec: nil, rollupVersion: nil) }
        let l2 = String(body.prefix(64))
        let version = Int(body.dropFirst(64).prefix(64), radix: 16)
        return Record(tag: tag, account: account,
                      aztec: l2.allSatisfy { $0 == "0" } ? nil : "0x" + l2, rollupVersion: version)
    }

    // MARK: - Moves on Ethereum

    /// What a watched wallet's transfer means, if it is zk.money's: DAI in
    /// from a portal or a withdrawal executor is a withdrawal, and so is
    /// anything in from a swap escrow (USDC, USDT); a transfer out to a
    /// deposit address or a savings escrow is a deposit. The caller has the
    /// counterparty's code.
    enum Move: Equatable {
        case withdrawal, deposit
    }

    static func move(token: String?, from: String, to: String, watched: String,
                     counterpartyCode: String?) -> Move? {
        let me = watched.lowercased()
        if to.lowercased() == me, paysWithdrawals(from), token?.lowercased() == dai { return .withdrawal }
        if to.lowercased() == me, role(code: counterpartyCode) == .swapOut { return .withdrawal }
        if from.lowercased() == me, role(code: counterpartyCode) == .deposit { return .deposit }
        return nil
    }

    static func title(_ move: Move, amount: String, symbol: String) -> String {
        switch move {
        case .withdrawal: return "Withdrew \(amount) \(symbol) from zk.money"
        case .deposit:    return "Deposited \(amount) \(symbol) to zk.money"
        }
    }

    /// The DAI an ERC-20 `balanceOf` answered, in whole units.
    static func dai(_ result: String?) -> Decimal? {
        guard let result else { return nil }
        let body = result.hasPrefix("0x") ? String(result.dropFirst(2)) : result
        guard body.count == 64 else { return nil }
        var value = Decimal(0)
        for c in body { guard let d = Int(String(c), radix: 16) else { return nil }; value = value * 16 + Decimal(d) }
        return value / pow(10, 18)
    }
}
