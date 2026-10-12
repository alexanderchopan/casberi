import Foundation

/// AZTEC staked on Aztec mainnet, read off Ethereum (2026-10-12, prd §1277,
/// §1279). Foundation-only and pure, so `scripts/aztec-stake-selftest.sh`
/// compiles it whole against replies saved off mainnet. `AztecStaking` is
/// the app half.
///
/// MEASURED (2026-10-12, keyless, every one checked against a real reply):
/// - A stake is an ATTESTER. Whoever may withdraw it is named in a Rollup's
///   `ValidatorQueued(attester indexed, withdrawer indexed)` (topic1,
///   topic2), for a stake made directly AND for one delegated through the
///   StakingRegistry (tx 0x47e2…c6e5). So one filtered `eth_getLogs` over
///   the Rollups finds every attester a wallet can withdraw.
/// - **A stake LIVES on the canonical Rollup, whichever Rollup queued it**
///   (§1279). Stakes made to follow the latest Rollup moved with each
///   upgrade and emitted nothing: of one delegator's ten stakes, four queued
///   on earlier Rollups read status 0 there and VALIDATING on the current
///   one. Reading a stake where it was queued drew three of seven (§1277's
///   defect). So the view is always asked of the canonical Rollup, which the
///   Registry names (`getCanonicalRollup()`), so the next upgrade follows.
/// - `getAttesterView(address)` (`0x34a51ed5`) returns eleven static words:
///   status (0 none, 1 validating, 2 zombie, 3 exiting), effective balance,
///   then the exit — withdrawal id, amount, exitable-at (unix seconds),
///   recipient, is-recipient, exists — two config words, and the withdrawer.
/// - **Token-sale and grant tokens sit in an ATP** (a vesting vault) that one
///   of six factories made for the wallet (`ATPCreated(beneficiary indexed,
///   atp indexed, allocation)`). Its stakes are queued with the ATP's STAKER
///   contract (`getStaker()`) as withdrawer, never the wallet; the unstaked
///   rest is the ATP's own AZTEC balance, `getClaimable()` of it free to take.
///   The factories are Aztec's own list (AztecProtocol/circulating-supply-api).
/// - **Rewards are owed to a payout address, not to the wallet.** A delegated
///   stake's `StakedWithProvider(providerId, rollup, attester indexed;
///   coinbase, rewardsRecipient)` names a 0xSplits contract as the payout
///   address; its `SplitUpdated` event holds the shares (one measured: the
///   delegator 7,500 of 10,000, the provider 2,500). `getSequencerRewards
///   (coinbase)` is what the Rollup owes that address, unclaimed. A direct
///   stake's payout address is the operator's node setting, never on chain,
///   so its rewards are NOT read rather than guessed.
/// - Governance: `proposalCount()`, `getProposal(id)` (13 static words: seven
///   config, cached state, payload, proposer, creation, yea, nay) and
///   `getProposalState(id)` (0 pending, 1 active, … 5 executed). A proposal
///   opens `votingDelay` after creation and votes for `votingDuration`.
enum AztecStakeWire {

    /// Aztec mainnet's Registry, as its own node lists it (`node_getNodeInfo`).
    static let registry = "0x35b22e09ee0390539439e24f06da43d83f90e298"
    static let getCanonicalRollup = "0x971b0e6b"

    /// Every Rollup a stake may have been queued on: the canonical one when
    /// this was written, then the two before it. Discovery reads all three;
    /// rewards may still be owed on any of them.
    static let rollups = ["0x91ff8bbd8ebb07893010d50a48a1609e5ebd8e34",
                          "0x603bb2c05d474794ea97805e8de69bccfb3bca12",
                          "0xae2001f7e21d5ecabf6234e9fdd1e76f50f74962"]

    /// The first `ValidatorQueued` on any of them: the stake walk's floor.
    static let firstBlock = 23_790_839

    static let validatorQueued = "0x676247b4195b3fe545499177befc02b4b4bebd3805a2283b30defcae63d54661"
    static let getAttesterView = "0x34a51ed5"

    static let token = "0xa27ec0006e59f245217ff08cd52a7e8b169e62d2"
    static let balanceOf = "0x70a08231"

    /// The six factories that made ATPs, Aztec's own list.
    static let atpFactories = ["0x23d5e1fb8315fc3321993c272f3270712e2d5c69",   // v1, insiders
                               "0xeb7442dc9392866324421bfe9ac5367ad9bbb3a6",   // v2, genesis sale
                               "0x42df694edf32d5ac19a75e1c7f91c982a7f2a161",   // token sale
                               "0xfd6bde35ec36906d61c1977c82dc429e9b009940",   // v3, grants
                               "0xfc5344e82c8deb027f9fbc95f92a94eef91f9afc",   // v4, self-lock
                               "0x278f39b11b3de0796561e85cb48535c9f45ddfcc"]   // v5, investors
    /// The first `ATPCreated` from any of them: the vault walk's floor.
    static let atpFirstBlock = 23_291_037
    static let atpCreated = "0xae7dba32b6368fe6ee51906b83422dd0a0955cf2aeeb91e9b5960ab0fa455f07"
    static let getStaker = "0x72b45a55"
    static let getClaimable = "0xee28b744"
    static let getBeneficiary = "0x565a2e2c"

    static let stakingRegistry = "0x042df8f42790d6943f41c25c2132400fd727f452"
    static let stakedWithProvider = "0xc91c8b4e934fb8f46c6d08a34d60ceb8dbe4ab6844a7040ca4c580e5a837d5c7"
    static let splitUpdated = "0x52cd08e805db808b670064dedc5cf97374a918fc17c82d7097753189550e8d51"
    static let getSequencerRewards = "0x8789a132"

    static let governance = "0x1102471eb3378fee427121c9efcea452e4b6b75e"
    static let proposalCount = "0xda35c664"
    static let getProposal = "0xc7f758a8"
    static let getProposalState = "0x9080936f"

    /// Missed attestations in a row before a sequencer reads as stopped: the
    /// testnet Node view's own threshold (`AztecWire`, §1271).
    static let stoppedStreak = 3

    static let decimals = 1e18

    enum Status: Int, Sendable {
        case none = 0, validating, zombie, exiting
    }

    /// How the wallet holds a stake: its own, delegated to a provider, or
    /// through a token-sale vault.
    enum Via: Equatable, Sendable {
        case direct
        case provider(Int)
        case vault(String)
    }

    struct Stake: Equatable, Sendable {
        /// The watched wallet this is money of, lowercased.
        let owner: String
        /// Who can withdraw it: the wallet, or its vault's staker.
        let withdrawer: String
        let attester: String
        let rollup: String
        let status: Status
        /// What is staked now, in AZTEC.
        let staked: Double
        /// What is on its way out, in AZTEC, and when it can be withdrawn.
        let exitAmount: Double
        let exitableAt: Date?
        let withdrawalID: Int
        var via: Via = .direct
        /// The wallet's share of what the Rollups owe this stake's payout
        /// address, in AZTEC; nil where it cannot be read (a direct stake).
        var rewards: Double?
        /// Missed attestations in a row, from Aztec's node; nil unread.
        var missedStreak: Int?
        var lastAttestationSlot: Int?

        /// The AZTEC this stake holds: what is staked, or what is leaving.
        var amount: Double { status == .exiting ? exitAmount : staked }
        var isStopped: Bool { (missedStreak ?? 0) >= AztecStakeWire.stoppedStreak && status == .validating }
    }

    /// A token-sale or grant vault: AZTEC locked for the wallet, its staked
    /// part counted in its stakes.
    struct Vault: Equatable, Sendable {
        let owner: String
        let atp: String
        let staker: String
        /// AZTEC sitting in the vault, unstaked.
        let held: Double
        /// Of that, what the wallet may take now; nil when it could not be read.
        let claimable: Double?
    }

    struct Proposal: Equatable, Sendable {
        let id: Int
        /// 0 pending, 1 active; nothing else is drawn.
        let state: Int
        let opens: Date
        let closes: Date
    }

    // MARK: - Calls

    static func topic(_ address: String) -> String {
        "0x" + String(repeating: "0", count: 24) + address.lowercased().dropFirst(2)
    }

    static func word(_ n: Int) -> String {
        let hex = String(n, radix: 16)
        return String(repeating: "0", count: 64 - hex.count) + hex
    }

    static func viewCall(_ attester: String) -> String {
        getAttesterView + topic(attester).dropFirst(2)
    }

    static func range(_ from: Int, _ to: Int) -> [String: Any] {
        ["fromBlock": "0x" + String(from, radix: 16), "toBlock": "0x" + String(to, radix: 16)]
    }

    /// `eth_getLogs` params for stakes withdrawable by any of `withdrawers`.
    static func logFilter(withdrawers: [String], from: Int, to: Int) -> [String: Any] {
        var f = range(from, to)
        f["address"] = rollups
        f["topics"] = [validatorQueued, NSNull(), withdrawers.map(topic)] as [Any]
        return f
    }

    /// `eth_getLogs` params for the vaults made for one wallet.
    static func vaultFilter(beneficiary: String, from: Int, to: Int) -> [String: Any] {
        var f = range(from, to)
        f["address"] = atpFactories
        f["topics"] = [atpCreated, topic(beneficiary)]
        return f
    }

    static func providerFilter(attester: String, from: Int, to: Int) -> [String: Any] {
        var f = range(from, to)
        f["address"] = stakingRegistry
        f["topics"] = [stakedWithProvider, NSNull(), NSNull(), topic(attester)] as [Any]
        return f
    }

    static func splitFilter(coinbase: String, from: Int, to: Int) -> [String: Any] {
        var f = range(from, to)
        f["address"] = coinbase.lowercased()
        f["topics"] = [splitUpdated]
        return f
    }

    // MARK: - Words off the wire

    static func words(_ hex: String?) -> [Substring]? {
        guard let hex else { return nil }
        let body = hex.hasPrefix("0x") ? hex.dropFirst(2) : Substring(hex)
        guard !body.isEmpty, body.count % 64 == 0, body.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        return stride(from: 0, to: body.count, by: 64).map {
            let a = body.index(body.startIndex, offsetBy: $0)
            return body[a..<body.index(a, offsetBy: 64)]
        }
    }

    static func uint(_ w: Substring) -> Double {
        w.reduce(0.0) { $0 * 16 + Double(Int(String($1), radix: 16) ?? 0) }
    }

    /// A word as a small whole number, or nil when its top 48 hex digits are
    /// not zero. Every count, offset, status and id goes through here:
    /// `Int(uint(word))` traps on any word past 2^63, so one hostile or
    /// garbled reply would crash the Wallet's refresh.
    static func small(_ w: Substring) -> Int? {
        guard w.count == 64, w.prefix(48).allSatisfy({ $0 == "0" }) else { return nil }
        return Int(w.suffix(16), radix: 16)
    }

    static func address(_ w: Substring) -> String? {
        let a = "0x" + w.suffix(40).lowercased()
        return a == "0x" + String(repeating: "0", count: 40) ? nil : a
    }

    /// One address from a single-word reply (`getCanonicalRollup`,
    /// `getStaker`, `getBeneficiary`), nil for zero or a malformed reply.
    static func address(reply hex: String?) -> String? {
        guard let w = words(hex), w.count == 1 else { return nil }
        return address(w[0])
    }

    /// A whole number from a single-word reply (`proposalCount`).
    static func count(reply hex: String?) -> Int? {
        guard let w = words(hex), w.count == 1, w[0].prefix(48).allSatisfy({ $0 == "0" }) else { return nil }
        return Int(w[0].suffix(16), radix: 16)
    }

    /// One amount in AZTEC from a single-word reply.
    static func amount(reply hex: String?) -> Double? {
        guard let w = words(hex), w.count == 1 else { return nil }
        return uint(w[0]) / decimals
    }

    // MARK: - Logs

    private static func live(_ log: [String: Any], from addresses: [String]) -> [String]? {
        guard (log["removed"] as? Bool) != true,
              let address = (log["address"] as? String)?.lowercased(), addresses.contains(address),
              let topics = (log["topics"] as? [String])?.map({ $0.lowercased() }) else { return nil }
        return topics
    }

    /// "attester@withdrawer" for each stake one of `withdrawers` can take
    /// out, oldest first. A log for another withdrawer, from another
    /// contract, or removed by a reorg is not this wallet's.
    static func attesters(fromLogs logs: [[String: Any]], withdrawers: [String]) -> [String] {
        let mine = Set(withdrawers.map(topic))
        var out: [String] = []
        for log in logs {
            guard let topics = live(log, from: rollups), topics.count == 3,
                  topics[0] == validatorQueued, mine.contains(topics[2]) else { continue }
            let key = "0x" + topics[1].suffix(40) + "@0x" + topics[2].suffix(40)
            if !out.contains(key) { out.append(key) }
        }
        return out
    }

    /// The vaults Aztec's factories made for `beneficiary`.
    static func vaults(fromLogs logs: [[String: Any]], beneficiary: String) -> [String] {
        var out: [String] = []
        for log in logs {
            guard let topics = live(log, from: atpFactories), topics.count == 3,
                  topics[0] == atpCreated, topics[1] == topic(beneficiary) else { continue }
            let atp = "0x" + topics[2].suffix(40)
            if !out.contains(atp) { out.append(atp) }
        }
        return out
    }

    /// The provider and payout address a delegated stake names, newest log.
    static func provider(fromLogs logs: [[String: Any]], attester: String) -> (id: Int, coinbase: String, recipient: String)? {
        for log in logs.reversed() {
            guard let topics = live(log, from: [stakingRegistry]), topics.count == 4,
                  topics[0] == stakedWithProvider, topics[3] == topic(attester),
                  let w = words(log["data"] as? String), w.count >= 2,
                  let coinbase = address(w[0]), let recipient = address(w[1]) else { continue }
            guard let id = small(Substring(topics[1].dropFirst(2))) else { continue }
            return (id, coinbase, recipient)
        }
        return nil
    }

    /// `recipient`'s share of a split, 0…1, off its newest `SplitUpdated`
    /// (a 0xSplits v2 `(address[] recipients, uint256[] allocations, uint256
    /// totalAllocation, uint16 distributionIncentive)`). nil when the split
    /// does not name it.
    static func share(fromLogs logs: [[String: Any]], coinbase: String, recipient: String) -> Double? {
        for log in logs.reversed() {
            guard let topics = live(log, from: [coinbase.lowercased()]), topics.first == splitUpdated,
                  let w = words(log["data"] as? String), w.count >= 6 else { continue }
            guard let head = small(w[0]), head % 32 == 0 else { continue }
            let base = head / 32
            guard base + 4 <= w.count, let r = small(w[base]), let a = small(w[base + 1]),
                  r % 32 == 0, a % 32 == 0 else { continue }
            let recipientsAt = base + r / 32, allocationsAt = base + a / 32
            let total = uint(w[base + 2])
            guard total > 0, recipientsAt < w.count, allocationsAt < w.count,
                  let n = small(w[recipientsAt]), n > 0, n <= 64, recipientsAt + n < w.count,
                  small(w[allocationsAt]) == n, allocationsAt + n < w.count else { continue }
            for i in 0..<n where address(w[recipientsAt + 1 + i]) == recipient.lowercased() {
                return min(max(uint(w[allocationsAt + 1 + i]) / total, 0), 1)
            }
            return nil
        }
        return nil
    }

    // MARK: - Views

    /// One attester's stake from its `getAttesterView` reply on the canonical
    /// Rollup, or nil when it holds nothing (status 0), the reply is
    /// malformed, or the view names a different withdrawer — the event said
    /// who queued it, the view says who can take it out now, and only the
    /// second decides whose money it is.
    static func stake(view hex: String?, owner: String, withdrawer: String,
                      attester: String, rollup: String) -> Stake? {
        guard let words = words(hex), words.count == 11 else { return nil }
        guard let raw = small(words[0]), let status = Status(rawValue: raw), status != .none else { return nil }
        guard address(words[10]) == withdrawer.lowercased() else { return nil }
        let exists = uint(words[7]) != 0
        let exitable = uint(words[4])
        return Stake(owner: owner.lowercased(), withdrawer: withdrawer.lowercased(),
                     attester: attester.lowercased(), rollup: rollup.lowercased(),
                     status: status,
                     staked: uint(words[1]) / decimals,
                     exitAmount: exists ? uint(words[3]) / decimals : 0,
                     exitableAt: exists && exitable > 0 ? Date(timeIntervalSince1970: exitable) : nil,
                     withdrawalID: exists ? (small(words[2]) ?? 0) : 0)
    }

    /// A proposal from `getProposal` and `getProposalState`, or nil once it
    /// is no longer pending or active: only a vote still to come is drawn.
    static func proposal(id: Int, view hex: String?, state stateHex: String?) -> Proposal? {
        guard let w = words(hex), w.count == 13, let s = words(stateHex), s.count == 1 else { return nil }
        guard let state = small(s[0]), state == 0 || state == 1 else { return nil }
        let opens = uint(w[10]) + uint(w[0])
        return Proposal(id: id, state: state, opens: Date(timeIntervalSince1970: opens),
                        closes: Date(timeIntervalSince1970: opens + uint(w[1])))
    }

    // MARK: - Words

    /// The row's state: "Validating", "Stopped" (a zombie: slashed below the
    /// minimum, so it can only exit), "Missing attestations" (validating but
    /// silent `stoppedStreak` slots running), "Withdrawing · from Oct 14", or
    /// "Ready to withdraw" once that date has passed.
    static func state(_ stake: Stake, now: Date = .now) -> String {
        switch stake.status {
        case .none: return ""
        case .validating:
            return stake.isStopped ? String(localized: "Missing attestations") : String(localized: "Validating")
        case .zombie: return String(localized: "Stopped")
        case .exiting:
            guard let at = stake.exitableAt else { return String(localized: "Withdrawing") }
            if at <= now { return String(localized: "Ready to withdraw") }
            return String(localized: "Withdrawing · from \(at.formatted(.dateTime.month(.abbreviated).day()))")
        }
    }

    /// "262.5 AZTEC earned", only when there is something to claim.
    static func earned(_ stake: Stake) -> String? {
        guard let rewards = stake.rewards, rewards >= 0.01 else { return nil }
        return String(localized: "\(plain(rewards)) AZTEC earned")
    }

    /// Whether the row's state asks something of the person: a stake that
    /// can be withdrawn and has not been, one that stopped, or one missing
    /// its attestations.
    static func needsYou(_ stake: Stake, now: Date = .now) -> Bool {
        switch stake.status {
        case .zombie: return true
        case .validating: return stake.isStopped
        case .exiting: return stake.exitableAt.map { $0 <= now } ?? false
        case .none: return false
        }
    }

    /// The landed row once an exit can be taken out.
    static func readyTitle(_ stake: Stake) -> String {
        String(localized: "Your \(plain(stake.exitAmount)) AZTEC can be withdrawn from Aztec staking")
    }

    static func stoppedTitle(_ stake: Stake) -> String {
        String(localized: "Your Aztec sequencer \(shortAddress(stake.attester)) stopped attesting")
    }

    static func voteTitle(_ p: Proposal, now: Date = .now) -> String {
        let day: (Date) -> String = { $0.formatted(.dateTime.month(.abbreviated).day()) }
        return p.state == 1 || p.opens <= now
            ? String(localized: "Aztec proposal \(p.id) is open for votes until \(day(p.closes))")
            : String(localized: "Aztec proposal \(p.id) opens for votes \(day(p.opens))")
    }

    static func shortAddress(_ a: String) -> String {
        a.count > 10 ? "\(a.prefix(6))…\(a.suffix(4))" : a
    }

    /// Whole numbers bare, else at most two decimals, grouped.
    static func plain(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US")))
    }
}
