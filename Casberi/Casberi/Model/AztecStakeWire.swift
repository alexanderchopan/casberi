import Foundation

/// AZTEC staked on Aztec mainnet, read off Ethereum (2026-10-12, prd §1277).
/// Foundation-only and pure, so `scripts/aztec-stake-selftest.sh` compiles it
/// whole against replies saved off mainnet. `AztecStaking` is the app half.
///
/// MEASURED (2026-10-12, keyless, every one checked against a real reply):
/// - A stake is an ATTESTER on a Rollup. Whoever may withdraw it is named in
///   the Rollup's `ValidatorQueued(attester indexed, withdrawer indexed)`
///   (topic1, topic2), for a stake made directly AND for one delegated
///   through the StakingRegistry: a delegator's own wallet is the withdrawer
///   (tx 0x47e2…c6e5). So one filtered `eth_getLogs` over the three Rollups
///   finds every attester a wallet can withdraw — 0.5s for full history on
///   `rpc.mevblocker.io`, the Wallet's first mainnet host.
/// - `getAttesterView(address)` (`0x34a51ed5`) returns eleven static words:
///   status (0 none, 1 validating, 2 zombie, 3 exiting), effective balance,
///   then the exit — withdrawal id, amount, exitable-at (unix seconds),
///   recipient, is-recipient, exists — two config words, and the withdrawer.
/// - The two earlier Rollups hold nothing now: 25 of 25 sampled attesters on
///   each read status 0. They stay in the log query because a wallet's first
///   stake may have been made there, and a status-0 view drops itself.
enum AztecStakeWire {

    /// The Rollup Aztec's mainnet node names (`node_getNodeInfo`), then the
    /// two before it.
    static let rollups = ["0x91ff8bbd8ebb07893010d50a48a1609e5ebd8e34",
                          "0x603bb2c05d474794ea97805e8de69bccfb3bca12",
                          "0xae2001f7e21d5ecabf6234e9fdd1e76f50f74962"]

    /// The first `ValidatorQueued` on any of them: the log walk's floor.
    static let firstBlock = 23_790_839

    static let validatorQueued = "0x676247b4195b3fe545499177befc02b4b4bebd3805a2283b30defcae63d54661"
    static let getAttesterView = "0x34a51ed5"

    static let decimals = 1e18

    enum Status: Int, Sendable {
        case none = 0, validating, zombie, exiting
    }

    struct Stake: Equatable, Sendable {
        /// The wallet that can withdraw it, lowercased.
        let owner: String
        let attester: String
        let rollup: String
        let status: Status
        /// What is staked now, in AZTEC.
        let staked: Double
        /// What is on its way out, in AZTEC, and when it can be withdrawn.
        let exitAmount: Double
        let exitableAt: Date?

        /// The AZTEC this stake holds: what is staked, or what is leaving.
        var amount: Double { status == .exiting ? exitAmount : staked }
    }

    // MARK: - Calls

    static func topic(_ address: String) -> String {
        "0x" + String(repeating: "0", count: 24) + address.lowercased().dropFirst(2)
    }

    static func viewCall(_ attester: String) -> String {
        getAttesterView + String(repeating: "0", count: 24) + attester.lowercased().dropFirst(2)
    }

    /// `eth_getLogs` params for one wallet's stakes in a block range.
    static func logFilter(withdrawer: String, from: Int, to: Int) -> [String: Any] {
        ["address": rollups,
         "topics": [validatorQueued, NSNull(), topic(withdrawer)],
         "fromBlock": "0x" + String(from, radix: 16),
         "toBlock": "0x" + String(to, radix: 16)]
    }

    // MARK: - Reading

    /// The (attester, rollup) pairs a wallet can withdraw, from its
    /// `ValidatorQueued` logs. A log for another withdrawer, from another
    /// contract, or removed by a reorg is not this wallet's.
    static func attesters(fromLogs logs: [[String: Any]], withdrawer: String) -> [String] {
        let me = topic(withdrawer)
        var out: [String] = []
        for log in logs {
            guard (log["removed"] as? Bool) != true,
                  let address = (log["address"] as? String)?.lowercased(), rollups.contains(address),
                  let topics = (log["topics"] as? [String])?.map({ $0.lowercased() }), topics.count == 3,
                  topics[0] == validatorQueued, topics[2] == me else { continue }
            let key = "0x" + topics[1].suffix(40) + "@" + address
            if !out.contains(key) { out.append(key) }
        }
        return out
    }

    /// One attester's stake from its `getAttesterView` reply, or nil when it
    /// holds nothing (status 0), the reply is malformed, or the view names a
    /// different withdrawer — the event said who queued it, the view says
    /// who can take it out now, and only the second is the person's money.
    static func stake(view hex: String?, owner: String, attester: String, rollup: String) -> Stake? {
        guard let hex else { return nil }
        let body = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard body.count == 11 * 64, body.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        let words: [Substring] = (0..<11).map {
            let a = body.index(body.startIndex, offsetBy: $0 * 64)
            return body[a..<body.index(a, offsetBy: 64)]
        }
        func uint(_ w: Substring) -> Double {
            w.reduce(0.0) { $0 * 16 + Double(Int(String($1), radix: 16) ?? 0) }
        }
        guard let status = Status(rawValue: Int(uint(words[0]))), status != .none else { return nil }
        let withdrawer = "0x" + words[10].suffix(40).lowercased()
        guard withdrawer == owner.lowercased() else { return nil }
        let exists = uint(words[7]) != 0
        let exitable = uint(words[4])
        return Stake(owner: owner.lowercased(), attester: attester.lowercased(), rollup: rollup.lowercased(),
                     status: status,
                     staked: uint(words[1]) / decimals,
                     exitAmount: exists ? uint(words[3]) / decimals : 0,
                     exitableAt: exists && exitable > 0 ? Date(timeIntervalSince1970: exitable) : nil)
    }

    // MARK: - Words

    /// The row's state: "Validating", "Stopped" (a zombie: slashed below the
    /// minimum, so it can only exit), "Withdrawing · from Oct 14", or
    /// "Ready to withdraw" once that date has passed.
    static func state(_ stake: Stake, now: Date = .now) -> String {
        switch stake.status {
        case .none: return ""
        case .validating: return String(localized: "Validating")
        case .zombie: return String(localized: "Stopped")
        case .exiting:
            guard let at = stake.exitableAt else { return String(localized: "Withdrawing") }
            if at <= now { return String(localized: "Ready to withdraw") }
            return String(localized: "Withdrawing · from \(at.formatted(.dateTime.month(.abbreviated).day()))")
        }
    }

    /// Whether the row's state asks something of the person: a stake that
    /// can be withdrawn and has not been, or one that stopped.
    static func needsYou(_ stake: Stake, now: Date = .now) -> Bool {
        switch stake.status {
        case .zombie: return true
        case .exiting: return stake.exitableAt.map { $0 <= now } ?? false
        default: return false
        }
    }
}
