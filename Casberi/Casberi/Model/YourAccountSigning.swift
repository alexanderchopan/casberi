import Foundation

/// **TWO KEYS TO SPEND ABOVE AN AMOUNT (prd §1447).**
///
/// The account is a Safe, so a second signature is one `changeThreshold(2)`
/// away — but a Safe has ONE threshold for everything, and "two signatures
/// above $500" cannot be said to it. The rule is Safe's own Allowance module
/// (0.1.1, measured on Base 2026-10-20 at `AllowanceModule.address`, 15,003
/// bytes; the 1.4.1 address is empty there): the Safe runs at 2-of-2, and
/// this phone's key is a DELEGATE with an allowance it spends alone, per token
/// per period, through `executeAllowanceTransfer`. Above the allowance a send
/// is a Safe transaction, and waits on the signer.
///
/// No contract of ours (standing rule), and never the app alone: a limit
/// enforced in software a compromised phone runs is not 2-of-2, and must not
/// be called it.
enum YourAccountSigning {
    typealias Op = YourAccountOp
    typealias Call = Op.Call

    /// How the account signs: the Safe's threshold, read live.
    enum Mode: Equatable {
        /// Threshold 1: any one key spends.
        case anyKey
        /// Threshold 2, the phone's key a delegate with an allowance.
        case bothAboveAllowance
        /// A threshold this app did not set (a Safe app elsewhere changed it).
        case other(Int)
    }

    /// Safe's Allowance module, one deployment per chain; the delegate's
    /// allowance is `(safe, delegate, token) → (amount, spent, resetMinutes, lastReset, nonce)`.
    enum AllowanceModule {
        static let address = "0xCFbFaC74C26F8647cBDb8c5caf80BB5b32E43134"
        static let enableModule = YourAccount.sel("enableModule(address)")
        static let addDelegate = YourAccount.sel("addDelegate(address)")
        static let setAllowance = YourAccount.sel("setAllowance(address,address,uint96,uint16,uint32)")
        static let getTokenAllowance = YourAccount.sel("getTokenAllowance(address,address,address)")
        static let executeAllowanceTransfer = YourAccount.sel("executeAllowanceTransfer(address,address,address,uint96,address,uint96,address,bytes)")
        static let generateTransferHash = YourAccount.sel("generateTransferHash(address,address,address,uint96,address,uint96,uint16)")
    }

    // MARK: - The calls, as the account signs them

    /// `changeThreshold(n)` on the account itself.
    static func thresholdCall(account: String, to n: Int) -> Call {
        Call(operation: 0, to: account, value: YourAccount.w(0),
             data: YourAccount.sel("changeThreshold(uint256)") + YourAccount.w(n))
    }

    /// The Allowance module enabled on the account.
    static func enableAllowanceCall(account: String) -> Call {
        Call(operation: 0, to: account, value: YourAccount.w(0),
             data: AllowanceModule.enableModule + YourAccount.w(AllowanceModule.address))
    }

    /// `delegate` made a delegate of the account on the module (called BY the
    /// account, so `msg.sender` is the Safe).
    static func addDelegateCall(delegate: String) -> Call {
        Call(operation: 0, to: AllowanceModule.address, value: YourAccount.w(0),
             data: AllowanceModule.addDelegate + YourAccount.w(delegate))
    }

    /// The delegate's allowance of `token` (the zero address for the chain's
    /// coin): `amount` in base units a period of `resetMinutes` long (0 = a
    /// one-off), from `resetBase` (0 = now).
    static func setAllowanceCall(delegate: String, token: String, amount: String, resetMinutes: Int) -> Call? {
        guard let amountWord = SafeABI.word(uint256: amount) else { return nil }
        return Call(operation: 0, to: AllowanceModule.address, value: YourAccount.w(0),
                    data: AllowanceModule.setAllowance + YourAccount.w(delegate) + YourAccount.w(token)
                        + amountWord + YourAccount.w(resetMinutes) + YourAccount.w(0))
    }

    /// Everything a switch to "both keys above an amount" needs, in one
    /// operation: the module on, this phone's delegate, its allowance, then
    /// the threshold last — so a step that fails leaves the account at 1.
    static func enableCalls(account: String, delegate: String, token: String, amount: String, resetMinutes: Int) -> [Call]? {
        guard let allowance = setAllowanceCall(delegate: delegate, token: token, amount: amount, resetMinutes: resetMinutes) else { return nil }
        return [enableAllowanceCall(account: account), addDelegateCall(delegate: delegate), allowance,
                thresholdCall(account: account, to: 2)]
    }

    /// Back to any one key: the threshold first. The module and allowance
    /// stay (harmless at threshold 1, and the next switch is one call).
    static func disableCalls(account: String) -> [Call] {
        [thresholdCall(account: account, to: 1)]
    }

    // MARK: - Reading

    /// `getTokenAllowance(safe, delegate, token)` → `[amount, spent, resetMinutes, lastReset, nonce]`.
    static func allowanceCalldata(account: String, delegate: String, token: String) -> [UInt8] {
        AllowanceModule.getTokenAllowance + YourAccount.w(account) + YourAccount.w(delegate) + YourAccount.w(token)
    }

    struct Allowance: Equatable {
        let amount: String
        let spent: String
        let resetMinutes: Int
        let lastReset: Int
        let nonce: Int
        var left: String { Op.difference(amount, spent) }
    }

    /// The five words an allowance read answers with; nil for anything else.
    static func decodeAllowance(_ hex: String) -> Allowance? {
        guard let bytes = SafeABI.hexBytes(hex), bytes.count == 5 * 32 else { return nil }
        func word(_ i: Int) -> String? { Op.decimal(hexQuantity: SafeABI.hex(Array(bytes[(i * 32)..<((i + 1) * 32)]))) }
        guard let amount = word(0), let spent = word(1),
              let reset = word(2).flatMap(Int.init), let last = word(3).flatMap(Int.init),
              let nonce = word(4).flatMap(Int.init) else { return nil }
        return Allowance(amount: amount, spent: spent, resetMinutes: reset, lastReset: last, nonce: nonce)
    }

    static func mode(threshold: Int) -> Mode {
        switch threshold {
        case 1: .anyKey
        case 2: .bothAboveAllowance
        default: .other(threshold)
        }
    }
}
