import Foundation

/// **GAS FOR YOUR AZTEC ACCOUNT (prd §1700e item 2): open, no check.** Your
/// Safe sends AZTEC into Aztec's own Fee Juice portal for the account — one
/// operation of two calls (approve, `depositToAztecPublic`) through
/// `YourAccountChain.privateCalls`, Lend's path: simulated as the account,
/// Face ID, the bundler. Aztec carries the message in minutes; then the engine
/// claims it in a transaction whose own fee is paid from what it claims, and
/// Holdings shows Fee Juice. Fee Juice is gas only: it cannot be sent to anyone.
/// Measured 2026-11-04 on a copy of mainnet: ~113k gas, no check of any kind.
enum AztecGas {
    static let token = "0xa27ec0006e59f245217ff08cd52a7e8b169e62d2"   // AZTEC, 18 decimals
    static let portal = "0x534361be805ca30bdb6404ec5e6cdaffb3e9f3b3"  // Aztec's FeeJuicePortal (V6)
    /// `DepositToAztecPublic(bytes32 indexed to, uint256 amount, bytes32 secretHash, bytes32 key, uint256 index)`
    static let depositTopic = "0xcb43dda0de11e57048e9d074ae7474446335afc906a0e5789d624fa5422629e3"

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Sends `units` AZTEC from your Safe to your Aztec account as gas.
    @MainActor
    static func send(units: String, stage: @escaping @Sendable (YourAccountChain.Stage) async -> Void) async throws -> AztecAccountStore.GasDeposit {
        // The demo moves nothing (prd §217, §1475).
        guard !DemoMode.isActive else { throw Failure(message: String(localized: "The demo moves nothing")) }
        guard let amount = SafeABI.word(uint256: units) else { throw Failure(message: String(localized: "This amount could not be written")) }
        let nonce = UInt64.random(in: 1...UInt64.max)
        guard let plan = try await AztecEngine.shared.call("feeJuicePlan", [String(nonce)]) as? [String: Any],
              let to = plan["to"] as? String, let secretHash = plan["secretHash"] as? String,
              let toWord = word(to), let hashWord = word(secretHash) else {
            throw Failure(message: String(localized: "Your Aztec account is not ready"))
        }
        let amountHex = hex(amount)
        let approve = "0x095ea7b3" + pad(portal) + amountHex
        let deposit = "0x284b5dc6" + toWord + amountHex + hashWord
        let sent = try await YourAccountChain.privateCalls(
            [(to: token, data: approve, value: "0"), (to: portal, data: deposit, value: "0")],
            on: YourAccountOp.ethereum, reason: String(localized: "Move AZTEC to your Aztec account for gas"), stage: stage)
        guard case .landed(let transaction?, _) = sent.outcome else {
            throw Failure(message: String(localized: "Sent; Aztec will see it once Ethereum shows it"))
        }
        guard let receipt = try? await YourAccountChain.rpc(YourAccountOp.ethereum, "eth_getTransactionReceipt", [transaction]) as? [String: Any],
              let message = message(in: receipt) else {
            throw Failure(message: String(localized: "Sent, but its message to Aztec could not be read yet"))
        }
        let deposit_ = AztecAccountStore.GasDeposit(nonce: nonce, amountUnits: units, transaction: transaction,
                                                    messageHash: message.key, leafIndex: message.index, claimed: false, at: .now)
        AztecAccountStore.shared.addGas(deposit_)
        return deposit_
    }

    /// Claims every deposit Aztec has carried; one that is not there yet waits.
    @MainActor
    static func settle() async {
        for deposit in AztecAccountStore.shared.snapshot.gas ?? [] where !deposit.claimed {
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
