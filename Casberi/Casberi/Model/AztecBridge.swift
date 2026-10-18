import Foundation
import Observation
import SwiftData

/// The Aztec seat (2026-10-11): the Aztec testnet, watched keylessly, beside
/// Logos in Testnets. What it can read is the PUBLIC half of a private chain
/// (`AztecWire`): the network's own progress, and the duty record of the
/// sequencers you follow — an attester address you run, or anyone's.
///
/// **No account is watched, by design.** An Aztec account's state is
/// encrypted to its owner, and a privately initialised one has no public
/// instance at all (measured 2026-10-11), so a "watched account" would draw a
/// confident nothing. The page refuses a 32-byte account address by name, as
/// Logos refuses a `Private/` id.
///
/// **Test fees, never money.** The fee asset on the testnet is test Fee
/// Juice; nothing here joins the wallet total, and the testnet is reset when
/// Aztec ships a major version (a new rollup on L1, detected by
/// `AztecWire.Chain.key`).
@Observable
final class AztecStore {
    static let shared = AztecStore()

    private static let sequencersKey = "aztec.sequencers.v1"
    private static let readingsKey = "aztec.readings.v1"
    private static let networkKey = "aztec.network.v1"
    private static let chainKey = "aztec.chain.v1"
    private static let readAtKey = "aztec.readAt.v1"
    private static let resetSeenKey = "aztec.resetSeen.v1"
    private static let followsNetworkKey = "aztec.followsNetwork.v1"
    private static let accountsKey = "aztec.accounts.v1"
    private static let feeJuiceKey = "aztec.feeJuice.v1"
    private static let stakesKey = "aztec.stakes.v1"
    private static let scheduleKey = "aztec.schedule.v1"
    private static let symbolKey = "aztec.stakeSymbol.v1"

    /// Followed sequencers' attester addresses, lowercased hex.
    private(set) var sequencers: [String] {
        didSet { persist(sequencers, Self.sequencersKey) }
    }

    /// Followed Aztec ACCOUNTS (32 bytes, lowercased): only their public Fee
    /// Juice is readable; a private balance stays private (round two).
    private(set) var accounts: [String] {
        didSet { persist(accounts, Self.accountsKey) }
    }

    /// Each followed account's last PUBLIC Fee Juice, whole units, as a
    /// decimal string (a u128 is past `Double`'s exact range).
    private(set) var feeJuice: [String: String] {
        didSet { UserDefaults.standard.set(feeJuice, forKey: Self.feeJuiceKey) }
    }

    /// Each sequencer's stake as Ethereum last answered it.
    private(set) var stakes: [String: AztecWire.Stake] {
        didSet {
            if let data = try? JSONEncoder().encode(stakes) { UserDefaults.standard.set(data, forKey: Self.stakesKey) }
        }
    }

    /// What the last schedule read said: each sequencer's next proposal (a
    /// date, nil when none in this epoch or the next) and whether it sits on
    /// the current epoch's committee.
    struct Duty: Codable, Equatable {
        let nextProposal: Date?
        let onCommittee: Bool
    }

    private(set) var schedule: [String: Duty] {
        didSet {
            if let data = try? JSONEncoder().encode(schedule) { UserDefaults.standard.set(data, forKey: Self.scheduleKey) }
        }
    }

    /// The stake token's symbol (STK on the testnet), read once per chain.
    private(set) var stakeSymbol: String? {
        didSet { UserDefaults.standard.set(stakeSymbol, forKey: Self.symbolKey) }
    }

    /// Each sequencer's last reading — what the next one is diffed against
    /// (`AztecWire.events`). nil until the first read, which lands nothing.
    private(set) var readings: [String: AztecWire.Sequencer] {
        didSet {
            if let data = try? JSONEncoder().encode(readings) {
                UserDefaults.standard.set(data, forKey: Self.readingsKey)
            }
        }
    }

    /// The network's last reading: the three heads and the minimum fee.
    struct Network: Codable, Equatable {
        let tips: AztecWire.Tips
        let minL2Fee: Decimal?
        let pending: Int?
        let at: Date
    }

    private(set) var network: Network? {
        didSet {
            if let data = network.flatMap({ try? JSONEncoder().encode($0) }) {
                UserDefaults.standard.set(data, forKey: Self.networkKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.networkKey)
            }
        }
    }

    /// Following the network alone connects the seat: the room's Home is the
    /// network, and someone with no sequencer still wants to see the testnet.
    private(set) var followsNetwork: Bool {
        didSet { UserDefaults.standard.set(followsNetwork, forKey: Self.followsNetworkKey) }
    }

    /// Which chain answered last (`AztecWire.Chain.key`).
    private(set) var chain: String? {
        didSet { UserDefaults.standard.set(chain, forKey: Self.chainKey) }
    }

    /// When every followed sequencer was last read — the roster's staleness
    /// stamp. A pass that could not read one leaves it where it was (prd §825).
    private(set) var readAt: Date? {
        didSet { UserDefaults.standard.set(readAt, forKey: Self.readAtKey) }
    }

    /// The reset this phone last OBSERVED: the new chain's key and when this
    /// phone saw it. What `DevnetNotify` announces, once (Logos' rule).
    private(set) var resetSeen: (key: String, at: Date)? {
        didSet {
            if let resetSeen {
                UserDefaults.standard.set(["key": resetSeen.key, "at": resetSeen.at.timeIntervalSince1970],
                                          forKey: Self.resetSeenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.resetSeenKey)
            }
        }
    }

    private init() {
        sequencers = UserDefaults.standard.data(forKey: Self.sequencersKey)
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        readings = UserDefaults.standard.data(forKey: Self.readingsKey)
            .flatMap { try? JSONDecoder().decode([String: AztecWire.Sequencer].self, from: $0) } ?? [:]
        network = UserDefaults.standard.data(forKey: Self.networkKey)
            .flatMap { try? JSONDecoder().decode(Network.self, from: $0) }
        followsNetwork = UserDefaults.standard.bool(forKey: Self.followsNetworkKey)
        chain = UserDefaults.standard.string(forKey: Self.chainKey)
        accounts = UserDefaults.standard.data(forKey: Self.accountsKey)
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        feeJuice = UserDefaults.standard.dictionary(forKey: Self.feeJuiceKey) as? [String: String] ?? [:]
        stakes = UserDefaults.standard.data(forKey: Self.stakesKey)
            .flatMap { try? JSONDecoder().decode([String: AztecWire.Stake].self, from: $0) } ?? [:]
        schedule = UserDefaults.standard.data(forKey: Self.scheduleKey)
            .flatMap { try? JSONDecoder().decode([String: Duty].self, from: $0) } ?? [:]
        stakeSymbol = UserDefaults.standard.string(forKey: Self.symbolKey)
        readAt = UserDefaults.standard.object(forKey: Self.readAtKey) as? Date
        if let seen = UserDefaults.standard.dictionary(forKey: Self.resetSeenKey),
           let key = seen["key"] as? String, let at = seen["at"] as? Double {
            resetSeen = (key, Date(timeIntervalSince1970: at))
        } else { resetSeen = nil }
    }

    var connected: Bool { followsNetwork || !sequencers.isEmpty || !accounts.isEmpty }

    func publicFeeJuice(for account: String) -> Decimal? { feeJuice[account].flatMap { Decimal(string: $0) } }
    func stake(for address: String) -> AztecWire.Stake? { stakes[address] }
    func duty(for address: String) -> Duty? { schedule[address] }

    func reading(for address: String) -> AztecWire.Sequencer? { readings[address] }

    enum AddResult: Equatable { case added, addedAccount, alreadyFollowing, invalid }

    /// Follows a sequencer (20 bytes) or an account (32 bytes) — the length
    /// says which, so the page keeps one field.
    @discardableResult
    func add(_ raw: String) -> AddResult {
        if let account = AztecWire.account(raw) {
            guard !accounts.contains(account) else { return .alreadyFollowing }
            accounts.append(account)
            return .addedAccount
        }
        guard let address = AztecWire.attester(raw) else { return .invalid }
        guard !sequencers.contains(address) else { return .alreadyFollowing }
        sequencers.append(address)
        return .added
    }

    func remove(_ address: String) {
        sequencers.removeAll { $0 == address }
        accounts.removeAll { $0 == address }
        readings.removeValue(forKey: address)
        stakes.removeValue(forKey: address)
        schedule.removeValue(forKey: address)
        feeJuice.removeValue(forKey: address)
    }

    func remember(stake: AztecWire.Stake, for address: String) { stakes[address] = stake }
    func remember(schedule read: [String: Duty]) { if schedule != read { schedule = read } }
    func remember(feeJuice value: Decimal, for account: String) { feeJuice[account] = "\(value)" }
    func remember(stakeSymbol symbol: String) { if stakeSymbol != symbol { stakeSymbol = symbol } }

    func follow(network on: Bool) { if followsNetwork != on { followsNetwork = on } }

    func remember(_ reading: AztecWire.Sequencer) { readings[reading.address] = AztecWire.slim(reading) }

    func remember(network snap: Network) { network = snap }

    func markRead(_ date: Date) { readAt = date }

    /// Records the chain's identity. Returns true when it CHANGED from a
    /// known one — a reset; first sight is not. A reset drops every reading,
    /// so the new chain's first reading lands nothing (forward-only again).
    @discardableResult
    func rememberChain(_ key: String) -> Bool {
        let reset = chain != nil && chain != key
        if chain != key { chain = key }
        if reset {
            resetSeen = (key, .now)
            readings = [:]
            stakes = [:]
            schedule = [:]
            feeJuice = [:]
            stakeSymbol = nil
            readAt = nil
            RoomValueHistory.forget(room: AztecRoom.source, address: AztecRoom.networkSeries)
        }
        return reset
    }

    func disconnect() {
        sequencers = []
        accounts = []
        readings = [:]
        stakes = [:]
        schedule = [:]
        feeJuice = [:]
        stakeSymbol = nil
        network = nil
        followsNetwork = false
        readAt = nil
        resetSeen = nil
    }

    private func persist(_ list: [String], _ key: String) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Ingest

enum AztecIngest {

    /// The service name every request declares to `NetworkLedger`.
    static let service = "Aztec"

    /// The network the seat follows. Alpha is read by the probe alone.
    static let network = AztecWire.Network.testnet

    @MainActor private static var running = false

    struct Outcome { var added: Int }

    static func call(_ method: String, _ params: [Any] = [], on net: AztecWire.Network = network) async -> Any? {
        AztecWire.result(await reply(method, params, on: net))
    }

    /// The whole reply: a dictionary with no `result` (or a null one) is the
    /// node ANSWERING that it has never seen an attester; nil is the node not
    /// answering.
    static func reply(_ method: String, _ params: [Any] = [], on net: AztecWire.Network = network) async -> Any? {
        await IngestSupport.postJSON(net.rpc, body: AztecWire.request(method, params), service: service)
    }

    /// One batched round trip to the network's Ethereum node.
    static func l1(_ calls: [[String: Any]], on net: AztecWire.Network = network) async -> [Int: String] {
        guard !calls.isEmpty else { return [:] }
        return AztecWire.batchResults(await IngestSupport.postJSONArray(net.l1, body: calls, service: service))
    }

    /// Reads the network, each followed sequencer (the Aztec node's duty
    /// record, then Ethereum's stake and schedule) and each followed
    /// account's public Fee Juice, and lands what changed since the last
    /// reading. nil when the Aztec node could not be reached at all.
    @MainActor
    static func refresh(context: ModelContext) async -> Outcome? {
        let store = AztecStore.shared
        guard store.connected, !running else { return running ? Outcome(added: 0) : nil }
        running = true
        defer { running = false }

        guard let chain = AztecWire.chain(await call("node_getNodeInfo")) else { return nil }
        store.rememberChain(chain.key)
        async let tipsRead = call("node_getChainTips")
        async let feesRead = call("node_getCurrentMinFees")
        async let pendingRead = call("node_getPendingTxCount")
        let (tipsReply, feesReply, pendingReply) = await (tipsRead, feesRead, pendingRead)
        if let tips = AztecWire.tips(tipsReply) {
            store.remember(network: .init(tips: tips, minL2Fee: AztecWire.minL2Fee(feesReply),
                                          pending: AztecWire.int(pendingReply), at: .now))
            // Home's line (round two): the proving lag, one sample a pass —
            // what this phone saw, the devnets' `RoomValueHistory`.
            if let lag = tips.provenLag {
                RoomValueHistory.note(room: AztecRoom.source, address: AztecRoom.networkSeries, value: Double(lag))
            }
        }

        var added = 0
        var readAll = true
        var existing = IngestSupport.existingSourceRefs(context, source: AztecRoom.source)
        func land(_ event: AztecWire.Event, _ sequencer: AztecWire.Sequencer) {
            let ref = event.ref(sequencer.address)
            guard !existing.contains(ref) else { return }
            Self.land(event, sequencer: sequencer, ref: ref, context: context)
            existing.insert(ref)
            added += 1
        }
        var current: [String: AztecWire.Sequencer] = [:]
        for address in store.sequencers {
            let answer = await reply("node_getValidatorStats", [address])
            guard let new = AztecWire.sequencer(AztecWire.result(answer)) else {
                // Never seen by this node is a real answer, not an outage:
                // the roster says so and nothing lands. Only a node that did
                // not answer leaves the stamp where it was.
                if answer == nil { readAll = false }
                continue
            }
            for event in AztecWire.events(old: store.reading(for: address), new: new) { land(event, new) }
            store.remember(new)
            current[address] = new
        }

        await readEthereum(chain: chain, current: current, land: land)

        // The testnet's own votes (prd §1419): quiet rows, as the Wallet
        // lands mainnet's (§1279), read off Governance on Sepolia.
        if let governance = chain.governance {
            added += await readVotes(governance: governance, existing: &existing, context: context)
        }

        for account in store.accounts {
            guard let slot = AztecWire.feeJuiceSlot(account) else { continue }
            if let value = AztecWire.feeJuice(await call("node_getPublicStorageAt",
                                                         ["latest", AztecWire.feeJuiceContract, slot])) {
                store.remember(feeJuice: value, for: account)
            } else {
                readAll = false
            }
        }

        if readAll { store.markRead(.now) }
        if added > 0 { context.saveHonestly() }
        return Outcome(added: added)
    }

    /// Ethereum's half, two batched round trips: every sequencer's stake and
    /// rewards with the slot, the committee and the stake token's symbol;
    /// then the proposer of every slot in this epoch and the next. A failed
    /// read leaves the last answer standing.
    @MainActor
    private static func readEthereum(chain: AztecWire.Chain, current: [String: AztecWire.Sequencer],
                                     land: (AztecWire.Event, AztecWire.Sequencer) -> Void) async {
        let store = AztecStore.shared
        let rollup = chain.rollup
        let followed = store.sequencers
        guard !followed.isEmpty else { return }
        var calls = [AztecWire.ethCall(to: rollup, selector: AztecWire.Selector.getCurrentSlot, id: 0),
                     AztecWire.ethCall(to: rollup, selector: AztecWire.Selector.getCurrentEpochCommittee, id: 1)]
        if store.stakeSymbol == nil, let asset = chain.stakingAsset {
            calls.append(AztecWire.ethCall(to: asset, selector: AztecWire.Selector.symbol, id: 2))
        }
        for (i, address) in followed.enumerated() {
            let arg = [AztecWire.word(address: address)]
            calls.append(AztecWire.ethCall(to: rollup, selector: AztecWire.Selector.getAttesterView, args: arg, id: 100 + 2 * i))
            calls.append(AztecWire.ethCall(to: rollup, selector: AztecWire.Selector.getSequencerRewards, args: arg, id: 101 + 2 * i))
        }
        let first = await l1(calls)
        guard !first.isEmpty else { return }
        if let hex = first[2], let symbol = AztecWire.string(hex) { store.remember(stakeSymbol: symbol) }

        let slotNow = first[0].flatMap { AztecWire.words($0).first }.flatMap(AztecWire.uint)
            .map { NSDecimalNumber(decimal: $0).intValue }
        for (i, address) in followed.enumerated() {
            guard let stake = AztecWire.stake(view: first[100 + 2 * i], rewards: first[101 + 2 * i]) else { continue }
            if let sequencer = current[address] ?? store.reading(for: address),
               let event = AztecWire.stakeEvent(old: store.stake(for: address), new: stake,
                                                slot: slotNow ?? sequencer.lastProcessedSlot ?? 0) {
                land(event, sequencer)
            }
            store.remember(stake: stake, for: address)
        }

        // The schedule: when the current slot began, then every slot's
        // proposer through the end of the next epoch.
        guard let slotNow,
              let startHex = await l1([AztecWire.ethCall(to: rollup, selector: AztecWire.Selector.getTimestampForSlot,
                                                         args: [AztecWire.word(slotNow)], id: 0)])[0],
              let startSeconds = AztecWire.words(startHex).first.flatMap(AztecWire.uint) else { return }
        let start = NSDecimalNumber(decimal: startSeconds).doubleValue
        let lookups = (0..<AztecWire.scheduleSlots).map { i in
            AztecWire.ethCall(to: rollup, selector: AztecWire.Selector.getProposerAt,
                              args: [AztecWire.word(Int(start) + i * Int(AztecWire.Network.slotSeconds))], id: i)
        }
        let replies = await l1(lookups)
        guard !replies.isEmpty else { return }
        let proposers = (0..<AztecWire.scheduleSlots).map { i in
            replies[i].flatMap { AztecWire.words($0).first }.flatMap(AztecWire.address)
        }
        let committee = Set((first[1].flatMap(AztecWire.addresses) ?? []).map { $0.lowercased() })
        var read: [String: AztecStore.Duty] = [:]
        for address in followed {
            let next = AztecWire.nextProposal(of: address, proposers: proposers, startSlot: slotNow).map {
                Date(timeIntervalSince1970: start + Double($0 - slotNow) * AztecWire.Network.slotSeconds)
            }
            read[address] = .init(nextProposal: next, onCommittee: committee.contains(address))
        }
        store.remember(schedule: read)
    }

    /// The newest three testnet proposals still pending or open, landed once
    /// each and retitled in place when one opens. Returns how many landed.
    @MainActor
    private static func readVotes(governance: String, existing: inout Set<String>,
                                  context: ModelContext) async -> Int {
        let countReply = await l1([AztecWire.ethCall(to: governance, selector: String(AztecStakeWire.proposalCount.dropFirst(2)), id: 1)])
        guard let count = AztecStakeWire.count(reply: countReply[1]), count > 0 else { return 0 }
        let ids = Array(max(0, count - 3)..<count)
        var calls: [[String: Any]] = []
        for (i, id) in ids.enumerated() {
            calls.append(AztecWire.ethCall(to: governance, selector: String(AztecStakeWire.getProposal.dropFirst(2)),
                                           args: [AztecStakeWire.word(id)], id: 10 + i * 2))
            calls.append(AztecWire.ethCall(to: governance, selector: String(AztecStakeWire.getProposalState.dropFirst(2)),
                                           args: [AztecStakeWire.word(id)], id: 11 + i * 2))
        }
        let replies = await l1(calls)
        var added = 0
        for (i, id) in ids.enumerated() {
            guard let p = AztecStakeWire.proposal(id: id, view: replies[10 + i * 2], state: replies[11 + i * 2]) else { continue }
            let ref = "aztec:testvote:\(governance.lowercased()):\(id)"
            let title = AztecStakeWire.voteTitle(p, testnet: true)
            if existing.contains(ref) {
                if let row = try? context.fetch(FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref })).first,
                   row.title != title { row.title = title }
                continue
            }
            let thing = Thing(kind: .note, title: title,
                              content: "https://sepolia.etherscan.io/address/\(governance)",
                              source: AztecRoom.source, capturedAt: .now, sourceRef: ref)
            thing.dueAt = p.closes
            context.insert(thing)
            SpotlightIndex.index([thing])
            existing.insert(ref)
            added += 1
        }
        return added
    }

    @MainActor
    private static func land(_ event: AztecWire.Event, sequencer: AztecWire.Sequencer,
                             ref: String, context: ModelContext) {
        let thing = Thing(
            kind: .note,
            title: IngestSupport.titleLine(event.title),
            content: "\(network.explorer)/validators/\(sequencer.address)",
            source: AztecRoom.source,
            // A slot's own time when the record stamps it; else counted from
            // the nearest stamp. Never "now" for a slot that happened earlier.
            capturedAt: AztecWire.date(of: event.slot, in: sequencer) ?? .now,
            tags: event.tags,
            sourceRef: ref
        )
        thing.authorHandle = AztecRoom.name(for: sequencer.address)
        context.insert(thing)
        SpotlightIndex.index([thing])
    }
}
