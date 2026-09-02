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

    /// **THE FAUCET, AND IT IS NOT THE PAYER (prd §553b, 2026-09-01).**
    ///
    /// §553 shipped this room's Top up as a hand-off that opened the faucet's
    /// web page, on the finding that vibenet "has nothing to top up from": its
    /// faucet is a PAYER (`payerEndpoint` above) that sponsors gas on a
    /// transaction somebody else composed, and no endpoint funds an address.
    /// §553's own amendment corrected half of that — the chain does run a
    /// faucet — and kept the hand-off, on a second finding: the faucet page is
    /// client-rendered, so nothing in its markup names the endpoint it calls.
    ///
    /// **That was true of the markup and false about the app.** The page is a
    /// Next.js bundle and its API client is in the chunks it ships; read on
    /// 2026-09-01, it names `POST /api/vibenet/faucet/drip` with
    /// `{"address": …}` on the same `api.vibes.base.org` host this file
    /// already posts to. MEASURED the same day against the live service, all
    /// three answers (see `HegotaFaucetVerdict.ofDrip`).
    ///
    /// The shape of the mistake is worth naming twice because it is the same
    /// one both times: **absence of a thing where we happened to look was read
    /// as absence of the thing.** First an endpoint missing from OUR bridge
    /// was read as a capability missing from the chain; then an endpoint
    /// missing from the SERVED HTML was read as an endpoint that could not be
    /// found. It was one `curl` away on both occasions.
    ///
    /// Keyless and signature-free, exactly like Hegotá's and Frames': this is
    /// the network handing an address free test ETH, not an account acting. It
    /// therefore needs no key, no Face ID and no account — which is why it can
    /// fund an account that does not exist on chain yet, the one state where a
    /// vibenet address most needs it.
    private static let faucetDripEndpoint = "https://api.vibes.base.org/api/vibenet/faucet/drip"

    enum Failure: Error, Equatable {
        case noKey
        case cannotCompose
        /// The payer answered and had nothing on offer. **A real answer**,
        /// and on a creation a final one — see `createAccount`.
        case noSponsor
        /// Nobody answered the payer at all. Deliberately NOT `noSponsor`
        /// (prd §530): not knowing whether the faucet would pay is not the
        /// faucet declining, and the two send a person to do different
        /// things — wait, or try again.
        case sponsorUnreadable
        /// The payer service refused. Carries its own words, because the one
        /// thing measured about this endpoint is that its errors are worth
        /// reading and its parse failure is worth nothing.
        case payerRefused(String)
        /// The node refused the transaction, **in the node's own words**. The
        /// string is the chain's, never ours: `insufficient funds`, `nonce too
        /// low`, `create address does not match the sender` are three
        /// different next steps, and this app spent them all on one sentence
        /// until prd §530.
        case broadcastRefused(String)
        /// No answer from the chain at all. Never reported as a refusal —
        /// blaming the node for a dropped connection is the §515a mistake.
        case chainUnreachable
        case signingRefused
    }

    /// **THE FAUCET'S REFUSAL IS ITS OWN ERROR, NOT A CASE ON `Failure`
    /// (prd §553b).** Hegotá and Frames hang theirs on the shared enum, and
    /// copying that here would have added a case to two exhaustive switches
    /// (`VibenetCreateSheet`, `VibenetAuthorizeSheet`) that can never see it —
    /// every member of `Failure` above is a way a SIGNED transaction fails, and
    /// a claim signs nothing, needs no key and raises no Face ID.
    ///
    /// The verdict is carried whole rather than flattened to a string (§531's
    /// ruling, taken here rather than re-derived): the cooldown is the refusal
    /// this service was MEASURED to make on an ordinary day and it is not a
    /// fault, so a screen has to be able to tell it apart from a real one,
    /// which a sentence it must grep cannot do.
    struct FaucetRefusal: Error, Equatable {
        let verdict: HegotaFaucetVerdict
    }

    /// What came back, so a receipt can state it rather than re-deriving it.
    struct Sent: Equatable {
        let account: Data
        let transactionHash: String
        /// nil when nobody sponsored — the person paid, or would have.
        let payer: Data?
    }

    // MARK: - Sponsorship

    /// WHAT A PAYER SAID — three answers, not two (prd §530).
    ///
    /// This read used to hand back `Data?`, which folded *the faucet has
    /// nothing for you* into *nobody answered*. Both render as an absent
    /// sponsor, and they are not the same fact: one is the devnet's finite
    /// quota doing its job, the other is a service that blinked. The creation
    /// sheet stated the first as a fact for both — "Nobody is sponsoring — the
    /// account needs funds first" — on a screen whose whole subject is who
    /// pays.
    /// **`declined`, never `none`** — deliberately. This value is held in an
    /// `Optional` by the sheet ("the check hasn't run yet"), and a case spelled
    /// `none` there is the Swift footgun where `.none` silently resolves to
    /// `Optional.none` instead of this case. A name that cannot be confused is
    /// cheaper than a comment warning about the one that can.
    enum PayerOffer: Equatable {
        case sponsored(Data)
        /// The service answered, and offered nothing. A real answer.
        case declined
        /// Nobody answered, or the answer did not parse. NOT an offer of
        /// nothing, and never reported as one.
        case unreadable
    }

    /// Ask what a payer would offer.
    static func payerOffer(for account: Data, gasLimit: UInt64) async -> PayerOffer {
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
              let options = result["options"] as? [[String: Any]] else { return .unreadable }
        // "sponsored" only. The other option is paying in USDV, which is a
        // different act with a different consent and is not taken silently.
        for option in options where (option["kind"] as? String) == "sponsored" {
            if let payer = option["payer"] as? String,
               let data = VibenetTransaction.data(fromHex: payer), data.count == 20 {
                return .sponsored(data)
            }
        }
        // The service answered and named no sponsor we can use. That is an
        // offer of nothing, which is a real answer.
        return .declined
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

    /// Broadcast. **The only write verb in this app's vibenet code**, and the
    /// method literal appears exactly once so the conduct guard has one thing
    /// to count.
    ///
    /// ## THE NODE'S OWN WORDS (prd §530)
    ///
    /// This rode `VibenetChain.call`, which maps a transport failure, a
    /// non-200 and a JSON-RPC `error` object all to nil — so every possible
    /// refusal arrived as one sentence, *"the node refused the transaction"*,
    /// naming none of them. That is §515a's lesson in the WRITE path, where it
    /// costs more: a read that goes quiet is annoying, a write refused with no
    /// reason cannot be acted on by the person holding the phone.
    ///
    /// `postJSONBody`, not `postJSON`, and that is the load-bearing half: a
    /// node commonly answers a rejected send with **HTTP 400 and the reason in
    /// the body**, and every other helper in `IngestSupport` gates the body on
    /// a 200 — so the one thing worth having was thrown away before any parse
    /// could reach it.
    ///
    /// `VibenetChain.call` is deliberately NOT extended to do this: that
    /// function is the read path's, `VibenetBridge.swift` is guarded as a
    /// reader, and `vibenet-selftest.sh` fails the build if a write-shaped
    /// method appears in it.
    static func broadcast(rawTransaction raw: String) async throws -> String {
        let body: [String: Any] = ["id": 1, "jsonrpc": "2.0",
                                   "method": "eth_sendRawTransaction", "params": [raw]]
        let answered = await IngestSupport.postJSONBody(VibenetChain.rpc, body: body,
                                                        service: VibenetIdentity.source)
        guard let root = answered.json as? [String: Any] else {
            // A status with no readable body is still the node answering, and
            // saying so beats claiming it refused something it may never have
            // read. Status 0 is no response at all.
            if answered.status > 0 {
                throw Failure.broadcastRefused(
                    String(localized: "the node answered \(String(answered.status)) and nothing readable"))
            }
            throw Failure.chainUnreachable
        }
        if let hash = root["result"] as? String, !hash.isEmpty { return hash }
        if let error = root["error"] as? [String: Any] {
            // `message` is where every node this chain runs puts it; `data` is
            // where a revert reason sometimes ends up instead. Neither is
            // invented: a refusal with no words says exactly that.
            let words = (error["message"] as? String) ?? (error["data"] as? String) ?? ""
            throw Failure.broadcastRefused(words.isEmpty
                ? String(localized: "the node refused it and gave no reason")
                : words)
        }
        // JSON, no result, no error — the node is answering something this
        // app does not understand, which is not the same as refusing.
        throw Failure.chainUnreachable
    }

    // MARK: - The faucet

    struct Claimed: Equatable {
        let transactionHash: String
        /// The address the service says it funded, in its own words. Read back
        /// rather than assumed: a receipt that names the address we ASKED for
        /// would say the same thing whether or not the service agreed.
        let to: String?
    }

    /// Ask the faucet to fund `account`. No key, no signature, no Face ID.
    ///
    /// **`postJSONBody`, NOT `postJSON`** (§531, the third time this file's
    /// neighbourhood has paid for it): `postJSON` returns nil for ANY non-200,
    /// so the measured cooldown arrives indistinguishable from a dead host,
    /// and `postJSONStatus` is no better — it drops the BODY on a non-200,
    /// which is exactly where this service puts `{"error": …}`.
    static func claimFaucet(for account: Data) async throws -> Claimed {
        let address = "0x" + VibenetTransaction.hex(account)
        let answered = await IngestSupport.postJSONBody(faucetDripEndpoint,
                                                        body: ["address": address],
                                                        service: VibenetIdentity.source)
        let root = answered.json as? [String: Any]
        let verdict = HegotaFaucetVerdict.ofDrip(status: answered.status,
                                                 error: root?["error"] as? String,
                                                 txHash: root?["tx_hash"] as? String)
        if case .sent(let hash) = verdict {
            return Claimed(transactionHash: hash, to: root?["to"] as? String)
        }
        throw FaucetRefusal(verdict: verdict)
    }

    /// The claim's own row. Same ruling as `landReceipt` below — **your own
    /// writes land rows** — and a claim qualifies for the reason §525 gave for
    /// Hegotá's: it carries no signature of yours, but you asked for it and it
    /// put money in an account you hold.
    ///
    /// `vibenet:claim:<txHash>`, a namespace no read path produces, so this
    /// row can only ever exist for a claim this phone made.
    @MainActor
    static func landClaimReceipt(txHash: String, account: Data, in context: ModelContext) {
        let ref = "vibenet:claim:\(txHash)"
        let existing = FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref })
        if let found = try? context.fetch(existing), !found.isEmpty { return }

        let thing = Thing(
            kind: .transaction,
            title: String(localized: "Claimed test ETH from the vibenet faucet"),
            content: VibenetExplorer.tx(txHash),
            source: VibenetIdentity.source,
            capturedAt: .now,
            tags: ["Faucet"],
            sourceRef: ref)
        thing.walletAddress = "0x" + VibenetTransaction.hex(account)
        thing.summary = String(localized: "Requested for this phone's account. No signature was needed \u{2014} the faucet gives it freely.")
        context.insert(thing)
        try? context.save()
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

        // WHY THIS CAN REFUSE BEFORE THE FACE ID (prd §530).
        //
        // An empty `payer` means the SENDER pays — and the sender here is an
        // account derived seconds ago from a salt this call generated at
        // random a few lines above. It holds nothing and cannot: nobody could
        // have funded an address nobody had ever seen. So an unsponsored
        // creation that costs anything is refused by the node EVERY TIME, and
        // the old flow found that out only after asking for a Face ID, signing
        // with it, and broadcasting — surfacing as *"The network refused it:
        // the node refused the transaction"*, which named neither the cause
        // nor the one thing that would fix it.
        //
        // `Failure.noSponsor` was declared for exactly this state and had no
        // thrower; `VibenetCreateSheet` has carried its sentence since the day
        // it shipped, and the screen's own "Gas" line says the same fact
        // BEFORE the tap. This is the code catching up with the copy.
        //
        // The condition is the FEE, not the sponsorship: a transaction that
        // costs nothing needs nobody to pay it, so a zero-fee creation is
        // still allowed to go unsponsored. That keeps the claim exactly true
        // rather than roughly true — the defaults are non-zero, so this is
        // the path every real creation takes.
        let feePayable = maxFeePerGas > 0 || maxPriorityFeePerGas > 0
        var payer: Data?
        switch await payerOffer(for: draft.address, gasLimit: gasLimit) {
        case .sponsored(let address):
            payer = address
        case .declined:
            if feePayable { throw Failure.noSponsor }
        case .unreadable:
            // NOT `noSponsor`: telling somebody the faucet said no, when the
            // faucet was never reached, sends them away to wait for a quota
            // that may be full. Two silences, two sentences.
            if feePayable { throw Failure.sponsorUnreadable }
        }

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

    // MARK: - Send value

    /// Sends ETH from an account this phone already holds the ONLY key for —
    /// `account` is a real, already-established address, never derived here
    /// (2026-08-31, prd §533).
    ///
    /// **The self-call, not a value on the wire call.** `VibenetTransaction
    /// .Call` carries no value by design — see `VibenetExecute`'s own doc for
    /// why and how it was confirmed against the reference `DefaultAccount.sol`
    /// rather than assumed. The one call in this transaction targets the
    /// account itself, invoking `execute(recipient, valueWei, "")`, which is
    /// where the real value-carrying EVM `CALL` happens.
    ///
    /// **The nonce is READ, not started at zero.** Unlike `createAccount`
    /// (a brand-new counterfactual account has never sent anything, so its
    /// nonce is 0 by construction), an established account's nonce is
    /// whatever the chain says — `eth_getTransactionCount` at `nonceKey: 0`,
    /// the default key `Fields` already uses. Signing over a stale or guessed
    /// nonce is a signature over a transaction the chain will refuse, not one
    /// that silently does the wrong thing — but refusing needlessly on a
    /// transient read failure is still a bad send, so a failed nonce read
    /// throws before anything is composed or signed.
    static func sendValue(from account: Data,
                          to recipient: Data,
                          valueWei: Data,
                          gasLimit: UInt64 = 200_000,
                          maxFeePerGas: UInt64 = 0x3b9a_ca00,
                          maxPriorityFeePerGas: UInt64 = 0xf4240) async throws -> Sent {
        guard let publicKey = VibenetDeviceKey.publicKeyXY() else { throw Failure.noKey }
        guard let contracts = await VibenetConfig.current(),
              let authenticator = VibenetTransaction.data(fromHex: contracts.p256Authenticator)
        else { throw Failure.cannotCompose }
        guard recipient.count == 20 else { throw Failure.cannotCompose }

        guard let nonceHex = await VibenetChain.call(
                method: "eth_getTransactionCount",
                params: ["0x" + VibenetTransaction.hex(account), "latest"]) as? String,
              let nonce = UInt64(nonceHex.dropFirst(2), radix: 16)
        else { throw Failure.cannotCompose }

        let call = VibenetTransaction.Call(
            to: account, data: VibenetExecute.calldata(target: recipient, value: valueWei))

        let feePayable = maxFeePerGas > 0 || maxPriorityFeePerGas > 0
        var payer: Data?
        switch await payerOffer(for: account, gasLimit: gasLimit) {
        case .sponsored(let address): payer = address
        case .declined:    if feePayable { throw Failure.noSponsor }
        case .unreadable:  if feePayable { throw Failure.sponsorUnreadable }
        }

        let fields = VibenetTransaction.Fields(
            chainID: VibenetSigner.chainID, sender: account, nonceSequence: nonce,
            maxPriorityFeePerGas: maxPriorityFeePerGas, maxFeePerGas: maxFeePerGas,
            gasLimit: gasLimit, calls: [[call]], payer: payer ?? Data())

        let digest = Data(Keccak256.hash([UInt8](VibenetTransaction.senderSigningPreimage(fields))))
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
            VibenetTransaction.encoded(fields, senderAuth: senderAuth))
        let raw = payer == nil ? mine : try await sponsor(rawTransaction: mine)
        let hash = try await broadcast(rawTransaction: raw)
        return Sent(account: account, transactionHash: hash, payer: payer)
    }

    /// WHAT YOU SENT LANDS IN THE CORPUS — `landReceipt`'s own ruling, applied
    /// to a transfer instead of a creation. Its ref is namespaced apart
    /// (`vibenet:send:`, not `vibenet:create:`) so the two can never dedupe
    /// against each other, and unlike a creation this one carries a real
    /// `transferAmount`: a send moved a specific quantity, and a receipt that
    /// omitted it would be the §83 fake status of describing an act by
    /// everything except the number that makes it one.
    @MainActor
    static func landSendReceipt(_ sent: Sent, to recipient: Data, valueWei: Data,
                                in context: ModelContext) {
        let ref = "vibenet:send:\(sent.transactionHash)"
        let existing = FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref })
        if let found = try? context.fetch(existing), !found.isEmpty { return }

        let recipientHex = "0x" + VibenetTransaction.hex(recipient)
        let thing = Thing(
            kind: .transaction,
            title: String(localized: "Sent from a vibenet account"),
            content: VibenetExplorer.tx(sent.transactionHash),
            source: VibenetIdentity.source,
            capturedAt: .now,
            tags: sent.payer == nil ? ["Send"] : ["Send", "Sponsored"],
            sourceRef: ref)
        thing.walletAddress = "0x" + VibenetTransaction.hex(sent.account)
        thing.transferAmount = VibenetExecute.decimalEther(weiBigEndian: valueWei)
        thing.summary = sent.payer == nil
            ? String(localized: "Sent to \(recipientHex), signed by this phone's key.")
            : String(localized: "Sent to \(recipientHex), signed by this phone's key. The devnet's faucet paid the gas.")
        context.insert(thing)
        try? context.save()
    }

    // MARK: - Modify owners

    /// Authorizes a NEW actor on an account this phone can already sign for
    /// (prd §534, 2026-08-31) — the one write behind both Modify Owners and
    /// Spending Account, which differ only in what's handed in for
    /// `newActorID`/`newAuthenticator`: a P-256 key's `keccak256(x||y)` +
    /// the P256Authenticator for a second physical key, or
    /// `ActorId.fromAddress(otherAccount)` + the DelegateAuthenticator for a
    /// spending sub-account. Neither is composed here — the caller already
    /// knows which shape it's asking for.
    ///
    /// **TWO Face ID prompts, not one.** `Keystore.applySignedAccountChanges`
    /// requires its OWN admin signature over `_changesDigest`
    /// (`VibenetAccountChanges`'s doc has the full reasoning, read from
    /// source) — separate from the outer transaction's `sender_auth`, which
    /// this account still owes for the transaction itself. Both happen to be
    /// signed by the same key today (this app has authorized only one), but
    /// they are two different claims — "I approve this exact change" and "I
    /// authorize this transaction" — and the contract checks them
    /// independently. UNMEASURED end to end: no `AuthorizeActor` has ever
    /// landed from this app, on real hardware or otherwise.
    static func authorizeActor(on account: Data,
                               newActorID: Data,
                               newAuthenticator: Data,
                               scope: UInt16 = 0,
                               policyData: Data = Data(),
                               localEpoch: UInt32,
                               localSequence: UInt32,
                               gasLimit: UInt64 = 250_000,
                               maxFeePerGas: UInt64 = 0x3b9a_ca00,
                               maxPriorityFeePerGas: UInt64 = 0xf4240) async throws -> Sent {
        guard let publicKey = VibenetDeviceKey.publicKeyXY() else { throw Failure.noKey }
        guard let contracts = await VibenetConfig.current(),
              let authenticator = VibenetTransaction.data(fromHex: contracts.p256Authenticator)
        else { throw Failure.cannotCompose }

        let payload = VibenetAccountChanges.authorizeActorPayload(
            actorId: newActorID, authenticator: newAuthenticator, scope: scope, policyData: policyData)
        let change = VibenetTransaction.Change.authorizeActor(payload)
        let changeHash = VibenetAccountChanges.changeHash(
            changeType: VibenetAccountChanges.authorizeActor, payload: payload)
        let sequenceWord = VibenetAccountChanges.localSequenceWord(epoch: localEpoch, sequence: localSequence)

        // Signature 1: THIS PHONE, as the account's admin, approving the
        // exact digest the Keystore will recompute and check.
        let configDigest = VibenetAccountChanges.changesDigest(
            account: account, chainID: VibenetSigner.chainID, sequence: sequenceWord,
            changeHashes: [changeHash])
        let configSig: Data
        do { configSig = try VibenetDeviceKey.sign(digest: configDigest) }
        catch { throw Failure.signingRefused }
        guard configSig.count == 64,
              let configAuth = VibenetP256Auth.senderAuth(authenticator: authenticator,
                                                          r: configSig.prefix(32),
                                                          s: configSig.suffix(32),
                                                          publicKeyXY: publicKey)
        else { throw Failure.cannotCompose }

        let configChange = VibenetTransaction.ConfigChange(
            sequence: sequenceWord, changes: [change], auth: configAuth)

        guard let nonceHex = await VibenetChain.call(
                method: "eth_getTransactionCount",
                params: ["0x" + VibenetTransaction.hex(account), "latest"]) as? String,
              let nonce = UInt64(nonceHex.dropFirst(2), radix: 16)
        else { throw Failure.cannotCompose }

        let feePayable = maxFeePerGas > 0 || maxPriorityFeePerGas > 0
        var payer: Data?
        switch await payerOffer(for: account, gasLimit: gasLimit) {
        case .sponsored(let address): payer = address
        case .declined:   if feePayable { throw Failure.noSponsor }
        case .unreadable: if feePayable { throw Failure.sponsorUnreadable }
        }

        let fields = VibenetTransaction.Fields(
            chainID: VibenetSigner.chainID, sender: account, nonceSequence: nonce,
            maxPriorityFeePerGas: maxPriorityFeePerGas, maxFeePerGas: maxFeePerGas,
            gasLimit: gasLimit, accountChanges: [.config(configChange)], payer: payer ?? Data())

        // Signature 2: the outer transaction itself — a SECOND prompt, see
        // this function's own doc for why it is not the same claim as #1.
        let outerDigest = Data(Keccak256.hash([UInt8](VibenetTransaction.senderSigningPreimage(fields))))
        let outerSig: Data
        do { outerSig = try VibenetDeviceKey.sign(digest: outerDigest) }
        catch { throw Failure.signingRefused }
        guard outerSig.count == 64,
              let outerAuth = VibenetP256Auth.senderAuth(authenticator: authenticator,
                                                         r: outerSig.prefix(32),
                                                         s: outerSig.suffix(32),
                                                         publicKeyXY: publicKey)
        else { throw Failure.cannotCompose }

        let mine = "0x" + VibenetTransaction.hex(
            VibenetTransaction.encoded(fields, senderAuth: outerAuth))
        let raw = payer == nil ? mine : try await sponsor(rawTransaction: mine)
        let hash = try await broadcast(rawTransaction: raw)
        return Sent(account: account, transactionHash: hash, payer: payer)
    }

    /// WHAT WAS AUTHORIZED LANDS IN THE CORPUS — same ruling as a send, a
    /// third `sourceRef` namespace (`vibenet:authorize:`) so none of the
    /// three can ever dedupe against another.
    @MainActor
    static func landAuthorizeReceipt(_ sent: Sent, newActorHex: String, in context: ModelContext) {
        let ref = "vibenet:authorize:\(sent.transactionHash)"
        let existing = FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref })
        if let found = try? context.fetch(existing), !found.isEmpty { return }

        let thing = Thing(
            kind: .transaction,
            title: String(localized: "Authorized a new key on a vibenet account"),
            content: VibenetExplorer.tx(sent.transactionHash),
            source: VibenetIdentity.source,
            capturedAt: .now,
            tags: sent.payer == nil ? ["Permissions"] : ["Permissions", "Sponsored"],
            sourceRef: ref)
        thing.walletAddress = "0x" + VibenetTransaction.hex(sent.account)
        thing.summary = String(localized: "\(newActorHex) can now act for this account.")
        context.insert(thing)
        try? context.save()
    }
}
