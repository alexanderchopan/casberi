import Foundation

/// **GAS FOR YOUR AZTEC ACCOUNT (prd §1700e item 2): open, no check.** Your
/// Safe sends AZTEC into Aztec's own Fee Juice portal for the account — one
/// operation of two calls (approve, `depositToAztecPublic`) through
/// `YourAccountChain.privateCalls`, Lend's path: simulated as the account,
/// Face ID, the bundler. Aztec carries the message in minutes; then the engine
/// claims it in a transaction whose own fee is paid from what it claims, and
/// Holdings shows Fee Juice. Fee Juice is gas only: it cannot be sent to anyone.
/// Measured 2026-11-04 on a copy of mainnet: ~113k gas, no check of any kind.
///
/// **PRIVATE GAS (prd §1700aa).** A deposit to the account names it on
/// Ethereum, and a send paid from the account's own Fee Juice names it on
/// Aztec as that send's fee payer. So the deposit now goes to the ecosystem's
/// shared private fee contract (the engine's `feeJuicePlan` answers its
/// address and a secret only this account can open), nothing claims it on its
/// own, and the next send mints it and pays from it in one transaction; later
/// sends pay from what is left inside. The contract is the community's and
/// unaudited: it holds gas only, one top-up at a time. A deposit made before
/// this, or on a rollup the contract is not pinned to, is the account's own
/// and is claimed as before.
enum AztecGas {
    static let token = "0xa27ec0006e59f245217ff08cd52a7e8b169e62d2"   // AZTEC, 18 decimals
    static let portal = "0x534361be805ca30bdb6404ec5e6cdaffb3e9f3b3"  // Aztec's FeeJuicePortal (V6)
    /// `DepositToAztecPublic(bytes32 indexed to, uint256 amount, bytes32 secretHash, bytes32 key, uint256 index)`
    static let depositTopic = "0xcb43dda0de11e57048e9d074ae7474446335afc906a0e5789d624fa5422629e3"

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// The least gas a first move brings along: Aztec takes a transaction only
    /// from an account that can cover its most (some 15 AZTEC, measured
    /// 2026-11-04), and a claim pays from what it claims.
    static let rideAlong = "30000000000000000000" // 30 AZTEC
    /// Below this the account's OWN Fee Juice is short for one more
    /// transaction (Aztec asks an account paying for itself to cover a
    /// transaction's most, some 15 AZTEC).
    static let enough = Decimal(string: "15000000000000000000")!
    /// Below this what the account keeps in the private fee contract is short
    /// (prd §1700aa): a send there declares limits measured for it, a few
    /// AZTEC, or the fixed ones, under 10 at the fees read 2026-11-10.
    static let enoughPrivate = Decimal(string: "10000000000000000000")!

    /// A gas deposit, written and not yet sent: its two calls, and what the
    /// claim will need once it lands.
    struct Plan {
        let nonce: UInt64
        let units: String
        let calls: [(to: String, data: String, value: String)]
        /// `"private"` or `"own"`, the engine's word for where it goes.
        let kind: String
    }

    /// The two calls that send `units` AZTEC to Aztec as your account's gas:
    /// to the private fee contract, or to the account where that is not this
    /// rollup's (the engine says which).
    @MainActor
    static func plan(units: String) async throws -> Plan {
        guard !DemoMode.isActive else { throw Failure(message: String(localized: "The demo moves nothing")) }
        guard let amount = SafeABI.word(uint256: units) else { throw Failure(message: String(localized: "This amount could not be written")) }
        let place = try await place()
        return Plan(nonce: place.nonce, units: units, calls: calls(to: place.to, amount: hex(amount), secretHash: place.secretHash),
                    kind: place.kind)
    }

    /// Where a new gas deposit goes, asked of the engine: a fresh nonce, the
    /// recipient and the secret's hash as 32-byte words, and the engine's
    /// word for the place.
    @MainActor
    private static func place() async throws -> (nonce: UInt64, to: String, secretHash: String, kind: String) {
        let nonce = UInt64.random(in: 1...UInt64.max)
        guard let plan = try await AztecEngine.shared.call("feeJuicePlan", [String(nonce)]) as? [String: Any],
              let to = (plan["to"] as? String).flatMap(word), let secretHash = (plan["secretHash"] as? String).flatMap(word) else {
            throw Failure(message: String(localized: "Your Aztec account is not ready"))
        }
        return (nonce, to, secretHash, plan["kind"] as? String ?? "own")
    }

    /// Approve, then the portal's `depositToAztecPublic(to, amount, secretHash)`.
    static func calls(to: String, amount: String, secretHash: String) -> [(to: String, data: String, value: String)] {
        [(to: token, data: "0x095ea7b3" + pad(portal) + amount, value: "0"),
         (to: portal, data: "0x284b5dc6" + to + amount + secretHash, value: "0")]
    }

    // MARK: - Gas bought with what you are moving (prd §1700aa)

    /// AZTEC on Ethereum, as Swap names a token.
    static let aztec = YourAccountOp.Token(symbol: "AZTEC", decimals: 18, contract: token)
    /// The least a bought top-up may come to (20 AZTEC): under it the price
    /// moved too far from the one the sale was sized by, and nothing is sold.
    static let leastBought = Decimal(string: "20000000000000000000")!

    /// **NO "BUY AZTEC FIRST".** An account holding no AZTEC was stopped at
    /// "Your Aztec account needs 30 AZTEC as gas the first time." Instead a
    /// little of the token being moved is sold for it, in the same operation.
    /// How much of a token worth `sellPrice` dollars buys one top-up (30 AZTEC
    /// at `aztecPrice`), base units: 4% over, for the two pools' fees and the
    /// room Swap leaves a price to move. nil without both prices.
    static func saleUnits(sellPrice: Double?, aztecPrice: Double?, decimals: Int) -> String? {
        guard let sellPrice, let aztecPrice, sellPrice > 0, aztecPrice > 0 else { return nil }
        let top = (Decimal(string: rideAlong) ?? 0) / pow(10, 18)
        var raw = top * Decimal(aztecPrice) / Decimal(sellPrice) * Decimal(string: "1.04")! * pow(10, decimals), up = Decimal()
        NSDecimalRound(&up, &raw, 0, .up)
        return up > 0 ? NSDecimalNumber(decimal: up).stringValue : nil
    }

    /// The calls that sell `units` of `sell` for AZTEC through Swap's own
    /// pools and send what the sale is sure to pay to Aztec as gas: Swap's
    /// checked calls (an approval or hand-over to a pinned router, one swap),
    /// then approve and the portal's deposit for the swap's least. What it
    /// pays over the least stays in your account as AZTEC.
    @MainActor
    static func plan(selling sell: YourAccountOp.Token, units: String, account: String) async throws -> Plan {
        guard !DemoMode.isActive else { throw Failure(message: String(localized: "The demo moves nothing")) }
        let net = YourAccountOp.ethereum
        let quote = try await YourAccountChain.swapQuote(net, sell: sell, buy: aztec, amount: units, account: account)
        guard let checked = YourAccountSwap.checked(quote, sell: sell, amount: units, chainId: net.chainId),
              let bought = Decimal(string: quote.minimumBuy), bought >= leastBought,
              let amount = SafeABI.word(uint256: quote.minimumBuy) else {
            throw Failure(message: String(localized: "Gas for Aztec could not be bought just now. Try again."))
        }
        let place = try await place()
        var calls: [(to: String, data: String, value: String)] = []
        for a in checked.approvals {
            guard let units = SafeABI.word(uint256: a.amount) else { throw Failure(message: String(localized: "This amount could not be written")) }
            calls.append((to: a.token, data: "0x095ea7b3" + pad(a.spender) + hex(units), value: "0"))
        }
        calls += checked.calls.map { (to: $0.to, data: "0x" + hex($0.data), value: $0.value) }
        calls += self.calls(to: place.to, amount: hex(amount), secretHash: place.secretHash)
        return Plan(nonce: place.nonce, units: quote.minimumBuy, calls: calls, kind: place.kind)
    }

    /// Keeps a planned deposit that landed in `transaction`, from its receipt.
    @MainActor @discardableResult
    static func record(_ plan: Plan, transaction: String, receipt: [String: Any]) -> AztecAccountStore.GasDeposit? {
        guard let message = message(in: receipt) else { return nil }
        let kept = AztecAccountStore.GasDeposit(nonce: plan.nonce, amountUnits: plan.units, transaction: transaction,
                                                messageHash: message.key, leafIndex: message.index, claimed: false, at: .now,
                                                kind: plan.kind)
        AztecAccountStore.shared.addGas(kept)
        return kept
    }

    /// Whether your Aztec account cannot pay for its next move: too little
    /// in the private fee contract AND too little of its own, and none on its
    /// way. (Its own Fee Juice still pays, in the open, when the contract's
    /// cannot.)
    @MainActor
    static var needed: Bool {
        let (gas, inside, own) = standing
        return needed(gas: gas, inside: inside, own: own)
    }
    static func needed(gas: [AztecAccountStore.GasDeposit], inside: Decimal, own: Decimal) -> Bool {
        if gas.contains(where: { !$0.claimed }) { return false }
        return inside < enoughPrivate && own < enough
    }

    /// **A MOVE-IN BRINGS PRIVATE GAS WHENEVER THE CONTRACT'S IS SHORT (prd
    /// §1700aa).** Whatever the account holds of its own: gas of its own names
    /// the account on every send, so an account funded before §1700aa would
    /// otherwise stay in the open until that ran out. Not while a private
    /// deposit is already on its way: one top-up at a time.
    @MainActor
    static var ridesAlong: Bool {
        let (gas, inside, _) = standing
        return ridesAlong(gas: gas, inside: inside)
    }
    static func ridesAlong(gas: [AztecAccountStore.GasDeposit], inside: Decimal) -> Bool {
        if gas.contains(where: { $0.isPrivate && !$0.claimed }) { return false }
        return inside < enoughPrivate
    }

    /// **HOW THE ACCOUNT'S GAS STANDS (prd §1761)**, for Holdings' gas row
    /// and its tray: a top-up on its way, nothing, under one transaction's
    /// worth, or enough. The thresholds are the ones a send already uses.
    enum Standing: Equatable { case arriving, none, low, enough }
    @MainActor
    static var state: Standing {
        let (gas, inside, own) = standing
        return state(waiting: gas.contains { !$0.claimed }, inside: inside, own: own)
    }
    static func state(waiting: Bool, inside: Decimal, own: Decimal) -> Standing {
        if waiting { return .arriving }
        if inside + own <= 0 { return .none }
        return inside >= enoughPrivate || own >= enough ? .enough : .low
    }

    /// The deposits kept, what the account holds inside the fee contract and
    /// what it holds of its own, base units.
    @MainActor
    private static var standing: (gas: [AztecAccountStore.GasDeposit], inside: Decimal, own: Decimal) {
        let store = AztecAccountStore.shared
        let juice = store.snapshot.holdings.first { $0.kind == .feeJuice }
        return (store.snapshot.gas ?? [],
                juice?.privateUnits.flatMap { Decimal(string: $0) } ?? 0,
                juice?.publicUnits.flatMap { Decimal(string: $0) } ?? 0)
    }

    /// **WHAT A SEND MAY MINT (prd §1700aa).** The private gas deposits nobody
    /// has minted yet, as the engine's sends take them: JSON of
    /// `[{ nonce, amount, leafIndex, messageHash }]`.
    @MainActor
    static var unminted: String { unminted(AztecAccountStore.shared.snapshot.gas ?? []) }
    static func unminted(_ gas: [AztecAccountStore.GasDeposit]) -> String {
        let rows = gas.filter { $0.isPrivate && !$0.claimed }.map {
            ["nonce": String($0.nonce), "amount": $0.amountUnits, "leafIndex": $0.leafIndex, "messageHash": $0.messageHash]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    /// A send's answer names the deposit it minted, if it minted one: that
    /// deposit is spent and never offered again.
    @MainActor
    static func spent(by answer: [String: Any]?) {
        guard let text = answer?["gasNonce"] as? String, let nonce = UInt64(text) else { return }
        AztecAccountStore.shared.markGasClaimed(nonce)
    }

    /// **GAS ON ITS OWN (Send's "Add gas").** One top-up from your account on
    /// Ethereum: the AZTEC it holds, or, holding too little, bought with its
    /// USDC (prd §1700aa). Neither: it says what is missing.
    @MainActor
    static func topUp(stage: @escaping @Sendable (YourAccountChain.Stage) async -> Void) async throws -> AztecAccountStore.GasDeposit {
        guard let account = YourAccountKey.address else { throw Failure(message: String(localized: "There is no account on this iPhone")) }
        let held = Decimal(string: await AztecMove.balance(of: token, at: account)) ?? 0
        if held >= (Decimal(string: rideAlong) ?? 0) { return try await send(plan(units: rideAlong), stage: stage) }
        let dollar = YourAccountOp.dollar(on: YourAccountOp.ethereum)
        let usdc = await MainnetPrices.prices(for: ["usdc"])["usdc"]
        let aztecPrice = await DefiLlamaPrices.prices(for: [("eth-mainnet", token)]).values.first?.price
        guard let contract = dollar.contract,
              let sale = saleUnits(sellPrice: usdc, aztecPrice: aztecPrice, decimals: dollar.decimals),
              (Decimal(string: await AztecMove.balance(of: contract, at: account)) ?? 0) >= (Decimal(string: sale) ?? 0) else {
            throw Failure(message: String(localized: "Your account needs a little USDC on Ethereum to buy gas for Aztec"))
        }
        return try await send(plan(selling: dollar, units: sale, account: account), stage: stage)
    }

    /// Sends a planned top-up from your Safe and keeps it.
    @MainActor
    static func send(_ planned: Plan, stage: @escaping @Sendable (YourAccountChain.Stage) async -> Void) async throws -> AztecAccountStore.GasDeposit {
        let sent = try await YourAccountChain.privateCalls(
            planned.calls, on: YourAccountOp.ethereum, reason: String(localized: "Move AZTEC to your Aztec account for gas"), stage: stage)
        guard case .landed(let transaction?, _) = sent.outcome else {
            throw Failure(message: String(localized: "Sent; Aztec will see it once Ethereum shows it"))
        }
        guard let receipt = try? await YourAccountChain.rpc(YourAccountOp.ethereum, "eth_getTransactionReceipt", [transaction]) as? [String: Any],
              let kept = record(planned, transaction: transaction, receipt: receipt) else {
            throw Failure(message: String(localized: "Sent, but its message to Aztec could not be read yet"))
        }
        return kept
    }

    /// Claims every deposit of the account's own that Aztec has carried; one
    /// that is not there yet waits. A private deposit is never claimed here:
    /// the next send mints it (prd §1700aa). One a send did mint while the app
    /// was away is read back from the chain and forgotten.
    @MainActor
    static func settle() async {
        let waiting = unminted
        if waiting != "[]",
           let answer = try? await AztecEngine.shared.call("gasSpent", [waiting]) as? [String: Any] {
            for nonce in (answer["spent"] as? [String] ?? []).compactMap({ UInt64($0) }) {
                AztecAccountStore.shared.markGasClaimed(nonce)
            }
        }
        for deposit in AztecAccountStore.shared.snapshot.gas ?? [] where !deposit.claimed && !deposit.isPrivate {
            guard let ready = try? await AztecEngine.shared.call("feeJuiceReady", [deposit.messageHash]) as? [String: Any],
                  ready["ready"] as? Bool == true else { continue }
            do {
                _ = try await AztecEngine.shared.call("feeJuiceClaim", [String(deposit.nonce), deposit.amountUnits, deposit.leafIndex])
                AztecAccountStore.shared.markGasClaimed(deposit.nonce)
                await AztecAccountStore.shared.refresh()
            } catch {
                NSLog("aztecEngine| gas | claim waits: %@", error.localizedDescription)
            }
        }
    }

    /// The portal's event in a receipt: (key, leaf index) as text.
    static func message(in receipt: [String: Any]) -> (key: String, index: String)? {
        for log in receipt["logs"] as? [[String: Any]] ?? [] {
            guard (log["address"] as? String)?.lowercased() == portal,
                  (log["topics"] as? [String])?.first?.lowercased() == depositTopic,
                  let data = log["data"] as? String, data.count == 2 + 64 * 4 else { continue }
            let words = stride(from: 2, to: data.count, by: 64).map { i -> String in
                let a = data.index(data.startIndex, offsetBy: i)
                return String(data[a..<data.index(a, offsetBy: 64)])
            }
            // amount, secretHash, key, index
            guard let index = UInt64(words[3].drop { $0 == "0" }.isEmpty ? "0" : String(words[3].drop { $0 == "0" }), radix: 16) else { return nil }
            return ("0x" + words[2], String(index))
        }
        return nil
    }

    private static func word(_ hex: String) -> String? {
        let body = hex.lowercased().hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard body.count <= 64, body.allSatisfy(\.isHexDigit) else { return nil }
        return String(repeating: "0", count: 64 - body.count) + body
    }
    private static func pad(_ address: String) -> String { word(address) ?? "" }
    private static func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
}
