import Foundation
import SwiftData

/// SENDING ON VIBENET (prd §523, 2026-08-29) — the one place this app can
/// write to a chain, and the only caller of `VibenetDeviceKey.sign`.
///
/// **PROVEN END TO END, not merely encoded.** Account
/// `0x6c7d8a1751d20a4b957868753673922c60897ae1` exists on vibenet because this
/// exact sequence created it: derive the address, sign as the account itself
/// with the P-256 key, have the faucet sign as payer, broadcast. Receipt
/// `0x1`, 93 bytes of code at the derived address. A software key stood in for
/// the Secure Enclave in that run — the only difference here is where the
/// signature comes from.
///
/// ## WHY THIS FILE IS THE ONLY ONE THAT SIGNS
///
/// `vibenet-selftest.sh` ties a caller of `VibenetDeviceKey.sign` to the three
/// sentences the app SHOWS a person — the catalog bullet, `VibenetBridge`'s
/// `canLine`, and the reach registry's purpose — and fails the build if a
/// signing path appears while any of them still claims the seat never signs.
/// Keeping the signature in one file is what makes that guard checkable: the
/// promise is about a specific, small, readable place rather than about a
/// 2,600-line bridge.
///
/// ## THREE THINGS MEASURED THE HARD WAY
///
/// 1. **The payer service's parameter is `signedTransaction`.** Not
///    `transaction`, not `tx`. Every wrong name — and a missing one — produces
///    the IDENTICAL error, `Cannot read properties of undefined (reading
///    'replace')`, so the message says nothing about which mistake was made.
/// 2. **`validBefore` is 0.** The terms advertise `maxExpiry: 15`, which reads
///    as "you must set a short expiry" and is not one: every epoch-second value
///    tried was refused as "already expired", while no-expiry is accepted and
///    matches every real transaction on the chain.
/// 3. **Anything derived from a clock is computed ONCE and passed in.** The
///    first working draft recomputed the expiry inside the function that built
///    the body — called once for the digest and once for the bytes — so the
///    signature covered a different transaction than the one sent. That is the
///    `BriefLedger`/`AppVisit` rule about taking `now` as a parameter, in the
///    one place where breaking it is a signature over the wrong thing.
enum VibenetSend {

    /// The payer service. Same host as the contract map, which is already in
    /// `NetworkReach` — no new host joins the app's reach for this.
    private static let payerEndpoint = "https://api.vibes.base.org/api/vibenet/account/payer"

    enum Failure: Error, Equatable {
        case noKey
        case cannotCompose
        case noSponsor
        /// The payer service refused. Carries its own words, because the one
        /// thing measured about this endpoint is that its errors are worth
        /// reading and its parse failure is worth nothing.
        case payerRefused(String)
        case broadcastRefused(String)
        case signingRefused
    }

    /// What came back, so a receipt can state it rather than re-deriving it.
    struct Sent: Equatable {
        let account: Data
        let transactionHash: String
        /// nil when nobody sponsored — the person paid, or would have.
        let payer: Data?
    }

    // MARK: - Sponsorship

    /// Ask what a payer would offer. nil when nothing is on offer, which is a
    /// real answer rather than a failure — the quota is finite and this is a
    /// devnet.
    static func sponsoredPayer(for account: Data, gasLimit: UInt64) async -> Data? {
        let body: [String: Any] = [
            "jsonrpc": "2.0", "id": 1, "method": "payer_getTerms",
            "params": [["chainId": VibenetSigner.chainID,
                        "from": "0x" + VibenetTransaction.hex(account),
                        "calls": [],
                        "gasLimit": "0x" + String(gasLimit, radix: 16),
                        "context": ["flow": "transact"]]],
        ]
        guard let root = await IngestSupport.postJSON(payerEndpoint, body: body) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let options = result["options"] as? [[String: Any]] else { return nil }
        // "sponsored" only. The other option is paying in USDV, which is a
        // different act with a different consent and is not taken silently.
        for option in options where (option["kind"] as? String) == "sponsored" {
            if let payer = option["payer"] as? String,
               let data = VibenetTransaction.data(fromHex: payer), data.count == 20 {
                return data
            }
        }
        return nil
    }

    /// Hand the payer a transaction we have signed and get it back with
    /// `payerAuth` filled.
    static func sponsor(rawTransaction raw: String) async throws -> String {
        let body: [String: Any] = [
            "jsonrpc": "2.0", "id": 1, "method": "payer_signTransaction",
            // `signedTransaction` — see this type's doc. A wrong name here is
            // indistinguishable from a malformed transaction.
            "params": [["chainId": VibenetSigner.chainID, "signedTransaction": raw]],
        ]
        guard let root = await IngestSupport.postJSON(payerEndpoint, body: body) as? [String: Any] else {
            throw Failure.payerRefused("no answer")
        }
        if let error = root["error"] as? [String: Any],
           let message = error["message"] as? String { throw Failure.payerRefused(message) }
        guard let result = root["result"] as? [String: Any],
              let signed = result["signedTransaction"] as? String else {
            throw Failure.payerRefused("no signed transaction")
        }
        return signed
    }

    // MARK: - The one write

    /// Broadcast. **The only write verb in this app's vibenet code**, and it
    /// appears exactly once so the conduct guard has one thing to count.
    static func broadcast(rawTransaction raw: String) async throws -> String {
        guard let hash = await VibenetChain.call(method: "eth_sendRawTransaction",
                                               params: [raw]) as? String else {
            throw Failure.broadcastRefused("the node refused the transaction")
        }
        return hash
    }

    // MARK: - The receipt

    /// WHAT YOU DID LANDS IN THE CORPUS (prd §523, user ruling).
    ///
    /// This seat deliberately lands NO `Thing` for anything it WATCHES —
    /// `VibenetBridge`'s own doc says a devnet test account has nothing worth a
    /// corpus row, and that stays true. A write is the other thing: it is news,
    /// you are its source, and it should be searchable and keepable like
    /// anything else you did. So the rule is not "vibenet lands rows" but
    /// **"your own writes land rows"**, which is a distinction the ref carries:
    /// `vibenet:create:<txHash>` exists only for a transaction this phone sent.
    ///
    /// `.transaction` with a `transferAmount` of nothing on purpose: a creation
    /// moves no money, and a receipt that shows "0" where an amount goes reads
    /// as a transfer of zero rather than as an act that had no amount. What it
    /// states instead is who paid, which is the fact that makes it remarkable.
    @MainActor
    static func landReceipt(_ sent: Sent, in context: ModelContext) {
        let ref = "vibenet:create:\(sent.transactionHash)"
        // The dedupe every bridge here does. A re-landed row is this path's
        // historical bug class, and `Thing.sourceRef` carries no unique
        // constraint to catch it for us.
        let existing = FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref })
        if let found = try? context.fetch(existing), !found.isEmpty { return }

        let account = "0x" + VibenetTransaction.hex(sent.account)
        let thing = Thing(
            kind: .transaction,
            title: String(localized: "Made a vibenet account"),
            content: VibenetExplorer.tx(sent.transactionHash),
            source: VibenetIdentity.source,
            capturedAt: .now,
            tags: sent.payer == nil ? ["Account"] : ["Account", "Sponsored"],
            sourceRef: ref)
        thing.walletAddress = account
        // The sentence a receipt closes on. Who paid is the whole of what makes
        // this act unusual, and it is stated only when it is KNOWN — an
        // unsponsored creation says nothing rather than implying the person
        // paid something we did not measure.
        thing.summary = sent.payer == nil
            ? String(localized: "Signed by this phone's key. It answers to that key and nothing else.")
            : String(localized: "Signed by this phone's key, and the devnet's faucet paid the gas.")
        context.insert(thing)
        try? context.save()
    }

    // MARK: - Make an account

    /// Create an account whose only key is this phone, sponsored where a payer
    /// offers.
    ///
    /// **The Face ID prompt happens inside this call** and only after the
    /// address, the plan and the sponsorship are settled — so a person is asked
    /// to authorize the exact transaction that will be sent, never a draft that
    /// still needs a field.
    ///
    /// `userSalt` is generated here rather than derived: it is what makes two
    /// accounts from one key distinct, so a derived salt would make the address
    /// a function of the key alone and a second account impossible.
    static func createAccount(keystore: Data,
                              defaultAccount: Data,
                              authenticator: Data,
                              gasLimit: UInt64 = 300_000,
                              maxFeePerGas: UInt64 = 0x3b9a_ca00,
                              maxPriorityFeePerGas: UInt64 = 0xf4240) async throws -> Sent {
        guard let publicKey = VibenetDeviceKey.publicKeyXY() else { throw Failure.noKey }

        var salt = Data(count: 32)
        salt.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            _ = SecRandomCopyBytes(kSecRandomDefault, 32, base)
        }

        // The address has to exist before sponsorship can be asked about it,
        // and before anything is signed — it is what gets signed AS `sender`.
        guard let draft = VibenetCreate.plan(keystore: keystore,
                                             defaultAccount: defaultAccount,
                                             authenticator: authenticator,
                                             publicKeyXY: publicKey,
                                             userSalt: salt,
                                             gasLimit: gasLimit,
                                             maxFeePerGas: maxFeePerGas,
                                             maxPriorityFeePerGas: maxPriorityFeePerGas)
        else { throw Failure.cannotCompose }

        let payer = await sponsoredPayer(for: draft.address, gasLimit: gasLimit)

        // Re-plan with the payer in place: `payer` is INSIDE the signed body,
        // so asking for sponsorship after signing would sign the wrong
        // transaction. Same salt, so the same address.
        guard let plan = VibenetCreate.plan(keystore: keystore,
                                            defaultAccount: defaultAccount,
                                            authenticator: authenticator,
                                            publicKeyXY: publicKey,
                                            userSalt: salt,
                                            gasLimit: gasLimit,
                                            maxFeePerGas: maxFeePerGas,
                                            maxPriorityFeePerGas: maxPriorityFeePerGas,
                                            payer: payer ?? Data())
        else { throw Failure.cannotCompose }

        let digest = Data(Keccak256.hash([UInt8](plan.preimage)))
        let signature: Data
        do { signature = try VibenetDeviceKey.sign(digest: digest) }
        catch { throw Failure.signingRefused }
        guard signature.count == 64,
              let senderAuth = VibenetP256Auth.senderAuth(authenticator: authenticator,
                                                          r: signature.prefix(32),
                                                          s: signature.suffix(32),
                                                          publicKeyXY: publicKey)
        else { throw Failure.cannotCompose }

        let mine = "0x" + VibenetTransaction.hex(
            VibenetTransaction.encoded(plan.fields, senderAuth: senderAuth))
        let raw = payer == nil ? mine : try await sponsor(rawTransaction: mine)
        let hash = try await broadcast(rawTransaction: raw)
        return Sent(account: plan.address, transactionHash: hash, payer: payer)
    }
}
