import Foundation

/// The order of the CATEGORY chips in the source strip — the default that
/// `MainSurface` has carried since 2026-08-11, plus the person's own
/// rearrangement of it (prd §533, 2026-08-29).
///
/// # Why this is a preference and the rest of the strip is not
///
/// Everything else in the strip earns its slot: a source chip is ranked by
/// `ChipMemory` (visits, decaying), "All" is pinned first because it is the
/// baseline, and Pinned sits second because a list you built by hand is
/// useless if you have to hunt for the door to it. The CATEGORY chips alone
/// have never been ranked by anything — they sit in a hand-authored order
/// (user ruling 2026-08-11: "wallet, markets, work, agents, life, social,
/// media, reading, notes, voice, shopping"), because a category is not a room
/// somebody visits, it is a shelf, and a shelf that reshuffles between opens
/// reads as broken. So the only thing deciding that order was a constant, and
/// the person it was decided for is the one holding the phone.
///
/// The learned half is untouched: `computedChips` still ranks SEATS by
/// `ChipMemory` and folds them afterwards, so a folded chip still inherits the
/// position of its best-ranked member — and then this order is applied over
/// the finished list exactly as the constant was. Nothing upstream knows this
/// is configurable, and `ShellChrome.chipOrder` (Mac's ⌘1–⌘9) is derived from
/// the drawn strip, so the shortcuts stay positional against what is on screen
/// for free.
///
/// # Why the reorder is not a drag on the strip itself
///
/// The strip is a horizontal `ScrollView` and a chip's long press is already
/// the §384 room peek, so a drag there would have to win two arbitrations —
/// the one `BoardDragDriver` lost before it was retired, and one against a
/// gesture the strip already answers. It is a settings screen instead, where
/// a native `List` reorder costs no gesture code at all.
///
/// # The two reconcile rules, and why each is load-bearing
///
/// A stored order is a list of names written by a build that is now old, so
/// `current` never trusts it whole:
///
///   * a name NOT in `defaultOrder` is DROPPED. Without this a category
///     renamed out from under the stored list keeps a slot that no chip can
///     ever occupy, and — worse — nothing stops a stored "All" or "Pinned"
///     from claiming a position those two must never be sorted into (they are
///     split off ahead of the sort in `computedChips`, so a stored one would
///     silently do nothing while looking like it should).
///   * a name in `defaultOrder` and MISSING from the stored list is APPENDED,
///     in default order. Without this a category added to the catalog after
///     somebody last rearranged their strip is invisible to this file, falls
///     to `rank`'s `Int.max` tail, and lands behind every category forever
///     with nothing on screen to say why.
///
/// Foundation-only by design, so `scripts/category-order-selftest.sh` compiles
/// it WHOLE and unmodified — the whole of this file's correctness is list
/// arithmetic over strings, and every failure it can have renders as a
/// perfectly ordinary strip in a slightly wrong order.
@MainActor
enum CategoryOrder {
    private static let key = "chips.categoryOrder"

    /// The category strip's default order (user ruling 2026-08-11) — see
    /// `MainSurface.computedChips()` for the reasoning behind each position.
    ///
    /// "Voice" is not a catalog category (it has no offer at all — an
    /// always-on device capability, `KNOWN_NO_CATALOG_SEAT` in
    /// `demo-selftest.py`), so it never folds and never appears in
    /// `CategoryFold`'s own name set, but it is still one of the fixed
    /// positions a person actually sees in the strip. Every catalog category
    /// IS here, and the harness proves it against `BridgeCatalog` rather than
    /// trusting this list to have been updated.
    static let defaultOrder: [String] = [
        "Wallet", "Markets", "Work", "Agents", "Life", "Social",
        "Media", "Reading", "Notes", "Voice", "Shopping",
    ]

    /// The order in force — the stored one reconciled against `defaultOrder`,
    /// or the default when nothing has been rearranged.
    static var current: [String] {
        guard let stored = UserDefaults.standard.stringArray(forKey: key) else {
            return defaultOrder
        }
        return reconcile(stored)
    }

    /// `stored`, made safe to sort by. See the type's own doc for why each
    /// half of this exists. Pure, so the harness can hammer it.
    static func reconcile(_ stored: [String]) -> [String] {
        let known = Set(defaultOrder)
        var kept: [String] = []
        var seen = Set<String>()
        for name in stored where known.contains(name) && seen.insert(name).inserted {
            kept.append(name)
        }
        // Appended in DEFAULT order, not in whatever order they happen to be
        // discovered in, so two devices reconciling the same stored list from
        // the same build always land on the same strip.
        let missing = defaultOrder.filter { !seen.contains($0) }
        return kept + missing
    }

    /// Where `label` sorts. `Int.max` for anything this file has never heard
    /// of — a legacy source, an unresolved seat, a category renamed out from
    /// under `defaultOrder` — which keeps that chip's learned-order position
    /// at the tail, exactly as the constant this replaced did.
    static func rank(of label: String, in order: [String]) -> Int {
        order.firstIndex(of: label) ?? Int.max
    }

    /// Store a rearrangement. Reconciled on the way IN as well as on the way
    /// out, so a screen handing over a list with a stray name in it cannot
    /// persist one.
    static func set(_ order: [String]) {
        let clean = reconcile(order)
        if clean == defaultOrder {
            // Storing the default as if it were a choice would make
            // `isCustom` true for somebody who dragged a chip and dragged it
            // back, and then "Reset" is a control with nothing to do (§83).
            reset()
            return
        }
        UserDefaults.standard.set(clean, forKey: key)
    }

    /// Back to the shipped order.
    static func reset() { UserDefaults.standard.removeObject(forKey: key) }

    /// Whether the person has rearranged the strip — what gates the Reset
    /// control and what the settings row says.
    static var isCustom: Bool { current != defaultOrder }

    #if DEBUG
    private static var seededThisLaunch = false
    /// `-categoryOrder "Life,Wallet,Media"` (or `clear`) seeds a rearranged
    /// strip headlessly — the names given lead, everything else follows in
    /// default order, exactly as a drag would leave it. Runs once per launch,
    /// and BEFORE the first freeze, or the strip it is meant to decide has
    /// already been decided.
    static func seedFromLaunchArgs() {
        guard !seededThisLaunch else { return }
        seededThisLaunch = true
        guard let spec = UserDefaults.standard.string(forKey: "categoryOrder"),
              !spec.isEmpty else { return }
        if spec == "clear" { reset(); return }
        set(spec.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    }
    #endif
}
