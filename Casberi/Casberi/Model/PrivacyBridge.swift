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
///     absent rather than empty (see `PrivacySection`).
///   • EIP-7708 IS live: `Transfer` logs arrive from `0xff…fe`, which has no
///     bytecode, so an `eth_getCode` existence test reports it absent. That
///     test is wrong for a system emitter and the reads below never use it.
///   • `eth_getTransactionCount` takes **two parameters only** — a third
///     nonce-channel argument is refused, where vibenet's node honours one — so
///     no channel control may be built here (§83).
enum PrivacyIdentity {
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

enum PrivacyChain {
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
struct PrivacyAccount: Equatable, Sendable, Identifiable {
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
    var roots: [PrivacyRoots.Reference] = []
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
final class PrivacyLiveState: ObservableObject {
    static let shared = PrivacyLiveState()

    @Published private(set) var accounts: [PrivacyAccount] = []
    @Published private(set) var headSlot: UInt64 = 0
    /// The genesis the chain last reported. A CHANGE here is a reset, and the
    /// only signal that catches one (see `PrivacyChain.genesis`).
    @Published private(set) var observedGenesis: String?

    private init() {}

    func account(_ address: String) -> PrivacyAccount? {
        accounts.first { $0.address.caseInsensitiveCompare(address) == .orderedSame }
    }

    /// Which scopes the room draws for `address`.
    ///
    /// Threads through `PrivacySection.present`, so the decision lives in the
    /// Foundation-only file the harness compiles rather than here.
    func sections(for address: String) -> [PrivacySection] {
        guard let a = account(address) else {
            return PrivacySection.present(frames: false, nullifiers: false,
                                          roots: false, sponsors: false)
        }
        return PrivacySection.present(frames: a.hasFrames, nullifiers: a.hasNullifiers,
                                      roots: a.hasRoots, sponsors: a.hasSponsors)
    }

    func replace(_ accounts: [PrivacyAccount]) { self.accounts = accounts }
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
        return seen.caseInsensitiveCompare(PrivacyChain.genesis) != .orderedSame
    }

    func clear() {
        accounts = []
        headSlot = 0
        observedGenesis = nil
    }
}

// MARK: - Demo

extension PrivacyLiveState {
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
        var a = PrivacyAccount(address: demoAddress)
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
            PrivacyRoots.Reference(
                sourceID: Self.hex("a0dfea37afb843c1fc18cfa21205766b96e6f7c7d7993ab5d5e041e0b1964f54"),
                slot: 0x3431,
                root: Self.hex("2dd32b6609c5a8e80505ac44c5cb8e9f712115c1f63f59b18be08fc9b9250bf4")),
            PrivacyRoots.Reference(
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
        let head: UInt64 = 0x3436 + (PrivacyRoots.windowSlots / 2)
        Task { @MainActor in
            PrivacyLiveState.shared.installDemo([a], headSlot: head,
                                                genesis: PrivacyChain.genesis)
        }
    }

    /// The only door that writes accounts without a read. Named by
    /// `demo-selftest.py`'s check M, which pins the whole chain: a fixture
    /// nothing installs furnishes nothing.
    func installDemo(_ accounts: [PrivacyAccount], headSlot: UInt64, genesis: String) {
        self.accounts = accounts
        self.headSlot = headSlot
        self.observedGenesis = genesis
    }

    /// Undone BY NAME, never a blanket wipe — a dev install may hold a real
    /// watch list under the same seat. `clear()` is the whole of it here only
    /// because this seat holds nothing else: no key, no credential, no rows.
    nonisolated static func teardownDemo() {
        Task { @MainActor in PrivacyLiveState.shared.clear() }
    }

    nonisolated fileprivate static func hex(_ s: String) -> Data {
        var out = Data(); var t = Substring(s)
        while t.count >= 2 {
            out.append(UInt8(t.prefix(2), radix: 16) ?? 0); t = t.dropFirst(2)
        }
        return out
    }
}
