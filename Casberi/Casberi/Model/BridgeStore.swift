import SwiftUI
import Observation

/// Bridge (app) state, shared across the shell. One store feeds three
/// derivations of the same fact (amendment to brief §7):
///   • the Apps row subline in Account — "3 connected · 1 needs attention"
///   • the breakage row in Feed — "Gmail disconnected", tap opens the fix
///   • the badge on the Account tab icon
/// Rows carry status (principle 6); the state exists once and renders where
/// the person is (P8 — awareness lands, it isn't polled).
@Observable
final class BridgeStore {
    private static let saveKey = "bridges.v1"

    var bridges: [BridgeApp] {
        didSet { persist() }
    }

    /// Saved bridges come back first (real connections survive relaunch);
    /// the demo set seeds dev installs; a fresh user starts with none.
    init(bridges: [BridgeApp]? = nil) {
        if let bridges {
            self.bridges = bridges
        } else if let data = ScratchDefaults.standard.data(forKey: Self.saveKey),
                  let saved = try? JSONDecoder().decode([BridgeApp].self, from: data),
                  !saved.isEmpty {
            self.bridges = saved
        } else {
            self.bridges = DemoState.seedsDemoData ? BridgeApp.demo : []
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(bridges) {
            ScratchDefaults.standard.set(data, forKey: Self.saveKey)
        }
    }

    var attention: [BridgeApp] { bridges.filter { $0.status == .attention } }
    var attentionCount: Int { attention.count }
    var connectedCount: Int { bridges.filter { $0.status == .connected }.count }

    /// The Account tile subline — words only when the seat grid can't speak
    /// (ruling: "1 needs attention" was the ring said twice). A fresh user
    /// gets the invitation; everyone else gets the grid, which IS the fact.
    var summaryLine: String {
        bridges.isEmpty ? "\(BridgeCatalog.offers.count) apps ready to connect" : ""
    }

    /// The one registration path for every bridge: a sync that lands proof
    /// reconnects the bridge if its name is already here, appends a fresh
    /// BridgeApp otherwise. Returns true when the bridge is new — callers
    /// celebrate first connections, not re-syncs.
    @discardableResult
    func registerConnected(id: String, name: String, proof: String,
                           can: [String]) -> Bool {
        if let existing = bridges.first(where: { $0.name == name }) {
            reconnect(existing.id, proof: proof)
            return false
        }
        bridges.append(BridgeApp(id: id, name: name, status: .connected,
                                 statusLine: proof, can: can))
        return true
    }

    /// Reconnects a bridge. `proof` states what landed ("4 screenshots in") —
    /// connect ends in proof; the default is the sync fact.
    func reconnect(_ id: String, proof: String? = nil) {
        guard let i = bridges.firstIndex(where: { $0.id == id }) else { return }
        bridges[i].status = .connected
        bridges[i].statusLine = proof ?? "Synced just now"
        // A fresh credential must not inherit the old one's refusal
        // (2026-08-10). Without this, pasting a new key leaves the stale
        // `authFailedAt` in place and the very next sweep re-flags the seat —
        // telling someone their brand-new key is broken before it has been
        // used once, which is worse than the silence this feature replaced.
        BridgeHealth.forget(bridges[i].name)
    }

    /// Flags a connected bridge as needing attention (access revoked upstream,
    /// a sync that can't proceed) without tearing it down — the honest middle
    /// state between connected and paused.
    func markAttention(_ id: String, statusLine: String) {
        guard let i = bridges.firstIndex(where: { $0.id == id }) else { return }
        bridges[i].status = .attention
        bridges[i].statusLine = statusLine
    }

    func remove(_ id: String) {
        // `bridges` persists and notifies observers on every mutating access,
        // so removing what isn't there costs a full JSON encode and an
        // invalidation for nothing. `reconcileWalletSeats` now calls this for
        // each of nine seats on every foreground, which for a person with no
        // wallet is nine of them (review, 2026-07-30).
        guard let seat = bridges.first(where: { $0.id == id }) else { return }
        BridgeHealth.forget(seat.name)
        bridges.removeAll { $0.id == id }
    }

    /// One catalog seat that RIDES the watched wallets — no account, no key,
    /// no connect switch (prd §207).
    private struct WalletSeat {
        let id: String
        let name: String
        /// How many of the thing this seat's proof line counts, given every
        /// form of every currently-watched wallet. Reads a persisted mark,
        /// never the network — `reconcileWalletSeats` runs on every
        /// foreground and inside several screens' `onAppear`.
        let count: (Set<String>) -> Int
        /// What that number IS, singular ("wallet", "card", "Safe") — pluralised
        /// below. Naming the object beats "wallets" wherever the protocol has
        /// one: "Watching 2 locks" says more than "Watching 1 wallet".
        let noun: String
        let can: [String]
    }

    /// Every wallet-riding seat, and the evidence that lights it.
    ///
    /// These nine have no connect switch: watching a wallet is the whole
    /// consent, and each sweep runs unconditionally inside
    /// `WalletIngest.refresh`. **A seat here gates no requests at all** — it
    /// is pure display, and has been since §207 took the switches away. So
    /// the only question it has to answer is whether the protocol is really
    /// part of this person's life, and each answers it from its own evidence
    /// mark rather than from "a wallet is watched" (see `WalletSeatEvidence`
    /// for why, and for the stamp-never-unstamp rule the sweeps keep).
    ///
    /// Peer and Privacy Pools moved onto that rule on 2026-07-30. They shipped
    /// with the §207 mirror — lit for ANY watched wallet — which claimed a
    /// relationship most people don't have, and made the seat wallpaper for
    /// the ones who do. Gnosis Pay (§222) and Safe already diverged this way;
    /// now there is one rule instead of two, and five more protocols the app
    /// already reads (Aave, Morpho, Hyperliquid, Aerodrome, Uniswap) can wear
    /// a seat honestly without a single extra request.
    private static let walletSeats: [WalletSeat] = [
        WalletSeat(id: "peer", name: "Peer",
                   count: { PeerBridge.evidence.count(in: $0) }, noun: "wallet",
                   can: ["Reads Peer fills for the wallets you watch, from the public chain.",
                         "Read-only — never starts, signs, or settles a trade."]),
        WalletSeat(id: "privacypools", name: "0xBow Privacy Pools",
                   count: { PrivacyPoolsBridge.evidence.count(in: $0) }, noun: "wallet",
                   can: ["Reads Privacy Pools deposits and their screening status for the wallets you watch, from public sources.",
                         "Read-only — never deposits, withdraws, or moves funds."]),
        WalletSeat(id: "altana", name: "Altana",
                   count: { AltanaKeystore.evidence.count(in: $0) }, noun: "wallet",
                   can: ["Reads which keys are allowed to sign for the wallets you watch, from Altana's public keystore.",
                         "Says when a key was granted, when it stops, and when the registry still lists one that can no longer act.",
                         "Read-only — never registers, revokes, or signs."]),
        WalletSeat(id: "railgun", name: "Railgun",
                   count: { RailgunBridge.evidence.count(in: $0) }, noun: "wallet",
                   can: ["Reads what you shield into Railgun and what comes back out, for the wallets you watch, from the public chain.",
                         "Never sees inside the pool — an unshield never names its sender, and relayer sends leave no public trace.",
                         "Read-only — never shields, unshields, or moves funds."]),
        WalletSeat(id: "gnosispay", name: "Gnosis Pay",
                   count: { GnosisPayBridge.evidence.count(in: $0) }, noun: "card",
                   can: ["Reads your Gnosis Pay card spending from Gnosis Chain, for the wallets you watch.",
                         "Amounts and timing only — the merchant never reaches the chain.",
                         "Read-only — never spends, tops up, or freezes a card."]),
        WalletSeat(id: "safe", name: "Safe",
                   count: { _ in SafeBridge.detectedCount() }, noun: "Safe",
                   can: ["Reads the pending signature queue for any Safe you watch, or that watches you as a signer.",
                         "Alerts on a change to a Safe's owners, threshold, or modules.",
                         "Read-only — signing always happens in your own Safe app."]),
        WalletSeat(id: "aave", name: "Aave",
                   count: { WalletDeFi.evidence.count(in: $0) }, noun: "wallet",
                   can: ["Reads your Aave collateral and debt for the wallets you watch, from the public chain.",
                         "Warns when a position drifts close to liquidation.",
                         "Read-only — never supplies, borrows, repays, or withdraws."]),
        WalletSeat(id: "morpho", name: "Morpho",
                   count: { MorphoDeFi.evidence.count(in: $0) }, noun: "wallet",
                   can: ["Reads your Morpho positions and vault deposits for the wallets you watch, from Morpho's public API.",
                         "Warns when a position drifts close to liquidation, and when a vault reallocates.",
                         "Read-only — never supplies, borrows, repays, or withdraws."]),
        WalletSeat(id: "hyperliquid", name: "Hyperliquid",
                   count: { HyperliquidDeFi.evidence.count(in: $0) }, noun: "wallet",
                   can: ["Reads your open positions, spot balances and staked HYPE for the wallets you watch, from Hyperliquid's public API.",
                         "Warns when a position drifts close to liquidation.",
                         "Read-only — never opens, closes, or adjusts a position."]),
        WalletSeat(id: "aerodrome", name: "Aerodrome",
                   count: { AerodromeDeFi.evidence.count(in: $0) }, noun: "wallet",
                   can: ["Reads your veAERO locks for the wallets you watch, from Base's public chain.",
                         "Reminds you before the weekly vote closes, and before a lock expires.",
                         "Read-only — never votes, locks, or claims."]),
        // ONE ether.fi seat, not two (user ruling 2026-07-31). The unstake
        // queue and Cash were seated separately because they're separate
        // products on separate chains — but to a person they are one company
        // and one tile, and two adjacent rows called "ether.fi" and "ether.fi
        // Cash" read as a duplicate, not as a distinction.
        //
        // Counted in WALLETS: the two reads find different evidence (an
        // unstake request is held by any wallet; a Cash account is its own
        // smart account), so the honest shared noun is the thing a person
        // actually watched. A wallet that shows up in either read counts once
        // — hence the union rather than the sum, which would double-count a
        // wallet that both stakes and spends.
        WalletSeat(id: "etherfi", name: "ether.fi",
                   count: { watched in
                       // The same shape `evidence.count(in:)` uses — evidence
                       // addresses filtered by what's watched — over the UNION
                       // of both reads, so a wallet that both stakes and spends
                       // counts once. `remember` already lowercases, and
                       // `watchedForms()` carries both forms of each wallet.
                       Set(EtherFiUnstake.evidence.addresses)
                           .union(EtherFiCash.evidence.addresses)
                           .filter { watched.contains($0) }.count
                   }, noun: "wallet",
                   can: ["Reads your unstake requests from Ethereum and your Cash spending from Optimism, for the wallets you watch.",
                         "Tells you the moment queued ETH becomes claimable.",
                         "Lands each card purchase, and warns when the credit line nears its limit.",
                         "Read-only — never stakes, claims, spends, or borrows."]),
        WalletSeat(id: "uniswap", name: "Uniswap",
                   count: { UniswapLiquidity.evidence.count(in: $0) }, noun: "wallet",
                   can: ["Reads your liquidity positions and uncollected fees for the wallets you watch, from the public chain.",
                         "Tells you when a position moves out of range, and when it comes back.",
                         "Read-only — never swaps, adds, removes, or collects."]),
    ]

    /// Writes the wallet-riding seats' truth — the one place it's written.
    /// Call after any change to the watch list and once per foreground
    /// refresh. Idempotent (`registerConnected` reconnects an existing seat).
    ///
    /// Note the loop: until 2026-07-30 this was a chain of
    /// `guard … else { remove(…); return }`, which meant a person with a Safe
    /// but no Gnosis Pay card never got their Safe seat — the Gnosis Pay guard
    /// returned before Safe was ever considered. Each seat now stands alone.
    func reconcileWalletSeats() {
        let watched = Self.watchedForms()
        for seat in Self.walletSeats {
            // An empty watch list means no wallet-riding seat can be honest,
            // whatever a stale mark says — and `count(in:)` gives that for
            // free, since nothing intersects the empty set.
            let n = seat.count(watched)
            guard n > 0 else { remove(seat.id); continue }
            let proof: String = switch seat.noun {
            case "wallet": String(localized: "Watching \(n) wallet")
            case "card":   String(localized: "Watching \(n) card")
            case "Safe":   String(localized: "Watching \(n) Safe")
            default:       String(localized: "Watching \(n) \(seat.noun)")
            }
            registerConnected(id: seat.id, name: seat.name,
                              proof: proof,
                              can: seat.can)
        }
    }

    /// Every spelling of every watched wallet, lowercased — the typed form
    /// AND its resolved hex, because the two halves of this app disagree on
    /// which one identifies a wallet: `WalletStore` unwatches by what the
    /// person typed, while every sweep stamps its evidence against the
    /// resolved address. Carrying both means a seat's count is right whether
    /// a wallet was added as `vitalik.eth` or as its hex.
    private static func watchedForms() -> Set<String> {
        var out = Set<String>()
        for watch in WalletStore.shared.addresses {
            out.insert(watch.address.lowercased())
            if let hex = WalletStore.shared.resolvedForm(of: watch.address) {
                out.insert(hex.lowercased())
            }
        }
        return out
    }

    func togglePause(_ id: String) {
        guard let i = bridges.firstIndex(where: { $0.id == id }) else { return }
        if bridges[i].status == .paused {
            bridges[i].status = .connected
            bridges[i].statusLine = "Synced just now"
        } else {
            bridges[i].status = .paused
            bridges[i].statusLine = "Paused"
        }
    }

    func setAsk(_ id: String, _ on: Bool) {
        guard let i = bridges.firstIndex(where: { $0.id == id }) else { return }
        bridges[i].askBeforeActing = on
    }
}

struct BridgeApp: Identifiable, Codable {
    enum Status: String, Equatable, Codable {
        case connected, attention, paused
        var rank: Int { switch self { case .attention: 0; case .connected: 1; case .paused: 2 } }
        var color: Color {
            switch self {
            case .connected: DS.confirm
            case .attention: DS.attention
            case .paused:    DS.textTertiary
            }
        }
        /// A shape per state, so the status mark is not hue alone (2026-07-21
        /// Differentiate Without Color pass): a filled dot, a warning triangle,
        /// a hollow pause. Distinguishable in greyscale.
        var glyph: String {
            switch self {
            case .connected: "circle.fill"
            case .attention: "exclamationmark.triangle.fill"
            case .paused:    "pause.circle"
            }
        }
        /// The state, said out loud — the mark is silent otherwise.
        var spoken: String {
            switch self {
            case .connected: String(localized: "Connected")
            case .attention: String(localized: "Needs attention")
            case .paused:    String(localized: "Paused")
            }
        }
    }
    let id: String
    let name: String
    var status: Status
    var statusLine: String
    /// What the bridge can do — sentences, Bob's words (PRD Apps spec).
    var can: [String] = []
    /// Writes ask first, per app; default on (PRD write model).
    var askBeforeActing: Bool = true

    static let demo: [BridgeApp] = [
        .init(id: "gmail", name: "Gmail",     status: .connected, statusLine: "Synced 5m ago",
              can: ["Reads your mail.", "Drafts replies when you ask."]),
        .init(id: "cal",   name: "Calendar",  status: .connected, statusLine: "Synced 2m ago",
              can: ["Reads your calendar.", "Adds events when you ask."]),
        .init(id: "gpt",   name: "ChatGPT",   status: .connected, statusLine: "Synced 1h ago",
              can: ["Brings in your chats.", "Does work when you ask."]),
        .init(id: "rem",   name: "Reminders", status: .paused,    statusLine: "Paused",
              can: ["Reads your reminders.", "Adds reminders when you ask."]),
        .init(id: "pho",   name: "Photos",    status: .paused,    statusLine: "Not connected",
              can: ["Reads screenshots you take."]),
        // Claude chats, imported from the official export (PRD S9 "import"
        // grade) — one chat thing per conversation, kept findable.
        .init(id: "claude", name: "Claude", status: .connected, statusLine: "Synced 1h ago",
              can: ["Brings in your Claude chats.", "Kept findable alongside your things."]),
        // A read bridge for onchain activity (Wallet, on Alchemy). Read-only — it
        // can never trade or move funds; a wallet's swaps/sends/receives just land as things.
        // The status line says SYNC, never an address (2026-08-11). It read
        // "0x1a2b…4f · 4 this week" — a hex nobody watches and a count nothing
        // computed, which is fake status (§83) in a demo whose whole job is to
        // show what the app really does. The room draws every watched wallet as
        // a face directly below this row now, so an address here would be a
        // truncated duplicate of something the rail already says better.
        .init(id: "wallet", name: "Wallet", status: .connected, statusLine: "Synced just now",
              can: ["Reads your wallet's activity.", "Read-only — never trades or moves funds."]),
        // Token-watching, powered by public price data (Dexscreener search,
        // GeckoTerminal/Alchemy candles). Read-only — no wallet, no keys, no trading.
        .init(id: "tokens", name: "Tokens", status: .connected, statusLine: "2 tokens watched",
              can: ["Watches the tokens you add.", "Read-only — public price data only."]),
    ]
        // Every other room the demo corpus furnishes (2026-08-07). Seats and
        // things are seeded together or the Apps catalog contradicts the feed:
        // a room full of rows whose app reads "not connected".
        + DemoSeedAll.seats
}
