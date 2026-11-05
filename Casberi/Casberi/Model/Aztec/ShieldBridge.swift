import Foundation

/// Shield's app half (prd §1700d, §1700e): its API, the Safe's sign-in, the
/// moves in and out. What it writes and reads is `ShieldWire.swift`.
extension ShieldBridge {
    // MARK: - Where you stand (public, no sign-in)

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

    // MARK: - Shield's signed limit

    @MainActor
    static func limit(_ direction: Direction, asset: Asset, units: String, account: String, aztec: String) async throws -> Limit {
        let token = try await token(account: account, aztec: aztec)
        var body: [String: Any] = ["portalAddress": asset.portal, "direction": direction.rawValue]
        if direction == .intoAztec {
            body["amount"] = units; body["tokenSymbol"] = asset.symbol; body["tokenDecimals"] = asset.decimals
        } else {
            // Shield's client sends only the direction and the two addresses.
            body["bridgeAddress"] = asset.bridge
        }
        let (json, status) = await IngestSupport.requestJSON("\(base)/api/attestation/passport", method: "POST", body: body,
                                                            headers: ["Authorization": "Bearer \(token)"], service: service)
        let o = json as? [String: Any]
        let l1 = o?["l1Signature"] as? String
        let l2 = (o?["l2Signature"] as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue }
        guard status == 200, let o, direction == .intoAztec ? l1 != nil : (l2?.count == 64 && l2!.allSatisfy { (0...255).contains($0) }) else {
            if status == 401 { session = nil }
            let why = ((json as? [String: Any])?["message"] as? String) ?? ((json as? [String: Any])?["error"] as? String)
            throw Failure(message: why ?? String(localized: "Shield did not give a limit for this move"))
        }
        return Limit(maxAmount: string(o["maxAmount"]), nonce: string(o["nonce"]), deadline: string(o["deadline"]),
                     signature: l1 ?? "", aztecSignature: l2)
    }

    private static func string(_ any: Any?) -> String {
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return "0"
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
    static func deposit(_ asset: Asset, units: String, gas: AztecGas.Plan? = nil,
                        stage: @escaping @Sendable (YourAccountChain.Stage) async -> Void) async throws -> AztecAccountStore.ShieldDeposit {
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
        // Gas rides along in the same operation when the account needs it
        // (prd §1700f item 13): one Face ID.
        let sent = try await YourAccountChain.privateCalls(
            (gas?.calls ?? []) + [(to: asset.ethToken, data: approve, value: "0"), (to: asset.portal, data: deposit, value: "0")],
            on: YourAccountOp.ethereum, reason: String(localized: "Move \(asset.symbol) into your Aztec account"), stage: stage)
        guard case .landed(let transaction?, _) = sent.outcome else {
            throw Failure(message: String(localized: "Sent; Aztec will see it once Ethereum shows it"))
        }
        guard let receipt = try? await YourAccountChain.rpc(YourAccountOp.ethereum, "eth_getTransactionReceipt", [transaction]) as? [String: Any],
              let message = message(in: receipt, portal: asset.portal) else {
            throw Failure(message: String(localized: "Sent, but its message to Aztec could not be read yet"))
        }
        if let gas { AztecGas.record(gas, transaction: transaction, receipt: receipt) }
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

// MARK: - Out of Aztec

extension ShieldBridge {
    /// Moves `units` of `asset` out of your Aztec account to your Safe: Shield's
    /// signed limit for this Aztec account (signing in with the Safe), then the
    /// bridge's exit, proved on this iPhone, which burns the tokens and leaves
    /// a message for Shield's portal. `finish` withdraws it on Ethereum once
    /// Aztec's proof is there.
    @MainActor
    static func exit(_ asset: Asset, units: String, to recipient: String) async throws -> AztecAccountStore.ShieldExit {
        guard !DemoMode.isActive else { throw Failure(message: String(localized: "The demo moves nothing")) }
        guard let account = YourAccountKey.address else { throw Failure(message: String(localized: "There is no account on this iPhone")) }
        guard let standing = await eligibility(account) else { throw Failure(message: String(localized: "Shield did not answer")) }
        guard standing.eligible else {
            throw Failure(message: standing.sanctioned
                ? String(localized: "Shield will not move money for this account")
                : String(localized: "Shield needs a Human Passport score of \(Int(standing.threshold)); yours is \(Int(standing.score))"))
        }
        let aztec = try await AztecEngine.shared.accountAddress()
        let limit = try await limit(.outOfAztec, asset: asset, units: units, account: account, aztec: aztec)
        guard let max = Decimal(string: limit.maxAmount), let want = Decimal(string: units), want <= max else {
            let most = Decimal(string: limit.maxAmount).map { PrivateMoney.figure(NSDecimalNumber(decimal: $0).stringValue, decimals: asset.decimals, symbol: asset.symbol) }
            throw Failure(message: most.map { String(localized: "Shield allows up to \($0) at a time") } ?? String(localized: "Shield did not give a limit for this move"))
        }
        let passport: [String: Any] = ["maxAmount": limit.maxAmount, "nonce": limit.nonce, "deadline": limit.deadline,
                                       "signature": limit.aztecSignature ?? []]
        guard let json = try? JSONSerialization.data(withJSONObject: passport), let text = String(data: json, encoding: .utf8) else {
            throw Failure(message: String(localized: "This move could not be written"))
        }
        // Any Ethereum address may be paid (prd §1700f item 14); the portal
        // pays exactly this one.
        guard recipient.count == 42, recipient.lowercased().hasPrefix("0x"), recipient.dropFirst(2).allSatisfy(\.isHexDigit) else {
            throw Failure(message: String(localized: "That isn't an Ethereum address"))
        }
        try await PrivateRootKey.unlock(reason: String(localized: "Send \(asset.symbol) out of your private balance on Aztec"))
        try await AztecCoSign.approve(String(localized: "Send \(PrivateMoney.figure(units, decimals: asset.decimals, symbol: asset.symbol)) from Aztec to \(recipient)"))
        guard let out = try await AztecEngine.shared.call("shieldExit", [asset.symbol, units, recipient, text]) as? [String: Any],
              let transaction = out["tx"] as? String, let message = out["message"] as? String else {
            throw Failure(message: String(localized: "Aztec did not take this move"))
        }
        let exit = AztecAccountStore.ShieldExit(symbol: asset.symbol, amountUnits: units, recipient: recipient, transaction: transaction,
                                                message: message, outbox: out["outbox"] as? String, withdrawal: nil, at: .now)
        AztecAccountStore.shared.addExit(exit)
        await AztecAccountStore.shared.refresh()
        return exit
    }

    /// Where an exit stands on Ethereum.
    enum ExitState: Equatable {
        /// Aztec's proof of its epoch is not on Ethereum yet.
        case waiting
        /// Ready: the portal's withdraw calldata.
        case ready(calldata: String)
        /// Someone already withdrew it (to the same recipient: nothing else can).
        case done
    }

    @MainActor
    static func state(of exit: AztecAccountStore.ShieldExit) async -> ExitState {
        guard let w = try? await AztecEngine.shared.call("exitWitness", [exit.transaction, exit.message]) as? [String: Any],
              let epoch = w["epoch"] as? String, let checkpoints = w["checkpoints"] as? String,
              let leaf = w["leaf"] as? String, let path = w["path"] as? [String] else { return .waiting }
        if let outbox = exit.outbox {
            // Proven on Ethereum yet? (Aztec's node can know the witness first.)
            guard let e = word(decimal: epoch), let n = word(decimal: checkpoints),
                  let root = try? await YourAccountChain.rpc(YourAccountOp.ethereum, "eth_call",
                                                             [["to": outbox, "data": rootDataSelector + e + n], "latest"]) as? String,
                  let rootWord = word(hex: root), rootWord != String(repeating: "0", count: 64) else { return .waiting }
            // Already withdrawn? The outbox keys a message by 2^depth + its index.
            if let leafID = leafID(leaf: leaf, depth: path.count), let id = word(decimal: leafID),
               let used = try? await YourAccountChain.rpc(YourAccountOp.ethereum, "eth_call",
                                                          [["to": outbox, "data": consumedSelector + e + id], "latest"]) as? String,
               decimal(hex: String(used.dropFirst(2))) == "1" {
                return .done
            }
        }
        guard let data = withdrawCalldata(recipient: exit.recipient, units: exit.amountUnits, epoch: epoch,
                                          checkpoints: checkpoints, leaf: leaf, path: path) else { return .waiting }
        return .ready(calldata: data)
    }

    /// Withdraws one ready exit on Ethereum from your Safe (simulated, Face ID).
    @MainActor
    static func finish(_ exit: AztecAccountStore.ShieldExit, stage: @escaping @Sendable (YourAccountChain.Stage) async -> Void) async throws {
        guard let asset = assets.first(where: { $0.symbol == exit.symbol }) else { return }
        switch await state(of: exit) {
        case .waiting:
            throw Failure(message: String(localized: "Aztec's proof is not on Ethereum yet"))
        case .done:
            AztecAccountStore.shared.markExitWithdrawn(exit.transaction, withdrawal: "consumed")
        case .ready(let calldata):
            let sent = try await YourAccountChain.privateCalls(
                [(to: asset.portal, data: calldata, value: "0")], on: YourAccountOp.ethereum,
                reason: String(localized: "Finish moving \(asset.symbol) out of Aztec"), stage: stage)
            if case .landed(let transaction, _) = sent.outcome {
                AztecAccountStore.shared.markExitWithdrawn(exit.transaction, withdrawal: transaction ?? "landed")
            }
        }
    }

}
