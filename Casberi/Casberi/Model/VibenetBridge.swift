import Foundation
import Observation
import SwiftData

/// Base "vibenet" (2026-08-23) — an experimental, EPHEMERAL devnet testing
/// EIP-8130 native account abstraction. Chain id 84538453, keyless RPC at
/// `rpc.vibes.base.org`. Genuinely read-only in every sense: no signing key
/// of this app's own touches it (unlike Safe's co-signer, prd §425/§426 —
/// there is no counterpart here), no funds move, and nothing this file does
/// can write to the chain. It reads a watched account's account-abstraction
/// state — is it established, which actors can act for it, is it locked —
/// the same "riding live state, never a landed `Thing`" shape
/// `WalletDeFi`/`SafeSigner` use, because a devnet test account has nothing
/// worth a corpus row: no news, nothing a screenshot would reference.
///
/// ## THE ONE RULE THAT MAKES THIS SAFE TO SHIP: NEVER HARDCODE AN ADDRESS
///
/// vibenet's contracts are redeployed on no fixed schedule — the sibling
/// Sepolia deployment of this same protocol redeployed three times in three
/// days, per its own broadcast history. `VibenetConfig.current()` fetches
/// the live contract map every time it's asked (behind a short cache) from
/// `api.vibes.base.org/api/vibenet/contracts`, and every read in this file
/// takes its Keystore/authenticator addresses from THAT fetch, never from a
/// Swift literal. **If you find yourself typing one of vibenet's contract
/// addresses into this file outside a DEBUG fixture, stop — a hardcoded
/// address here goes stale within days and starts reading (or worse,
/// writing eth_call data to) a contract that no longer means what this file
/// thinks it means.** The one exception, twice over: `K1_AUTHENTICATOR`
/// (`address(1)`) is `Keystore.sol`'s own fixed constant, and the RPC host
/// itself is a stable endpoint, not a contract.
///
/// Watching is a plain UserDefaults list of address strings (`VibenetWatch`)
/// rather than a `Thing` per address — the `TrendingStore` shape, not
/// `L2beatWatch`'s: a devnet address has no product page, no news to arrive
/// under it, nothing to search for. What lives here reads the way
/// `AerodromeDeFi`/`WalletApprovals` read a public chain: keyless
/// `eth_call`/`eth_getLogs` against a measured RPC host.

// MARK: - Identity

enum VibenetIdentity {
    static let source = "Base Vibenet"
    static let seatID = "vibenet"
}

// MARK: - The live contracts config

/// The shape of `api.vibes.base.org/api/vibenet/contracts`'s response —
/// every field but the four this file actually reads is carried through
/// unread rather than dropped, so a future read (the faucet, USDV/NFV/
/// vibecheck) doesn't need to re-touch the parse.
struct VibenetContracts: Equatable, Codable {
    let branch: String?
    let commit: String?
    let faucetAddress: String?
    let keystore: String
    let defaultAccount: String?
    let canonicalHighRatePayerAccount: String?
    let p256Authenticator: String
    let webAuthnAuthenticator: String
    let delegateAuthenticator: String
    let policyManager: String?
    let sessionPolicy: String?
    let usdv: String?
    let nfv: String?
    let vibecheck: String?

    /// The three DYNAMIC authenticator addresses `VibenetAuthenticatorKind
    /// .identify` compares against — see that type's own doc for why they
    /// may never be literals.
    var knownAuthenticators: VibenetKnownAuthenticators {
        VibenetKnownAuthenticators(p256: p256Authenticator, webAuthn: webAuthnAuthenticator,
                                   delegate: delegateAuthenticator)
    }
}

enum VibenetConfig {
    /// *** STANDING CONSTRAINT — DO NOT "SIMPLIFY" THIS INTO A LITERAL ***
    /// This is the ONE address in the whole feature that names a real
    /// contract without going through a live fetch, and it's allowed to
    /// because it isn't a contract — it's the config document ITSELF, the
    /// thing every other address in this file is read from. See the file's
    /// header doc for why every address downstream of this call must be.
    private static let configURL = "https://api.vibes.base.org/api/vibenet/contracts"

    private static let cacheKey = "vibenet.contracts.cache.v1"
    private static let fetchedAtKey = "vibenet.contracts.fetchedAt"

    /// How long a fetched config is trusted before the next call re-asks.
    /// SHORT on purpose: vibenet's whole premise is that its contracts move
    /// (see the file header), so this cache exists to avoid re-fetching a
    /// 1KB document on every keystroke of a probe loop, never to let a
    /// stale address set survive a redeploy for long. Persisted, not merely
    /// in-memory, so a cold launch inherits a still-fresh read instead of
    /// treating every app open as the first one.
    static let ttl: TimeInterval = 10 * 60

    static func cached() -> VibenetContracts? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(VibenetContracts.self, from: data)
    }

    private static func store(_ contracts: VibenetContracts) {
        guard let data = try? JSONEncoder().encode(contracts) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Date(), forKey: fetchedAtKey)
    }

    private static var fresh: Bool {
        guard let at = UserDefaults.standard.object(forKey: fetchedAtKey) as? Date else { return false }
        return Date().timeIntervalSince(at) < ttl
    }

    private static func fetch() async -> VibenetContracts? {
        guard let raw = await IngestSupport.getJSON(configURL) as? [String: Any] else { return nil }
        return parse(raw)
    }

    /// `eip8130` is the one nested object this file reads today — the four
    /// addresses `VibenetRead` calls against. A field missing from that
    /// object is a shape this build can't use at all (never a partial
    /// contracts set with a hole in the middle of it), so the whole parse
    /// fails rather than returning something that would silently point
    /// `getActorConfig` at an empty string.
    static func parse(_ raw: [String: Any]) -> VibenetContracts? {
        guard let eip8130 = raw["eip8130"] as? [String: Any],
              let keystore = eip8130["Keystore"] as? String, !keystore.isEmpty,
              let p256 = eip8130["P256Authenticator"] as? String, !p256.isEmpty,
              let webAuthn = eip8130["WebAuthnAuthenticator"] as? String, !webAuthn.isEmpty,
              let delegate = eip8130["DelegateAuthenticator"] as? String, !delegate.isEmpty
        else { return nil }
        return VibenetContracts(
            branch: raw["_branch"] as? String,
            commit: raw["_commit"] as? String,
            faucetAddress: raw["faucetAddress"] as? String,
            keystore: keystore,
            defaultAccount: eip8130["DefaultAccount"] as? String,
            canonicalHighRatePayerAccount: eip8130["CanonicalHighRatePayerAccount"] as? String,
            p256Authenticator: p256,
            webAuthnAuthenticator: webAuthn,
            delegateAuthenticator: delegate,
            policyManager: eip8130["PolicyManager"] as? String,
            sessionPolicy: eip8130["SessionPolicy"] as? String,
            usdv: raw["usdv"] as? String,
            nfv: raw["nfv"] as? String,
            vibecheck: raw["vibecheck"] as? String)
    }

    /// The config a read should use RIGHT NOW: a fresh cache when there is
    /// one, else a live fetch (which refreshes the cache), else — only when
    /// BOTH of those miss — the last config this device ever saw, so a
    /// momentary network hiccup doesn't blank out an otherwise-good read.
    /// There is no OTHER fallback: a config this call can't produce is
    /// reported unreached (`VibenetRoom.configReached == false`), never
    /// guessed at from a literal.
    static func current() async -> VibenetContracts? {
        if fresh, let cached = cached() { return cached }
        if let live = await fetch() { store(live); return live }
        return cached()
    }
}

// MARK: - The watch list

/// Which vibenet addresses this device has named — a plain `Codable`
/// `[String]` in UserDefaults, `TrendingStore`'s exact shape, not a `Thing`
/// per address: see the file's header doc for why. Watching is naming, not
/// consent to anything beyond a read — there is no account, no key, and no
/// write this bridge could make even if it wanted to.
@Observable
final class VibenetWatch {
    static let shared = VibenetWatch()
    private static let key = "vibenet.watch.addresses.v1"
    /// A SEPARATE key from the address list on purpose — an older install's
    /// watch list decodes untouched whether or not this one has ever
    /// written anything, and clearing every name can never take a watched
    /// address down with it.
    private static let namesKey = "vibenet.watch.names.v1"

    private var addressList: [String] { didSet { persist() } }
    /// Lowercased address → the local nickname. Display-only: never read by
    /// any network call, never lands on a `Thing`, never appears in a log
    /// line — the address itself is what identifies the account everywhere
    /// else in this bridge.
    private var names: [String: String] { didSet { persistNames() } }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([String].self, from: data) {
            addressList = saved
        } else {
            addressList = []
        }
        if let data = UserDefaults.standard.data(forKey: Self.namesKey),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            names = saved
        } else {
            names = [:]
        }
    }

    var addresses: [String] { addressList }
    var connected: Bool { !addressList.isEmpty }

    /// The nickname for an address, or nil when none was set — the row
    /// falls back to the short hex form exactly as before.
    func name(for address: String) -> String? {
        let key = address.lowercased()
        guard let n = names[key], !n.isEmpty else { return nil }
        return n
    }

    /// An empty/whitespace-only string CLEARS the name rather than storing
    /// it — there is no separate "remove name" action, so the same text
    /// field that sets a name is the one that unsets it.
    func setName(_ raw: String, for address: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = address.lowercased()
        if trimmed.isEmpty { names.removeValue(forKey: key) }
        else { names[key] = trimmed }
    }

    func isWatching(_ address: String) -> Bool {
        addressList.contains { $0.caseInsensitiveCompare(address) == .orderedSame }
    }

    /// A plain `0x`-prefixed 40-hex-char address — the whole validation.
    /// vibenet has no name registrar, so unlike a mainnet wallet there is no
    /// ENS/.sol form to resolve; a pasted name that isn't already hex is
    /// simply not a vibenet address.
    static func isValidAddress(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count == 42, s.hasPrefix("0x") else { return false }
        return s.dropFirst(2).allSatisfy(\.isHexDigit)
    }

    @discardableResult
    func add(_ raw: String) -> Bool {
        let address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard VibenetWatch.isValidAddress(address), !isWatching(address) else { return false }
        addressList.append(address)
        return true
    }

    func remove(_ address: String) {
        addressList.removeAll { $0.caseInsensitiveCompare(address) == .orderedSame }
        names.removeValue(forKey: address.lowercased())
    }

    func removeAll() {
        addressList = []
        names = [:]
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(addressList) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private func persistNames() {
        if let data = try? JSONEncoder().encode(names) {
            UserDefaults.standard.set(data, forKey: Self.namesKey)
        }
    }
}

// MARK: - Bridge registration

enum VibenetBridge {
    /// The seat registers itself off the watch list, so the catalog can
    /// never show a connected seat that reads nothing.
    static func registerBridge(store: BridgeStore) {
        let addresses = VibenetWatch.shared.addresses
        guard !addresses.isEmpty else { store.remove(VibenetIdentity.seatID); return }
        store.registerConnected(
            id: VibenetIdentity.seatID,
            name: VibenetIdentity.source,
            proof: addresses.count == 1
                ? String(localized: "1 address watched")
                : String(localized: "\(addresses.count) addresses watched"),
            can: [
                String(localized: "Reads which keys can act for a watched address — and whether it's locked — on Base's vibenet devnet, where native account abstraction (EIP-8130) is being tested."),
                String(localized: "Read-only — this app never signs or sends anything against it."),
            ])
    }

    static func disconnect(store: BridgeStore) {
        VibenetWatch.shared.removeAll()
        store.remove(VibenetIdentity.seatID)
    }
}

// MARK: - RPC (keyless)

/// The one measured RPC host — `WalletApprovals`'s pattern of a small chain
/// table, shrunk to a single chain that isn't in that file's own table
/// (vibenet isn't a `WalletChainStore` network; a person's wallet holdings
/// have nothing to do with a devnet test account).
enum VibenetChain {
    static let network = "vibenet"
    static let chainID = 84_538_453
    static let rpc = "https://rpc.vibes.base.org"

    static func call(method: String, params: [Any]) async -> Any? {
        let body: [String: Any] = ["id": 1, "jsonrpc": "2.0", "method": method, "params": params]
        guard let root = await IngestSupport.postJSON(rpc, body: body) as? [String: Any],
              let result = root["result"], !(result is NSNull) else { return nil }
        return result
    }

    static func ethCall(to: String, data: String) async -> String? {
        await call(method: "eth_call", params: [["to": to, "data": data], "latest"]) as? String
    }

    /// A full-range read from block 0 — this is a brand-new, small devnet,
    /// so unlike `WalletApprovals`'s mainnet chunking there is no history
    /// large enough to need it. A read that fails or times out simply
    /// returns nil, same as every other read here, and the caller reports
    /// that address unreached rather than guessing at a partial roster.
    static func getLogs(address: String, topics: [Any]) async -> [[String: Any]]? {
        let params: [String: Any] = [
            "address": address, "fromBlock": "0x0", "toBlock": "latest", "topics": topics,
        ]
        return await call(method: "eth_getLogs", params: [params]) as? [[String: Any]]
    }

    /// A block's own timestamp — what a landed event is dated by, never
    /// `.now`. `WalletApprovals`' own doc states the reason: a fallback
    /// rendered as a sentence dates a years-old event to today, and on a
    /// devnet whose whole story is "this changed while you weren't
    /// looking", a wrong date is the one thing this feature can't afford to
    /// get wrong.
    static func blockTime(_ blockNumber: Int) async -> Date? {
        guard blockNumber >= 0,
              let raw = await call(method: "eth_getBlockByNumber",
                                   params: ["0x" + String(blockNumber, radix: 16), false]) as? [String: Any],
              let tsHex = raw["timestamp"] as? String
        else { return nil }
        let seconds = WalletIngest.hexToDouble(tsHex)
        guard seconds.isFinite, seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}

/// `Keystore.sol`'s event topics — verified by keccak256 against
/// pycryptodome ground truth (`scripts/vibenet-selftest.sh`, the exact
/// discipline `Model/Keccak256.swift`'s own self-test uses).
enum VibenetTopics {
    /// `ActorAuthorized(address indexed account, bytes32 indexed actorId, bytes actorData)`
    static let actorAuthorized = "0x7427678b205ea26cd22254b5ebdc924c4bf6f9bb78e436872e49599e97963559"
    /// `ActorRevoked(address indexed account, bytes32 indexed actorId)`
    static let actorRevoked = "0xeb5bd9b1e97c446e28bffcb6963893ca5ad94dc662962fd732ffc03ca279b3e5"
    /// `AccountLocked(address indexed account, uint16 unlockDelay)`
    static let accountLocked = "0x4a8801779ef27ce1723fcf0d4ff8167d3d1710a93ca5e61bbbf0f5b753f02d8b"
    /// `AccountCreated(address indexed account, bytes32 userSalt, bytes32 codeHash)` —
    /// the ONLY door onto "which accounts exist at all" (`Keystore.sol`
    /// exposes no enumeration call), so it's what the empty-state discovery
    /// read filters on rather than an owner topic — there is no owner to
    /// filter by until an address has been named.
    static let accountCreated = "0x934abbffb6906db60a85b076f1e41da9667dfa53c7724f4fe2333298d7b1db8c"
}

// MARK: - ABI (hand-rolled, no dynamic types — every return here is fixed-width)

enum VibenetABI {
    static func padAddress(_ address: String) -> String {
        String(repeating: "0", count: 24) + address.dropFirst(2).lowercased()
    }

    private static func padTopic32(_ hex: String) -> String {
        var s = hex.lowercased()
        if s.hasPrefix("0x") { s.removeFirst(2) }
        guard s.count < 64 else { return s }
        return String(repeating: "0", count: 64 - s.count) + s
    }

    /// `isContractEstablished(address)` — 0x28a4c4cb
    static func isEstablishedCall(_ address: String) -> String {
        "0x28a4c4cb" + padAddress(address)
    }

    /// `getActorConfig(address,bytes32)` — 0xd1a62df4
    static func actorConfigCall(_ address: String, actorId: String) -> String {
        "0xd1a62df4" + padAddress(address) + padTopic32(actorId)
    }

    /// `getLockStatus(address)` — 0x0f36f691
    static func lockStatusCall(_ address: String) -> String {
        "0x0f36f691" + padAddress(address)
    }

    /// `getChangeSequences(address)` — 0x82e5f7c6
    static func changeSequencesCall(_ address: String) -> String {
        "0x82e5f7c6" + padAddress(address)
    }

    /// One 32-byte WORD at `index` (0-based) out of an ABI-encoded return.
    /// Every return this file reads is fixed-width — no dynamic `bytes`, no
    /// offset table — so this is the whole decoder.
    static func word(_ hex: String, at index: Int) -> String? {
        var s = hex.lowercased()
        if s.hasPrefix("0x") { s.removeFirst(2) }
        let start = index * 64
        guard s.count >= start + 64 else { return nil }
        let i = s.index(s.startIndex, offsetBy: start)
        let j = s.index(i, offsetBy: 64)
        return String(s[i..<j])
    }

    static func addressWord(_ hex: String, at index: Int) -> String? {
        guard let w = word(hex, at: index) else { return nil }
        return "0x" + w.suffix(40)
    }

    /// A safe, bounded `UInt64` read of a word — `WalletIngest.hexToDouble`
    /// already refuses a non-finite/oversized hex string rather than
    /// trapping, so this only adds the ceiling that keeps a garbage 256-bit
    /// word from overflowing the `UInt64(_:)` conversion.
    static func uintWord(_ hex: String, at index: Int) -> UInt64 {
        guard let w = word(hex, at: index) else { return 0 }
        let d = WalletIngest.hexToDouble("0x" + w)
        guard d.isFinite, d >= 0, d < 1e15 else { return 0 }
        return UInt64(d)
    }

    static func boolWord(_ hex: String, at index: Int) -> Bool {
        guard let w = word(hex, at: index) else { return false }
        return WalletIngest.hexToDouble("0x" + w) != 0
    }
}

// MARK: - The live per-address read

enum VibenetRead {
    /// Every actorId this account has EVER authorized, unioned against later
    /// revocations by the LATEST event per id (by block, then log index).
    ///
    /// `Keystore.sol` exposes no "list my actors" call, so this is the only
    /// door in: `eth_getLogs` for `ActorAuthorized`/`ActorRevoked` filtered
    /// to this account as the FIRST indexed topic (both events share that
    /// shape), the `WalletApprovals` OR-topic0 pattern. A revoked-then-
    /// reauthorized actorId must read as live, which is exactly what
    /// "latest event wins" gives for free — and it's why `VibenetRoom`'s
    /// doc calls `getActorConfig` the AUTHORITATIVE confirmation: an actor
    /// can also stop being live by its own `expiry` passing, which this log
    /// walk alone has no way to see.
    static func actorIDs(account: String, keystore: String) async -> [String]? {
        guard let events = await actorEvents(account: account, keystore: keystore) else { return nil }
        // The chronological last-write-wins union is `VibenetActorLog
        // .survivors` (`VibenetRoom.swift`, Foundation-only and mutation-
        // tested by `scripts/vibenet-selftest.sh`) — kept out of this file
        // so that arithmetic can be proven with no network in sight.
        return Array(VibenetActorLog.survivors(events))
    }

    /// The RAW event log behind `actorIDs`'s survivor union — split out so
    /// `account(_:contracts:)` can read the key-history strip (R2.1) off
    /// the SAME `eth_getLogs` call rather than paying for it twice.
    static func actorEvents(account: String, keystore: String) async -> [VibenetActorEvent]? {
        let ownerTopic = "0x" + VibenetABI.padAddress(account)
        guard let logs = await VibenetChain.getLogs(
            address: keystore,
            topics: [[VibenetTopics.actorAuthorized, VibenetTopics.actorRevoked], ownerTopic])
        else { return nil }

        var events: [VibenetActorEvent] = []
        for log in logs {
            guard (log["removed"] as? Bool) != true,
                  let topics = log["topics"] as? [String], topics.count >= 3,
                  let blockHex = log["blockNumber"] as? String,
                  let indexHex = log["logIndex"] as? String
            else { continue }
            let topic0 = topics[0].lowercased()
            let authorized = topic0 == VibenetTopics.actorAuthorized
            guard authorized || topic0 == VibenetTopics.actorRevoked else { continue }
            events.append(VibenetActorEvent(actorId: topics[2].lowercased(), authorized: authorized,
                                            block: WalletIngest.hexToInt(blockHex),
                                            logIndex: WalletIngest.hexToInt(indexHex)))
        }
        return events
    }

    /// One actor's LIVE state, confirmed via `getActorConfig` rather than
    /// trusted to the log walk alone. A revoked (or never-real) actor reads
    /// back the zero address here, which is dropped rather than reported as
    /// a phantom actor.
    static func actor(account: String, keystore: String, actorId: String,
                      known: VibenetKnownAuthenticators) async -> VibenetActor? {
        guard let raw = await VibenetChain.ethCall(
            to: keystore, data: VibenetABI.actorConfigCall(account, actorId: actorId)),
              let authenticator = VibenetABI.addressWord(raw, at: 0)
        else { return nil }
        guard authenticator.lowercased() != VibenetAuthenticatorKind.zeroAddress else { return nil }
        let expiry = VibenetABI.uintWord(raw, at: 1)
        let scopeRaw = UInt16(truncatingIfNeeded: VibenetABI.uintWord(raw, at: 2))
        let kind = VibenetAuthenticatorKind.identify(authenticator: authenticator, known: known)
        return VibenetActor(actorId: actorId, authenticator: authenticator, kind: kind,
                            scope: VibenetScope(raw: scopeRaw), expiry: expiry)
    }

    /// One account's change-sequence standing on THIS chain — see
    /// `VibenetChangeSequences`'s own doc for what the three fields mean.
    /// `nil` on any read failure, never a zeroed struct: a genuine "no
    /// changes yet" account and a call this build couldn't complete must
    /// not render the same way.
    static func changeSequences(account: String, keystore: String) async -> VibenetChangeSequences? {
        guard let raw = await VibenetChain.ethCall(
            to: keystore, data: VibenetABI.changeSequencesCall(account))
        else { return nil }
        return VibenetChangeSequences(
            multichain: VibenetABI.uintWord(raw, at: 0),
            localEpoch: UInt32(truncatingIfNeeded: VibenetABI.uintWord(raw, at: 1)),
            localSequence: UInt32(truncatingIfNeeded: VibenetABI.uintWord(raw, at: 2)))
    }

    /// One address's whole live read: established?, actor roster, lock
    /// status, change-sequence standing. `reached == false` only when the
    /// FIRST call (`isContractEstablished`) failed outright — every other
    /// field then carries its neutral default rather than a half-finished
    /// guess.
    static func account(_ address: String, contracts: VibenetContracts) async -> VibenetAccountItem {
        guard let establishedWord = await VibenetChain.ethCall(
            to: contracts.keystore, data: VibenetABI.isEstablishedCall(address))
        else {
            return VibenetAccountItem(address: address, reached: false, established: false,
                                      actors: [], locked: false, hasInitiatedUnlock: false,
                                      unlocksAt: nil, unlockDelay: nil)
        }
        let established = WalletIngest.hexToDouble(establishedWord) != 0

        async let eventsTask = actorEvents(account: address, keystore: contracts.keystore)
        async let lockTask = VibenetChain.ethCall(
            to: contracts.keystore, data: VibenetABI.lockStatusCall(address))
        async let sequencesTask = changeSequences(account: address, keystore: contracts.keystore)
        let events = await eventsTask
        let lockRaw = await lockTask
        let sequences = await sequencesTask

        var actors: [VibenetActor] = []
        if let events {
            let ids = VibenetActorLog.survivors(events)
            let known = contracts.knownAuthenticators
            for id in ids {
                if let a = await actor(account: address, keystore: contracts.keystore,
                                       actorId: id, known: known) {
                    actors.append(a)
                }
            }
        }

        // R2.1: the account's own story, off the SAME events — no second
        // `eth_getLogs`. Kind is resolved only for a currently-live
        // authorized actor (matched against the roster just built above,
        // zero extra `eth_call`s); a later-revoked actor's kind at that
        // past moment isn't retrievable without an archive node, so it
        // stays nil rather than guessed. Block times are looked up ONCE
        // per distinct block (several events can share a block) and
        // bounded to `VibenetKeyHistory.cap` moments — devnet-cheap.
        var history: [VibenetKeyMoment] = []
        if let events {
            let liveKind = Dictionary(uniqueKeysWithValues: actors.map { ($0.actorId, $0.kind) })
            let newest = VibenetKeyHistory.newest(events)
            var blockDates: [Int: Date] = [:]
            for block in Set(newest.map(\.block)) {
                if let date = await VibenetChain.blockTime(block) { blockDates[block] = date }
            }
            history = VibenetKeyHistory.ordered(newest.map { e in
                VibenetKeyMoment(block: e.block, logIndex: e.logIndex, authorized: e.authorized,
                                 kind: e.authorized ? liveKind[e.actorId] : nil,
                                 date: blockDates[e.block])
            })
        }

        var locked = false, hasInitiatedUnlock = false
        var unlocksAt: UInt64?
        var unlockDelay: UInt16?
        if let lockRaw {
            locked = VibenetABI.boolWord(lockRaw, at: 0)
            hasInitiatedUnlock = VibenetABI.boolWord(lockRaw, at: 1)
            let at = VibenetABI.uintWord(lockRaw, at: 2)
            unlocksAt = at > 0 ? at : nil
            unlockDelay = UInt16(truncatingIfNeeded: VibenetABI.uintWord(lockRaw, at: 3))
        }

        return VibenetAccountItem(address: address, reached: true, established: established,
                                  actors: actors, locked: locked,
                                  hasInitiatedUnlock: hasInitiatedUnlock,
                                  unlocksAt: unlocksAt, unlockDelay: unlockDelay,
                                  changeSequences: sequences, history: history)
    }
}

// MARK: - Has vibenet redeployed since this device last looked?

/// The last vibenet commit THIS DEVICE has seen — a fact about the screen,
/// not the chain, so it lives here in UserDefaults rather than in
/// `VibenetRoom` (pure, Foundation-only, no UserDefaults of its own), the
/// same split `AddressConnectionsSeen`/`ChipMemory` already draw elsewhere.
enum VibenetSeenCommit {
    private static let key = "vibenet.contracts.lastSeenCommit"

    /// Compares `commit` against what was stored, then advances the stored
    /// value to `commit` regardless of the outcome — every call is also the
    /// write. A first-ever call (nothing stored yet) is silent by design:
    /// there is nothing yet to compare against, so it can never report a
    /// redeploy on the very first read, the same rule that keeps
    /// `AddressConnectionsSeen` from painting someone's whole existing book
    /// as "new" the day the feature ships.
    static func checkAndAdvance(_ commit: String?) -> Bool {
        guard let commit else { return false }
        let previous = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set(commit, forKey: key)
        guard let previous else { return false }
        return previous != commit
    }
}

// MARK: - Composing the room

enum VibenetRoomSource {
    /// The whole card — a config read, then every watched address, up to 3
    /// at once (`AerodromeDeFi`'s pacing lesson: this is one public host,
    /// and an unpaced burst against a small devnet node is the surest way
    /// to make the very first thing this feature does read "unreachable").
    static func compose() async -> VibenetRoom {
        // The demo reaches nothing, the standing rule for every bridge here —
        // and this one has NO persistence layer to seed a snapshot into the
        // way Cloudflare's estate or Altana's keystore do, since a real read
        // is deliberately never cached (the whole feature's premise is that
        // vibenet moves under you). `VibenetRoom.demoFixture()` is the
        // snapshot instead, returned before this ever touches the network.
        if DemoMode.isActive { return VibenetRoom.demoFixture() }
        guard let contracts = await VibenetConfig.current() else {
            return VibenetRoom.compose(items: [], branch: nil, commit: nil, configReached: false)
        }
        // Checked (and the stored value advanced) BEFORE the account reads,
        // not after — a redeploy is exactly what the account reads below are
        // being freshly checked against, so the note's claim that "every
        // watched account was just re-read against it" has to already be true
        // by the time it's shown.
        let redeployed = VibenetSeenCommit.checkAndAdvance(contracts.commit)
        let addresses = VibenetWatch.shared.addresses
        let items = await IngestSupport.boundedGather(addresses, maxConcurrent: 3) { address in
            await VibenetRead.account(address, contracts: contracts)
        }
        return VibenetRoom.compose(items: items, branch: contracts.branch,
                                   commit: contracts.commit, configReached: true,
                                   redeployedSinceLastSeen: redeployed)
    }
}

// MARK: - The explorer door

/// Base's own vibenet block explorer — MEASURED, not guessed (2026-08-23):
/// `chain.base.org/vibenet/explorer/address/<addr>` answers 200 with a real
/// account page (confirmed against `K1_AUTHENTICATOR`'s own fixed address).
/// The transaction form follows the same explorer's own address/tx
/// convention but has not itself been fetched against a real tx hash — UN-
/// MEASURED, and it fails safe: a wrong tx path is a page that 404s in the
/// person's own browser, never a crash or a wrong claim inside the app.
enum VibenetExplorer {
    private static let base = "https://chain.base.org/vibenet/explorer"
    static func address(_ address: String) -> String { "\(base)/address/\(address)" }
    static func tx(_ hash: String) -> String { "\(base)/tx/\(hash)" }
}

// MARK: - Landed events (ActorAuthorized / ActorRevoked / AccountLocked)

enum VibenetEvents {
    /// Lands every NEW key-authorized/revoked and account-locked event for
    /// every WATCHED address, as `Thing`s — see `VibenetEventKind`'s own doc
    /// for why these three (and only these three) are news rather than live
    /// state. Read-only like everything else in this file: it reads the
    /// events `VibenetRead.actorIDs` already reads for the live roster, and
    /// nothing here signs or sends. Called from `BridgeRefresh`, the same
    /// door every other watch-list bridge lands through.
    @MainActor
    static func land(context: ModelContext) async -> Int {
        guard let contracts = await VibenetConfig.current() else { return 0 }
        let addresses = VibenetWatch.shared.addresses
        guard !addresses.isEmpty else { return 0 }
        let existing = IngestSupport.existingSourceRefs(context, source: VibenetIdentity.source)

        var landed = 0
        for address in addresses {
            landed += await landAccount(address, contracts: contracts, context: context, existing: existing)
        }
        return landed
    }

    private struct RawEvent {
        let kind: VibenetEventKind
        let actorId: String?
        let txHash: String
        let logIndex: Int
        let block: Int
    }

    private static func parse(_ log: [String: Any], kind: VibenetEventKind) -> RawEvent? {
        guard (log["removed"] as? Bool) != true,
              let topics = log["topics"] as? [String],
              let txHash = log["transactionHash"] as? String,
              let indexHex = log["logIndex"] as? String,
              let blockHex = log["blockNumber"] as? String
        else { return nil }
        // ActorAuthorized/ActorRevoked carry the actorId as topics[2]; a
        // lock event has no third topic to read (unlockDelay isn't
        // indexed), so `actorId` stays nil for that kind.
        let actorId = (kind == .locked) ? nil : (topics.count >= 3 ? topics[2].lowercased() : nil)
        if kind != .locked && actorId == nil { return nil }
        return RawEvent(kind: kind, actorId: actorId, txHash: txHash,
                        logIndex: WalletIngest.hexToInt(indexHex), block: WalletIngest.hexToInt(blockHex))
    }

    private static func ref(_ e: RawEvent) -> String {
        "vibenet:\(e.kind == .locked ? "locked" : "actor"):\(e.txHash):\(e.logIndex)"
    }

    @MainActor
    private static func landAccount(_ address: String, contracts: VibenetContracts,
                                    context: ModelContext, existing: Set<String>) async -> Int {
        let ownerTopic = "0x" + VibenetABI.padAddress(address)
        async let actorLogsTask = VibenetChain.getLogs(
            address: contracts.keystore,
            topics: [[VibenetTopics.actorAuthorized, VibenetTopics.actorRevoked], ownerTopic])
        async let lockLogsTask = VibenetChain.getLogs(
            address: contracts.keystore, topics: [VibenetTopics.accountLocked, ownerTopic])
        let actorLogs = await actorLogsTask ?? []
        let lockLogs = await lockLogsTask ?? []

        var events: [RawEvent] = []
        for log in actorLogs {
            guard let topics = log["topics"] as? [String], let topic0 = topics.first?.lowercased() else { continue }
            let kind: VibenetEventKind = topic0 == VibenetTopics.actorAuthorized ? .actorAuthorized : .actorRevoked
            if let e = parse(log, kind: kind) { events.append(e) }
        }
        for log in lockLogs {
            if let e = parse(log, kind: .locked) { events.append(e) }
        }
        let fresh = events.filter { !existing.contains(ref($0)) }
        guard !fresh.isEmpty else { return 0 }

        // Block times, ONE call per distinct block among the new events —
        // never `.now` unless the read genuinely fails, the WalletApprovals
        // rule: a fallback rendered as a sentence dates real news to today.
        var times: [Int: Date] = [:]
        for block in Set(fresh.map(\.block)) {
            times[block] = await VibenetChain.blockTime(block)
        }

        let known = contracts.knownAuthenticators
        let shortAddress = VibenetRoom.shortAddress(address)
        var landedCount = 0
        for event in fresh {
            var keyLabel: String?
            if event.kind == .actorAuthorized, let actorId = event.actorId,
               let actor = await VibenetRead.actor(account: address, keystore: contracts.keystore,
                                                    actorId: actorId, known: known) {
                keyLabel = actor.kind.label
            }
            let thing = Thing(
                kind: .transaction,
                title: event.kind.title(shortAddress: shortAddress, keyLabel: keyLabel),
                content: VibenetExplorer.tx(event.txHash),
                source: VibenetIdentity.source,
                capturedAt: times[event.block] ?? .now,
                sourceRef: ref(event))
            thing.walletAddress = address
            context.insert(thing)
            landedCount += 1
        }
        return landedCount
    }
}

// MARK: - Discovery (the empty-state door)

enum VibenetDiscovery {
    /// The most recently created vibenet accounts, straight off
    /// `AccountCreated` — the setup screen's fix for the empty state a
    /// paste-only address field left someone in on a devnet where nothing
    /// they own has ever touched it. `Keystore.sol` names no owner in this
    /// event (an account can be created by anyone, for any address), so
    /// unlike every other read in this file there is no address to filter
    /// by — this is the one GLOBAL read here, bounded by taking only the
    /// newest `limit` rather than by a block range, the same "small young
    /// devnet, no chunking needed" reasoning `VibenetChain.getLogs`'s own
    /// doc already gives for the per-address reads.
    static func recentAccounts(keystore: String, limit: Int = 5) async -> [VibenetDiscoveredAccount] {
        guard let logs = await VibenetChain.getLogs(
            address: keystore, topics: [VibenetTopics.accountCreated])
        else { return [] }

        struct Row { let address: String; let block: Int; let logIndex: Int }
        var rows: [Row] = []
        for log in logs {
            guard (log["removed"] as? Bool) != true,
                  let topics = log["topics"] as? [String], topics.count >= 2,
                  let blockHex = log["blockNumber"] as? String,
                  let indexHex = log["logIndex"] as? String
            else { continue }
            let address = "0x" + topics[1].suffix(40)
            rows.append(Row(address: address, block: WalletIngest.hexToInt(blockHex),
                            logIndex: WalletIngest.hexToInt(indexHex)))
        }
        // Newest first (by block, then log index within a block) — someone
        // exploring the devnet wants what's fresh, not the oldest account
        // ever created on it.
        rows.sort { ($0.block, $0.logIndex) > ($1.block, $1.logIndex) }

        var seen = Set<String>()
        var picked: [Row] = []
        for row in rows {
            let key = row.address.lowercased()
            guard seen.insert(key).inserted else { continue }
            picked.append(row)
            if picked.count >= limit { break }
        }

        // Bounded by the same cap as the walk itself — at most `limit`
        // sequential lookups, fine on a devnet this small.
        var out: [VibenetDiscoveredAccount] = []
        for row in picked {
            let createdAt = await VibenetChain.blockTime(row.block)
            out.append(VibenetDiscoveredAccount(address: row.address, createdAt: createdAt))
        }
        return out
    }
}
