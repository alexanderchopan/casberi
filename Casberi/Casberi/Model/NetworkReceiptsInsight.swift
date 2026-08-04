import Foundation

/// The receipts screen's lead (prd §299, 2026-08-04) — "What it actually
/// reached" as one reading instead of a list you have to add up yourself.
///
/// **It composes from what `NetworkLedger` ALREADY stores and nothing else**:
/// one row per host with a count, and the service the screen already resolved
/// for it. No new field, no new request, nothing added to the ledger — which
/// matters more here than anywhere, because the ledger's restraint IS the
/// feature. Its own doc refuses a per-request log ("a behavioural timeline in
/// cleartext UserDefaults"), so there is no requests-over-time chart to build
/// and there should never be one. Counts and names are what's available, and
/// counts and names are what this draws.
///
/// **Grouped by SERVICE, not by host.** The rows below already list hosts; a
/// map of hosts would restate them (§208's "one thing said twice") and would
/// also lie about proportion — a wallet sweep spreads its traffic over five
/// per-chain Alchemy hosts, so per-host cells would show five medium shares
/// where the truth is one large one. A person can act on "the wallet asks
/// most"; they can't act on `base-mainnet.g.alchemy.com`.
///
/// **An undeclared host does NOT get promoted into a big cell.** It is the
/// finding this screen exists for, so the instinct is to make it the largest
/// thing on the card — but area and opacity here mean magnitude and only
/// magnitude (§145's wash rule), and a two-request stranger drawn as the
/// biggest cell is a fake number in service of a true alarm. It carries state
/// in its FILL (attention, not tint), the headline carries the count, and the
/// screen's own "Not on the list" section — which already sorts above
/// everything — carries the row. Three honest signals beat one dishonest area.
enum NetworkReceiptsInsight {

    /// One observed host as the screen already resolved it: the registry's
    /// service where there is one, the recorder's own attribution where the
    /// registry structurally can't have one (a feed you follow, a store you
    /// named), nil where neither — which is the finding.
    struct Row: Equatable {
        let host: String
        let count: Int
        let service: String?
    }

    struct Cell: Identifiable, Equatable {
        /// A service name, an undeclared host, or the folded tail's own label.
        let label: String
        let count: Int
        /// 0…1 against the LARGEST cell, not against the total — the fill is a
        /// comparison between cells, and normalising by the total would leave
        /// every cell nearly transparent as soon as the tail got long.
        let share: Double
        /// False only for a host no registry entry and no attribution claims.
        /// The folded tail is `true`: it holds declared services by
        /// construction (an undeclared host is never folded — see `compose`).
        let declared: Bool
        /// The "N more" cell. Named because it must never be read as a service
        /// — it can't be tapped, and it isn't one thing.
        let isTail: Bool
        var id: String { label }
    }

    struct Reach: Equatable {
        /// Every request recorded in the window, across every host.
        let requests: Int
        /// Distinct DECLARED services. The headline unit, because it's the one
        /// a person can act on; `hosts` stays in the subline.
        let services: Int
        let hosts: Int
        /// Hosts with neither a registry entry nor an accepted attribution.
        let undeclaredHosts: Int
        /// Ranked, at most `UnitTreemap.maxCells`, tail folded.
        let cells: [Cell]
        /// The largest cell's share of ALL requests, for the card's subline.
        /// Nil when the map has nothing to lead with.
        let leadShare: Double?
        var leadLabel: String? { cells.first.map(\.label) }
        var clean: Bool { undeclaredHosts == 0 }
    }

    /// Kept in step with `UnitTreemap.maxCells` by hand — this file is
    /// Foundation-only on purpose (it compiles in `scripts/receipts-insight-selftest.sh`
    /// with no SwiftUI), so it can't read the view's constant.
    static let maxCells = 6

    /// Nil when there is nothing to draw. A fresh install has an empty ledger
    /// and gets no card at all — not a card full of zeros (the room-head rule:
    /// a visualization that can't say anything declines the slot).
    static func compose(rows: [Row]) -> Reach? {
        let live = rows.filter { $0.count > 0 }
        guard !live.isEmpty else { return nil }

        let requests = live.reduce(0) { $0 + $1.count }
        guard requests > 0 else { return nil }

        // Declared rows collapse onto their service; an undeclared host stands
        // alone under its own name, because that host IS the fact worth
        // reporting and merging them into one "unknown" bucket would hide how
        // many distinct strangers were reached.
        var byService: [String: Int] = [:]
        var undeclared: [(String, Int)] = []
        for row in live {
            if let service = row.service {
                byService[service, default: 0] += row.count
            } else {
                undeclared.append((row.host, row.count))
            }
        }

        // Deterministic ordering: count descending, then label ascending. The
        // tie-break is not cosmetic — without it two services on the same
        // count swap places between launches on dictionary order alone, and a
        // card that reshuffles when nothing changed reads as live data.
        var ranked: [(label: String, count: Int, declared: Bool)] =
            byService.map { (label: $0.key, count: $0.value, declared: true) }
            + undeclared.map { (label: $0.0, count: $0.1, declared: false) }
        ranked.sort { $0.count == $1.count ? $0.label < $1.label : $0.count > $1.count }

        // Fold the tail rather than truncating it. A map that silently drops
        // its seventh service looks identical to one with only six — and the
        // tail's own share is a real number worth showing.
        //
        // An UNDECLARED entry is never folded: it is pulled out of the tail
        // and takes the last slot, because the one row this screen exists to
        // surface must not be able to disappear into a "9 more" cell. It keeps
        // its true count, so the area still doesn't lie — it just can't be
        // hidden by rank.
        var head = ranked
        var tail: [(label: String, count: Int, declared: Bool)] = []
        if ranked.count > maxCells {
            head = Array(ranked.prefix(maxCells - 1))
            tail = Array(ranked.dropFirst(maxCells - 1))
            if let hidden = tail.firstIndex(where: { !$0.declared }) {
                // Swap the highest-ranked hidden undeclared entry into the last
                // head slot, and push what it displaced back into the tail.
                let promoted = tail.remove(at: hidden)
                let displaced = head.removeLast()
                head.append(promoted)
                tail.insert(displaced, at: 0)
                tail.sort { $0.count == $1.count ? $0.label < $1.label : $0.count > $1.count }
            }
        }

        let maxCount = max(head.first?.count ?? 1, 1)
        var cells = head.map {
            Cell(label: $0.label, count: $0.count,
                 share: Double($0.count) / Double(maxCount),
                 declared: $0.declared, isTail: false)
        }
        if !tail.isEmpty {
            // The tail's summed count can exceed the largest single cell, so
            // its share is clamped — and the view draws it in a neutral fill
            // rather than the magnitude wash anyway. "Everything else" is not
            // a thing with a magnitude, and letting a sum of small services
            // out-shout the biggest one would invert the card's whole claim.
            let rest = tail.reduce(0) { $0 + $1.count }
            cells.append(Cell(label: "\(tail.count) more", count: rest,
                              share: min(Double(rest) / Double(maxCount), 1),
                              declared: true, isTail: true))
        }

        return Reach(requests: requests,
                     services: byService.count,
                     hosts: live.count,
                     undeclaredHosts: undeclared.count,
                     cells: cells,
                     leadShare: cells.first.map { Double($0.count) / Double(requests) })
    }
}
