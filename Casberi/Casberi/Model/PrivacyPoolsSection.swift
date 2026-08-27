import Foundation

/// THE PRIVACY POOLS ROOM'S SCOPE — which of its three readings is on screen
/// (prd §486, 2026-08-26). `WalletSection` (§483) and `VibenetSection` (§482),
/// a third time, in the room that needed it for the same reason and at a
/// tenth the scale.
///
/// **Why this exists.** Reported as *"the 0xbow room looks messy"*, and the
/// mess was arrangement rather than any one drawing. The head stacked SEVEN
/// blocks in one slab — headline, note, holdings, split bar, legend, respond
/// door, cover line, footnote — of which three were grey sentences in three
/// different type tiers at three different positions, which is §315's
/// setup-copy failure arriving in a room head. It said its counts three times
/// over (the headline names the leading state, the note re-counts what is
/// waiting, the legend counts each state again), and it ended in a run-on of
/// up to six `·`-joined clauses.
///
/// **This is a REGROUPING, not a redraw**, on `WalletSection`'s own terms:
/// every block that shipped lands in exactly one scope, so content loss is
/// structurally impossible rather than merely unlikely. What is in the pools
/// and how much cover it has are one reading (`shielded`); the split, its
/// legend and the 0xBow door are one reading (`review`); the deposits and
/// reclaims themselves are the room's feed (`activity`). The footnote is not
/// deleted — its clauses are distributed to the scope each one is about, which
/// is why there is no longer a paragraph of tertiary text under a card.
///
/// **The HEADLINE belongs to no scope** and stays above the control, the way
/// Wallet's crown does: it is the room's identity ("a deposit needs your
/// proof"), and a strip that could scope it away would let you open the room
/// and not be told the one thing it exists to tell you. §349's trouble-leads
/// ranking is therefore untouched.
///
/// **ORDER is events → state → hazard**, and the last part is structural
/// rather than taste (§483): `shielded` and `review` are both CONDITIONAL —
/// a room whose deposits all came back out has no holdings, and a room of
/// pre-§311 deposits has no states — so they sit after the one scope that is
/// always there. A conditional scope in the middle makes every scope after it
/// shift the day it appears, and position was never how you find an alarm
/// anyway: the dot is.
///
/// Foundation-only by design, so `scripts/wallet-rooms-selftest.sh` compiles
/// it WHOLE and unmodified beside the room it scopes. Every failure it catches
/// renders as an ordinary room: a scope offered over an empty page, a
/// remembered scope resolving somewhere nobody chose, or a strip whose order
/// changes between opens.
enum PrivacyPoolsSection: String, CaseIterable, Identifiable, Sendable {
    case activity
    case shielded
    case review

    var id: String { rawValue }

    /// The strip's order. `allCases` already declares it, but the order is a
    /// RULING (see the type's doc) rather than an accident of declaration, so
    /// it is stated where a reader looking for it will find it and where a
    /// self-test can assert it.
    static let order: [PrivacyPoolsSection] = [.activity, .shielded, .review]

    /// Both readings past `activity` depend on the room actually having one.
    /// Stated as data rather than left implicit in `present(…)`, because it is
    /// the whole reason the order ends the way it does.
    var isConditional: Bool { self != .activity }

    var label: String {
        switch self {
        case .activity: return String(localized: "Activity")
        case .shielded: return String(localized: "Shielded")
        case .review:   return String(localized: "Review")
        }
    }

    /// What a scope holds, for the accessibility label and the tooltip. Short
    /// nouns are learnable but not self-explaining, and "Review" in particular
    /// must not read as something YOU do — it is 0xBow's screener ruling on
    /// your deposits, and only one of its states asks anything of you.
    var summary: String {
        switch self {
        case .activity: return String(localized: "Deposits and reclaims, as they happened")
        case .shielded: return String(localized: "What's in the pools, and its cover")
        case .review:   return String(localized: "Where each deposit stands with the screener")
        }
    }

    /// Which scopes have anything to show.
    ///
    /// **EVERY FLAG IS THE SCOPE'S OWN RENDER GATE, SPELLED THE SAME WAY**
    /// (§483's own lesson, learned there from a Risk chip that opened an empty
    /// page): `shielded` is exactly the test `PrivacyPoolsRoom.holdingsLine`
    /// answers nil to, and `review` is exactly what the split and its legend
    /// need between them — the legend draws a state row per segment AND an
    /// unknown row for untagged deposits, so a room with untagged deposits and
    /// no segments still has something to say and still earns the scope.
    ///
    /// Deliberately takes plain Bools rather than the room: the caller does
    /// the reading, this does the deciding, so the rule stays testable without
    /// building a `PrivacyPoolsRoom` at every call site.
    static func present(shielded: Bool, review: Bool) -> [PrivacyPoolsSection] {
        order.filter { section in
            switch section {
            case .activity: return true
            case .shielded: return shielded
            case .review:   return review
            }
        }
    }

    /// Resolve the scope actually shown from the one the person last picked.
    ///
    /// **Falls back to `.activity`, never to "the first present scope"** —
    /// `WalletSection.resolve`'s rule. A remembered scope whose content has
    /// since gone (the last deposit reclaimed, so nothing is shielded any
    /// more) resolves to the room's own feed rather than to an empty page
    /// claiming to be a section.
    static func resolve(_ wanted: PrivacyPoolsSection?,
                        present: [PrivacyPoolsSection]) -> PrivacyPoolsSection {
        guard let wanted, present.contains(wanted) else { return .activity }
        return wanted
    }

    /// Whether the strip is worth drawing at all. One scope is not a control,
    /// it is a label — the §83 dead-control ban. A room of two untagged
    /// deposits is a short list and should look like one.
    static func shows(present: [PrivacyPoolsSection]) -> Bool { present.count > 1 }

    /// Which scope wears the dot.
    ///
    /// **Earned, never mere presence** (§483). A deposit sitting in review is
    /// the NORMAL state of this room — a dot on every one of them is a dot
    /// that fires on ordinary progress and trains you to ignore the one that
    /// matters. The two that light it are the two that need a PERSON: proof
    /// required (nothing moves until you supply it) and declined (the money
    /// sits in the pool until you reclaim it). Both are errands; being in
    /// review is not.
    static func attention(needsProof: Bool, declined: Bool,
                          present: [PrivacyPoolsSection]) -> Set<PrivacyPoolsSection> {
        guard present.contains(.review), needsProof || declined else { return [] }
        return [.review]
    }
}
