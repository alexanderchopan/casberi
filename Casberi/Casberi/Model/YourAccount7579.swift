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
    /// Rhinestone's passkey validator, the audited (ChainLight) build that
    /// answers a session's `validateSignatureWithData`; the module SDK's
    /// `0x7ab16f…` does not, so it cannot sign for a session.
    static let webAuthnValidator = "0x0000000000578c4cb0e472a5462da43c495c3f33"
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

    /// UniActionPolicy's `ActionConfig`, all static: no ETH with the call,
    /// and ONE rule — the token amount (`transfer`'s second word, offset 32)
    /// at most `units`. The policy refuses a config with no rule, and every
    /// rule reads the call's data, so a plain ETH send can never pass it:
    /// ETH has no per-send cap among the deployed policies (prd §1447 item 14).
    static func perSendConfig(units: String) -> [UInt8]? {
        guard let cap = word(units) else { return nil }
        let lessThanOrEqual = 4
        let rule = YourAccount.w(lessThanOrEqual) + YourAccount.w(32) + YourAccount.w(0) + cap
            + YourAccount.w(0) + YourAccount.w(0)
        return YourAccount.w(0) + YourAccount.w(1) + rule + [UInt8](repeating: 0, count: 15 * 6 * 32)
    }

    /// A session's salt, so each limit is its own permission.
    static func salt(token: String, units: String) -> [UInt8] {
        Keccak256.hash(Array("casberi.spendLimit".utf8) + YourAccount.w(token) + (word(units) ?? []))
    }

    /// The session's id: `keccak256(abi.encode(validator, initData, salt))`.
    static func permissionId(validatorInit: [UInt8], salt: [UInt8]) -> [UInt8] {
        Keccak256.hash(YourAccount.w(webAuthnValidator) + YourAccount.w(96) + salt + YourAccount.dynamic(validatorInit))
    }

    /// One `Session`: the passkey validator over `validatorInit`, no user
    /// operation policies, no ERC-1271, and ONE action — `token.transfer`,
    /// to anyone, at most `units` a send.
    static func session(validatorInit: [UInt8], token: String, perSend units: String) -> [UInt8]? {
        guard let config = perSendConfig(units: units) else { return nil }
        let initTail = YourAccount.dynamic(validatorInit)
        let userOpPolicies = YourAccount.w(0)
        let erc7739 = YourAccount.w(64) + YourAccount.w(96) + YourAccount.w(0) + YourAccount.w(0)
        let policy = YourAccount.w(uniActionPolicy) + YourAccount.w(64) + YourAccount.dynamic(config)
        let policies = YourAccount.w(1) + YourAccount.w(32) + policy
        let transfer = YourAccount.sel("transfer(address,uint256)") + [UInt8](repeating: 0, count: 28)
        let action = transfer + YourAccount.w(token) + YourAccount.w(96) + policies
        let actions = YourAccount.w(1) + YourAccount.w(32) + action
        let head = 7 * 32
        let a = head, b = a + initTail.count, c = b + userOpPolicies.count, d = c + erc7739.count
        return YourAccount.w(webAuthnValidator) + YourAccount.w(a) + salt(token: token, units: units)
            + YourAccount.w(b) + YourAccount.w(c) + YourAccount.w(d) + YourAccount.w(0)
            + initTail + userOpPolicies + erc7739 + actions
    }

    private static func sessions(_ session: [UInt8]) -> [UInt8] {
        YourAccount.w(32) + YourAccount.w(1) + YourAccount.w(32) + session
    }

    /// `enableSessions([session])`, on Smart Sessions already installed.
    static func enableSessionCall(_ session: [UInt8]) -> Call {
        Call(operation: 0, to: smartSession, value: YourAccount.w(0),
             data: YourAccount.sel("enableSessions((address,bytes,bytes32,(address,bytes)[],((bytes32,string[])[],(address,bytes)[]),(bytes4,address,(address,bytes)[])[],bool)[])")
                + sessions(session))
    }

    /// `removeSession(permissionId)`: a limit taken back.
    static func removeSessionCall(_ permissionId: [UInt8]) -> Call {
        Call(operation: 0, to: smartSession, value: YourAccount.w(0),
             data: YourAccount.sel("removeSession(bytes32)") + permissionId)
    }

    /// `installModule(1, smartSession, ENABLE ‖ abi.encode(Session[1]))`,
    /// called by the account on itself (the adapter's `onlyEntryPointOrSelf`).
    static func installSessionCall(account: String, session: [UInt8]) -> Call {
        let initData: [UInt8] = [0x01] + sessions(session)
        return Call(operation: 0, to: account, value: YourAccount.w(0),
                    data: YourAccount.sel("installModule(uint256,address,bytes)") + YourAccount.w(1)
                        + YourAccount.w(smartSession) + YourAccount.w(96) + YourAccount.dynamic(initData))
    }

    /// `token.transfer(to, units)` as the adapter's one plain call.
    static func transferCall(token: String, to: String, units: String) -> [UInt8]? {
        guard let amount = word(units) else { return nil }
        return executeSingle(to: token, wei: "0", data: YourAccount.sel("transfer(address,uint256)") + YourAccount.w(to) + amount)
    }

    /// The adapter's `execute(mode 0, target ‖ value ‖ data)`: one plain call.
    static func executeSingle(to target: String, wei: String, data: [UInt8] = []) -> [UInt8]? {
        guard let value = word(wei) else { return nil }
        return YourAccount.sel("execute(bytes32,bytes)") + YourAccount.w(0) + YourAccount.w(64)
            + YourAccount.dynamic(YourAccount.addressBytes(target) + value + data)
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
