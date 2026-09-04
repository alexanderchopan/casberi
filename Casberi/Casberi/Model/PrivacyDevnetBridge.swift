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
@MainActor
final class PrivacyDevnetLiveState: ObservableObject {
    static let shared = PrivacyDevnetLiveState()

    @Published private(set) var accounts: [PrivacyDevnetAccount] = []
    @Published private(set) var headSlot: UInt64 = 0
    /// The genesis the chain last reported. A CHANGE here is a reset, and the
    /// only signal that catches one (see `PrivacyDevnetChain.genesis`).
    @Published private(set) var observedGenesis: String?

    private init() {}

    func account(_ address: String) -> PrivacyDevnetAccount? {
        accounts.first { $0.address.caseInsensitiveCompare(address) == .orderedSame }
    }

    /// Which scopes the room draws for `address`.
    ///
    /// Threads through `PrivacyDevnetSection.present`, so the decision lives in the
    /// Foundation-only file the harness compiles rather than here.
    func sections(for address: String) -> [PrivacyDevnetSection] {
        guard let a = account(address) else {
            return PrivacyDevnetSection.present(frames: false, nullifiers: false,
                                          roots: false, sponsors: false)
        }
        return PrivacyDevnetSection.present(frames: a.hasFrames, nullifiers: a.hasNullifiers,
                                      roots: a.hasRoots, sponsors: a.hasSponsors)
    }

    func replace(_ accounts: [PrivacyDevnetAccount]) { self.accounts = accounts }
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

    func clear() {
        accounts = []
        headSlot = 0
        observedGenesis = nil
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
                String(localized: "Reading needs no key. This seat only ever reads \u{2014} it makes no key, signs nothing and sends nothing."),
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
            // Frames, nullifiers and roots need a transaction walk, which this
            // sweep does NOT do yet — so those three scopes stay absent rather
            // than reading zero. Absent and empty are different claims, and
            // `PrivacyDevnetSection.present` is gated on evidence the address
            // produced rather than on the read having run.
            out.append(a)
        }
        replace(out)
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
        a.frameCount = 2
        // The two 32-byte keys off block 13347, which are byte-identical to the
        // pool's own spent-key log topics — the evidence that a keyed nonce is
        // a nullifier on this chain.
        a.nullifiers = [
            Self.hex("0cca26d343c75c5d092b41abc4c7372c0105537e6f5209967fee5bb6b6ca390c"),
            Self.hex("277a116036d2c29207c09c18015780c8e161402d2017d07012147a1d4b7240fe"),
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
        // Zero, and CORRECT: no transaction measured on this chain carries a
        // `payer` differing from its sender, so the Sponsors chip is absent in
        // the demo exactly as it is on the live chain. Furnishing one would
        // show a reading this chain has never produced.
        a.sponsoredCount = 0

        // **THE DEMO'S HEAD, and it must stay AHEAD of the fixture's roots but
        // inside the window**, or the one card this seat exists for draws
        // nothing. Slot 0x3436 is 13,366; a head of 13,366 + 4,096 puts both
        // roots at half the ring — visibly live, visibly counting down, which
        // is the reading. A head taken from the real chain today (~14,450)
        // would also work now and would silently age out of the window on any
        // demo shown after the fixture is ~27 hours old in slot terms.
        let head: UInt64 = 0x3436 + (PrivacyDevnetRoots.windowSlots / 2)
        Task { @MainActor in
            PrivacyDevnetLiveState.shared.installDemo([a], headSlot: head,
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
