#!/bin/zsh
# frames-flow-selftest.sh — the Frames tile's FLOW (prd §925): steps by
# position, links between consecutive positions, ends where runs stop.
#
# `RoomFrames.flow` is pure, so this compiles `Model/RoomFrames.swift` alone
# and drives it: every step of every run lands in exactly one node, every run
# contributes exactly `steps.count - 1` links and one end (or none, past the
# drawn positions), nodes sort biggest-first within a position, a failed step
# is its own node and never a Send that happened, and the beyond count is the
# steps that flow off the right edge. Three mutations prove the assertions
# bite, and each mutation is checked to have CHANGED the source (a mutation
# that did not apply prints nothing and proves nothing).
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="Casberi/Casberi/Model/RoomFrames.swift"
[[ -f "$SRC" ]] || { echo "✗ $SRC not found"; exit 1; }
TMP=$(mktemp -d /tmp/frames-flow-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}
func step(_ mode: String, _ outcome: RoomFrames.Outcome = .ran, id: Int) -> RoomFrames.Step {
    RoomFrames.Step(modeName: mode, weight: 1, outcome: outcome, id: id)
}
// The UTXO demo's five, plus one with a failed third step and one seven long.
let runs: [RoomFrames.Run] = [
    .init(id: "a", steps: [step("Verify", id: 1), step("UTXO", id: 2)]),
    .init(id: "b", steps: [step("UTXO", id: 3)]),
    .init(id: "c", steps: [step("UTXO", id: 4)]),
    .init(id: "d", steps: [step("Verify", id: 5), step("Send", id: 6)]),
    .init(id: "e", steps: [step("Verify", id: 7), step("Send", id: 8)]),
    .init(id: "f", steps: [step("Verify", id: 9), step("Send", id: 10), step("Send", .failed, id: 11)]),
    .init(id: "g", steps: (0..<7).map { step("Send", id: 100 + $0) }),
]
guard let flow = RoomFrames.flow(runs) else { print("  ✗ no flow"); exit(1) }
let key = RoomFrames.Flow.key
// Every step in exactly one node: node counts sum to the steps drawn.
let drawnSteps = runs.reduce(0) { $0 + min($1.steps.count, RoomFrames.Flow.positionsShown) }
check(flow.nodes.reduce(0) { $0 + $1.count } == drawnSteps, "node counts sum to the drawn steps (\(drawnSteps))")
check(flow.beyond == 3, "a seven-step run flows three steps off the edge — got \(flow.beyond)")
check(flow.positions == 4, "four positions drawn — got \(flow.positions)")
// Links: one per consecutive pair within the drawn positions.
let expectedLinks = runs.reduce(0) { $0 + max(0, min($1.steps.count, RoomFrames.Flow.positionsShown) - 1) }
check(flow.links.reduce(0) { $0 + $1.count } == expectedLinks, "links sum to the consecutive pairs (\(expectedLinks))")
check(flow.links.first { $0.from == key(0, "Verify") && $0.to == key(1, "Send") }?.count == 3, "Verify → Send carries 3")
check(flow.links.first { $0.from == key(0, "Verify") && $0.to == key(1, "UTXO") }?.count == 1, "Verify → UTXO carries 1")
// Ends: one per run that finishes inside the drawn positions.
check(flow.ends.reduce(0) { $0 + $1.count } == runs.filter { $0.steps.count <= RoomFrames.Flow.positionsShown }.count,
      "every run that finishes inside the drawn positions ends once")
check(flow.ended(key(0, "UTXO")) == 2, "two runs end at the first UTXO")
// A failed step is its own node, never a Send that happened.
check(flow.nodes.contains { $0.id == key(2, "Failed") && $0.kind == .failed && $0.count == 1 }, "the failed third step is a Failed node")
check(flow.nodes.first { $0.id == key(2, "Send") }?.count == 1, "the third-position Send counts only the run that ran it")
// Biggest first within a position.
let first = flow.nodes(at: 0)
check(first.first?.label == "Verify" && first.first?.count == 4, "the first column leads with Verify 4 — got \(first.map { "\($0.label) \($0.count)" })")
check(first.map(\.count) == first.map(\.count).sorted(by: >), "nodes within a position are biggest first")
// Position words.
check(RoomFrames.positionWord(0) == "1st" && RoomFrames.positionWord(3) == "4th", "position words")
// Nothing framed is nothing.
check(RoomFrames.flow([.init(id: "z", steps: [])]) == nil, "a run with no steps makes no flow")
if failures > 0 { print("✗ frames-flow: \(failures) failed"); exit(1) }
print("ok")
SWIFT

run() {  # $1 = source to compile
  swiftc -o "$TMP/bin" "$1" "$TMP/main.swift" 2>"$TMP/err" || { cat "$TMP/err"; return 2; }
  "$TMP/bin"
}
echo "frames-flow: assertions"
run "$SRC" || { echo "✗ frames-flow: assertions failed"; exit 1; }

# Mutations — each must APPLY (change the file) and then FAIL the assertions.
mutate() {  # $1 = label, $2 = perl -pe expression
  cp "$SRC" "$TMP/mut.swift"
  perl -0pi -e "$2" "$TMP/mut.swift"
  if cmp -s "$SRC" "$TMP/mut.swift"; then echo "  ✗ mutation did not apply: $1"; exit 1; fi
  if run "$TMP/mut.swift" >/dev/null 2>&1; then echo "  ✗ SURVIVED: $1"; exit 1; fi
  echo "  ok   caught  $1"
}
mutate "a link is dropped when the previous step is forgotten" 's/\n                previous = id\n/\n/'
mutate "ends are counted for every run, drawn or not" 's/if let previous, run\.steps\.count <= shown \{/if let previous {/'
mutate "a failed step is folded into its mode" 's/case \.failed:     return \(String\(localized: "Failed"\), \.failed\)/case .failed:     return (step.modeName, .ran)/'
mutate "nodes stop sorting biggest first" 's/: a\.count != b\.count \? a\.count > b\.count/: a.count != b.count ? a.count < b.count/'
echo "✓ frames-flow: the flow's counts, links, ends, outcomes and order, 4 mutations"
