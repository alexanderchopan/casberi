#!/bin/zsh
# Casberi note-folders self-test — the Notes room's folders (prd §980):
#
#   Casberi/Casberi/Model/NoteFolders.swift   (compiled WHOLE, Foundation-only)
#
# WHY A HARNESS. Every failure here renders as an ordinary folder list:
#
#   · "Recipes" and "recipes" as two folders, the room's rows split between
#     them with nothing on screen saying why
#   · a folder a row carries but the store has not heard of (the key-value
#     mirror lands after CloudKit) missing from the list, so its rows are
#     filed somewhere no tap can reach
#   · a name of spaces kept as a folder with no visible name
#
# Plus drift guards for the wiring no function can prove: the room scopes on
# the folder, New files into the open folder, the row menu reaches the store,
# and the tile has a case and a glyph. Pure, local, no simulator.
set -euo pipefail
cd "$(dirname "$0")/.."

FOLDERS="Casberi/Casberi/Model/NoteFolders.swift"
STORE="Casberi/Casberi/Model/NoteFolderStore.swift"
PINBOARD="Casberi/Casberi/Model/Pinboard.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
SHEET="Casberi/Casberi/Shell/NoteCaptureSheet.swift"
GLYPHS="Casberi/Casberi/Screens/ScopeTileGlyphs.swift"
THING="Casberi/Shared/Thing.swift"
CKDB="docs/cloudkit-schema.ckdb"
for f in "$FOLDERS" "$STORE" "$PINBOARD" "$FEED" "$SHEET" "$GLYPHS" "$THING" "$CKDB"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP="$(mktemp -d /tmp/note-folders-selftest.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

fail=0
guard() {  # name, pattern, file
  if grep -qE -- "$2" "$3"; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=1; fi
}

echo "Drift guards"
guard "Thing carries its folder"                    'var folder: String\? = nil'                "$THING"
guard "CD_folder is in the checked-in schema"       'CD_folder +STRING'                         "$CKDB"
guard "the tile row has a Folders case"             'case all, pinned, folders, new'            "$PINBOARD"
guard "the Folders tile wears the folder glyph"     'case \.folders: return ScopeTileGlyph\.folders' "$GLYPHS"
guard "the room scopes on the open folder"          'NoteFolderName\.key\(filed\) == NoteFolderName\.key\(open\)' "$FEED"
guard "the folder list reads the store and the rows" 'NoteFolderStore\.shared\.list\(with: filed\)' "$FEED"
guard "the row menu files through the screen"      'onFile: fileThing, onNewFolder:'           "$FEED"
guard "the row menu offers any row in the room"     'if let onFile, Pinboard\.inRoom\(thing\)'  "$FEED"
guard "a typed note is filed in the open folder"    'thing\.folder = filingFolder'              "$SHEET"
guard "a spoken note is filed in the open folder"   'thing\.folder = folder'                    "$SHEET"
guard "New files only under the Folders tile"       'chrome\.notesScope == \.folders \? chrome\.notesFolder : nil' "$SHEET"
guard "deleting a folder unfiles, never deletes"    'for thing in members\(of: name, in: context\) \{ thing\.folder = nil \}' "$STORE"
[[ $fail -eq 0 ]] || { echo "note-folders-selftest: ✗ drift guard(s) failed"; exit 1; }

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ name: String) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

print("Names")
check(NoteFolderName.clean("  Recipes  ") == "Recipes", "whitespace is trimmed")
check(NoteFolderName.clean("Trip \n  to   Lisbon") == "Trip to Lisbon", "inner runs collapse to one space")
check(NoteFolderName.clean("   ") == nil, "a name of spaces is no folder")
check(NoteFolderName.clean("") == nil, "an empty name is no folder")
check(NoteFolderName.clean(String(repeating: "a", count: 90))?.count == NoteFolderName.maxLength,
      "a long name is clamped to one row")
check(NoteFolderName.key("Recipes") == NoteFolderName.key("recipes"), "case is one folder")
check(NoteFolderName.key("Café") == NoteFolderName.key("cafe"), "accents are one folder")
check(NoteFolderName.key("Work") != NoteFolderName.key("Home"), "two names are two folders")
check(NoteFolderName.existing("recipes", in: ["Home", "Recipes"]) == "Recipes",
      "a later spelling files into the first")
check(NoteFolderName.existing("Ideas", in: ["Home", "Recipes"]) == nil, "a new name is new")

print("The list")
let list = NoteFolderName.list(stored: ["Recipes", "home"], filed: ["recipes", nil, "Trips", "Trips"])
check(list == ["home", "Recipes", "Trips"], "stored and filed, one each, Finder's order (got \(list))")
check(NoteFolderName.list(stored: [], filed: ["Trips"]) == ["Trips"],
      "a folder only a row carries is listed")
check(NoteFolderName.list(stored: ["Empty"], filed: []) == ["Empty"],
      "an empty stored folder is listed")
check(NoteFolderName.list(stored: ["Folder 10", "Folder 2"], filed: []) == ["Folder 2", "Folder 10"],
      "numbers sort as numbers")
check(NoteFolderName.list(stored: ["  "], filed: []) == [], "a blank stored name is dropped")

print("Counts")
let counts = NoteFolderName.counts(filed: ["Recipes", "recipes", nil, "Trips"])
check(counts[NoteFolderName.key("Recipes")] == 2, "two spellings count as one folder")
check(counts[NoteFolderName.key("Trips")] == 1, "each folder counts its own")
check(counts.count == 2, "an unfiled row counts nowhere")

if failures > 0 { print("note-folders-selftest: ✗ \(failures) assertion(s) failed"); exit(1) }
SWIFT

if ! swiftc -Onone -o "$TMP/run" "$FOLDERS" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ NoteFolders.swift did not compile against the harness"; cat "$TMP/build.log"; exit 1
fi
"$TMP/run"

echo "Mutations"
mutate() {
  local name="$1" from="$2" to="$3"
  local a="$TMP/mut.swift"
  cp "$FOLDERS" "$a"
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

mutate "two spellings are two folders" \
  'name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)' \
  'name'
mutate "a folder only a row carries is dropped" \
  'for name in stored + filed.compactMap({ $0 }) {' \
  'for name in stored {'
mutate "a blank name is kept" \
  'return clamped.isEmpty ? nil : clamped' \
  'return clamped'
mutate "names are never clamped" \
  'String(joined.prefix(maxLength))' \
  'String(joined)'
mutate "the list is in stored order" \
  'return out.sorted { $0.localizedStandardCompare($1) == .orderedAscending }' \
  'return out'
mutate "counts split by spelling" \
  'out[key(name), default: 0] += 1' \
  'out[name, default: 0] += 1'

echo "note-folders-selftest: OK — assertions and mutations both pass."
