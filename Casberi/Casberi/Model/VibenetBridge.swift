import Foundation
import Observation
import SwiftData

/// Base "vibenet" (2026-08-23) — an experimental, EPHEMERAL devnet testing
/// EIP-8130 native account abstraction. Chain id 84538453, keyless RPC at
/// `rpc.vibes.base.org`. Genuinely read-only in every sense, and the sentence
/// that used to say why has been narrowed rather than deleted (2026-08-29):
/// there IS a key of this app's own now — `VibenetDeviceKey` makes one in this
/// phone's Secure Enclave (prd §522) — and it has never touched this chain.
/// `VibenetDeviceKey.sign` has no caller, so no signature exists to send, and
/// nothing this file does can write to the chain. That pairing is the claim,
/// not "there is no key", and `vibenet-selftest.sh` ties it to the three
/// sentences the app SHOWS a person: the catalog bullet, the `canLine` below,
/// and the reach registry's purpose. A signing path may not appear without
/// those three moving in the same commit. It reads a watched account's account-abstraction
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
    /// THE TOKENS THIS CONFIG NAMES (prd §507).
    ///
    /// **`vibecheck` IS NOT ONE, and that is measured rather than assumed
    /// (2026-08-28, against the live devnet).** It was carried through the
    /// parse unread from the day this seat shipped, and the obvious use for
    /// an address beside `usdv` and `nfv` is a third balance — so it was
    /// tried, and the chain answered: `decimals()` REVERTS, ERC-165
    /// `supportsInterface(0x80ac58cd)` REVERTS, and `symbol()` REVERTS, over a
    /// contract that does have 1,236 bytes of code. It is a real contract of
    /// some other kind, and reading it as a token buys two failing `eth_call`s
    /// per pass forever (a revert is not cached — only a positive answer is)
    /// in exchange for nothing.
    ///
    /// Left in the parse, still unread, for the reason it was left there
    /// before: a future read of it does not have to re-touch the parse. What
    /// changed is that the question has an ANSWER now, in the ledger and in
    /// `-vibenetLedgerProbe`, instead of an open field nobody had asked.
    ///
    /// USDV is the fungible one (`decimals()` = **6**, measured — not 18, the
    /// standing lesson) and NFV is an **ERC-721** (`decimals()` reverts,
    /// ERC-165 answers true), which is the bug `VibenetTokenFacts` exists for.
    ///
    /// `defaultAccount` and `canonicalHighRatePayerAccount` are the other
    /// unread fields and they are NOT tokens either — they are reference
    /// accounts, and `VibenetDiscovery.reference` is where they land.
    var tokenContracts: [(address: String, symbol: String?)] {
        var out: [(address: String, symbol: String?)] = []
        if let usdv, !usdv.isEmpty { out.append((usdv, "USDV")) }
        if let nfv, !nfv.isEmpty { out.append((nfv, "NFV")) }
        return out
    }

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

    /// The cached contracts — MEMOISED IN PROCESS (2026-08-25, prd §477).
    ///
    /// Every call was a `UserDefaults` read plus a `JSONDecoder` pass, and the
    /// callers are in view bodies: `VibenetAccountDetail.knownManagers` is a
    /// COMPUTED static reached from `termRows`, which runs once per key row —
    /// so an account with eight keys decoded this config eight times per body
    /// pass, on every scroll frame. That is the account page's jitter, and it
    /// survived §476's fix because that one hoisted a different store in a
    /// different file.
    ///
    /// A cache of a cache, which is why memoising is safe rather than clever:
    /// the only writers are `store` and `forgetCache`, both of which drop the
    /// memo, so it cannot go stale behind a fetch. Not `@MainActor`-isolated
    /// because `cached()` never was — the memo is written only through those
    /// two paths and the decoded value is a `let`-only struct.
    private nonisolated(unsafe) static var memo: VibenetContracts?
    private nonisolated(unsafe) static var memoLoaded = false

    static func cached() -> VibenetContracts? {
        if memoLoaded { return memo }
        memoLoaded = true
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else {
            memo = nil
            return nil
        }
        memo = try? JSONDecoder().decode(VibenetContracts.self, from: data)
        return memo
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
        memo = nil
        memoLoaded = false
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: fetchedAtKey)
    }

    private static func store(_ contracts: VibenetContracts) {
        guard let data = try? JSONEncoder().encode(contracts) else { return }
        // The memo goes with it, or a fetch lands and every view keeps reading
        // the config it replaced.
        memo = contracts
        memoLoaded = true
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

    /// The nickname for an address, or nil when none was set — the row
    /// falls back to the short hex form exactly as before.
    ///
    /// **Delegates to `AddressBook` (2026-08-27, the address-book
    /// unification).** Names used to live in a device-local dictionary here
    /// (`vibenet.watch.names.v1`, never iCloud-synced, forgotten on
    /// disconnect) — the exact split `AddressBook`'s own header calls out as
    /// the reason it exists at all. One vibenet account is one book entry
    /// now, same as any mainnet wallet; every call site above keeps calling
    /// this exact method and sees no difference except that the name now
    /// survives a disconnect and reaches a second device.
    func name(for address: String) -> String? {
        AddressBook.shared.name(for: address)
    }

    /// An empty/whitespace-only string CLEARS the name rather than storing
    /// it — there is no separate "remove name" action, so the same text
    /// field that sets a name is the one that unsets it. (Clearing the name
    /// on an entry the book knows about also drops its kind/provenance/note —
    /// the same "an empty name is how you leave the book" contract the
    /// wallet side already carries; see `AddressBook.setName`.)
    func setName(_ raw: String, for address: String) {
        AddressBook.shared.setName(raw, for: address, networks: [AddressBook.Network.vibenet])
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
        // Watching implies the book holds it (2026-08-27) — the same
        // invariant `AddressBook.addToGroup` enforces for groups, one door
        // over. A short-form name so a freshly-watched account is findable
        // in the book immediately, exactly the fallback `WalletStore.add`
        // uses on the mainnet side.
        let book = AddressBook.shared
        if book.entry(for: address) == nil {
            book.setName(WalletStore.shortAddress(address), for: address,
                        networks: [AddressBook.Network.vibenet])
        } else {
            book.addNetwork(AddressBook.Network.vibenet, for: address)
        }
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
    func remove(_ address: String) {
        addressList.removeAll { $0.caseInsensitiveCompare(address) == .orderedSame }
    }

    /// Stop watching every account. **No longer touches names (2026-08-27,
    /// the address-book unification, amending §472's own copy).** Names live
    /// in `AddressBook` now, the one ledger that outlives every watch — the
    /// exact doctrine that file's header states as the reason it exists —
    /// so disconnecting the vibenet seat is no different from unwatching a
    /// mainnet wallet: the chip leaves the strip, the names stay in the
    /// Address Book. `VibenetAddressBookScreen`'s last-account confirm copy
    /// was rewritten to say so.
    func removeAll() {
        addressList = []
    }

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
                String(localized: "Reads which keys can act for a watched address — and whether it's locked — on Base's vibenet devnet, where native account abstraction (EIP-8130) is being tested."),
                String(localized: "Reading needs no key. Making an account signs with a key held in this phone's Secure Enclave — it never leaves, and it asks for Face ID every time."),
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
        // And the backfill's own ledger (prd §507) — a re-watch is a first
        // sight there too, and its whole promise is "paid once per account,
        // ever" against a history store that has just been dropped.
        VibenetBackfill.forget()
        store.remove(VibenetIdentity.seatID)
    }
}

// MARK: - RPC (keyless)

/// The one measured RPC host — `WalletApprovals`'s pattern of a small chain
/// table, shrunk to a single chain that isn't in that file's own table
/// (vibenet isn't a `WalletChainStore` network; a person's wallet holdings
/// have nothing to do with a devnet test account).
/// The chain tip, memoised for a few seconds (prd §507).
///
/// An `actor` rather than a `nonisolated(unsafe) static` like
/// `VibenetConfig.memo`, and the difference is real: that one is written only
/// through two paths on one thread, while this is read by
/// `IngestSupport.boundedGather`'s concurrent per-account reads by
/// construction — the whole reason it saves anything.
actor VibenetTipCache {
    static let shared = VibenetTipCache()
    /// SHORT, and short for a stated reason: the tip is used to place the
    /// NEWEST end of every log walk, so staleness costs coverage of the
    /// present, which is the half every caller most needs. Seconds, not
    /// minutes.
    static let ttl: TimeInterval = 15

    private var tip: Int?
    private var at: Date?

    func current(now: Date = .now) -> Int? {
        guard let tip, let at, now.timeIntervalSince(at) < Self.ttl else { return nil }
        return tip
    }

    func store(_ value: Int, now: Date = .now) {
        tip = value
        at = now
    }

    /// Dropped when the room is disconnected or a pull-to-refresh asks for a
    /// genuinely fresh read — a cache nobody can invalidate is a cache that
    /// makes "refresh" a lie.
    func forget() {
        tip = nil
        at = nil
    }
}

enum VibenetChain {
    static let network = "vibenet"
    /// **RETIRED AS A LITERAL (prd §515a).** It read `84_538_453`, nothing
    /// ever used it, and by 2026-08-29 the devnet had reset past it to
    /// `84_542_549` — a stale fact nobody could notice because nobody asked
    /// it. `chainIdentifier()` reads it live; this is the value this device
    /// first shipped knowing, kept only so the reset ledger has a floor to
    /// describe and never as an assertion about the chain now.
    static let firstKnownChainID = 84_538_453
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

    /// WHY A REVERT AND A SILENCE ARE TWO ANSWERS (prd §515a).
    ///
    /// `call` maps both a transport failure and a JSON-RPC `error` object to
    /// nil, which is right for every caller that only wants the value — and
    /// is how the 2026-08-29 outage stayed invisible for a day. The Keystore
    /// had dropped `isContractEstablished`, so every `eth_call` came back
    /// `execution reverted`, and the room reported *"Couldn't reach the
    /// chain"* over a devnet that was answering every single request.
    ///
    /// Nothing on the read path is gated on this any more (see
    /// `VibenetDeployment`) — it exists so `-vibenetProbe` can tell the two
    /// apart in one launch, which is the diagnostic that would have named
    /// that bug the moment it landed instead of a day later.
    enum CallOutcome: Equatable {
        case value(String)
        /// The node answered, and the answer was a revert — the contract
        /// does not have this method, or refused it.
        case reverted(String?)
        /// No usable answer at all.
        case unreachable
    }

    static func ethCallOutcome(to: String, data: String) async -> CallOutcome {
        let body: [String: Any] = ["id": 1, "jsonrpc": "2.0", "method": "eth_call",
                                   "params": [["to": to, "data": data], "latest"]]
        guard let root = await IngestSupport.postJSON(rpc, body: body) as? [String: Any] else {
            return .unreachable
        }
        if let hex = root["result"] as? String { return .value(hex) }
        if let error = root["error"] as? [String: Any] {
            return .reverted(error["message"] as? String)
        }
        return .unreachable
    }

    /// An address's deployed code — the reachability gate (prd §515a).
    ///
    /// Plain JSON-RPC, deliberately: `eth_getCode` belongs to the node, not
    /// to any contract, so no redeploy can take it away. That is the whole
    /// reason it replaced a Keystore view method here; see
    /// `VibenetDeployment` for the measurement.
    static func getCode(address: String) async -> String? {
        await call(method: "eth_getCode", params: [address, "latest"]) as? String
    }

    /// The chain's own identifier, read rather than assumed (prd §515a).
    ///
    /// It was a literal — `84_538_453` — and by 2026-08-29 it was wrong:
    /// vibenet had reset and stepped to `84_542_549`. Nothing read the
    /// constant, so nothing broke and nothing said so, which is exactly the
    /// shape of fact this file's header warns about. Now it is a live read,
    /// and the step between the two IS the reset signal.
    static func chainIdentifier() async -> Int? {
        guard let hex = await call(method: "eth_chainId", params: []) as? String else { return nil }
        let n = WalletIngest.hexToInt(hex)
        return n > 0 ? n : nil
    }

    static func blockNumber() async -> Int? {
        guard let hex = await call(method: "eth_blockNumber", params: []) as? String else { return nil }
        let n = WalletIngest.hexToInt(hex)
        return n >= 0 ? n : nil
    }

    /// The tip, at most once every `VibenetTipCache.ttl` (prd §507).
    ///
    /// **This is a saving, not an addition.** `getLogs` has asked
    /// `eth_blockNumber` on every single call since it learned to chunk, and
    /// one composed read makes four such calls PER ACCOUNT — so a five-account
    /// room spent twenty round trips re-asking a number that cannot have
    /// moved meaningfully between them, and this pass adds two more log reads
    /// per account on top. A few seconds of staleness costs a chunk boundary
    /// nothing: the walk starts at the tip and reaches backward, so a tip a
    /// block or two old simply reads one block less of the present, and the
    /// next pass catches it.
    static func cachedTip() async -> Int? {
        if let held = await VibenetTipCache.shared.current() { return held }
        guard let tip = await blockNumber() else { return nil }
        await VibenetTipCache.shared.store(tip)
        return tip
    }

    /// THE CHAIN'S OWN PULSE (prd §507) — three calls, once per composed read,
    /// for the fact this room could not state: is this devnet still alive.
    ///
    /// The rate is MEASURED across a real span of this chain's own blocks
    /// rather than assumed, because `VibenetChainPulse`'s verdict thresholds
    /// are multiples of it and a guessed rate moves them with it. A span too
    /// short to measure yields a nil rate, which falls back to that type's own
    /// absolute floors — not to a made-up number.
    static let pulseSpan = 500

    static func pulse() async -> VibenetChainPulse? {
        guard let tip = await cachedTip() else { return nil }
        async let tipTimeTask = blockTime(tip)
        async let backTimeTask = tip > pulseSpan ? blockTime(tip - pulseSpan) : nil
        let tipTime = await tipTimeTask
        let backTime = await backTimeTask
        var rate: Double?
        if let tipTime, let backTime {
            let seconds = tipTime.timeIntervalSince(backTime)
            // A non-positive span is a node disagreeing with itself; report no
            // rate rather than a negative one, which would make every verdict
            // threshold collapse to its floor without saying why.
            if seconds > 0 { rate = seconds / Double(pulseSpan) }
        }
        return VibenetChainPulse(tip: tip, lastBlockAt: tipTime, secondsPerBlock: rate)
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

    /// The same balance AT A PAST BLOCK (prd §507) — what lets the native
    /// curve start before the day this app was installed.
    ///
    /// `eth_getBalance` takes a block tag, so a node that keeps state can
    /// answer what an account held last week. A PRUNED node cannot, and says
    /// so by erroring — which arrives here as nil and is recorded as nothing,
    /// never as a zero: a zero would draw a real cliff on the chart, the
    /// failure `VibenetValueStore.record` already refuses one line up.
    static func getBalance(address: String, atBlock block: Int) async -> String? {
        guard block >= 0 else { return nil }
        return await call(method: "eth_getBalance",
                          params: [address, "0x" + String(block, radix: 16)]) as? String
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
    static func getLogs(address: String, topics: [Any],
                        maxChunks: Int = maxLogChunks) async -> [[String: Any]]? {
        guard let tip = await cachedTip() else { return nil }
        let ranges = VibenetLogChunking.ranges(tip: tip, maxRange: maxLogRange, maxChunks: maxChunks)
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
    /// `Transfer(address indexed from, address indexed to, uint256 value)` —
    /// the ERC-20 topic, and byte-identical to ERC-721's
    /// `Transfer(address,address,uint256)` because the two signatures ARE the
    /// same string. That collision is the whole reason `VibenetRead.transfers`
    /// decides on the TOPIC COUNT rather than on the contract: three topics is
    /// a fungible amount in `data`, four is an indexed token id and no data at
    /// all, and a decoder that assumes one reads the other as a transfer of
    /// zero.
    ///
    /// Not keccak-derived here like the Keystore's five: this is the most
    /// widely deployed event signature on any EVM chain and its hash is a
    /// constant every explorer, indexer and wallet in existence pins. The
    /// harness re-derives it anyway, for the same reason it re-derives the
    /// others.
    static let erc20Transfer = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
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

    /// **`isContractEstablished(address)` — 0x28a4c4cb — IS GONE, and this
    /// note is the point of the comment (prd §515a).**
    ///
    /// It was the first call of every account read and the gate `reached`
    /// hung on. On 2026-08-29 the Keystore redeployed (config `_commit`
    /// a9ae95e1b → 3a23204ca) WITHOUT it: the selector appears nowhere in
    /// the new 10,420-byte runtime, and `eth_call` answers
    /// `execution reverted` for every address — including the config's own
    /// `DefaultAccount` and four accounts that Keystore's own logs show as
    /// authorized. The whole seat read "Couldn't reach the chain".
    ///
    /// It is DELETED rather than kept as a fallback, for `vibecheck`'s own
    /// reason (prd §507): a call that reverts for every address buys one
    /// failing round trip per account per pass, forever, in exchange for
    /// nothing. `VibenetDeployment` is what replaced it.
    ///
    /// Do not restore it without measuring it against the live devnet first.

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

    /// `supportsInterface(bytes4)` — 0x01ffc9a7, ERC-165 (prd §507). The
    /// argument is a `bytes4`, which ABI-encodes LEFT-aligned in its word —
    /// the opposite of every other value this file pads, and padding it the
    /// usual way asks about interface `0x00000000`, which every compliant
    /// contract answers false to. That would read as "not an NFT" for every
    /// NFT on the chain.
    static func supportsInterfaceCall(_ interfaceID: String) -> String {
        var id = interfaceID.lowercased()
        if id.hasPrefix("0x") { id.removeFirst(2) }
        guard id.count == 8 else { return "0x01ffc9a7" + String(repeating: "0", count: 64) }
        return "0x01ffc9a7" + id + String(repeating: "0", count: 56)
    }

    /// ERC-721's own interface id, from the standard itself.
    static let erc721InterfaceID = "80ac58cd"

    /// `symbol()` — 0x95d89b41, no arguments. Read only for a token the live
    /// config named but did not name a symbol FOR (`vibecheck`); USDV and NFV
    /// take their symbol from the config's own field naming, which is free.
    static let symbolCall = "0x95d89b41"

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
/// What a token IS, cached forever per contract (prd §507).
///
/// **The bug this fixes is silent and shipped**: `tokenBalance` gave up on any
/// token whose `decimals()` did not answer, which is the right refusal for an
/// unknown scale and the wrong one for an ERC-721 — where `decimals()` does
/// not exist, reverts, and means "this is a count". The demo fixture has shown
/// `NFV: 12` since the day balances landed, while a live NFV that is a 721
/// would have been absent from the room forever with nothing anywhere saying
/// why.
///
/// Asked in ORDER and never both at once: `decimals()` first because most
/// tokens are fungible and one answer ends the question, ERC-165 only when it
/// fails. A contract that answers neither is still dropped — "we could not
/// learn the scale" stays a real state, and assuming one is the lesson this
/// codebase has paid for in Solana SPL and in Gnosis Pay's USDCe.
enum VibenetTokenFacts {
    struct Facts: Equatable {
        let identity: VibenetTokenIdentity
        /// Nil for a collectible, which has no scale by definition.
        let decimals: Int?
    }

    private static func key(_ contract: String) -> String {
        "vibenet.tokenkind.\(contract.lowercased())"
    }

    static func read(contract: String) async -> Facts? {
        if let decimals = await VibenetTokenDecimals.read(contract: contract) {
            return Facts(identity: .fungible, decimals: decimals)
        }
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: key(contract)) {
            return Facts(identity: .collectible, decimals: nil)
        }
        guard let hex = await VibenetChain.ethCall(
            to: contract, data: VibenetABI.supportsInterfaceCall(VibenetABI.erc721InterfaceID)),
              VibenetABI.boolWord(hex, at: 0)
        else { return nil }
        defaults.set(true, forKey: key(contract))
        return Facts(identity: .collectible, decimals: nil)
    }

    static func forget(contract: String) {
        UserDefaults.standard.removeObject(forKey: key(contract))
    }
}

/// A token's own `symbol()`, sanitised (prd §507).
///
/// Read ONLY for a contract the live config named without naming a symbol for
/// it — `vibecheck`, which had been parsed and never read at all. USDV and NFV
/// keep taking their symbol from the config's field naming, which costs
/// nothing and cannot be spoofed.
///
/// **SANITISED, not merely trimmed**, and for the `SmartAccount.vendor`
/// reason: this string is returned by an arbitrary contract on a devnet
/// anybody can deploy to, and it lands in the app's own chrome beside a
/// number. Letters and digits only, 1–12 characters, uppercased; anything
/// else yields nil and the balance is simply not shown, because a holding we
/// cannot name is one we cannot honestly draw.
enum VibenetTokenSymbol {
    private static func key(_ contract: String) -> String {
        "vibenet.tokensymbol.\(contract.lowercased())"
    }

    static func sanitize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{0}"))
        guard (1...12).contains(trimmed.count),
              trimmed.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return trimmed.uppercased()
    }

    /// Hex bytes → text, for both shapes a `symbol()` can return: the modern
    /// dynamic `string` and the old fixed `bytes32` several long-lived tokens
    /// still use. Nil rather than mojibake for anything that is not UTF-8.
    static func decode(_ hex: String) -> String? {
        var payload = VibenetLogData.dynamicBytes(hex)
        if payload == nil, let word = VibenetABI.word(hex, at: 0) { payload = "0x" + word }
        guard var body = payload else { return nil }
        if body.hasPrefix("0x") { body.removeFirst(2) }
        var bytes: [UInt8] = []
        var index = body.startIndex
        while index < body.endIndex {
            let next = body.index(index, offsetBy: 2, limitedBy: body.endIndex) ?? body.endIndex
            guard next > index, let byte = UInt8(body[index..<next], radix: 16) else { return nil }
            if byte != 0 { bytes.append(byte) }
            index = next
        }
        guard !bytes.isEmpty, let text = String(bytes: bytes, encoding: .utf8) else { return nil }
        return sanitize(text)
    }

    static func read(contract: String) async -> String? {
        let defaults = UserDefaults.standard
        if let held = defaults.string(forKey: key(contract)) { return held }
        guard let hex = await VibenetChain.ethCall(to: contract, data: VibenetABI.symbolCall),
              let symbol = decode(hex) else { return nil }
        defaults.set(symbol, forKey: key(contract))
        return symbol
    }
}

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

    /// EVERY POLICY EXECUTION, KEPT WHOLE (prd §507, was `policyUses` since
    /// 2026-08-24).
    ///
    /// The read is unchanged — one filtered `eth_getLogs` on `PolicyManager`,
    /// every field it needs indexed — and what changed is that it no longer
    /// throws the individual runs away. Folding straight to a count meant a
    /// session key running every day produced a number on one line inside one
    /// sheet and no row anywhere, on a screen called Activity. The fold still
    /// happens (`VibenetPolicyRuns.fold`, pure and harness-tested) — it just
    /// happens after the runs have been kept.
    ///
    /// `caller` is the log's own NON-INDEXED word, which nothing decoded: it
    /// is the difference between "4 uses" and "used by the account you also
    /// watch". See `VibenetPolicyReadability` for the long form of what this
    /// event deliberately does NOT publish — the cap, the period and the
    /// allowed recipients are committed as a hash and are not on chain to
    /// read.
    ///
    /// Returns [] rather than nil on failure, as it always has: a key's own
    /// "Never used" is spoken off its commitment being absent, and the
    /// account-level `reached` flag already carries whether this pass got to
    /// the chain at all.
    static func policyRuns(account: String, policyManager: String?) async
        -> (runs: [VibenetPolicyRun], uses: [VibenetPolicyUse]) {
        guard let policyManager else { return ([], []) }
        guard let logs = await VibenetChain.getLogs(
            address: policyManager,
            topics: [VibenetTopics.policyExecuted, "0x" + VibenetABI.padAddress(account)])
        else { return ([], []) }

        var rows: [VibenetPolicyRun] = []
        for log in logs {
            guard (log["removed"] as? Bool) != true,
                  let topics = log["topics"] as? [String], topics.count >= 4,
                  let txHash = log["transactionHash"] as? String,
                  let blockHex = log["blockNumber"] as? String,
                  let indexHex = log["logIndex"] as? String
            else { continue }
            let block = WalletIngest.hexToInt(blockHex)
            let logIndex = WalletIngest.hexToInt(indexHex)
            guard block >= 0, logIndex >= 0 else { continue }
            rows.append(VibenetPolicyRun(
                commitment: topics[3].lowercased(),
                // The `caller` word, read at last. Nil rather than the account
                // itself on a failed decode — a fallback there would claim you
                // ran your own key.
                caller: (log["data"] as? String).flatMap { VibenetLogData.address($0, at: 0) },
                at: nil, txHash: txHash, block: block, logIndex: logIndex))
        }
        guard !rows.isEmpty else { return ([], []) }

        // Newest first, then bounded — the same order-then-cap the ledger
        // keeps, because capping first drops today's runs to keep last
        // month's.
        let all = VibenetPolicyRuns.ordered(rows)
        let kept = Array(all.prefix(VibenetPolicyRuns.cap))
        // ONE block-time lookup per distinct block — several runs can share
        // one, and this is the same "never `.now`" discipline every other
        // dated read in this file keeps.
        var times: [Int: Date] = [:]
        for block in Set(kept.map(\.block)) {
            if let date = await VibenetChain.blockTime(block) { times[block] = date }
        }
        let dated = kept.map {
            VibenetPolicyRun(commitment: $0.commitment, caller: $0.caller, at: times[$0.block],
                             txHash: $0.txHash, block: $0.block, logIndex: $0.logIndex)
        }
        // THE FOLD SEES EVERY RUN, the stored array only the newest `cap` —
        // so a key's use COUNT stays exact however busy it is, and what the
        // bound costs is a date on the oldest runs, never a wrong number
        // about a key's authority (see `VibenetPolicyRuns.cap`).
        return (dated, VibenetPolicyRuns.fold(dated + all.dropFirst(VibenetPolicyRuns.cap)))
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
    static func account(_ address: String, contracts: VibenetContracts,
                        tokens: [Token] = []) async -> VibenetAccountItem {
        // THE GATE (prd §515a). `eth_getCode`, not a Keystore view method:
        // this is the one call in the read that decides whether the node was
        // reached at all, and a redeploy must never be able to delete it.
        // See `VibenetDeployment` for the day this was measured and the
        // 7702 trap it names.
        guard let code = await VibenetChain.getCode(address: address) else {
            return VibenetAccountItem(address: address, reached: false, established: false,
                                      actors: [], locked: false, hasInitiatedUnlock: false,
                                      unlocksAt: nil, unlockDelay: nil)
        }
        let established = VibenetDeployment.isDeployed(code: code)

        async let eventsTask = actorEvents(account: address, keystore: contracts.keystore)
        async let lockTask = VibenetChain.ethCall(
            to: contracts.keystore, data: VibenetABI.lockStatusCall(address))
        async let sequencesTask = changeSequences(account: address, keystore: contracts.keystore)
        // Balances (2026-08-24), read alongside everything above rather
        // than as a second pass over the watch list — one more `async let`
        // apiece, paced by the same `IngestSupport.boundedGather(maxConcurrent: 3)`
        // that already governs how many addresses run at once.
        async let nativeTask = VibenetChain.getBalance(address: address)
        async let balancesTask = tokenBalances(account: address, tokens: tokens)
        // WHAT MOVED, and WHERE THIS ACCOUNT CAME FROM (prd §507) — both ride
        // the same concurrent fan-out as everything above, and each answers a
        // question the room could not answer at all before: what this account
        // has actually done with its tokens, and how old it is.
        async let transfersTask = transfers(account: address, tokens: tokens)
        async let originTask = origin(account: address, keystore: contracts.keystore)
        // Both 2026-08-24 additions ride the same concurrent fan-out. Each is
        // ONE filtered `eth_getLogs` (plus a bounded block-time lookup), and
        // each answers a question this room could not answer at all before:
        // has a session key actually been used, and what accounts can this
        // address act for.
        async let policyRunsTask = policyRuns(account: address, policyManager: contracts.policyManager)
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
        let tokenBalances = await balancesTask

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
                                 // The live roster first; then the one kind
                                 // a DEAD key can still prove about itself
                                 // (prd §507) — an address-shaped actorId is
                                 // a delegate, with no read and no guess.
                                 // Applies to an authorized moment too: a key
                                 // authorized and later revoked is absent from
                                 // the roster exactly like a revoke is.
                                 kind: liveKind[e.actorId]
                                     ?? VibenetKeyHistory.inferredKind(actorId: e.actorId),
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

        let moved = await transfersTask
        let policy = await policyRunsTask
        return VibenetAccountItem(address: address, reached: true, established: established,
                                  actors: actors, locked: locked,
                                  hasInitiatedUnlock: hasInitiatedUnlock,
                                  unlocksAt: unlocksAt, unlockDelay: unlockDelay,
                                  changeSequences: sequences, history: history,
                                  nativeBalance: nativeBalance, tokenBalances: tokenBalances,
                                  policyUses: policy.uses,
                                  subAccounts: await subAccountsTask,
                                  transfers: moved.rows, transfersCapped: moved.capped,
                                  origin: await originTask, policyRuns: policy.runs)
    }

    /// Every named token's balance for one account, concurrently.
    private static func tokenBalances(account: String, tokens: [Token]) async
        -> [VibenetTokenBalance] {
        guard !tokens.isEmpty else { return [] }
        return await withTaskGroup(of: VibenetTokenBalance?.self) { group in
            for token in tokens {
                group.addTask { await tokenBalance(account: account, token: token) }
            }
            var out: [VibenetTokenBalance] = []
            for await balance in group where balance != nil { out.append(balance!) }
            // A TOTAL order, because a task group answers in completion order
            // and a room whose token tiles reshuffle between reads over
            // identical balances reads as broken.
            return out.sorted { $0.symbol < $1.symbol }
        }
    }

    /// One ERC-20-shaped balance for `account` on `contract` — nil for any
    /// of three reasons this file deliberately does NOT distinguish
    /// further (no contract named by the live config, the balance read
    /// failed, or `decimals()` couldn't be confirmed): every one of them
    /// means "no honest number to show", never "assume zero" or "assume
    /// 18 decimals" (§83, and the standing decimals lesson — see
    /// `VibenetTokenDecimals`'s own doc).
    /// One token's balance for one account, against a token whose identity is
    /// ALREADY RESOLVED (`tokens(_:)`, once per pass).
    ///
    /// The resolution moved out of here deliberately: it is per-CONTRACT, not
    /// per-account, and doing it inside meant every account re-asked what
    /// USDV was. It also means the balance read and the transfer read below
    /// can never disagree about whether a contract is fungible — one answer,
    /// one pass.
    private static func tokenBalance(account: String, token: Token) async -> VibenetTokenBalance? {
        guard let balanceHex = await VibenetChain.ethCall(
            to: token.contract, data: VibenetABI.balanceOfCall(account)),
              let raw = VibenetABI.rawAmountWord(balanceHex),
              let amount = token.identity.amount(raw: raw, decimals: token.decimals)
        else { return nil }
        return VibenetTokenBalance(symbol: token.symbol, amount: amount,
                                   isCount: token.identity == .collectible)
    }

    /// One token's identity, resolved once per pass so the transfer read and
    /// the balance read cannot disagree about what a contract is.
    struct Token: Equatable {
        let contract: String
        let symbol: String
        let identity: VibenetTokenIdentity
        let decimals: Int?
    }

    static func tokens(_ contracts: VibenetContracts) async -> [Token] {
        var out: [Token] = []
        for entry in contracts.tokenContracts {
            guard let facts = await VibenetTokenFacts.read(contract: entry.address) else { continue }
            // Spelled out rather than `entry.symbol ?? await …`: `??`'s
            // right-hand side is an autoclosure, which cannot carry an await.
            var symbol = entry.symbol
            if symbol == nil { symbol = await VibenetTokenSymbol.read(contract: entry.address) }
            guard let symbol else { continue }
            out.append(Token(contract: entry.address, symbol: symbol,
                             identity: facts.identity, decimals: facts.decimals))
        }
        return out
    }

    // MARK: - What moved (prd §507)

    /// How far back a transfer walk reaches, in `VibenetChain.maxLogRange`
    /// chunks.
    ///
    /// **Deliberately SHALLOWER than the actor walk, and the asymmetry is the
    /// point.** The roster's own doc says why it must be complete: liveness is
    /// decided by the LATEST event per actorId, so a missed early
    /// authorization makes a live key vanish. A ledger has no such property —
    /// a missed old transfer is a missing row, not a wrong claim — and it is
    /// the read this pass adds SIX of per account, so it takes the bound. What
    /// it must never do is present the result as complete: that is
    /// `transfersCapped` and `VibenetBalanceSeries.isComplete`.
    static let transferChunks = 3

    /// Every `Transfer` touching this account, across every token the config
    /// names.
    ///
    /// TWO reads per token, and they cannot be one: `from` and `to` are
    /// different indexed POSITIONS, and `eth_getLogs` ORs within a position
    /// and ANDs across them, so a single filter naming both asks for the
    /// transfers an account made TO ITSELF and nothing else. The self-move is
    /// then the row that appears in both answers, which is exactly how it is
    /// detected here rather than by comparing strings twice.
    static func transfers(account: String, tokens: [Token]) async -> (rows: [VibenetTransfer], capped: Bool) {
        guard !tokens.isEmpty else { return ([], false) }
        let mine = "0x" + VibenetABI.padAddress(account)
        var rows: [VibenetTransfer] = []
        var blocks = Set<Int>()
        var capped = false

        for token in tokens {
            async let outTask = VibenetChain.getLogs(
                address: token.contract, topics: [VibenetTopics.erc20Transfer, mine],
                maxChunks: transferChunks)
            async let inTask = VibenetChain.getLogs(
                address: token.contract, topics: [VibenetTopics.erc20Transfer, NSNull(), mine],
                maxChunks: transferChunks)
            let outgoing = await outTask ?? []
            let incoming = await inTask ?? []
            // A log appearing in BOTH answers is a self-move — the account is
            // the `from` and the `to`. Keyed by (tx, index), which is one log
            // on any EVM chain.
            var seen: [String: VibenetTransfer] = [:]
            for (logs, direction) in [(outgoing, VibenetTransferDirection.outgoing),
                                      (incoming, VibenetTransferDirection.incoming)] {
                for log in logs {
                    guard let row = transfer(log, token: token, direction: direction) else { continue }
                    if let held = seen[row.id], held.direction != direction {
                        seen[row.id] = VibenetTransfer(
                            symbol: row.symbol, direction: .selfMove, counterparty: account,
                            amount: row.amount, at: nil, txHash: row.txHash,
                            block: row.block, logIndex: row.logIndex, tokenID: row.tokenID)
                    } else {
                        seen[row.id] = row
                    }
                }
            }
            rows.append(contentsOf: seen.values)
            if outgoing.count >= VibenetLedger.cap || incoming.count >= VibenetLedger.cap {
                capped = true
            }
        }

        let kept = VibenetLedger.capped(rows)
        capped = capped || rows.count > kept.count
        // ONE block-time lookup per distinct block — several transfers share
        // one, and this is the same "never `.now`" discipline every other
        // dated read in this file keeps. Bounded by the cap above it.
        for row in kept { blocks.insert(row.block) }
        var times: [Int: Date] = [:]
        for block in blocks {
            if let date = await VibenetChain.blockTime(block) { times[block] = date }
        }
        let dated = kept.map { row in
            VibenetTransfer(symbol: row.symbol, direction: row.direction,
                            counterparty: row.counterparty, amount: row.amount,
                            at: times[row.block], txHash: row.txHash, block: row.block,
                            logIndex: row.logIndex, tokenID: row.tokenID)
        }
        return (dated, capped)
    }

    /// One `Transfer` log, decoded.
    ///
    /// **THE TOPIC COUNT DECIDES**, never the contract: ERC-20 and ERC-721
    /// share the signature `Transfer(address,address,uint256)` byte for byte,
    /// and differ only in whether that third argument is indexed. Three topics
    /// is a fungible amount in `data`; four is a token id and empty data,
    /// which a fungible decoder reads as an amount of ZERO — a transfer of
    /// nothing, landed as a real row, on a screen about what moved.
    private static func transfer(_ log: [String: Any], token: Token,
                                 direction: VibenetTransferDirection) -> VibenetTransfer? {
        guard (log["removed"] as? Bool) != true,
              let topics = log["topics"] as? [String], topics.count >= 3,
              topics[0].lowercased() == VibenetTopics.erc20Transfer,
              let txHash = log["transactionHash"] as? String,
              let blockHex = log["blockNumber"] as? String,
              let indexHex = log["logIndex"] as? String
        else { return nil }
        let from = "0x" + topics[1].suffix(40)
        let to = "0x" + topics[2].suffix(40)
        let counterparty = direction == .outgoing ? to : from
        let block = WalletIngest.hexToInt(blockHex)
        let logIndex = WalletIngest.hexToInt(indexHex)
        guard block >= 0, logIndex >= 0 else { return nil }

        if topics.count >= 4 {
            // A token id, not an amount. Rendered as a short id rather than
            // the full 32-byte word: a 78-digit decimal is not a name.
            let raw = topics[3].lowercased()
            let trimmed = String(raw.dropFirst(2).drop(while: { $0 == "0" }))
            let id = trimmed.isEmpty ? "0" : trimmed
            guard let value = VibenetLogData.uint(raw, at: 0), value < 1e15 else {
                return VibenetTransfer(symbol: token.symbol, direction: direction,
                                       counterparty: counterparty, amount: 1, at: nil,
                                       txHash: txHash, block: block, logIndex: logIndex,
                                       tokenID: "…" + String(id.suffix(6)))
            }
            return VibenetTransfer(symbol: token.symbol, direction: direction,
                                   counterparty: counterparty, amount: 1, at: nil,
                                   txHash: txHash, block: block, logIndex: logIndex,
                                   tokenID: String(Int(value)))
        }

        guard let data = log["data"] as? String,
              let raw = VibenetLogData.uint(data, at: 0),
              let amount = token.identity.amount(raw: raw, decimals: token.decimals)
        else { return nil }
        return VibenetTransfer(symbol: token.symbol, direction: direction,
                               counterparty: counterparty, amount: amount, at: nil,
                               txHash: txHash, block: block, logIndex: logIndex)
    }

    /// WHERE THIS ACCOUNT CAME FROM (prd §507) — one filtered `AccountCreated`
    /// read, on the topic that has been indexed the whole time.
    ///
    /// The event has been read since the seat shipped and only GLOBALLY, for
    /// the empty state's "recently created" list, so the room could never say
    /// how old its own accounts were and Activity began at the first key
    /// rather than at the account.
    ///
    /// `codeHash` is the second non-indexed word (`userSalt` is the first) —
    /// the fact worth having on a chain that redeploys weekly, because two
    /// accounts sharing it run the same implementation.
    static func origin(account: String, keystore: String) async -> VibenetOrigin? {
        guard let logs = await VibenetChain.getLogs(
            address: keystore,
            topics: [VibenetTopics.accountCreated, "0x" + VibenetABI.padAddress(account)])
        else { return nil }
        // The OLDEST is the creation — an account cannot be created twice, but
        // a redeployed Keystore can emit for an address that already existed,
        // and the first one is the one that means "created".
        var best: (block: Int, index: Int, log: [String: Any])?
        for log in logs {
            guard (log["removed"] as? Bool) != true,
                  let blockHex = log["blockNumber"] as? String,
                  let indexHex = log["logIndex"] as? String else { continue }
            let block = WalletIngest.hexToInt(blockHex)
            let index = WalletIngest.hexToInt(indexHex)
            if let held = best, (held.block, held.index) <= (block, index) { continue }
            best = (block, index, log)
        }
        guard let best else { return nil }
        let createdAt = await VibenetChain.blockTime(best.block)
        let data = best.log["data"] as? String
        let codeHash = data.flatMap { VibenetLogData.word($0, at: 1) }.map { "0x" + $0 }
        return VibenetOrigin(createdAt: createdAt, codeHash: codeHash,
                             txHash: best.log["transactionHash"] as? String,
                             logIndex: best.index)
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

/// **THE CHAIN THIS DEVICE LAST SAW (prd §515a).**
///
/// `VibenetSeenCommit`'s neighbour and its exact shape, for a stronger fact:
/// that one notices the CONTRACTS moving, this notices the CHAIN UNDER THEM
/// being replaced. On 2026-08-29 both happened at once and neither was
/// visible anywhere in the app.
///
/// Storage only — the judgement is `VibenetChainReset`, where the harness can
/// compile it.
enum VibenetSeenChain {
    private static let chainKey = "vibenet.chain.lastSeenID"
    private static let tipKey = "vibenet.chain.highWaterTip"
    /// The verdict of the most recent check, so the room can state it without
    /// re-reading the chain (and without a second check ADVANCING the stored
    /// values, which would make the reset un-sayable one pass later).
    private static let stickyKey = "vibenet.chain.resetSeenAt"
    /// Which reset that sticky date belongs to (prd §522) — the notification
    /// ledger's key, so the same wipe is announced once and a SECOND wipe is
    /// announced again. Written and cleared together with the date.
    private static let resetKeyKey = "vibenet.chain.resetKey"

    /// Reads the chain, compares, advances, and — on a real reset — forgets
    /// the per-address caches that describe a chain which no longer exists.
    ///
    /// EVERY CALL IS ALSO THE WRITE, `VibenetSeenCommit`'s rule, so a first
    /// call can never report a reset.
    @discardableResult
    static func check() async -> VibenetChainReset.Verdict {
        let liveID = await VibenetChain.chainIdentifier()
        let liveTip = await VibenetChain.cachedTip()
        let storedID = UserDefaults.standard.object(forKey: chainKey) as? Int
        let storedTip = UserDefaults.standard.object(forKey: tipKey) as? Int
        let verdict = VibenetChainReset.verdict(storedChainID: storedID, liveChainID: liveID,
                                                storedHighWater: storedTip, liveTip: liveTip)
        if let liveID { UserDefaults.standard.set(liveID, forKey: chainKey) }
        if let next = VibenetChainReset.nextHighWater(stored: storedTip, liveTip: liveTip,
                                                      verdict: verdict) {
            UserDefaults.standard.set(next, forKey: tipKey)
        }
        if verdict.isReset {
            UserDefaults.standard.set(Date(), forKey: stickyKey)
            // The key rides ALONGSIDE the date rather than replacing it: the
            // room asks "was there a reset recently" and the notification asks
            // "which one, and have I said it", and those are different
            // questions with different lifetimes.
            if let key = verdict.notifyKey {
                UserDefaults.standard.set(key, forKey: resetKeyKey)
            }
            forgetChainState()
        }
        return verdict
    }

    /// Whether a reset was observed recently enough to still be the reason
    /// this room is empty. A WINDOW, not a flag: a month later "vibenet was
    /// reset since you last looked" is no longer the explanation for
    /// anything, and a sentence that never expires becomes furniture.
    static let sayItFor: TimeInterval = 7 * 86_400

    static func sawResetRecently(now: Date = .now) -> Bool {
        guard let at = UserDefaults.standard.object(forKey: stickyKey) as? Date else { return false }
        return now.timeIntervalSince(at) < sayItFor
    }

    /// The reset this device last observed, for the notification sweep
    /// (prd §522) — nil when there has not been one.
    ///
    /// **A READ, never a claim.** It does not consult the ledger and does not
    /// clear anything: `NotifyDevnet` decides whether it is still news and
    /// `NotifyLedger` decides whether it has already been said, which is what
    /// keeps this callable from a sweep that runs on every foreground.
    /// A date with no key is a reset observed by a build that predates this,
    /// and is deliberately silent rather than announced under an invented key.
    static func observedReset() -> (key: String, at: Date)? {
        guard let at = UserDefaults.standard.object(forKey: stickyKey) as? Date,
              let key = UserDefaults.standard.string(forKey: resetKeyKey)
        else { return nil }
        return (key, at)
    }

    static func describe(_ verdict: VibenetChainReset.Verdict) -> String {
        switch verdict {
        case .firstSight:               return "first sight (silent by design)"
        case .same:                     return "same chain"
        case let .newChain(from, to):   return "RESET — chain id \(from) → \(to)"
        case let .rewound(from, to):    return "RESET — tip rewound \(from) → \(to)"
        }
    }

    /// **WHAT A RESET FORGETS, BY NAME (prd §515a).**
    ///
    /// Every one of these is a snapshot OF A CHAIN THAT NO LONGER EXISTS: a
    /// balance sampled from it, a key roster read off it, the contract set it
    /// carried. Kept, they would be shown as the current state of a devnet
    /// that was wiped.
    ///
    /// Three deliberate NON-deletions, each with its reason:
    ///
    /// - **The watch list stays.** An EIP-8130 account is counterfactual, so
    ///   the address survives the reset and comes back the moment it
    ///   transacts. Dropping it would make the person re-enter an address
    ///   that was never wrong.
    /// - **Landed `Thing`s stay.** The standing rule (`delete-guard-audit.py`)
    ///   is that upstream going quiet is never licence to prune, and it holds
    ///   doubly here: those events DID happen, they are dated by the block
    ///   times they really had, and their refs are keyed on transaction hash
    ///   so nothing on the new chain can collide with them.
    /// - **`VibenetSeenCommit` stays.** It answers a different question — did
    ///   the CONTRACTS move — and clearing it would silence the redeploy
    ///   notice on exactly the pass that most needs it.
    static func forgetChainState() {
        // The contracts: a reset redeploys them, so the cached set names
        // addresses that no longer hold code.
        VibenetConfig.forgetCache()
        // The room snapshot: keys, locks and rosters read off the dead chain.
        // One empty head until the next read lands is the right cost — the
        // alternative is drawing a wiped account's key roster as current.
        VibenetState.forget()
        // Which keys this device has already seen, per account. Kept, the
        // next read would diff a fresh chain's roster against a dead one's
        // and announce every key as revoked.
        VibenetKeysSeen.forget()
        // The balance curve, and the per-block backfill behind it. Note the
        // DIVERGENCE from a redeploy, which deliberately keeps both (see
        // `VibenetBackfillLedger.forget`'s own doc: a contract deployment
        // does not rewrite a chain's past blocks). A RESET does exactly that
        // — those blocks are gone — so here they go.
        VibenetValueStore.forget()
        VibenetBackfillLedger.forget()
        Task { await VibenetTipCache.shared.forget() }
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
        // HAS THE CHAIN BEEN REPLACED UNDER US (prd §515a) — asked FIRST, and
        // the order is load-bearing: a reset forgets the cached contract set,
        // so this has to run before `current()` or the pass below reads a
        // still-fresh cache naming a Keystore that no longer holds code. It
        // also forgets the room snapshot and the balance curve, both of which
        // describe a chain that is gone.
        await VibenetSeenChain.check()
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
        // TOKEN IDENTITY IS RESOLVED ONCE PER PASS, not once per account
        // (prd §507): what USDV is does not vary by who holds it, and asking
        // per account meant the same `decimals()` round trip for every address
        // on the list. It also means the balance read and the transfer read
        // cannot disagree about whether a contract is fungible.
        let tokens = await VibenetRead.tokens(contracts)
        // THE CHAIN'S OWN PULSE (prd §507) — three calls for the whole room,
        // read alongside the accounts rather than after them, because on a
        // stalled devnet it is the fact that explains every reading below it.
        async let pulseTask = VibenetChain.pulse()
        let items = await IngestSupport.boundedGather(addresses, maxConcurrent: 3) { address in
            await VibenetRead.account(address, contracts: contracts, tokens: tokens)
        }
        let pulse = await pulseTask
        // `readAt` — stamped HERE and only here, because this is the only
        // place in the app that has genuinely just read the chain. See
        // `VibenetRoom.readAt` for the defect it closes; `vibenet-selftest.sh`
        // guards that this call site still passes it, since a room that
        // silently loses its timestamp goes back to drawing three-day-old
        // state with a confident face.
        let room = VibenetRoom.compose(items: items, branch: contracts.branch,
                                       commit: contracts.commit, configReached: true,
                                       redeployedSinceLastSeen: redeployed, readAt: .now,
                                       pulse: pulse)
        VibenetState.save(room)
        // THE CURVE THAT STARTS BEFORE YOU DID (prd §507) — once per account,
        // ever, and only where the local history is too thin to draw. See
        // `VibenetNativeBackfill` for why this is worth a handful of calls and
        // `VibenetBackfillLedger` for why it can only ever be paid once.
        await VibenetBackfill.run(room: room, tip: pulse?.tip)
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
    /// **v2 (prd §507).** The snapshot gained transfers, an origin, policy
    /// runs and the chain's pulse, and `VibenetAccountItem`'s new arrays are
    /// non-Optional — Swift's synthesised decoder does not apply a property's
    /// default for a missing key, so every v1 snapshot on every device would
    /// have failed to decode. That failure is SILENT here (`try?` → nil → the
    /// head draws nothing until the next read lands), which is precisely why
    /// it gets a new key rather than a shrug: a one-off empty head on upgrade
    /// day is a decision, and a decode that quietly never succeeds again if a
    /// future field is added wrong is not. The old key is left to be dropped
    /// by the system rather than migrated — it is a cache of a chain that
    /// redeploys weekly.
    private static let key = "vibenet.room.snapshot.v2"

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

/// THE NATIVE CURVE, BACKFILLED FROM THE CHAIN (prd §507).
///
/// `VibenetValueHistory` can only record what it saw while the app was open:
/// six readings before it draws a line, two minutes apart at best, and
/// structurally blind to everything before the day somebody started watching.
/// So the room's own sparkline was a chart of when you opened the app.
///
/// `eth_getBalance` takes a block tag. A node that keeps state can therefore
/// answer what an account held last week, and those answers are REAL readings
/// — nothing here interpolates, and a node that will not answer (pruned, or
/// simply erroring) yields nothing rather than a zero, which would draw a
/// cliff.
///
/// **Paid ONCE per account, ever.** The ledger below is what makes that true;
/// without it this is eight extra calls per account on every foreground, for
/// a curve that only needs building once.
enum VibenetBackfillLedger {
    private static let key = "vibenet.backfill.done.v1"

    static func done() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func isDone(_ address: String) -> Bool { done().contains(address.lowercased()) }

    static func mark(_ address: String) {
        var held = done()
        held.insert(address.lowercased())
        UserDefaults.standard.set(Array(held), forKey: key)
    }

    /// Dropped on disconnect with everything else — and NOT on a redeploy,
    /// deliberately: the balances a node reports for past blocks are that
    /// chain's own history, and a new contract deployment does not rewrite it.
    static func forget() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

enum VibenetBackfill {
    /// The room's OWN series is backfilled under one extra rule: a point is
    /// kept only when EVERY watched account answered at that block.
    ///
    /// A total whose membership changes between points is not a total — it is
    /// a cliff drawn where a read failed, on the crown's own line, which is
    /// the "flat curve reads as went to zero" failure wearing a different
    /// shape. The per-account curves have no such problem and keep every
    /// point they can get.
    private static let roomKey = "vibenet.backfill.room.v1"

    @discardableResult
    static func run(room: VibenetRoom, tip: Int?) async -> Int {
        guard let tip, tip > 0, !room.items.isEmpty else { return 0 }
        let blocks = VibenetNativeBackfill.blocks(tip: tip)
        guard !blocks.isEmpty else { return 0 }

        let roomDone = UserDefaults.standard.bool(forKey: roomKey)
        let roomThin = VibenetValueStore.samples().count < VibenetValueHistory.minimumForCurve
        let wantRoom = !roomDone && roomThin
        // Which accounts still need one. An account with a real local history
        // already has a curve, and buying eight more points for it would spend
        // requests to redraw a line that is already there.
        let wanted = room.items.filter { item in
            item.reached && item.nativeBalance != nil
                && !VibenetBackfillLedger.isDone(item.address)
                && VibenetValueStore.samples(for: item.address).count < VibenetValueHistory.minimumForCurve
        }
        guard wantRoom || !wanted.isEmpty else { return 0 }
        // The room's total needs every account at the same block, so when it
        // is wanted the whole roster is read; otherwise only the thin ones.
        let subjects = wantRoom ? room.items.filter(\.reached) : wanted
        guard !subjects.isEmpty else { return 0 }

        var perAccount: [String: [VibenetValueSample]] = [:]
        var roomSamples: [VibenetValueSample] = []
        var filled = 0
        for block in blocks {
            // ONE block-time lookup per block, shared by every account — the
            // same discipline every other dated read in this file keeps.
            guard let at = await VibenetChain.blockTime(block) else { continue }
            var total = 0.0
            var answered = 0
            for item in subjects {
                guard let hex = await VibenetChain.getBalance(address: item.address, atBlock: block)
                else { continue }
                let value = WalletIngest.hexToDouble(hex)
                guard value.isFinite else { continue }
                let native = value / 1e18
                total += native
                answered += 1
                guard wanted.contains(where: { $0.address == item.address }) else { continue }
                perAccount[item.address.lowercased(), default: []]
                    .append(VibenetValueSample(at: at, native: native))
                filled += 1
            }
            if wantRoom && answered == subjects.count {
                roomSamples.append(VibenetValueSample(at: at, native: total))
            }
        }

        if !perAccount.isEmpty {
            var book = VibenetValueStore.accountSamples()
            for (address, chain) in perAccount {
                book[address] = VibenetValueHistory.merged(local: book[address] ?? [], chain: chain)
            }
            VibenetValueStore.replaceAccounts(book)
        }
        if wantRoom && !roomSamples.isEmpty {
            VibenetValueStore.replace(
                VibenetValueHistory.merged(local: VibenetValueStore.samples(), chain: roomSamples))
        }
        // MARKED EVEN WHEN IT ANSWERED NOTHING. A pruned node will not start
        // answering because we asked again, and re-asking every foreground is
        // the unbounded crawl this file refuses everywhere else. The cost of
        // being wrong is a curve that starts today — exactly where it started
        // before this existed.
        for item in wanted { VibenetBackfillLedger.mark(item.address) }
        if wantRoom { UserDefaults.standard.set(true, forKey: roomKey) }
        return filled
    }

    static func forget() {
        UserDefaults.standard.removeObject(forKey: roomKey)
        VibenetBackfillLedger.forget()
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
    static func land(context: ModelContext, room: VibenetRoom? = nil) async -> Int {
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

        // THE COMPOSED ROOM IS THE SOURCE FOR EVERYTHING NEW (prd §507), and
        // that is a cost decision as much as a design one: transfers, policy
        // runs and an account's creation are all read by
        // `VibenetRoomSource.compose()` moments earlier in the same sweep, and
        // re-reading them here would double this bridge's request count to
        // learn facts already in hand. The key and lock events still make
        // their own log reads, because a landed row's ref needs the
        // TRANSACTION HASH and the composed room's key history carries block
        // and index but not that.
        //
        // Falls back to the saved snapshot when no room is handed in, so a
        // caller that lands without composing (a probe, an older call site)
        // still gets the new rows — one pass stale, which for a row that is
        // already a record of the past is a delay rather than an error.
        let composed = room ?? VibenetState.saved
        var landed = 0
        for address in addresses {
            let item = composed?.items.first {
                $0.address.caseInsensitiveCompare(address) == .orderedSame
            }
            landed += await landAccount(address, contracts: contracts, context: context,
                                        existing: byRef, item: item)
        }
        return landed
    }

    /// The rows that come from the composed room rather than from a log read
    /// of this pass's own (prd §507).
    ///
    /// Every one of them is an EVENT with a clock — tokens arriving, a policy
    /// key running, the account itself being created — which is the same test
    /// the four key and lock events already pass. What is deliberately NOT
    /// here is any reading of STATE: a balance, a roster count, a lock status.
    /// Those are live and belong to the room, and landing one would be the
    /// count-as-a-thing failure §223 names.
    @MainActor
    private static func landComposed(_ item: VibenetAccountItem, context: ModelContext,
                                     existing: [String: Thing]) -> Int {
        let shortAddress = VibenetRoom.shortAddress(item.address)
        var landed = 0

        func insert(kind: VibenetEventKind, txHash: String, logIndex: Int, at: Date?,
                    detail: String?, extraTags: [String] = []) {
            let ref = "vibenet:\(kind.refSegment):\(txHash):\(logIndex)"
            guard existing[ref] == nil else { return }
            // NO DATE, NO ROW. Every other landing in this file falls back to
            // `.now` only where the event is known to have just happened;
            // these are historical by construction — a transfer from four
            // months ago stamped today is the wrong-date failure this file
            // has a rule against, and the row is worth less than the lie.
            guard let at else { return }
            let thing = Thing(
                kind: .event,
                title: kind.title(shortAddress: shortAddress, keyLabel: nil, detail: detail),
                content: VibenetExplorer.tx(txHash),
                source: VibenetIdentity.source,
                capturedAt: at,
                sourceRef: ref)
            thing.authorHandle = item.address
            thing.summary = kind.phrase(keyLabel: nil, detail: detail)
            thing.tags = kind.facetTags + extraTags
            context.insert(thing)
            landed += 1
        }

        for transfer in item.transfers {
            // A SELF-MOVE LANDS NOTHING. It is a real log and it is not news:
            // the balance did not change, and a row reading "sent 5 USDV" for
            // money that never left is a false claim about where it went.
            guard transfer.direction != .selfMove else { continue }
            let other = VibenetRoom.shortAddress(transfer.counterparty)
            insert(kind: transfer.direction == .incoming ? .transferIn : .transferOut,
                   txHash: transfer.txHash, logIndex: transfer.logIndex, at: transfer.at,
                   detail: transfer.direction == .incoming
                       ? String(localized: "\(transfer.display) from \(other)")
                       : String(localized: "\(transfer.display) to \(other)"))
        }
        for run in item.policyRuns {
            insert(kind: .policyRun, txHash: run.txHash, logIndex: run.logIndex, at: run.at,
                   detail: run.caller.map { String(localized: "by \(VibenetRoom.shortAddress($0))") })
        }
        if let origin = item.origin, let txHash = origin.txHash {
            insert(kind: .created, txHash: txHash, logIndex: origin.logIndex ?? 0,
                   at: origin.createdAt, detail: nil)
        }
        return landed
    }

    private struct RawEvent {
        let kind: VibenetEventKind
        let actorId: String?
        let txHash: String
        let logIndex: Int
        let block: Int
        /// The log's non-indexed half — read for the two LOCK kinds, whose
        /// one interesting number lives there and was never decoded (prd
        /// §507, `VibenetLockDetail`).
        var data: String? = nil
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
                        logIndex: WalletIngest.hexToInt(indexHex),
                        block: WalletIngest.hexToInt(blockHex),
                        data: log["data"] as? String)
    }

    private static func ref(_ e: RawEvent) -> String {
        "vibenet:\(e.kind.refSegment):\(e.txHash):\(e.logIndex)"
    }

    @MainActor
    private static func landAccount(_ address: String, contracts: VibenetContracts,
                                    context: ModelContext, existing: [String: Thing],
                                    item: VibenetAccountItem? = nil) async -> Int {
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

        // THE COMPOSED ROWS LAND BEFORE THE EARLY RETURN (prd §507), and that
        // placement is the whole of whether they ever land at all: on almost
        // every pass there is no new KEY event, so behind the return a
        // transfer would only ever arrive on a pass that happened to be
        // landing a key change. The deadline sweep above it is here for the
        // same reason and learned it the same way.
        var composedLanded = 0
        if let item { composedLanded = landComposed(item, context: context, existing: existing) }

        let fresh = events.filter { existing[ref($0)] == nil }
        guard !fresh.isEmpty else { return composedLanded }

        // Block times, ONE call per distinct block among the new events —
        // never `.now` unless the read genuinely fails, the WalletApprovals
        // rule: a fallback rendered as a sentence dates real news to today.
        var times: [Int: Date] = [:]
        for block in Set(fresh.map(\.block)) {
            times[block] = await VibenetChain.blockTime(block)
        }

        let known = contracts.knownAuthenticators
        let shortAddress = VibenetRoom.shortAddress(address)
        var landedCount = composedLanded
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
            // THE LOCK'S OWN NUMBER (prd §507) — seconds of timelock for a
            // lock, the moment it opens for an unlock. Both were sitting in
            // the log's `data` and neither was read, so the two rows a locked
            // account produces said what happened and not what it means.
            var detail: String?
            if let data = event.data {
                switch event.kind {
                case .locked:
                    detail = VibenetLogData.uint64(data, at: 0)
                        .flatMap { VibenetLockDetail.timelockPhrase(seconds: $0) }
                case .unlockInitiated:
                    detail = VibenetLogData.uint64(data, at: 0)
                        .flatMap { VibenetLockDetail.opensPhrase(unlocksAt: $0) }
                default: break
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
                title: event.kind.title(shortAddress: shortAddress, keyLabel: keyLabel,
                                        detail: detail),
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
            thing.summary = event.kind.phrase(keyLabel: keyLabel, detail: detail)
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
    /// THE TWO REFERENCE ACCOUNTS THE CONFIG NAMES (prd §507).
    ///
    /// `defaultAccount` and `canonicalHighRatePayerAccount` have been parsed
    /// out of the live config since the seat shipped and read by nothing.
    /// They are exactly what the empty state wants — a real established
    /// account to look at before you own one — and they cost ZERO requests,
    /// where `recentAccounts` below pays for a global log walk to find the
    /// same kind of thing.
    ///
    /// Named rather than listed bare, because "0x1f9c…20a1" tells nobody why
    /// it is being offered; and never presented as YOURS, which is the whole
    /// distinction the empty state is about.
    static func reference(_ contracts: VibenetContracts?) -> [VibenetDiscoveredAccount] {
        guard let contracts else { return [] }
        var out: [VibenetDiscoveredAccount] = []
        var seen = Set<String>()
        for address in [contracts.defaultAccount, contracts.canonicalHighRatePayerAccount] {
            guard let address, VibenetWatch.isValidAddress(address),
                  seen.insert(address.lowercased()).inserted else { continue }
            // `createdAt` nil, and not looked up: these are offered as
            // examples rather than dated as news, and a block-time read to
            // put "created 4 months ago" under a demonstration account is a
            // request bought for decoration.
            out.append(VibenetDiscoveredAccount(address: address, createdAt: nil))
        }
        return out
    }

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
