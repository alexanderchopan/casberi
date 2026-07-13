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

    func remove(_ id: String) {
        bridges.removeAll { $0.id == id }
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
        .init(id: "gmail", name: "Gmail",     status: .attention, statusLine: "Reconnect Gmail",
              can: ["Reads your mail.", "Drafts replies when you ask."]),
        .init(id: "cal",   name: "Calendar",  status: .connected, statusLine: "Synced 2m ago",
              can: ["Reads your calendar.", "Adds events when you ask."]),
        .init(id: "gpt",   name: "ChatGPT",   status: .connected, statusLine: "Synced 1h ago",
              can: ["Brings in your chats.", "Does work when you ask."]),
        .init(id: "rem",   name: "Reminders", status: .paused,    statusLine: "Paused",
              can: ["Reads your reminders.", "Adds reminders when you ask."]),
        .init(id: "pho",   name: "Photos",    status: .paused,    statusLine: "Not connected",
              can: ["Reads screenshots you take."]),
        .init(id: "claw",  name: "OpenClaw",  status: .connected, statusLine: "Listening · 3 agents",
              can: ["Brings in what your agents make.", "Their state lands in your feed.", "Approvals reach you here."]),
        // Claude chats, imported from the official export (PRD S9 "import"
        // grade) — one chat thing per conversation, kept findable.
        .init(id: "claude", name: "Claude", status: .connected, statusLine: "Synced 1h ago",
              can: ["Brings in your Claude chats.", "Kept findable alongside your things."]),
        // A read bridge for onchain activity (Wallet, on Alchemy). Read-only — it
        // can never trade or move funds; a wallet's swaps/sends/receives just land as things.
        .init(id: "wallet", name: "Wallet", status: .connected, statusLine: "0x1a2b…4f · 4 this week",
              can: ["Reads your wallet's activity.", "Read-only — never trades or moves funds."]),
        // Token-watching, powered by public price data (Dexscreener search +
        // GeckoTerminal candles). Read-only — no wallet, no keys, no trading.
        .init(id: "dexscreener", name: "Dexscreener", status: .connected, statusLine: "2 tokens watched",
              can: ["Watches the tokens you add.", "Read-only — public price data only."]),
    ]
}
