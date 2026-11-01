import Foundation

/// **THE ACCOUNT ON SAFE'S 7579 ADAPTER (prd §1447 item 11).**
///
/// A Safe reaches ERC-7579 modules only through Safe's adapter, Safe7579
/// (measured on Base and Ethereum, 2026-10-20: `adapter`, 20,014 bytes, at
/// the same address on both). No contract of ours, none deployed by us. The
/// spend limit that first put accounts on it is deleted (prd §1570, §1632);
/// what stays of Smart Sessions is the read of an older build's sessions and
/// their removal.
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
    /// Smart Sessions, where an older build's spend limit kept its sessions
    /// (prd §1447 item 14, deleted §1632): read off its repository's
    /// `Deploy.toml` and matched byte for byte on Base and Ethereum.
    static let smartSession = "0x00000000008bDABA73cD9815d79069c247Eb4bDA"
    /// Multicall3, the standard contract at one address on every network.
    /// An older build's sessions sent ETH THROUGH it (prd §1447 item 15), so
    /// until the co-signer switch removes them the account never approves it
    /// a token (`approvesMulticall3`).
    static let multicall3 = "0xcA11bde05977b3631167028862bE2a173976CA11"
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

    // MARK: - Sessions an older build enabled (prd §1455, deleted §1632)

    /// `removeSession(permissionId)`: one taken back.
    static func removeSessionCall(_ permissionId: [UInt8]) -> Call {
        Call(operation: 0, to: smartSession, value: YourAccount.w(0),
             data: YourAccount.sel("removeSession(bytes32)") + permissionId)
    }

    /// `getPermissionIDs(account)`: every session the account has.
    static func permissionIdsCall(account: String) -> [UInt8] {
        YourAccount.sel("getPermissionIDs(address)") + YourAccount.w(account)
    }

    /// Whether `call` would let Multicall3 spend a token of the account's —
    /// an `approve`, `increaseAllowance` or `setApprovalForAll` naming it —
    /// which would hand a standing session's ETH route the token too. Refused.
    static func approvesMulticall3(_ call: Call) -> Bool {
        let spenderFirst = ["approve(address,uint256)", "increaseAllowance(address,uint256)", "setApprovalForAll(address,bool)"]
        guard call.data.count >= 36 else { return false }
        let selector = Array(call.data.prefix(4))
        guard spenderFirst.contains(where: { YourAccount.sel($0) == selector }) else { return false }
        return Array(call.data[4..<36]) == YourAccount.w(multicall3)
    }
}
