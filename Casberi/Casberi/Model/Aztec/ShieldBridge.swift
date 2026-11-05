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

    // MARK: - Where you stand (public, no sign-in)

    struct Eligibility: Equatable {
        let eligible: Bool
        let sanctioned: Bool
        let score: Double
        let threshold: Double
        let maxUSD: Double
        let reason: String?
    }

    static func eligibility(_ address: String) async -> Eligibility? {
        let url = "\(base)/api/attestation/l1-eligibility?address=\(address)"
        let (json, status) = await IngestSupport.requestJSON(url, service: service)
        guard status == 200, let o = json as? [String: Any] else { return nil }
        return Eligibility(eligible: o["eligible"] as? Bool ?? false, sanctioned: o["sanctioned"] as? Bool ?? false,
                           score: (o["passportScore"] as? NSNumber)?.doubleValue ?? 0,
                           threshold: (o["passportThreshold"] as? NSNumber)?.doubleValue ?? 20,
                           maxUSD: (o["passportMaxUsd"] as? NSNumber)?.doubleValue ?? 1000,
                           reason: o["reason"] as? String)
    }

    // MARK: - Signing in with the Safe

    @MainActor private static var session: (account: String, token: String, until: Date)?

    /// A session token for `account`, signing in (Face ID) when there is none.
    @MainActor
    static func token(account: String, aztec: String) async throws -> String {
        if let s = session, s.account.lowercased() == account.lowercased(), s.until > .now { return s.token }
        guard let (data, http) = await IngestSupport.sendRequest(URLRequest(url: URL(string: "\(base)/api/auth/nonce")!), service: service),
              http.statusCode == 200, let nonce = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !nonce.isEmpty else {
            throw Failure(message: String(localized: "Shield did not answer"))
        }
        let message = siwe(account: EIP55.checksum(account), aztec: aztec, nonce: nonce, now: .now)
        let signature = try await YourAccountMessage.signText(message, on: YourAccountOp.ethereum, account: account,
                                                              reason: String(localized: "Sign in to Shield with your account"))
        let body: [String: Any] = [
            "message": message, "signature": "0x" + signature.map { String(format: "%02x", $0) }.joined(),
            "l1LoginMethod": "wallet", "l1WalletProvider": "casberi",
            "l2LoginMethod": "wallet", "l2WalletProvider": "casberi", "l2NetworkVerified": true,
        ]
        let (json, status) = await IngestSupport.requestJSON("\(base)/api/auth/authenticate", method: "POST", body: body, service: service)
        guard status == 200, let token = (json as? [String: Any])?["token"] as? String else {
            let why = ((json as? [String: Any])?["message"] as? String) ?? ((json as? [String: Any])?["error"] as? String)
            throw Failure(message: why.map { String(localized: "Shield refused the sign-in: \($0)") }
                          ?? String(localized: "Shield did not accept your account's signature"))
        }
        session = (account, token, Date.now.addingTimeInterval(20 * 60))
        return token
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

    // MARK: - Shield's signed limit

    struct Limit: Equatable {
        let maxAmount: String
        let nonce: String
        let deadline: String
        /// Hex: an Ethereum signature (deposit) or an Aztec one (exit).
        let signature: String
    }

    enum Direction: String { case intoAztec = "L1_TO_L2", outOfAztec = "L2_TO_L1" }

    @MainActor
    static func limit(_ direction: Direction, asset: Asset, units: String, account: String, aztec: String) async throws -> Limit {
        let token = try await token(account: account, aztec: aztec)
        var body: [String: Any] = ["portalAddress": asset.portal, "direction": direction.rawValue]
        if direction == .intoAztec {
            body["amount"] = units; body["tokenSymbol"] = asset.symbol; body["tokenDecimals"] = asset.decimals
        } else {
            body["bridgeAddress"] = asset.bridge
        }
        let (json, status) = await IngestSupport.requestJSON("\(base)/api/attestation/passport", method: "POST", body: body,
                                                            headers: ["Authorization": "Bearer \(token)"], service: service)
        guard status == 200, let o = json as? [String: Any],
              let signature = (direction == .intoAztec ? o["l1Signature"] : o["l2Signature"]) as? String else {
            if status == 401 { session = nil }
            let why = ((json as? [String: Any])?["message"] as? String) ?? ((json as? [String: Any])?["error"] as? String)
            throw Failure(message: why ?? String(localized: "Shield did not give a limit for this move"))
        }
        return Limit(maxAmount: string(o["maxAmount"]), nonce: string(o["nonce"]), deadline: string(o["deadline"]), signature: signature)
    }

    private static func string(_ any: Any?) -> String {
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return "0"
    }

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
    static func word(decimal: String) -> String? {
        SafeABI.word(uint256: decimal).map { $0.map { String(format: "%02x", $0) }.joined() }
    }
    static func bytes(hex: String) -> [UInt8]? { SafeABI.hexBytes(hex) }
    static func decimal(hex: String) -> String? {
        var value = Decimal(0)
        for c in hex.lowercased() { guard let d = c.hexDigitValue else { return nil }; value = value * 16 + Decimal(d) }
        return NSDecimalNumber(decimal: value).stringValue
    }
}

// MARK: - Into Aztec

extension ShieldBridge {
    /// Moves `units` of `asset` from your Safe into your Aztec account,
    /// privately: where you stand, Shield's signed limit (signing in with the
    /// Safe, Face ID), then one Safe operation — approve and the portal's
    /// deposit — through `privateCalls` (simulated, Face ID). The claim on Aztec
    /// follows in `settle()` once Aztec has the message.
    @MainActor
    static func deposit(_ asset: Asset, units: String, stage: @escaping @Sendable (YourAccountChain.Stage) async -> Void) async throws -> AztecAccountStore.ShieldDeposit {
        guard !DemoMode.isActive else { throw Failure(message: String(localized: "The demo moves nothing")) }
        guard let account = YourAccountKey.address else { throw Failure(message: String(localized: "There is no account on this iPhone")) }
        guard let standing = await eligibility(account) else { throw Failure(message: String(localized: "Shield did not answer")) }
        guard standing.eligible else {
            throw Failure(message: standing.sanctioned
                ? String(localized: "Shield will not take money from this account")
                : String(localized: "Shield needs a Human Passport score of \(Int(standing.threshold)); yours is \(Int(standing.score))"))
        }
        let aztec = try await AztecEngine.shared.accountAddress()
        let limit = try await limit(.intoAztec, asset: asset, units: units, account: account, aztec: aztec)
        let nonce = UInt64.random(in: 1...UInt64.max)
        guard let plan = try await AztecEngine.shared.call("shieldPlan", [String(nonce)]) as? [String: Any],
              let secretHash = plan["secretHash"] as? String,
              let deposit = depositCalldata(units: units, secretHash: secretHash, limit: limit),
              let amount = word(decimal: units) else {
            throw Failure(message: String(localized: "This move could not be written"))
        }
        let approve = "0x095ea7b3" + (word(hex: asset.portal) ?? "") + amount
        let sent = try await YourAccountChain.privateCalls(
            [(to: asset.ethToken, data: approve, value: "0"), (to: asset.portal, data: deposit, value: "0")],
            on: YourAccountOp.ethereum, reason: String(localized: "Move \(asset.symbol) into your Aztec account"), stage: stage)
        guard case .landed(let transaction?, _) = sent.outcome else {
            throw Failure(message: String(localized: "Sent; Aztec will see it once Ethereum shows it"))
        }
        guard let receipt = try? await YourAccountChain.rpc(YourAccountOp.ethereum, "eth_getTransactionReceipt", [transaction]) as? [String: Any],
              let message = message(in: receipt, portal: asset.portal) else {
            throw Failure(message: String(localized: "Sent, but its message to Aztec could not be read yet"))
        }
        let pending = AztecAccountStore.ShieldDeposit(nonce: nonce, symbol: asset.symbol, amountUnits: message.amount,
                                                      transaction: transaction, messageHash: message.key,
                                                      leafIndex: message.index, claimed: false, at: .now)
        AztecAccountStore.shared.addShield(pending)
        return pending
    }

    /// Claims every Shield deposit Aztec has carried, privately, to your account.
    @MainActor
    static func settle() async {
        for d in AztecAccountStore.shared.snapshot.shield ?? [] where !d.claimed {
            guard let ready = try? await AztecEngine.shared.call("messageReady", [d.messageHash]) as? [String: Any],
                  ready["ready"] as? Bool == true else { continue }
            do {
                _ = try await AztecEngine.shared.call("shieldClaim", [d.symbol, d.amountUnits, String(d.nonce), d.leafIndex])
                AztecAccountStore.shared.markShieldClaimed(d.nonce)
                await AztecAccountStore.shared.refresh()
            } catch {
                NSLog("aztecEngine| shield | claim waits: %@", error.localizedDescription)
            }
        }
    }
}
