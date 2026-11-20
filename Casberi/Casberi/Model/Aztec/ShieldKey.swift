import Foundation
import P256K

/// **INTO AZTEC WITHOUT A CO-SIGNER, UP TO $100 A DAY (prd §1920).**
///
/// Shield takes a sign-in only from one key's signature, so your account (a
/// Safe) can never sign in (§1890), and until now the way in was your
/// co-signer's wallet. This is one ordinary key of your own that can: Shield
/// screens it like any address and lets it move in up to $100 a day with no
/// score (measured, §1918a). Your account hands it what it moves and the gas
/// for its two sends; it signs in, approves Shield's portal and deposits.
///
/// **ONE KEY, KEPT, NEVER A FRESH ONE PER MOVE.** Shield's $100 is per address
/// per day; a new key each time would walk around its rule. The key is
/// derived from the private root in iCloud Keychain (`PrivateRoot.shieldKey`),
/// so it is the same key on every phone of yours and nothing new is stored;
/// it is made for each signature and zeroed.
///
/// **IT CAN ONLY DO THIS.** What it signs on chain must pass
/// `FreshTx.shieldAllowed`: a Shield token's approval of its own portal, a
/// deposit into a Shield portal, or what it holds sent back to your own
/// account. Its one message is Shield's sign-in (`ShieldBridge.siwe`).
enum ShieldKey {
    enum Failure: Error, Equatable { case noRoot, curve, refused(String) }

    /// The private root this key comes from: the current one.
    static var rootID: String? { PrivateRootKey.currentID }

    private static func key() throws -> P256K.Recovery.PrivateKey {
        guard let id = rootID, var root = PrivateRootKey.root(id) else { throw Failure.noRoot }
        defer { for i in root.indices { root[i] = 0 } }
        guard var k = PrivateRoot.shieldKey(root) else { throw Failure.curve }
        defer { for i in k.indices { k[i] = 0 } }
        return try P256K.Recovery.PrivateKey(dataRepresentation: Data(k), format: .uncompressed)
    }

    /// Its address, checksummed; nil with no private root on this phone.
    static var address: String? {
        guard let k = try? key() else { return nil }
        return SignerKey.ethereumAddress(uncompressedPublicKey: [UInt8](k.publicKey.dataRepresentation))
    }

    /// Shield's sign-in, signed: `personal_sign` of the SIWE message, 65 bytes
    /// (r ‖ s ‖ v, v 27 or 28). Nothing but a sign-in to Shield is signed here.
    static func signIn(_ message: String) throws -> [UInt8] {
        guard message.hasPrefix("shield.human.tech wants you to sign in with your Ethereum account:\n") else {
            throw Failure.refused("not Shield's sign-in")
        }
        let signature = try key().signature(for: HashDigest(NearAIVerify.personalSignDigest(message)))
        let compact = try signature.compactRepresentation
        let rs = [UInt8](compact.signature)
        guard rs.count == 64 else { throw Failure.curve }
        return rs + [UInt8(27 + compact.recoveryId)]
    }

    /// Signs one allowed move at `gas` and sends it on Ethereum; its hash.
    /// The fee ceiling fits what the key holds (as a fresh address's, prd
    /// §1894): under the price now, it is not sent.
    static func send(to: String, data: String, value: String = "0x0", gas: Int, account: String) async throws -> String {
        let net = PrivacyNetwork.ethereum
        guard let from = address else { throw Failure.noRoot }
        let nonce = try await PrivateRPC.call(net, "eth_getTransactionCount", [from, "pending"]) as? String ?? "0x0"
        let price = UInt64(try await PrivateRPC.decimal(net, "eth_gasPrice", [])) ?? 0
        let tip = min(max(price / 10, 1_000_000), price)
        var maxFee = price * 2
        let held = UInt64(try await PrivateRPC.decimal(net, "eth_getBalance", [from, "latest"])) ?? 0
        let carried = UInt64(PrivateMoney.decimal(hex: value)) ?? 0
        guard held >= carried, gas > 0 else { throw Failure.refused("it holds too little ETH") }
        let fits = (held - carried) / UInt64(gas)
        if fits < maxFee {
            guard fits >= price else { throw Failure.refused("its gas rose past what it holds") }
            maxFee = fits
        }
        guard let tx = FreshTx.Tx(shield: account, nonce: nonce, maxPriorityFeePerGas: "0x" + String(tip, radix: 16),
                                  maxFeePerGas: "0x" + String(maxFee, radix: 16), gas: "0x" + String(gas, radix: 16),
                                  to: to, value: value, data: data) else { throw Failure.refused("not a Shield key's move") }
        let k = try key()
        let signature = try k.signature(for: HashDigest(tx.signingHash))
        let compact = try signature.compactRepresentation
        let rs = [UInt8](compact.signature)
        guard rs.count == 64, let raw = tx.signed(yParity: Int(compact.recoveryId), r: Array(rs[0..<32]), s: Array(rs[32..<64])) else {
            throw Failure.curve
        }
        let hash = "0x" + Keccak256.hexString(Keccak256.hash(raw))
        do {
            _ = try await PrivateRPC.call(net, "eth_sendRawTransaction", [TestnetTx.hex(raw)])
        } catch FreshSigner.Failure.refused(let why) where why.lowercased().contains("already known") {}
        NSLog("shieldKey| sent | %@ | gas %d", hash, gas)
        return hash
    }

    // MARK: - Its day (prd §1922)

    private static let dayKey = "aztec.shieldKey.day"

    /// Dollars the key moved into Aztec today (UTC), as this phone counted
    /// them: what is left of Shield's $100 is read from this, never by asking
    /// Shield for a limit (a limit asked counts against the day, §1918a).
    static func movedToday(now: Date = .now) -> Double {
        guard let kept = UserDefaults.standard.dictionary(forKey: dayKey),
              kept["day"] as? String == day(now) else { return 0 }
        return kept["usd"] as? Double ?? 0
    }

    static func noteMoved(_ usd: Double, now: Date = .now) {
        UserDefaults.standard.set(["day": day(now), "usd": movedToday(now: now) + usd], forKey: dayKey)
    }

    private static func day(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The gas its two sends are held to: an approval (measured at ~55K for a
    /// fresh address's, `FreshTx.approveGas`) and Shield's deposit (170K to
    /// 175K, §1700 measurements), each with room.
    static let approveGas = FreshTx.approveGas
    static let depositGas = 260_000
}
