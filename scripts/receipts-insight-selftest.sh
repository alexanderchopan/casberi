#!/bin/zsh
# Casberi receipts-insight self-test — the SHIPPED composition behind the
# receipts screen's reach map (prd §299, 2026-08-04):
#
#   Casberi/Casberi/Model/NetworkReceiptsInsight.swift
#
# Foundation-only BY DESIGN, so it is compiled WHOLE AND UNMODIFIED rather than
# extracted — the strongest form of "the harness ran the shipped logic".
#
# WHY A HARNESS. Every failure mode in this file is a SILENT WRONG ANSWER that
# renders as a perfectly convincing card:
#
#   · an undeclared host folded into "3 more" — the ONE row this screen exists
#     to surface, hidden by rank, with nothing anywhere saying it happened
#   · a tail truncated instead of folded, so a nine-service ledger draws six
#     tiles and looks exactly like a six-service one
#   · shares normalised against the total instead of the largest cell, which
#     leaves every tile the same near-transparent wash as the tail grows
#   · two services on the same count trading places between launches, so a card
#     nobody's data changed reads as live
#   · per-host grouping, which would split one wallet sweep across five Alchemy
#     hosts and show five medium shares where the truth is one large one
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

MODEL="Casberi/Casberi/Model/NetworkReceiptsInsight.swift"
SCREEN="Casberi/Casberi/Screens/NetworkReceiptsScreen.swift"
GRID="Casberi/Casberi/Design/UnitTreemap.swift"
PROBES="Casberi/Casberi/Shell/ProbeHooks.swift"
for f in "$MODEL" "$SCREEN" "$GRID" "$PROBES"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards -----------------------------------------------------------
# Wiring facts the compiled function cannot prove about itself. A perfect
# `compose` is worthless if the card draws its own order, resolves its own
# services, or tiles more cells than the model ever caps at.
grep -q 'NetworkReceiptsInsight.compose(rows: receipts.map' "$SCREEN" \
  || { echo "✗ the card no longer composes from the screen's own resolved receipts — the map and the rows below could disagree about who owns a host"; exit 1; }
grep -q 'UnitTreemap(count: reach.cells.count' "$SCREEN" \
  || { echo "✗ the card no longer tiles the composed cells"; exit 1; }
# 2026-08-10: every OTHER treemap in the app moved from a tinted wash to the
# neutral DS.ink(magnitude:) ramp, and this card moved with them for its
# DECLARED cells — but attention is a state, not decoration, so an undeclared
# cell was deliberately kept out of that ramp (DS.wash(DS.attention, …)
# instead of DS.ink(…)), the one place this map departs from the shared rule.
grep -q 'DS.wash(DS.attention, magnitude: cell.share)' "$SCREEN" \
  || { echo "✗ an undeclared cell no longer wears attention — the finding would be drawn as an ordinary service"; exit 1; }
grep -q 'if cell.isTail { return DS.fillLine }' "$SCREEN" \
  || { echo "✗ the tail no longer takes a neutral fill — a sum of small services would out-shout the largest single one"; exit 1; }
# maxCells is spelled in both files on purpose (the model is Foundation-only and
# cannot read the view's constant). That is exactly why it can drift.
grep -q 'static let maxCells = 6' "$MODEL" \
  || { echo "✗ the model's cell cap moved"; exit 1; }
grep -q 'static var maxCells: Int { 6 }' "$GRID" \
  || { echo "✗ UnitTreemap's cell cap moved out of step with the model's — cells past the frame table would silently vanish"; exit 1; }
grep -q 'reachCell|' "$PROBES" \
  || { echo "✗ -receiptsProbe no longer dumps the composed cells; an empty or mis-grouped card would have no headless diagnosis"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

typealias Row = NetworkReceiptsInsight.Row
func row(_ host: String, _ count: Int, _ service: String?) -> Row {
    Row(host: host, count: count, service: service)
}

print("Nothing to draw")
check("an empty ledger declines the slot", NetworkReceiptsInsight.compose(rows: []) == nil)
check("rows that recorded nothing decline too",
      NetworkReceiptsInsight.compose(rows: [row("a.example", 0, "A")]) == nil)
// A host that recorded nothing is not a host reached. It can exist: the ledger
// prunes by `last`, not by count, and a future caller could record a zero.
let withDead = NetworkReceiptsInsight.compose(rows: [
    row("real.example", 5, "Real"), row("dead.example", 0, "Dead"),
])!
check("a zero-count row is not counted as a host reached", withDead.hosts == 1)
check("nor as a service", withDead.services == 1)
check("nor drawn a cell", withDead.cells.count == 1)

print("")
print("Grouping is by service, not by host")
// The measured shape this exists for: one wallet sweep spreads over five
// per-chain Alchemy hosts (prd §289). Per-host cells would draw five medium
// shares where the truth is one large one.
let wallet = NetworkReceiptsInsight.compose(rows: [
    row("base-mainnet.g.alchemy.com", 40, "Wallet"),
    row("eth-mainnet.g.alchemy.com", 35, "Wallet"),
    row("opt-mainnet.g.alchemy.com", 25, "Wallet"),
    row("public.api.bsky.app", 30, "Bluesky"),
])!
check("five hosts of one service collapse to one cell", wallet.cells.count == 2)
check("the collapsed cell carries the summed count", wallet.cells[0].count == 100)
check("the cell is labelled by the service", wallet.cells[0].label == "Wallet")
check("hosts still counts hosts", wallet.hosts == 4)
check("services counts services", wallet.services == 2)
check("requests is every request", wallet.requests == 130)
check("the lead's share is of the TOTAL, not of the largest cell",
      abs((wallet.leadShare ?? 0) - 100.0 / 130.0) < 0.0001)

print("")
print("Shares are normalised against the largest cell")
// Against the TOTAL instead, every cell washes out as the tail grows — the map
// goes uniformly pale exactly when it has the most to say.
check("the largest cell is fully saturated", wallet.cells[0].share == 1)
check("a smaller cell is its fraction of the largest",
      abs(wallet.cells[1].share - 0.30) < 0.0001)

print("")
print("An undeclared host is its own cell, and says so")
let stranger = NetworkReceiptsInsight.compose(rows: [
    row("api.known.example", 90, "Known"),
    row("who.is.this.example", 4, nil),
])!
check("it stands under its own host name", stranger.cells[1].label == "who.is.this.example")
check("it is marked undeclared", stranger.cells[1].declared == false)
check("the headline counts it", stranger.undeclaredHosts == 1)
check("a clean ledger reads clean", wallet.clean)
check("a ledger with a stranger does not", !stranger.clean)
check("an undeclared host is NOT counted as a service", stranger.services == 1)
// Two strangers stay two cells: merging them into one "unknown" bucket would
// hide how many distinct hosts were reached, which is the number that matters.
let strangers = NetworkReceiptsInsight.compose(rows: [
    row("api.known.example", 90, "Known"),
    row("one.example", 4, nil),
    row("two.example", 3, nil),
])!
check("two strangers are two cells", strangers.undeclaredHosts == 2 && strangers.cells.count == 3)

print("")
print("Ranking is deterministic")
let tied = NetworkReceiptsInsight.compose(rows: [
    row("z.example", 10, "Zulu"), row("a.example", 10, "Alpha"), row("m.example", 20, "Mike"),
])!
check("count descending leads", tied.cells[0].label == "Mike")
check("a tie breaks on the label, ascending", tied.cells[1].label == "Alpha")
let reordered = NetworkReceiptsInsight.compose(rows: [
    row("a.example", 10, "Alpha"), row("m.example", 20, "Mike"), row("z.example", 10, "Zulu"),
])!
check("input order cannot change the result", tied.cells == reordered.cells)

print("")
print("The tail is folded, never truncated")
func many(_ n: Int, undeclaredAt: Int? = nil) -> [Row] {
    (0..<n).map { i in
        let count = 100 - i          // strictly descending, so rank is unambiguous
        let declared = undeclaredAt != i
        return row("h\(i).example", count, declared ? "S\(i)" : nil)
    }
}
let six = NetworkReceiptsInsight.compose(rows: many(6))!
check("exactly six services need no tail", six.cells.count == 6 && !six.cells.contains { $0.isTail })
let nine = NetworkReceiptsInsight.compose(rows: many(9))!
check("nine services still draw six cells", nine.cells.count == 6)
check("the last one is the tail", nine.cells[5].isTail)
check("the tail says how many it holds", nine.cells[5].label == "4 more")
check("the tail carries their summed count",
      nine.cells[5].count == (100 - 5) + (100 - 6) + (100 - 7) + (100 - 8))
check("no request is lost to the fold",
      nine.cells.reduce(0) { $0 + $1.count } == nine.requests)
check("the tail's share can never exceed the largest cell's", nine.cells[5].share <= 1)
// A tail of one would be a cell saying "1 more" where naming it is free —
// impossible by construction, and worth pinning.
let seven = NetworkReceiptsInsight.compose(rows: many(7))!
check("a seven-service ledger folds two, never one", seven.cells[5].label == "2 more")

print("")
print("An undeclared host can never be hidden by rank")
// The whole point of the screen. `many(9, undeclaredAt: 8)` puts the stranger
// LAST by count, exactly where a plain prefix would bury it.
let buried = NetworkReceiptsInsight.compose(rows: many(9, undeclaredAt: 8))!
check("it is promoted into the drawn cells",
      buried.cells.contains { !$0.declared })
check("it keeps its real count — promotion changes rank, never magnitude",
      buried.cells.first { !$0.declared }!.count == 100 - 8)
check("it takes the last head slot, not the first",
      buried.cells[4].declared == false)
check("the cell count is unchanged", buried.cells.count == 6)
check("what it displaced went back into the tail, which still holds four",
      buried.cells[5].label == "4 more")
check("no request is lost to the promotion",
      buried.cells.reduce(0) { $0 + $1.count } == buried.requests)
check("the head is still ordered biggest first",
      zip(buried.cells.dropLast(), buried.cells.dropFirst().dropLast())
        .allSatisfy { $0.count >= $1.count })

print("")
if failures > 0 {
    print("receipts-insight-selftest: \(failures) FAILED")
    exit(1)
}
print("assertions: all pass")
SWIFT

if ! swiftc -O -o "$TMP/run" "$MODEL" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ the harness did not compile against the shipped source:"
  cat "$TMP/build.log"
  exit 1
fi
"$TMP/run" || exit 1

# --- mutations --------------------------------------------------------------
# Each is a silent-wrong-answer this file exists to catch. A mutation the
# harness still passes means nothing was testing that behaviour.
mutate() {
  local name="$1" from="$2" to="$3"
  local target="$TMP/mut.swift"
  cp "$MODEL" "$target"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$target" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$target"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$target" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

echo ""
echo "Mutations"
# The failure this whole file exists to prevent.
mutate "an undeclared host can be buried in the tail" \
  'if let hidden = tail.firstIndex(where: { !$0.declared }) {' \
  'if let hidden: Int = nil {'
# A truncated tail looks identical to no tail.
mutate "the tail is dropped instead of folded" \
  'head = Array(ranked.prefix(maxCells - 1))
            tail = Array(ranked.dropFirst(maxCells - 1))' \
  'head = Array(ranked.prefix(maxCells))
            tail = []'
# The wash goes uniformly pale exactly when the map has most to say.
mutate "shares normalise against the total instead of the largest cell" \
  'let maxCount = max(head.first?.count ?? 1, 1)' \
  'let maxCount = max(requests, 1)'
# A card nobody's data changed, reshuffling between launches.
mutate "the tie-break is dropped" \
  'ranked.sort { $0.count == $1.count ? $0.label < $1.label : $0.count > $1.count }' \
  'ranked.sort { $0.count == $1.count ? $0.label > $1.label : $0.count > $1.count }'
# Five Alchemy hosts drawn as five medium shares.
mutate "grouping falls back to per-host" \
  'byService[service, default: 0] += row.count' \
  'byService[row.host, default: 0] += row.count'
# Strangers merged into one bucket hide how many there were.
mutate "undeclared hosts merge into one cell" \
  'undeclared.append((row.host, row.count))' \
  'undeclared.append(("unknown", row.count))'
# A host that recorded nothing counted as one that was reached. (There is no
# mutation for the empty-ledger guard: it is doubly covered — `!live.isEmpty`
# and `requests > 0` each return nil on their own, so neither can be mutated
# into a failure alone. Two guards that cover each other is the right shape;
# a mutation that nothing catches would only be proof the harness is toothless.)
mutate "zero-count rows are counted as hosts reached" \
  'let live = rows.filter { $0.count > 0 }' \
  'let live = rows'
# A tail sum out-shouting the largest single service.
mutate "the tail's share is left unclamped" \
  'share: min(Double(rest) / Double(maxCount), 1)' \
  'share: Double(rest) / Double(maxCount) + 1'

echo ""
echo "receipts-insight-selftest: OK — assertions pass and every mutation is caught."
