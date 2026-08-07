#!/bin/zsh
# Casberi agent-panel self-test — the SHIPPED composition behind the agent's
# instrument panel (prd §334, 2026-08-07):
#
#   Casberi/Casberi/Model/AgentPanel.swift
#     — Figure.isEmpty   (which readings are too thin to draw)
#     — rank             (affinity order, one card per room, total ordering)
#     — richness         (the tie-break, and why a pulse scores live days)
#     — normalized       (bars against the leader; a curve over its own range)
#     — levels           (per-day counts bucketed against the observed max)
#
# WHY A HARNESS. This is the first screen a person sees, and every failure in
# it renders as a perfectly good-looking tile:
#
#   • a flat wallet curve drawn along the floor, which reads as "went to zero"
#     — the most alarming possible way to say nothing happened;
#   • a room appearing twice because two registries both answered for it;
#   • tiles reshuffling between opens over identical data, which reads as a
#     broken screen (§332's per-process Dictionary hashing, one surface over);
#   • a heatmap outranking everything forever because raw length was scored
#     instead of live days — every registered grid is the same width;
#   • a bar row of NaN widths from a zero leader, which SwiftUI draws as
#     nothing at all.
#
# `AgentPanel.swift` is Foundation-only BY DESIGN, so this compiles it WHOLE
# and UNMODIFIED with no stubs. There is no extraction step that can drift.
#
# Pure, local, deterministic — no network, no simulator, no corpus.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/AgentPanel.swift"
GRID="Casberi/Casberi/Screens/AgentPanelGrid.swift"
COMPOSER="Casberi/Casberi/Shell/Composer.swift"
for f in "$SRC" "$GRID" "$COMPOSER"; do
  [[ -f "$f" ]] || { print -u2 "missing $f"; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}

func cells(_ n: Int) -> [AgentPanel.Cell] {
    (0..<n).map { AgentPanel.Cell(label: "c\($0)", weight: n - $0) }
}
func bars(_ values: [Int]) -> [AgentPanel.Bar] {
    values.enumerated().map { AgentPanel.Bar(label: "b\($0.offset)", value: $0.element,
                                             detail: "\($0.element)") }
}
func card(_ source: String, _ figure: AgentPanel.Figure, key: String? = nil,
          affinity: Int = 0) -> AgentPanel.Card {
    AgentPanel.Card(source: source, key: key ?? source, title: "t", caption: "c",
                    figure: figure, affinity: affinity)
}
func lanes(_ usds: [Double]) -> [AgentPanel.FlowLane] {
    usds.enumerated().map { AgentPanel.FlowLane(name: "l\($0.offset)", usd: $0.element, count: 1) }
}

// ─────────────────── which readings are too thin to draw ───────────────────
print("isEmpty")
check(AgentPanel.Figure.treemap(cells(1)).isEmpty, "a one-cell map is not a map")
check(!AgentPanel.Figure.treemap(cells(2)).isEmpty, "two cells is a map")
check(AgentPanel.Figure.rail([]).isEmpty, "an empty rail draws nothing")
check(AgentPanel.Figure.curve([1, 2]).isEmpty, "two points is a line between dots, not a curve")
check(!AgentPanel.Figure.curve([1, 2, 3]).isEmpty, "three points is a curve")
check(AgentPanel.Figure.wall(["a", "b", "c"]).isEmpty, "a wall needs a full grid")
// The pulse pair — the one that actually happens on a quiet room.
check(AgentPanel.Figure.pulse(Array(repeating: 0, count: 84)).isEmpty,
      "a full-width grid of ZEROS is empty boxes claiming to be a year")
var oneDay = Array(repeating: 0, count: 84); oneDay[40] = 1
check(!AgentPanel.Figure.pulse(oneDay).isEmpty, "one live day is a real pulse")
check(AgentPanel.Figure.pulse([1, 2, 3]).isEmpty, "a pulse shorter than a week is not a rhythm")

// The flow — the figure the user asked for by name.
check(AgentPanel.Figure.flow(inLanes: lanes([100]), outLanes: []).isEmpty,
      "one side alone is a bar chart pretending to be a flow")
check(!AgentPanel.Figure.flow(inLanes: lanes([100]), outLanes: lanes([40])).isEmpty,
      "one lane each side is a real flow")

// ─────────────────── ranking ───────────────────
print("rank")
let ranked = AgentPanel.rank([
    card("Photos", .treemap(cells(3)), affinity: 1),
    card("Reddit", .bars(bars([5, 3, 1])), affinity: 9),
])
check(ranked.first?.source == "Reddit", "the room you actually open leads")

// One card per room, even when two registries answer for it.
let deduped = AgentPanel.rank([
    card("Instagram", .treemap(cells(4)), affinity: 5),
    card("Instagram", .bars(bars([9, 8])), affinity: 5),
])
check(deduped.count == 1, "a doubly-registered room takes one tile, not two")

// …but the dedupe keys on KEY, not source: the Wallet legitimately holds its
// curve and its flow as two cards. Keying on source would silently drop the
// sankey, which is exactly the figure the user asked for by name.
let wallet = AgentPanel.rank([
    card("Wallet", .curve([1, 2, 3]), key: "wallet.curve", affinity: 5),
    card("Wallet", .flow(inLanes: lanes([100]), outLanes: lanes([40])),
         key: "wallet.flow", affinity: 5),
])
check(wallet.count == 2, "the Wallet's curve and flow both survive under their own keys")

// Empty figures never become tiles.
check(AgentPanel.rank([card("X", .treemap(cells(1)))]).isEmpty,
      "a figure too thin to draw never becomes a card")

// The cap.
let many = (0..<20).map { card("s\($0)", .bars(bars([3, 2])), affinity: 5) }
check(AgentPanel.rank(many).count == AgentPanel.maxCards, "the panel caps at maxCards")

// TOTAL order: equal affinity AND equal richness must fall to the name, or the
// panel reshuffles between opens over identical data.
let tied = AgentPanel.rank([
    card("Zulip", .bars(bars([3, 2])), affinity: 4),
    card("Apple Music", .bars(bars([3, 2])), affinity: 4),
])
check(tied.map(\.source) == ["Apple Music", "Zulip"], "equal cards sort by name, so the order is total")

// Richness breaks an affinity tie before the name does.
let rich = AgentPanel.rank([
    card("Aaa", .bars(bars([3, 2])), affinity: 4),
    card("Zzz", .bars(bars([5, 4, 3, 2])), affinity: 4),
])
check(rich.first?.source == "Zzz", "with equal affinity the fuller figure leads")

// §336: a contribution wall answers WHEN — the weakest thing a room can say —
// so it never outranks a real figure, even from a room you open far more.
let demoted = AgentPanel.rank([
    card("Photos", .pulse(oneDay), affinity: 99),
    card("RSS", .bars(bars([5, 3])), affinity: 0),
])
check(demoted.first?.source == "RSS", "a year wall never leads over a real figure")
check(AgentPanel.grade(.pulse(oneDay)) < AgentPanel.grade(.bars(bars([1]))),
      "pulse grades below everything else")

// The Wallet holds a slot without having been tapped (user: "the wallet should
// always be on the visualizations") — affinity is a TAP counter, and the
// wallet's figure is one you want without having gone looking for it.
let pinned = AgentPanel.rank([
    card("Photos", .bars(bars([9, 8])), affinity: 99),
    card("Wallet", .curve([1, 2, 3]), key: "wallet.curve", affinity: 0),
])
check(pinned.first?.source == "Wallet", "the Wallet is pinned ahead of affinity")

// A heatmap must not win on width alone.
var sparse = Array(repeating: 0, count: 84); sparse[0] = 1; sparse[1] = 1
check(AgentPanel.richness(.pulse(sparse)) == 2, "a pulse is scored on live days, not its width")
check(AgentPanel.richness(.pulse(sparse)) < AgentPanel.richness(.bars(bars([4, 3, 2]))),
      "…so a nearly-empty year does not outrank a real leaderboard")

// ─────────────────── normalization ───────────────────
print("normalized")
check(AgentPanel.normalized(bars([10, 5])) == [1.0, 0.5], "bars are fractions of the leader")
check(AgentPanel.normalized(bars([0, 0])) == [0.0, 0.0], "a zero leader yields zero widths, never NaN")
check(AgentPanel.normalized(bars([0, 0])).allSatisfy { $0.isFinite }, "…and every width is finite")

let curve = AgentPanel.normalized([10.0, 20.0, 30.0])
check(curve == [0.0, 0.5, 1.0], "a curve maps over its own range")
// The one that matters most on a wallet tile.
check(AgentPanel.normalized([7.0, 7.0, 7.0]) == [0.5, 0.5, 0.5],
      "a FLAT curve rides the middle — along the floor reads as 'went to zero'")
check(AgentPanel.normalized([Double]()).isEmpty, "an empty curve normalizes to nothing")

print("levels")
check(AgentPanel.levels([0, 0, 0]) == [0, 0, 0], "an empty week has no intensity")
let lv = AgentPanel.levels([0, 1, 4])
check(lv[0] == 0 && lv[2] == 4, "the busiest day is the brightest")
check(AgentPanel.levels([1, 1, 1]).allSatisfy { $0 == 4 },
      "a uniformly busy room still shows its own shape, not one dim wall")

print("clamp")
check(AgentPanel.clamp("short") == "short", "a short caption is untouched")
check(AgentPanel.clamp("the quick brown fox jumps over", max: 15) == "the quick…",
      "a clamp cuts at a word, never mid-word")

print("")
if failures > 0 { print("\(failures) failure(s)"); exit(1) }
print("agent-panel self-test passed")
SWIFT

print "AgentPanel self-test — the shipped file, compiled whole"
xcrun swiftc -O -o "$WORK/run" "$SRC" "$WORK/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$WORK/run" ]] || { print -u2 "✗ compile failed"; exit 1; }
"$WORK/run" || exit 1

print ""
print "Mutations — each must FAIL the suite"
mutate() {
  local name="$1" from="$2" to="$3"
  local dir="$WORK/mut"; rm -rf "$dir"; mkdir -p "$dir"
  python3 - "$SRC" "$dir/AgentPanel.swift" "$from" "$to" <<'PY'
import sys
src, dst, a, b = sys.argv[1:5]
s = open(src).read()
if a not in s:
    sys.stderr.write("MUTATION ANCHOR MISSING: %r\n" % a); sys.exit(3)
open(dst, "w").write(s.replace(a, b, 1))
PY
  if [[ $? -eq 3 ]]; then print "  ✗ $name — anchor missing (harness is stale)"; return 1; fi
  if xcrun swiftc -O -o "$dir/run" "$dir/AgentPanel.swift" "$WORK/main.swift" >/dev/null 2>&1 \
       && "$dir/run" >/dev/null 2>&1; then
    print "  ✗ $name — SURVIVED"; return 1
  fi
  print "  ✓ $name caught"
}

rc=0
mutate "a flat curve is drawn along the floor" \
  'guard hi > lo else { return curve.map { _ in 0.5 } }' \
  'guard hi > lo else { return curve.map { _ in 0.0 } }' || rc=1
mutate "a zero leader yields NaN bar widths" \
  'guard let top = bars.map(\.value).max(), top > 0 else {
            return Array(repeating: 0, count: bars.count)
        }' \
  'let top = bars.map(\.value).max() ?? 0' || rc=1
mutate "a room can take two tiles" \
  'guard !out.contains(where: { $0.key == card.key }) else { return }' \
  'if false { return }' || rc=1
mutate "dedupe keys on source and eats the sankey" \
  'guard !out.contains(where: { $0.key == card.key }) else { return }' \
  'guard !out.contains(where: { $0.source == card.source }) else { return }' || rc=1
mutate "a one-sided flow draws" \
  'case .flow(let inL, let outL): return inL.isEmpty || outL.isEmpty' \
  'case .flow(let inL, let outL): return inL.isEmpty && outL.isEmpty' || rc=1
mutate "the panel loses its cap" \
  'guard out.count < maxCards else { return }' \
  'if false { return }' || rc=1
mutate "tile order stops being total" \
  'return a.source < b.source' \
  'return false' || rc=1
mutate "a year wall outranks a real figure again" \
  'if ga != gb { return ga > gb }' \
  'if false { return false }' || rc=1
mutate "the Wallet loses its pin" \
  'if pa != pb { return pa }' \
  'if false { return false }' || rc=1
mutate "affinity stops leading the sort" \
  'if a.affinity != b.affinity { return a.affinity > b.affinity }' \
  'if false { return false }' || rc=1
mutate "a pulse is scored on its width" \
  'case .pulse(let p):   return p.filter { $0 > 0 }.count' \
  'case .pulse(let p):   return p.count' || rc=1
mutate "an all-zero year counts as a drawable pulse" \
  'case .pulse(let p):   return p.count < 7 || !p.contains { $0 > 0 }' \
  'case .pulse(let p):   return p.count < 7' || rc=1
mutate "a two-point curve draws as a rule across the tile" \
  'case .curve(let v):   return v.count < 3' \
  'case .curve(let v):   return v.count < 2' || rc=1
mutate "empty figures become blank tiles" \
  'filter { !$0.figure.isEmpty }' \
  'filter { _ in true }' || rc=1
mutate "levels stop scaling to the room's own max" \
  'let step = Double(count) / Double(top)' \
  'let step = Double(count) / 100.0' || rc=1

print ""
print "Drift guards"
guard_has() {
  local what="$1" file="$2" pat="$3"
  # A here-string, NOT a pipe into `grep -q`: under `pipefail` a matching
  # `grep -q` exits early, `sed` dies on SIGPIPE, and the PIPELINE reports
  # failure — so a guard reads as broken exactly when it succeeds. It is
  # size-dependent, which is what made it vicious in §332's harness.
  local body; body="$(sed 's|//.*||' "$file")"
  if grep -qE "$pat" <<< "$body"; then print "  ✓ $what"
  else print "  ✗ $what"; return 1; fi
}

# The panel's contract: the tile previews the figure the ROOM draws. The chain
# below mirrors FeedScreen.shapedSections; if a registry is dropped here the
# tile silently previews a different figure than the room.
guard_has "the chain still asks topicMap first" "$COMPOSER" 'FeedInsight\.topicMap\(source:' || rc=1
guard_has "…then leaderboard"   "$COMPOSER" 'FeedInsight\.leaderboard\(source:' || rc=1
guard_has "…then distribution"  "$COMPOSER" 'FeedInsight\.distribution\(source:' || rc=1
guard_has "…then mosaic"        "$COMPOSER" 'FeedInsight\.mosaic\(source:' || rc=1
guard_has "…then the heatmap"   "$COMPOSER" 'FeedHeatmap\.label\(for:' || rc=1
# Affinity is ChipMemory's weight, not a number invented here.
guard_has "affinity rides ChipMemory" "$COMPOSER" 'ChipMemory\.weight\(for:' || rc=1
# Import receipts are the app talking about itself.
guard_has "import receipts are excluded" "$COMPOSER" 'Corpus\.isImportReceipt' || rc=1
# A tap must land you in the room the tile previewed.
guard_has "a tile tap switches the room" "$COMPOSER" 'filter\.source = source' || rc=1
# The sankey rides the room's own composer — the panel must not grow a second
# flow engine that can disagree with the feed's band.
guard_has "the flow card rides WalletFlowSource" "$COMPOSER" 'WalletFlowSource\.band\(from:' || rc=1
# …and it must take a full-width slot: half a sankey is unreadable by the
# sizing inventory this panel was built against.
guard_has "a flow figure demands full width" "$GRID" 'case \.flow = figure \{ return true \}' || rc=1
# §334's tripwire: the moment a figure can be words, the panel is a list again.
if sed 's|//.*||' "$SRC" | grep -qE 'case text\('; then
  print "  ✗ a Figure case may never be text (§334's tripwire)"; rc=1
else
  print "  ✓ no text figure — the panel only ever draws"
fi
# The entrance must honour Reduce Motion.
guard_has "tile entrance honours Reduce Motion" "$GRID" 'reduceMotion \? nil' || rc=1

print ""
if [[ $rc -ne 0 ]]; then print "✗ agent-panel self-test FAILED"; exit 1; fi
print "✓ agent-panel self-test passed"
