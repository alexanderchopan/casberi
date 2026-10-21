import Foundation

/// **THE ACCOUNT ON SAFE'S 7579 ADAPTER (prd §1447 item 11).**
///
/// The spend limit lives in Rhinestone's Smart Sessions, an ERC-7579 module,
/// and a Safe reaches 7579 modules only through Safe's adapter, Safe7579
/// (measured on Base and Ethereum, 2026-10-20: `adapter`, 20,014 bytes, and
/// `smartSession`, 23,940, at the same addresses on both). No contract of
/// ours, none deployed by us.
///
/// Installing it on an account that exists is ONE operation, signed by this
/// phone like any send, read off the adapter's source
/// (`rhinestonewtf/safe7579`, `core/Initializer.sol`, `AccessControl.sol`):
/// 1. `enableModule(adapter)` — it runs the Safe's calls for its modules;
/// 2. `setFallbackHandler(adapter)` — the EntryPoint's calls on the Safe now
///    reach the adapter, not Safe's 4337 module;
/// 3. the account calls ITSELF with `initializeAccount([], no registry)` —
///    `onlyEntryPointOrSelf` takes a call whose fallback sender is the Safe;
/// 4. `disableModule(adapter → 4337 module)` — the old module, out of reach
///    once it is no longer the handler, out of the list too.
///
/// After it, a validator of address(0) in the nonce key falls back to the
/// Safe's own `checkSignatures` — the path the shared passkey signer answers
/// on — so the two keys sign as before; the SafeOp hash keeps its shape and
/// takes the adapter as its domain; and a send's calls are the adapter's
/// `execute(mode, calls)`. Until that send path is built and proven, the
/// install runs only as a simulation.
enum YourAccount7579 {
    typealias Call = YourAccountOp.Call

    static let adapter = "0x7579EE8307284F293B1927136486880611F20002"
    /// Smart Sessions' current family, each read off its repository's
    /// `Deploy.toml` and artifacts through Safe's singleton factory and
    /// matched byte for byte on Base and Ethereum (prd §1447 item 14). An
    /// older SmartSession (`0x…2B0e…`) shares the Session shape; not it.
    static let smartSession = "0x00000000008bDABA73cD9815d79069c247Eb4bDA"
    static let uniActionPolicy = "0x0000000000714cf48fcf88a0bfba70d313415032"
    static let timeFramePolicy = "0x0000000000d30f611fa3bf652ac6879428586930"
    static let valueLimitPolicy = "0x000000000021dc45451291bcdfc9f0b46d6f0278"
    /// Multicall3, the standard contract at one address on every network:
    /// ETH under the limit goes THROUGH it, because a plain ETH send carries
    /// no call a policy can be pinned to, and the only way to allow one to
    /// anyone is a catch-all that would also let the session call the
    /// account itself (prd §1447 item 15). Multicall3 holds no power over the
    /// account, so through it the session can spend ETH up to the limit and
    /// nothing else — as long as the account never approves it a token.
    static let multicall3 = "0xcA11bde05977b3631167028862bE2a173976CA11"
    /// Rhinestone's passkey validator, the audited (ChainLight) build that
    /// answers a session's `validateSignatureWithData`; the module SDK's
    /// `0x7ab16f…` does not, so it cannot sign for a session.
    static let webAuthnValidator = "0x0000000000578c4cb0e472a5462da43c495c3f33"
    /// Safe's singleton factory (`CREATE2` of `salt ‖ initcode`, the same
    /// address on every network), which published the adapter on Ethereum in
    /// `publishTransaction` (block 20,998,751, by Rhinestone's deployer).
    static let singletonFactory = "0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7"
    static let publishTransaction = "0xa782c12dcef5ba32d484fbacb96ae9616b1eb61bcdb4f7ce1195201b7ca55fd2"

    /// Where `salt ‖ initcode` sent to the singleton factory lands: the
    /// address commits to the code, so a match IS the audited adapter.
    static func publishedAddress(_ input: [UInt8]) -> String? {
        guard input.count > 32 else { return nil }
        let salt = Array(input.prefix(32)), initCode = Array(input.dropFirst(32))
        let hash = Keccak256.hash([0xff] + YourAccount.addressBytes(singletonFactory) + salt + Keccak256.hash(initCode))
        return "0x" + Keccak256.hexString(Array(hash.suffix(20)))
    }

    /// The head of Safe's module list (`SENTINEL_MODULES`).
    static let sentinel = "0x0000000000000000000000000000000000000001"

    /// `initializeAccount(validators, executors, fallbacks, hooks, registryInit)`,
    /// the DEPLOYED adapter's v1 signature (its bytecode carries `0x540fb4f9`;
    /// `main` has since merged the four lists into one, and that selector is
    /// not on chain — measured 2026-10-20). Every list empty, no registry:
    /// the adapter set up, nothing installed.
    static func initializeAccountData() -> [UInt8] {
        let selector = YourAccount.sel("initializeAccount((address,bytes)[],(address,bytes)[],(address,bytes)[],(address,bytes)[],(address,address[],uint8))")
        let empty = YourAccount.w(0)                                // an empty list: its length
        let registry = YourAccount.w(SafeTransaction.zeroAddress)   // registry
            + YourAccount.w(96)                                     // attesters' offset in the tuple
            + YourAccount.w(0)                                      // threshold
            + YourAccount.w(0)                                      // attesters, length 0
        // Five dynamic arguments: five offsets, then four empty lists, then the tuple.
        let head = 5 * 32
        let offsets = (0..<4).map { YourAccount.w(head + $0 * 32) } + [YourAccount.w(head + 4 * 32)]
        return selector + offsets.flatMap { $0 } + empty + empty + empty + empty + registry
    }

    /// The four calls, in order. The account's module list is the 4337
    /// module alone (measured on Base), so once the adapter is enabled at
    /// the head the 4337 module's predecessor is the adapter.
    static func installCalls(account: String) -> [Call] {
        let zero = YourAccount.w(0)
        return [
            Call(operation: 0, to: account, value: zero,
                 data: YourAccount.sel("enableModule(address)") + YourAccount.w(adapter)),
            Call(operation: 0, to: account, value: zero,
                 data: YourAccount.sel("setFallbackHandler(address)") + YourAccount.w(adapter)),
            Call(operation: 0, to: account, value: zero, data: initializeAccountData()),
            // enableModule puts the adapter at the head: SENTINEL → adapter → 4337 module.
            Call(operation: 0, to: account, value: zero,
                 data: YourAccount.sel("disableModule(address,address)") + YourAccount.w(adapter) + YourAccount.w(YourAccount.module4337)),
        ]
    }

    // MARK: - The spend limit's session (prd §1447 item 14)

    private static func word(_ decimal: String) -> [UInt8]? { SafeABI.word(uint256: decimal) }

    /// The passkey validator's session config, `abi.encode(context, account)`
    /// as its DEPLOYED build reads it (the repository's `main` dropped the
    /// account): one credential, this phone's session key, user verification
    /// required, threshold 1, native P-256.
    ///
    /// Smart Sessions keeps a validator's config in at most 320 bytes
    /// (`FlatBytesLib`, ten words) and the plain encoding is 384, so this one
    /// is PACKED, measured on Base 2026-10-20 (prd §1447 item 14): `account`
    /// only seeds the credential id (the check is stateless, the session
    /// itself is stored under the real account), so it is `address(1)` and its
    /// word is also the context's `usePrecompile = true`; the credential's
    /// `requireUV = 1` is also the id list's length. A real P-256 assertion
    /// verifies through it, a tampered one and another hash do not.
    static func validatorInitData(x: [UInt8], y: [UInt8]) -> [UInt8] {
        let one = YourAccount.w(1)
        let id = Keccak256.hash(x + y + one)                    // generateCredentialId(x, y, address(1))
        return YourAccount.w(32)                                 // the context starts at word 1
            + one                                                // account = address(1) = usePrecompile
            + one                                                // threshold
            + YourAccount.w(224) + YourAccount.w(128)            // ids at word 8, credentials at word 5
            + one + x + y                                        // one credential: x, y,
            + one                                                // requireUV = the ids' length
            + id
    }

    /// One period's allowance: from `from` until `until` (unix seconds), at
    /// most `dollarCap` units of the network's dollar and `ethCap` wei, each a
    /// running total within it. "0" leaves that token out: it then always
    /// needs both keys.
    struct Window: Codable, Equatable {
        let from: Int
        let until: Int
    }

    struct Plan: Codable, Equatable {
        let chainId: Int
        let dollar: String
        let dollarCap: String
        let ethCap: String
        let windows: [Window]

        /// The window that holds `now`, if any.
        func window(at now: Int) -> Window? { windows.first { $0.from <= now && now < $0.until } }
    }

    /// `count` back-to-back windows of `seconds` each, from `start`. A period
    /// limit is set up AHEAD: no deployed policy refills, so each period is
    /// its own session, valid only inside it (TimeFramePolicy).
    static func windows(start: Int, seconds: Int, count: Int) -> [Window] {
        (0..<max(count, 0)).map { Window(from: start + $0 * seconds, until: start + ($0 + 1) * seconds) }
    }

    /// UniActionPolicy's `ActionConfig`, all static: no ETH with the call,
    /// and ONE rule on the token amount (`transfer`'s second word, offset
    /// 32): at most `units` a send, and — `isLimited` — at most `units` in
    /// all, so the session's total within its window.
    static func tokenTotalConfig(units: String) -> [UInt8]? {
        guard let cap = word(units) else { return nil }
        let lessThanOrEqual = 4
        let rule = YourAccount.w(lessThanOrEqual) + YourAccount.w(32) + YourAccount.w(1) + cap
            + cap + YourAccount.w(0)                                             // usage: limit, used
        return YourAccount.w(0) + YourAccount.w(1) + rule + [UInt8](repeating: 0, count: 15 * 6 * 32)
    }

    /// TimeFramePolicy's 12 bytes: `validUntil` then `validAfter`, 6 each.
    static func timeFrameInit(_ window: Window) -> [UInt8] {
        func six(_ n: Int) -> [UInt8] { (0..<6).map { UInt8(truncatingIfNeeded: n >> (8 * (5 - $0))) } }
        return six(window.until) + six(window.from)
    }

    /// How many windows a plan sets up ahead (prd §1455): a year of months
    /// or of twelve weeks, two weeks of days — then a new plan, both keys.
    static func windowCount(minutes: Int) -> Int {
        switch minutes {
        case ..<1_441: 14
        default: 12
        }
    }

    /// A window's salt, so each period is its own permission.
    static func salt(_ plan: Plan, _ window: Window) -> [UInt8] {
        Keccak256.hash(Array("casberi.spendLimit".utf8) + YourAccount.w(plan.dollar) + (word(plan.dollarCap) ?? [])
                       + (word(plan.ethCap) ?? []) + YourAccount.w(window.from) + YourAccount.w(window.until))
    }

    /// The session's id: `keccak256(abi.encode(validator, initData, salt))`.
    static func permissionId(validatorInit: [UInt8], salt: [UInt8]) -> [UInt8] {
        Keccak256.hash(YourAccount.w(webAuthnValidator) + YourAccount.w(96) + salt + YourAccount.dynamic(validatorInit))
    }

    private static func policyList(_ policy: String, _ initData: [UInt8]) -> [UInt8] {
        YourAccount.w(1) + YourAccount.w(32) + YourAccount.w(policy) + YourAccount.w(64) + YourAccount.dynamic(initData)
    }

    private static func selectorWord(_ signature: String) -> [UInt8] {
        YourAccount.sel(signature) + [UInt8](repeating: 0, count: 28)
    }

    /// One window's `Session`: the passkey validator over `validatorInit`,
    /// the window as its user-operation policy, no ERC-1271, and at most two
    /// actions — the dollar's `transfer` to anyone, totalled; ETH through
    /// Multicall3's `aggregate3Value`, totalled (ValueLimitPolicy).
    static func session(validatorInit: [UInt8], plan: Plan, window: Window) -> [UInt8]? {
        var actions: [[UInt8]] = []
        if plan.dollarCap != "0" {
            guard let config = tokenTotalConfig(units: plan.dollarCap) else { return nil }
            actions.append(selectorWord("transfer(address,uint256)") + YourAccount.w(plan.dollar) + YourAccount.w(96)
                           + policyList(uniActionPolicy, config))
        }
        if plan.ethCap != "0" {
            guard let cap = word(plan.ethCap) else { return nil }
            actions.append(selectorWord("aggregate3Value((address,bool,uint256,bytes)[])") + YourAccount.w(multicall3)
                           + YourAccount.w(96) + policyList(valueLimitPolicy, cap))
        }
        guard !actions.isEmpty else { return nil }
        var heads: [UInt8] = [], tails: [UInt8] = []
        for action in actions {
            heads += YourAccount.w(actions.count * 32 + tails.count)
            tails += action
        }
        let actionList = YourAccount.w(actions.count) + heads + tails
        let initTail = YourAccount.dynamic(validatorInit)
        let userOpPolicies = policyList(timeFramePolicy, timeFrameInit(window))
        let erc7739 = YourAccount.w(64) + YourAccount.w(96) + YourAccount.w(0) + YourAccount.w(0)
        let a = 7 * 32, b = a + initTail.count, c = b + userOpPolicies.count, d = c + erc7739.count
        return YourAccount.w(webAuthnValidator) + YourAccount.w(a) + salt(plan, window)
            + YourAccount.w(b) + YourAccount.w(c) + YourAccount.w(d) + YourAccount.w(0)
            + initTail + userOpPolicies + erc7739 + actionList
    }

    /// `abi.encode(Session[])`.
    private static func sessions(_ list: [[UInt8]]) -> [UInt8] {
        var heads: [UInt8] = [], tails: [UInt8] = []
        for session in list {
            heads += YourAccount.w(list.count * 32 + tails.count)
            tails += session
        }
        return YourAccount.w(32) + YourAccount.w(list.count) + heads + tails
    }

    /// `enableSessions(sessions)`, on Smart Sessions already installed.
    static func enableSessionsCall(_ list: [[UInt8]]) -> Call {
        Call(operation: 0, to: smartSession, value: YourAccount.w(0),
             data: YourAccount.sel("enableSessions((address,bytes,bytes32,(address,bytes)[],((bytes32,string[])[],(address,bytes)[]),(bytes4,address,(address,bytes)[])[],bool)[])")
                + sessions(list))
    }

    /// `removeSession(permissionId)`: a limit taken back.
    static func removeSessionCall(_ permissionId: [UInt8]) -> Call {
        Call(operation: 0, to: smartSession, value: YourAccount.w(0),
             data: YourAccount.sel("removeSession(bytes32)") + permissionId)
    }

    /// `installModule(1, smartSession, ENABLE ‖ abi.encode(Session[]))`,
    /// called by the account on itself (the adapter's `onlyEntryPointOrSelf`).
    static func installSessionsCall(account: String, sessions list: [[UInt8]]) -> Call {
        let initData: [UInt8] = [0x01] + sessions(list)
        return Call(operation: 0, to: account, value: YourAccount.w(0),
                    data: YourAccount.sel("installModule(uint256,address,bytes)") + YourAccount.w(1)
                        + YourAccount.w(smartSession) + YourAccount.w(96) + YourAccount.dynamic(initData))
    }

    /// `token.transfer(to, units)` as the adapter's one plain call.
    static func transferCall(token: String, to: String, units: String) -> [UInt8]? {
        guard let amount = word(units) else { return nil }
        return executeSingle(to: token, wei: "0", data: YourAccount.sel("transfer(address,uint256)") + YourAccount.w(to) + amount)
    }

    /// `wei` ETH to `to` THROUGH Multicall3 — `aggregate3Value([(to, no
    /// failure allowed, wei, no data)])` with `wei` on the call — as the
    /// adapter's one plain call. Multicall3 forwards it with all its gas, so
    /// a smart account receives it too.
    static func ethSendCall(to: String, wei: String) -> [UInt8]? {
        guard let value = word(wei) else { return nil }
        let call3 = YourAccount.w(to) + YourAccount.w(0) + value + YourAccount.w(128) + YourAccount.w(0)
        let data = YourAccount.sel("aggregate3Value((address,bool,uint256,bytes)[])")
            + YourAccount.w(32) + YourAccount.w(1) + YourAccount.w(32) + call3
        return executeSingle(to: multicall3, wei: wei, data: data)
    }

    /// Whether `call` would let Multicall3 spend a token of the account's —
    /// an `approve`, `increaseAllowance` or `setApprovalForAll` naming it —
    /// which would hand every session's ETH route the token too. Refused.
    static func approvesMulticall3(_ call: Call) -> Bool {
        let spenderFirst = ["approve(address,uint256)", "increaseAllowance(address,uint256)", "setApprovalForAll(address,bool)"]
        guard call.data.count >= 36 else { return false }
        let selector = Array(call.data.prefix(4))
        guard spenderFirst.contains(where: { YourAccount.sel($0) == selector }) else { return false }
        return Array(call.data[4..<36]) == YourAccount.w(multicall3)
    }

    /// One call of a batch: where, how much ETH, with what.
    struct Execution: Equatable, Sendable {
        let target: String
        let value: [UInt8]
        let data: [UInt8]
    }

    /// The adapter's `execute(mode 1, abi.encode(Execution[]))`: several
    /// plain calls in one, as Smart Sessions checks each against its actions.
    static func executeBatch(_ calls: [Execution]) -> [UInt8] {
        var mode = [UInt8](repeating: 0, count: 32)
        mode[0] = 0x01
        var heads: [UInt8] = [], tails: [UInt8] = []
        for c in calls {
            heads += YourAccount.w(calls.count * 32 + tails.count)
            tails += YourAccount.w(c.target) + c.value + YourAccount.w(96) + YourAccount.dynamic(c.data)
        }
        let list = YourAccount.w(32) + YourAccount.w(calls.count) + heads + tails
        return YourAccount.sel("execute(bytes32,bytes)") + mode + YourAccount.w(64) + YourAccount.dynamic(list)
    }

    /// A send as a session may carry it (prd §1455): the network's dollar by
    /// `transfer`, ETH through Multicall3; nil for anything else, which the
    /// limit does not cover and both keys sign.
    static func sessionCall(token contract: String?, dollar: String, to: String, units: String) -> Execution? {
        guard let amount = word(units) else { return nil }
        if let contract {
            guard contract.caseInsensitiveCompare(dollar) == .orderedSame else { return nil }
            return Execution(target: contract, value: YourAccount.w(0),
                             data: YourAccount.sel("transfer(address,uint256)") + YourAccount.w(to) + amount)
        }
        let call3 = YourAccount.w(to) + YourAccount.w(0) + amount + YourAccount.w(128) + YourAccount.w(0)
        let data = YourAccount.sel("aggregate3Value((address,bool,uint256,bytes)[])")
            + YourAccount.w(32) + YourAccount.w(1) + YourAccount.w(32) + call3
        return Execution(target: multicall3, value: amount, data: data)
    }

    /// The adapter's `execute(mode 0, target ‖ value ‖ data)`: one plain call.
    static func executeSingle(to target: String, wei: String, data: [UInt8] = []) -> [UInt8]? {
        guard let value = word(wei) else { return nil }
        return YourAccount.sel("execute(bytes32,bytes)") + YourAccount.w(0) + YourAccount.w(64)
            + YourAccount.dynamic(YourAccount.addressBytes(target) + value + data)
    }

    /// `getPermissionIDs(account)`: every session the account has.
    static func permissionIdsCall(account: String) -> [UInt8] {
        YourAccount.sel("getPermissionIDs(address)") + YourAccount.w(account)
    }

    /// The nonce key that picks Smart Sessions: its address, then 4 zero bytes.
    static var sessionNonceKey: [UInt8] { YourAccount.addressBytes(smartSession) + [0, 0, 0, 0] }

    /// USE mode: `0x00 ‖ permissionId ‖ abi.encode(WebAuthnAuth[1])`, the
    /// assertion over `SafeWebAuthn`'s own authenticator data and client
    /// data, challenge the user operation's hash.
    static func useSignature(permissionId: [UInt8], hash: [UInt8], r: [UInt8], s: [UInt8]) -> [UInt8] {
        let json = Array(SafeWebAuthn.clientDataJSON(challenge: hash).utf8)
        let challengeIndex = indexOf(Array("\"challenge\"".utf8), in: json) ?? 0
        let typeIndex = indexOf(Array("\"type\"".utf8), in: json) ?? 0
        let auth = YourAccount.dynamic(SafeWebAuthn.authenticatorData)
        let tuple = YourAccount.w(192) + YourAccount.w(192 + auth.count) + YourAccount.w(challengeIndex)
            + YourAccount.w(typeIndex) + r + s + auth + YourAccount.dynamic(json)
        return [0x00] + permissionId + YourAccount.w(32) + YourAccount.w(1) + YourAccount.w(32) + tuple
    }

    private static func indexOf(_ needle: [UInt8], in hay: [UInt8]) -> Int? {
        guard needle.count <= hay.count else { return nil }
        return (0...(hay.count - needle.count)).first { Array(hay[$0..<($0 + needle.count)]) == needle }
    }

    /// `validateSignatureWithData(hash, abi.encode(WebAuthnAuth[]), initData)`,
    /// asked of the validator before anything is sent.
    static func checkCall(hash: [UInt8], useSignature: [UInt8], validatorInit: [UInt8]) -> [UInt8] {
        let sig = Array(useSignature.dropFirst(33))
        let a = 96, b = a + YourAccount.dynamic(sig).count
        return YourAccount.sel("validateSignatureWithData(bytes32,bytes,bytes)") + hash + YourAccount.w(a) + YourAccount.w(b)
            + YourAccount.dynamic(sig) + YourAccount.dynamic(validatorInit)
    }
}
