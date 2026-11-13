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
///   address on every lookup (measured, ~6 s each) — the payment path, taken
///   only when Move's Send pays a tag (prd §1692, "Paying a tag" below).
/// - **Links** are `ZkMoneyLink` (Shared, so the share extension reads
///   them too).
enum ZkMoneyWire {

    // MARK: - Deployments (Ethereum mainnet)

    /// Every production deployment's contracts. v2…v6-sky are on Aztec Alpha
    /// V5, from the manifest `d1ylrbyes5g693.cloudfront.net/prod.v4.json`
    /// (schema 4, read 2026-10-11; frozen at V5 since). The two "aztec-v6"
    /// lines are zk.money's move to Aztec V6 (live 2026-11-03 12:24 UTC),
    /// from the profile `cdn.zk.money/profiles/v6/current.json` and the
    /// manifest it names, `v6-prod.oxide.zk.money/v6/v6-prod/releases.json`
    /// (schema 5, `dep-v6`). zk.money's own "v6" label predates Aztec V6 and
    /// is not it. Old portals keep funds people have not moved, so every one
    /// still names a withdrawal. A NEW deployment is a line here — neither
    /// manifest is fetched at runtime.
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
        // Aztec V6 (`dep-v6`): a deposit address is a SIPA clone of
        // `depositSIPAImplementation` (measured 2026-11-03: 205 bytes, 3 of
        // 5 sweeps into the DAI portal; the other 2 are registration clones,
        // `registrationImplementations`).
        .init(label: "aztec-v6", portal: "0xcb99c58fe81ae6b2cb4835e46f7b703745879042",
              depositImplementation: "0xbfe3de3c4466cbc5803a756847208c69b3bae401",
              operationExecutor: "0x5ece3b4ebe7137b1b6f92406de17d9816d585c1c"),
        .init(label: "aztec-v6-susds", portal: "0x2ebfee284babf94869fac44bc85edb3c34e536d8",
              depositImplementation: "0xbfe3de3c4466cbc5803a756847208c69b3bae401",
              operationExecutor: "0x5ece3b4ebe7137b1b6f92406de17d9816d585c1c"),
    ]

    /// Aztec V6's first deposit, the one that claims a tag, goes through a
    /// REGISTRATION clone (`registrationSIPAImplementation`, measured
    /// 2026-11-03): money in, so a deposit.
    static let registrationImplementations: Set<String> = ["0x96a52ed47af73423d4b8a920913e5c1cefdc1319"]

    /// The portal deposits go to now: Aztec V6's DAI portal (2026-11-03).
    static let currentPortal = "0xcb99c58fe81ae6b2cb4835e46f7b703745879042"
    /// Aztec V6's rollup version, the one a tag's record must carry before
    /// Casberi pays it (a V5 record's money would land on the rollup Aztec
    /// left).
    static let currentRollupVersion = 2_070_860_440
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
    /// On Aztec V6 the DAI portal pays its `plainWithdrawalExecutor` and it
    /// pays the person (measured 2026-11-03: portal → `0x7c8c…` → person,
    /// 0.1 DAI to the FPC funder, a tip to the operation executor); the
    /// sUSDS portal's executor and the savings `skyWithdrawalExecutor` are
    /// the manifest's, unmeasured, and name only DAI.
    static let withdrawalExecutors: Set<String> = ["0xc2363b7155ee8391c5395b72c46a6d22bf49151c",   // v6
                                                   "0x63e6cd9ff886cff198eaaab01cec2b707e7f5475",   // v6-sky
                                                   "0x7c8c2147d1bb8b83e0a0501097372de170ee702a",   // aztec-v6 DAI
                                                   "0xd0d8e5c5b128ea7e5f2d461afd6c669bc0877df8",   // aztec-v6 sUSDS
                                                   "0xfe0b2b24cca52d1680103e258985a5aca33742d5"]   // aztec-v6 savings

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

    static let savingsEscrowImplementations: Set<String> = ["0x5c412ba5b338f3e5e2a1332069bdd3aae6ae6b8a",
                                                            "0xb61d97faf96ec8de617aaf54f4764d01cfd25b8b"]   // aztec-v6, manifest
    static let swapEscrowImplementations: Set<String> = ["0xf16fd140036925e3a0630d0f743204a4c7d8ccaf",   // v6
                                                         "0xcfaf1dfc22ce92cf3f2b534b3b5c1f116028fb95",   // v6, second factory
                                                         "0xc953308e66da19881d8ddd240e6369db8ef72ab9"]   // aztec-v6, manifest

    static func role(code: String?) -> Role? {
        guard let code else { return nil }
        let body = (code.hasPrefix("0x") ? String(code.dropFirst(2)) : code).lowercased()
        guard body.hasPrefix(proxyPrefix), body.count >= proxyPrefix.count + 40 else { return nil }
        let start = body.index(body.startIndex, offsetBy: proxyPrefix.count)
        let implementation = "0x" + body[start..<body.index(start, offsetBy: 40)]
        if deployments.contains(where: { $0.depositImplementation == implementation })
            || registrationImplementations.contains(implementation)
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

    /// **`@bob` IS `bob.zk.money` (prd §1767).** zk.money's own app spells a
    /// tag with an at sign; Send's To and Contacts' search read it the same
    /// way. Only that spelling: a bare word is a name in your book or
    /// nothing, and `@bob.zk.money` is already a tag. Nil for anything else.
    static func atTag(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("@"), tag(text) == nil, let bare = tag(text, bareAllowed: true) else { return nil }
        return display(bare)
    }

    /// **WHO A DEPOSIT ADDRESS WAS FOR (prd §1767).** A tag is paid at a
    /// one-time address, so the chain never names the person: Activity said
    /// "Deposited into zk.money" for every tag you ever paid. Send knows the
    /// tag when it sends, and keeps the pair here: `[address, tag]`, the
    /// newest first, each address once, `paidCap` at most.
    static let paidCap = 500
    static func paid(_ ledger: [[String]], adding pairs: [(address: String, tag: String)]) -> [[String]] {
        var out: [[String]] = [], seen = Set<String>()
        let fresh = pairs.compactMap { pair -> [String]? in
            guard let bare = tag(pair.tag), pair.address.lowercased().hasPrefix("0x") else { return nil }
            return [pair.address.lowercased(), bare]
        }
        for row in fresh.reversed() + ledger where row.count == 2 && seen.insert(row[0]).inserted {
            out.append(row)
            if out.count == paidCap { break }
        }
        return out
    }
    static func paidTag(_ ledger: [[String]], at address: String) -> String? {
        let a = address.lowercased()
        return ledger.first { $0.count == 2 && $0[0] == a }?[1]
    }

    /// The tags among your saved contacts that a typed `query` finds, by the
    /// name you gave or the tag itself: `(tag, name)`, as Send's To lists them.
    static func savedTags(_ saved: [(id: String, name: String)], query: String) -> [(tag: String, name: String)] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let needle = q.hasPrefix("@") ? String(q.dropFirst()) : q
        return saved.compactMap { entry -> (tag: String, name: String)? in
            guard let bare = tag(entry.id) else { return nil }
            let full = display(bare)
            guard needle.isEmpty || entry.name.lowercased().contains(needle) || full.hasPrefix(needle) else { return nil }
            return (full, entry.name)
        }
    }

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

    // MARK: - Paying a tag (Aztec V6, 2026-11-03)

    /// **PAYING A TAG IS ENS, PROVEN ON CHAIN.** zk.money's ENS resolver
    /// (`sipaResolver`, the one ENS names for `zk.money`, read 2026-11-03)
    /// answers `resolve(<tag>.zk.money, addr)` with EIP-3668's
    /// `OffchainLookup`: its operator's gateway hands back a FRESH deposit
    /// address with a zero-knowledge proof, and `resolveWithProof` checks
    /// the proof on chain against the tag's public record, rebuilds the
    /// address itself and refuses any other (`Resolver__SIPAMismatch`). So
    /// the gateway can be slow or down, never wrong. A proof holds for its
    /// UTC day (± 30 minutes): it is asked for at pay time, never kept.
    ///
    /// The resolver refuses, itself, a tag whose account is on another
    /// rollup than its operator's (`Resolver__RollupVersionMismatch`):
    /// measured on `charlie` and `money`, both still on Alpha V5. That is
    /// the guard against paying into the rollup Aztec left.
    ///
    /// **THE RESOLVER MOVED (prd §1746, measured 2026-11-11).** ENS's
    /// registry now names `0x3dc7…0a6e` for zk.money; the gateway answers
    /// 400 to a lookup from the one pinned on 2026-11-03 (`0xc329…d525`),
    /// so every tag read "zk.money's resolver didn't answer" and nothing
    /// was sent. Same gateway, callback and errors (measured against `zac`,
    /// `charlie`, `money` and an unclaimed tag). The nightly asks ENS
    /// whether this is still the one it names (`live-integrations.sh`).
    static let resolver = "0x3dc71762063d7b87b3f79b3b98e03f0051b00a6e"
    /// The operator's gateway, as `OffchainLookup` names it
    /// (`https://rop-v6.v6-prod.oxide.zk.money/{sender}/{data}.json`,
    /// measured; the manifest's `resolverGatewayUrl`). Any other host is
    /// refused: it is the only one `NetworkReach` discloses.
    static let gatewayHost = "rop-v6.v6-prod.oxide.zk.money"
    static let usdc = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
    static let usdt = "0xdac17f958d2ee523a2206206994597c13d831ec7"
    /// What a deposit address takes: DAI, USDC or USDT on Ethereum (the
    /// docs' Limits; USDC and USDT are swapped to DAI on the way in).
    static let payTokens: Set<String> = [dai, usdc, usdt]
    /// The order a request in dollars picks among them (prd §1749): the one
    /// you hold, USDC first.
    static let payOrder = [usdc, dai, usdt]
    /// A deposit costs $0.35 (the docs, 2026-11-03), so an amount at or
    /// under it is marked recoverable and never arrives; each must stay
    /// below $5,000.
    static let payFeeUSD = 0.35
    static let payCapUSD = 5_000.0

    /// The deposit's own limits, said before the tap; nil when they pass.
    /// `usd` nil (no price yet) checks the token and network only.
    static func payRefusal(chainId: Int, token: String?, usd: Double?) -> String? {
        guard chainId == 1, let token, payTokens.contains(token.lowercased()) else {
            return String(localized: "zk.money takes DAI, USDC or USDT on Ethereum")
        }
        guard let usd else { return nil }
        if usd <= payFeeUSD { return String(localized: "zk.money's $0.35 fee would take all of it") }
        if usd >= payCapUSD { return String(localized: "zk.money takes under $5,000 at a time") }
        return nil
    }

    // MARK: - Paying a request (prd §1745)

    /// What Pay writes into Send for a saved request link: the tag in To,
    /// the token it asks for, and the amount asked PLUS the deposit's fee,
    /// so what was asked is what the fee leaves (user, 2026-11-11: "add
    /// the fee"). The fee is in dollars and the three tokens a deposit
    /// takes are dollars, so it is added for one of them, and for a request
    /// that names no token at all (format 4 asks in dollars: `token` nil,
    /// you pick which of the three pays); a request in any other token, or
    /// with no amount, leaves the amount to you.
    struct RequestPayment: Equatable {
        /// "zac.zk.money": Send's To resolves it to a fresh deposit address.
        let to: String
        /// "20.85": the amount field's text, token units; "" when left to you.
        let amount: String
        /// The amount asked alone ("20.5"), for the line that says the fee was added.
        let asked: String?
        /// The token's contract on Ethereum, lowercased (`Tokens.Held.id`).
        let token: String?
    }

    static func requestPayment(tag: String, amount: Decimal?, symbol: String?) -> RequestPayment {
        let token: String? = switch symbol?.uppercased() {
        case "DAI": dai
        case "USDC": usdc
        case "USDT": usdt
        default: nil
        }
        guard let amount, amount > 0, symbol == nil || token != nil, let fee = Decimal(string: "\(payFeeUSD)") else {
            return RequestPayment(to: "\(tag).zk.money", amount: "", asked: nil, token: token)
        }
        return RequestPayment(to: "\(tag).zk.money", amount: plainAmount(amount + fee), asked: plainAmount(amount), token: token)
    }

    /// **A FEE BIGGER THAN THE AMOUNT SAYS SO (prd §1752).** `total` is what
    /// Send holds for a request, the amount asked plus the fee: when the fee
    /// is the larger part, the line says how many times over ("35 times"
    /// for a cent), or "more than" under twice. nil when the amount is the
    /// larger, or `total` is not the fee and something.
    static func feeWarning(total: String) -> String? {
        guard let total = Double(total) else { return nil }
        let asked = total - payFeeUSD
        guard asked > 0.000_000_5, payFeeUSD > asked else { return nil }
        let times = Int((payFeeUSD / asked).rounded())
        return times >= 2 ? String(localized: "The fee is \(times) times the amount")
                          : String(localized: "The fee is more than the amount")
    }

    /// A request can be paid until its expiry; one with none stays open.
    static func requestOpen(expires: Date?, now: Date) -> Bool {
        expires.map { $0 > now } ?? true
    }

    /// An amount as the amount field takes it: plain digits and a point, up
    /// to six places, no grouping ("20.85", never "20,85" or "2.085e1").
    static func plainAmount(_ value: Decimal) -> String {
        var v = value, rounded = Decimal()
        NSDecimalRound(&rounded, &v, 6, .plain)
        return NSDecimalNumber(decimal: rounded).description(withLocale: Locale(identifier: "en_US_POSIX"))
    }

    enum Selector3668 {
        static let resolve = "9061b923"           // resolve(bytes,bytes)
        static let addr = "3b3b57de"              // addr(bytes32)
        static let offchainLookup = "556f1830"    // OffchainLookup(address,string[],bytes,bytes4,bytes)
        static let resolveWithProof = "f4d4d2f8"  // resolveWithProof(bytes,bytes)
        static let rollupMismatch = "9adb585e"    // Resolver__RollupVersionMismatch(uint256,uint256)
        static let userNotFound = "9a66e130"      // Resolver__UserNotFound()
    }

    /// `<tag>.zk.money` in DNS wire form; nil for a label DNS cannot carry.
    static func dnsName(_ tag: String) -> [UInt8]? {
        var out: [UInt8] = []
        for label in display(tag).split(separator: ".") {
            let bytes = Array(label.utf8)
            guard !bytes.isEmpty, bytes.count <= 63 else { return nil }
            out.append(UInt8(bytes.count))
            out += bytes
        }
        return out + [0]
    }

    /// `resolve(dnsName, addr(namehash))`, the call that answers with the
    /// gateway's lookup.
    static func resolveCall(tag: String) -> String? {
        guard let name = dnsName(tag), let node = hexBytes(nameHash(tag)) else { return nil }
        let inner = hexBytes(Selector3668.addr)! + node
        return "0x" + Selector3668.resolve + Keccak256.hexString(abiBytes([name, inner]))
    }

    /// What `resolve` answered, as a revert.
    enum Lookup: Equatable {
        case offchain(Offchain)
        /// The tag's account is still on another rollup (Alpha V5).
        case notOnV6
        case unclaimed
        case unreadable
    }

    struct Offchain: Equatable {
        let sender: String
        let url: String
        let callData: [UInt8]
        let callback: [UInt8]
        let extraData: [UInt8]
    }

    /// **THE RESOLVER IS THE ONE ENS NAMES, ASKED AT PAY TIME (prd §1750;
    /// zk.money, 2026-11-11: "yes ENS will be accurate").** A pin went
    /// stale in eight days (§1746) and every tag stopped paying. ENS's
    /// registry is asked for zk.money's resolver before each lookup, and the
    /// lookup must come from that contract; the pin above stands in only
    /// when the registry cannot be reached. The gateway's host stays pinned,
    /// and `resolveWithProof` still rebuilds the address on chain.
    static let ensRegistry = "0x00000000000c2e074ec69a0dfb2997ba6c7d2e1e"
    /// `resolver(bytes32)` of namehash("zk.money") (viem's, 2026-11-11).
    static let ensResolverCall = "0x0178b8bf" + "f605999a299a7229da9f2a3c65acf5cb829ae965cfe467f053e1b97c50b0eec2"

    /// The address in the registry's answer, lowercased; nil for none set
    /// (a zero word) and for anything that is not one word holding an address.
    static func namedResolver(result: String?) -> String? {
        guard let result, let b = hexBytes(result), b.count == 32, b[..<12].allSatisfy({ $0 == 0 }),
              b[12...].contains(where: { $0 != 0 }) else { return nil }
        return "0x" + Keccak256.hexString(Array(b[12...]))
    }

    /// `expected`: the resolver the lookup must come from; any other
    /// contract's is refused.
    static func lookup(revert: String?, from expected: String = resolver) -> Lookup {
        guard let revert, let b = hexBytes(revert), b.count >= 4 else { return .unreadable }
        let selector = Keccak256.hexString(Array(b[0..<4]))
        if selector == Selector3668.rollupMismatch { return .notOnV6 }
        if selector == Selector3668.userNotFound { return .unclaimed }
        guard selector == Selector3668.offchainLookup else { return .unreadable }
        let body = Array(b[4...])
        guard let sender = word(body, 0).map({ "0x" + Keccak256.hexString(Array($0[12...])) }),
              sender == expected.lowercased(),
              let urlsAt = offset(body, 1), let callAt = offset(body, 2),
              let cb = word(body, 3), let extraAt = offset(body, 4),
              let callData = dynamicBytes(body, at: callAt), let extraData = dynamicBytes(body, at: extraAt),
              let count = word(body, at: urlsAt).flatMap(small), count >= 1,
              let firstAt = word(body, at: urlsAt + 32).flatMap(small),
              let urlBytes = dynamicBytes(body, at: urlsAt + 32 + firstAt),
              let url = String(bytes: urlBytes, encoding: .utf8) else { return .unreadable }
        return .offchain(Offchain(sender: sender, url: url, callData: callData,
                                  callback: Array(cb[0..<4]), extraData: extraData))
    }

    /// EIP-3668's GET: `{sender}` and `{data}` filled in, https on the one
    /// disclosed host only.
    static func gatewayURL(_ o: Offchain) -> URL? {
        guard o.url.contains("{data}") else { return nil }
        let filled = o.url.replacingOccurrences(of: "{sender}", with: o.sender)
            .replacingOccurrences(of: "{data}", with: "0x" + Keccak256.hexString(o.callData))
        guard let url = URL(string: filled), url.scheme == "https", url.host == gatewayHost else { return nil }
        return url
    }

    /// The gateway's `data`, the bytes `resolveWithProof` checks.
    static func gatewayData(_ json: Any?) -> [UInt8]? {
        guard let text = (json as? [String: Any])?["data"] as? String,
              let bytes = hexBytes(text), !bytes.isEmpty else { return nil }
        return bytes
    }

    /// The callback the lookup named, with the gateway's answer.
    static func callbackCall(_ o: Offchain, response: [UInt8]) -> String {
        "0x" + Keccak256.hexString(o.callback + abiBytes([response, o.extraData]))
    }

    /// The deposit address `resolveWithProof` returned (`bytes` holding
    /// `abi.encode(address)`); nil for anything else or zero.
    static func depositAddress(callbackResult: String?) -> String? {
        guard let callbackResult, let b = hexBytes(callbackResult),
              let at = offset(b, 0), let inner = dynamicBytes(b, at: at), inner.count == 32,
              inner[0..<12].allSatisfy({ $0 == 0 }) else { return nil }
        let address = Array(inner[12...])
        guard !address.allSatisfy({ $0 == 0 }) else { return nil }
        return "0x" + Keccak256.hexString(address)
    }

    // MARK: ABI, the few shapes above

    private static func hexBytes(_ hex: String) -> [UInt8]? {
        let body = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard body.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(body.count / 2)
        var i = body.startIndex
        while i < body.endIndex {
            let j = body.index(i, offsetBy: 2)
            guard let v = UInt8(body[i..<j], radix: 16) else { return nil }
            out.append(v)
            i = j
        }
        return out
    }

    /// `abi.encode(bytes, bytes, …)`.
    private static func abiBytes(_ parts: [[UInt8]]) -> [UInt8] {
        func uint(_ n: Int) -> [UInt8] { [UInt8](repeating: 0, count: 24) + withUnsafeBytes(of: UInt64(n).bigEndian, Array.init) }
        var head: [UInt8] = []
        var tail: [UInt8] = []
        for p in parts {
            head += uint(parts.count * 32 + tail.count)
            tail += uint(p.count) + p + [UInt8](repeating: 0, count: (32 - p.count % 32) % 32)
        }
        return head + tail
    }

    private static func word(_ b: [UInt8], _ index: Int) -> [UInt8]? { word(b, at: index * 32) }
    private static func word(_ b: [UInt8], at: Int) -> [UInt8]? {
        guard at >= 0, at + 32 <= b.count else { return nil }
        return Array(b[at..<(at + 32)])
    }
    /// A word that must be a small number (an offset or a length).
    private static func small(_ w: [UInt8]) -> Int? {
        guard w[0..<28].allSatisfy({ $0 == 0 }) else { return nil }
        return w[28...].reduce(0) { $0 << 8 | Int($1) }
    }
    private static func offset(_ b: [UInt8], _ index: Int) -> Int? { word(b, index).flatMap(small) }
    private static func dynamicBytes(_ b: [UInt8], at: Int) -> [UInt8]? {
        guard let n = word(b, at: at).flatMap(small), at + 32 + n <= b.count else { return nil }
        return Array(b[(at + 32)..<(at + 32 + n)])
    }
}
