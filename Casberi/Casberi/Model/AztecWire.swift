import Foundation

/// The Aztec testnet's wire, pure (2026-10-11). Foundation only, no app
/// types, so `scripts/aztec-selftest.sh` compiles this file WHOLE and
/// unmodified against the shapes measured off the live testnet.
///
/// **What a keyless reader can see.** Aztec is private by design: an account
/// is a contract whose notes are encrypted to its owner, and one initialised
/// privately has no public instance at all (`node_getContract` answers
/// nothing for it, measured). So there is no address to "watch" the way a
/// Logos or EVM account is watched. What IS public, and what this wire reads:
/// the chain's own progress (`node_getChainTips`, `node_getCurrentMinFees`,
/// `node_getPendingTxCount`) and a SEQUENCER's duty record
/// (`node_getValidatorStats`, keyed by its L1 attester address): the slots
/// it attested, the checkpoints it proposed, what it missed, and its
/// all-time committee epochs.
///
/// **The node's view, not the chain's.** Validator stats are what the
/// answering node observed since it started (`initialSlot`) over a sliding
/// window (`slotWindow`, 768 slots). Another node can count differently;
/// the page says whose count it is.
///
/// **Stake lives on Ethereum** (round two, 2026-10-11). A sequencer's status,
/// stake, rewards, committee seat and proposer slots are the Rollup
/// contract's (`getAttesterView`, `getSequencerRewards`,
/// `getCurrentEpochCommittee`, `getProposerAt`), read keylessly over a public
/// Ethereum node with hand-encoded calls — selectors measured off Aztec's own
/// `RollupAbi`. **An account's PUBLIC Fee Juice** is a storage slot in the
/// Fee Juice contract (address 3, map at slot 1), derived with Poseidon2
/// (`AztecPoseidon2`) and read with `node_getPublicStorageAt`; its private
/// balance stays private.
enum AztecWire {

    // MARK: - Network

    /// The value that names a chain (FramesNetwork's rule, prd §962): its
    /// Aztec node, its explorer, and the Ethereum node its Rollup lives on.
    /// The testnet is Aztec's CURRENT one (v6.0.0, rollup version 679261766,
    /// read 2026-10-26, prd §1565; the v5 host the getting-started page names
    /// is the previous testnet). The node names its own Rollup, and that is
    /// the testnet Registry's canonical one on Sepolia, so nothing L1 is pinned.
    /// Both Aztec hosts are dRPC's public endpoints, which refuse a batch of
    /// more than three (measured), so they are asked one call at a time; the
    /// Ethereum nodes are publicnode's, which answer a batch of 40 in ~130ms.
    struct Network: Equatable {
        let name: String
        let rpc: String
        let explorer: String
        let l1: String

        static let testnet = Network(name: "testnet", rpc: "https://aztec-testnet.drpc.org",
                                     explorer: "https://testnet.aztecscan.xyz",
                                     l1: "https://ethereum-sepolia-rpc.publicnode.com")
        // Aztec's mainnet ("Alpha", node 5.2.0, `aztec-mainnet.drpc.org`,
        // its Rollup on Ethereum mainnet) answers the same reads, measured
        // 2026-10-11 — but it is real stake, so it never joins Testnets
        // (prd §1050), and no host of it is reached until it has a place.

        /// Measured 2026-10-11 (`getSlotDuration`, `getEpochDuration`).
        static let slotSeconds: TimeInterval = 72
        static let epochSlots = 32
    }

    static func request(_ method: String, _ params: [Any], id: Int = 1) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
    }

    /// The `result` of a reply, or nil for an `error` object, or for a reply
    /// with no `result` key — which is how the node answers an attester it
    /// has never seen (measured: `{"jsonrpc":"2.0","id":1}`).
    static func result(_ reply: Any?) -> Any? {
        guard let obj = reply as? [String: Any], obj["error"] == nil else { return nil }
        return obj["result"]
    }

    // MARK: - Chain

    /// Which chain answered: a reset or a new major version deploys a new
    /// rollup on L1, so the rollup address and version name the chain the
    /// way block 1's hash names Logos' (prd §1035).
    struct Chain: Codable, Equatable {
        let rollup: String
        let version: Int
        let l1ChainID: Int
        let nodeVersion: String
        /// The ERC-20 a sequencer stakes (STK on the testnet, AZTEC on Alpha).
        var stakingAsset: String? = nil
        /// The Governance contract on Ethereum, as the node lists it (prd §1419).
        var governance: String? = nil
        var key: String { "\(rollup.lowercased()):\(version)" }
    }

    static func chain(_ result: Any?) -> Chain? {
        guard let r = result as? [String: Any],
              let l1 = r["l1ContractAddresses"] as? [String: Any],
              let rollup = l1["rollupAddress"] as? String,
              let version = int(r["rollupVersion"]),
              let chainID = int(r["l1ChainId"]) else { return nil }
        return Chain(rollup: rollup, version: version, l1ChainID: chainID,
                     nodeVersion: r["nodeVersion"] as? String ?? "",
                     stakingAsset: l1["stakingAssetAddress"] as? String,
                     governance: l1["governanceAddress"] as? String)
    }

    /// The three heads (`node_getChainTips`): proposed is what sequencers
    /// built, checkpointed is what reached L1, proven is what a proof
    /// finalised. The gap from proposed to proven is the chain's lag.
    struct Tips: Codable, Equatable {
        let proposed: Int
        let checkpointed: Int?
        let proven: Int?
        var provenLag: Int? { proven.map { max(0, proposed - $0) } }
    }

    static func tips(_ result: Any?) -> Tips? {
        guard let r = result as? [String: Any],
              let proposed = int((r["proposed"] as? [String: Any])?["number"]) else { return nil }
        func block(_ key: String) -> Int? {
            int(((r[key] as? [String: Any])?["block"] as? [String: Any])?["number"])
        }
        return Tips(proposed: proposed, checkpointed: block("checkpointed"), proven: block("proven"))
    }

    /// `node_getCurrentMinFees`: fee per unit of L2 and DA gas, in the fee
    /// asset's smallest unit (a decimal string on the wire; DA was "0").
    static func minL2Fee(_ result: Any?) -> Decimal? {
        guard let r = result as? [String: Any] else { return nil }
        return decimal(r["feePerL2Gas"])
    }

    // MARK: - Sequencers

    /// A sequencer is named by its L1 ATTESTER address: 20 bytes, hex.
    /// Lowercased so two spellings are one watch. An Aztec ACCOUNT address
    /// (32 bytes) is refused by length — its state is private, and the page
    /// says so rather than reading it as an idle sequencer.
    static func attester(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`“”‘’<>()[].,;"))
        if let range = text.range(of: "/", options: .backwards) { text = String(text[range.upperBound...]) }
        guard text.lowercased().hasPrefix("0x") else { return nil }
        let hex = text.dropFirst(2)
        guard hex.count == 40, hex.allSatisfy(\.isHexDigit) else { return nil }
        return "0x" + hex.lowercased()
    }

    /// True for a 32-byte hex string — an Aztec account address, which a
    /// watch cannot read (see the type comment).
    static func isAccountAddress(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.lowercased().hasPrefix("0x") else { return false }
        let hex = text.dropFirst(2)
        return hex.count == 64 && hex.allSatisfy(\.isHexDigit)
    }

    static func short(_ address: String) -> String { AddressTail.short(address) }

    struct Missed: Codable, Equatable {
        let streak: Int
        let count: Int
        let total: Int
    }

    struct Moment: Codable, Equatable {
        let slot: Int
        let date: Date
    }

    /// One slot's duty. Statuses (stdlib `ValidatorStatusInSlot`):
    /// proposer `checkpoint-mined` / `-valid` / `-invalid` / `-unvalidated` /
    /// `-missed`, `blocks-missed`; attester `attestation-sent` / `-missed`.
    struct Duty: Codable, Equatable {
        let slot: Int
        let status: String
    }

    struct Sequencer: Codable, Equatable {
        let address: String
        let totalSlots: Int
        let proposals: Missed
        let attestations: Missed
        let lastProposal: Moment?
        let lastAttestation: Moment?
        let history: [Duty]
        /// All-time committee duty, by epoch (`allTimeEpochPerformance`).
        let epochs: Int
        let epochsMissed: Int
        /// The last `stripEpochs` committee epochs, oldest first: how many
        /// slots each one missed (0 is a clean epoch). The Node box's strip.
        var recentEpochs: [Int] = []
        /// The node's window: what it has processed through, and how far back.
        let lastProcessedSlot: Int?
        let slotWindow: Int?

        var attested: Int { attestations.total - attestations.count }
        var proposed: Int { history.filter { $0.status == "checkpoint-mined" }.count }
    }

    /// `node_getValidatorStats(address)`'s result. nil for an attester the
    /// node has never seen — the reply carries no `result` at all.
    static func sequencer(_ result: Any?) -> Sequencer? {
        guard let r = result as? [String: Any], let v = r["validator"] as? [String: Any],
              let address = v["address"] as? String else { return nil }
        func missed(_ key: String) -> Missed {
            let m = v[key] as? [String: Any] ?? [:]
            return Missed(streak: int(m["currentStreak"]) ?? 0, count: int(m["count"]) ?? 0,
                          total: int(m["total"]) ?? 0)
        }
        func moment(_ key: String) -> Moment? {
            guard let m = v[key] as? [String: Any], let slot = int(m["slot"]),
                  let seconds = int(m["timestamp"]) else { return nil }
            return Moment(slot: slot, date: Date(timeIntervalSince1970: TimeInterval(seconds)))
        }
        let history = (v["history"] as? [[String: Any]] ?? []).compactMap { entry -> Duty? in
            guard let slot = int(entry["slot"]), let status = entry["status"] as? String else { return nil }
            return Duty(slot: slot, status: status)
        }
        let epochs = (r["allTimeEpochPerformance"] as? [[String: Any]] ?? [])
            .sorted { (int($0["epoch"]) ?? 0) < (int($1["epoch"]) ?? 0) }
        return Sequencer(address: address.lowercased(), totalSlots: int(v["totalSlots"]) ?? 0,
                         proposals: missed("missedProposals"), attestations: missed("missedAttestations"),
                         lastProposal: moment("lastProposal"), lastAttestation: moment("lastAttestation"),
                         history: history, epochs: epochs.count,
                         epochsMissed: epochs.filter { (int($0["missed"]) ?? 0) > 0 }.count,
                         recentEpochs: epochs.suffix(stripEpochs).map { int($0["missed"]) ?? 0 },
                         lastProcessedSlot: int(r["lastProcessedSlot"]), slotWindow: int(r["slotWindow"]))
    }

    /// How many epochs the Node box's strip draws.
    static let stripEpochs = 48

    /// A slot's time: exact when the record stamps that slot, else counted
    /// from the nearest stamp at `slotSeconds` a slot. nil with no stamp.
    static func date(of slot: Int, in s: Sequencer) -> Date? {
        let anchors = [s.lastAttestation, s.lastProposal].compactMap { $0 }
        if let exact = anchors.first(where: { $0.slot == slot }) { return exact.date }
        guard let anchor = anchors.min(by: { abs($0.slot - slot) < abs($1.slot - slot) }) else { return nil }
        return anchor.date.addingTimeInterval(TimeInterval(slot - anchor.slot) * Network.slotSeconds)
    }

    // MARK: - Events

    /// A sequencer that has missed this many attestations IN A ROW has
    /// stopped, not stumbled: one slot is 72s, so three is ~4 minutes of
    /// silence while its committee was voting.
    static let stoppedStreak = 3

    struct Event: Equatable {
        enum Kind: String { case proposed, missedProposal, stopped, resumed, missedAway, status }
        let kind: Kind
        let title: String
        let slot: Int
        /// State tags only (`HomeComposition.mechanicalTags`): Logos' node
        /// words where they mean the same thing, never a subject.
        var tags: [String] {
            switch kind {
            case .proposed:       return ["Node", "Proposed"]
            case .missedProposal: return ["Node", "Missed"]
            case .stopped:        return ["Node", "Offline"]
            case .resumed:        return ["Node"]
            case .missedAway:     return ["Node", "Missed"]
            case .status:         return ["Node"]
            }
        }
        /// The row's `sourceRef`: one per sequencer, kind and slot, so a
        /// re-read of the same window lands nothing twice.
        func ref(_ address: String) -> String { "aztec:seq:\(address):\(kind.rawValue):\(slot)" }
    }

    /// What changed between two readings of one sequencer. The FIRST reading
    /// lands nothing (`old == nil`): a watch is forward-only, and the window
    /// it opens on is history this phone did not see happen.
    ///
    /// Proposals land one row each, only once FINAL (`checkpoint-mined`, or
    /// a miss) — a `-valid`/`-unvalidated` slot can still become mined.
    /// Attestations never land one row each (752 a window): a missed STREAK
    /// crossing `stoppedStreak` lands "Stopped attesting", and the streak
    /// returning to zero after one lands "Attesting again".
    static func events(old: Sequencer?, new: Sequencer) -> [Event] {
        guard let old else { return [] }
        var out: [Event] = []
        // What the old reading covered: its processed slot, else its newest
        // duty. A stored reading keeps only proposer duty (`slim`), so the
        // processed slot is the one that counts.
        let seen = max(old.lastProcessedSlot ?? Int.min, old.history.map(\.slot).max() ?? Int.min)
        for duty in new.history where duty.slot > seen {
            switch duty.status {
            case "checkpoint-mined":
                out.append(Event(kind: .proposed, title: "Proposed a checkpoint — slot \(grouped(duty.slot))", slot: duty.slot))
            case "checkpoint-missed", "blocks-missed", "checkpoint-invalid":
                out.append(Event(kind: .missedProposal, title: "Missed a proposal — slot \(grouped(duty.slot))", slot: duty.slot))
            default:
                break
            }
        }
        let was = old.attestations.streak, now = new.attestations.streak
        let lastSlot = new.lastProcessedSlot ?? new.history.map(\.slot).max() ?? 0
        if now >= stoppedStreak && was < stoppedStreak {
            out.append(Event(kind: .stopped, title: "Stopped attesting — \(now) missed in a row",
                             slot: lastSlot - now + 1))
        } else if now == 0 && was >= stoppedStreak {
            out.append(Event(kind: .resumed, title: "Attesting again — after \(was) missed", slot: lastSlot))
        } else if now < stoppedStreak && was < stoppedStreak,
                  new.attestations.count - old.attestations.count >= stoppedStreak {
            // A stop that began AND ended between two readings: no streak
            // crossed, but the window's miss count rose. Said once, after
            // the fact — never an alarm, because it is already over.
            let n = new.attestations.count - old.attestations.count
            out.append(Event(kind: .missedAway, title: "Missed \(n) attestations", slot: lastSlot))
        }
        return out
    }

    /// The reading as STORED: proposer duty only. Attestations are counted in
    /// `attestations` and never land one row each, so their ~750 entries a
    /// window would be persisted for nothing.
    static func slim(_ s: Sequencer) -> Sequencer {
        Sequencer(address: s.address, totalSlots: s.totalSlots, proposals: s.proposals,
                  attestations: s.attestations, lastProposal: s.lastProposal,
                  lastAttestation: s.lastAttestation,
                  history: s.history.filter { !$0.status.hasPrefix("attestation-") },
                  epochs: s.epochs, epochsMissed: s.epochsMissed, recentEpochs: s.recentEpochs,
                  lastProcessedSlot: s.lastProcessedSlot, slotWindow: s.slotWindow)
    }

    /// Whether the sequencer reads as stopped right now (the alarm, prd
    /// §1084's `nodeDown`, keyed by address).
    static func isStopped(_ s: Sequencer) -> Bool { s.attestations.streak >= stoppedStreak }

    // MARK: - Ethereum: stake, rewards, committee, schedule

    /// Function selectors, measured off `@aztec/l1-artifacts` 5.2.0's
    /// `RollupAbi` with viem (2026-10-11), and unchanged in
    /// `@aztec-foundation/l1-artifacts` 6.0.0 (2026-10-26) — keccak isn't in
    /// Foundation, and these never change for a deployed contract.
    enum Selector {
        static let getAttesterView = "34a51ed5"
        static let getSequencerRewards = "8789a132"
        static let getCurrentSlot = "d8e3784c"
        static let getTimestampForSlot = "d03b2bae"
        static let getProposerAt = "c27f08b5"
        static let getCurrentEpochCommittee = "966ab4ee"
        static let symbol = "95d89b41"
    }

    /// One `eth_call`, for a batch.
    static func ethCall(to: String, selector: String, args: [String] = [], id: Int) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "method": "eth_call",
         "params": [["to": to, "data": "0x" + selector + args.joined()], "latest"]]
    }

    /// An address or an integer as one 32-byte ABI word, hex without "0x".
    static func word(address: String) -> String {
        let hex = address.lowercased().hasPrefix("0x") ? String(address.dropFirst(2)) : address
        return String(repeating: "0", count: max(0, 64 - hex.count)) + hex.lowercased()
    }

    static func word(_ n: Int) -> String {
        let hex = String(n, radix: 16)
        return String(repeating: "0", count: 64 - hex.count) + hex
    }

    /// A batch's replies by id: a reply is the hex `result`, or absent.
    static func batchResults(_ reply: Any?) -> [Int: String] {
        var out: [Int: String] = [:]
        for item in reply as? [[String: Any]] ?? [] {
            if let id = int(item["id"]), let hex = item["result"] as? String, hex.count > 2 { out[id] = hex }
        }
        return out
    }

    /// The ABI words of a result, as hex strings without "0x".
    static func words(_ hex: String) -> [String] {
        let body = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard body.count % 64 == 0 else { return [] }
        return stride(from: 0, to: body.count, by: 64).map {
            let start = body.index(body.startIndex, offsetBy: $0)
            return String(body[start..<body.index(start, offsetBy: 64)])
        }
    }

    /// A word as an unsigned integer, exactly (a uint256 is past `Int`).
    static func uint(_ word: String) -> Decimal? {
        guard word.count == 64, word.allSatisfy(\.isHexDigit) else { return nil }
        var value = Decimal(0)
        for c in word { value = value * 16 + Decimal(Int(String(c), radix: 16)!) }
        return value
    }

    static func address(_ word: String) -> String? {
        guard word.count == 64 else { return nil }
        return "0x" + word.suffix(40).lowercased()
    }

    /// A dynamic `address[]` return: offset, length, then the items.
    static func addresses(_ hex: String) -> [String]? {
        let w = words(hex)
        guard w.count >= 2, let offset = uint(w[0]).map({ NSDecimalNumber(decimal: $0).intValue / 32 }),
              offset < w.count, let n = uint(w[offset]).map({ NSDecimalNumber(decimal: $0).intValue }),
              w.count >= offset + 1 + n else { return nil }
        return w[(offset + 1)..<(offset + 1 + n)].compactMap(address)
    }

    /// A `string` return (ERC-20 `symbol()`).
    static func string(_ hex: String) -> String? {
        let w = words(hex)
        guard w.count >= 3, let n = uint(w[1]).map({ NSDecimalNumber(decimal: $0).intValue }), n <= 64 else { return nil }
        let bytes = Data(stride(from: 0, to: n * 2, by: 2).compactMap { i -> UInt8? in
            let s = (w[2] + (w.count > 3 ? w[3] : ""))
            let a = s.index(s.startIndex, offsetBy: i)
            return UInt8(s[a..<s.index(a, offsetBy: 2)], radix: 16)
        })
        return String(data: bytes, encoding: .utf8)
    }

    /// The Rollup's status enum: NONE, VALIDATING, ZOMBIE (stake fell under
    /// the minimum, typically a slash), EXITING.
    enum Status: Int, Codable {
        case none = 0, validating, zombie, exiting

        var word: String {
            switch self {
            case .none:       return "Not staked"
            case .validating: return "Validating"
            case .zombie:     return "Inactive"
            case .exiting:    return "Exiting"
            }
        }
    }

    /// What Ethereum says about a sequencer's stake. Amounts are in the
    /// stake token's whole units (18 decimals, measured on both networks).
    struct Stake: Codable, Equatable {
        let status: Status
        let staked: Decimal
        let rewards: Decimal?
    }

    /// `getAttesterView`: the status word, then the effective balance.
    static func stake(view: String?, rewards: String?) -> Stake? {
        guard let view, case let w = words(view), w.count >= 2,
              let raw = uint(w[0]).map({ NSDecimalNumber(decimal: $0).intValue }),
              let status = Status(rawValue: raw), let balance = uint(w[1]) else { return nil }
        let earned = rewards.flatMap { words($0).first }.flatMap(uint)
        return Stake(status: status, staked: whole(balance), rewards: earned.map(whole))
    }

    /// 18-decimal base units as whole tokens.
    static func whole(_ base: Decimal) -> Decimal { base / pow(10, 18) }

    /// A status change between two readings lands one row; the first
    /// reading, as everywhere here, lands nothing.
    static func stakeEvent(old: Stake?, new: Stake, slot: Int) -> Event? {
        guard let old, old.status != new.status else { return nil }
        let title: String
        switch new.status {
        case .exiting:    title = "Started exiting — the stake unlocks after a delay"
        case .zombie:     title = "Inactive — the stake fell under the minimum"
        case .validating: title = "Validating again"
        case .none:       title = "No longer staked"
        }
        return Event(kind: .status, title: title, slot: slot)
    }

    /// The first slot at or after `startSlot` whose proposer is `address`,
    /// in a run of proposers read one slot apart.
    static func nextProposal(of address: String, proposers: [String?], startSlot: Int) -> Int? {
        let me = address.lowercased()
        return proposers.firstIndex { $0?.lowercased() == me }.map { startSlot + $0 }
    }

    /// How far ahead the schedule is read: this epoch and the next.
    static let scheduleSlots = 2 * Network.epochSlots

    // MARK: - Accounts: public Fee Juice

    /// An Aztec account address: 32 bytes, hex, lowercased.
    static func account(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`“”‘’<>()[].,;"))
        if let range = text.range(of: "/", options: .backwards) { text = String(text[range.upperBound...]) }
        guard isAccountAddress(text) else { return nil }
        return "0x" + text.dropFirst(2).lowercased()
    }

    /// The Fee Juice contract (protocol address 3) and its balances map's
    /// slot (1), and the map's separator — identical in v5.2.0,
    /// v6.0.0-rc.1 (`constants.nr`, read 2026-10-11) and v6.0.0
    /// (`@aztec-labs/constants` 6.0.0, read 2026-10-26).
    static let feeJuiceContract = "0x" + String(repeating: "0", count: 63) + "3"
    static let feeJuiceBalancesSlot: UInt64 = 1
    static let publicStorageMapSlot: UInt32 = 4015149901

    /// `derive_storage_slot_in_map(1, account)`, hex.
    static func feeJuiceSlot(_ account: String) -> String? {
        guard let key = AztecPoseidon2.field(account) else { return nil }
        let slot = AztecPoseidon2.field(String(feeJuiceBalancesSlot, radix: 16))!
        return AztecPoseidon2.hex(AztecPoseidon2.hash([slot, key], separator: publicStorageMapSlot))
    }

    /// `node_getPublicStorageAt`'s field as whole Fee Juice (18 decimals).
    static func feeJuice(_ result: Any?) -> Decimal? {
        guard let hex = result as? String else { return nil }
        let body = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        return uint(String(repeating: "0", count: max(0, 64 - body.count)) + body).map(whole)
    }

    /// A whole-token amount with grouping and at most two decimals.
    static func tokens(_ amount: Decimal) -> String {
        let f = amount < 1 && amount > 0 ? smallFormatter : tokenFormatter
        return f.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount)"
    }

    private static let tokenFormatter = decimalFormatter(fraction: 2)
    private static let smallFormatter = decimalFormatter(fraction: 4)
    private static func decimalFormatter(fraction: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = fraction
        return f
    }

    // MARK: - Words

    /// The roster's line for one sequencer: what it did in the node's window.
    static func line(_ s: Sequencer) -> String {
        if s.totalSlots == 0 {
            return s.epochs > 0
                ? "Not on a committee lately — \(s.epochs) epochs all-time"
                : "No duty seen yet"
        }
        var parts = ["Attested \(grouped(s.attested)) of \(grouped(s.attestations.total))"]
        if s.proposals.total > 0 { parts.append("proposed \(grouped(s.proposals.total - s.proposals.count))") }
        if s.attestations.count + s.proposals.count > 0 {
            parts.append("missed \(grouped(s.attestations.count + s.proposals.count))")
        }
        return parts.joined(separator: " · ")
    }

    static func grouped(_ n: Int) -> String {
        groupedFormatter.string(from: NSNumber(value: n)) ?? String(n)
    }

    /// One formatter: `line` runs in view bodies, once per sequencer.
    private static let groupedFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        return f
    }()

    // MARK: - Numbers

    /// Ints arrive as JSON numbers or decimal strings ("1791766188" stamps).
    static func int(_ any: Any?) -> Int? {
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String {
            if s.hasPrefix("0x") { return Int(s.dropFirst(2), radix: 16) }
            return Int(s)
        }
        return nil
    }

    static func decimal(_ any: Any?) -> Decimal? {
        if let s = any as? String { return Decimal(string: s) }
        if let n = any as? NSNumber { return n.decimalValue }
        return nil
    }
}
