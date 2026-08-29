import Foundation

// MARK: - Discovery

/// One account the explorer itself lists, offered to look at.
struct AltanaDiscoveredAccount: Identifiable, Hashable {
    let address: String
    /// How many credentials the registry holds for it, when a read answered.
    /// Nil is "we did not ask" or "the read did not answer" — never 0, which
    /// is a real and different answer (an account the explorer lists whose
    /// keys have all been revoked).
    let keyCount: Int?
    var id: String { address.lowercased() }
}

/// Where the example accounts come from.
///
/// **The explorer's own `/account/<address>` links are the discriminator, and
/// picking them rather than sweeping the page for hex is the whole of this
/// file's correctness.** Measured 2026-08-28 on the live page: a raw
/// `0x[0-9a-f]{40}` sweep returns **204 distinct addresses** — contracts, key
/// ids, the zero address 86 times — while the `/account/` links return **9**,
/// and calling `getKeys` on BNB for each answered 3, 2, 18, 3, 1, 3, 4, 1, 4:
/// **9 for 9, 39 keys, zero false positives.** Offering the raw sweep would
/// invite somebody to watch a contract address and then show them an empty
/// account, which is §83's confident wrong answer on the screen whose entire
/// job is to prove the seat works.
///
/// **Logs are still a dead end** (§403): public BSC RPCs gate ranged
/// `eth_getLogs`, which is why this reads a page rather than a chain — the
/// same door §403 used to find the accounts it measured.
///
/// **Scrape-grade, with no contract behind it**, so it fails to NOTHING: the
/// link shape moving returns an empty list, and the screen falls back to the
/// fixed account below. `live-integrations.sh` watches the marker nightly,
/// because when a scrape's markup moves the screen does not break, it goes
/// quiet.
enum AltanaDiscovery {
    static let explorer = "https://explorer.altana.network"

    /// A fixed, always-available account to look at — `VibenetDiscoverySection`'s
    /// own fallback rule, and needed more here: this is the ONE thing on the
    /// screen when the explorer cannot be reached, and without it a new arrival
    /// is left with a paste field for a registry they hold no address for.
    ///
    /// The richest of the nine measured (18 of the 39 keys), deliberately: a
    /// peek that opens on an account with one key proves the plumbing and shows
    /// none of the readings — roots against sessions, live against expired,
    /// the hygiene finding §403 built the room around.
    static let peekAddress = "0x561b561ef37874c8e61534be9bae52eb6261ddc4"

    /// A plain `0x`-prefixed 40-hex address — the whole validation, and the
    /// reason it lives HERE rather than on `AltanaWatch`: this file is
    /// Foundation-only by design so a harness can compile it whole, and the
    /// parse below has to reject a link that is not an address.
    ///
    /// Deliberately NOT ENS-resolving: an ENS name resolves to a MAINNET
    /// address, and 38 of the 39 keys measured 2026-08-28 are on BNB, so
    /// resolving would quietly answer a different question than the one asked.
    static func isValidAddress(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count == 42, s.hasPrefix("0x") else { return false }
        return s.dropFirst(2).allSatisfy(\.isHexDigit)
    }

    /// Pure, so the harness can hold the markup still. Separated from the fetch
    /// for exactly that reason — the parse is the half that silently rots.
    static func parse(html: String, limit: Int = 6) -> [AltanaDiscoveredAccount] {
        var out: [AltanaDiscoveredAccount] = []
        var seen = Set<String>()
        var rest = Substring(html)
        let marker = "/account/0x"
        while let hit = rest.range(of: marker), out.count < limit {
            let start = hit.upperBound
            // "0x" is part of the marker, so the hex body follows it directly.
            let body = rest[start...].prefix(40)
            rest = rest[start...]
            guard body.count == 40, body.allSatisfy(\.isHexDigit) else { continue }
            let address = "0x" + String(body)
            guard isValidAddress(address),
                  seen.insert(address.lowercased()).inserted else { continue }
            // `keyCount` nil and NOT looked up here: one read per suggested
            // account, bought to decorate a list somebody may not tap, is the
            // request `VibenetBridge.reference` declines for the same reason.
            // The count arrives when the account is watched and read.
            out.append(AltanaDiscoveredAccount(address: address, keyCount: nil))
        }
        return out
    }
}
