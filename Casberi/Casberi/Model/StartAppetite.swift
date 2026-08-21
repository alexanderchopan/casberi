import Foundation

/// Which of the onboarding fork's cards to lead with, given what somebody
/// actually opened while the demo was furnished (prd §422).
///
/// **Why this exists.** Since 2026-08-07 the greeting's own CTA enters the
/// demo, so the fork's main job is catching somebody LEAVING it — and that
/// person is not a blank slate. They have just spent a few minutes opening
/// rooms, and which rooms they opened is the only thing this app knows about
/// what they came for. Drawing the three cards in a fixed order throws that
/// away and asks the question as if nothing had happened.
///
/// **It reorders, it never hides.** All three cards are always drawn, in the
/// same shape and at the same weight — §217's "one decision, not three offers
/// of different weight" is untouched. The only thing that moves is which one
/// is read first, which is what a reader's eye spends on anyway.
///
/// **The mapping is DELIBERATELY PARTIAL, and that is the design.** Four of
/// the catalog's ten categories (Work, Agents, Media, Shopping) argue for no
/// card in particular: a person who read the demo's Linear room has told us
/// nothing about whether their own things live in a folder, a wallet or a
/// feed. Inventing a correspondence for them would be a guess dressed as a
/// preference, so they score nothing and the default order stands. A fork
/// that reorders on no evidence is worse than one that never reorders.
///
/// **Categories, not source names.** Membership comes from
/// `BridgeCatalog.category(forSource:)` — the registry `SourcesTray` already
/// groups by — so a seat added tomorrow is covered the day it lands and
/// there is no hand list here to go stale. The resolver is passed IN rather
/// than called directly, which keeps this file Foundation-only and lets
/// `scripts/start-fork-selftest.sh` compile it whole against no catalog at
/// all.
enum StartAppetite {
    /// One card of the fork. The demo card is not an arm — it is hidden once
    /// the demo has been seen, which is precisely the case this type exists
    /// for, so it can never be in a list this orders.
    enum Arm: String, CaseIterable, Hashable {
        case files, wallet, follow
    }

    /// The order the fork has always drawn in, and the answer whenever there
    /// is no signal — which is the COMMON case, not a fallback: somebody who
    /// skipped the demo, or walked it without opening a single room, gets
    /// exactly the screen §217 shipped.
    static let defaultOrder: [Arm] = [.files, .wallet, .follow]

    /// Catalog category → the arm it argues for, or nil for the four that
    /// argue for none. See the type's doc for why nil is a real answer here
    /// rather than a gap to be filled in later.
    static func arm(forCategory category: String) -> Arm? {
        switch category {
        // Money, in both the categories the catalog splits it across —
        // §322 keeps Wallet and Markets far apart on the wall so the app
        // does not read as crypto-only, but for "what did you come for?"
        // they are one answer.
        case "Wallet", "Markets":  .wallet
        // Somebody else's writing: the two categories whose rooms fill with
        // what other people published.
        case "Social", "Reading":  .follow
        // Your own things. "Life" is the catalog's own bucket for Photos,
        // Schedule, Storage, Mail and People — the miscellany a folder
        // holds — and Notes is what you wrote.
        case "Life", "Notes":      .files
        default:                   nil
        }
    }

    /// The order to draw the fork in.
    ///
    /// Scored by VISIT COUNT rather than by distinct rooms: opening the
    /// wallet room nine times and three market rooms once each are both
    /// "money", and the person who did the former is the one who was
    /// reading rather than browsing.
    ///
    /// The sort is a TOTAL order — score descending, then the default
    /// position — so it is deterministic without relying on `sorted` being
    /// stable (which the standard library does not promise, whatever
    /// `ChipMemory`'s own comment assumes). A fork whose cards reshuffle
    /// between two draws of identical data reads as broken.
    static func order(visits: [String: Int],
                      category: (String) -> String?) -> [Arm] {
        var score: [Arm: Int] = [:]
        for (source, count) in visits where count > 0 {
            guard let name = category(source),
                  let arm = arm(forCategory: name) else { continue }
            score[arm, default: 0] += count
        }
        guard score.values.contains(where: { $0 > 0 }) else { return defaultOrder }
        return defaultOrder.enumerated()
            .sorted { left, right in
                let a = score[left.element] ?? 0
                let b = score[right.element] ?? 0
                if a != b { return a > b }
                return left.offset < right.offset
            }
            .map(\.element)
    }
}
