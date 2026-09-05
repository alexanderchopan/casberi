import Foundation

/// ETHREX PRIVACY (prd §593, 2026-09-04) — the third ethrex devnet, and a chain
/// of its own rather than a re-host of Hegotá.
///
/// **WATCH-ONLY, and structurally so.** This file issues reads and nothing
/// else: no key is made here, nothing is signed, nothing is broadcast. That is
/// not caution about the App Store question — it is that §593a could not
/// reproduce this chain's type-`0x6` envelope byte-exactly, and signing a
/// guessed layout yields a signature that is well-formed, recovers to a real
/// address, and authorises something other than what the screen said. The
/// conduct is enforced rather than remembered: `scripts/privacy-selftest.sh`
/// fails the build if this file gains a write verb.
///
/// **What separates it from its two siblings**, all measured on 2026-09-04:
///   • chain **8141** (`0x1fcd`), genesis `0x7ca0f735…` — distinct from both.
///   • EIP-8272's recent-roots predeploy `0x…8272` has **144 bytes** here and
///     no code on either sibling, so the Roots scope exists nowhere else.
///   • the UTXO vault `0x…8312` has **no code**, so there is no Coins scope —
///     absent rather than empty (see `PrivacyDevnetSection`).
///   • EIP-7708 IS live: `Transfer` logs arrive from `0xff…fe`, which has no
///     bytecode, so an `eth_getCode` existence test reports it absent. That
///     test is wrong for a system emitter and the reads below never use it.
///   • `eth_getTransactionCount` takes **two parameters only** — a third
///     nonce-channel argument is refused, where vibenet's node honours one — so
///     no channel control may be built here (§83).
enum PrivacyDevnetIdentity {
    /// The catalog and `Thing.source` name. Family grammar, operator then
    /// chain, matching Base Vibenet and Ethrex Hegotá.
    static let source = "Ethrex Privacy"
    static let seatID = "privacy"
    static let explorer = "https://dora.privacy.ethrex.xyz"
    /// Reachable and deliberately UNUSED: the app posts nothing to it while the
    /// seat is watch-only, so it is NOT in `NetworkReach`'s host list. §531's
    /// lesson, one seat over — a host joins that list the day the app really
    /// reaches it, and not before.
    static let faucetPage = "https://faucet.privacy.ethrex.xyz"
}

enum PrivacyDevnetChain {
    static let chainID: UInt64 = 8141

    /// The genesis hash, which is the ONLY sound reset signal.
    ///
    /// Measured 2026-09-02 on Base vibenet: a reset re-dated genesis while the
    /// **chain id did not change** and the tip climbed past its old high-water,
    /// so a detector built on id or height reads `.same` through a wipe. This is
    /// the third signal, and the only one that cannot be fooled by a chain that
    /// simply kept running.
    static let genesis = "0x7ca0f7358d127dc4a68983050eb88837a5f384225254d1b009fa87fbcd0f2332"

    /// Three nodes, walked in order — one being down is a retry, not an outage.
    static let hosts = ["https://rpc1.privacy.ethrex.xyz",
                        "https://rpc2.privacy.ethrex.xyz",
                        "https://rpc3.privacy.ethrex.xyz"]

    /// EIP-8250's keyed-nonce predeploy. 5 bytes here and on Hegotá.
    static let nonceManager = "0x0000000000000000000000000000000000008250"
    /// EIP-8272's recent-roots predeploy. 144 bytes here, NO CODE on either
    /// sibling — the one contract that makes this seat different.
    static let recentRoots = "0x0000000000000000000000000000000000008272"
}

/// One watched address's reading.
struct PrivacyDevnetAccount: Equatable, Sendable, Identifiable {
    var address: String
    var id: String { address.lowercased() }

    /// Whether the chain answered at all. **Distinct from an empty account**,
    /// and the distinction is the whole of the roster's honesty: a row saying
    /// "couldn't be reached" is an answer, a row silently reading zero is a
    /// lie about somebody's balance.
    var reached = false
    var balanceWei: Decimal?
    var nonce: UInt64?

    /// What the scopes are gated on. Each is "this address really has some",
    /// never "the chain supports it" — a scope present on evidence the address
    /// itself produced.
    var frameCount = 0
    var nullifiers: [Data] = []
    var roots: [PrivacyDevnetRoots.Reference] = []
    var sponsoredCount = 0
    /// The transactions the walk saw, newest first.
    var moves: [PrivacyDevnetLiveState.Move] = []

    var hasFrames: Bool { frameCount > 0 }
    var hasNullifiers: Bool { !nullifiers.isEmpty }
    var hasRoots: Bool { !roots.isEmpty }
    var hasSponsors: Bool { sponsoredCount > 0 }
}

/// The seat's live state — the watch list and what each address reads.
///
/// Held in memory and mirrored to UserDefaults like its siblings, and it lands
/// **no `Thing` at all**: every reading here is live chain state, and a devnet
/// test address has no news. That is why the seat is rowless in `DemoSeedAll`
/// and why its whole demo furnishing is the fixture below.
/// **`@Observable`, NOT `ObservableObject` — and the difference is a bug this
/// shipped with.** The room reads this through `PrivacyDevnetRoomSource`'s
/// static functions, and with `ObservableObject` + `@Published` a read from a
/// static context establishes NO dependency: the demo fixture installs
/// asynchronously, SwiftUI never learns, and the room sits on whatever it
/// composed first — "Reading the chain…", forever, over a fixture that is
/// right there in memory. Reported from a device; it worked in my own testing
/// purely because the install happened to land before the first compose.
/// `@Observable` tracks the property read itself, which is why both sibling
/// seats use it.
@MainActor
@Observable
final class PrivacyDevnetLiveState {
    static let shared = PrivacyDevnetLiveState()

    /// How many log-touched transactions one walk will read.
    ///
    /// 18 exist chain-wide today, so this is headroom rather than a limit — but
    /// it is a real bound, and without it the walk grows with the chain until a
    /// room open costs minutes.
    static let walkCap = 60

    /// Blocks per `eth_getLogs` page. Under the 100,000 that a sibling ethrex
    /// deployment enforces, with room to spare.
    static let walkChunk: UInt64 = 50_000
    /// How many pages one walk will read — a bound on the bound, so a chain
    /// that grows enormous cannot turn one room open into an unbounded scan.
    /// At 50k blocks a page this reaches 2,000,000 blocks; 8141 is at ~15,000.
    static let walkChunkCap = 40

    /// How long a sweep's answers stand before another is worth making.
    ///
    /// **The walk is ~15 seconds** (measured: 21 requests, most of them
    /// sequential transaction reads), so running it on every room open would
    /// make the room feel broken while it re-derived what it already knew. A
    /// devnet with 14 transactions in two weeks does not change inside a
    /// minute.
    static let staleAfter: TimeInterval = 120
    private(set) var readAt: Date?

    private(set) var accounts: [PrivacyDevnetAccount] = []
    private(set) var headSlot: UInt64 = 0
    /// The genesis the chain last reported. A CHANGE here is a reset, and the
    /// only signal that catches one (see `PrivacyDevnetChain.genesis`).
    private(set) var observedGenesis: String?

    /// What the last walk could not read (prd §593d). Empty on every pass today.
    private(set) var walkCut = WalkCut()

    // MARK: - The moments this room owes (prd §598)

    /// Set when a sweep has just watched a transaction THIS PHONE signed turn
    /// out to be real, and cleared by the room once it has said so.
    ///
    /// **A flag rather than a direct `chrome.flash`**, and for Frames' own
    /// reason: a celebration nobody was present for is not a celebration, and
    /// this seat is one chip away from three others, so the moment is claimed
    /// by whoever is actually looking.
    private(set) var firstSettleReady = false
    /// Set when a watched address turns out to have used the pool, for the
    /// first time on this device. A DISCOVERY, never an achievement — this
    /// phone can never spend a one-time key here, since the pool's ABI is not
    /// something this project has (§593).
    private(set) var poolSightReady = false

    /// This phone's own account address, HANDED IN rather than looked up.
    ///
    /// **`privacy-selftest.sh` fails the build if this file so much as names
    /// `PrivacyDevnetKey`, and that guard is right** — this is what every room
    /// open drives, on a timer, with no tap behind it, so the read file stays a
    /// read file and the signing surface stays where a button calls it. The
    /// address is a public string and reading it signs nothing, but the guard
    /// is deliberately coarse and weakening it to let one convenience through
    /// is how a coarse guard becomes no guard.
    ///
    /// So the view that already knows publishes it (`PrivacyDevnetRoomList`),
    /// and a sweep that runs before anything mounted simply has no address —
    /// which costs nothing, because the moment it feeds needs somebody looking
    /// at the room anyway.
    private(set) var mine: String?

    func setMine(_ address: String?) {
        guard mine != address else { return }
        mine = address
    }

    func spendFirstSettle() {
        firstSettleReady = false
        PrivacyDevnetMoments.spendFirstSettle()
    }

    func spendPoolSight() {
        poolSightReady = false
        PrivacyDevnetMoments.spendPoolSight()
    }

    private init() {}

    func account(_ address: String) -> PrivacyDevnetAccount? {
        accounts.first { $0.address.caseInsensitiveCompare(address) == .orderedSame }
    }

    /// Which scopes the room draws for `address`.
    ///
    /// Threads through `PrivacyDevnetSection.present`, so the decision lives in
    /// the Foundation-only file the harness compiles rather than here — which
    /// is why §610's ruling that every scope is always present needed no
    /// change on this side beyond dropping the arguments.
    func sections(for address: String) -> [PrivacyDevnetSection] {
        PrivacyDevnetSection.present()
    }

    func replace(_ accounts: [PrivacyDevnetAccount]) { self.accounts = accounts }
    func setCut(_ cut: WalkCut) { walkCut = cut }
    func setHead(slot: UInt64) { headSlot = slot }
    func setGenesis(_ hash: String?) { observedGenesis = hash }

    /// Whether the chain has been relaunched under this seat's feet.
    ///
    /// **Genesis only.** Not the chain id, which survived a measured reset
    /// unchanged, and not the tip, which climbed past its old high-water in the
    /// same reset. Returns nil rather than false when nothing has been observed
    /// yet — not knowing and knowing it is fine are different answers.
    func wasReset() -> Bool? {
        guard let seen = observedGenesis else { return nil }
        return seen.caseInsensitiveCompare(PrivacyDevnetChain.genesis) != .orderedSame
    }

    // MARK: - The relaunch, recorded so something can SAY it (prd §593d)

    private static let relaunchHashKey = "privacydevnet.genesis.relaunchHash"
    private static let relaunchAtKey = "privacydevnet.genesis.relaunchAt"

    /// Stamp a relaunch on FIRST sight of a given genesis and never again.
    ///
    /// **Re-stamping would move the moment we claim to have noticed forward
    /// forever**, which keeps it permanently inside the news window and makes
    /// it permanently news — Hegotá's own §522 lesson, and the reason this is a
    /// first-sight write rather than an every-pass one.
    private func noteRelaunch(_ hash: String) {
        guard hash.caseInsensitiveCompare(PrivacyDevnetChain.genesis) != .orderedSame
        else { return }
        guard UserDefaults.standard.string(forKey: Self.relaunchHashKey) != hash else { return }
        UserDefaults.standard.set(hash, forKey: Self.relaunchHashKey)
        UserDefaults.standard.set(Date(), forKey: Self.relaunchAtKey)
    }

    /// The relaunch this device has observed, for the notification sweep.
    ///
    /// **A READ, never a claim** (`HegotaLiveState.observedRestart`'s rule): it
    /// consults no ledger and clears nothing, so a sweep on every foreground
    /// costs two `UserDefaults` reads and decides nothing on its own.
    nonisolated static func observedRelaunch() -> (key: String, at: Date)? {
        guard let hash = UserDefaults.standard.string(forKey: relaunchHashKey),
              let at = UserDefaults.standard.object(forKey: relaunchAtKey) as? Date
        else { return nil }
        return (hash, at)
    }

    /// Forget the observation. Used by the demo teardown alone — this seat has
    /// no "accept the new chain" act, because it compares against a SHIPPED
    /// genesis constant rather than a baseline it stored, so there is no
    /// baseline for a person to re-set.
    nonisolated static func forgetRelaunch() {
        UserDefaults.standard.removeObject(forKey: relaunchHashKey)
        UserDefaults.standard.removeObject(forKey: relaunchAtKey)
    }

    func clear() {
        accounts = []
        headSlot = 0
        observedGenesis = nil
        readAt = nil
        walkCut = WalkCut()
        // The PENDING moments go; the once-ever ledger does NOT. Disconnecting
        // does not un-happen your first transaction, and re-watching an
        // address later must not re-fire a moment already spent.
        firstSettleReady = false
        poolSightReady = false
    }
}

/// A balance on this chain, in words (prd §593d).
///
/// **ONE SPELLING, because there were two.** `FaceScopeRail` carried a private
/// copy of exactly this arithmetic and the send sheet needed the same sentence
/// — and two formatters of one balance is how a rail and a form come to
/// disagree about what an account holds, in the room where that is the only
/// number on screen.
///
/// **NEVER MONEY.** Test ETH has no market, so there is no currency symbol, no
/// conversion and no total — §83 in the room whose whole subject is what can
/// and cannot be claimed.
enum PrivacyDevnetMoney {
    /// Four places, which is what a faucet chain's balances need: the drip is
    /// 0.1 ETH and a send is typically a thousandth of it.
    static func line(wei: Decimal) -> String {
        let eth = wei / Decimal(sign: .plus, exponent: 18, significand: 1)
        let n = NSDecimalNumber(decimal: eth).doubleValue
        return "\(n.formatted(.number.precision(.fractionLength(4)))) ETH"
    }
}

/// One JSON-RPC read, walking the three hosts until one answers.
///
/// **READS ONLY.** Every method named here is an `eth_*` read; the harness
/// fails the build if this file ever names a signing or broadcasting verb. Note
/// a JSON-RPC read is itself an HTTP POST, so "no POST" would be the wrong
/// rule — the rule is no `eth_sendRawTransaction`, no signature, no key.
enum PrivacyDevnetRPC {
    /// Returns nil when NO host answered, which callers must keep distinct
    /// from "answered with nothing": an unreached read is not evidence of an
    /// empty account, and collapsing the two draws somebody's balance as zero.
    static func call(method: String, params: [Any]) async -> Any? {
        let body: [String: Any] = ["id": 1, "jsonrpc": "2.0", "method": method, "params": params]
        for host in PrivacyDevnetChain.hosts {
            guard let root = await IngestSupport.postJSON(host, body: body,
                                                          service: PrivacyDevnetIdentity.source)
                    as? [String: Any] else { continue }
            if let result = root["result"], !(result is NSNull) { return result }
            // A host that answered with an ERROR has answered — walking on
            // would ask two more hosts the same malformed question and report
            // "unreachable" for what is really our own bad request.
            if root["error"] != nil { return nil }
        }
        return nil
    }

    /// A hex string as raw bytes, with an odd-length quantity left-padded.
    ///
    /// **The padding matters**: the wire is quantity-encoded, so a real 32-byte
    /// nonce key whose first byte is zero arrives as 63 hex characters, and
    /// dropping the odd nibble would corrupt every byte of it.
    static func hexData(_ s: String) -> Data {
        var t = s.hasPrefix("0x") ? String(s.dropFirst(2)) : s
        if t.count % 2 == 1 { t = "0" + t }
        var out = Data()
        var i = t.startIndex
        while i < t.endIndex {
            let j = t.index(i, offsetBy: 2)
            guard let b = UInt8(t[i..<j], radix: 16) else { return Data() }
            out.append(b); i = j
        }
        return out
    }

    static func hexInt(_ any: Any?) -> UInt64? {
        guard let s = any as? String else { return nil }
        return UInt64(s.hasPrefix("0x") ? String(s.dropFirst(2)) : s, radix: 16)
    }

    /// A hex quantity as a `Decimal`.
    ///
    /// **Not `UInt64`**, and that is measured rather than defensive: an address
    /// on this chain holds 999,997.999 ETH, which is ~1e24 wei and overflows a
    /// `UInt64` by six orders of magnitude. `FramesMoney` learned the same
    /// thing one chain over.
    static func hexWei(_ any: Any?) -> Decimal? {
        guard let s = any as? String else { return nil }
        let digits = s.hasPrefix("0x") ? String(s.dropFirst(2)) : s
        guard !digits.isEmpty else { return nil }
        var total = Decimal(0)
        for ch in digits {
            guard let d = ch.hexDigitValue else { return nil }
            total = total * 16 + Decimal(d)
        }
        return total
    }
}

/// The watch list.
///
/// **The seat registers on the WATCH LIST ALONE**, which is the divergence from
/// Frames worth stating: that seat also registers off a key this phone made,
/// because its chain is days old and making an account is the common path.
/// Here no key exists — the seat is watch-only while the envelope is
/// unreproduced (§593a) — so registering on a key would be registering on a
/// thing that can never be true, and the honest gate is the watch list.
@Observable
final class PrivacyDevnetWatch {
    static let shared = PrivacyDevnetWatch()
    private static let key = "privacydevnet.watch.addresses.v1"

    private var addressList: [String] { didSet { persist() } }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([String].self, from: data) {
            addressList = saved
        } else {
            addressList = []
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(addressList) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    var addresses: [String] { addressList }
    var connected: Bool { !addressList.isEmpty }

    func isWatching(_ address: String) -> Bool {
        addressList.contains { $0.caseInsensitiveCompare(address) == .orderedSame }
    }

    static func isValidAddress(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count == 42, s.hasPrefix("0x") else { return false }
        return s.dropFirst(2).allSatisfy(\.isHexDigit)
    }

    @discardableResult
    func add(_ raw: String) -> Bool {
        let address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidAddress(address), !isWatching(address) else { return false }
        addressList.append(address)
        let book = AddressBook.shared
        if book.entry(for: address) == nil {
            book.setName(WalletStore.shortAddress(address), for: address,
                         networks: [AddressBook.Network.privacyDevnet])
        } else {
            book.addNetwork(AddressBook.Network.privacyDevnet, for: address)
        }
        return true
    }

    func remove(_ address: String) {
        addressList.removeAll { $0.caseInsensitiveCompare(address) == .orderedSame }
    }

    func removeAll() { addressList = [] }

    func name(for address: String) -> String? { AddressBook.shared.name(for: address) }
}

/// Addresses worth watching when you have none of your own.
///
/// **This chain makes suggestions load-bearing rather than a nicety.** It holds
/// 14 type-`0x6` transactions across ~15,000 blocks and only FOUR of them
/// reference a root, so a pasted stranger's address shows a correct blank that
/// reads exactly like a broken feature. Vibenet and Frames offer the same thing
/// for the same reason.
///
/// **Declared ONCE and read by both the setup screen and the empty room.** Two
/// copies of an address is how two screens end up suggesting different things,
/// and the room is where somebody actually hits the wall — the setup screen is
/// a place you pass through, the empty room is where you stand wondering what
/// to do.
///
/// Both were read off `rpc1.privacy.ethrex.xyz` on 2026-09-04 by running the
/// walk itself, and each is here for a DIFFERENT reading: only the first
/// references a root, so it is the only way to see the Roots scope at all
/// without waiting for somebody to use the chain.
enum PrivacyDevnetSuggestions {
    struct Entry: Identifiable, Sendable {
        let address: String
        let title: String
        let detail: String
        var id: String { address }
    }

    static let all: [Entry] = [
        Entry(address: "0x062901d23f7e2d3bf9949c8a8cfd2c7a5ae3f980",
              title: String(localized: "An address that used the pool"),
              detail: String(localized: "Two one-time spend keys, and a proof against a recent snapshot")),
        Entry(address: "0x248ac8584135c94469a90fbb02ba053b17f1cc60",
              title: String(localized: "An address that sent early"),
              detail: String(localized: "Frame transactions from the chain's first hour")),
    ]

    /// The ones not already watched — an offer to watch something you are
    /// already watching is the dead control §83 bans.
    @MainActor
    static var unwatched: [Entry] {
        all.filter { !PrivacyDevnetWatch.shared.isWatching($0.address) }
    }
}

// MARK: - Bridge registration

enum PrivacyDevnetBridge {
    static func registerBridge(store: BridgeStore) {
        let addresses = PrivacyDevnetWatch.shared.addresses
        guard !addresses.isEmpty else { store.remove(PrivacyDevnetIdentity.seatID); return }
        let proof = addresses.count == 1
            ? String(localized: "1 address watched")
            : String(localized: "\(addresses.count) addresses watched")
        // The `can:` lines are the seat's own promise and are held to it: the
        // second says the seat only watches, and `privacy-selftest.sh` fails
        // the build if this file gains a write verb. Both retire together on
        // the day the envelope is reproduced (§593a) — never one without the
        // other, which is the §83 failure in the room whose whole subject is
        // what can and cannot be claimed.
        store.registerConnected(
            id: PrivacyDevnetIdentity.seatID,
            name: PrivacyDevnetIdentity.source,
            proof: proof,
            can: [
                String(localized: "Reads a watched address's balance, the steps each transaction ran, the one-time spend keys it used and which recent snapshot a proof named, on a public devnet testing Ethereum's privacy proposals."),
                // **THIS LINE WAS FALSE FROM §593d TO §602, AND THE COMMENT
                // ABOVE IT SAID SO.** It promised the seat "makes no key,
                // signs nothing and sends nothing" — and §593d gave the room
                // Create, Top up and Send. That comment's own rule is that
                // this line and the catalog's retire TOGETHER, never one
                // without the other; the catalog half was retired and guarded
                // that day, and this half was left standing for eight builds
                // on the ONE surface whose job is saying what a seat can do.
                //
                // Worded as its two siblings word it, because they are the
                // same fact about the same kind of key on the same fork —
                // and the plain-scalar clause matters more here than anywhere,
                // since this is the seat somebody reads while deciding whether
                // a privacy devnet is safe to try.
                String(localized: "Reading needs no key. Sending signs with a key held on this device \u{2014} a plain scalar, not the Secure Enclave, because the test ETH here has no value and the network may be reset without notice."),
                String(localized: "It does not hide who you are. Every transaction on this chain names its sender in the open; what a proof hides is which earlier deposit it is spending."),
            ])
    }

    /// Undone BY NAME, never a blanket wipe.
    static func disconnect(store: BridgeStore) {
        PrivacyDevnetWatch.shared.removeAll()
        Task { @MainActor in PrivacyDevnetLiveState.shared.clear() }
        store.remove(PrivacyDevnetIdentity.seatID)
    }
}

// MARK: - The live read

extension PrivacyDevnetLiveState {
    /// One sweep over every watched address.
    ///
    /// **Reads only, and it never runs in the demo** — `DemoMode` reaches no
    /// network by ruling, and a live sweep here would answer with empty
    /// accounts and overwrite the fixture, drawing the seat as a room with
    /// nothing in it.
    ///
    /// **The head slot comes from `0x4b`, not from `eth_blockNumber`.** They
    /// are not interchangeable: measured, frames runs 5,223 slots ahead of its
    /// own block height, and the whole root-window reading is in slots. Read
    /// via an `eth_call` over init code that executes the single opcode and
    /// returns its stack word, which is the only way to reach it — no RPC
    /// method exposes the slot.
    /// Refresh only if the last answer has gone stale — what the room's own
    /// task calls, so opening it twice in a row costs one sweep.
    ///
    /// **THE DEMO RE-INSTALLS ITS FIXTURE HERE, and without it the room is
    /// permanently stuck.** `DemoSeedAll` runs on demo ENTRY only, this state
    /// is in-memory, and `DemoMode` is sticky across launches — so relaunching
    /// inside a demo leaves the fixture gone AND the live read refused, and the
    /// room says "Reading the chain…" forever over a chain it is not allowed to
    /// read. Reported from a device, then reproduced here by opening the room
    /// on a second launch. `HegotaLiveState.refreshIfStale` had already solved
    /// exactly this and says so in its own comment — I did not read it before
    /// writing this file, which is the whole cost of the bug.
    ///
    /// Idempotent and in-memory: it reaches nothing, which is the rule this
    /// seat inherits.
    func refreshIfStale() async {
        if DemoMode.isActive {
            if accounts.isEmpty { PrivacyDevnetLiveState.seedDemo() }
            return
        }
        if let readAt, Date().timeIntervalSince(readAt) < Self.staleAfter { return }
        await refresh()
    }

    func refresh() async {
        guard !DemoMode.isActive else { return }
        let watched = PrivacyDevnetWatch.shared.addresses
        guard !watched.isEmpty else { return }

        // Genesis first: a relaunch invalidates every reading below it, and
        // knowing that early means the room can say so rather than describing
        // a chain that is gone.
        if let g = await PrivacyDevnetRPC.call(method: "eth_getBlockByNumber",
                                               params: ["0x0", false]) as? [String: Any],
           let hash = g["hash"] as? String {
            setGenesis(hash)
            noteRelaunch(hash)
        }

        // `0x4b` = SLOT. The init code is <op> PUSH1 00 MSTORE PUSH1 20 PUSH1
        // 00 RETURN — one opcode, its word returned. Measured on all three
        // ethrex devnets; the neighbouring `0x4e` is NOT an opcode, which was
        // believed from reading the pool's bytecode and refuted by probing.
        if let word = await PrivacyDevnetRPC.call(
            method: "eth_call",
            params: [["data": "0x4b60005260206000f3"], "latest"]),
           let slot = PrivacyDevnetRPC.hexInt(word) {
            setHead(slot: slot)
        }

        var out: [PrivacyDevnetAccount] = []
        for address in watched {
            var a = PrivacyDevnetAccount(address: address)
            // Two params ONLY. Measured: this node refuses a third
            // nonce-channel argument ("Invalid params: Expected 2 params")
            // where vibenet's honours one, so the feature is per-deployment
            // rather than per-fork and a channel control here would be dead.
            let bal = await PrivacyDevnetRPC.call(method: "eth_getBalance",
                                                  params: [address, "latest"])
            let cnt = await PrivacyDevnetRPC.call(method: "eth_getTransactionCount",
                                                  params: [address, "latest"])
            // `reached` is the two reads answering, NOT the balance being
            // non-zero — an address with nothing in it is a real answer and a
            // host that did not reply is not.
            a.reached = bal != nil || cnt != nil
            a.balanceWei = PrivacyDevnetRPC.hexWei(bal)
            a.nonce = PrivacyDevnetRPC.hexInt(cnt)
            out.append(a)
        }
        // The walk that fills Frames, Nullifiers, Roots and Sponsors. Done
        // ONCE for every watched address rather than per address, because its
        // expensive half — reading every transaction a log touched — is shared.
        if let (walked, cut) = await walkTransactions(for: watched) {
            setCut(cut)
            for i in out.indices {
                if let w = walked[out[i].address.lowercased()] {
                    out[i].frameCount = w.frames
                    out[i].nullifiers = w.nullifiers
                    out[i].roots = w.roots
                    out[i].sponsoredCount = w.sponsored
                    // **Newest first**, which the figures order on. `block` is
                    // Optional, so an unread one sorts LAST rather than to the
                    // beginning of time.
                    out[i].moves = w.moves.sorted { ($0.block ?? 0) > ($1.block ?? 0) }
                }
            }
        }
        replace(out)

        // **THE MOMENTS, OBSERVED HERE AND SAID BY THE ROOM (prd §598).**
        //
        // `seeding` is this install's first completed sweep, and it is what
        // keeps both moments off history: an account that had already sent
        // before this build existed, or an address watched last week that
        // always had spend keys, is recorded in silence rather than announced.
        let seeding = PrivacyDevnetMoments.isFirstRead()
        if PrivacyDevnetMoments.noteNonce(await myNonce(watched: watched),
                                          seeding: seeding) {
            firstSettleReady = true
        }
        if PrivacyDevnetMoments.notePoolSight(
            hasKeys: out.contains(where: { !$0.nullifiers.isEmpty }),
            seeding: seeding) {
            poolSightReady = true
        }
        PrivacyDevnetMoments.markRead()

        readAt = Date()
    }

    /// This phone's own account's nonce — **the only signal this seat has for
    /// "a send of mine landed", and it costs at most one request, once ever.**
    ///
    /// The nonce IS the count of transactions an account signed, incremented
    /// by the chain on INCLUSION, so 0 → non-zero is exactly the transition
    /// Frames watches a pending row make. Building a pending list here to
    /// carry one toast would be a machine larger than the moment.
    ///
    /// Free when the key's address is already watched (the sweep just read
    /// it), one extra `eth_getTransactionCount` when it is not — and asked at
    /// all only while the moment is still owed, so it stops happening the day
    /// it fires.
    private func myNonce(watched: [String]) async -> UInt64? {
        guard PrivacyDevnetMoments.firstSettleOwed(), let mine else { return nil }
        if let known = accounts.first(where: {
            $0.address.caseInsensitiveCompare(mine) == .orderedSame
        })?.nonce { return known }
        guard !watched.contains(where: { $0.caseInsensitiveCompare(mine) == .orderedSame })
        else { return nil }
        let raw = await PrivacyDevnetRPC.call(method: "eth_getTransactionCount",
                                              params: [mine, "latest"])
        return PrivacyDevnetRPC.hexInt(raw)
    }

    /// One frame of a transaction, as the walk saw it.
    ///
    /// **Every field is Optional and nil never means zero.** A budget the wire
    /// did not carry draws an unweighted strip; a status the receipt did not
    /// report must never mark a frame failed. This chain's own spellings are
    /// `gasLimit`/`stateLimit` — Hegotá says `executionGasLimit`/`stateGasLimit`
    /// and Frames says `gasLimit`/`stateGasLimit`, so a reader written for
    /// either sibling gets nil here and draws frames that look budget-less.
    struct Frame: Equatable, Sendable {
        var gasLimit: UInt64?
        var stateLimit: UInt64?
        /// **Never read today.** `eth_getTransactionReceipt` on this chain
        /// carries no per-frame breakdown, so this stays nil and a figure must
        /// not weight or fail a frame off it. Measured on 8141, not assumed.
        var gasUsed: UInt64?
        /// Same: no per-frame status is served. Nil, always, for now.
        var succeeded: Bool?
        /// The frame's own wire fields, read off the SAME `eth_getTransaction
        /// ByHash` payload the budgets come from — zero extra requests
        /// (prd §596). All Optional and nil never claims: the move sheet draws
        /// a step's target, value and mode only where the wire carried them.
        /// Mode 2 is SENDER on this chain (measured, §593c: "non-zero value
        /// only allowed in SENDER mode"); an unknown mode is named by number
        /// rather than given a word it may not mean.
        var mode: UInt64? = nil
        var target: String? = nil
        var valueWeiHex: String? = nil
    }

    /// One transaction, as the walk saw it.
    ///
    /// Carries VALUES rather than only counts, because the Nullifiers scope
    /// groups keys BY TRANSACTION and the Home scope draws the newest moves'
    /// snapshots — both of which need the values on the move rather than only
    /// in the account's flattened union.
    struct Move: Equatable, Sendable, Identifiable {
        var hash: String
        /// Nil when the transaction read carried none — never 0, which would
        /// sort a real transaction to the beginning of time.
        var block: UInt64?
        var frames: [Frame] = []
        var nullifiers: [Data] = []
        var roots: [PrivacyDevnetRoots.Reference] = []
        var sponsored = false
        /// WHO paid, when somebody else did — the receipt's own `payer`
        /// field, kept beside the Bool so the sheet can name the sponsor
        /// instead of saying "somebody" (prd §596). Nil when self-paid or
        /// when the receipt was not read.
        var payer: String? = nil
        /// What the transaction ACTUALLY spent, off the receipt this walk
        /// already fetched for the payer (prd §602) — **zero extra requests**.
        ///
        /// **Transaction level, and only transaction level.** No per-frame
        /// breakdown is served on this chain (measured, §593a), which is why
        /// `Frame.gasUsed` stays permanently nil and no strip segment is ever
        /// weighted or failed by usage. The receipt's own total is a real
        /// number the chain reported, and it was being thrown away — so the
        /// room could say what every transaction was ALLOWED and never what
        /// any of them cost.
        var gasUsed: UInt64? = nil
        var id: String { hash }

        var frameCount: Int { frames.count }
        var nullifierCount: Int { nullifiers.count }
        var rootCount: Int { roots.count }
    }

    struct Walked { var frames = 0; var nullifiers: [Data] = []
                    var roots: [PrivacyDevnetRoots.Reference] = []; var sponsored = 0
                    var moves: [Move] = [] }

    /// **WHAT THE WALK DID NOT READ (prd §593d).**
    ///
    /// A truncated room and a complete one look IDENTICAL from outside — this
    /// repo's oldest recurring defect (§307, §309) — and it bit here in a form
    /// the figures were already guarding against: `PrivacyDevnetFigure`'s own
    /// stated rule is "a truncated list SAYS SO", which every drawing obeyed
    /// while the walk feeding them cut silently. Every count in the room is
    /// derived from the transactions this walk read, so an unreported cut makes
    /// all of them quietly low.
    ///
    /// **Both numbers are facts about the WALK, never about an address.** The
    /// `walkCap` drops the oldest candidates chain-wide, and which of them
    /// belonged to whom is exactly what reading them would have told us — so
    /// attributing a cut to one roster row would be inventing the answer the
    /// cut prevented.
    struct WalkCut: Equatable, Sendable {
        /// Candidate transactions beyond `walkCap` that were never opened.
        var unread = 0
        /// The block the log scan stopped at when `walkChunkCap` bit before the
        /// tip. Nil when the whole chain was scanned, which is every pass today
        /// — 40 chunks of 50,000 covers two million blocks against a tip of
        /// ~17,000. Separate from `unread` because it is strictly worse: those
        /// transactions were never even candidates.
        var scannedTo: UInt64?
        var isEmpty: Bool { unread == 0 && scannedTo == nil }
    }

    /// What each watched address has DONE on this chain.
    ///
    /// **There is no indexer and no `eth_getLogs` filter that answers this**, so
    /// the walk is the cheapest honest shape the chain allows: one all-time log
    /// read, then the transactions those logs sit in, then the receipts of the
    /// ones that turn out to be yours. Measured 2026-09-04 on the real chain —
    /// 32 logs in 1.2s, 18 distinct transactions, 21 requests total for one
    /// address, and it recovers exactly the right shape for the pool
    /// participant (4 frames, 4 nullifiers, 2 roots).
    ///
    /// **STATED CEILING, and it is the reason for every bound below.** A
    /// transaction that emitted NO log is invisible to this walk. That is
    /// currently a small set and it is the honest trade: the alternative is
    /// scanning every block, which is ~15,000 requests today and grows without
    /// limit. It also means the counts are a FLOOR — which is why nothing here
    /// renders as "you have exactly N", and why an absent scope means "we found
    /// none", never "there are none".
    ///
    /// Returns nil when the log read itself failed, which callers keep distinct
    /// from an empty walk: an unreached read must not blank scopes that were
    /// drawing a moment ago.
    func walkTransactions(for watched: [String]) async -> (walked: [String: Walked], cut: WalkCut)? {
        guard !watched.isEmpty else { return ([:], WalkCut()) }
        // **CHUNKED, because an unbounded range is refused by a sibling node
        // ALREADY.** This asked `fromBlock: 0x0, toBlock: latest` with no
        // address filter, which 8141 answers happily today (32 logs, 1.2s) and
        // which Base vibenet's node rejects outright with `query exceeds max
        // block range 100000` — so this is a measurement of what a maturing
        // ethrex deployment does, not a worry about one. The `walkCap` does not
        // help: it is applied AFTER the response arrives, so a refused query
        // returns nil and four scopes go silently absent.
        guard let tipHex = await PrivacyDevnetRPC.call(method: "eth_blockNumber", params: []),
              let tip = PrivacyDevnetRPC.hexInt(tipHex) else { return nil }
        var logs: [[String: Any]] = []
        var from: UInt64 = 0
        var chunks = 0
        while from <= tip && chunks < Self.walkChunkCap {
            let to = min(from &+ Self.walkChunk &- 1, tip)
            guard let page = await PrivacyDevnetRPC.call(
                    method: "eth_getLogs",
                    params: [["fromBlock": "0x" + String(from, radix: 16),
                              "toBlock": "0x" + String(to, radix: 16)]]) as? [[String: Any]]
            // A refused or unreached chunk abandons the WHOLE walk rather than
            // returning a partial one: a half-read chain reports an address as
            // quieter than it is, which is worse than saying nothing.
            else { return nil }
            logs.append(contentsOf: page)
            if to == tip { break }
            from = to &+ 1
            chunks += 1
        }
        // **THE SCAN'S OWN CEILING, said rather than left to be inferred
        // (prd §593d).** If the chunk cap bit before the tip, every block past
        // `from` was never looked at — strictly worse than the candidate cap
        // below, because those transactions were never even candidates. Two
        // million blocks against a tip of ~17,000 means this is nil today, and
        // it is recorded so the day it is not is a sentence rather than a
        // room that has quietly stopped covering recent history.
        var cut = WalkCut()
        if from <= tip { cut.scannedTo = from == 0 ? 0 : from &- 1 }

        // **SORTED, NOT REVERSED.** The first cut called `reverse()` and said
        // in a comment that this kept recent history when the cap bites — a
        // claim that rests entirely on `eth_getLogs` answering oldest-first,
        // which the JSON-RPC spec does not guarantee. A node answering
        // newest-first would make the reverse produce oldest-first, the cap
        // would keep the genesis fixtures, and a busy address would report as
        // quiet: precisely the failure the comment claimed to prevent, silently.
        // Sorting on the block and the log's place in it costs nothing and
        // makes the claim true rather than assumed.
        var newest: [String: (block: UInt64, index: UInt64)] = [:]
        for log in logs {
            guard let h = log["transactionHash"] as? String else { continue }
            let key = (block: PrivacyDevnetRPC.hexInt(log["blockNumber"]) ?? 0,
                       index: PrivacyDevnetRPC.hexInt(log["logIndex"]) ?? 0)
            if let seen = newest[h], seen.block > key.block { continue }
            newest[h] = key
        }
        let ranked = newest.sorted {
            $0.value.block == $1.value.block ? $0.value.index > $1.value.index
                                             : $0.value.block > $1.value.block
        }
        .map(\.key)
        // Counted BEFORE the prefix, or the number is always zero.
        cut.unread = max(0, ranked.count - Self.walkCap)
        let hashes = ranked.prefix(Self.walkCap)

        let wanted = Set(watched.map { $0.lowercased() })
        var out: [String: Walked] = [:]
        for hash in hashes {
            guard let tx = await PrivacyDevnetRPC.call(method: "eth_getTransactionByHash",
                                                       params: [hash]) as? [String: Any],
                  let sender = (tx["sender"] as? String ?? tx["from"] as? String)?.lowercased(),
                  wanted.contains(sender) else { continue }
            var w = out[sender] ?? Walked()
            let before = (nullifiers: w.nullifiers.count, roots: w.roots.count, sponsored: w.sponsored)
            w.frames += (tx["frames"] as? [[String: Any]])?.count ?? 0
            for key in (tx["nonceKeys"] as? [String] ?? []) {
                let data = PrivacyDevnetRPC.hexData(key)
                // `0x0` is the ordinary nonce channel, not a nullifier — see
                // `PrivacyDevnetRoots.isNullifier`. Counting it would light the
                // scope for every address that ever sent anything.
                if PrivacyDevnetRoots.isNullifier(data) { w.nullifiers.append(data) }
            }
            for r in (tx["recentRootReferences"] as? [[String: Any]] ?? []) {
                guard let src = r["sourceId"] as? String,
                      let root = r["root"] as? String,
                      let slot = PrivacyDevnetRPC.hexInt(r["slot"]) else { continue }
                w.roots.append(PrivacyDevnetRoots.Reference(
                    sourceID: PrivacyDevnetRPC.hexData(src), slot: slot,
                    root: PrivacyDevnetRPC.hexData(root)))
            }
            // The receipt is read ONLY for a transaction already known to be
            // yours, which is what keeps the walk's cost proportional to what
            // you watch rather than to the chain.
            var movePayer: String?
            // **ONE RECEIPT, TWO FACTS.** The payer read used to bind `rc`
            // inside its own chained `if`, so the total gas the chain reported
            // was unreachable to everything downstream — a number already in
            // memory, dropped on the floor. Bound once now; the payer test is
            // unchanged and still the only thing that sets `sponsored`.
            var moveGasUsed: UInt64?
            if let rc = await PrivacyDevnetRPC.call(method: "eth_getTransactionReceipt",
                                                    params: [hash]) as? [String: Any] {
                moveGasUsed = PrivacyDevnetRPC.hexInt(rc["gasUsed"])
                if let payer = (rc["payer"] as? String)?.lowercased(), payer != sender {
                    w.sponsored += 1
                    movePayer = payer
                }
            }
            let moveFrames = (tx["frames"] as? [[String: Any]] ?? []).map { f in
                Frame(gasLimit: PrivacyDevnetRPC.hexInt(f["gasLimit"]),
                      stateLimit: PrivacyDevnetRPC.hexInt(f["stateLimit"]),
                      // Both nil, deliberately: no per-frame breakdown is
                      // served on this chain (measured), and a figure must not
                      // weight or fail a frame off a value nobody reported.
                      gasUsed: nil, succeeded: nil,
                      // The frame's own wire fields, off the same payload —
                      // zero extra requests (prd §596). Nil-safe throughout.
                      mode: PrivacyDevnetRPC.hexInt(f["mode"]),
                      target: f["to"] as? String,
                      valueWeiHex: f["value"] as? String)
            }
            w.moves.append(Move(hash: hash,
                                block: PrivacyDevnetRPC.hexInt(tx["blockNumber"]),
                                frames: moveFrames,
                                nullifiers: Array(w.nullifiers.dropFirst(before.nullifiers)),
                                roots: Array(w.roots.dropFirst(before.roots)),
                                sponsored: w.sponsored > before.sponsored,
                                payer: movePayer,
                                gasUsed: moveGasUsed))
            out[sender] = w
        }
        return (out, cut)
    }
}

// MARK: - Demo

extension PrivacyDevnetLiveState {
    /// The demo's own address — the one carrying both nullifiers and a root, so
    /// one account furnishes every scope this seat has.
    ///
    /// A `static let` rather than a literal in `seedDemo` because the room card
    /// names the same address, and two copies of an address in two files is how
    /// a card draws a balance belonging to somebody else's fixture.
    nonisolated static let demoAddress = "0x062901d23f7e2d3bf9949c8a8cfd2c7a5ae3f980"

    /// The demo's account.
    ///
    /// **A FIXTURE, never a read** — `DemoMode` reaches no network by ruling,
    /// and a live sweep here would answer with an empty account and draw the
    /// seat as a room with nothing in it.
    ///
    /// **EVERY FIGURE IS REAL**, read off `rpc1.privacy.ethrex.xyz` on
    /// 2026-09-04. One account rather than Hegotá's two, and that is a fact
    /// about this chain rather than a shortcut: here the coin owners and the
    /// keyed-nonce senders are the SAME population, because the nonce key is a
    /// nullifier the pool emits for the address that spent it.
    nonisolated static func seedDemo() {
        var a = PrivacyDevnetAccount(address: demoAddress)
        a.reached = true
        a.balanceWei = Decimal(string: "448132919986930440")   // 0.448133 ETH
        a.nonce = 1
        a.frameCount = 4
        // The two 32-byte keys off block 13347, which are byte-identical to the
        // pool's own spent-key log topics — the evidence that a keyed nonce is
        // a nullifier on this chain.
        // FOUR, not two: this address has TWO pool transactions, each carrying
        // two keys.
        //
        // **TWO OF THESE WERE FABRICATED AND SHIPPED**, caught in review. The
        // COUNT was measured by running the walk; the VALUES were then written
        // from a different block's census, and the comment here claimed the
        // measurement while standing over invented bytes. All four are now read
        // back off `eth_getTransactionByHash` for the two hashes below —
        // 13347's pair, then 13352's.
        //
        // The lesson is the one that makes eye review useless here: a fixture
        // that LOOKS like a 32-byte key is indistinguishable from one that is,
        // and a confident comment tells the next reader not to check. Read
        // every hex value back, or do not claim it was measured.
        a.nullifiers = [
            Self.hex("0cca26d343c75c5d092b41abc4c7372c0105537e6f5209967fee5bb6b6ca390c"),
            Self.hex("277a116036d2c29207c09c18015780c8e161402d2017d07012147a1d4b7240fe"),
            // CORRECTED 2026-09-04 during the ship review: these two were
            // FABRICATED. Block 13352's real keys are the ones below — read
            // back off `rpc1.privacy.ethrex.xyz` and compared against the
            // transaction the fixture's own `Move` names. The invented pair
            // appeared on neither of this address's two transactions.
            //
            // Third fabricated hex value in the session that wrote this file
            // (the genesis hash and a transaction hash were the others, both
            // caught before commit). A fixture that LOOKS like a 32-byte key is
            // indistinguishable from one that is, which is why every value here
            // has to be read back rather than reviewed by eye.
            Self.hex("1871055c1947afa152d04f00757f94f890efa87190de3d8e481d7c22b6b381e1"),
            Self.hex("1a3f0e61700a2fc8652d33787331f955bff2b1a500426b4dfd83481f5c645ffe"),
        ]
        a.roots = [
            PrivacyDevnetRoots.Reference(
                sourceID: Self.hex("a0dfea37afb843c1fc18cfa21205766b96e6f7c7d7993ab5d5e041e0b1964f54"),
                slot: 0x3431,
                root: Self.hex("2dd32b6609c5a8e80505ac44c5cb8e9f712115c1f63f59b18be08fc9b9250bf4")),
            PrivacyDevnetRoots.Reference(
                sourceID: Self.hex("a0dfea37afb843c1fc18cfa21205766b96e6f7c7d7993ab5d5e041e0b1964f54"),
                slot: 0x3436,
                root: Self.hex("1ea261e94b9f2b02699e293bd4ad36b4c39cf23975b84c4cc39794bb577df422")),
        ]
        // THE TWO REAL TRANSACTIONS, so Activity and Frames draw in the demo
        // rather than saying "nothing yet" under a chip that only exists
        // because the counts above are non-zero. Hashes and shapes are this
        // address's own, off blocks 13352 and 13347 — obtained by running the
        // walk's own path against the live chain, not by hand.
        a.moves = [
            Move(hash: "0xeda9b1c8231c7ba375c831d63655acc813cf8c7d3ac2b095b23e3011d7b2999a",
                 block: 13352,
                 frames: [Frame(gasLimit: 0x4e200, stateLimit: 0),
                          Frame(gasLimit: 0x4e200, stateLimit: 0)],
                 nullifiers: [a.nullifiers[2], a.nullifiers[3]],
                 roots: [a.roots[1]], sponsored: false),
            Move(hash: "0xfa32623718a4ac87bca85daa2f62af32522f4e2f763adec8ac2fbde5aeb5cf0f",
                 block: 13347,
                 frames: [Frame(gasLimit: 0x4e200, stateLimit: 0),
                          Frame(gasLimit: 0x4e200, stateLimit: 0)],
                 nullifiers: [a.nullifiers[0], a.nullifiers[1]],
                 roots: [a.roots[0]], sponsored: false),
        ]
        // Zero, and CORRECT: no transaction measured on this chain carries a
        // `payer` differing from its sender, so the Sponsors chip is absent in
        // the demo exactly as it is on the live chain. Furnishing one would
        // show a reading this chain has never produced.
        a.sponsoredCount = 0

        // **TWO MORE REAL ACCOUNTS (prd §593d, user: "you need to seed the demo
        // with activity so it is present").** One account with two moves left
        // most of the room's figures near-empty. Both below are the chain's own
        // — every hash, key, frame budget, root, balance and nonce read back
        // off `rpc1.privacy.ethrex.xyz` on 2026-09-04, the same rule the
        // fixture above already enforces — and each furnishes a DIFFERENT
        // reading: `b` is the other pool participant, whose two roots (slots
        // 0xaf1/0xaf6) are AGED against the demo head, so the ring shows
        // hollow marks past the edge beside `a`'s live pair; `c` is the
        // chain's first-hour sender, whose keys are the ordinary channel and a
        // NAMED channel (0x81410003) — so it lights Frames and correctly does
        // NOT light Nullifiers, which is the per-evidence scope rule on
        // display.
        var b = PrivacyDevnetAccount(address: "0x753d91eef10c8e26924aabcb0ad73052f8fc4522")
        b.reached = true
        b.balanceWei = Decimal(string: "447999725722746562")   // 0.448000 ETH
        b.nonce = 1
        b.frameCount = 4
        // **These four include the two the fixture above once misattributed.**
        // They were called fabricated because they appear on neither of THAT
        // address's transactions; they are byte-real on THIS one's (blocks
        // 2787 and 2792), which is where they now live. The harness pins the
        // attribution both ways.
        b.nullifiers = [
            Self.hex("055b6c2720e71fbe4d5fa4ad130f4f7b68879ee7d062d0e21af30c5e8ce5839c"),
            Self.hex("08cda6582e3ed667ed4b907d27093659da30882f1d1437ee86125664ecf6f9ce"),
            Self.hex("060ed959302b15fe85a8e0358e936cb5ca584d174295b603d46d5c3dc1a654d4"),
            Self.hex("19dcb924895a2dc08568ae34801b4a393d9a37a75091b3c0d9c2378f62fe7ae5"),
        ]
        b.roots = [
            PrivacyDevnetRoots.Reference(
                sourceID: Self.hex("b08f15750c491f4cfd65215c11a33b3962903a8896fc586bbd7c697851c26e20"),
                slot: 0xaf1,
                root: Self.hex("2dd32b6609c5a8e80505ac44c5cb8e9f712115c1f63f59b18be08fc9b9250bf4")),
            PrivacyDevnetRoots.Reference(
                sourceID: Self.hex("b08f15750c491f4cfd65215c11a33b3962903a8896fc586bbd7c697851c26e20"),
                slot: 0xaf6,
                root: Self.hex("1ea261e94b9f2b02699e293bd4ad36b4c39cf23975b84c4cc39794bb577df422")),
        ]
        b.moves = [
            Move(hash: "0xb17e6a8292d3ed1f559d7e78f85b62fad2962b589e51ce90eb6462440b6d2a66",
                 block: 2792,
                 frames: [Frame(gasLimit: 0x4e200, stateLimit: 0),
                          Frame(gasLimit: 0x155cc0, stateLimit: 0x86470)],
                 nullifiers: [b.nullifiers[2], b.nullifiers[3]],
                 roots: [b.roots[1]], sponsored: false),
            Move(hash: "0x5ad114d29ed7e9326bbc300b951c6ee9a59c648985dbba9497dfea454cccaa4a",
                 block: 2787,
                 frames: [Frame(gasLimit: 0x4e200, stateLimit: 0),
                          Frame(gasLimit: 0x155cc0, stateLimit: 0x86470)],
                 nullifiers: [b.nullifiers[0], b.nullifiers[1]],
                 roots: [b.roots[0]], sponsored: false),
        ]

        var c = PrivacyDevnetAccount(address: "0x248ac8584135c94469a90fbb02ba053b17f1cc60")
        c.reached = true
        // The chain's own figure for its first-hour sender — a genesis-scale
        // balance, which is what a devnet fixture account holds. Real, not
        // rounded to look plausible.
        c.balanceWei = Decimal(string: "999999999912820000000000")
        c.nonce = 406
        c.frameCount = 4
        c.moves = [
            Move(hash: "0xd0b667abc741070f0bd46e156ed32848316261a3dcb550bab14db41bce06411b",
                 block: 69,
                 frames: [Frame(gasLimit: 0x13880, stateLimit: 0),
                          Frame(gasLimit: 0x7530, stateLimit: 0x2cd30)],
                 nullifiers: [], roots: [], sponsored: false),
            Move(hash: "0xd4bf5b4d8d71d1cae6c2fe947daaa644f7b5770586f542ebe8ddc09b0040a51e",
                 block: 66,
                 frames: [Frame(gasLimit: 0x13880, stateLimit: 0),
                          Frame(gasLimit: 0x7530, stateLimit: 0x2cd30)],
                 nullifiers: [], roots: [], sponsored: false),
        ]

        // **THE DEMO'S HEAD, and it must stay AHEAD of the fixture's roots but
        // inside the window**, or the one card this seat exists for draws
        // nothing. Slot 0x3436 is 13,366; a head of 13,366 + 4,096 puts both
        // roots at half the ring — visibly live, visibly counting down, which
        // is the reading. A head taken from the real chain today (~14,450)
        // would also work now and would silently age out of the window on any
        // demo shown after the fixture is ~27 hours old in slot terms.
        let head: UInt64 = 0x3436 + (PrivacyDevnetRoots.windowSlots / 2)
        Task { @MainActor in
            PrivacyDevnetLiveState.shared.installDemo([a, b, c], headSlot: head,
                                                genesis: PrivacyDevnetChain.genesis)
        }
    }

    /// The only door that writes accounts without a read. Named by
    /// `demo-selftest.py`'s check M, which pins the whole chain: a fixture
    /// nothing installs furnishes nothing.
    func installDemo(_ accounts: [PrivacyDevnetAccount], headSlot: UInt64, genesis: String) {
        self.accounts = accounts
        self.headSlot = headSlot
        self.observedGenesis = genesis
    }

    /// Undone BY NAME, never a blanket wipe — a dev install may hold a real
    /// watch list under the same seat. `clear()` is the whole of it here only
    /// because this seat holds nothing else: no key, no credential, no rows.
    nonisolated static func teardownDemo() {
        Task { @MainActor in PrivacyDevnetLiveState.shared.clear() }
    }

    nonisolated fileprivate static func hex(_ s: String) -> Data {
        var out = Data(); var t = Substring(s)
        while t.count >= 2 {
            out.append(UInt8(t.prefix(2), radix: 16) ?? 0); t = t.dropFirst(2)
        }
        return out
    }
}
