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

/// The shape of `api.vibes.base.org/api/vibenet/contracts`'s response.
/// `usdv`/`nfv` are read now (2026-08-24, `VibenetRead.tokenBalance`) —
/// `faucetAddress`/`vibecheck` are still carried through unread rather
/// than dropped, so a future read of either doesn't need to re-touch the
/// parse.
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

    /// THE DEMO'S CONTRACTS (2026-08-25, prd §476).
    ///
    /// The demo fixture carries an account that is reached but NOT established
    /// — the undeployed case — and §476 put its explainer and its faucet door
    /// on the accounts card, where somebody would actually meet it. The
    /// explainer drew; **the faucet could not**, because that door is gated on
    /// `cached()?.faucetAddress` and nothing had ever written a config in demo
    /// mode: `cached()` reads what a LIVE fetch last stored, and a demo
    /// install has never made one. So the demo showed the problem and withheld
    /// the one button that answers it — exactly the "demo has less than the
    /// app" gap `verify.sh`'s own demo-parity step exists to catch.
    ///
    /// Written through the same `store` the live fetch uses rather than a
    /// demo-only key, so the demo exercises the REAL read path; `forget()`
    /// takes it away again on teardown, and a real config simply overwrites
    /// it on the next fetch (the cache is a cache).
    ///
    /// Addresses are the fixture's own shape — deliberately NOT starting
    /// `0x8130`, vibenet's vanity prefix, for `demoFixture`'s stated reason:
    /// the drift guard forbidding a hardcoded vibenet contract address cannot
    /// tell a demo fixture from a live call, and should not have to.
    static func seedDemo() {
        store(VibenetContracts(
            branch: "main", commit: "a9ae95e1b",
            faucetAddress: "0xfafa1111222233334444555566667777888899fa",
            keystore: "0x9999111122223333444455556666777788889999",
            defaultAccount: nil, canonicalHighRatePayerAccount: nil,
            p256Authenticator: "0xaaaa1111222233334444555566667777888899aa",
            webAuthnAuthenticator: "0xbbbb1111222233334444555566667777888899bb",
            delegateAuthenticator: "0xcccc1111222233334444555566667777888899cc",
            policyManager: "0xdddd1111222233334444555566667777888899dd",
            sessionPolicy: "0xeeee1111222233334444555566667777888899ee",
            usdv: nil, nfv: nil, vibecheck: nil))
    }

    /// Drops the cached config — demo teardown's own call. A live install
    /// re-fetches on its next sweep, so this is only ever a cache miss.
    static func forgetCache() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: fetchedAtKey)
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

    /// Stop watching one account — and KEEP THE NAME (2026-08-25, prd §472).
    ///
    /// It used to forget the name in the same breath, so a mis-tapped "Stop
    /// watching" destroyed something the person had typed, with no undo and
    /// (until §472) no confirmation, and re-watching the address a second
    /// later brought back a bare `0x…44b1`. Watching and naming are two tiers
    /// over one ledger — §461's ruling for Wallet's book, and the reason this
    /// screen has no cap at all: a name costs nothing to keep.
    ///
    /// `removeAll` still clears both, which is what `VibenetBridge.disconnect`
    /// calls — so "forget everything" remains reachable and remains one
    /// deliberate act rather than a side effect of tidying a list.
    func remove(_ address: String) {
        addressList.removeAll { $0.caseInsensitiveCompare(address) == .orderedSame }
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
        // Or the feed's head keeps drawing accounts nobody watches
        // anymore — the snapshot outlives the watch list otherwise.
        VibenetState.forget()
        // And the "which keys had you seen" ledger — a re-watch months later
        // is a first sight, which seeds silently rather than reporting every
        // key change since as news.
        VibenetKeysSeen.forget()
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

    static func blockNumber() async -> Int? {
        guard let hex = await call(method: "eth_blockNumber", params: []) as? String else { return nil }
        let n = WalletIngest.hexToInt(hex)
        return n >= 0 ? n : nil
    }

    /// Native (vibenet ETH-equivalent) balance — `eth_getBalance`, standard
    /// JSON-RPC rather than an `eth_call`: there's no contract to call, the
    /// node tracks an account's native balance itself. Always 18 decimals
    /// (an EVM-wide constant for the native asset, not a per-token guess —
    /// the one balance in this feature safe to scale without a live
    /// `decimals()` read first; see `VibenetRead.account`'s own doc).
    static func getBalance(address: String) async -> String? {
        await call(method: "eth_getBalance", params: [address, "latest"]) as? String
    }

    /// MEASURED 2026-08-23: the RPC enforces a 100,000-block ceiling on
    /// `eth_getLogs` ("query exceeds max block range 100000") — this devnet
    /// simply outgrew the "brand-new, small devnet, no history large enough
    /// to need chunking" assumption this file shipped with (chain height
    /// 285,133 the day this was measured, walkable at block 0 in a single
    /// unbounded call for the feature's first three weeks). A from-block-0
    /// read now fails OUTRIGHT and silently reads as "unreached" — the
    /// reported bug this fixes: a genuinely established account read as
    /// "not established yet", and the empty-state discovery read as
    /// nothing found, from the SAME root cause hitting two call sites.
    static let maxLogRange = 100_000

    /// A circuit breaker, not a coverage promise — `WalletApprovals`'s own
    /// reasoning: an unbounded crawl of a shared public RPC serves no one.
    /// 50 chunks covers 5,000,000 blocks, many multiples of this devnet's
    /// current height, so in practice every read here is still COMPLETE;
    /// if vibenet ever outgrows that too, the oldest history is what's
    /// dropped (walked TIP-BACKWARD), the same "accept a hole in the past,
    /// keep the present accurate" tradeoff `WalletApprovals` already makes.
    static let maxLogChunks = 50

    /// Walks backward from the chain tip in `maxLogRange`-sized windows,
    /// accumulating every log across all of them — unlike `WalletApprovals`
    /// (which reads a WALLET's own recent activity and is fine missing an
    /// old approval), this file needs the account's COMPLETE authorize/
    /// revoke history: `VibenetActorLog.survivors` decides liveness by the
    /// LATEST event per actorId, so a missed early authorization for a key
    /// nothing has touched since would make a live key vanish from the
    /// roster, not merely read stale. Nil only when the FIRST chunk (the
    /// newest, and the one every caller most needs) fails to answer; a
    /// failure on an OLDER chunk stops the walk there and returns what was
    /// gathered — the same partial-is-better-than-nothing shape `blockTime`
    /// and every other read in this file already uses.
    static func getLogs(address: String, topics: [Any]) async -> [[String: Any]]? {
        guard let tip = await blockNumber() else { return nil }
        let ranges = VibenetLogChunking.ranges(tip: tip, maxRange: maxLogRange, maxChunks: maxLogChunks)
        var gathered: [[String: Any]] = []
        for (index, range) in ranges.enumerated() {
            let params: [String: Any] = [
                "address": address,
                "fromBlock": "0x" + String(range.from, radix: 16),
                "toBlock": "0x" + String(range.to, radix: 16),
                "topics": topics,
            ]
            guard let page = await call(method: "eth_getLogs", params: [params]) as? [[String: Any]] else {
                return index == 0 ? nil : gathered
            }
            gathered.append(contentsOf: page)
        }
        return gathered
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
    /// `AccountUnlockInitiated(address indexed account, uint48 unlocksAt)`,
    /// prd §463 —
    /// keccak-derived and checked the way the four above were: the same
    /// derivation reproduces `accountLocked` and `actorRevoked` byte for
    /// byte, which is what makes this one trustworthy without a live log
    /// to match it against.
    static let accountUnlockInitiated = "0x3aa02eb34bef59a5898ff00768e28faaa44610222c4be33b4ff1549abf3ac5a7"
    /// `PolicyExecuted(address indexed account, address indexed policy, bytes32 indexed commitment, address caller)`
    /// — emitted by `PolicyManager` (NOT the Keystore) on every run of a
    /// policy-gated key. Derived by keccak and then MEASURED against the live
    /// chain on 2026-08-24: 6 real executions matched it.
    ///
    /// All three fields worth having are INDEXED, which is what makes this
    /// affordable: one filtered read per account gives every execution, and
    /// the commitment topic joins each straight to the key that made it, with
    /// no `data` to decode at all.
    static let policyExecuted = "0x0576b52ea4ec966438d3c15a05c64ec622b3bb0991f2b4e8ba159e9bd00b7a42"
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

    /// `getPolicyManager(address,bytes32)` — 0xa1994f16. MEASURED live against
    /// vibenet on 2026-08-24, not derived and hoped for: 7 of 34 sampled
    /// actors carried the POLICY bit and every one answered with the config's
    /// own `PolicyManager`. Note the spec's prose names a `getPolicy` that
    /// `Keystore.sol` does not declare — the contract has this, its
    /// `getPolicyCommitment` sibling, and `getActorWithPolicy`.
    static func policyManagerCall(_ address: String, actorId: String) -> String {
        "0xa1994f16" + padAddress(address) + padTopic32(actorId)
    }

    /// `getPolicyCommitment(address,bytes32)` — 0x560846aa. MEASURED live on
    /// 2026-08-24 against a real gated actor: returns the 32-byte commitment
    /// its policy is bound to.
    ///
    /// **`getActorWithPolicy` WOULD HAVE BEEN ONE CALL FOR ALL THREE FACTS,
    /// AND IT REVERTS.** It is declared in `Keystore.sol` on GitHub `main`
    /// and is NOT in vibenet's deployed build (commit a9ae95e1b) — measured
    /// the same day, `execution reverted`, while `getActorConfig`,
    /// `getPolicyManager` and this each answered correctly. Reaching for it
    /// on the strength of the published source would have taken every gated
    /// key's read down with it. The source of truth for this devnet is the
    /// devnet, not the repository it was built from.
    static func policyCommitmentCall(_ address: String, actorId: String) -> String {
        "0x560846aa" + padAddress(address) + padTopic32(actorId)
    }

    /// `getLockStatus(address)` — 0x0f36f691
    static func lockStatusCall(_ address: String) -> String {
        "0x0f36f691" + padAddress(address)
    }

    /// `getChangeSequences(address)` — 0x82e5f7c6
    static func changeSequencesCall(_ address: String) -> String {
        "0x82e5f7c6" + padAddress(address)
    }

    /// `balanceOf(address)` — 0x70a08231, the standard ERC-20 selector,
    /// used against USDV/NFV (2026-08-24).
    static func balanceOfCall(_ address: String) -> String {
        "0x70a08231" + padAddress(address)
    }

    /// `decimals()` — 0x313ce567, standard ERC-20, no arguments. Read LIVE
    /// per contract (`VibenetTokenDecimals`) rather than assumed — see that
    /// type's own doc for why 18 is never a safe default here.
    static let decimalsCall = "0x313ce567"

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

    /// The raw, UNSCALED value of a `uint256` word — deliberately NOT
    /// routed through `uintWord`'s 1e15 ceiling, which exists for a
    /// duration/timestamp field and would silently zero out any real token
    /// balance (one token at 18 decimals is already 1e18 raw, well past
    /// that ceiling). `WalletIngest.hexToDouble` already refuses a
    /// non-finite result; the CALLER divides by the token's own live-read
    /// `decimals()` before this is ever displayed, and only after that
    /// division does "too large to be real" become a meaningful question.
    static func rawAmountWord(_ hex: String, at index: Int = 0) -> Double? {
        guard let w = word(hex, at: index) else { return nil }
        let d = WalletIngest.hexToDouble("0x" + w)
        return d.isFinite ? d : nil
    }
}

/// USDV/NFV's `decimals()`, cached forever per contract —
/// `WalletApprovals.tokenFacts`'s exact reasoning, mirrored: neither value
/// can change for a deployed ERC-20, so a contract is asked once per
/// install and never again. A read that answers with nothing is NOT
/// cached — a flaky public host must not pin "unreadable" for the life of
/// the install, since a missing `decimals` is exactly what makes a balance
/// unscaleable (never assumed at 18, the standing lesson: Solana SPL,
/// Gnosis Pay's USDCe being 6 not 18).
enum VibenetTokenDecimals {
    static func read(contract: String) async -> Int? {
        let key = "vibenet.decimals.\(contract.lowercased())"
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key) != nil { return defaults.integer(forKey: key) }
        guard let hex = await VibenetChain.ethCall(to: contract, data: VibenetABI.decimalsCall),
              let word = VibenetABI.word(hex, at: 0)
        else { return nil }
        let value = WalletIngest.hexToInt("0x" + word)
        // A garbage/reverted `eth_call` can decode to an implausible value
        // (`RailgunBridge.decodeDecimals`'s own lesson: several public
        // gateways answer a REVERTING call with `{"result":"0x"}` rather
        // than an error, and an empty word must not be read as zero
        // decimals) — bounded the same way that file bounds it.
        guard (0...36).contains(value) else { return nil }
        defaults.set(value, forKey: key)
        return value
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
        let scope = VibenetScope(raw: scopeRaw)
        // The second call is made ONLY for a policy-gated key, which is what
        // keeps this cheap: most keys are not gated (27 of 34 sampled live),
        // and asking every key would double this bridge's per-actor cost to
        // learn a fact that is zero for nearly all of them. A gated key whose
        // manager reads back as the zero address, or does not read at all,
        // keeps a nil manager — "Send to one contract" still stands, it just
        // cannot say which, which is the honest degradation.
        var manager: String?
        var commitment: String?
        if scope.raw & VibenetScope.policy != 0 {
            // Both gated-key facts in one round trip each, concurrently —
            // `getActorWithPolicy` would have been one call for all three and
            // reverts on the deployed build (see its ABI doc). The commitment
            // is what joins this key to its `PolicyExecuted` history, i.e.
            // the difference between "Limited to the policy manager" — a
            // sentence identical for every gated key on the chain — and a
            // fact about THIS key.
            async let managerTask = VibenetChain.ethCall(
                to: keystore, data: VibenetABI.policyManagerCall(account, actorId: actorId))
            async let commitmentTask = VibenetChain.ethCall(
                to: keystore, data: VibenetABI.policyCommitmentCall(account, actorId: actorId))
            if let raw = await managerTask, let read = VibenetABI.addressWord(raw, at: 0),
               read.lowercased() != VibenetAuthenticatorKind.zeroAddress {
                manager = read
            }
            // A ZERO commitment is `Keystore`'s own valid "no params" (its
            // `_slicePolicy` doc says so outright), not a failed read — but it
            // can never match a `PolicyExecuted` topic for THIS key alone, so
            // carrying it would join every no-params key on the account to one
            // another's usage. Dropped rather than stored.
            if let raw = await commitmentTask, let word = VibenetABI.word(raw, at: 0),
               word.contains(where: { $0 != "0" }) {
                commitment = "0x" + word
            }
        }
        return VibenetActor(actorId: actorId, authenticator: authenticator, kind: kind,
                            scope: scope, expiry: expiry, policyManager: manager,
                            policyCommitment: commitment)
    }

    /// Every policy execution this account has made, folded per commitment —
    /// the count and the most recent time, which is the ONE live fact about a
    /// session key vibenet publishes (see `VibenetPolicyReadability` for the
    /// long form of what it deliberately does NOT publish: the spend cap, the
    /// period and the allowed recipients are committed as a hash, never
    /// stored, so there is nothing on chain to read them from).
    ///
    /// Read off `PolicyManager`, not the Keystore — a different contract, so
    /// this cannot ride the account read's own `getLogs`. Returns [] rather
    /// than nil on failure: a key's own "Never used" is spoken off its
    /// commitment being absent, and an unreachable read and a genuinely
    /// unused key are not distinguished HERE because the caller draws neither
    /// differently — the account-level `reached` flag already carries whether
    /// this pass reached the chain at all.
    static func policyUses(account: String, policyManager: String?) async -> [VibenetPolicyUse] {
        guard let policyManager else { return [] }
        guard let logs = await VibenetChain.getLogs(
            address: policyManager,
            topics: [VibenetTopics.policyExecuted, "0x" + VibenetABI.padAddress(account)])
        else { return [] }

        // commitment → (count, newest block). All three interesting fields
        // are indexed topics, so nothing here decodes `data`.
        var counts: [String: Int] = [:]
        var newestBlock: [String: Int] = [:]
        for log in logs {
            guard (log["removed"] as? Bool) != true,
                  let topics = log["topics"] as? [String], topics.count >= 4,
                  let blockHex = log["blockNumber"] as? String
            else { continue }
            let commitment = topics[3].lowercased()
            counts[commitment, default: 0] += 1
            let block = WalletIngest.hexToInt(blockHex)
            if block > (newestBlock[commitment] ?? -1) { newestBlock[commitment] = block }
        }
        guard !counts.isEmpty else { return [] }

        // ONE block-time lookup per distinct newest block — several
        // commitments can share one, and this is the same "never `.now`"
        // discipline every other dated read in this file keeps.
        var times: [Int: Date] = [:]
        for block in Set(newestBlock.values) {
            if let date = await VibenetChain.blockTime(block) { times[block] = date }
        }
        return counts.map { commitment, count in
            VibenetPolicyUse(commitment: commitment, count: count,
                             lastUsed: newestBlock[commitment].flatMap { times[$0] })
        }
        // TOTAL order so a persisted snapshot cannot differ from a fresh read
        // over an identical chain — `Dictionary` iteration order is not
        // stable across runs, and this array is `Codable` into `VibenetState`.
        .sorted { $0.commitment < $1.commitment }
    }

    /// Every account that authorized `address` as its DELEGATE — Base's own
    /// "Sub-accounts", and the direction `VibenetAccountMapping.links` cannot
    /// see (that one only relates two addresses the person ALREADY watches,
    /// which is the case needing no discovery).
    ///
    /// ONE indexed filter does the whole job, and only because of how
    /// `DelegateAuthenticator` works: it returns
    /// `actorId = ActorId.fromAddress(delegate)`, and `actorId` is
    /// `ActorAuthorized`'s second indexed topic — so pinning that topic to
    /// this address asks the node "who named you" directly. No global walk,
    /// no `data` decoding. MEASURED 2026-08-24 against a real delegate.
    ///
    /// A REVOCATION IS HONOURED: an account that later revoked the delegate
    /// must not still be listed, so the same `survivors` union the actor
    /// roster uses decides membership here too. Without it this read is
    /// append-only and would keep claiming authority that was taken away —
    /// the worst direction for a mistake on a screen about who can spend.
    static func subAccounts(delegate address: String, keystore: String) async -> [VibenetSubAccount] {
        guard let actorId = VibenetActorId.actorId(forAddress: address) else { return [] }
        guard let logs = await VibenetChain.getLogs(
            address: keystore,
            topics: [[VibenetTopics.actorAuthorized, VibenetTopics.actorRevoked], NSNull(), actorId])
        else { return [] }

        // Per delegating account, the latest event wins — `VibenetActorLog
        // .survivors`' rule, applied one level up (there the id varies and
        // the account is fixed; here the id is fixed and the account varies).
        struct Row { let authorized: Bool; let block: Int; let logIndex: Int }
        var latest: [String: Row] = [:]
        for log in logs {
            guard (log["removed"] as? Bool) != true,
                  let topics = log["topics"] as? [String], topics.count >= 3,
                  let blockHex = log["blockNumber"] as? String,
                  let indexHex = log["logIndex"] as? String
            else { continue }
            let topic0 = topics[0].lowercased()
            let authorized = topic0 == VibenetTopics.actorAuthorized
            guard authorized || topic0 == VibenetTopics.actorRevoked else { continue }
            let account = "0x" + topics[1].suffix(40)
            let row = Row(authorized: authorized, block: WalletIngest.hexToInt(blockHex),
                          logIndex: WalletIngest.hexToInt(indexHex))
            if let held = latest[account.lowercased()],
               (held.block, held.logIndex) >= (row.block, row.logIndex) { continue }
            latest[account.lowercased()] = row
        }

        let live = latest.filter(\.value.authorized)
        guard !live.isEmpty else { return [] }
        var times: [Int: Date] = [:]
        for block in Set(live.values.map(\.block)) {
            if let date = await VibenetChain.blockTime(block) { times[block] = date }
        }
        let watching = VibenetWatch.shared
        return live.map { account, row in
            VibenetSubAccount(address: account, watched: watching.isWatching(account),
                              authorizedAt: times[row.block])
        }
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
        // Balances (2026-08-24), read alongside everything above rather
        // than as a second pass over the watch list — one more `async let`
        // apiece, paced by the same `IngestSupport.boundedGather(maxConcurrent: 3)`
        // that already governs how many addresses run at once.
        async let nativeTask = VibenetChain.getBalance(address: address)
        async let usdvTask = tokenBalance(account: address, contract: contracts.usdv, symbol: "USDV")
        async let nfvTask = tokenBalance(account: address, contract: contracts.nfv, symbol: "NFV")
        // Both 2026-08-24 additions ride the same concurrent fan-out. Each is
        // ONE filtered `eth_getLogs` (plus a bounded block-time lookup), and
        // each answers a question this room could not answer at all before:
        // has a session key actually been used, and what accounts can this
        // address act for.
        async let policyUsesTask = policyUses(account: address, policyManager: contracts.policyManager)
        async let subAccountsTask = subAccounts(delegate: address, keystore: contracts.keystore)
        let events = await eventsTask
        let lockRaw = await lockTask
        let sequences = await sequencesTask
        // nil on ANY failure (no hex back, or the value doesn't parse) —
        // never a guessed zero (§83): a genuinely empty vibenet account and
        // one this read never reached must not render the same.
        let nativeBalance = (await nativeTask).flatMap { hex -> Double? in
            let d = WalletIngest.hexToDouble(hex)
            return d.isFinite ? d / 1e18 : nil
        }
        let tokenBalances = [await usdvTask, await nfvTask].compactMap { $0 }

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
                                 date: blockDates[e.block],
                                 // prd §473 — what lets one key ask the
                                 // account's history about itself. Free: the
                                 // id is already in hand and the block dates
                                 // are already resolved for the strip.
                                 actorId: e.actorId)
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
                                  changeSequences: sequences, history: history,
                                  nativeBalance: nativeBalance, tokenBalances: tokenBalances,
                                  policyUses: await policyUsesTask,
                                  subAccounts: await subAccountsTask)
    }

    /// One ERC-20-shaped balance for `account` on `contract` — nil for any
    /// of three reasons this file deliberately does NOT distinguish
    /// further (no contract named by the live config, the balance read
    /// failed, or `decimals()` couldn't be confirmed): every one of them
    /// means "no honest number to show", never "assume zero" or "assume
    /// 18 decimals" (§83, and the standing decimals lesson — see
    /// `VibenetTokenDecimals`'s own doc).
    private static func tokenBalance(account: String, contract: String?, symbol: String)
        async -> VibenetTokenBalance? {
        guard let contract else { return nil }
        async let balanceTask = VibenetChain.ethCall(to: contract, data: VibenetABI.balanceOfCall(account))
        async let decimalsTask = VibenetTokenDecimals.read(contract: contract)
        guard let balanceHex = await balanceTask, let raw = VibenetABI.rawAmountWord(balanceHex),
              let decimals = await decimalsTask
        else { return nil }
        return VibenetTokenBalance(symbol: symbol, amount: raw / pow(10, Double(decimals)))
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

/// WHICH KEYS THIS DEVICE HAS ALREADY SEEN, per account — the ledger behind
/// `VibenetKeyChanges`. `VibenetSeenCommit`'s neighbour and its exact shape,
/// for its exact reason: "have you looked at this" is a fact about this
/// device's screen, so it is UserDefaults, never a `Thing`, never synced.
///
/// The DIFFING rules — silent first sight, an unreached account contributing
/// nothing, an unwatched account dropping out — all live in
/// `VibenetKeySeenDiff` where the harness can compile them. This half is
/// storage only.
enum VibenetKeysSeen {
    private static let key = "vibenet.keys.seen.v1"

    private static func book() -> [String: Set<String>] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let raw = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return raw.mapValues(Set.init)
    }

    /// What has moved since this device last looked at these accounts. Does
    /// NOT advance — reading and marking-as-read are two acts, and the card
    /// must be able to draw the answer before it spends it.
    static func changes(in items: [VibenetAccountItem]) -> VibenetKeyChanges {
        VibenetKeySeenDiff.since(seen: book(), items: items)
    }

    /// Mark this roster as looked at.
    static func advance(_ items: [VibenetAccountItem]) {
        let next = VibenetKeySeenDiff.advanced(seen: book(), items: items)
        guard let data = try? JSONEncoder().encode(next.mapValues(Array.init)) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Disconnecting forgets it — the `VibenetState.forget` rule: a re-watch
    /// later is a first sight again, which seeds silently rather than
    /// reporting a year of key changes as news.
    static func forget() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Plant a book directly — the demo's door. NOT behind `#if DEBUG`:
    /// `demo-selftest.py`'s check A exists because `ChipMemory.seedDemo` once
    /// shipped DEBUG-only inside a file carrying none, so the demo furnished
    /// nothing in Release and every check here (all of them DEBUG) said it
    /// did. Without this the demo's key card can never draw its
    /// since-you-last-looked line, because a first sight seeds silently — by
    /// design, and correctly.
    static func seed(_ book: [String: Set<String>]) {
        guard let data = try? JSONEncoder().encode(book.mapValues(Array.init)) else { return }
        UserDefaults.standard.set(data, forKey: key)
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
        // `readAt` — stamped HERE and only here, because this is the only
        // place in the app that has genuinely just read the chain. See
        // `VibenetRoom.readAt` for the defect it closes; `vibenet-selftest.sh`
        // guards that this call site still passes it, since a room that
        // silently loses its timestamp goes back to drawing three-day-old
        // state with a confident face.
        let room = VibenetRoom.compose(items: items, branch: contracts.branch,
                                       commit: contracts.commit, configReached: true,
                                       redeployedSinceLastSeen: redeployed, readAt: .now)
        VibenetState.save(room)
        // The line the crown draws under. Recorded here, from the read that
        // already fetched the balances, so the chart is REAL on every device
        // rather than a curve the demo alone knows how to draw.
        VibenetValueStore.record(room)
        return room
    }

    /// The room's head, composed SYNCHRONOUSLY off the last saved read
    /// (R4.1) — `AltanaKeystore`'s exact shape, and for its exact reason:
    /// `FeedScreen.sourceHead` runs on every draw, and this room's subject
    /// is chain state, so composing it live would spend an `eth_call` per
    /// scroll. Nil until a read has ever completed, which is the honest
    /// answer — a head that invented a state it had not read would be the
    /// §83 fake status on the one card whose whole job is saying what the
    /// chain says.
    @MainActor
    static func card() -> VibenetRoom? {
        if DemoMode.isActive { return VibenetRoom.demoFixture() }
        guard let room = VibenetState.saved, !room.items.isEmpty else { return nil }
        return room
    }
}

/// The last composed room, kept so the feed's head can draw without
/// reaching the chain (R4.1). Flat `Codable` in UserDefaults — the
/// `AltanaState`/`X402State` shape, not a `Thing`: this is a snapshot of
/// state that changes constantly, exactly what this file's own header
/// says must never become a corpus row.
enum VibenetState {
    private static let key = "vibenet.room.snapshot.v1"

    static var saved: VibenetRoom? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(VibenetRoom.self, from: data)
    }

    static func save(_ room: VibenetRoom) {
        guard let data = try? JSONEncoder().encode(room) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Disconnecting forgets the snapshot too — otherwise the head keeps
    /// drawing accounts that are no longer watched.
    static func forget() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Where the room's balance history lives — one series for the ROOM, not one
/// per account, because the crown it draws under is the room's own total.
///
/// UserDefaults, like every other small vibenet store here. The samples are
/// tiny (a date and a double, capped at `VibenetValueHistory.cap`) and they
/// are a reading of a devnet that redeploys, so nothing here is worth a
/// CloudKit-mirrored `Thing` field — the same reasoning that keeps the room
/// itself out of the corpus.
enum VibenetValueStore {
    private static let key = "vibenet.value.history.v1"

    static func samples() -> [VibenetValueSample] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let out = try? JSONDecoder().decode([VibenetValueSample].self, from: data)
        else { return [] }
        return out
    }

    /// Called on every composed read; usually writes nothing, because
    /// `VibenetValueHistory.appending` throttles to one point every four
    /// hours. A room with no native reading at all records NOTHING rather
    /// than a zero — a zero here would draw a real cliff on the chart.
    static func record(_ room: VibenetRoom, now: Date = .now) {
        if let native = VibenetBalanceAggregation.compose(room.items)?.nativeTotal,
           let out = VibenetValueHistory.appending(samples(), native: native, now: now),
           let data = try? JSONEncoder().encode(out) {
            UserDefaults.standard.set(data, forKey: key)
        }
        recordAccounts(room, now: now)
    }

    static func replace(_ samples: [VibenetValueSample]) {
        if let data = try? JSONEncoder().encode(samples) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: - Per-account history (2026-08-24)

    /// **A SCOPED ROOM NEEDS ITS OWN CURVE, and must never borrow the
    /// aggregate's.** Picking one account narrows every other reading on the
    /// card to that account, so a line drawn from the room-wide series would
    /// be the one element still describing all five — a chart claiming this
    /// account rose 38% because the total did. That is §83 on the screen where
    /// it is least visible, since a plausible curve under a correct balance
    /// looks exactly like a correct curve.
    ///
    /// Keyed by LOWERCASED address, for the reason every comparison in this
    /// bridge is case-insensitive: an RPC's hex casing is not a promise, and a
    /// re-cased address would silently start a second history for one account.
    private static let accountsKey = "vibenet.value.history.accounts.v1"

    static func accountSamples() -> [String: [VibenetValueSample]] {
        guard let data = UserDefaults.standard.data(forKey: accountsKey),
              let out = try? JSONDecoder().decode([String: [VibenetValueSample]].self, from: data)
        else { return [:] }
        return out
    }

    static func samples(for address: String) -> [VibenetValueSample] {
        accountSamples()[address.lowercased()] ?? []
    }

    /// One reading per account per pass, each throttled on its OWN history —
    /// an account watched today starts building its curve today rather than
    /// inheriting the interval of one watched last week.
    static func recordAccounts(_ room: VibenetRoom, now: Date = .now) {
        var book = accountSamples()
        var changed = false
        for item in room.items {
            guard let native = item.nativeBalance else { continue }
            let key = item.address.lowercased()
            guard let out = VibenetValueHistory.appending(book[key] ?? [], native: native, now: now)
            else { continue }
            book[key] = out
            changed = true
        }
        guard changed, let data = try? JSONEncoder().encode(book) else { return }
        UserDefaults.standard.set(data, forKey: accountsKey)
    }

    static func replaceAccounts(_ book: [String: [VibenetValueSample]]) {
        if let data = try? JSONEncoder().encode(book) {
            UserDefaults.standard.set(data, forKey: accountsKey)
        }
    }

    static func forget() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: accountsKey)
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

    /// Base's own EIP-8130 account console — MEASURED 2026-08-24 by driving
    /// it: it creates accounts (smart or EOA-delegating), mints K1/P-256/
    /// passkey keys, composes transactions, and demonstrates the two app
    /// shapes this room reads — a "Monthly Vibes" SUBSCRIPTION (a capped
    /// session key) and a "Spending Account" (a sub-account).
    ///
    /// It is the door for everything this app deliberately does not do. The
    /// keys that console mints live in the browser, and reading a devnet
    /// needs none of them; a write path here would mean this app holding a
    /// signing key for a chain whose whole point is that nothing on it is
    /// worth anything.
    static let console = "https://chain.base.org/demos/account"
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
        // The ROWS, not just their refs (2026-08-25, prd §468): an event
        // already in the corpus dedupes out of the landing path, and the
        // social-bridge rule is that a bridge heals on the dedupe hit — which
        // is the only way the §308 facet tags below can ever reach an event
        // landed by an earlier build. `refSegment` is "actor" for BOTH an
        // authorize and a revoke, so the tags cannot be re-derived from a
        // stored ref; they have to come from the log, which this pass is
        // already reading. Bounded by the walk, and stated as such: an event
        // older than `VibenetLogChunking`'s reach is never revisited.
        let byRef = IngestSupport.thingsByRef(context, source: VibenetIdentity.source)

        var landed = 0
        for address in addresses {
            landed += await landAccount(address, contracts: contracts, context: context, existing: byRef)
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
        let carriesActor = (kind != .locked && kind != .unlockInitiated)
        let actorId = carriesActor ? (topics.count >= 3 ? topics[2].lowercased() : nil) : nil
        if carriesActor && actorId == nil { return nil }
        return RawEvent(kind: kind, actorId: actorId, txHash: txHash,
                        logIndex: WalletIngest.hexToInt(indexHex), block: WalletIngest.hexToInt(blockHex))
    }

    private static func ref(_ e: RawEvent) -> String {
        "vibenet:\(e.kind.refSegment):\(e.txHash):\(e.logIndex)"
    }

    @MainActor
    private static func landAccount(_ address: String, contracts: VibenetContracts,
                                    context: ModelContext, existing: [String: Thing]) async -> Int {
        let ownerTopic = "0x" + VibenetABI.padAddress(address)
        async let actorLogsTask = VibenetChain.getLogs(
            address: contracts.keystore,
            topics: [[VibenetTopics.actorAuthorized, VibenetTopics.actorRevoked], ownerTopic])
        // Both lock-family topics in ONE filtered read, the OR-topic0 shape
        // the actor read above already uses — a second `getLogs` per account
        // per pass would double this bridge's request count to land an event
        // that arrives on the same contract with the same owner topic.
        async let lockLogsTask = VibenetChain.getLogs(
            address: contracts.keystore,
            topics: [[VibenetTopics.accountLocked, VibenetTopics.accountUnlockInitiated], ownerTopic])
        // THE OPTIONAL IS KEPT rather than collapsed with `?? []` at the
        // await: `VibenetChain.getLogs` answers nil when its NEWEST chunk
        // fails, and the deadline sweep below must be able to tell "this
        // account revoked nothing" from "we could not read this account".
        // See `VibenetDeadlineSweep.maySweep`.
        let actorLogsRead = await actorLogsTask
        let actorLogs = actorLogsRead ?? []
        let lockLogs = await lockLogsTask ?? []

        var events: [RawEvent] = []
        for log in actorLogs {
            guard let topics = log["topics"] as? [String], let topic0 = topics.first?.lowercased() else { continue }
            let kind: VibenetEventKind = topic0 == VibenetTopics.actorAuthorized ? .actorAuthorized : .actorRevoked
            if let e = parse(log, kind: kind) { events.append(e) }
        }
        for log in lockLogs {
            guard let topics = log["topics"] as? [String], let topic0 = topics.first?.lowercased() else { continue }
            let kind: VibenetEventKind = topic0 == VibenetTopics.accountUnlockInitiated
                ? .unlockInitiated : .locked
            if let e = parse(log, kind: kind) { events.append(e) }
        }
        // HEAL ON THE DEDUPE HIT, before the fresh split — the facet tags
        // (prd §468) are the whole reason, and an event landed by an earlier
        // build has no other route to them. `isLive` guarded because a row can
        // be deleted under an async pass (corollary 6); only ever ADDS a
        // missing tag, so a tag somebody's own edit removed is not re-forced.
        for event in events {
            guard let thing = existing[ref(event)], thing.isLive else { continue }
            let wanted = event.kind.facetTags
            let missing = wanted.filter { !thing.tags.contains($0) }
            if !missing.isEmpty { thing.tags.append(contentsOf: missing) }
        }

        // A REVOKED KEY LOSES ITS DEADLINE (2026-08-25, prd §473).
        //
        // Runs BEFORE the `fresh` early-return, and that placement is the
        // whole of whether this works: on almost every pass there is no new
        // event to land, and a revocation that arrived weeks ago is precisely
        // the case this exists for — behind the return it would only ever fire
        // on a pass that happened to be landing something else.
        //
        // Clears the field and nothing else. The authorization row STAYS: it
        // is a true record of a real moment, and a key having been authorized
        // is not made untrue by its later revocation — what stops being true
        // is that something is coming up.
        let actorEvents = events.compactMap { e -> VibenetActorEvent? in
            guard let actorId = e.actorId,
                  e.kind == .actorAuthorized || e.kind == .actorRevoked else { return nil }
            return VibenetActorEvent(actorId: actorId, authorized: e.kind == .actorAuthorized,
                                     block: e.block, logIndex: e.logIndex)
        }
        if VibenetDeadlineSweep.maySweep(logsAnswered: actorLogsRead != nil, events: actorEvents) {
            let dead = VibenetDeadlineSweep.revoked(actorEvents)
            for event in events where event.kind == .actorAuthorized {
                guard let actorId = event.actorId, dead.contains(actorId),
                      let thing = existing[ref(event)], thing.isLive,
                      thing.dueAt != nil
                else { continue }
                thing.dueAt = nil
            }
        }

        let fresh = events.filter { existing[ref($0)] == nil }
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
            var expiresAt: Date?
            /// prd §468 — the one vibenet event worth the lock screen. See the
            /// tag's use in `NotifySweep.classify`.
            var isAdminKey = false
            if event.kind == .actorAuthorized, let actorId = event.actorId,
               let actor = await VibenetRead.actor(account: address, keystore: contracts.keystore,
                                                    actorId: actorId, known: known) {
                keyLabel = actor.kind.label
                // EIP-8130's scope 0 is UNRESTRICTED (prd §463) — a key that
                // can do everything, including the reserved things this build
                // cannot name. Read here, at landing, from the same live
                // re-read that resolves the kind, because the scope is not
                // recoverable from the row afterwards.
                isAdminKey = actor.scope.isAdmin
                // A KEY THAT EXPIRES IS A DEADLINE, so it lands as one —
                // and that is the whole of the work. `NotifySweep` already
                // scans the live corpus for any row whose `dueAt` is near
                // and plans a `deadlineNear` for it, so an expiring session
                // key reaches the lock screen with no `NotifyKind` of this
                // bridge's own, no new notification code, and none of
                // `notify-selftest.sh`'s 79 assertions re-proved. The same
                // reasoning App Store Connect's build expiries already ride.
                //
                // `expiry == 0` is Keystore's own "never", never a date.
                if actor.expiry > 0 {
                    expiresAt = Date(timeIntervalSince1970: TimeInterval(actor.expiry))
                }
            }
            let thing = Thing(
                // `.event`, NOT `.transaction`, and the difference is a
                // false claim this shipped with: every `.transaction`
                // thing is routed through `MoneyReceiptSource` (whose
                // whole gate is `kind == .transaction`), which for a row
                // carrying no stamped amount falls through to
                // `MoneyReceipt.generic` and draws a money receipt reading
                // "In your wallet". Both halves were untrue — a key
                // authorization moves no money, and a watched devnet
                // address is not the person's wallet. A key added or
                // revoked at a known block time is exactly what `.event`
                // means: a moment with a clock.
                kind: .event,
                title: event.kind.title(shortAddress: shortAddress, keyLabel: keyLabel),
                content: VibenetExplorer.tx(event.txHash),
                source: VibenetIdentity.source,
                capturedAt: times[event.block] ?? .now,
                sourceRef: ref(event))
            // NO `walletAddress` — it was write-only here (nothing in this
            // feature ever read it back) and it is the field that told the
            // receipt this devnet account was yours.
            //
            // `authorHandle` IS stamped (R4.2): the room's rows lead with
            // the account's face and name, and the only other way to know
            // which account a row belongs to would be parsing the address
            // back out of the display title — the exact thing
            // `MoneyReceiptSource`'s own doc forbids. An existing,
            // already-deployed field, so no CloudKit deploy.
            thing.authorHandle = address
            // The same event WITHOUT the address (R4.2) — what the room's
            // row says once its face and name have said who. Stored
            // rather than derived: recovering it would mean parsing the
            // address back out of a localized display title, the exact
            // thing `MoneyReceiptSource`'s own doc forbids. `summary` is
            // display copy this bridge has never used, already deployed.
            thing.summary = event.kind.phrase(keyLabel: keyLabel)
            // The §308 facets — an existing, already-deployed field, so no
            // CloudKit deploy. See `VibenetEventKind.facetTags` for why a
            // revoke carries two and a lock carries none.
            thing.tags = event.kind.facetTags
            // "Admin key" — a MECHANICAL tag, not a facet: it is stamped by
            // one bridge for one state and nobody would type it as a search.
            // It is the whole of what makes this row reach the lock screen,
            // and it is a tag rather than a ref segment because changing the
            // ref would re-land every event already in every corpus.
            if isAdminKey { thing.tags.append("Admin key") }
            // An existing, already-deployed field — no CloudKit deploy. Nil
            // for every other event kind and for a key that never expires,
            // so nothing here invents a clock a key does not have.
            thing.dueAt = expiresAt
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
