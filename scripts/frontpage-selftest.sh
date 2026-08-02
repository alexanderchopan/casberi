#!/bin/zsh
# Casberi front-page self-test — verifies the SHIPPED pure logic behind the
# brief's two-column layout (§274, 2026-08-01):
#
#   Casberi/Casberi/GenUI/GenRenderer.swift
#     — genChapterIDs (the Stack's chapter arg, parsed)
#     — GenFrontPage.segments (the refs cut at every chapter opener)
#     — GenFrontPage.headSegmentCount (what spans full width)
#
# GenRenderer.swift is a SwiftUI file thousands of lines deep, so unlike
# wallet-viz-selftest it cannot be compiled as shipped; the three functions
# are EXTRACTED from the shipped source by their own signatures instead —
# never copied into this file — so the harness still cannot pass against
# logic the app doesn't run. The only transformation is stripping `private `
# (a struct's private members are invisible to the driver's top-level code);
# if an extraction pattern stops matching, the compile fails loudly rather
# than asserting nothing.
#
# Why a harness rather than a sim check: the failure mode here is a WRONG
# SPLIT, not a crash — a head that swallows a column block, a sparse brief
# that "qualifies" and stretches one file of modules across 1040pt, a
# streaming prefix that re-segments and moves a settled block. Every one of
# those renders and looks plausible. The only way to know the cuts are right
# is to feed them docs whose seams are known.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/GenUI/GenRenderer.swift"
[[ -f "$SRC" ]] || { echo "✗ $SRC not found"; exit 1; }

# --- drift guards -----------------------------------------------------------
# The split is only honest while BOTH deciders consult the same test: the
# renderer's column layout and the Composer's per-turn width cap. If either
# call site drifts, a doc can get the wide cap with no columns (one file of
# modules stretched wide) or columns crushed into the reading cap.
grep -q 'GenFrontPage(el: el' "$SRC" \
  || { echo "✗ the Stack case no longer routes chapters into GenFrontPage"; exit 1; }
(( $(grep -c 'GenFrontPage\.qualifies(' Casberi/Casberi/Shell/Composer.swift) == 2 )) \
  || { echo "✗ Composer no longer caps both turns via GenFrontPage.qualifies"; exit 1; }

TMP=$(mktemp -d /tmp/frontpage-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- extraction -------------------------------------------------------------
# Each function is cut from its own signature line to the first closing brace
# at that line's indent. `awk` records the signature's indentation and stops
# at the matching close, so a body containing nested braces survives intact.
extract() {  # extract <signature-regex>
  awk -v sig="$1" '
    $0 ~ sig { on=1; match($0, /^ */); ind=RLENGTH }
    on { print }
    on && $0 ~ ("^" sprintf("%*s", ind, "") "}$") && $0 !~ sig { on=0 }
  ' "$SRC"
}

{
  echo "import Foundation"
  extract '^func genChapterIDs'
  echo "enum FP {"
  extract '    private static func segments.refs:' | sed 's/private static func/static func/'
  extract '    private static func headSegmentCount' | sed 's/private static func/static func/'
  echo "}"
} > "$TMP/extracted.swift"

# Extraction produced real bodies, not empty shells.
(( $(grep -c 'func ' "$TMP/extracted.swift") == 3 )) \
  || { echo "✗ extraction drift — expected 3 functions, got:"; cat "$TMP/extracted.swift"; exit 1; }

# MUST be named main.swift (the wallet-viz lesson): with several files on the
# command line, `swift` runs only main.swift's top-level code — named anything
# else the driver compiles and never executes, and the run exits 0 having
# asserted NOTHING.
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ cond: Bool, _ name: String) {
    if cond { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

// ── genChapterIDs ──────────────────────────────────────────────────────────
check(genChapterIDs("hero, themes,notes") == ["hero", "themes", "notes"],
      "chapter arg parses with stray spaces")
check(genChapterIDs("").isEmpty, "empty arg means nobody is a chapter")
check(genChapterIDs("hero,") == ["hero"], "trailing comma mid-stream is not a phantom chapter")

// ── segments: the full brief ───────────────────────────────────────────────
// lede · hero+pair+tmkt (money, glued) · themes · notes · leads+trailing
let full = ["lede", "hero", "pair", "tmkt", "themes", "notes", "l1", "l2", "men"]
let fullCh: Set<String> = ["hero", "themes", "notes", "l1"]
let fullSegs = FP.segments(refs: full, chapters: fullCh)
check(fullSegs == [["lede"], ["hero", "pair", "tmkt"], ["themes"], ["notes"], ["l1", "l2", "men"]],
      "full brief cuts at every chapter opener, glue intact")
check(FP.headSegmentCount(fullSegs) == 2,
      "a lone masthead is not a head — the money story joins it")
check(fullSegs.count - FP.headSegmentCount(fullSegs) >= 2,
      "full brief qualifies (>=2 column blocks)")
check(fullSegs.prefix(2).flatMap { $0 } == ["lede", "hero", "pair", "tmkt"],
      "head = lede + the whole money story (never split)")

// ── segments: no lede (brief opens on the hero) ────────────────────────────
let noLede = ["hero", "pair", "themes", "notes", "l1"]
let noLedeCh: Set<String> = ["themes", "notes", "l1"]   // first id is never a chapter
let noLedeSegs = FP.segments(refs: noLede, chapters: noLedeCh)
check(noLedeSegs == [["hero", "pair"], ["themes"], ["notes"], ["l1"]],
      "hero-first brief keeps hero in the pre-chapter segment")
check(FP.headSegmentCount(noLedeSegs) == 1,
      "a multi-module opening segment is a head on its own")
check(noLedeSegs.count - FP.headSegmentCount(noLedeSegs) >= 2,
      "hero-first brief qualifies")

// ── sparse briefs fall back ────────────────────────────────────────────────
let sparseSegs = FP.segments(refs: ["hero", "notes"], chapters: ["notes"])
check(sparseSegs.count - FP.headSegmentCount(sparseSegs) < 2,
      "hero+notes alone does not qualify — no column has a partner")
let thinSegs = FP.segments(refs: ["lede", "hero", "pair"], chapters: ["hero"])
check(thinSegs.count - FP.headSegmentCount(thinSegs) < 2,
      "masthead+money alone does not qualify")
check(FP.headSegmentCount([]) == 0, "empty doc computes an empty head, no trap")

// ── streaming stability ────────────────────────────────────────────────────
// Refs arrive in order; a settled segment must never re-cut as later refs
// land. Every prefix's segmentation is a prefix of the full segmentation
// (only the LAST segment may still be growing).
var stable = true
for n in 1...full.count {
    let partial = FP.segments(refs: Array(full.prefix(n)), chapters: fullCh)
    for (i, seg) in partial.enumerated() {
        if i < partial.count - 1 && seg != fullSegs[i] { stable = false }
        if i == partial.count - 1 && !fullSegs[i].starts(with: seg) { stable = false }
    }
}
check(stable, "every streaming prefix is a prefix of the settled segmentation")

// ── determinism ────────────────────────────────────────────────────────────
check(FP.segments(refs: full, chapters: fullCh) == fullSegs, "segments is deterministic")

if failures > 0 { print("frontpage-selftest: \(failures) FAILED"); exit(1) }
print("frontpage-selftest: OK — every cut, head and gate answers as designed.")
SWIFT

# swiftc + run, never `swift f1 f2` — the latter compiles the pair as a
# module and executes NOTHING, exiting 0 (re-learned here; the wallet-viz
# harness documents the same trap from its own first run).
swiftc -o "$TMP/selftest" "$TMP/extracted.swift" "$TMP/main.swift"
"$TMP/selftest"
