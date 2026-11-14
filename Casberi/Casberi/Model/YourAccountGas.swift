import Foundation

/// **GAS PAID IN USDC (prd §1780; user: "i don't want them to need eth to do
/// a transaction", "we don't have money to sponsor gas").** On Base a send
/// whose account is short of ETH for the fee has Circle's paymaster front
/// the gas and take it back from the account's own USDC, in the same
/// operation. Nobody is sponsored: the person pays, in the token they hold.
///
/// The paymaster is a contract anyone may name (no account, no key). It pulls
/// the most the operation can cost before it runs and refunds the rest after,
/// so it needs an allowance on the account's USDC. That allowance is given by
/// an EIP-2612 permit the account signs (a Safe answers it through ERC-1271),
/// carried inside the operation; nothing is sent to set it up.
///
/// **The allowance is capped (user, 2026-11-13: "$5, refilled").** The
/// paymaster is an upgradeable proxy of Circle's, so an unlimited allowance
/// would trust it with every USDC the account holds on Base. A permit is for
/// `cap`; when what is left of it no longer covers a send, the next send
/// carries a new permit, which is a second Face ID.
///
/// Foundation only, and no network: `usdc-gas-selftest.sh` pins every byte
/// here to viem's and the cost to the contract's own arithmetic.
enum YourAccountGas {
    /// The most the paymaster may take before it is asked again: 5 USDC.
    static let cap = "5000000"

    /// A permit with no end: the paymaster passes `type(uint256).max` as the
    /// deadline itself (`TokenPaymasterV07.validatePaymasterUserOp`), so any
    /// other value signs a permit it never presents.
    static let deadline = [UInt8](repeating: 0xFF, count: 32)

    private static func k(_ b: [UInt8]) -> [UInt8] { Keccak256.hash(b) }
    private static func word(_ decimal: String) -> [UInt8]? { SafeABI.word(uint256: decimal) }

    /// USDC's EIP-712 domain separator, computed here and compared with the
    /// token's own `DOMAIN_SEPARATOR()` before anything is signed: its name
    /// differs by network ("USD Coin" on Base, "USDC" on Base Sepolia).
    static func domainSeparator(name: String, version: String, chainId: Int, token: String) -> [UInt8] {
        k(k(Array("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)".utf8))
          + k(Array(name.utf8)) + k(Array(version.utf8)) + YourAccount.w(chainId) + YourAccount.w(token))
    }

    /// The names USDC signs under, by chain: the one fact about the token
    /// this file cannot derive. A domain that does not hash to the token's
    /// own separator is a refusal (`YourAccountChain`), never a signature.
    static func tokenName(chainId: Int) -> (name: String, version: String)? {
        switch chainId {
        case 8453: ("USD Coin", "2")
        case 84532: ("USDC", "2")
        default: nil
        }
    }

    /// The EIP-2612 digest the account signs: `owner` lets `spender` take up
    /// to `value`, at the token's `nonce` for the owner, with no deadline.
    static func permitDigest(domain: [UInt8], owner: String, spender: String, value: String, nonce: String) -> [UInt8]? {
        guard domain.count == 32, let value = word(value), let nonce = word(nonce) else { return nil }
        let type = k(Array("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)".utf8))
        let structHash = k(type + YourAccount.w(owner) + YourAccount.w(spender) + value + nonce + deadline)
        return k([0x19, 0x01] + domain + structHash)
    }

    /// What the paymaster is handed with a permit: one byte it keeps for
    /// later use, the token, the permit's amount, the signature
    /// (`BaseTokenPaymaster.parsePermitData`, read 2026-11-13).
    static func permitData(token: String, amount: String, signature: [UInt8]) -> [UInt8]? {
        guard let amount = word(amount), !signature.isEmpty else { return nil }
        return [0x00] + YourAccount.addressBytes(token) + amount + signature
    }

    /// `permit(address,address,uint256,uint256,bytes)` as the paymaster calls
    /// it: asked of the token with `eth_call` before the operation goes, so a
    /// signature the token would refuse is a refusal here (the paymaster
    /// swallows a failed permit, and the send would then fail unexplained).
    static func permitCall(owner: String, spender: String, value: String, signature: [UInt8]) -> [UInt8]? {
        guard let value = word(value) else { return nil }
        return YourAccount.sel("permit(address,address,uint256,uint256,bytes)") + YourAccount.w(owner) + YourAccount.w(spender)
            + value + deadline + YourAccount.w(160) + YourAccount.dynamic(signature)
    }

    static func allowanceCall(owner: String, spender: String) -> [UInt8] {
        YourAccount.sel("allowance(address,address)") + YourAccount.w(owner) + YourAccount.w(spender)
    }

    static func noncesCall(owner: String) -> [UInt8] { YourAccount.sel("nonces(address)") + YourAccount.w(owner) }

    /// The slot of `allowed[owner][spender]` in Circle's FiatToken (slot 10),
    /// for the bundler's estimate alone: priced as if the allowance stood,
    /// so the fee is known before the permit is signed. Nothing signed or
    /// sent reads it.
    static func allowanceSlot(owner: String, spender: String) -> String {
        let inner = k(YourAccount.w(owner) + YourAccount.w(10))
        return SafeABI.hex(k(YourAccount.w(spender) + inner))
    }

    /// The slot of the owner's balance in Circle's FiatToken (slot 9), for
    /// DEBUG's dry run alone (`-usdcGasProbe`): an empty simulator account
    /// priced as if it held USDC, so the paymaster's whole validation runs.
    static func balanceSlot(owner: String) -> String {
        SafeABI.hex(k(YourAccount.w(owner) + YourAccount.w(9)))
    }

    /// The most the paymaster takes for an operation, in USDC's base units,
    /// by its own arithmetic (`FeeLib.calculateUserChargeWithSpread`): the
    /// operation's most in wei plus its fixed charge of gas, at the oracle's
    /// price, plus one unit, plus its spread. What is not used comes back in
    /// the same operation. Nil when a number does not parse.
    static func tokenCost(maxCost: UInt64, maxFeePerGas: UInt64, charge: UInt64, price: String, spreadBips: UInt64) -> String? {
        guard let price = Decimal(string: price), price > 0 else { return nil }
        let wei = Decimal(charge) * Decimal(maxFeePerGas) + Decimal(maxCost)
        var product = wei * price / Decimal(sign: .plus, exponent: 18, significand: 1)
        var floor = Decimal()
        NSDecimalRound(&floor, &product, 0, .down)
        let base = floor + 1
        var spread = base * Decimal(spreadBips) / 10_000
        var spreadFloor = Decimal()
        NSDecimalRound(&spreadFloor, &spread, 0, .down)
        return NSDecimalNumber(decimal: base + spreadFloor).stringValue
    }

    /// Whether a send must carry a permit: what is left of the allowance no
    /// longer covers the most it can cost.
    static func needsPermit(allowance: String, cost: String) -> Bool { !YourAccountOp.atMost(cost, allowance) }

    /// What a permit is for: the cap, or the one send's cost where that is
    /// more (it never is on Base; a cap under the cost would fail the send).
    static func permitValue(cost: String) -> String { YourAccountOp.atMost(cost, cap) ? cap : cost }

    /// Dollars for a fee line: "0.02", never "0.00" for something that costs.
    static func spoken(_ units: String) -> String {
        guard let u = Decimal(string: units), u > 0 else { return "0" }
        let cents = NSDecimalNumber(decimal: u / 10_000).doubleValue.rounded(.up)
        return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), max(cents, 1) / 100)
    }
}
