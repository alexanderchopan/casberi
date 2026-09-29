#!/bin/zsh
# Casberi music-shelf self-test — the music rooms' tiles (prd §995):
#
#   Casberi/Casberi/Model/MusicShelf.swift   (compiled WHOLE, Foundation-only)
#
# WHY A HARNESS. Every failure here renders as an ordinary A–Z list:
#
#   · "Émile" filed under a letter of its own, or a song starting with a digit
#     leading the list instead of standing under # at the end
#   · Spotify's "(2016)" left on an album's name, so each year is an album
#   · "Blonde" and "blonde" as two albums, their songs split between them
#   · an album called "1999 (Deluxe)" losing its own parentheses
#
# Plus drift guards for the wiring no function can prove: the room draws the
# tiles, every room's grid draws A–Z with its lead first (user, 2026-09-29:
# "that's a rule for any room"), and each tile has its own glyph.
# Pure, local, no simulator.
set -euo pipefail
cd "$(dirname "$0")/.."

SHELF="Casberi/Casberi/Model/MusicShelf.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
TILES="Casberi/Casberi/Design/DSScopeTiles.swift"
GLYPHS="Casberi/Casberi/Screens/ScopeTileGlyphs.swift"
SURFACE="Casberi/Casberi/Shell/MainSurface.swift"
for f in "$SHELF" "$FEED" "$TILES" "$GLYPHS" "$SURFACE"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP="$(mktemp -d /tmp/music-shelf-selftest.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

fail=0
guard() {  # name, pattern, file
  if grep -qE -- "$2" "$3"; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=1; fi
}

echo "Drift guards"
guard "the music face draws its own sections"       'case \.music:[[:space:]]*$'                          "$FEED"
guard "…through musicSections"                      'musicSections\(visible, nextEventID: nextEventID, heroShown: heroShown\)' "$FEED"
guard "Albums and Artists stand only over a name"   '!scope\.groups \|\| live\.contains \{ musicName\(\$0, scope\) != nil \}' "$FEED"
guard "a room change opens on Activity"             'chrome\.musicScope = \.activity'                     "$SURFACE"
guard "the grid draws A–Z, lead first"              'ForEach\(Self\.alphabetical\(sections, verbs: verbs\)\)' "$TILES"
guard "…sorted by the word the person reads"        '\.sorted \{ \$0\.label\.localizedStandardCompare\(\$1\.label\) == \.orderedAscending \}' "$TILES"
guard "…All and Home first, verbs last"            'return leads \+ middle \+ tail'                       "$TILES"
guard "…a lead known by its glyph, never by place"  '\$0\.glyph == ScopeTileGlyph\.all \|\| \$0\.glyph == ScopeTileGlyph\.home' "$TILES"
guard "Songs wears its own glyph"                   'case \.songs:    return ScopeTileGlyph\.songs'       "$GLYPHS"
guard "Albums wears its own glyph"                  'case \.albums:   return ScopeTileGlyph\.albums'      "$GLYPHS"
guard "Artists wears its own glyph"                 'case \.artists:  return ScopeTileGlyph\.artists'     "$GLYPHS"
[[ $fail -eq 0 ]] || { echo "music-shelf-selftest: ✗ drift guard(s) failed"; exit 1; }

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ name: String) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

print("Tile order")
check(MusicScope.allCases == [.activity, .albums, .artists, .songs],
      "the tiles are A–Z and open on Activity (got \(MusicScope.allCases))")
check(MusicScope.allCases.filter(\.groups) == [.albums, .artists], "Albums and Artists are the name lists")

print("Letters")
check(MusicShelf.letter("Reckoner") == "R", "a name files under its first letter")
check(MusicShelf.letter("avril 14th") == "A", "lower case files under the capital")
check(MusicShelf.letter("Ágætis byrjun") == "A", "an accent folds to its letter")
check(MusicShelf.letter("1999") == "#", "a digit files under #")
check(MusicShelf.letter("   ") == "#", "a blank name files under #")

print("Sections")
let names = ["teardrop", "Xtal", "Avril 14th", "22 Acacia Avenue", "Ágætis", "Reckoner", "roygbiv"]
let sections = MusicShelf.sections(names) { $0 }
check(sections.map(\.letter) == ["A", "R", "T", "X", "#"],
      "letters in order, # last (got \(sections.map(\.letter)))")
check(sections.first?.items == ["Ágætis", "Avril 14th"], "one section per letter, A–Z inside it (got \(sections.first?.items ?? []))")
check(sections[1].items == ["Reckoner", "roygbiv"], "case does not split a letter")
check(MusicShelf.sections(["Track 10", "Track 2"]) { $0 }.first?.items == ["Track 2", "Track 10"],
      "numbers sort as numbers")

print("Groups")
let groups = MusicShelf.groups([("Blonde", "a"), ("blonde ", nil), (nil, "x"), ("  ", "y"), ("Endless", nil)])
let blonde = groups.first { MusicShelf.key($0.name) == MusicShelf.key("Blonde") }
check(groups.count == 2, "one group per name, a missing name nowhere (got \(groups.count))")
check(blonde?.count == 2, "two spellings are one album")
check(blonde?.name == "Blonde", "the name as first met")
check(blonde?.art == "a", "the first artwork met")
check(groups.first { $0.name == "Endless" }?.art == nil, "no artwork is none")

print("Albums")
check(MusicShelf.album(fact: "In Rainbows", summary: nil) == "In Rainbows", "Apple Music's fact")
check(MusicShelf.album(fact: "  ", summary: "From Blonde (2016)") == "Blonde", "a blank fact falls to the line")
check(MusicShelf.album(fact: nil, summary: "From Blonde (2016)") == "Blonde", "Spotify's year is dropped")
check(MusicShelf.album(fact: nil, summary: "From Blonde (2016) · from playlist") == "Blonde",
      "the play's context is dropped")
check(MusicShelf.album(fact: nil, summary: "From Blonde · from playlist") == "Blonde", "no year, context dropped")
check(MusicShelf.album(fact: nil, summary: "From 1999 (Deluxe)") == "1999 (Deluxe)",
      "an album's own parentheses are kept")
check(MusicShelf.album(fact: nil, summary: "from playlist") == nil, "a context alone is no album")
check(MusicShelf.album(fact: nil, summary: nil) == nil, "nothing is no album")

print("Artists")
check(MusicShelf.artist(handle: "Radiohead", titleLine: "Other") == "Radiohead", "the stored handle first")
check(MusicShelf.artist(handle: " ", titleLine: "Bibio") == "Bibio", "else the title's line")
check(MusicShelf.artist(handle: nil, titleLine: nil) == nil, "nothing is no artist")

if failures > 0 { print("music-shelf-selftest: ✗ \(failures) assertion(s) failed"); exit(1) }
SWIFT

if ! swiftc -Onone -o "$TMP/run" "$SHELF" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ MusicShelf.swift did not compile against the harness"; cat "$TMP/build.log"; exit 1
fi
"$TMP/run"

echo "Mutations"
mutate() {
  local name="$1" from="$2" to="$3"
  local a="$TMP/mut.swift"
  cp "$SHELF" "$a"
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

mutate "the tiles in the old order" \
  'case activity, albums, artists, songs' \
  'case activity, songs, albums, artists'
mutate "accents keep their own letter" \
  'options: [.diacriticInsensitive, .caseInsensitive],' \
  'options: [.caseInsensitive],'
mutate "# leads instead of trailing" \
  'if !tail.isEmpty { out.append(("#", tail)) }' \
  'if !tail.isEmpty { out.insert(("#", tail), at: 0) }'
mutate "names sort by code point" \
  'a.localizedStandardCompare(b) == .orderedAscending' \
  'a < b'
mutate "two spellings are two albums" \
  'let k = key(name)' \
  'let k = name'
mutate "Spotify's year stays on the album" \
  'if inner.count == 4, inner.allSatisfy(\.isNumber) { line = String(line[..<open.lowerBound]) }' \
  'if inner.count == 99 { line = String(line[..<open.lowerBound]) }'
mutate "the play's context stays on the album" \
  'if let dot = line.range(of: " · ") { line = String(line[..<dot.lowerBound]) }' \
  ''
mutate "the title's line is never read" \
  'for raw in [handle, titleLine] {' \
  'for raw in [handle] {'

echo "music-shelf-selftest: OK — assertions and mutations both pass."
