#!/bin/zsh
# Casberi Instagram self-test — the SHIPPED pure judgement behind the Instagram
# room's head, plus the wiring that head and the rest of prd §395 rest on:
#
#   Casberi/Casberi/Model/InstagramRoom.swift   (compiled WHOLE and unmodified)
#
# It is Foundation-only BY DESIGN, so it is compiled as shipped rather than
# extracted — the strongest form of "the harness ran the shipped logic".
# Everything that touches `Thing` lives in `InstagramRoomSource.swift`, which no
# harness can compile and which contains no judgement to test.
#
# WHY A HARNESS AND NOT A LIVE CHECK. Nothing on this host has ever imported a
# real Instagram export — the seat is export-only by construction (prd §245:
# Meta's Basic Display API died in 2024 and its replacement needs a Professional
# account), so there is no key to mint and no account to open. Every failure
# here is a SILENT WRONG ANSWER that renders perfectly:
#
#   · saves and likes summed into one board, which is a number with no meaning
#     (§247's ruling, and the one this card is most able to break)
#   · a board that reshuffles between two opens of the same corpus, because the
#     tie-break stopped being total
#   · "from 4 accounts" over a library of four hundred, because the count came
#     from the DRAWN rows rather than all of them
#   · a card claiming a library exists over eleven taps
#   · a year printed as a quantity — "All from 2,019" — in the note under the
#     headline (the §375 finding, in the room next door)
#   · NaN bar widths from a zero leader, which SwiftUI draws as no bar at all
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

ROOM="Casberi/Casberi/Model/InstagramRoom.swift"
LEDE="Casberi/Casberi/Model/RoomLede.swift"   # prd §585 — the shared lede type these rooms now return
SRC="Casberi/Casberi/Model/InstagramRoomSource.swift"
IMPORT="Casberi/Casberi/Model/InstagramImport.swift"
CAPTIONS="Casberi/Casberi/Model/InstagramCaptions.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
INSIGHT="Casberi/Casberi/Model/FeedInsight.swift"
RETRIEVER="Casberi/Casberi/Model/Retriever.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
for f in "$ROOM" "$SRC" "$IMPORT" "$CAPTIONS" "$FEED" "$INSIGHT" "$RETRIEVER" "$REACH"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# A comment-stripped copy for the NEGATIVE guards below. Three of these files
# document the rules they follow by NAMING the thing they must not do, so a
# guard grepping raw source fires against the prose explaining it — the
# Obsidian/Cursor lesson, paid for twice already in this repo.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
strip_comments() {
  python3 - "$1" > "$2" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
out = []
for line in src.split("\n"):
    s = line.lstrip()
    if s.startswith("//") or s.startswith("///"):
        continue
    out.append(line)
print("\n".join(out))
PY
}
strip_comments "$IMPORT" "$TMP/import.nc"
strip_comments "$CAPTIONS" "$TMP/captions.nc"
strip_comments "$FEED" "$TMP/feed.nc"

# --- drift guards -----------------------------------------------------------
# Each is a wiring fact the compiled head cannot prove about itself: a perfect
# `compose` is worthless if nothing calls it, and a perfect `Keep` is worthless
# if the rows never carry the fields it reads.

# THE ROOM'S SHAPE (prd §395). Instagram had no `Shape` case at all until this
# date, so a photo app's room drew as band rows over pixels the importer had
# been storing since §310. If this case goes, it silently does so again.
grep -qF 'case "Instagram":           self = .instagram' "$TMP/feed.nc" \
  || { echo "✗ Instagram has no feed Shape — the room falls back to plain band rows over its own pictures"; exit 1; }
grep -qF 'isInstagramPhotoTile' "$TMP/feed.nc" \
  || { echo "✗ the Instagram grid's membership test is gone — wordless picture posts read as rows titled \"Photo\""; exit 1; }
# A tile promises a picture. The test is the pixels AND the tag, never the
# title: that title is the LOCALIZED word "Photo", and matching on it empties
# this grid on every device that isn't in English.
grep -qF 'thing.tags.contains("Photo")' "$TMP/feed.nc" \
  || { echo "✗ the Instagram/X grid no longer keys on the Photo tag"; exit 1; }

# THE HEAD is reached, and reached for the right source.
grep -qF 'InstagramRoomSource.compose(things: visible).map { .instagram($0) }' "$TMP/feed.nc" \
  || { echo "✗ sourceHead no longer resolves the Instagram head"; exit 1; }
grep -qF 'InstagramRoomCard(room: room)' "$TMP/feed.nc" \
  || { echo "✗ the Instagram head composes and nothing draws it"; exit 1; }

# §349's RULE AS A TEST. This card displaces `FeedInsight.leaderboard`'s "Who
# you save most", so it may not draw fewer accounts than that board would. The
# two caps are spelled in different files and cannot see each other, so the only
# thing keeping them equal is this line.
grep -qF 'static let rowCap = 6' "$ROOM" \
  || { echo "✗ InstagramRoom.rowCap moved — it must equal FeedInsight.ranked's own prefix(6), or the head draws less than the board it displaces (§349)"; exit 1; }
grep -qF '.prefix(6)' "$INSIGHT" \
  || { echo "✗ FeedInsight.ranked no longer caps at 6 — InstagramRoom.rowCap must follow it"; exit 1; }

# THE FIELDS the head reads, stamped where it expects them.
grep -qF 'thing.socialContext = marker' "$TMP/import.nc" \
  || { echo "✗ saves/likes no longer carry their act as socialContext — the post card loses its Saved/Liked word"; exit 1; }
grep -qF '"Instagram"' Casberi/Casberi/Model/SocialBridge.swift \
  || { echo "✗ Instagram is not a context source — contextLabel returns nil for every save"; exit 1; }
grep -qF 'if !row.handle.isEmpty { thing.authorHandle = row.handle }' "$TMP/import.nc" \
  || { echo "✗ saves no longer stamp authorHandle — the head has nobody to rank"; exit 1; }
grep -qF 'thing.tags.append("Gone")' "$TMP/captions.nc" \
  || { echo "✗ a deleted saved post is no longer tagged Gone — the head's footnote can never fire"; exit 1; }

# THE COVERS (prd §395). Two halves, each useless alone: the pixels must be
# KEPT as bytes, and the signed URL must NOT be kept — that is the whole of
# §245's measured refusal, and storing the URL brings back art that 404s within
# the week.
grep -qF 'thing.previewImageData = thumb' "$TMP/captions.nc" \
  || { echo "✗ the cover is no longer stored as bytes"; exit 1; }
if grep -qF 'previewImageURL' "$TMP/captions.nc"; then
  echo "✗ InstagramCaptions writes previewImageURL — og:image is SIGNED and expires in days (§245); only the bytes may be kept"; exit 1
fi
grep -qF 'coverHosts' "$TMP/captions.nc" \
  || { echo "✗ the cover host allowlist is gone — og:image is a string out of somebody else's page"; exit 1; }
grep -qF 'NetworkLedger.shared.record(request)' "$TMP/captions.nc" \
  || { echo "✗ a cover fetch is no longer recorded — an undisclosed reach is the build-214 failure"; exit 1; }
grep -qF 'cdninstagram.com' "$REACH" \
  || { echo "✗ Meta's picture CDN is not in the reach registry — the privacy screen is wrong the moment a cover lands"; exit 1; }

# THE OTHER FOUR media files (prd §395). Reels and stories are the half of an
# Instagram account this importer never opened; a missing path here is a person
# importing their comments and nothing they have made in years.
for f in reels stories archived_posts igtv_videos; do
  grep -qF "media/$f.json" "$TMP/import.nc" \
    || { echo "✗ $f.json is no longer imported — your own $f never land"; exit 1; }
done
# A wordless VIDEO must stay skipped: `CGImageSource` cannot open an .mp4, so
# landing one gives a row titled "Photo" with no photo in it.
grep -qF 'isPicture(uri: uri)' "$TMP/import.nc" \
  || { echo "✗ a captionless entry no longer has to name a decodable picture — wordless videos land as empty rows titled Photo"; exit 1; }

# THE FACETS. All three are ordinary English words, so each only ever filters
# alongside a named room (§308) — and each is read off a fact the export already
# states rather than guessed.
for tag in Reel Story Photo; do
  grep -qF "\"$tag\")," "$RETRIEVER" \
    || { echo "✗ the $tag facet is gone — that half of the room can't be asked for"; exit 1; }
done
# "Everything I wrote" must not answer with a photograph. A wordless post wears
# a writing tag beside `Photo` (a photograph you posted is still a post), which
# is right for a facet and wrong for this scope.
#
# The exclusion became a SET on 2026-08-18 (prd §396): the X pass added `Video`
# the same afternoon this guard landed, and a wordless clip wears `Post` beside
# it for the identical reason — so a check pinned to `Photo` alone passed while
# captionless video walked straight back into the one scope that must hold
# none. Both members are asserted, and the guard is stronger than it was.
grep -qF 'wordless.isDisjoint(with: tags)' "$RETRIEVER" \
  || { echo "✗ the writing scope no longer excludes wordless picture posts"; exit 1; }
for wordless in Photo Video; do
  grep -qE "static let wordless.*\"$wordless\"" "$RETRIEVER" \
    || { echo "✗ $wordless is not excluded from the writing scope — captionless media reads as something you wrote"; exit 1; }
done
# …and the topic map must not count them into its own denominator.
grep -qF 'belongs = { !$0.tags.contains("Photo") }' "$INSIGHT" \
  || { echo "✗ the Instagram topic map counts wordless pictures as writing"; exit 1; }

echo "instagram-selftest: drift guards ✓"

# --- the compiled head ------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

/// N keeps from one handle, dated in `year`.
func keeps(_ handle: String?, _ n: Int, year: Int = 2024,
           gone: Int = 0, refPrefix: String = "r") -> [InstagramRoom.Keep] {
    (0..<n).map { i in
        InstagramRoom.Keep(ref: "\(refPrefix):\(handle ?? "none"):\(i)",
                           handle: handle, year: year, gone: i < gone)
    }
}

print("InstagramRoom")

// --- the floors -----------------------------------------------------------
check("eleven taps are not a library",
      InstagramRoom.compose(saved: keeps("a", 4) + keeps("b", 4) + keeps("c", 3),
                            liked: [], made: 0) == nil)
check("…and twelve from two accounts still are not",
      InstagramRoom.compose(saved: keeps("a", 6) + keeps("b", 6),
                            liked: [], made: 0) == nil)
let lib = InstagramRoom.compose(saved: keeps("a", 8) + keeps("b", 5) + keeps("c", 2),
                                liked: [], made: 40)!
check("a library over both floors composes", lib.accounts.count == 3)

// --- saves and likes are NEVER summed (§247) ------------------------------
let mixed = InstagramRoom.compose(saved: keeps("a", 8) + keeps("b", 5) + keeps("c", 2),
                                  liked: keeps("z", 900), made: 0)!
check("the act the card is about is saves when there are enough of them",
      mixed.act == .saved)
check("…and the total counts that act ALONE — a like is never added to a save",
      mixed.kept == 15)
check("…nor is a liked account allowed onto a saves board",
      !mixed.accounts.contains(where: { $0.handle == "z" }))
let likesOnly = InstagramRoom.compose(saved: keeps("a", 3),
                                      liked: keeps("x", 9) + keeps("y", 4) + keeps("w", 3),
                                      made: 0)!
check("too few saves falls back to likes", likesOnly.act == .liked && likesOnly.kept == 16)
check("…and the headline SAYS SO rather than re-labelling the same bars",
      InstagramRoom.headline(likesOnly).contains("liked")
      && InstagramRoom.headline(lib).contains("saved"))
check("the unit under each bar follows the act too",
      InstagramRoom.accountLine(likesOnly.accounts[0], act: .liked).contains("likes")
      && InstagramRoom.accountLine(lib.accounts[0], act: .saved).contains("saves"))

// --- the board is TOTALLY ordered ------------------------------------------
check("biggest first", lib.accounts.map(\.handle) == ["a", "b", "c"])
let tiedA = InstagramRoom.compose(saved: keeps("zeta", 5) + keeps("alpha", 5) + keeps("mid", 5),
                                  liked: [], made: 0)!
let tiedB = InstagramRoom.compose(saved: keeps("mid", 5) + keeps("alpha", 5) + keeps("zeta", 5),
                                  liked: [], made: 0)!
check("a tie breaks by handle, so the board cannot reshuffle between two opens",
      tiedA.accounts.map(\.handle) == ["alpha", "mid", "zeta"]
      && tiedA.accounts.map(\.handle) == tiedB.accounts.map(\.handle))
let many = InstagramRoom.compose(
    saved: (0..<9).flatMap { keeps("acct\($0)", 10 - $0) }, liked: [], made: 0)!
check("the board is capped at the same six rows the leaderboard it displaces drew",
      many.accounts.count == InstagramRoom.rowCap)
check("…and the headline still names every account, not just the drawn ones",
      many.accountCount == 9 && InstagramRoom.headline(many).contains("9"))

// --- an unnamed save counts, and does not rank -----------------------------
let anon = InstagramRoom.compose(
    saved: keeps("a", 6) + keeps("b", 4) + keeps("c", 2) + keeps(nil, 5) + keeps("  ", 3),
    liked: [], made: 0)!
check("a save the export named nobody for still counts toward the library",
      anon.kept == 20)
check("…and is never ranked as an account, nor as a whitespace one",
      anon.accountCount == 3 && !anon.accounts.contains(where: { $0.handle.isEmpty }))

// --- the span --------------------------------------------------------------
let spanned = InstagramRoom.compose(
    saved: keeps("a", 6, year: 2019) + keeps("b", 4, year: 2024) + keeps("c", 2, year: 2021),
    liked: [], made: 0)!
check("the span runs first year to last, inclusive",
      spanned.firstYear == 2019 && spanned.lastYear == 2024 && spanned.span == 6)
check("a library inside one year spans 1, not 0", lib.span == 1)
check("…and says the year as a YEAR, never as a quantity",
      InstagramRoom.note(lib).contains("2024") && !InstagramRoom.note(lib).contains("2,024"))
check("the note names what you made yourself, in its own clause",
      InstagramRoom.note(lib).contains("40"))
check("…and a person who only ever saved gets no such clause",
      !InstagramRoom.note(spanned).contains("of your own"))
check("what you MADE is never added to what you kept",
      lib.kept == 15 && lib.made == 40)

// --- the tap target --------------------------------------------------------
let newest = InstagramRoom.compose(
    saved: keeps("a", 6, year: 2019, refPrefix: "old")
         + keeps("a", 6, year: 2023, refPrefix: "new")
         + keeps("b", 4) + keeps("c", 2),
    liked: [], made: 0)!
check("an account's tap lands on its NEWEST kept post",
      newest.accounts[0].newestRef?.hasPrefix("new:") == true)

// --- gone ------------------------------------------------------------------
check("a library with nothing gone says nothing about it",
      InstagramRoom.footnote(lib) == nil && lib.gone == 0)
let dead = InstagramRoom.compose(saved: keeps("a", 8, gone: 3) + keeps("b", 5) + keeps("c", 2),
                                 liked: [], made: 0)!
check("…and one with dead saves counts them", dead.gone == 3)
check("…and states it as the reading no service can make",
      (InstagramRoom.footnote(dead) ?? "").contains("3"))

// --- the bars --------------------------------------------------------------
check("every bar is a share of the biggest account's",
      InstagramRoom.top(lib) == 8
      && InstagramRoom.share(kept: 8, of: 8) == 1
      && InstagramRoom.share(kept: 4, of: 8) == 0.5)
check("a zero leader draws flat bars rather than NaN, which SwiftUI draws as nothing",
      InstagramRoom.share(kept: 0, of: 0) == 0)
check("…and a share can never exceed the full width",
      InstagramRoom.share(kept: 99, of: 8) == 1)

print("")
if failures > 0 { print("\(failures) failed"); exit(1) }
print("all assertions passed")
SWIFT

echo "instagram-selftest: compiling the head WHOLE and unmodified…"
swiftc -O -o "$TMP/run" "$ROOM" "$LEDE" "$TMP/main.swift" \
  || { echo "✗ InstagramRoom does not compile Foundation-only — something reached Thing/SwiftUI"; exit 1; }
"$TMP/run" || exit 1

# --- mutation pass ----------------------------------------------------------
# Every mutation below is a silent wrong answer that renders perfectly. A
# mutation that survives means nothing here was testing that line.
echo ""
echo "mutations (each must be caught):"

mutate() {
  local name="$1" frm="$2" to="$3"
  cp "$ROOM" "$TMP/InstagramRoom.swift"
  FRM="$frm" TO="$to" python3 - "$TMP/InstagramRoom.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["FRM"], os.environ["TO"]
if frm not in src:
    sys.exit(1)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$TMP/InstagramRoom.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$TMP/InstagramRoom.swift" "$LEDE" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# §247's ruling, broken. A save is a deliberate keep and a like is a reaction in
# passing; one board over both is a number with no meaning — and it renders as
# a perfectly ordinary card.
mutate "saves and likes summed into one board" \
  '        build(.saved, saved, made: made) ?? build(.liked, liked, made: made)' \
  '        build(.saved, saved + liked, made: made) ?? build(.liked, liked, made: made)'

# A board whose order is not TOTAL reshuffles between two opens over identical
# rows, which reads as broken and is invisible in a single screenshot.
mutate "the tie-break stops being total" \
  '            .sorted { (counts[$0]!, $1) > (counts[$1]!, $0) }' \
  '            .sorted { counts[$0]! > counts[$1]! }'

# "from 6 accounts" over a library of four hundred — the count taken from the
# rows DRAWN rather than from all of them.
mutate "the account count is taken from the drawn rows" \
  '                             accountCount: counts.count,' \
  '                             accountCount: accounts.count,'

# A card claiming a library exists over a handful of taps, with three bars that
# are the whole of what you ever saved.
mutate "the kept floor is dropped" \
  '        guard keeps.count >= minimumKept else { return nil }' \
  '        guard keeps.count >= 0 else { return nil }'

mutate "the account floor is dropped" \
  '        guard counts.count >= minimumAccounts, first <= last else { return nil }' \
  '        guard counts.count >= 0, first <= last else { return nil }'

# An account's tap landing on its OLDEST kept post — a real row, in the right
# room, and the wrong one by years.
mutate "the tap lands on the oldest kept post" \
  '            if keep.year > (newest[handle]?.year ?? Int.min) {' \
  '            if keep.year < (newest[handle]?.year ?? Int.max) {'

# A span that excludes its own last year, which draws a decade as nine years and
# is invisible beside a feed sorted by the same field.
mutate "the span drops a year" \
  '    var span: Int { max(1, lastYear - firstYear + 1) }' \
  '    var span: Int { max(1, lastYear - firstYear) }'

# What you MADE folded into what you KEPT — the same mistake as the first
# mutation, wearing a different noun.
mutate "your own posts are counted into the library" \
  '                             kept: keeps.count,' \
  '                             kept: keeps.count + made,'

# A grant with no leader divides by nothing. SwiftUI draws a NaN frame as no bar
# at all, so the card renders as a list with its bars silently missing.
mutate "the zero-leader guard is dropped" \
  '        guard top > 0 else { return 0 }' \
  '        guard top >= 0 else { return 0 }'

# A whitespace handle ranked as an account of its own, which files every save
# the export named nobody for under one invented name.
mutate "an empty handle is allowed to rank" \
  '            guard !handle.isEmpty else { continue }' \
  '            guard handle.count >= 0 else { continue }'

echo ""
echo "instagram-selftest: OK"
