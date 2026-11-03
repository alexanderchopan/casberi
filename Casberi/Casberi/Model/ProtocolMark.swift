import Foundation

/// **WHO DID IT RIDES THE CORNER (prd §1685, user: "i like C b/c if we do B
/// it may mistake the token icon for the token someone interacted with").**
///
/// A wallet row that a protocol carried — a swap on Uniswap, a deposit into
/// Privacy Pools, a lend on Aave — keeps leading with what it DID (§516's
/// action glyph), and the protocol's own mark rides that glyph's corner. The
/// mark never LEADS: a full-size circle at the head of a money row already
/// means "the token" everywhere in the Wallet, and Uniswap's unicorn there
/// would read as UNI.
///
/// This file answers one question: which bundled mark, if any, names the
/// venue a row stamped. It reads STAMPED fields only — the counterparty name
/// ingest set (`transferCounterparty`), Solana's program slot
/// (`transferVenue`) and the seat a row landed from (`source`) — never a
/// title (§363). A venue outside the table gets no badge, never a monogram:
/// a corner monogram would be a second, smaller guess beside the glyph.
///
/// Foundation-only BY DESIGN, so `protocol-mark-selftest.sh` compiles it
/// whole and unmodified.
enum ProtocolMark {

    /// A venue as rows name it, and the `BrandMark` name of its bundled
    /// mark. Matched case-insensitively on the whole name or the name and a
    /// trailing word ("Uniswap V3", "Aave V3", "Aztec staking"), so "Safe"
    /// can never catch "SafePal". Only venues whose mark ships are listed;
    /// `protocol-mark-selftest.sh` fails one whose imageset is missing.
    static let venues: [(name: String, mark: String)] = [
        ("Uniswap", "uniswap"),
        ("Aave", "aave"),
        ("Morpho", "morpho"),
        ("Spark", "spark"),
        ("Privacy Pools", "privacy-pools"),
        ("0xBow", "privacy-pools"),
        ("0xBow Privacy Pools", "privacy-pools"),
        ("Railgun", "railgun"),
        ("Across", "across"),
        ("CoW Protocol", "cowswap"),
        ("CoW Swap", "cowswap"),
        ("Aerodrome", "aerodrome"),
        ("Hyperliquid", "hyperliquid"),
        ("ether.fi", "etherfi"),
        ("1inch", "1inch"),
        ("Relay", "relay"),
        ("Aztec", "aztec"),
        ("Peer", "peer"),
    ]

    /// The mark for one venue name, or nil.
    static func mark(forVenue venue: String?) -> String? {
        guard let venue = venue?.trimmingCharacters(in: .whitespaces).lowercased(),
              !venue.isEmpty else { return nil }
        // Longest name first, so "0xBow Privacy Pools" is never read as "0xBow".
        for entry in venues.sorted(by: { $0.name.count > $1.name.count }) {
            let name = entry.name.lowercased()
            if venue == name || venue.hasPrefix(name + " ") { return entry.mark }
        }
        return nil
    }

    /// The mark for a row: its named counterparty, else its program, else
    /// the seat it landed from. "Wallet" is the chain read itself, never a
    /// venue, so it falls through to nil.
    static func mark(counterparty: String?, venue: String?, source: String?) -> String? {
        mark(forVenue: counterparty) ?? mark(forVenue: venue) ?? mark(forVenue: source)
    }
}
