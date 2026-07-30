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
        } else if let data = UserDefaults.standard.data(forKey: Self.saveKey),
                  let saved = try? JSONDecoder().decode([BridgeApp].self, from: data),
                  !saved.isEmpty {
            self.bridges = saved
        } else {
            self.bridges = DemoState.seedsDemoData ? BridgeApp.demo : []
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(bridges) {
            UserDefaults.standard.set(data, forKey: Self.saveKey)
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
        bridges.removeAll { $0.id == id }
    }

    /// Peer & Privacy Pools ride the watched wallets automatically now (prd
    /// §207, 2026-07-25) — there is no connect switch, so their catalog seat
    /// is a mirror of "is a wallet watched": connected while ≥1 is, gone when
    /// none are. This is the one place that truth is written; call it after
    /// any change to the watch list and once per foreground refresh.
    /// Idempotent (registerConnected reconnects an existing seat).
    func reconcileWalletSeats() {
        let n = WalletStore.shared.addresses.count
        guard n > 0 else {
            remove("peer"); remove("privacypools"); remove("gnosispay"); return
        }
        let watching = "Watching \(n) wallet\(n == 1 ? "" : "s")"
        registerConnected(id: "peer", name: "Peer", proof: watching,
            can: ["Reads Peer fills for the wallets you watch, from the public chain.",
                  "Read-only — never starts, signs, or settles a trade."])
        registerConnected(id: "privacypools", name: "0xBow Privacy Pools", proof: watching,
            can: ["Reads Privacy Pools deposits and their screening status for the wallets you watch, from public sources.",
                  "Read-only — never deposits, withdraws, or moves funds."])
        // Gnosis Pay DIVERGES from its two siblings above (prd §222): its
        // seat is gated on a card spend actually having been seen, not on a
        // wallet merely being watched. Most wallets hold no Gnosis Pay card,
        // and a seat claiming to watch one that doesn't exist is fake status.
        let cards = GnosisPayBridge.accounts().count
        guard cards > 0 else { remove("gnosispay"); return }
        registerConnected(id: "gnosispay", name: "Gnosis Pay",
            proof: "Watching \(cards) card\(cards == 1 ? "" : "s")",
            can: ["Reads your Gnosis Pay card spending from Gnosis Chain, for the wallets you watch.",
                  "Amounts and timing only — the merchant never reaches the chain.",
                  "Read-only — never spends, tops up, or freezes a card."])
        // Safe DIVERGES the same way Gnosis Pay does: gated on an actual
        // detected Safe, not on a wallet merely being watched — most wallets
        // are neither a Safe nor a Safe signer, and a seat claiming
        // otherwise would be fake status.
        let safes = SafeBridge.detectedCount()
        guard safes > 0 else { remove("safe"); return }
        registerConnected(id: "safe", name: "Safe",
            proof: "Watching \(safes) Safe\(safes == 1 ? "" : "s")",
            can: ["Reads the pending signature queue for any Safe you watch, or that watches you as a signer.",
                  "Alerts on a change to a Safe's owners, threshold, or modules.",
                  "Read-only — signing always happens in your own Safe app."])
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
        .init(id: "wallet", name: "Wallet", status: .connected, statusLine: "0x1a2b…4f · 4 this week",
              can: ["Reads your wallet's activity.", "Read-only — never trades or moves funds."]),
        // Token-watching, powered by public price data (Dexscreener search,
        // GeckoTerminal/Alchemy candles). Read-only — no wallet, no keys, no trading.
        .init(id: "tokens", name: "Tokens", status: .connected, statusLine: "2 tokens watched",
              can: ["Watches the tokens you add.", "Read-only — public price data only."]),
    ]
}
