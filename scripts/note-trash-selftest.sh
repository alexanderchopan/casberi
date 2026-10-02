#!/bin/zsh
# Casberi note-trash self-test — Recently Deleted (prd §985).
#
#   Casberi/Casberi/Model/NoteTrashRules.swift   (compiled whole)
#
# WHY A HARNESS. Every failure here is a note that is gone when the app said it
# was not, and nothing on a screen shows it until the day somebody needs it:
#
#   · a window that rounds a last hour down to "0 days" reads as already gone
#   · a note deleted BEFORE it is archived is lost if the archive write fails
#   · Delete everything that leaves the archive behind keeps words the person
#     asked to erase
#   · the dialog promising thirty days over a delete that archives nothing
#
# Pure, local, deterministic. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

RULES="Casberi/Casberi/Model/NoteTrashRules.swift"
STORE="Casberi/Casberi/Model/NoteTrash.swift"
# FeedScreen is split across files (prd §718). Checks read the room as ONE text,
# so a guard can neither fail nor pass because its code moved next door.
FEED_DIR="$(mktemp -d)"
FEED="$FEED_DIR/FeedScreen.swift"
cat Casberi/Casberi/Screens/FeedScreen.swift Casberi/Casberi/Screens/FeedScreen+*.swift > "$FEED"
ACCOUNT="Casberi/Casberi/Screens/AccountDetailSheet.swift"
for f in "$RULES" "$STORE" "$FEED" "$ACCOUNT"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP="$(mktemp -d /tmp/note-trash-selftest.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

fail=0
guard() {  # name, pattern, file
  if grep -qE -- "$2" "$3"; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=1; fi
}

echo "Drift guards"
# The archive write GATES the delete: `keep` returns before `modelContext.delete`.
if python3 - "$FEED" <<'PY'
import sys
src = open(sys.argv[1]).read()
start = src.index("func deleteNote(_ thing: Thing)")
body = src[start:start + 1500]
k, d = body.find("guard NoteTrash.shared.keep(thing) else"), body.find("modelContext.delete(thing)")
sys.exit(0 if 0 <= k < d else 1)
PY
then echo "  ✓ a note is archived before it is deleted, and kept if the archive fails"
else echo "  ✗ a note is archived before it is deleted, and kept if the archive fails"; fail=1; fi
guard "the dialog states the window it promises"   'It stays in Recently deleted for \\\(NoteTrashRules\.keepDays\) days' "$FEED"
guard "Delete everything empties the archive"      'NoteTrash\.shared\.eraseAll\(\)'        "$ACCOUNT"
guard "the archive purges at launch"               'purgeExpired\(\)'                          "$STORE"
guard "a voice or locked note is not recovered without its bytes" 'if entry\.hasAudio && audio == nil \{ return nil \}' "$STORE"
[[ $fail -eq 0 ]] || { echo "note-trash-selftest: ✗ drift guard(s) failed"; exit 1; }

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ name: String) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}
let day: TimeInterval = 86_400
let t0 = Date(timeIntervalSince1970: 1_800_000_000)

print("The window")
check(NoteTrashRules.daysLeft(t0, now: t0.addingTimeInterval(60)) == 30, "a note deleted a minute ago has 30 days")
check(NoteTrashRules.daysLeft(t0, now: t0.addingTimeInterval(29 * day + 3600)) == 1, "the last day reads 1, never 0")
check(!NoteTrashRules.isExpired(t0, now: t0.addingTimeInterval(30 * day - 1)), "not gone a second early")
check(NoteTrashRules.isExpired(t0, now: t0.addingTimeInterval(30 * day)), "gone at thirty days")
check(NoteTrashRules.daysLeft(t0, now: t0.addingTimeInterval(31 * day)) == 0, "past the window there is nothing left")

print("The list")
func entry(_ at: TimeInterval) -> NoteTrashEntry {
    NoteTrashEntry(id: UUID(), kind: "note", title: "t", content: "", source: "You",
                   createdAt: t0, capturedAt: t0, tags: [], sourceRef: nil, folder: nil,
                   pinnedAt: nil, wikilinks: [], deletedAt: t0.addingTimeInterval(at),
                   hasPicture: false, hasAudio: false)
}
let older = entry(0), newer = entry(day)
check(NoteTrashRules.ordered([older, newer]) == [newer, older], "the newest deletion leads")

print("An entry survives the disk")
let e = NoteTrashEntry(id: UUID(), kind: "voice", title: "Locked note", content: "", source: "You",
                       createdAt: t0, capturedAt: t0, tags: ["Note"], sourceRef: "notelock:v1",
                       folder: "Home", pinnedAt: t0, wikilinks: ["Book club"], deletedAt: t0,
                       hasPicture: true, hasAudio: true)
let round = try! JSONDecoder().decode(NoteTrashEntry.self, from: JSONEncoder().encode(e))
check(round == e, "every field comes back, the lock's mark and the folder included")

if failures > 0 { print("note-trash-selftest: ✗ \(failures) assertion(s) failed"); exit(1) }
SWIFT

if ! swiftc -Onone -o "$TMP/run" "$RULES" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ NoteTrashRules.swift did not compile against the harness"; cat "$TMP/build.log"; exit 1
fi
"$TMP/run"

echo "Mutations"
mutate() {
  local name="$1" from="$2" to="$3"
  local a="$TMP/mut.swift"
  cp "$RULES" "$a"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$a" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$a"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -Onone -o "$TMP/mut" "$a" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

mutate "the last day rounds down to 0" '(seconds / 86_400).rounded(.up)' '(seconds / 86_400).rounded(.down)'
mutate "a note expires a day early"    'static let keepDays = 30'        'static let keepDays = 29'
mutate "the oldest deletion leads"     '$0.deletedAt > $1.deletedAt'     '$0.deletedAt < $1.deletedAt'
mutate "an expired note lingers"       'now >= expiry(of: deletedAt)'    'now > expiry(of: deletedAt).addingTimeInterval(86_400)'

echo "note-trash-selftest: OK — guards, assertions and mutations all pass."
