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
    static let smartSession = "0x00000000002B0eCfbD0496EE71e01257dA0E37DE"
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
}
