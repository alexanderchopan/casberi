import Foundation

/// **SHIELD, THE BRIDGE MOVE USES INTO AND OUT OF AZTEC (prd §1700b, §1700d,
/// §1700e).** Read from Shield's own web app, 2026-11-04 (its API is the site's
/// own `/api/…`):
///   - `GET /api/attestation/l1-eligibility?address=` — public: eligible or not,
///     by which method, sanctioned, the Passport score and its threshold (20).
///   - `GET /api/auth/nonce`, then a Sign-In-With-Ethereum message from the
///     Safe (ERC-1271, `YourAccountMessage`) to `POST /api/auth/authenticate` →
///     a session token.
///   - `POST /api/attestation/passport` — Shield's signed limit for one move
///     (`L1_TO_L2`: an Ethereum signature for the portal's deposit; `L2_TO_L1`:
///     an Aztec one for the bridge's exit). Casberi asks only for the Passport
///     method, never Proof of Clean Hands (government ID, §1700e item 1).
/// The deposit is `depositToAztecPrivate(amount, secretHash, cleanHands, passport)`
/// with `cleanHands` blank, as Shield's own client sends it.
enum ShieldBridge {
    static let base = "https://shield.human.tech"
    /// `NetworkReach` service name.
    static let service = "Shield bridge"

    struct Asset: Equatable {
        let symbol: String
        let decimals: Int
        /// The token on Ethereum, Shield's portal for it, its bridge on Aztec.
        let ethToken: String
        let portal: String
        let bridge: String
    }

    static let assets = [
        Asset(symbol: "USDC", decimals: 6, ethToken: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
              portal: "0x6c34d66633ffc36be2dfddc7b0c652fbb305e74c",
              bridge: "0x023aafff7595c5698625486a010e385144a4a960d268df8ccb205f9134afd775"),
        Asset(symbol: "WETH", decimals: 18, ethToken: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
              portal: "0x477a911f76c44a5d3e5e692c59945263f61426c4",
              bridge: "0x267a10e5463760e88f487a719bd38f09c46ec87260c51b0affc88fd9ff1d9ef4"),
    ]

    /// `DepositToAztecPrivate(uint256 amount, uint256 fee, bytes32 secretHash, bytes32 key, uint256 index)`
    static let depositTopic = "0xec915cbb614f4e8d4e71c5f18aa49dbb6e41d25ab75f44560c28ea05916168c3"

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct Eligibility: Equatable {
        let eligible: Bool
        let sanctioned: Bool
        let score: Double
        let threshold: Double
        let maxUSD: Double
        let reason: String?
    }

    /// EIP-4361, as the `siwe` library Shield uses writes it.
    static func siwe(account: String, aztec: String, nonce: String, now: Date) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return """
        shield.human.tech wants you to sign in with your Ethereum account:
        \(account)

        Sign in to Aztec Bridge to manage your cross-chain operations.

        URI: \(base)
        Version: 1
        Chain ID: 1
        Nonce: \(nonce)
        Issued At: \(iso.string(from: now))
        Expiration Time: \(iso.string(from: now.addingTimeInterval(300)))
        Resources:
        - \(base)/aztec/address/\(aztec.lowercased())
        """
    }

    struct Limit: Equatable {
        let maxAmount: String
        let nonce: String
        let deadline: String
        /// Hex: the Ethereum signature (deposit). Empty for an exit.
        let signature: String
        /// The Aztec signature (exit): 64 bytes, Schnorr, as Shield sends it.
        var aztecSignature: [Int]? = nil
    }

    enum Direction: String { case intoAztec = "L1_TO_L2", outOfAztec = "L2_TO_L1" }

    // MARK: - The deposit's calldata

    /// `depositToAztecPrivate(uint256, bytes32, (uint256,uint256,uint256,bytes), (uint256,uint256,uint256,bytes))`
    /// with `cleanHands` blank and `passport` Shield's limit.
    static func depositCalldata(units: String, secretHash: String, limit: Limit) -> String? {
        guard let amount = word(decimal: units), let hash = word(hex: secretHash),
              let max = word(decimal: limit.maxAmount), let nonce = word(decimal: limit.nonce),
              let deadline = word(decimal: limit.deadline), let sig = bytes(hex: limit.signature) else { return nil }
        let zero = String(repeating: "0", count: 64)
        func tuple(_ a: String, _ b: String, _ c: String, _ data: [UInt8]) -> String {
            let padded = data + [UInt8](repeating: 0, count: (32 - data.count % 32) % 32)
            return a + b + c + word(int: 4 * 32) + word(int: data.count) + padded.map { String(format: "%02x", $0) }.joined()
        }
        let cleanHands = tuple(zero, zero, zero, [])
        let passport = tuple(max, nonce, deadline, sig)
        let head = 4 * 32
        return "0x62470a10" + amount + hash + word(int: head) + word(int: head + cleanHands.count / 2) + cleanHands + passport
    }

    /// The portal's event in a receipt: (amount after fee, key, leaf index) as text.
    static func message(in receipt: [String: Any], portal: String) -> (amount: String, key: String, index: String)? {
        for log in receipt["logs"] as? [[String: Any]] ?? [] {
            guard (log["address"] as? String)?.lowercased() == portal.lowercased(),
                  (log["topics"] as? [String])?.first?.lowercased() == depositTopic,
                  let data = log["data"] as? String, data.count == 2 + 64 * 5 else { continue }
            let words = stride(from: 2, to: data.count, by: 64).map { i -> String in
                let a = data.index(data.startIndex, offsetBy: i)
                return String(data[a..<data.index(a, offsetBy: 64)])
            }
            guard let amount = decimal(hex: words[0]), let index = decimal(hex: words[4]) else { return nil }
            return (amount, "0x" + words[3], index)
        }
        return nil
    }

    // MARK: - Words

    static func word(int: Int) -> String { String(format: "%064lx", int) }
    static func word(hex: String) -> String? {
        let body = hex.lowercased().hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard body.count <= 64, body.allSatisfy(\.isHexDigit) else { return nil }
        return String(repeating: "0", count: 64 - body.count) + body
    }
    /// A base-10 integer as one 32-byte word (hex), or nil when it is not one.
    static func word(decimal: String) -> String? {
        let s = decimal.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, s.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        var acc = [UInt8](repeating: 0, count: 32)
        for ch in s {
            var carry = Int(ch.asciiValue! - 48)
            for i in stride(from: 31, through: 0, by: -1) {
                let v = Int(acc[i]) * 10 + carry
                acc[i] = UInt8(v & 0xff); carry = v >> 8
            }
            guard carry == 0 else { return nil } // past 2^256
        }
        return acc.map { String(format: "%02x", $0) }.joined()
    }
    static func bytes(hex: String) -> [UInt8]? {
        var s = Substring(hex.lowercased())
        if s.hasPrefix("0x") { s = s.dropFirst(2) }
        guard s.count % 2 == 0, s.allSatisfy(\.isHexDigit) else { return nil }
        var out: [UInt8] = []; var i = s.startIndex
        while i < s.endIndex { let j = s.index(i, offsetBy: 2); out.append(UInt8(s[i..<j], radix: 16)!); i = j }
        return out
    }
    static func decimal(hex: String) -> String? {
        var value = Decimal(0)
        for c in hex.lowercased() { guard let d = c.hexDigitValue else { return nil }; value = value * 16 + Decimal(d) }
        return NSDecimalNumber(decimal: value).stringValue
    }

    // MARK: - Out of Aztec

    /// `withdraw(address,uint256,bool,uint256,uint256,uint256,bytes32[])` on the portal.
    static let withdrawSelector = "0xaab5a3f1"
    /// The outbox's `getRootData(uint256 epoch, uint256 numCheckpointsInEpoch)`: zero until that epoch is proven.
    static let rootDataSelector = "0x765a2b33"
    /// The outbox's `hasMessageBeenConsumedAtEpoch(uint256 epoch, uint256 leafId)`.
    static let consumedSelector = "0xd70bd71b"

    static func withdrawCalldata(recipient: String, units: String, epoch: String, checkpoints: String, leaf: String, path: [String]) -> String? {
        guard let to = word(hex: recipient), let amount = word(decimal: units), let e = word(decimal: epoch),
              let n = word(decimal: checkpoints), let l = word(decimal: leaf) else { return nil }
        let siblings = path.compactMap { word(hex: $0) }
        guard siblings.count == path.count else { return nil }
        return withdrawSelector + to + amount + word(int: 0) + e + n + l + word(int: 7 * 32) + word(int: siblings.count) + siblings.joined()
    }

    /// 2^depth + leaf, in decimal.
    static func leafID(leaf: String, depth: Int) -> String? {
        guard depth < 120, let l = Decimal(string: leaf) else { return nil }
        return NSDecimalNumber(decimal: pow(Decimal(2), depth) + l).stringValue
    }
}
