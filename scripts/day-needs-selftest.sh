#!/bin/zsh
# Casberi day-needs self-test — Day gathers every place's Needs you
# (prd §1327 item 9):
#
#   Casberi/Casberi/Model/DayNeeds.swift        (compiled whole: the gather,
#                                                and Work's fold-then-ask)
#   Casberi/Casberi/Model/WalletNeedsYou.swift  (compiled whole against stubs
#                                                of the names it reads)
#   Casberi/Casberi/Model/ObjectFold.swift, ThingLinks.swift, WorkAsk.swift, WorkStage.swift
#
# WHY A HARNESS. Every failure here renders as a calm list. A gather that
# drops its dedupe draws one stuck transfer twice; one that sorts by place
# buries this morning's review under last month's price rise; a Work read that
# asks BEFORE it folds lists an incident that has since resolved; a Wallet rule
# Day copied instead of shared drifts from the Wallet's own list, and the two
# places disagree about what needs you (§837). Only a case-by-case statement
# can say the merge is right, and the drift guards say both places still ask
# the one rule.
#
# Pure, local, deterministic. Exit non-zero on failure. `--self-test` (and
# every plain run) also proves each check can fail: plausible mutations of the
# two files must be CAUGHT.
set -euo pipefail
cd "$(dirname "$0")/.."

DAY="Casberi/Casberi/Model/DayNeeds.swift"
WALLET="Casberi/Casberi/Model/WalletNeedsYou.swift"
FOLD="Casberi/Casberi/Model/ObjectFold.swift"
ASK="Casberi/Casberi/Model/WorkAsk.swift"
LINKS="Casberi/Casberi/Model/ThingLinks.swift"
STAGE="Casberi/Casberi/Model/WorkStage.swift"
SOURCE="Casberi/Casberi/Model/DayNeedsSource.swift"
SCREEN="Casberi/Casberi/Screens/FeedScreen+DayNeeds.swift"
ROOM="Casberi/Casberi/Screens/FeedScreen+MergedRoom.swift"
WROOM="Casberi/Casberi/Screens/FeedScreen+WalletRoom.swift"
TABS="Casberi/Casberi/Design/PlaceTabBar.swift"
for f in "$DAY" "$WALLET" "$FOLD" "$LINKS" "$ASK" "$STAGE" "$SOURCE" "$SCREEN" "$ROOM" "$WROOM" "$TABS"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards -----------------------------------------------------------
# Wiring the compiled functions cannot prove about themselves.
grep -q 'WalletNeedsYou.waiting(' "$WROOM" \
  || { echo "✗ the Wallet's Home no longer asks WalletNeedsYou — Day and the Wallet can disagree"; exit 1; }
grep -q 'WalletNeedsYou.waiting(' "$SOURCE" \
  || { echo "✗ Day no longer asks the Wallet's own rule"; exit 1; }
grep -q 'DayNeeds.workAsks(' "$SOURCE" \
  || { echo "✗ Day no longer reads Work's asks through the fold"; exit 1; }
grep -q 'DayNeeds.gather(' "$SCREEN" \
  || { echo "✗ Day no longer gathers the places into one list"; exit 1; }
grep -q 'dayNeedsSection(nextEventID:' "$ROOM" \
  || { echo "✗ Day's list no longer leads with Needs you"; exit 1; }
grep -q '.task(id: dayNeedsKey)' "$ROOM" \
  || { echo "✗ Day's Needs you is no longer read in a task (prd §628)"; exit 1; }
grep -q 'WorkAsk.needsYou(' "$ROOM" \
  || { echo "✗ Work's own Coming up lost its Needs you — each place keeps its own"; exit 1; }
grep -q 'walletDaySections(\[(Self.needsYouGroup' "Casberi/Casberi/Screens/FeedScreen+WalletHome.swift" \
  || { echo "✗ the Wallet's Home lost its Needs you — each place keeps its own"; exit 1; }
grep -qi 'badge' "$TABS" \
  && { echo "✗ the tab bar wears a badge — the Day tab does not (user, prd §1327 item 9)"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$FOLD" "$LINKS" "$ASK" "$STAGE" "$TMP/"

# Stubs of the names WalletNeedsYou reads, at their shipped spellings.
cat > "$TMP/stubs.swift" <<'SWIFT'
import Foundation
enum SafeBridge { static let sourceName = "Safe" }
enum PrivacyPoolsBridge { static let sourceName = "Privacy Pools" }
enum AppleWalletBridge { static let sourceName = "Apple Wallet" }
struct PrivacyPoolsRoom {
    static let depositPrefix = "privacypools:dep:"
    enum State: String { case pending = "Pending", needsProof = "Needs proof", approved = "Approved"
        var resolved: Bool { self != .pending && self != .needsProof } }
    static func state(tags: [String]) -> State? { tags.lazy.compactMap(State.init(rawValue:)).first }
}
enum WiseShape {
    static let source = "Wise"
    static func isStuck(tags: [String]) -> Bool { tags.contains("Needs attention") }
}
enum ZFiOrders {
    struct Book: Equatable { var waiting: Set<String> = []; var complete = true }
    static let reclaimPrefix = "zfi:reclaim:"
    static func stillWaiting(ref: String, in book: Book) -> Bool {
        guard ref.hasPrefix(reclaimPrefix) else { return false }
        return book.waiting.contains(ref) || !book.complete
    }
}
SWIFT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { failures += 1; print("✗ \(what)") }
}
let now = Date(timeIntervalSince1970: 2_000_000_000)
func ago(_ h: Double) -> Date { now.addingTimeInterval(-h * 3_600) }
func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
func item(_ n: Int, _ place: String, _ h: Double) -> DayNeeds.Item { .init(id: id(n), place: place, at: ago(h)) }

// ── The gather ───────────────────────────────────────────────────────
let wallet = [item(1, "Wallet", 2), item(2, "Wallet", 30)]
let work = [item(3, "Work", 1), item(4, "Work", 5)]
let all = DayNeeds.gather([wallet, work])
check(all.map(\.id) == [id(3), id(1), id(4), id(2)], "every place's rows stand newest first, not place by place")
check(all.count == 4, "nothing is dropped")
check(DayNeeds.gather([[], []]).isEmpty, "nothing waiting gathers nothing — Day draws no section")
let twice = DayNeeds.gather([[item(9, "Wallet", 3)], [item(9, "Work", 3)]])
check(twice.count == 1, "a thing two places hold stands once")
check(twice.first?.place == "Wallet", "under the first place to name it")
let tie = DayNeeds.gather([[item(5, "Wallet", 4)], [item(6, "Work", 4)]])
check(tie.map(\.id) == [id(5), id(6)], "a tie on time keeps Day's place order")
check(DayNeeds.gather([wallet]).map(\.place) == ["Wallet", "Wallet"], "each row keeps the place it came from")

// ── Work: fold, then ask ─────────────────────────────────────────────
func row(_ n: Int, _ source: String, tags: [String] = [], ref: String? = nil, key: String? = nil,
         _ h: Double) -> DayNeeds.WorkRow {
    .init(id: id(n), at: ago(h), key: key,
          row: .init(source: source, sourceRef: ref, title: "x", tags: tags))
}
let rows = [
    row(10, "PagerDuty", tags: ["Incident", "Resolved"], key: "pd:1", 1),   // newest state of incident 1
    row(11, "PagerDuty", tags: ["Incident"], key: "pd:1", 3),               // folded: it resolved
    row(12, "GitHub", tags: ["Notifications", "Review"], 2),
    row(13, "GitHub", tags: ["Notifications"], 4),                          // asks nothing
    row(14, "GitHub", tags: ["Review"], 24 * 8),                            // older than a week
    row(15, "Vercel", tags: ["Build failure"], 0.5),
]
let asks = DayNeeds.workAsks(rows, place: "Work", now: now)
check(asks.map(\.id) == [id(15), id(12)], "Work's asks: the fold first, then WorkAsk, newest first")
check(!asks.contains { $0.id == id(11) }, "an incident since resolved has left — the fold runs before the ask")
check(asks.allSatisfy { $0.place == "Work" }, "Work's rows name Work")

// ── The Wallet's one rule ────────────────────────────────────────────
func waits(_ source: String, ref: String?, tags: [String] = [], at: Date = ago(1),
           safe: Set<String> = [], zfi: ZFiOrders.Book = .init()) -> Bool {
    WalletNeedsYou.waiting(source: source, ref: ref, tags: tags, capturedAt: at,
                           safePending: safe, zfi: zfi, now: now)
}
check(waits("Safe", ref: "safe:tx:1", tags: ["Your turn"], safe: ["safe:tx:1"]), "a Safe transaction waiting on your signature needs you")
check(!waits("Safe", ref: "safe:tx:1", safe: ["safe:tx:1"]), "one collecting others' signatures does not (prd §1340)")
check(!waits("Privacy Pools", ref: "privacypools:dep:1", tags: ["Pending"]), "a deposit under review waits on the screener, not you (prd §1340)")
check(!waits("Safe", ref: "safe:tx:2", safe: ["safe:tx:1"]), "an executed one does not, whatever its tags")
check(waits("Privacy Pools", ref: "privacypools:dep:1", tags: ["Needs proof"]), "a deposit waiting on proof needs you")
check(!waits("Privacy Pools", ref: "privacypools:dep:1", tags: ["Approved"]), "a cleared deposit does not")
check(!waits("Privacy Pools", ref: "privacypools:dep:1"), "an untagged deposit is not called waiting")
check(waits("Wise", ref: "wise:transfer:1", tags: ["Needs attention"]), "a stuck Wise transfer needs you")
check(!waits("Wise", ref: "wise:transfer:2"), "a Wise transfer that moved does not")
check(waits("Wallet", ref: "zfi:reclaim:b:1", zfi: .init(waiting: ["zfi:reclaim:b:1"])), "a zFi escrow still on the board needs you")
check(!waits("Wallet", ref: "zfi:reclaim:b:1"), "one the book no longer lists does not")
check(waits("Apple Wallet", ref: "aw:1", tags: ["Price rise"], at: ago(24 * 29)), "a price rise stands a month")
check(!waits("Apple Wallet", ref: "aw:1", tags: ["Price rise"], at: ago(24 * 31)), "and goes after it")
check(!waits("Apple Wallet", ref: "aw:2", tags: ["Spend"]), "an ordinary charge does not")
check(!waits("Safe", ref: nil, safe: ["x"]), "a row with no ref never waits")
check(WalletNeedsYou.readsBook(ref: "zfi:reclaim:b:1") && !WalletNeedsYou.readsBook(ref: "wise:transfer:1"),
      "the zFi book is read for reclaim rows only")

if failures > 0 { print("✗ day needs: \(failures) failing"); exit(1) }
print("✓ day needs self-test passed")
SWIFT

build() { # $1 DayNeeds.swift, $2 WalletNeedsYou.swift, $3 binary
  swiftc -Onone -o "$3" "$1" "$2" "$TMP/ObjectFold.swift" "$TMP/ThingLinks.swift" "$TMP/WorkAsk.swift" "$TMP/WorkStage.swift" \
    "$TMP/stubs.swift" "$TMP/main.swift" 2>&1 | grep -v '^ *$' || true
}

build "$DAY" "$WALLET" "$TMP/run"
[[ -x "$TMP/run" ]] || { echo "✗ day needs harness did not compile — DayNeeds or WalletNeedsYou no longer builds Foundation-only"; exit 1; }
"$TMP/run" || exit 1

# --- mutation pass ----------------------------------------------------------
# Each mutation is a plausible edit that must be CAUGHT. A check that cannot
# fail proves nothing (the `--self-test` doctrine used by every audit here).
mutate() {
  local label="$1" file="$2" expr="$3"
  python3 - "$file" "$TMP/mutated.swift" "$expr" <<'PY' || { echo "  ✗ STALE MUTATION: the applier exited non-zero (anchor not found — nothing was tested)"; exit 1; }
import sys
src = open(sys.argv[1]).read()
old, new = sys.argv[3].split("|||")
if old not in src:
    sys.exit(f"✗ mutation anchor not found: {old!r} — this harness is testing stale code")
open(sys.argv[2], "w").write(src.replace(old, new, 1))
PY
  rm -f "$TMP/mrun"
  if [[ "$file" == "$DAY" ]]; then build "$TMP/mutated.swift" "$WALLET" "$TMP/mrun" >/dev/null
  else build "$DAY" "$TMP/mutated.swift" "$TMP/mrun" >/dev/null; fi
  if [[ -x "$TMP/mrun" ]] && "$TMP/mrun" >/dev/null 2>&1; then
    echo "  ✗ mutation SURVIVED: $label"
    return 1
  fi
  echo "  ✓ mutation caught: $label"
}

echo "day-needs-selftest: mutation pass…"
mfail=0
mutate "the gather keeps a thing twice" "$DAY" \
  'where seen.insert(item.id).inserted {|||{' || mfail=1
mutate "the gather stands place by place instead of newest first" "$DAY" \
  'a.item.at != b.item.at ? a.item.at > b.item.at : a.order < b.order|||a.order < b.order' || mfail=1
mutate "a tie on time loses Day's place order" "$DAY" \
  ': a.order < b.order|||: a.order > b.order' || mfail=1
mutate "Work asks before it folds" "$DAY" \
  '!hidden.contains($0.id) && WorkAsk|||WorkAsk' || mfail=1
mutate "Work's asks come oldest first" "$DAY" \
  '.sorted { $0.at > $1.at }|||.sorted { $0.at < $1.at }' || mfail=1
mutate "a price rise stands forever" "$WALLET" \
  'return now.timeIntervalSince(capturedAt) < priceRiseWindow|||return true' || mfail=1
mutate "an executed Safe transaction still waits" "$WALLET" \
  'return safePending.contains(ref) && |||return true || ' || mfail=1
mutate "every Wise transfer waits" "$WALLET" \
  'return WiseShape.isStuck(tags: tags)|||return true' || mfail=1
mutate "a deposit under review is called waiting" "$WALLET" \
  'PrivacyPoolsRoom.state(tags: tags) == .needsProof|||PrivacyPoolsRoom.state(tags: tags).map { !$0.resolved } ?? false' || mfail=1
mutate "a Safe transaction waiting on others still waits on you" "$WALLET" \
  'safePending.contains(ref) && tags.contains("Your turn")|||safePending.contains(ref)' || mfail=1

[[ $mfail -eq 0 ]] || { echo "day-needs-selftest: a mutation SURVIVED — a check above proves nothing"; exit 1; }
echo "day-needs-selftest: OK — the gather, Work's fold-then-ask and the Wallet's one rule all pinned."
