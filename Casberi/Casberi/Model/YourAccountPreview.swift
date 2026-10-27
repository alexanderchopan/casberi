import Foundation

/// **WHAT A MOVE WILL DO, BEFORE FACE ID (prd §1509 item 1, Phase 1 of
/// `docs/signing-safety-spec.md`).** The sentence stays the screen; its grey
/// line gains the network fee and one word, Details, which opens what this
/// exact operation is: who it goes to, the fee in the network's coin, the
/// nonce, what the simulation found, and a page deeper the calls in words,
/// the hash Face ID signs and the bytes.
///
/// The arithmetic and the words are here, Foundation and the Safe encoders
/// only, so `move-details-selftest.sh` holds them; the reads that fill a
/// `YourAccountChain.Preview` are the chain's.
///
/// **Two readings of "the hash" (ERC-8213, read 2026-10-24, Draft):** an
/// operation your own keys sign is a SafeOp, EIP-712 typed data, so its hash
/// IS an "EIP-712 Digest" and is labelled exactly so. A send under the spend
/// limit is signed by the session key over EntryPoint v0.7's own
/// `getUserOpHash`, which is not EIP-712, so it is the "Operation hash". The
/// ERC's "Calldata Digest" (`keccak256(uint256(len) ‖ calldata)`) stands
/// under the operation's calldata either way.
enum YourAccountPreview {
    typealias Op = YourAccountOp

    // MARK: - The fee

    /// The most the operation can cost, in wei: every gas limit the
    /// operation carries times the most it pays a unit of gas. A ceiling,
    /// never the charge — what is used is less — so it is said "up to" (§83:
    /// a fee that can move says so). nil when a number overflows.
    static func networkFee(verification: UInt64, call: UInt64, preVerification: UInt64, maxFeePerGas: UInt64) -> String? {
        let (a, o1) = verification.addingReportingOverflow(call)
        let (b, o2) = a.addingReportingOverflow(preVerification)
        let (c, o3) = b.multipliedReportingOverflow(by: maxFeePerGas)
        return o1 || o2 || o3 ? nil : String(c)
    }

    /// The grey line's fee: "Fee under a cent" (the swap's words, a ceiling
    /// under a cent is a charge under a cent), else "Fee up to $0.03"; with
    /// no dollar price, the coin.
    static func feePhrase(usd: Double?, wei: String, coin: String = "ETH", money: (Double) -> String) -> String {
        if let usd {
            return usd < 0.01 ? String(localized: "Fee under a cent") : String(localized: "Fee up to \(money(usd))")
        }
        return String(localized: "Fee up to \(Self.coin(wei)) \(coin)")
    }

    /// Wei as the coin, to two significant figures under one: "0.0000031",
    /// never the six places that round a fee to "0.000003".
    static func coin(_ wei: String) -> String {
        let whole = Op.display(wei, decimals: 18, places: 18)
        guard whole.hasPrefix("0."), let dot = whole.firstIndex(of: "."),
              let first = whole[dot...].firstIndex(where: { $0 != "0" && $0 != "." }) else {
            return Op.display(wei, decimals: 18)
        }
        return Op.display(wei, decimals: 18, places: whole.distance(from: whole.index(after: dot), to: first) + 2)
    }

    // MARK: - ERC-8213

    /// The **Calldata Digest** (ERC-8213): `keccak256(uint256(len(calldata))
    /// ‖ calldata)`, the length a big-endian 32-byte word, no chain id.
    static func calldataDigest(_ calldata: [UInt8]) -> [UInt8] {
        var length = [UInt8](repeating: 0, count: 32)
        var n = UInt64(calldata.count)
        for i in stride(from: 31, through: 24, by: -1) { length[i] = UInt8(n & 0xff); n >>= 8 }
        return Keccak256.hash(length + calldata)
    }

    /// How a hash is labelled, in ERC-8213's exact terms where they apply.
    enum HashKind: Equatable, Sendable {
        /// A SafeOp: EIP-712 typed data, its digest what Face ID signs.
        case eip712
        /// EntryPoint v0.7's `getUserOpHash`, which the session key signs.
        case userOp

        var label: String {
            switch self {
            case .eip712: String(localized: "EIP-712 Digest")
            case .userOp: String(localized: "Operation hash")
            }
        }
    }

    // MARK: - What the simulation found

    /// What running this exact operation's calls against the network's
    /// state said (`eth_simulateV1`). "Checked" is drawn only for `lands` and
    /// `returnsAtLeast` (§83).
    enum Checked: Equatable, Sendable {
        case lands
        /// A swap: at least this many base units of the bought token.
        case returnsAtLeast(String, Op.Token)
        /// A call refused: which one (the transaction's own order), the
        /// token it was, and the node's reason decoded where it can be.
        case fails(call: Int?, token: String?, reason: String?)
        /// The node would not simulate, or could not be asked.
        case notChecked

        var fails: Bool { if case .fails = self { true } else { false } }
    }

    /// The red line when the simulation refuses (canvas figure 9): the
    /// token that refused, else the network.
    static func failLine(_ checked: Checked, swap: Bool, network: String) -> String? {
        guard case .fails(_, let token, _) = checked else { return nil }
        if let token {
            return swap ? String(localized: "This swap would fail: \(token) refuses it.")
                        : String(localized: "This send would fail: \(token) refuses it.")
        }
        return swap ? String(localized: "This swap would fail on \(network).")
                    : String(localized: "This send would fail on \(network).")
    }

    /// A revert's reason in words where the bytes carry one: `Error(string)`,
    /// `Panic(uint256)`, the few custom errors tokens raise for a transfer;
    /// else the selector, so Details says which error it was.
    static func revertReason(_ data: String?) -> String? {
        guard let data, let bytes = SafeABI.hexBytes(data), bytes.count >= 4 else { return nil }
        let selector = Keccak256.hexString(Array(bytes.prefix(4)))
        let body = Array(bytes.dropFirst(4))
        switch selector {
        case "08c379a0":
            // Error(string): offset, length, bytes.
            guard body.count >= 64 else { return nil }
            let length = body[32..<64].reduce(0) { ($0 << 8) | Int($1) }
            guard length > 0, length <= 512, body.count >= 64 + length,
                  let text = String(bytes: body[64..<(64 + length)], encoding: .utf8) else { return nil }
            return text
        case "4e487b71":
            guard body.count >= 32 else { return nil }
            return "Panic 0x" + String(format: "%02x", body[31])
        case "356680b7": return "InsufficientFunds()"
        case "e450d38c": return "ERC20InsufficientBalance"
        case "ec442f05": return "ERC20InvalidReceiver"
        case "96c6fd1e": return "ERC20InvalidSender"
        default: return "0x" + selector
        }
    }

    // MARK: - The calls, in words

    /// One numbered line of "What it does": the call's act, and under it
    /// what it means when that is not plain (the key change).
    struct Step: Equatable, Sendable {
        let words: String
        var detail: String? = nil
    }

    /// An approval the operation makes: always exactly what is sold, to the
    /// exchange's router that swaps it, used in the same step (§1539).
    struct Approval: Equatable, Sendable {
        let figure: String
        let symbol: String
        let spender: String
    }

    /// What one swap sells, and the pools it goes through (prd §1539): the
    /// pool fee is in the price, so there is no fee to add.
    struct Sold: Equatable, Sendable {
        let token: Op.Token
        let amount: String
        let route: YourAccountSwap.Route?
        /// A swap to another network: its crossing, for Details' Across
        /// rows (prd §1555).
        var across: YourAccountAcross.Leg? = nil
        /// WETH and ETH one for one through the network's WETH (prd §1559).
        var wrap: YourAccountSwap.Wrap? = nil
    }

    /// "Unwraps 0.01 WETH for 0.01 ETH" (prd §1559): one for one, the
    /// network's WETH contract, no pool.
    static func wrap(_ w: YourAccountSwap.Wrap, _ figure: String) -> Step {
        switch w {
        case .unwrap: Step(words: String(localized: "Unwraps \(figure) WETH for \(figure) ETH"),
                           detail: String(localized: "Through Uniswap's router, which pays the ETH out in full"))
        case .wrap: Step(words: String(localized: "Wraps \(figure) ETH for \(figure) WETH"))
        }
    }

    /// A swap to another network (prd §1555): "Sends 0.01 ETH to Base
    /// through Across", what arrives and the refund said beneath.
    static func crossing(_ figure: String, _ symbol: String, to network: String, arrives: String, _ bought: String,
                         back origin: String) -> Step {
        Step(words: String(localized: "Sends \(figure) \(symbol) to \(network) through Across"),
             detail: String(localized: "\(arrives) \(bought) arrives there; if no one fills it, it comes back on \(origin)"))
    }

    /// An address in a line of words: "...cD09", its tail only (prd §1553),
    /// as Details' To row shows it whole.
    static func short(_ address: String) -> String { AddressTail.short(address) }

    static func send(_ figure: String, _ symbol: String, to who: String) -> Step {
        Step(words: String(localized: "Sends \(figure) \(symbol) to \(who)"))
    }

    /// An approval is always exact (§1539: `YourAccountSwap.checked` refuses
    /// any other amount or spender), used in the same step.
    static func approve(_ figure: String, _ symbol: String, to spender: String) -> Step {
        Step(words: String(localized: "Lets \(spender) spend exactly \(figure) \(symbol)"),
             detail: String(localized: "Used in the same step"))
    }

    static func swap(_ figure: String, _ symbol: String, atLeast: String, _ bought: String, on exchange: String) -> Step {
        Step(words: String(localized: "Swaps \(figure) \(symbol) for at least \(atLeast) \(bought) on \(exchange)"))
    }

    static func roundUp(_ figure: String, _ symbol: String, buys target: String, on network: String) -> Step {
        Step(words: String(localized: "Sends \(figure) \(symbol) of round-ups to Relay"),
             detail: String(localized: "Buys \(target) on \(network)"))
    }

    /// A round-up bought on the send's own network, on the exchanges (prd
    /// §1545): the swap's own words, said as the round-up it is.
    /// A send the spend limit's session key signs never buys on the
    /// exchanges (prd §1545): the change is kept, counted, for the next send
    /// Face ID approves.
    static func roundUpKept(_ figure: String, _ symbol: String) -> Step {
        Step(words: String(localized: "Keeps \(figure) \(symbol) of round-ups for a send you approve with Face ID"))
    }

    static func roundUpSwap(_ figure: String, _ symbol: String, atLeast: String, _ bought: String, on exchange: String) -> Step {
        Step(words: String(localized: "Swaps \(figure) \(symbol) of round-ups for at least \(atLeast) \(bought) on \(exchange)"))
    }

    /// Every operation your own keys sign carries the key change
    /// (`YourAccountOp.callData(calls:rotateTo:)`): the shared signer
    /// re-configured to the next Enclave key.
    static func rotate(to key: Int) -> Step {
        Step(words: String(localized: "Moves your account to a new key"),
             detail: String(localized: "This iPhone's key \(key). The old key stops working."))
    }

    static func opens(network: String) -> Step {
        Step(words: String(localized: "Opens your account on \(network)"))
    }

    static var addsRecovery: Step { Step(words: String(localized: "Adds your recovery key")) }
    static var addsSigner: Step { Step(words: String(localized: "Adds your Signer as a second key")) }

    static func setsLimit(periods: Int) -> Step {
        Step(words: String(localized: "Sets your spend limit"),
             detail: String(localized: "\(periods) periods ahead. Over it, and for a swap or a private move, your Signer signs too."))
    }

    static func renewsLimit(periods: Int) -> Step {
        Step(words: String(localized: "Renews your spend limit"),
             detail: String(localized: "\(periods) periods ahead"))
    }

    /// The session key signs under the limit: no key change rides it.
    static var underLimit: Step {
        Step(words: String(localized: "Signed by your spend limit's key"),
             detail: String(localized: "Under your limit, so your Signer is not asked."))
    }

    // MARK: - Hex

    /// "0x5f3c…" in full, lowercase, as ERC-8213 says a digest is shown.
    static func hex(_ bytes: [UInt8]) -> String { "0x" + Keccak256.hexString(bytes) }
}
