import Foundation

/// Safe (multisig) asks (2026-07-20) — "anything pending on my Safe",
/// "signatures needed". "safe" alone is far too common a word ("is this
/// safe") to trust bare — requires either the specific word "multisig", or
/// "safe" paired with a queue-shaped word.
enum SafeAsk {
    static func matches(_ raw: String) -> Bool {
        let q = raw.lowercased()
        if q.contains("multisig") { return true }
        guard q.contains("safe") else { return false }
        return q.contains("pending") || q.contains("signature") || q.contains("queue")
    }

    /// nil ONLY when no EVM wallet is watched; no detected Safe, or nothing
    /// pending, still answers honestly.
    @MainActor
    static func answer() async -> String? {
        let watched = WalletStore.shared.addresses.map(\.address)
        let addresses = await WalletIngest.resolvedAddresses(watched).filter { ENS.isHexAddress($0) }
        guard !addresses.isEmpty else { return nil }
        // Under the demo, the seeded snapshot the Safe room head reads — the
        // live queue is a reach, and it answered "no Safe detected" beside a
        // room showing one (census 2026-09-05).
        let counts = DemoMode.isActive ? WalletDemoState.safePending
            : await SafeBridge.pendingCounts(addresses: addresses)
        guard !counts.isEmpty else {
            return String(localized: "No Safe wallets detected.")
        }
        let total = counts.values.reduce(0) { $0 + $1.count }
        guard total > 0 else {
            return String(localized: "Nothing pending on your Safe.")
        }
        let head = total == 1
            ? String(localized: "1 signature needed across your Safes.")
            : String(localized: "\(total) signatures needed across your Safes.")
        // WHAT it is and WHO it waits on, when the room head knows — the same
        // sentences the Safe card draws, so the ask and the card cannot say
        // different things about one queue (§349's "the head one line above
        // it said something else"). Costs nothing: `compose` reads the
        // tracking store `SafeBridge.sync` already keeps.
        guard let room = SafeRoomSource.compose(), let lead = room.lead else { return head }
        var out = head + " " + SafeRoom.subject(lead) + " — " + SafeRoom.stateLabel(lead).lowercased() + "."
        // The two standing facts that outrank a queue: funds that can move
        // with no signature at all, and a rule sitting in front of every
        // transaction. Both are free off the same persisted config snapshots.
        if let note = SafeRoom.note(room) { out += " " + note + "." }
        if let guardNote = SafeRoom.guardNote(room) { out += " " + guardNote + "." }
        return out
    }
}
