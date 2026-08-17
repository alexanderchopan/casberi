import Foundation

/// How the sources tray packs whole categories into rows (2026-08-10, user).
///
/// Split out of `SourcesTray` and Foundation-only by design, so
/// `scripts/source-packing-selftest.sh` can compile it WHOLE and unmodified and
/// check it against an exact optimiser. That is the only proof this rule has,
/// and it needs one: the failure it prevents is invisible in a build and in a
/// screenshot — a tray that packs one row worse than it could still renders
/// perfectly, it is just taller, and past the resting cap "taller" means the
/// picker scrolls.
///
/// # The rule: a card is never split, and the rows are packed instead
///
/// A category is drawn as one filled card, so it is placed WHOLE or not at all.
/// The first cut of the card inherited the old cell packing, which let a
/// category run past column five — its tail arrived on the next row as a card
/// with no title holding one chip, cut at the screen edge. Five of eight
/// categories did that on the real corpus. Reversing which one gives way is
/// what makes a continuation, and therefore a nameless box, unrepresentable.
///
/// # The order: CATALOG WHEN IT'S FREE, biggest first when it pays (2026-08-16)
///
/// Placing whole categories into `columns`-slot rows is bin packing, so the
/// order they are offered in decides the row count. Compared against the exact
/// optimum (subset DP) over **39,237 random corpora** — 3–12 categories, up to
/// 45 sources:
///
/// - **biggest first: 0 losses.** It tied the exact optimum every single time.
/// - catalog order: worse on **7.76%**, by up to **two rows** (236pt in the
///   tray's own arithmetic — the difference between resting and scrolling).
///
/// So biggest-first is the optimiser, and the DP was deliberately NOT shipped:
/// it never once won, and it would have cost a scrambled order to run. It
/// lives in the harness instead, where it proves the sort still ties it.
/// **Do not replace this with a cleverer packer without re-running that
/// comparison — there is no room above it to win.**
///
/// But the sort's cost is ORDER CHURN in the one tray whose job is teaching
/// positions: under pure biggest-first, connecting a single source can reorder
/// every group. The same measurement bounds that cost — catalog order TIES the
/// optimum on ~92% of corpora — so both orders are packed and catalog wins
/// every tie. Result: most corpora keep the stable, catalog-familiar order,
/// and the sort kicks in only when it genuinely saves a row, which is the only
/// time it was ever buying anything. The harness pins both halves: still never
/// worse than biggest-first, and catalog order returned whenever it ties.
///
/// Ties inside the sort break on the order given (catalog order), so a packing
/// is deterministic for a given corpus rather than depending on dictionary
/// iteration.
enum SourceRowPacking {
    /// Chips across the phone's grid. The tray's own column count; kept here
    /// because every span and wrap decision below is relative to it.
    static let columns = 5

    /// One category and its members, in the strip's frozen order.
    ///
    /// Named `Block` rather than `Group` on purpose — `SwiftUI.Group` is in
    /// scope throughout the view that draws these, and shadowing it would be a
    /// trap for whoever next reaches for a `Group { }` there.
    struct Block: Equatable {
        let name: String
        let members: [String]

        init(name: String, members: [String]) {
            self.name = name
            self.members = members
        }

        /// Slots this block occupies on ONE chip row. A block bigger than the
        /// grid is full width and wraps inside its own card.
        var span: Int { min(members.count, SourceRowPacking.columns) }

        /// How many chip rows the card is tall. Only an oversized block is >1,
        /// and an oversized block is always alone in its row (it fills the
        /// width), so a row's height is just its tallest block's.
        var chipRows: Int {
            max(1, Int((Double(members.count) / Double(SourceRowPacking.columns)).rounded(.up)))
        }
    }

    /// Pack whole categories into rows of at most `columns` slots.
    ///
    /// `catalog` arrives in catalog order; the returned rows are in packing
    /// order. Empty categories are dropped rather than drawn as an empty card.
    ///
    /// Both orders are packed and CATALOG WINS EVERY TIE — see the type doc.
    /// The comparison is in `chipRows`, the unit the tray's height is paid in,
    /// not `rows.count`: an oversized card makes the two disagree, and height
    /// is the thing the sort exists to buy.
    static func pack(_ catalog: [Block]) -> [[Block]] {
        let blocks = catalog.filter { !$0.members.isEmpty }

        let stable = firstFit(blocks)

        // Biggest first — the optimiser, consulted second. See the type doc.
        let ordered = blocks.indices
            .sorted { a, b in
                blocks[a].members.count == blocks[b].members.count
                    ? a < b
                    : blocks[a].members.count > blocks[b].members.count
            }
            .map { blocks[$0] }
        let sorted = firstFit(ordered)

        return chipRows(stable) <= chipRows(sorted) ? stable : sorted
    }

    /// First-fit over blocks in the order given — the packing itself, shared
    /// by both candidate orders so they can never drift apart.
    private static func firstFit(_ ordered: [Block]) -> [[Block]] {
        var rows: [[Block]] = []
        for block in ordered {
            // An oversized block can share with nobody: it fills the row and
            // wraps inside its own card.
            guard block.members.count <= columns else {
                rows.append([block])
                continue
            }
            // No separate "is this row an oversized one?" test is needed, and
            // one was DELETED here after the harness proved it unreachable: an
            // oversized row's member sum is already greater than `columns`, so
            // the budget below rejects it for every block. Re-adding that guard
            // would be a branch no test can ever reach.
            let fit = rows.firstIndex { row in
                row.reduce(0) { $0 + $1.members.count } + block.members.count <= columns
            }
            if let fit {
                rows[fit].append(block)
            } else {
                rows.append([block])
            }
        }
        return rows
    }

    /// Total chip rows a packing draws — the number the height is paid in, and
    /// what the harness compares against the exact optimum. Distinct from
    /// `rows.count` because one oversized card is several chip rows tall.
    static func chipRows(_ rows: [[Block]]) -> Int {
        rows.reduce(0) { $0 + ($1.map(\.chipRows).max() ?? 1) }
    }

    // MARK: - Where the cluster metrics used to be

    /// Nothing. `rowMetrics` was added and DELETED on 2026-08-16, and this note
    /// is here so the deletion is a decision rather than a gap.
    ///
    /// It computed a per-row chip pitch and a flexible group gap for build
    /// 343's cluster layout — the fix for "the boundary between two groups is
    /// the same gap as the one inside a group". The arithmetic was correct and
    /// the layout it served was wrong: whitespace can only widen the gap
    /// between groups by MOVING the chips, so the column a chip landed in came
    /// to depend on how many chips preceded it in its own row, and a `4|1` row
    /// sat 53px off the `2|2|1` rows above and below it. Reported the same
    /// evening as "more janky for the groups".
    ///
    /// The boundary is a CARVE now — a translucent recess behind each group,
    /// which bounds it without moving anything — so the tray is back on five
    /// equal columns and needs only `SourcesTray.columnWidth`. Do not restore
    /// a per-row pitch here without reading §392a: alignment outranks the
    /// boundary, and a pitch is how alignment gets lost.
}
