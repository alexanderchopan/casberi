import Foundation

/// Renewing a followed name — PREPARED here, signed somewhere else
/// (2026-08-31, prd §540; paid in a stablecoin since ENSv2, prd §1585). The
/// §112 preparing surface, second instance: `WalletPrepare` does this for an
/// approval's revoke, and this does it for a `.eth` renewal. Casberi reads the
/// price, encodes the transactions, quotes the fee, and hands them to the
/// person's own wallet. It signs nothing and holds no key.
///
/// Foundation-only BY DESIGN so `scripts/ens-renew-selftest.sh` compiles it
/// WHOLE and unmodified. Nothing here fetches; `ENSRenewPrepare` does the
/// reads and calls in.
///
/// **WHY THIS FILE IS THE DANGEROUS ONE.** Its transactions move REAL MONEY
/// when signed, and a wrong byte here is not a crash: it is a well-formed
/// transaction that a wallet will happily sign and a chain will happily
/// execute, doing something nobody asked for. That is why the ABI encoding
/// below is pinned against vectors produced by an independent implementation
/// (viem) rather than merely eyeballed.
///
/// **EVERY CONSTANT HERE WAS MEASURED ON MAINNET 2026-10-28**, the day after
/// ENSv2 activated, against the verified sources Sourcify holds for both
/// contracts. See each.
enum ENSRenew {

    // MARK: - The contracts

    /// Who renews a name depends on whether its owner has moved it to ENSv2.
    ///
    /// **MEASURED 2026-10-28.** An unmigrated name is `RESERVED` in the ENSv2
    /// registry and only `ETHRenewerV1` will renew it (`isRenewable` answers 1
    /// there and 0 on the registrar, casberi.eth and vitalik.eth); a migrated
    /// one is `REGISTERED` and only `ETHRegistrar` will (nick.eth, the other
    /// way round). Both take the same `renew` and the same price read, so the
    /// one fact that differs is the address, and it is asked of the chain per
    /// quote rather than guessed: a name can migrate between two reads.
    enum Contract: String, CaseIterable {
        case renewer
        case registrar

        var address: String {
            switch self {
            // Owns the v1 BaseRegistrar since ENSv2's activation.
            case .renewer:   return "0x56c447F308F463A01121C41E72b0E7e7557fCb68"
            // ENSv2's `.eth` registrar (ENS's deployments page, mainnet).
            case .registrar: return "0xD6D8369e55c94Ae8AFA714E6cF7AB5bE54D5CC81"
            }
        }
    }

    /// The tokens ENS takes for a renewal. **MEASURED 2026-10-28**:
    /// `StandardRentPriceOracle.isPaymentToken` answers 1 for USDC and DAI and
    /// 0 for USDT, USDS, PYUSD, USDe, GHO, FRAX, RLUSD, EURC and WETH. ETH is
    /// not one: `renew` is nonpayable, so a transaction carrying ETH reverts.
    enum Token: String, CaseIterable {
        case usdc
        case dai

        var symbol: String {
            switch self {
            case .usdc: return "USDC"
            case .dai:  return "DAI"
            }
        }

        var address: String {
            switch self {
            case .usdc: return "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
            case .dai:  return "0x6B175474E89094C44Da98b954EedeAC495271d0F"
            }
        }

        /// The oracle's own ratios agree (USDC 1/10⁶, DAI 10⁶/1 over a
        /// 12-decimal dollar), and so does each token's `decimals()`.
        var decimals: Int {
            switch self {
            case .usdc: return 6
            case .dai:  return 18
            }
        }
    }

    /// Kept as a switch rather than deleted, so turning the card off again is
    /// one line if ENS moves the renewal a second time (§1573 did exactly
    /// that, and the sheet drew `ENSRenewDoor` in its place).
    static let prepares = true

    /// Derived from the signatures rather than pasted as magic constants
    /// (`AerodromeDeFi`'s precedent), so the harness pins each derivation
    /// against the selector found in BOTH deployed contracts' bytecode.
    static var renewSignature: String { "renew((string,uint64,bytes32),address)" }
    static var priceSignature: String { "getRenewPrice(string,uint64,address)" }
    static var isRenewableSignature: String { "isRenewable(string)" }
    static var approveSignature: String { "approve(address,uint256)" }
    static var allowanceSignature: String { "allowance(address,address)" }
    static var balanceSignature: String { "balanceOf(address)" }

    /// No referrer. A zero word — this app is nobody's referrer and inventing
    /// one would silently attribute somebody's renewal to a party they never
    /// chose.
    static let noReferrer = String(repeating: "0", count: 64)

    /// Ethereum mainnet. `.eth` names live in exactly one place; there is no
    /// chain picker here and there must never be one.
    static let chainID = 1

    // MARK: - How long

    /// ENS prices by the 365-day year, NOT the calendar year — `duration` is
    /// a raw number of seconds added to the expiry, so a leap year does not
    /// buy an extra day and must not be drawn as though it did.
    static let year: Int = 31_536_000

    enum Term: Int, CaseIterable, Identifiable {
        case oneYear = 1
        case twoYears = 2
        case fiveYears = 5

        var id: Int { rawValue }
        var seconds: Int { rawValue * ENSRenew.year }
        var label: String {
            rawValue == 1
                ? String(localized: "1 year")
                : String(localized: "\(rawValue) years")
        }
    }

    // MARK: - Amounts

    /// A token amount as the chain wrote it: one 32-byte word, never a
    /// `Double`. Five years of a three-letter name in DAI is 3,200 × 10¹⁸, past
    /// what a `UInt64` holds, and a `Double` rounds a wei figure; either way
    /// the approval would no longer match what `renew` pulls.
    struct Amount: Equatable, Comparable {
        /// 64 lowercase hex digits.
        let word: String

        /// From an `eth_call` reply. nil for a revert or an empty reply ("0x"),
        /// which would otherwise read as ZERO — a free renewal shown to
        /// somebody about to sign.
        init?(reply: String) {
            guard reply.hasPrefix("0x") else { return nil }
            let hex = reply.dropFirst(2).lowercased()
            guard hex.count >= 64 else { return nil }
            let first = String(hex.prefix(64))
            guard first.allSatisfy(\.isHexDigit) else { return nil }
            word = first
        }

        var isZero: Bool { word.allSatisfy { $0 == "0" } }

        /// Equal-length lowercase hex compares as the numbers it spells.
        static func < (a: Amount, b: Amount) -> Bool { a.word < b.word }

        /// The amount in whole tokens, exactly.
        func decimal(_ token: Token) -> Decimal {
            var units = Decimal(0)
            for c in word { units = units * 16 + Decimal(Int(String(c), radix: 16) ?? 0) }
            var scale = Decimal(1)
            for _ in 0..<token.decimals { scale *= 10 }
            return units / scale
        }
    }

    /// "8.000021 USDC". Up to six places, trailing zeros trimmed to two, and
    /// ROUNDED UP: the price really is $8.000021 (measured), and a figure
    /// shown as less than what the approval takes is a number people believe
    /// (§83) on the one screen where they are deciding to spend.
    static func tokenLine(_ amount: Amount, _ token: Token) -> String {
        var value = amount.decimal(token)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 6, .up)
        let figure = tokenFormatter.string(from: rounded as NSDecimalNumber) ?? "\(rounded)"
        return "\(figure) \(token.symbol)"
    }

    private static let tokenFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 6
        return formatter
    }()

    // MARK: - The calldata

    /// `renew((label, duration, referrer), paymentToken)`.
    ///
    /// **THE LABEL, NEVER THE NAME.** The contract hashes what it is given, so
    /// handing it `"vitalik.eth"` renews the label *"vitalik.eth"* — a
    /// different, almost certainly unregistered entry — and this refuses
    /// anything with a dot in it rather than trusting callers.
    ///
    /// The tuple holds a string, so it is DYNAMIC: the head is an offset to
    /// it (0x40, two head words) and the token; inside the tuple the string's
    /// own offset is 0x60 (three words: offset, duration, referrer), relative
    /// to the tuple, not to the calldata.
    static func calldata(label: String, term: Term, token: Token) -> String? {
        guard isLabel(label) else { return nil }
        return "0x" + selector(renewSignature)
            + word(0x40)
            + addressWord(token.address)
            + word(0x60)
            + word(term.seconds)
            + noReferrer
            + encodedString(label)
    }

    /// `getRenewPrice(label, duration, paymentToken)`: three head words, the
    /// string's offset 0x60. Spelled out rather than shared with `calldata`,
    /// whose offsets differ — a shared constant would be wrong for one.
    static func priceCalldata(label: String, term: Term, token: Token) -> String? {
        guard isLabel(label) else { return nil }
        return "0x" + selector(priceSignature)
            + word(0x60)
            + word(term.seconds)
            + addressWord(token.address)
            + encodedString(label)
    }

    static func isRenewableCalldata(label: String) -> String? {
        guard isLabel(label) else { return nil }
        return "0x" + selector(isRenewableSignature) + word(0x20) + encodedString(label)
    }

    /// An approval for EXACTLY the renewal price, never more.
    ///
    /// `renew` pulls the price with `safeTransferFrom` (read from the verified
    /// source), so the contract needs an allowance first. The oracle prices in
    /// dollars at a fixed ratio per token — no oracle drift, unlike §540's ETH
    /// price — so the price read now is the price taken, and a buffer would
    /// only leave a standing allowance behind. An open-ended one is what this
    /// app's own approvals card flags as exposure.
    static func approveCalldata(spender: Contract, amount: Amount) -> String {
        "0x" + selector(approveSignature) + addressWord(spender.address) + amount.word
    }

    static func allowanceCalldata(owner: String, spender: Contract) -> String? {
        guard isAddress(owner) else { return nil }
        return "0x" + selector(allowanceSignature) + addressWord(owner) + addressWord(spender.address)
    }

    static func balanceCalldata(owner: String) -> String? {
        guard isAddress(owner) else { return nil }
        return "0x" + selector(balanceSignature) + addressWord(owner)
    }

    // MARK: - The transactions

    /// The wallet-ready renewal, in the same JSON object shape `WalletPrepare`
    /// hands out for a revoke.
    ///
    /// **`value` is 0x0 and must stay so.** `renew` is nonpayable: the money
    /// moves as a token transfer the contract pulls, and any ETH attached
    /// reverts the call after the person has paid gas.
    static func renewJSON(from: String, contract: Contract, label: String, term: Term,
                          token: Token) -> String? {
        guard isAddress(from), let data = calldata(label: label, term: term, token: token)
        else { return nil }
        return object(from: from, to: contract.address, data: data)
    }

    static func approveJSON(from: String, contract: Contract, token: Token,
                            amount: Amount) -> String? {
        guard isAddress(from), !amount.isZero else { return nil }
        return object(from: from, to: token.address,
                      data: approveCalldata(spender: contract, amount: amount))
    }

    /// What Copy hands over: the renewal alone when the allowance already
    /// covers it, else the approval and then the renewal, in that order, as
    /// one JSON array — the order a wallet must send them in, and the shape
    /// `wallet_sendCalls` takes.
    static func handoffJSON(from: String, contract: Contract, label: String, term: Term,
                            token: Token, amount: Amount, needsApproval: Bool) -> String? {
        guard let renew = renewJSON(from: from, contract: contract, label: label,
                                    term: term, token: token) else { return nil }
        guard needsApproval else { return renew }
        guard let approve = approveJSON(from: from, contract: contract, token: token,
                                        amount: amount) else { return nil }
        return "[" + approve + ", " + renew + "]"
    }

    private static func object(from: String, to: String, data: String) -> String {
        """
        {"chainId": \(chainID), "data": "\(data)", "from": "\(from)", \
        "to": "\(to)", "value": "0x0"}
        """
    }

    // MARK: - Words

    /// "0.0020 ETH" — the network fee, which is still paid in ETH.
    static func ethLine(_ wei: Double) -> String {
        String(format: "%.4f ETH", wei / 1e18)
    }

    /// The one sentence this card owes that no other prepare surface does.
    ///
    /// **Renewing is PERMISSIONLESS** — read in the verified ENSv2 source:
    /// `renew` takes the token from whoever calls and extends the name, with
    /// no owner check. So this card can genuinely renew a name somebody else
    /// owns, and **paying does not transfer the name.** Nobody should learn
    /// that after signing.
    static func ownershipNote(isYours: Bool) -> String? {
        isYours ? nil : String(localized: "Renewing pays for this name and does not transfer it — it stays with its current owner.")
    }

    // MARK: - ABI

    private static func isLabel(_ label: String) -> Bool {
        !label.isEmpty && !label.contains(".") && !label.contains(where: \.isWhitespace)
    }

    private static func isAddress(_ s: String) -> Bool {
        s.count == 42 && s.hasPrefix("0x") && s.dropFirst(2).allSatisfy(\.isHexDigit)
    }

    /// A `String` as an ABI dynamic `string`: a length word, then the UTF-8
    /// bytes, right-padded to a whole number of words.
    static func encodedString(_ s: String) -> String {
        let bytes = Array(s.utf8)
        // THE LENGTH IS IN BYTES, NOT CHARACTERS. `"café"` is four characters
        // and five bytes; encoding `4` there produces a transaction that is
        // well-formed, signable, and renews a truncated label. Pinned.
        var hex = word(bytes.count)
        hex += bytes.map { String(format: "%02x", $0) }.joined()
        // Pad to the next word boundary — and add NOTHING when the length is
        // already a multiple of 32. The naive `32 - count % 32` appends a
        // whole dead word on a 32-byte label. Also pinned.
        let remainder = bytes.count % 32
        if remainder != 0 { hex += String(repeating: "00", count: 32 - remainder) }
        return hex
    }

    /// A `UInt` as a 32-byte ABI word.
    static func word(_ n: Int) -> String { String(format: "%064x", n) }

    /// An address left-padded to a word, lowercased (ABI does not checksum).
    static func addressWord(_ address: String) -> String {
        String(repeating: "0", count: 24) + address.dropFirst(2).lowercased()
    }

    /// A function selector: the first four bytes of the signature's Keccak-256.
    static func selector(_ signature: String) -> String {
        Keccak256.hexString(Array(Keccak256.hash(Array(signature.utf8)).prefix(4)))
    }
}
