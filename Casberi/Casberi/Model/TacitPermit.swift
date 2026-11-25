import Foundation

/// THE PERMIT YOUR CO-SIGNER SIGNS TO MAKE TAC PRIVATE, AND WHAT IS CHECKED
/// BEFORE IT IS ASKED FOR (prd §1971 item 20).
///
/// A deposit to the Tacit chain is proved on this phone by Tacit's own code
/// (`TacitEngine.shieldProve`), and the TAC reaches it through an EIP-2612
/// permit on Tacit's token: your co-signer lets the deposit's inbox take
/// exactly the amount and the leader's fee, until a deadline. The leader
/// then sweeps it and puts the deposit in a block.
///
/// Nothing the engine says is believed on its own word. Before the wallet is
/// asked, the permit must:
/// 1. be on Ethereum, for TAC, from your co-signer;
/// 2. name as spender the inbox the chain's own contract computes for this
///    deposit and its return path (`inboxCall`, read by the app, not the engine);
/// 3. take exactly the amount plus the leader's fee, and a fee within a fifth
///    of the one you were shown (Tacit's own rule);
/// 4. end within two hours;
/// 5. fit in what your co-signer holds.
///
/// Pure (Foundation, `Keccak256`, `EIP712`): `tacit-permit-selftest.sh`
/// compiles it whole.
enum TacitPermit {

    /// TAC on Ethereum (`TacitPocket.tacToken`), its permit domain read off
    /// the token: name "Tacit Token", version "1".
    static let token = "0xa1313eb9f3a445606d9583bcac3ebeb56a858279"
    static let chainId = 1
    static let name = "Tacit Token"
    static let version = "1"

    /// The longest a permit may stand.
    static let longest: TimeInterval = 2 * 3600

    enum Problem: Error, Equatable {
        case notTheCoSigner
        case wrongInbox
        case wrongValue
        case feeRose
        case deadline
        case notEnough
        case overCap
        case malformed
    }

    /// The typed data `eth_signTypedData_v4` takes, every number a decimal
    /// string as the spec allows.
    static func typedData(owner: String, spender: String, value: Decimal, nonce: Decimal, deadline: Int) -> [String: Any] {
        [
            "types": [
                "EIP712Domain": [["name": "name", "type": "string"], ["name": "version", "type": "string"],
                                 ["name": "chainId", "type": "uint256"], ["name": "verifyingContract", "type": "address"]],
                "Permit": [["name": "owner", "type": "address"], ["name": "spender", "type": "address"],
                           ["name": "value", "type": "uint256"], ["name": "nonce", "type": "uint256"],
                           ["name": "deadline", "type": "uint256"]],
            ],
            "primaryType": "Permit",
            "domain": ["name": name, "version": version, "chainId": chainId, "verifyingContract": token],
            "message": ["owner": owner.lowercased(), "spender": spender.lowercased(),
                        "value": text(value), "nonce": text(nonce), "deadline": String(deadline)],
        ]
    }

    /// The digest the wallet's signature must recover to the co-signer over.
    static func digest(_ data: [String: Any]) -> [UInt8]? {
        EIP712.parse(data).flatMap(EIP712.digest)
    }

    /// The checks above. `chainInbox` is the inbox the chain's contract
    /// answered `inboxCall` with; `balance` what the co-signer holds, TAC wei.
    static func check(proved: TacitEngineWire.ShieldProved, quote: TacitEngineWire.ShieldQuote,
                      coSigner: String, owner: String, units: UInt64, chainInbox: String,
                      balance: Decimal, now: Date) -> Problem? {
        guard owner.caseInsensitiveCompare(coSigner) == .orderedSame else { return .notTheCoSigner }
        guard let value = number(proved.value), let fee = number(proved.sweepFee), let shown = number(quote.sweepFee),
              let provedUnits = number(proved.units) else { return .malformed }
        guard provedUnits == Decimal(units) else { return .wrongValue }
        guard proved.inbox.lowercased() == chainInbox.lowercased(), isAddress(chainInbox) else { return .wrongInbox }
        guard value == Decimal(units) * pow(Decimal(10), 10) + fee else { return .wrongValue }
        guard fee <= shown + shown / 5 + pow(Decimal(10), 10) else { return .feeRose }
        let left = TimeInterval(proved.deadline) - now.timeIntervalSince1970
        guard left > 60, left <= longest else { return .deadline }
        if let cap = quote.cap.flatMap(number), Decimal(units) > cap { return .overCap }
        guard balance >= value else { return .notEnough }
        return nil
    }

    /// The checks for TAC your Casberi account pays into the inbox itself, no
    /// permit: the proof is for this amount, the inbox is the chain's, the
    /// account holds it, and it is under Tacit's cap. The send that pays it
    /// is your account's own, checked and simulated as every send is.
    static func checkTransfer(proved: TacitEngineWire.ShieldProved, quote: TacitEngineWire.ShieldQuote,
                              units: UInt64, chainInbox: String, balance: Decimal) -> Problem? {
        guard let provedUnits = number(proved.units) else { return .malformed }
        guard provedUnits == Decimal(units) else { return .wrongValue }
        guard proved.inbox.lowercased() == chainInbox.lowercased(), isAddress(chainInbox) else { return .wrongInbox }
        if let cap = quote.cap.flatMap(number), Decimal(units) > cap { return .overCap }
        guard balance >= Decimal(units) * pow(Decimal(10), 10) else { return .notEnough }
        return nil
    }

    /// The call that asks the chain's contract which inbox a deposit and
    /// its return path make: `inbox(shares, amount, cx, cy, body, back)`.
    static func inboxCall(_ d: TacitEngineWire.Deposit, back: String) -> String? {
        let selector = Keccak256.hash(Array("inbox(uint256,uint256,bytes32,bytes32,bytes32,bytes32)".utf8)).prefix(4)
        guard let shares = word(d.shares), let amount = word(d.amount), let cx = word(d.cx), let cy = word(d.cy),
              let body = word(d.body), let b = word(back) else { return nil }
        return "0x" + Keccak256.hexString(Array(selector)) + shares + amount + cx + cy + body + b
    }

    /// `nonces(owner)` on TAC.
    static func noncesCall(_ owner: String) -> String? {
        guard let w = word(owner) else { return nil }
        return "0x7ecebe00" + w
    }

    /// A 32-byte word as returned by `eth_call`, as an address.
    static func address(fromWord hex: String) -> String? {
        let body = hex.lowercased().replacingOccurrences(of: "0x", with: "")
        guard body.count == 64, body.prefix(24).allSatisfy({ $0 == "0" }) else { return nil }
        return "0x" + body.suffix(40)
    }

    /// 0x-hex as a whole number; nil for anything else.
    static func number(_ hex: String) -> Decimal? {
        guard hex.hasPrefix("0x"), hex.count > 2, hex.count <= 66 else { return nil }
        var n = Decimal(0)
        for c in hex.dropFirst(2) {
            guard let d = c.hexDigitValue else { return nil }
            n = n * 16 + Decimal(d)
        }
        return n
    }

    static func text(_ d: Decimal) -> String {
        NSDecimalNumber(decimal: d).stringValue
    }

    static func isAddress(_ s: String) -> Bool {
        s.count == 42 && s.hasPrefix("0x") && s.dropFirst(2).allSatisfy(\.isHexDigit)
    }

    /// A value as one 32-byte ABI word, hex without 0x.
    private static func word(_ hex: String) -> String? {
        let body = hex.lowercased().replacingOccurrences(of: "0x", with: "")
        guard !body.isEmpty, body.count <= 64, body.allSatisfy(\.isHexDigit) else { return nil }
        return String(repeating: "0", count: 64 - body.count) + body
    }
}
