import Foundation
import UIKit

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
                           reason: o["reason"] as? String,
                           screeningUSD: ((o["tiers"] as? [String: Any])?["screeningUsd"] as? NSNumber)?.doubleValue ?? 100)
    }

    // MARK: - Signing in with the Safe

    @MainActor private static var session: (account: String, token: String, until: Date)?

    /// Whether a sign-in for `account` still stands, so none is asked (prd §1918).
    @MainActor static func signedIn(_ account: String) -> Bool {
        guard let s = session else { return false }
        return s.account.lowercased() == account.lowercased() && s.until > .now
    }

    /// A session token for `account`, signing in (Face ID) when there is none.
    /// `coSigner`: `account` is your co-signer, whose own wallet signs the
    /// sign-in through the Signer sheet (prd §1720) — the wallet Shield
    /// scored when you linked accounts on its page.
    @MainActor
    static func token(account: String, aztec: String, coSigner: Bool = false) async throws -> String {
        if let s = session, s.account.lowercased() == account.lowercased(), s.until > .now { return s.token }
        guard let (data, http) = await IngestSupport.sendRequest(URLRequest(url: URL(string: "\(base)/api/auth/nonce")!), service: service),
              http.statusCode == 200, let nonce = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !nonce.isEmpty else {
            throw Failure(message: String(localized: "Shield did not answer"))
        }
        let message = siwe(account: EIP55.checksum(account), aztec: aztec, nonce: nonce, now: .now)
        let signature: [UInt8]
        if let key = ShieldKey.address, key.lowercased() == account.lowercased() {
            // Your Shield key signs in on this phone, asking no one (prd §1920).
            do { signature = try ShieldKey.signIn(message) } catch {
                throw Failure(message: String(localized: "This iPhone could not sign in to Shield"))
            }
        } else {
            // Only one key's signature signs in (prd §1890): a Safe's is refused.
            guard coSigner else { throw Failure(message: String(localized: "Shield takes a sign-in from your co-signer, not your account")) }
            let hex = "0x" + Array(message.utf8).map { String(format: "%02x", $0) }.joined()
            signature = try await SignerRequestSheet.asking(signer: account, title: String(localized: "Your co-signer signs in to Shield")) { ask in
                try await YourAccountSignerLink.signForApp(method: "personal_sign", params: [hex, account],
                                                          digest: NearAIVerify.personalSignDigest(message), signer: account,
                                                          resend: ask.resends, sent: { ask.ask(kept: $0) },
                                                          show: { ask.pair($0); openCoSignerWallet(account, onto: $0) })
            }
        }
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
    static func limit(_ direction: Direction, asset: Asset, units: String, account: String, aztec: String,
                      coSigner: Bool = false) async throws -> Limit {
        let token = try await token(account: account, aztec: aztec, coSigner: coSigner)
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
    /// **INTO AZTEC FROM YOUR CO-SIGNER (prd §1720).** Shield scores the
    /// wallet that signs in, and its portal takes a deposit only from that
    /// wallet (`depositToAztecPrivateFor` answers `NotTrustedForwarder` to
    /// anyone but Shield's router, measured 2026-11-07), so when your
    /// co-signer holds the Human Passport score the deposit is the
    /// co-signer's own: Shield's limit signed in by the co-signer; what the
    /// co-signer lacks (the token, and ETH for two sends) moved to it from
    /// your account first, gas for Aztec riding along — one operation, Face
    /// ID, the Signer when your account needs both keys; then the
    /// co-signer's wallet approves the portal (only if it must) and
    /// deposits. The claim on Aztec follows in `settle()` as for any deposit.
    @MainActor
    static func depositFromCoSigner(_ asset: Asset, units: String, coSigner: String, gas: AztecGas.Plan? = nil,
                                    said: @escaping @MainActor (String) -> Void) async throws -> AztecAccountStore.ShieldDeposit {
        guard !DemoMode.isActive else { throw Failure(message: String(localized: "The demo moves nothing")) }
        guard YourAccountKey.address != nil else { throw Failure(message: String(localized: "There is no account on this iPhone")) }
        guard let standing = await eligibility(coSigner), standing.eligible else {
            throw Failure(message: String(localized: "Shield does not take money from your co-signer yet"))
        }
        let aztec = try await AztecEngine.shared.accountAddress()
        said(String(localized: "Your co-signer signs in to Shield…"))
        let limit = try await limit(.intoAztec, asset: asset, units: units, account: coSigner, aztec: aztec, coSigner: true)
        let nonce = UInt64.random(in: 1...UInt64.max)
        guard let plan = try await AztecEngine.shared.call("shieldPlan", [String(nonce)]) as? [String: Any],
              let secretHash = plan["secretHash"] as? String,
              let deposit = depositCalldata(units: units, secretHash: secretHash, limit: limit),
              let amount = word(decimal: units), let portalWord = word(hex: asset.portal) else {
            throw Failure(message: String(localized: "This move could not be written"))
        }
        let approve = "0x095ea7b3" + portalWord + amount
        let net = YourAccountOp.ethereum
        // What the co-signer lacks, from your account, in one operation.
        let held = Decimal(string: await AztecMove.balance(of: asset.ethToken, at: coSigner)) ?? 0
        let wanted = Decimal(string: units) ?? 0
        let allowed = Decimal(string: await allowance(of: asset.ethToken, owner: coSigner, spender: asset.portal)) ?? 0
        let ethNeeded = try await coSignerGas(coSigner, approves: allowed < wanted)
        var calls: [(to: String, data: String, value: String)] = gas?.calls ?? []
        if held < wanted, let short = word(decimal: NSDecimalNumber(decimal: wanted - held).stringValue),
           let to = word(hex: coSigner) {
            calls.append((to: asset.ethToken, data: "0xa9059cbb" + to + short, value: "0"))
        }
        if let ethNeeded { calls.append((to: coSigner, data: "0x", value: ethNeeded)) }
        if !calls.isEmpty {
            said(String(localized: "Confirm with Face ID"))
            let sent = try await YourAccountChain.appCalls(calls, on: net,
                reason: String(localized: "Move \(asset.symbol) to your co-signer for Aztec"),
                signer: { SignerRequestSheet.coSigner(owner: $0, chainId: net.chainId) }) { _ in }
            guard case .landed = sent.outcome else {
                throw Failure(message: String(localized: "On its way to your co-signer. Try again once it lands."))
            }
            if let gas, case .landed(let tx?, _) = sent.outcome,
               let receipt = try? await YourAccountChain.rpc(net, "eth_getTransactionReceipt", [tx]) as? [String: Any] {
                AztecGas.record(gas, transaction: tx, receipt: receipt)
            }
        }
        if allowed < wanted {
            said(String(localized: "Approve in your co-signer's wallet"))
            let tx = try await coSend(["from": coSigner, "to": asset.ethToken, "data": approve, "value": "0x0"], signer: coSigner,
                                      title: String(localized: "Your co-signer lets Shield take \(asset.symbol)"))
            _ = try await mined(tx)
        }
        said(String(localized: "Deposit in your co-signer's wallet"))
        let tx = try await coSend(["from": coSigner, "to": asset.portal, "data": deposit, "value": "0x0"], signer: coSigner,
                                  title: String(localized: "Your co-signer moves \(asset.symbol) into Aztec"))
        let receipt = try await mined(tx)
        guard let message = message(in: receipt, portal: asset.portal) else {
            throw Failure(message: String(localized: "Sent, but its message to Aztec could not be read yet"))
        }
        let pending = AztecAccountStore.ShieldDeposit(nonce: nonce, symbol: asset.symbol, amountUnits: message.amount,
                                                      transaction: tx, messageHash: message.key,
                                                      leafIndex: message.index, claimed: false, at: .now)
        AztecAccountStore.shared.addShield(pending)
        NSLog("shieldBridge| co-signer deposited | %@ | %@ %@", tx, units, asset.symbol)
        return pending
    }

    /// **INTO AZTEC THROUGH YOUR SHIELD KEY (prd §1920).** No co-signer: the
    /// key on this phone (`ShieldKey`) signs in, Shield's screening tier
    /// gives it up to $100 a day, your account hands it what it lacks (the
    /// token, and ETH for its two sends) in one operation with Face ID, and
    /// the key approves the portal (only if it must) and deposits. What it
    /// already holds counts, so a move that stopped half way is finished by
    /// the next. The claim on Aztec follows in `settle()`.
    @MainActor
    static func depositFromKey(_ asset: Asset, units: String, gas: AztecGas.Plan? = nil,
                               said: @escaping @MainActor (String) -> Void) async throws -> AztecAccountStore.ShieldDeposit {
        guard !DemoMode.isActive else { throw Failure(message: String(localized: "The demo moves nothing")) }
        guard let account = YourAccountKey.address else { throw Failure(message: String(localized: "There is no account on this iPhone")) }
        guard let key = ShieldKey.address else { throw Failure(message: String(localized: "Private money is not set up on this iPhone")) }
        guard let standing = await eligibility(key), standing.eligible, !standing.sanctioned else {
            throw Failure(message: String(localized: "Shield does not take money from this iPhone"))
        }
        let aztec = try await AztecEngine.shared.accountAddress()
        said(String(localized: "Signing in to Shield…"))
        let limit = try await limit(.intoAztec, asset: asset, units: units, account: key, aztec: aztec)
        let nonce = UInt64.random(in: 1...UInt64.max)
        guard let plan = try await AztecEngine.shared.call("shieldPlan", [String(nonce)]) as? [String: Any],
              let secretHash = plan["secretHash"] as? String,
              let deposit = depositCalldata(units: units, secretHash: secretHash, limit: limit),
              let amount = word(decimal: units), let portalWord = word(hex: asset.portal) else {
            throw Failure(message: String(localized: "This move could not be written"))
        }
        let approve = "0x095ea7b3" + portalWord + amount
        let net = YourAccountOp.ethereum
        let held = Decimal(string: await AztecMove.balance(of: asset.ethToken, at: key)) ?? 0
        let wanted = Decimal(string: units) ?? 0
        let allowed = Decimal(string: await allowance(of: asset.ethToken, owner: key, spender: asset.portal)) ?? 0
        let ethNeeded = try await keyGas(key, approves: allowed < wanted)
        var calls: [(to: String, data: String, value: String)] = gas?.calls ?? []
        if held < wanted, let short = word(decimal: NSDecimalNumber(decimal: wanted - held).stringValue), let to = word(hex: key) {
            calls.append((to: asset.ethToken, data: "0xa9059cbb" + to + short, value: "0"))
        }
        if let ethNeeded { calls.append((to: key, data: "0x", value: ethNeeded)) }
        if !calls.isEmpty {
            said(String(localized: "Confirm with Face ID"))
            let sent = try await YourAccountChain.appCalls(calls, on: net,
                reason: String(localized: "Move \(asset.symbol) into Aztec"),
                signer: { SignerRequestSheet.coSigner(owner: $0, chainId: net.chainId) }) { _ in }
            guard case .landed = sent.outcome else {
                throw Failure(message: String(localized: "On its way to your Shield key. Try again once it lands."))
            }
            if let gas, case .landed(let tx?, _) = sent.outcome,
               let receipt = try? await YourAccountChain.rpc(net, "eth_getTransactionReceipt", [tx]) as? [String: Any] {
                AztecGas.record(gas, transaction: tx, receipt: receipt)
            }
        }
        do {
            if allowed < wanted {
                said(String(localized: "Letting Shield take it…"))
                _ = try await mined(try await ShieldKey.send(to: asset.ethToken, data: approve, gas: ShieldKey.approveGas, account: account))
            }
            said(String(localized: "Moving it into Aztec…"))
            let tx = try await ShieldKey.send(to: asset.portal, data: deposit, gas: ShieldKey.depositGas, account: account)
            let receipt = try await mined(tx)
            guard let message = message(in: receipt, portal: asset.portal) else {
                throw Failure(message: String(localized: "Sent, but its message to Aztec could not be read yet"))
            }
            let pending = AztecAccountStore.ShieldDeposit(nonce: nonce, symbol: asset.symbol, amountUnits: message.amount,
                                                          transaction: tx, messageHash: message.key,
                                                          leafIndex: message.index, claimed: false, at: .now)
            AztecAccountStore.shared.addShield(pending)
            NSLog("shieldBridge| key deposited | %@ | %@ %@", tx, units, asset.symbol)
            return pending
        } catch ShieldKey.Failure.refused(let why) {
            NSLog("shieldBridge| key refused | %@", why)
            throw Failure(message: String(localized: "Your Shield key could not send it. Try again: it keeps what it holds."))
        }
    }

    /// ETH the Shield key lacks for its sends, wei, or nil: as the co-signer's.
    private static func keyGas(_ key: String, approves: Bool) async throws -> String? {
        let net = YourAccountOp.ethereum
        guard let balanceHex = try await YourAccountChain.rpc(net, "eth_getBalance", [key, "latest"]) as? String,
              let priceHex = try await YourAccountChain.rpc(net, "eth_gasPrice", []) as? String,
              let balance = Decimal(string: decimal(hex: String(balanceHex.dropFirst(2))) ?? ""),
              let price = Decimal(string: decimal(hex: String(priceHex.dropFirst(2))) ?? "") else {
            throw Failure(message: String(localized: "Ethereum did not answer"))
        }
        let units = Decimal((approves ? ShieldKey.approveGas : 0) + ShieldKey.depositGas)
        let need = units * price * 2
        guard balance < need else { return nil }
        var rounded = Decimal(), short = need - balance
        NSDecimalRound(&rounded, &short, 0, .up)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    /// One send by the co-signer's own wallet, through the Signer sheet.
    @MainActor
    private static func coSend(_ tx: [String: String], signer: String, title: String) async throws -> String {
        try await SignerRequestSheet.asking(signer: signer, title: title) { ask in
            try await YourAccountSignerLink.sendForApp(tx: tx, signer: signer, resend: ask.resends,
                                                      sent: { ask.ask(kept: $0) },
                                                      show: { ask.pair($0); openCoSignerWallet(signer, onto: $0) })
        }
    }

    /// ETH (wei, decimal) your co-signer needs for its approve and deposit
    /// beyond what it holds, with room for the price to move; nil when it
    /// holds enough.
    private static func coSignerGas(_ coSigner: String, approves: Bool) async throws -> String? {
        let net = YourAccountOp.ethereum
        guard let balanceHex = try await YourAccountChain.rpc(net, "eth_getBalance", [coSigner, "latest"]) as? String,
              let priceHex = try await YourAccountChain.rpc(net, "eth_gasPrice", []) as? String,
              let balance = Decimal(string: decimal(hex: String(balanceHex.dropFirst(2))) ?? ""),
              let price = Decimal(string: decimal(hex: String(priceHex.dropFirst(2))) ?? "") else {
            throw Failure(message: String(localized: "Ethereum did not answer"))
        }
        let units: Decimal = (approves ? 70_000 : 0) + 260_000
        let need = units * price * 2
        guard balance < need else { return nil }
        var rounded = Decimal(), short = need - balance
        NSDecimalRound(&rounded, &short, 0, .up)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    /// `owner`'s ERC-20 allowance to `spender`, base units, or "0".
    static func allowance(of token: String, owner: String, spender: String) async -> String {
        guard let o = word(hex: owner), let s = word(hex: spender),
              let answer = try? await YourAccountChain.rpc(YourAccountOp.ethereum, "eth_call",
                                                           [["to": token, "data": "0xdd62ed3e" + o + s], "latest"]) as? String
        else { return "0" }
        return decimal(hex: String(answer.dropFirst(2))) ?? "0"
    }

    /// The receipt of `tx` once Ethereum has it (ten minutes at most).
    private static func mined(_ tx: String) async throws -> [String: Any] {
        for _ in 0..<150 {
            if let r = try? await YourAccountChain.rpc(YourAccountOp.ethereum, "eth_getTransactionReceipt", [tx]) as? [String: Any] {
                guard (r["status"] as? String) == "0x1" else { throw Failure(message: String(localized: "It failed on Ethereum")) }
                return r
            }
            try await Task.sleep(for: .seconds(4))
        }
        throw Failure(message: String(localized: "Sent; Aztec will see it once Ethereum shows it"))
    }

    /// Opens the co-signer's own wallet onto a fresh pairing, on the phone,
    /// when a session it settled before names it (prd §1700l item 12).
    @MainActor
    static func openCoSignerWallet(_ signer: String, onto pairing: URL) {
        guard UIDevice.current.userInterfaceIdiom == .phone,
              let wallet = YourAccountSignerLink.walletHolding(signer),
              let link = SignerSwitch.link(wallet, pairing: pairing) else { return }
        UIApplication.shared.open(link)
    }

    /// Claims every Shield deposit Aztec has carried, privately, to your account.
    /// Asked only through `AztecArrivals.settle()`: one pass at a time.
    @MainActor
    static func settle() async {
        for d in AztecAccountStore.shared.snapshot.shield ?? [] where !d.claimed {
            guard let ready = try? await AztecEngine.shared.call("messageReady", [d.messageHash]) as? [String: Any],
                  ready["ready"] as? Bool == true else { continue }
            do {
                // The claim mints a waiting gas deposit and pays from it (prd §1700aa).
                let out = try await AztecEngine.shared.call("shieldClaim", [d.symbol, d.amountUnits, String(d.nonce), d.leafIndex, AztecGas.unminted]) as? [String: Any]
                AztecGas.spent(by: out)
                AztecAccountStore.shared.markShieldClaimed(d.nonce)
                // Told when you are away from Casberi (prd §1881).
                let arrived = String(localized: "\(AztecAccountStore.figure(d)) from Ethereum")
                Task { await Notifications.outcome(.moveArrived, id: "aztec:\(d.nonce)", place: "Aztec",
                                                   body: arrived, mark: "Aztec") }
                // It arrived: one Activity row by the deposit's transaction,
                // Etherscan its door (prd §1700ac).
                if let context = SharedStore.live?.mainContext {
                    PrivateActivity.land(hash: d.transaction,
                                         title: PrivateMoney.activityTitle(figure: AztecAccountStore.figure(d), to: nil),
                                         chainId: PrivacyNetwork.ethereum.chainId, context: context)
                }
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
        // **OUT AS IN, BY YOUR CO-SIGNER (prd §1700r, user: "it says shield
        // needs a human passport score of 20 and mine is 0" — the deposit had
        // gone in by the co-signer, §1720).** When your account is not
        // eligible and your co-signer is, the co-signer signs in to Shield for
        // the exit's limit. The exit itself is proved here and pays only the
        // address in the sentence.
        // Always by your co-signer (prd §1890): your account's own sign-in
        // is refused, whatever Shield's screening tier says of it.
        guard !standing.sanctioned else { throw Failure(message: String(localized: "Shield will not move money for this account")) }
        let found = try? await YourAccountChain.knownSigners(YourAccountOp.ethereum, account).first
        let theirs: Eligibility? = if let found { await eligibility(found) } else { nil }
        guard let coSigner = found, let theirs, theirs.eligible, !theirs.sanctioned else {
            throw Failure(message: String(localized: "Shield needs a Human Passport score of \(Int(theirs?.threshold ?? standing.threshold)) on your co-signer; it has \(Int(theirs?.score ?? 0))"))
        }
        let signer = coSigner
        let byCoSigner = true
        let aztec = try await AztecEngine.shared.accountAddress()
        let limit = try await limit(.outOfAztec, asset: asset, units: units, account: signer, aztec: aztec, coSigner: byCoSigner)
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
        try await PrivateRootKey.unlock(reason: String(localized: "Send \(asset.symbol) out of your private account on Aztec"))
        try await AztecCoSign.approve(String(localized: "Send \(PrivateMoney.figure(units, decimals: asset.decimals, symbol: asset.symbol)) from Aztec to \(recipient)"))
        guard let out = try await AztecEngine.shared.call("shieldExit", [asset.symbol, units, recipient, text, AztecGas.unminted]) as? [String: Any],
              let transaction = out["tx"] as? String, let message = out["message"] as? String else {
            throw Failure(message: String(localized: "Aztec did not take this move"))
        }
        AztecGas.spent(by: out)
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
