#!/bin/zsh
# Casberi sources-tray packing self-test — verifies the SHIPPED row packer
# behind the sources tray's category cards (2026-08-10, user):
#
#   Casberi/Casberi/Model/SourceRowPacking.swift
#     — Block.span / Block.chipRows  (how wide and how tall a category's card is)
#     — pack(_:)                     (whole cards, packed rows, biggest first)
#     — chipRows(_:)                 (the number the tray's height is paid in)
#
# WHY A HARNESS. Every failure here is a SILENT WRONG ANSWER — the class that
# renders perfectly and reads as working. A tray packed one row worse than it
# could be looks completely normal; it is just taller, and past the 620pt
# resting cap "taller" means the picker scrolls, which is the one thing this
# tray has been redesigned three times to avoid. `xcodebuild` cannot see it, a
# screenshot cannot see it, and the screen sweep cannot see it.
#
# THE CLAIM IT DEFENDS, which is the sharpest thing in the file: the shipped
# rule is a three-line sort, and the ONLY evidence it is the right rule is that
# it ties an exact optimiser. So the optimiser is written HERE — a subset DP
# that computes the true minimum row count — and the harness runs the shipped
# packer against it over thousands of random corpora. The DP was deliberately
# not shipped (it never once won, and it would have cost a scrambled category
# order to run); this is where it lives instead, proving the sort still ties it.
# If someone "improves" the packer, this is what tells them they made it worse.
#
# `SourceRowPacking.swift` is Foundation-only BY DESIGN — that is why it is a
# separate type from the view that draws it — so it compiles WHOLE and
# UNMODIFIED here. No extraction, no stubs, no copies: the harness cannot pass
# against logic the app doesn't run.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

PACK="Casberi/Casberi/Model/SourceRowPacking.swift"
TRAY="Casberi/Casberi/Shell/SourcesTray.swift"
for f in "$PACK" "$TRAY"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- drift guards -----------------------------------------------------------
# Wiring the compiled functions cannot prove on their own. A perfect packer is
# worthless if the view stops calling it, or draws it with a different number
# of columns than it packed for.

grep -q 'SourceRowPacking.pack(catalog)' "$TRAY" \
  || { echo "✗ SourcesTray no longer calls SourceRowPacking.pack — the tray packs by some other rule"; exit 1; }

grep -q 'columns = SourceRowPacking.columns' "$TRAY" \
  || { echo "✗ SourcesTray.columns no longer mirrors SourceRowPacking.columns — the view would draw a different grid than the packer packed for"; exit 1; }

# The card is the whole point (a filled container is SEEN rather than read), and
# a fill that quietly becomes clear is the feature silently reverting to the
# 2026-08-06 overline-only tray that prompted this work.
#
# 2026-08-11: moved off DS.surfaceWell onto DS.surfaceRaised — a well is read
# INTO (a chart backing, a media cover), and these cards hold the screen's own
# primary tappable content, so sitting below the page's own plane inverted the
# relationship. The invariant this guard protects (a real fill, not clear) is
# unchanged; only which token supplies it moved.
grep -q 'UnevenRoundedRectangle' "$TRAY" \
  || { echo "✗ SourcesTray no longer draws a per-card shape — a spanning card cannot round only its outer corners without one"; exit 1; }
grep -q 'fill(DS.surfaceRaised)' "$TRAY" \
  || { echo "✗ the category card has no fill — the grouping is back to being read rather than seen"; exit 1; }

# A spanning card is drawn per slot and bridged across the row gap by NEGATIVE
# padding. Without it every multi-category card shows a seam at each column
# boundary, which reads as several small cards rather than one group.
grep -q 'padding(.leading, opensLeading ? 0 : -DS.Space.s2)' "$TRAY" \
  || { echo "✗ the card fill no longer bridges the column gap — a 3-chip category would draw as three separate cards"; exit 1; }

# --- harness ----------------------------------------------------------------
# `SourceRowPacking.swift` compiles as-is. The DP and the fixtures are appended.

cp "$PACK" "$WORK/SourceRowPacking.swift"

cat > "$WORK/main.swift" <<'SWIFT'
import Foundation

var failures = 0
var checks = 0
func expect(_ cond: Bool, _ what: String) {
    checks += 1
    if !cond { failures += 1; print("  ✗ \(what)") }
}
func expectEq<T: Equatable>(_ got: T, _ want: T, _ what: String) {
    checks += 1
    if got != want { failures += 1; print("  ✗ \(what): got \(got), want \(want)") }
}

typealias Block = SourceRowPacking.Block
let COLS = SourceRowPacking.columns

/// Build a category of `n` members with distinct names.
func block(_ name: String, _ n: Int) -> Block {
    Block(name: name, members: (0..<n).map { "\(name)-\($0)" })
}

/// THE EXACT OPTIMISER — deliberately NOT shipped. Minimum total chip rows,
/// by subset DP over the categories that fit a row, plus the forced rows an
/// oversized category takes on its own. This is the number the shipped greedy
/// rule has to tie.
func optimalChipRows(_ catalog: [Block]) -> Int {
    let blocks = catalog.filter { !$0.members.isEmpty }
    let small = blocks.filter { $0.members.count <= COLS }.map(\.members.count)
    let forced = blocks.filter { $0.members.count > COLS }
        .reduce(0) { $0 + $1.chipRows }
    let k = small.count
    guard k > 0 else { return forced }

    var fits = Set<Int>()
    for mask in 1..<(1 << k) {
        var sum = 0
        for i in 0..<k where mask >> i & 1 == 1 { sum += small[i] }
        if sum <= COLS { fits.insert(mask) }
    }

    var memo = [Int: Int]()
    func solve(_ mask: Int) -> Int {
        if mask == 0 { return 0 }
        if let hit = memo[mask] { return hit }
        // Force the lowest set bit into the row we are choosing — kills the
        // permutation symmetry that makes this exponential in practice.
        let low = mask & -mask
        var best = Int.max
        var sub = mask
        while sub > 0 {
            if sub & low != 0, fits.contains(sub) {
                best = min(best, 1 + solve(mask ^ sub))
            }
            sub = (sub - 1) & mask
        }
        memo[mask] = best
        return best
    }
    return forced + solve((1 << k) - 1)
}

// A deterministic PRNG — the harness must fail and pass identically on every
// machine and every run, or a mutation "surviving" means nothing.
struct LCG {
    var state: UInt64
    mutating func next(_ bound: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 33) % UInt64(bound))
    }
}

print("— shape of a single card")
expectEq(block("A", 3).span, 3, "a 3-member card spans 3 slots")
expectEq(block("A", 3).chipRows, 1, "a 3-member card is one chip row tall")
expectEq(block("A", 5).span, 5, "a full-width card spans every slot")
expectEq(block("A", 5).chipRows, 1, "exactly five still fits one chip row")
// The oversized case: a category bigger than the grid can't be a row-mate, so
// it wraps INSIDE its own card rather than splitting into a second nameless one.
expectEq(block("A", 6).span, 5, "an oversized card is clamped to the grid width")
expectEq(block("A", 6).chipRows, 2, "six members wrap to a second chip row")
expectEq(block("A", 10).chipRows, 2, "ten members are exactly two chip rows")
expectEq(block("A", 11).chipRows, 3, "eleven spill to a third")
expectEq(block("A", 1).chipRows, 1, "a single-member card is one row, never zero")
// `pack` filters empty categories, so this floor is only reachable through the
// type's own API — and it is asserted here rather than trusted, because a
// `chipRows` of 0 would collapse a row to nothing in the tray's height
// arithmetic. The harness added this check after a mutation removing the floor
// survived: nothing else in the suite could reach it.
expectEq(Block(name: "Empty", members: []).chipRows, 1,
         "an empty card still reports one chip row, never zero")
expectEq(Block(name: "Empty", members: []).span, 0, "…and spans no slots")

print("— today's real corpus packs to four full rows")
// The shipped catalog order, with the member counts the real corpus has.
let today = [block("Wallet", 3), block("Social", 3), block("Mail", 1),
             block("Media", 2), block("Markets", 5), block("Life", 4),
             block("Work", 1), block("Reading", 1)]
let todayRows = SourceRowPacking.pack(today)
expectEq(todayRows.count, 4, "twenty sources in eight categories pack to four rows")
expectEq(SourceRowPacking.chipRows(todayRows), 4, "and four chip rows")
for row in todayRows {
    expectEq(row.reduce(0) { $0 + $1.members.count }, COLS, "every row is completely full")
}
// Biggest first is the rule, so the largest category must lead.
expectEq(todayRows.first?.first?.name, "Markets", "the biggest category leads")

print("— nothing is ever lost, split, or duplicated")
func members(_ rows: [[Block]]) -> [String] { rows.flatMap { $0.flatMap(\.members) }.sorted() }
expectEq(members(todayRows), today.flatMap(\.members).sorted(),
         "every source survives the packing exactly once")
// The entire point of the redesign: a category appears in ONE row, as ONE card.
var seen = Set<String>()
for row in todayRows {
    for b in row {
        expect(!seen.contains(b.name), "category \(b.name) appears in exactly one row")
        seen.insert(b.name)
    }
}
expectEq(seen.count, today.count, "no category was dropped")

print("— a card is never wider than the grid it sits in")
let oversized = [block("Social", 7), block("Wallet", 1), block("Mail", 1),
                 block("Media", 1), block("Markets", 2), block("Life", 3)]
let overRows = SourceRowPacking.pack(oversized)
for row in overRows {
    expect(row.reduce(0) { $0 + $1.span } <= COLS, "no row spans more than \(COLS) slots")
}
// An oversized card fills the row, so nothing may be filed beside it — a
// one-chip category squeezed in there would land outside the card's own width.
for row in overRows where row.contains(where: { $0.members.count > COLS }) {
    expectEq(row.count, 1, "an oversized card shares its row with nobody")
}

print("— empty categories never draw an empty card")
let withEmpty = [block("Wallet", 2), Block(name: "Ghost", members: []), block("Life", 2)]
let emptyRows = SourceRowPacking.pack(withEmpty)
expect(!emptyRows.flatMap { $0 }.contains { $0.name == "Ghost" },
       "a category with no members is dropped, not drawn")

print("— equal sizes keep catalog order, so a packing is deterministic")
let ties = [block("Aaa", 2), block("Bbb", 2), block("Ccc", 1)]
let tieRows = SourceRowPacking.pack(ties)
expectEq(tieRows.first?.first?.name, "Aaa", "the earlier catalog entry wins a size tie")
expectEq(SourceRowPacking.pack(ties).map { $0.map(\.name) },
         tieRows.map { $0.map(\.name) }, "packing the same corpus twice gives the same answer")

print("— degenerate corpora")
expectEq(SourceRowPacking.pack([]).count, 0, "no categories packs to no rows")
expectEq(SourceRowPacking.pack([block("Only", 1)]).count, 1, "one tiny category is one row")
expectEq(SourceRowPacking.pack([block("Huge", 23)]).count, 1,
         "one enormous category is still one card")
expectEq(SourceRowPacking.chipRows(SourceRowPacking.pack([block("Huge", 23)])), 5,
         "…five chip rows tall")

print("— THE CLAIM: the shipped rule ties the exact optimum")
// This is what the whole harness is for. If a "smarter" packer is ever written,
// this is the check that says whether it actually helped — and if the sort is
// ever removed or reversed, this is what fails.
var rng = LCG(state: 0x5EED_1234)
let sizes = [1, 1, 1, 2, 2, 2, 3, 3, 4, 4, 5, 6, 7]
var trials = 0, losses = 0, worstGap = 0
var worstCase: [Int] = []
for _ in 0..<4000 {
    let k = 3 + rng.next(10)                       // 3–12 categories
    let counts = (0..<k).map { _ in sizes[rng.next(sizes.count)] }
    if counts.reduce(0, +) > 45 { continue }       // beyond any plausible corpus
    trials += 1
    let catalog = counts.enumerated().map { block("c\($0.offset)", $0.element) }
    let got = SourceRowPacking.chipRows(SourceRowPacking.pack(catalog))
    let best = optimalChipRows(catalog)
    expect(got >= best, "the packer can never beat the optimum (would mean the DP is wrong)")
    if got > best {
        losses += 1
        if got - best > worstGap { worstGap = got - best; worstCase = counts }
    }
}
expect(trials > 3000, "the sweep actually ran (got \(trials) trials)")
expectEq(losses, 0, "shipped packer is optimal on all \(trials) corpora"
    + (worstCase.isEmpty ? "" : " — worst \(worstCase) by \(worstGap) row(s)"))

print("— and catalog order genuinely is worse, so the sort is load-bearing")
// If this ever stops finding losses, the sort has become decoration and the
// claim above is no longer evidence of anything.
func packInGivenOrder(_ catalog: [Block]) -> [[Block]] {
    var rows: [[Block]] = []
    for b in catalog where !b.members.isEmpty {
        guard b.members.count <= COLS else { rows.append([b]); continue }
        let fit = rows.firstIndex { row in
            row.allSatisfy { $0.members.count <= COLS }
                && row.reduce(0) { $0 + $1.members.count } + b.members.count <= COLS
        }
        if let fit { rows[fit].append(b) } else { rows.append([b]) }
    }
    return rows
}
var rng2 = LCG(state: 0x5EED_1234)
var naiveLosses = 0, naiveTrials = 0
for _ in 0..<4000 {
    let k = 3 + rng2.next(10)
    let counts = (0..<k).map { _ in sizes[rng2.next(sizes.count)] }
    if counts.reduce(0, +) > 45 { continue }
    naiveTrials += 1
    let catalog = counts.enumerated().map { block("c\($0.offset)", $0.element) }
    if SourceRowPacking.chipRows(packInGivenOrder(catalog)) > optimalChipRows(catalog) {
        naiveLosses += 1
    }
}
expect(naiveLosses > naiveTrials / 50,
       "packing in catalog order is measurably worse (\(naiveLosses)/\(naiveTrials)) — "
     + "if this fails, the biggest-first sort is no longer buying anything")

print("")
if failures == 0 {
    print("✓ source packing: \(checks) checks passed "
        + "(\(trials) corpora vs exact optimum, \(naiveLosses) catalog-order losses avoided)")
} else {
    print("✗ source packing: \(failures) of \(checks) checks FAILED")
}
exit(failures == 0 ? 0 : 1)
SWIFT

swiftc -O -o "$WORK/pack" "$WORK/SourceRowPacking.swift" "$WORK/main.swift" 2>&1 \
  | grep -v '^$' || true
[[ -x "$WORK/pack" ]] || { echo "✗ harness did not compile — SourceRowPacking.swift may no longer be Foundation-only"; exit 1; }
"$WORK/pack"

# --- mutation pass ----------------------------------------------------------
# A check that cannot fail proves nothing. Each mutation is a real bug this
# packer could plausibly acquire; every one must turn the harness RED.

# A mutation must COMPILE and then FAIL. The three outcomes are deliberately
# kept apart, because two of them look like success and aren't:
#   • matched nothing  — the sed is stale after a refactor, so it silently
#     re-tested the shipped source and scored it green;
#   • did not compile  — proves nothing about the assertions, only that Swift
#     rejects the edit.
# Only "compiled, and the checks went red" is evidence.
mutate() {  # name, sed-expression
  local name="$1" expr="$2"
  sed "$expr" "$PACK" > "$WORK/SourceRowPacking.swift"
  if cmp -s "$PACK" "$WORK/SourceRowPacking.swift"; then
    echo "  ✗ MUTATION MATCHED NOTHING (stale): $name"
    MUT_FAIL=1
    return
  fi
  if ! swiftc -O -o "$WORK/mut" "$WORK/SourceRowPacking.swift" "$WORK/main.swift" 2>/dev/null; then
    echo "  ✗ MUTATION DID NOT COMPILE (proves nothing): $name"
    MUT_FAIL=1
    return
  fi
  if "$WORK/mut" >/dev/null 2>&1; then
    echo "  ✗ MUTATION SURVIVED: $name"
    MUT_FAIL=1
  else
    echo "  ✓ caught: $name"
  fi
}

MUT_FAIL=0
echo ""
echo "— mutation pass"

# The headline rule. Reversed, the packer offers smallest first, which is
# strictly worse than catalog order and loses rows on real corpora.
mutate "sort reversed (smallest category first)" \
  's|? a < b|? a > b|; s|blocks\[a\].members.count > blocks\[b\].members.count|blocks[a].members.count < blocks[b].members.count|'

# The sort deleted entirely — packing in catalog order. This is the exact
# regression the 39,237-corpus comparison exists to forbid.
mutate "sort removed (catalog order)" \
  's|blocks\[a\].members.count > blocks\[b\].members.count|false|'

# Off-by-one in the row budget: rows overflow the grid and chips would draw
# outside their own card.
mutate "row budget one too wide" \
  's|+ block.members.count <= columns|+ block.members.count <= columns + 1|'

# The oversized guard removed — a 7-member category would be filed into a
# 5-slot row, silently losing two chips off the end of the grid.
mutate "oversized guard removed" \
  's|guard block.members.count <= columns else {|guard false else {|'

# chipRows rounding down: a 6-member card would claim to be one row tall, and
# the tray would reserve too little height and clip its own second row.
mutate "chipRows rounds down" \
  's|.rounded(.up)|.rounded(.down)|'

# The floor under chipRows: an empty card would report zero rows and collapse
# the row it sits in. Only reachable through the type's own API, which is why
# the suite needed a check aimed straight at it.
mutate "chipRows floor removed" \
  's|max(1, Int((Double(members.count)|max(0, Int((Double(members.count)|'

# span unclamped: an oversized card would claim 7 of 5 slots and the row's
# geometry would run off the screen.
mutate "span unclamped" \
  's|min(members.count, SourceRowPacking.columns)|members.count|'

# Empty categories drawn: a titled card with nothing in it.
mutate "empty categories kept" \
  's|catalog.filter { !\$0.members.isEmpty }|catalog|'

# chipRows measuring a row's WIDTH instead of its height — the two are the same
# number for a full single-row card, which is exactly why the confusion is easy
# to make and impossible to see on today's corpus without this check.
mutate "chipRows measures span, not height" \
  's|\$1.map(\\.chipRows).max()|\$1.map(\\.span).max()|'

# Row reuse disabled, so every category opens its own row. This is option C
# from the mock — the never-share-a-row masonry that measured 816pt in a single
# column, past the resting cap and into a scroll.
mutate "row reuse disabled (a row per category)" \
  's|row.reduce(0) { \$0 + \$1.members.count } + block.members.count <= columns|false|'

cp "$PACK" "$WORK/SourceRowPacking.swift"
echo ""
if [[ $MUT_FAIL -eq 0 ]]; then
  echo "✓ every mutation caught"
else
  echo "✗ a mutation survived — the checks above are weaker than they look"
  exit 1
fi
