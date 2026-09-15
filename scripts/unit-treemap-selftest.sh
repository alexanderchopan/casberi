#!/bin/zsh
# Casberi unit-treemap self-test — the ONE 4×3 grid table every treemap in the
# app tiles on:
#
#   Casberi/Casberi/Design/UnitTreemap.swift   — `frames(_:)`, `evenFrames(_:)`
#
# RECOVERED 2026-09-15. These checks lived in `scripts/x402-selftest.sh`, which
# was deleted on 2026-09-06 with the Circle x402 seat (prd §638, third
# amendment). The treemap half had nothing to do with x402 — that harness was
# merely where the receipts/x402/topic maps first met — and it went with the
# seat, so for nine days the table the whole app ranks by was unguarded while
# its own doc comments still named a script that no longer existed.
#
# WHY A HARNESS. Every failure here renders as a perfectly convincing map:
#
#   · AREA RISING WITH RANK. The map is rank-ordered, not area-proportional
#     (§300), so a tile's size is its RANK and nothing else. It shipped: the
#     six-cell table gave rank 3 one unit and ranks 4–5 two each, so "t.co · 97"
#     drew smaller than "app · 63" (user-reported, 2026-08-06).
#   · A HOLE or an OVERLAP. A table that ranks correctly but leaves a unit empty
#     or draws two cells into one is a different bug with the same look.
#   · THE WRONG NUMBER OF CELLS for a count. A five-cell layout holding four
#     tuples tiles all twelve units, ranks correctly, and traps (or stacks two
#     cells) the moment a caller indexes slot 4 — `GenTagMap` indexes directly.
#   · A SECOND TABLE. `GenTagMap` kept a private copy for a day after the shared
#     one was corrected, so the holdings map and the receipts map disagreed
#     about rank 3. Each table was internally consistent; only the pair was
#     wrong. So the guard is "there is one table", not "every table ranks".
#   · A WORD AT THE HEADLINE RUNG (prd §565). `DSTreemapLeader` sets slot 0's
#     figure at `price40` — right for a count, wrong for a term, and the word
#     maps live in `GenRenderer.swift`. Recovered with the rest because it was
#     in the same deleted block and is guarded nowhere else.
#
# The table is PARSED from the shipped source rather than compiled —
# `UnitTreemap` is a SwiftUI view — and a table the parser cannot read FAILS:
# every count 1…6 must be found, so a reformatted `case` cannot pass vacuously.
#
# STATED CEILING. The one-table scan walks every `.swift` file under `Casberi/`,
# and verify.sh's skip cache hashes only the files a harness NAMES
# (`scripts/support/harness-key.py`). A second table added to a file named
# nowhere below would be served this harness's cached ✓ on a local pass; CI
# (`logic-selftests.yml`) and the nightly run uncached and catch it there.
#
# Mutations at the bottom prove each check fails. Pure, local, deterministic —
# no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

TREEMAP="Casberi/Casberi/Design/UnitTreemap.swift"
GENUI="Casberi/Casberi/GenUI/GenRenderer.swift"
LEADER="Casberi/Casberi/Design/DSTreemapLeader.swift"
HEG="Casberi/Casberi/Screens/HegotaRoomCard.swift"
for f in "$TREEMAP" "$GENUI" "$LEADER" "$HEG"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/check.py" <<'PY'
import os, re, sys

treemap, genui, leader, heg, scan_root, owner = sys.argv[1:7]
bad = 0
def fail(msg):
    global bad
    print(f"  ✗ {msg}"); bad = 1

def tuples(s):
    return [tuple(int(v) for v in f.split(",")) for f in re.findall(r'\(([^)]*)\)', s)]

def read_table(src, name, nxt):
    """{count: [(x,y,w,h)]} for 1…6, parsed from `static func <name>`."""
    start = src.find(f"static func {name}(")
    if start < 0:
        fail(f"`static func {name}` not found — the parser is blind"); return {}
    body = src[start:]
    end = body.find(nxt)
    body = body if end < 0 else body[:end]
    body = "\n".join(l.split("//")[0] for l in body.splitlines()) + "\n"
    out = {}
    for m in re.finditer(r'case ([0-9, ]+):\s*return \[(.*?)\]\s*\n', body, re.S):
        # `case 0, 1` is one table for both: an empty map clamps to one cell
        # it never draws, so the count-0 label is not a count to check.
        for n in (int(x) for x in m.group(1).replace(" ", "").split(",") if x):
            if n >= 1:
                out[n] = tuples(m.group(2))
    m = re.search(r'default:\s*return \[(.*?)\]\s*\n', body, re.S)
    if m:
        out.setdefault(6, tuples(m.group(1)))
    elif re.search(rf'default:\s*return {name}\(6\)', body):
        pass  # the six case is spelled explicitly and the default delegates to it
    else:
        fail(f"{name}: no readable `default:` — the six-cell table is invisible")
    missing = [n for n in range(1, 7) if n not in out]
    if missing:
        fail(f"{name}: could not read the table for counts {missing} — a table the "
             "parser cannot see is a table nothing checks")
    return out

def check_table(name, table, ranked):
    for n in sorted(table):
        frames = table[n]
        if len(frames) != n:
            fail(f"{name}({n}): {len(frames)} cells for a count of {n} — "
                 f"a caller indexing slot {n - 1} traps or stacks two cells")
        areas = [w * h for _, _, w, h in frames]
        if ranked and any(areas[i] < areas[i + 1] for i in range(len(areas) - 1)):
            fail(f"{name}({n}): area RISES with rank {areas} — a smaller value would draw bigger")
        grid = set()
        for (x, y, w, h) in frames:
            if x < 0 or y < 0 or x + w > 4 or y + h > 3 or w < 1 or h < 1:
                fail(f"{name}({n}): cell {(x, y, w, h)} leaves the 4×3 board")
            for dx in range(w):
                for dy in range(h):
                    c = (x + dx, y + dy)
                    if c in grid:
                        fail(f"{name}({n}): cells overlap at {c}")
                    grid.add(c)
        if len(grid) != 12:
            fail(f"{name}({n}): tiles {len(grid)} of 12 units — the board has a hole")

src = open(treemap).read()
ranked = read_table(src, "frames", "static var maxCells")
check_table("frames", ranked, True)
# `evenFrames` (prd §688) is equal-area by design, except five, which twelve
# units cannot split — so it is held to shape and cell count, not to rank.
even = read_table(src, "evenFrames", "static func frames(")
check_table("evenFrames", even, False)

m = re.search(r'static var maxCells: Int \{ (\d+) \}', src)
if not m:
    fail("couldn't read UnitTreemap.maxCells — the ceiling guard is blind")
elif int(m.group(1)) != max(ranked or {0: 0}):
    fail(f"UnitTreemap.maxCells ({m.group(1)}) != the table's largest count "
         f"({max(ranked or {0: 0})}) — cells past the table would trap or vanish")

# ONE TABLE. A tiling literal anywhere else in the app fails, and names itself.
lit = re.compile(r'\[\s*(\((?:\s*\d+\s*,){3}\s*\d+\s*\)(?:\s*,\s*)?)+\]')
owner = os.path.abspath(owner)
for root, dirs, files in os.walk(scan_root):
    dirs[:] = [d for d in dirs if d not in (".build", "build")]
    for name in files:
        if not name.endswith(".swift"): continue
        path = os.path.join(root, name)
        if os.path.abspath(path) == owner: continue
        for i, line in enumerate(open(path, errors="replace"), 1):
            if line.lstrip().startswith("//"): continue
            for mm in lit.finditer(line):
                t = tuples(mm.group(0))
                # Bounded so an ordinary array of small quadruples can't read
                # as a treemap: two or more, all on the board, 6–12 units.
                if len(t) < 2: continue
                if not all(x + w <= 4 and y + h <= 3 for x, y, w, h in t): continue
                if not 6 <= sum(w * h for _, _, w, h in t) <= 12: continue
                fail(f"{path}:{i} carries its own 4×3 treemap table {mm.group(0)}\n"
                     "    Call UnitTreemap.frames(_:) — a second table is how the holdings\n"
                     "    map and the receipts map came to disagree about rank 3.")

if "UnitTreemap<EmptyView>.frames(items.count)" not in open(genui).read():
    fail("GenTagMap no longer reads UnitTreemap's table — the holdings map can drift again")

# THE LEADER LOCKUP IS FOR A NUMBER, NEVER A WORD (prd §565). Comment-stripped:
# both files explain the exclusion in prose that names `DSTreemapLeader`.
def code(path):
    return "\n".join(l.split("//")[0] for l in open(path).read().splitlines())
if "DSTreemapLeader" in code(genui):
    fail("GenRenderer.swift reaches DSTreemapLeader — it draws the WORD maps "
         "(TopicMapHero, GenTagMap); a term at price40 is a headline (prd §565)")
if "DSTreemapLeader" in code(heg):
    fail("HegotaRoomCard.swift reaches DSTreemapLeader — that map's leader is a "
         "BALANCE, which §374 withholds")
lsrc = open(leader).read()
if "let figure: String" not in lsrc or "let name: String" not in lsrc:
    fail("DSTreemapLeader no longer splits figure from name — one title lets a "
         "word be passed where a number belongs (prd §565)")

sys.exit(bad)
PY

run_check() {  # treemap genui leader heg scan-root
  python3 "$TMP/check.py" "$1" "$2" "$3" "$4" "$5" "$TREEMAP"
}

echo "UnitTreemap's table, its one owner, and the leader lockup"
run_check "$TREEMAP" "$GENUI" "$LEADER" "$HEG" Casberi || exit 1
echo "  ✓ frames(1…6): one cell per count, area never rises with rank, all twelve units, no overlap"
echo "  ✓ evenFrames(1…6): one cell per count, all twelve units, no overlap"
echo "  ✓ maxCells is the table's ceiling"
echo "  ✓ no second 4×3 table anywhere under Casberi/, and GenTagMap reads this one"
echo "  ✓ the leader lockup is numeric-only, and the word maps are out"

# --- mutations --------------------------------------------------------------
# Each is a failure this file exists to catch. A mutation the checker still
# passes means nothing was testing that behaviour; an anchor that no longer
# matches fails loudly rather than "passing" a mutation that never ran.
EMPTY="$TMP/empty-root"; mkdir -p "$EMPTY"
mutate() {  # name, which (treemap|genui|leader|heg), from, to
  local name="$1" which="$2" from="$3" to="$4"
  local t="$TREEMAP" g="$GENUI" l="$LEADER" h="$HEG" src target="$TMP/mut-$which.swift"
  case "$which" in
    treemap) src="$TREEMAP"; t="$target" ;;
    genui)   src="$GENUI";   g="$target" ;;
    leader)  src="$LEADER";  l="$target" ;;
    heg)     src="$HEG";     h="$target" ;;
  esac
  MUT_FROM="$from" MUT_TO="$to" python3 - "$src" "$target" <<'PY' || { echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1; }
import os, sys
src = open(sys.argv[1]).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if src.count(frm) != 1 or frm == to:
    sys.exit(2)
open(sys.argv[2], "w").write(src.replace(frm, to, 1))
PY
  # The scan is proven separately below, so these walk an empty root.
  if run_check "$t" "$g" "$l" "$h" "$EMPTY" > "$TMP/mut.log" 2>&1; then
    echo "  ✗ $name — the checker still passed, so nothing was testing this"; exit 1
  fi
  # A crash is not a catch: the failure must be a check's own ✗ line.
  if grep -q 'Traceback' "$TMP/mut.log" || ! grep -q '✗' "$TMP/mut.log"; then
    echo "  ✗ $name — the checker failed without a finding:"; cat "$TMP/mut.log"; exit 1
  fi
  echo "  ✓ $name"
}

echo ""
echo "Mutations"
# The 2026-08-06 table itself: rank 3 one unit, ranks 4–5 two each.
mutate "the six-cell table goes back to the one that shipped (area rises)" treemap \
  'default:   return [(0, 0, 2, 2), (2, 0, 2, 1), (2, 1, 2, 1), (0, 2, 2, 1), (2, 2, 1, 1), (3, 2, 1, 1)]' \
  'default:   return [(0, 0, 2, 2), (2, 0, 2, 1), (2, 1, 1, 1), (3, 1, 1, 2), (0, 2, 2, 1), (2, 2, 1, 1)]'
mutate "a cell shrinks and leaves a hole" treemap \
  'case 4:    return [(0, 0, 2, 2), (2, 0, 2, 2), (0, 2, 2, 1), (2, 2, 2, 1)]' \
  'case 4:    return [(0, 0, 2, 2), (2, 0, 2, 2), (0, 2, 2, 1), (2, 2, 1, 1)]'
# (Anchors spell a whole line that only `frames` carries: cases 1–3 are the
# same literal in `evenFrames`, and an ambiguous anchor refuses to apply.)
mutate "two cells overlap" treemap \
  'case 5:    return [(0, 0, 2, 2), (2, 0, 2, 2), (0, 2, 2, 1), (2, 2, 1, 1), (3, 2, 1, 1)]' \
  'case 5:    return [(0, 0, 2, 2), (2, 0, 2, 2), (0, 2, 2, 1), (2, 2, 1, 1), (2, 2, 1, 1)]'
# Tiles twelve units and ranks correctly — only the cell count catches it.
mutate "the five-cell layout holds four cells" treemap \
  'case 5:    return [(0, 0, 2, 2), (2, 0, 2, 2), (0, 2, 2, 1), (2, 2, 1, 1), (3, 2, 1, 1)]' \
  'case 5:    return [(0, 0, 2, 2), (2, 0, 2, 2), (0, 2, 2, 1), (2, 2, 2, 1)]'
mutate "a cell runs off the board" treemap \
  'case 4:    return [(0, 0, 2, 2), (2, 0, 2, 2), (0, 2, 2, 1), (2, 2, 2, 1)]' \
  'case 4:    return [(0, 0, 2, 2), (2, 0, 2, 2), (0, 2, 2, 1), (2, 2, 3, 1)]'
mutate "the even table leaves a hole" treemap \
  '(0, 2, 2, 1), (2, 2, 2, 1)]        // 2 each' \
  '(0, 2, 2, 1), (2, 2, 1, 1)]        // 2 each'
# A reformatted case the regex cannot read must fail, never pass vacuously.
mutate "a case the parser cannot read" treemap \
  'case 4:    return [(0, 0, 2, 2), (2, 0, 2, 2), (0, 2, 2, 1), (2, 2, 2, 1)]' \
  'case 4 where true: return [(0, 0, 2, 2), (2, 0, 2, 2), (0, 2, 2, 1), (2, 2, 2, 1)]'
mutate "maxCells outgrows the table" treemap \
  'static var maxCells: Int { 6 }' \
  'static var maxCells: Int { 7 }'
mutate "GenTagMap stops reading the shared table" genui \
  'UnitTreemap<EmptyView>.frames(items.count)' \
  'GenTagMap.frames(items.count)'
mutate "a word map reaches the leader lockup" genui \
  'UnitTreemap<EmptyView>.frames(items.count)' \
  'UnitTreemap<EmptyView>.frames(items.count); _ = DSTreemapLeader.self'
mutate "the leader folds figure and name into one title" leader \
  'let figure: String' \
  'let title: String'

# The scan, both ways: a second table under an app root fails; a small array
# of quadruples and a table in a comment do not (the scan's own bounds).
SCAN="$TMP/scan-root"; mkdir -p "$SCAN"
print -r -- 'let layout = [(0, 0, 2, 3), (2, 0, 2, 3)]' > "$SCAN/Second.swift"
if run_check "$TREEMAP" "$GENUI" "$LEADER" "$HEG" "$SCAN" > /dev/null 2>&1; then
  echo "  ✗ a second 4×3 table elsewhere — the checker still passed"; exit 1
fi
echo "  ✓ a second 4×3 table elsewhere"
{ print -r -- 'let insets = [(0, 0, 1, 1), (1, 0, 1, 1)]'
  print -r -- '// [(0, 0, 2, 3), (2, 0, 2, 3)] was the old layout'; } > "$SCAN/Second.swift"
if ! run_check "$TREEMAP" "$GENUI" "$LEADER" "$HEG" "$SCAN" > /dev/null 2>&1; then
  echo "  ✗ the scan fires on a two-unit array or a comment — it would cry wolf"; exit 1
fi
echo "  ✓ a two-unit array and a commented table are not a second table"

echo ""
echo "unit-treemap-selftest: OK — the table holds and every mutation is caught."
