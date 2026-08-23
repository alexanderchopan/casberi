import Foundation
import Observation

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

    private var addressList: [String] { didSet { persist() } }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([String].self, from: data) {
            addressList = saved
        } else {
            addressList = []
        }
    }

    var addresses: [String] { addressList }
    var connected: Bool { !addressList.isEmpty }

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
    }

    func removeAll() { addressList = [] }

    private func persist() {
        if let data = try? JSONEncoder().encode(addressList) {
            UserDefaults.standard.set(data, forKey: Self.key)
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
                String(localized: "Reads a watched address's account-abstraction state on Base's experimental vibenet devnet."),
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
}

/// `Keystore.sol`'s event topics — verified by keccak256 against
/// pycryptodome ground truth (`scripts/vibenet-selftest.sh`, the exact
/// discipline `Model/Keccak256.swift`'s own self-test uses).
enum VibenetTopics {
    /// `ActorAuthorized(address indexed account, bytes32 indexed actorId, bytes actorData)`
    static let actorAuthorized = "0x7427678b205ea26cd22254b5ebdc924c4bf6f9bb78e436872e49599e97963559"
    /// `ActorRevoked(address indexed account, bytes32 indexed actorId)`
    static let actorRevoked = "0xeb5bd9b1e97c446e28bffcb6963893ca5ad94dc662962fd732ffc03ca279b3e5"
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
        // The chronological last-write-wins union is `VibenetActorLog
        // .survivors` (`VibenetRoom.swift`, Foundation-only and mutation-
        // tested by `scripts/vibenet-selftest.sh`) — kept out of this file
        // so that arithmetic can be proven with no network in sight.
        return Array(VibenetActorLog.survivors(events))
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

    /// One address's whole live read: established?, actor roster, lock
    /// status. `reached == false` only when the FIRST call
    /// (`isContractEstablished`) failed outright — every other field then
    /// carries its neutral default rather than a half-finished guess.
    static func account(_ address: String, contracts: VibenetContracts) async -> VibenetAccountItem {
        guard let establishedWord = await VibenetChain.ethCall(
            to: contracts.keystore, data: VibenetABI.isEstablishedCall(address))
        else {
            return VibenetAccountItem(address: address, reached: false, established: false,
                                      actors: [], locked: false, hasInitiatedUnlock: false,
                                      unlocksAt: nil, unlockDelay: nil)
        }
        let established = WalletIngest.hexToDouble(establishedWord) != 0

        async let idsTask = actorIDs(account: address, keystore: contracts.keystore)
        async let lockTask = VibenetChain.ethCall(
            to: contracts.keystore, data: VibenetABI.lockStatusCall(address))
        let ids = await idsTask
        let lockRaw = await lockTask

        var actors: [VibenetActor] = []
        if let ids {
            let known = contracts.knownAuthenticators
            for id in ids {
                if let a = await actor(account: address, keystore: contracts.keystore,
                                       actorId: id, known: known) {
                    actors.append(a)
                }
            }
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
                                  unlocksAt: unlocksAt, unlockDelay: unlockDelay)
    }
}

// MARK: - Composing the room

enum VibenetRoomSource {
    /// The whole card — a config read, then every watched address, up to 3
    /// at once (`AerodromeDeFi`'s pacing lesson: this is one public host,
    /// and an unpaced burst against a small devnet node is the surest way
    /// to make the very first thing this feature does read "unreachable").
    static func compose() async -> VibenetRoom {
        guard let contracts = await VibenetConfig.current() else {
            return VibenetRoom.compose(items: [], branch: nil, commit: nil, configReached: false)
        }
        let addresses = VibenetWatch.shared.addresses
        let items = await IngestSupport.boundedGather(addresses, maxConcurrent: 3) { address in
            await VibenetRead.account(address, contracts: contracts)
        }
        return VibenetRoom.compose(items: items, branch: contracts.branch,
                                   commit: contracts.commit, configReached: true)
    }
}
