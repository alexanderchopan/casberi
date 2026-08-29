#!/bin/zsh
# Casberi sources-tray packing self-test — verifies the SHIPPED row packer
# behind the sources tray's category cards (2026-08-10, user):
#
#   Casberi/Casberi/Model/SourceRowPacking.swift
#     — Block.span / Block.chipRows  (how wide and how tall a category's card is)
#     — pack(_:)                     (whole cards, packed rows; catalog order
#                                     when it ties, biggest first when it pays —
#                                     2026-08-16)
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

# The card is GONE (2026-08-16, user ruling) and these guards protect what
# replaced it. The tray's cells now float directly on a glass sheet, so the
# grouping rests on exactly two things and neither is a container: the sheet is
# glass, and the eyebrow is textPrimary. Lose either and the tray silently
# reverts to the 2026-08-06 bare grid that prompted the card in the first place
# — a wall of icons whose structure has to be read to be seen.
#
# History, so this is not re-litigated by someone reading only the code: from
# 2026-08-10 a category was a filled raised card (DS.surfaceRaised), and that
# was correct while the sheet was opaque. On glass an opaque slab masks the
# material over ~85% of the tray, and the sheet's local value varies with the
# feed behind it, so the same card reads raised over a dark row and recessed
# over a bright one. See SourcesTray's own "Where the card used to be" note.
# The tray is an OVERLAY, not a sheet, since 2026-08-16 (§394). That began as
# a GLASS argument — a sheet presents in its own context and `glassEffect` does
# not reach across it (§393a), so only an overlay could sample the feed.
#
# THE GLASS HALF IS SUPERSEDED (user ruling, commit e19c7507, 2026-08-28): the
# panel paints `DS.surfaceSheet`, the same opaque ink `DSTray` and every other
# content sheet already use. Design law §8 is the reason and it outranks §394's
# preference — glass belongs to the FLOATING layer (composer, FAB, toasts) and
# never to content, and the sources tray is content. So the assertion is
# INVERTED rather than deleted: what must hold now is that the panel is ink and
# has NOT drifted back onto a material.
#
# The OVERLAY half survives the reversal untouched and is the reason this block
# still exists. It never rested on glass alone: a `.sheet` presents in its own
# context, which is what broke the tray's environment and its dismissal, so
# reverting to one silently returns the panel four builds were spent chasing.
OVERLAY="Casberi/Casberi/Shell/SourcesOverlay.swift"
[[ -f "$OVERLAY" ]] \
  || { echo "✗ SourcesOverlay is gone — the tray is presented as a sheet again (§394)"; exit 1; }
grep -q 'DS.surfaceSheet' "$OVERLAY" \
  || { echo "✗ the panel no longer paints DS.surfaceSheet — design law §8: glass is for the"
       echo "  floating layer, and the sources tray is content (user ruling, e19c7507)"; exit 1; }
# Read a COMMENT-STRIPPED copy for the negative half: the file DOCUMENTS the
# reversal by naming the materials it no longer uses, so a guard grepping raw
# source fires on the prose explaining it. Fifth time this repo has paid for
# that (Obsidian, Cursor, ondevice, the glass guard this replaces, here).
sed 's|//.*||' "$OVERLAY" | grep -qE 'glassEffect\(|ultraThinMaterial' \
  && { echo "✗ the panel is back on a material — design law §8 puts glass on the floating"
       echo "  layer only, and this ruling was made once already (e19c7507)"; exit 1; }
grep -q '.sheet(isPresented: \$sourcesOpen)' Casberi/Casberi/Shell/RootShell.swift \
  && { echo "✗ the sources tray is presented as a sheet again — it must stay an overlay (§394)"; exit 1; }
# The environment crash this refactor shipped and caught in the simulator: an
# overlay sits ABOVE the shell's `.environment(...)` injections in the modifier
# chain, so it is as starved as a sheet. Without this the tray dies on open
# with "No Observable object of type BridgeStore found" — a clean compile and
# every static audit green.
grep -q 'rootPresented(SourcesOverlay' Casberi/Casberi/Shell/RootShell.swift \
  || { echo "✗ SourcesOverlay is no longer rootPresented — it will crash on open with no BridgeStore"; exit 1; }
# Scoped to nameBand, NOT a bare file grep: the chip's own name is textPrimary
# when it is the active source (line ~441), so an unscoped grep matches whatever
# the eyebrow does and is a guard that cannot fail.
awk '/private func nameBand/,/^    }/' "$TRAY" | grep -q 'foregroundStyle(DS.textPrimary)' \
  || { echo "✗ the category eyebrow is no longer textPrimary — with no card that ink IS the grouping"; exit 1; }

# The tint was refused twice (2026-08-11, re-asked and re-ruled 2026-08-16):
# DS.tint means SELECTION here (the active chip's ring), so tinted category
# names put selection's colour on eight unselected things.
grep -q 'func nameBand(_ block' "$TRAY" \
  || { echo "✗ the eyebrow moved off its cluster — check the tint ruling still holds"; exit 1; }
awk '/private func nameBand/,/^    }/' "$TRAY" | grep -q 'DS.tint' \
  && { echo "✗ the category eyebrow is tinted — ruled against twice; tint means selection in this tray"; exit 1; }

# ALIGNMENT OUTRANKS THE BOUNDARY (2026-08-16, user — build 343 shipped the
# other way round and was reported the same evening). Every chip in the tray
# must sit on a column shared by every row: one `columnWidth` from the width
# the row is handed, blocks sized to a whole number of those columns, and NO
# flexible width anywhere in between — a block that stretched to fill would
# take its chips off the grid, which is the exact defect. The boundary is a
# translucent carve instead, which bounds a group without moving anything.
grep -q 'static func columnWidth' "$TRAY" \
  || { echo "✗ the tray no longer derives one shared column width — rows can drift off a common grid"; exit 1; }
grep -q 'frame(width: column)' "$TRAY" \
  || { echo "✗ cells are no longer pinned to one column — a 4|1 row would sit off the columns of a 2|2|1 row"; exit 1; }
grep -q 'blockWidth(span:' "$TRAY" \
  || { echo "✗ blocks are no longer a whole number of columns wide — the grid stops being a grid"; exit 1; }
# NO CONTAINER, and this is a NEGATIVE guard now (2026-08-16). Four boundary
# treatments have been tried on this tray and all four were rejected by the
# user: an opaque card (masked the glass), a translucent carve ("makes it
# amateur"), fixed-pitch whitespace clusters (knocked chips off the grid —
# "janky"), and a skipped separator column ("weird … it's odd"). The grouping
# is carried by the bold textPrimary eyebrow and the row rhythm alone. Do not
# add a fifth without a ruling — read §392a/§394 first.
awk '/private func blockView/,/^    }/' "$TRAY" | grep -qE 'glassCarve|surfaceRaised|\.background \{' \
  && { echo "✗ a container is back behind the groups — four have been tried and all four rejected; see §394"; exit 1; }
awk '/private func rowView/,/^    }/' "$TRAY" | grep -q 'Color.clear.frame(width: column)' \
  && { echo "✗ the skipped separator column is back — ruled odd 2026-08-16"; exit 1; }
# The 343 shape, spelled out so it cannot come back by accident.
awk '/private func rowView/,/^    }/' "$TRAY" | grep -q 'groupGap\|metrics.gap' \
  && { echo "✗ a per-row group gap is back — that is build 343's whitespace boundary, which cost column alignment"; exit 1; }

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
// Catalog order ties biggest-first on this corpus (both pack four full rows),
// and CATALOG WINS EVERY TIE (2026-08-16) — so the first catalog category
// leads, NOT the biggest. This is the stability half of the rule: on a tying
// corpus, connecting one more source can no longer reshuffle the whole tray.
expectEq(todayRows.first?.first?.name, "Wallet", "catalog order survives when it ties the optimum")

print("— and the sort still kicks in when catalog order would cost a row")
// Catalog order first-fits [1,3,4,2] into THREE rows ([1,3],[4],[2]) while
// biggest-first finds the two-row packing ([4,1],[3,2]). The sort must win
// here — this is the only case it was ever buying anything, and it is also
// the deterministic pin for the sort-reversed/sort-removed mutations, which
// the random sweep alone catches only probabilistically.
let sortPays = [block("A", 1), block("B", 3), block("C", 4), block("D", 2)]
let sortRows = SourceRowPacking.pack(sortPays)
expectEq(sortRows.count, 2, "the sort saves a row where catalog order loses one")
expectEq(sortRows.first?.first?.name, "C", "and biggest-first order is what's drawn then")

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
