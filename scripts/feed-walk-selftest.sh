#!/bin/zsh
# Casberi feed-walk self-test — next and previous, following the list you
# actually opened from (prd §645 pass 3, 2026-09-08).
#
#   Casberi/Casberi/Model/SheetWalk.swift  — WalkScope + SheetWalk.eligible
#
# Foundation-only BY DESIGN and compiled WHOLE AND UNMODIFIED. The FETCH is
# SwiftData and stays in `NoteSheetSource`; what is here is the part that
# decides, which is the part that can be wrong quietly.
#
# WHY A HARNESS. Every failure in this pass draws a perfectly ordinary pair of
# chevrons and is invisible to a build, an audit and a screen sweep — you only
# find it by opening a door and noticing the row behind it was never on the
# list:
#
#   • the scope dropped on the way into the route, so the doors walk the WHOLE
#     corpus from inside a room — the failure A.3 names first;
#   • the import-receipt filter lost, which §399 paid for by hand: a door onto
#     our own note about a sync, from inside somebody's diary;
#   • the All room's doors walking into a bulk import's dump — thousands of
#     rows dated across years that the All list deliberately hides, so the walk
#     leaves the list without saying so;
#   • a kind-filtered room walking rows of every other kind;
#   • a narrowed room (pinned, a wallet, a person, a vibenet account) drawing
#     doors at all, when its membership cannot be rebuilt from a source and a
#     kind — an absent door is honest, a wrong one is not;
#   • the scope left out of the route's `id`, so the same thing opened from two
#     rooms is ONE identity to SwiftUI and the second open silently reuses the
#     first's doors.
#
# WHAT THIS CANNOT PROVE. That the fetch's own predicate matches the scope —
# that is SwiftData, and `swiftdata-liveness-audit.py` plus the drift guards
# below are what cover it. And nothing renders.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

WALK="Casberi/Casberi/Model/SheetWalk.swift"
SOURCE="Casberi/Casberi/Model/NoteSheetSource.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
SHEET="Casberi/Casberi/Screens/ThingSheetView.swift"
for f in "$WALK" "$SOURCE" "$FEED" "$SHEET"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/feed-walk-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

strip_comments() {
  python3 - "$1" <<'PY'
import re, sys
src = re.sub(r"/\*.*?\*/", "", open(sys.argv[1]).read(), flags=re.S)
print("\n".join(l for l in src.splitlines() if not l.strip().startswith("//")))
PY
}
strip_comments "$FEED"  > "$TMP/feed.nocomment"
strip_comments "$SHEET" > "$TMP/sheet.nocomment"

# --- drift guards -----------------------------------------------------------
echo "drift guards"
# THE ROUTE CARRIES THE SCOPE, and its identity folds it in.
grep -q 'case thing(Thing, walk: WalkScope)' "$TMP/feed.nocomment" \
  || { echo "✗ FeedSheetRoute.thing no longer carries a scope — every sheet"; \
       echo "  would walk on its own source, or on nothing"; exit 1; }
grep -q 'thing:\\(t.id.uuidString)@\\(walk.key)' "$TMP/feed.nocomment" \
  || { echo "✗ the route's id no longer folds the scope in — the same thing"; \
       echo "  opened from two rooms is ONE identity to SwiftUI, and the second"; \
       echo "  open reuses the first's doors"; exit 1; }
# NEVER A [Thing]. Corollary 4, build 177, and A.3 says it in as many words.
python3 - "$TMP/feed.nocomment" <<'PY' || exit 1
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r"case thing\(Thing, walk: ([^)]*)\)", src)
if m and "[" in m.group(1):
    print("✗ FeedSheetRoute.thing carries an ARRAY — a held [Thing] handed")
    print("  onward is docs/liveness.md corollary 4 and build 177 exactly")
    sys.exit(1)
PY
# The row tap uses the live filter; the heroes and shelves do not.
grep -q 'private var rowWalk: WalkScope' "$TMP/feed.nocomment" \
  || { echo "✗ FeedScreen has no rowWalk — the row tap cannot say which list"; \
       echo "  it came from"; exit 1; }
grep -q 'detail.present(thing, walk: walk)' "$TMP/feed.nocomment" \
  || { echo "✗ the iPad pane is handed no scope — the doors would vanish on"; \
       echo "  exactly the device with room to draw them"; exit 1; }
# The four narrowings the fetch cannot rebuild must all reach `narrowed`.
for narrowing in 'Pinboard.isPinnedRoom(source)' 'selectedWallet != nil' \
                 'chrome.personScope != nil' 'chrome.vibenetScope != nil'; do
  grep -qF -- "$narrowing" "$TMP/feed.nocomment" \
    || { echo "✗ rowWalk does not consider $narrowing — a room narrowed by it"; \
         echo "  would draw doors onto rows its own list is hiding"; exit 1; }
done
# The sheet gates on the scope, not on a note shape.
grep -q 'if walk.walks {' "$TMP/sheet.nocomment" \
  || { echo "✗ the sheet no longer gates its neighbour read on the scope"; exit 1; }
grep -q 'NoteSheetSource.neighbours(of: thing, scope: walk' "$TMP/sheet.nocomment" \
  || { echo "✗ the sheet's neighbour read is unscoped — it would walk the row's"; \
       echo "  own source from inside a list that is showing something else"; exit 1; }
grep -q 'ThingSheetView(thing: note.thing, walk: walkingToScope)' "$TMP/sheet.nocomment" \
  || { echo "✗ a walked-to sheet inherits no scope — the second door would"; \
       echo "  stop following the list"; exit 1; }
# The fetch keeps its bound.
grep -q 'd.fetchLimit = SheetWalk.fetchWindow' "$SOURCE" \
  || { echo "✗ the neighbour fetch is unbounded, or bounded by a literal that"; \
       echo "  cannot move with the rule that rejects rows"; exit 1; }
echo "  ✓ the route carries a scope by value, and its id folds it in"
echo "  ✓ the row tap scopes; the heroes, shelves and the pane are explicit"
echo "  ✓ the sheet gates on the scope and passes it on"

# --- the driver -------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}
typealias Row = SheetWalk.Row
func row(_ id: String, source: String = "RSS", tags: [String] = [],
         receipt: Bool = false, showsInAll: Bool = true,
         searchOnly: Bool = false) -> Row {
    Row(id: id, source: source, tags: tags, isReceipt: receipt,
        showsInAll: showsInAll, searchOnly: searchOnly)
}

// ── the scope a room hands over ───────────────────────────────────────────
print("WalkScope.feed")
let all = WalkScope.feed(source: "All", tag: "All", narrowed: false)
check("the All room walks, scoped to no source", all.walks && all.source == nil)
check("…and to no kind", all.typeTag == nil)
let room = WalkScope.feed(source: "Obsidian", tag: "All", narrowed: false)
check("a source room carries its source", room.source == "Obsidian")
let kinded = WalkScope.feed(source: "RSS", tag: "Links", narrowed: false)
check("a kind-filtered room carries both", kinded.source == "RSS" && kinded.typeTag == "Links")
// THE HONEST ABSENCE (A.3 rule 4).
check("a narrowed room does not walk at all",
      !WalkScope.feed(source: "Bluesky", tag: "All", narrowed: true).walks)
check("…and carries nothing that could be read as a scope",
      WalkScope.feed(source: "Bluesky", tag: "All", narrowed: true).source == nil)
check("WalkScope.none does not walk", !WalkScope.none.walks)

// ── the identity ──────────────────────────────────────────────────────────
print("\nthe route key")
check("two rooms give two keys", room.key != all.key)
check("a room and the same room kind-filtered give two keys", room.key != kinded.key)
check("every non-walking scope shares one key",
      WalkScope.none.key == WalkScope.feed(source: "X", tag: "All", narrowed: true).key)

// ── eligibility ───────────────────────────────────────────────────────────
print("\nSheetWalk.eligible — the list you opened from")
check("a row in the same room is walkable",
      SheetWalk.eligible(row("b", source: "Obsidian"), scope: room, from: "a"))
check("a row from ANOTHER source is not",
      !SheetWalk.eligible(row("b", source: "Substack"), scope: room, from: "a"))
check("the thing itself is never its own neighbour",
      !SheetWalk.eligible(row("a", source: "Obsidian"), scope: room, from: "a"))
check("a scope that does not walk offers nothing",
      !SheetWalk.eligible(row("b", source: "Obsidian"), scope: .none, from: "a"))

print("\n…the import receipt (§399 paid for this one by hand)")
check("a receipt is never offered",
      !SheetWalk.eligible(row("b", source: "Obsidian", receipt: true), scope: room, from: "a"))
check("…and the row beside it still is",
      SheetWalk.eligible(row("b", source: "Obsidian", receipt: false), scope: room, from: "a"))

print("\n…the All room hides a bulk import's dump")
check("a row the All list hides is not walked to",
      !SheetWalk.eligible(row("b", source: "Instagram", showsInAll: false), scope: all, from: "a"))
// …but INSIDE that source's own room it is exactly what the list shows.
let instagram = WalkScope.feed(source: "Instagram", tag: "All", narrowed: false)
check("…and inside its own room it is",
      SheetWalk.eligible(row("b", source: "Instagram", showsInAll: false),
                         scope: instagram, from: "a"))

print("\n…the search-only corpus is on no list")
check("a search-only row is never walked to, even in its own room",
      !SheetWalk.eligible(row("b", source: "Contacts", searchOnly: true),
                          scope: WalkScope.feed(source: "Contacts", tag: "All", narrowed: false),
                          from: "a"))

print("\n…a kind filter")
check("a row of the filtered kind is walkable",
      SheetWalk.eligible(row("b", source: "RSS", tags: ["Links"]), scope: kinded, from: "a"))
check("a row of another kind is not",
      !SheetWalk.eligible(row("b", source: "RSS", tags: ["Note"]), scope: kinded, from: "a"))
check("…and a row with no tags at all is not",
      !SheetWalk.eligible(row("b", source: "RSS"), scope: kinded, from: "a"))

print("\nthe fetch window")
check("the window is bounded", SheetWalk.fetchWindow > 2 && SheetWalk.fetchWindow <= 100)

print(failures == 0 ? "\nAll assertions passed." : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

if ! swiftc -Onone -o "$TMP/run" "$WALK" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ the shipped SheetWalk.swift did not compile against the harness"
  grep -E 'error:' "$TMP/build.log" | head -20
  exit 1
fi
"$TMP/run"

# --- mutations --------------------------------------------------------------
echo
echo "mutations (each must be caught)"
WORK="$TMP/work"
mutate() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$WALK" "$WORK/SheetWalk.swift"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/SheetWalk.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$WORK/SheetWalk.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved,"
    echo "    so this guard has been testing nothing)"; exit 1
  fi
  if ! swiftc -Onone -o "$TMP/mut" "$WORK/SheetWalk.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 1. THE ONE A.3 NAMES FIRST: the scope dropped, so the doors walk the whole
#    corpus from inside a room.
mutate "the source scope dropped" \
  'if let source = scope.source {
            guard row.source == source else { return false }' \
  'if let source = scope.source {
            guard row.source == source || true else { return false }'

# 2. THE ONE §399 PAID FOR: the receipt filter lost — a door onto our own note
#    about a sync, from inside somebody'\''s diary.
mutate "the import-receipt filter lost" \
  'guard !row.isReceipt else { return false }' \
  'guard true else { return false }'

# 3. A narrowed room made to walk anyway.
mutate "a narrowed room walks" \
  'guard !narrowed else { return .none }' \
  'if false { return .none }'

# 4. The All room walking into a bulk import'\''s dump.
mutate "the All room walks a hidden dump" \
  'guard row.showsInAll else { return false }' \
  'guard row.showsInAll || true else { return false }'

# 5. The kind filter dropped.
mutate "the kind filter dropped" \
  'guard row.tags.contains(tag) else { return false }' \
  'guard row.tags.contains(tag) || true else { return false }'

# 6. A row offered as its own neighbour.
mutate "a thing offered as its own neighbour" \
  'guard scope.walks, row.id != selfID else { return false }' \
  'guard scope.walks else { return false }'

# 7. The search-only corpus walked into.
mutate "the search-only corpus walked into" \
  'guard !row.searchOnly else { return false }' \
  'guard !row.searchOnly || true else { return false }'

# 8. The key stops distinguishing rooms, so two opens are one identity.
mutate "the route key stops naming the room" \
  'walks ? "\(source ?? "*")/\(typeTag ?? "*")" : "-"' \
  '"-"'

echo
echo "✓ feed-walk self-test: assertions and mutations all passed"
