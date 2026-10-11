import Foundation

/// What a pending Safe transaction would do to the Safe's own balances, asked
/// of Alchemy's simulation API when the sign block opens (prd §1246) — the
/// plan, the request body and the parse, Foundation-only and pure, so
/// `safetx-selftest.sh` compiles it whole beside `SafeTransaction.swift` and
/// drives it with fixtures. The one network call is `SafeSimulator`.
///
/// **What is simulated is the SAFE'S CALL, not `execTransaction`.** The
/// request sends `{from: safe, to, value, data}` — the call the Safe would make
/// once the threshold is met — because the signatures that would let the
/// real `execTransaction` run do not exist yet. So the answer says nothing
/// about gas, a refund, or whether enough owners will ever sign, and the one
/// footnote under the rows says exactly that.
///
/// **Simulated only where the reading allows it, and said when it is not.**
/// A top-level DELEGATECALL runs another contract's code in the Safe's own
/// storage, which a call from the Safe does not reproduce, so it is never
/// simulated. A batch is simulated as a bundle of its calls, in order, from
/// the Safe — only when every call is a CALL and there are at most
/// `bundleLimit` of them. Every other case is a `Skip` with a reason, and the
/// surface prints the reason rather than a guess.
///
/// UNMEASURED: the request and response shapes are authored from Alchemy's
/// published API reference (`alchemy_simulateAssetChanges`,
/// `alchemy_simulateAssetChangesBundle`), not from a response this build has
/// seen — no build host reaches Alchemy. So the parse is defensive: a change
/// that touches the Safe and cannot be read makes the WHOLE answer
/// unreadable, never a shorter list (§83: a list missing the one outflow it
/// could not parse is the fluent wrong summary).
enum SafeSimulation {

    /// The Safe chains Alchemy's simulation serves, by the Alchemy network id
    /// every other Alchemy read in this app uses for that chain (their hosts
    /// are declared in `NetworkReach`). Gnosis Chain (100) is absent: this app
    /// reads it through `GnosisPayBridge`'s public RPCs and has no Alchemy
    /// host for it, so a Gnosis Safe is `.chainNotServed`.
    static let networks: [Int: String] = [
        1: "eth-mainnet",
        8453: "base-mainnet",
        42161: "arb-mainnet",
        10: "opt-mainnet",
        137: "matic-mainnet",
    ]

    /// `alchemy_simulateAssetChangesBundle`'s documented ceiling — three
    /// transactions. A longer batch is skipped and says so; it is never
    /// simulated as its first three.
    static let bundleLimit = 3

    /// One call as Alchemy takes it: hex QUANTITY value, hex data.
    struct Call: Equatable {
        let from: String
        let to: String
        let value: String
        let data: String

        var json: [String: Any] { ["from": from, "to": to, "value": value, "data": data] }
    }

    /// Why a transaction was not simulated. Each is a sentence on screen.
    enum Skip: Equatable {
        /// The Safe's chain has no Alchemy host in this app.
        case chainNotServed
        /// A top-level DELEGATECALL, or one inside the batch.
        case delegateCall
        /// A batch longer than `bundleLimit`.
        case tooManyCalls(Int)
        /// The call or the batch did not read well enough to send.
        case unreadable
        /// Asked, and the answer did not come or did not parse.
        case failed
    }

    enum Plan: Equatable {
        case single(Call)
        case bundle([Call])
        case skip(Skip)
    }

    /// What to ask, or why not to.
    static func plan(chainId: Int, safe: String, tx: SafeTransaction,
                     reading: SafeCalldata) -> Plan {
        guard networks[chainId] != nil else { return .skip(.chainNotServed) }
        switch tx.operation {
        case 0:
            guard let value = quantity(tx.value) else { return .skip(.unreadable) }
            return .single(Call(from: safe, to: tx.to, value: value, data: hexData(tx.data)))
        case 1:
            // A DELEGATECALL is simulable only as the batch a known MultiSend
            // would run — which is exactly when the reader says `.batch`.
            guard case .batch(let calls) = reading else { return .skip(.delegateCall) }
            guard !calls.isEmpty else { return .skip(.unreadable) }
            guard calls.allSatisfy({ $0.operation == 0 }) else { return .skip(.delegateCall) }
            guard calls.count <= bundleLimit else { return .skip(.tooManyCalls(calls.count)) }
            var out: [Call] = []
            for call in calls {
                guard let value = quantity(call.value) else { return .skip(.unreadable) }
                out.append(Call(from: safe, to: call.to, value: value, data: hexData(call.data)))
            }
            return out.count == 1 ? .single(out[0]) : .bundle(out)
        default:
            return .skip(.unreadable)
        }
    }

    /// The JSON-RPC body for a plan, nil for a skip.
    static func requestBody(_ plan: Plan) -> [String: Any]? {
        switch plan {
        case .single(let call):
            return ["id": 1, "jsonrpc": "2.0",
                    "method": "alchemy_simulateAssetChanges",
                    "params": [call.json]]
        case .bundle(let calls):
            return ["id": 1, "jsonrpc": "2.0",
                    "method": "alchemy_simulateAssetChangesBundle",
                    "params": [calls.map(\.json)]]
        case .skip:
            return nil
        }
    }

    /// A uint256 (decimal or hex) as a JSON-RPC QUANTITY: `0x`, no leading
    /// zeros, `0x0` for zero. Nil when it does not read — the encoder in
    /// `SafeABI` is the one judge of whether a value fits.
    static func quantity(_ uint256: String) -> String? {
        guard let word = SafeABI.word(uint256: uint256) else { return nil }
        let digits = String(SafeABI.hex(word).dropFirst(2).drop(while: { $0 == "0" }))
        return "0x" + (digits.isEmpty ? "0" : digits)
    }

    private static func hexData(_ data: String) -> String {
        data.isEmpty ? "0x" : data
    }

    // MARK: - The answer

    /// One asset's NET change for the Safe — negative is out. Several
    /// transfers of one asset (a batch, or a swap's route) fold into one line.
    struct Line: Equatable {
        let symbol: String
        let amount: Double
        /// Lowercased; nil for the chain's native coin.
        let contract: String?
    }

    enum Reading: Equatable {
        /// Every balance change for the Safe, in the order first seen. Empty
        /// means the simulation answered and nothing moved in or out.
        case changes([Line])
        /// The call reverted in simulation, with the reason Alchemy gave.
        case reverted(String?)
    }

    /// Reads Alchemy's answer for `safe`. Nil when it is not an answer this
    /// parser understands — a JSON-RPC error, a missing `changes`, or a
    /// transfer touching the Safe whose amount or asset it cannot name.
    ///
    /// Only `TRANSFER` changes count: an `APPROVE` moves no balance, and the
    /// decoded call above the rows already names an approval.
    static func parse(_ root: Any?, safe: String, bundle: Bool) -> Reading? {
        guard let root = root as? [String: Any] else { return nil }
        if let error = root["error"], !(error is NSNull) { return nil }
        let results: [[String: Any]]
        if bundle {
            guard let array = root["result"] as? [[String: Any]], !array.isEmpty else { return nil }
            results = array
        } else {
            guard let one = root["result"] as? [String: Any] else { return nil }
            results = [one]
        }
        // A bundle is one Safe transaction: if any call in it reverts, the
        // MultiSend reverts them all, so one revert is the whole answer.
        for result in results {
            if let error = result["error"], !(error is NSNull) {
                return .reverted(revertReason(error))
            }
        }
        let me = safe.lowercased()
        var order: [String] = []
        var net: [String: Line] = [:]
        for result in results {
            guard let changes = result["changes"] as? [[String: Any]] else { return nil }
            for change in changes {
                guard (change["changeType"] as? String)?.uppercased() == "TRANSFER" else { continue }
                let from = (change["from"] as? String)?.lowercased()
                let to = (change["to"] as? String)?.lowercased()
                let sign: Double
                if from == me, to != me { sign = -1 }
                else if to == me, from != me { sign = 1 }
                else { continue }   // not the Safe's money, or the Safe paying itself
                guard let amount = amount(change), let symbol = assetName(change) else { return nil }
                let contract = (change["contractAddress"] as? String)
                    .flatMap { $0.isEmpty ? nil : $0.lowercased() }
                let key = contract ?? "native:" + symbol
                if net[key] == nil { order.append(key) }
                let previous = net[key]?.amount ?? 0
                net[key] = Line(symbol: symbol, amount: previous + sign * amount, contract: contract)
            }
        }
        return .changes(order.compactMap { net[$0] }.filter { $0.amount != 0 })
    }

    /// The amount, positive, from `rawAmount` and `decimals` when both read
    /// (exact up to a Double), else the pre-scaled `amount` string, else 1 for
    /// a single ERC-721 token. Nil when none of those reads.
    static func amount(_ change: [String: Any]) -> Double? {
        if let raw = number(change["rawAmount"]), let decimals = integer(change["decimals"]),
           decimals >= 0, decimals <= 77 {
            return raw / pow(10, Double(decimals))
        }
        if let scaled = number(change["amount"]) { return scaled }
        if (change["assetType"] as? String)?.uppercased() == "ERC721" { return 1 }
        return nil
    }

    /// The asset's symbol, else its name. Nil when it has neither — an
    /// amount of an unnamed thing is not a line anybody can check.
    static func assetName(_ change: [String: Any]) -> String? {
        for key in ["symbol", "name"] {
            if let text = (change[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty { return text }
        }
        return nil
    }

    private static func revertReason(_ error: Any) -> String? {
        if let text = error as? String { return text.isEmpty ? nil : text }
        guard let object = error as? [String: Any] else { return nil }
        for key in ["revertReason", "message"] {
            if let text = (object[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty { return text }
        }
        return nil
    }

    private static func number(_ any: Any?) -> Double? {
        if let d = any as? Double { return d.isFinite ? d : nil }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.lowercased().hasPrefix("0x") {
                return UInt64(t.dropFirst(2), radix: 16).map(Double.init)
            }
            return Double(t).flatMap { $0.isFinite ? $0 : nil }
        }
        return nil
    }

    private static func integer(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s) }
        return nil
    }
}
