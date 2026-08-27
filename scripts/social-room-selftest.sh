#!/bin/zsh
# Casberi social-room self-test — the SHIPPED judgement behind every social
# room's rows (prd §489, 2026-08-26):
#
#   Casberi/Casberi/Model/SocialRoom.swift
#
# Foundation-only BY DESIGN, so it is compiled WHOLE AND UNMODIFIED rather than
# extracted — the strongest form of "the harness ran the shipped logic".
#
# WHY A HARNESS. Until this pass these rules lived inside `FeedScreen.swift`, in
# five hand-rolled branches over an 8,900-line SwiftUI view — which means NO
# check in this repo could reach them. Not a `swiftc` harness (the file needs
# SwiftData and SwiftUI), not the screen sweep (it proves a room painted, never
# that it painted the right anatomy), not the liveness audit (it asks about
# tombstones, not about which row is a card). So the rules drifted for months
# with every gate green, in exactly the way this repo's own history predicts:
#
#   · Nostr had NO case at all, so its rows fell to the generic band while
#     `PostCard`, `SocialThreadCard`, `SocialThread.replies` and
#     `NostrStore.socialAccounts` all already carried Nostr-specific code that
#     nothing on any screen could reach
#   · TikTok had none either — a room of saved videos drawing as 80-character
#     title rows, found by auditing the other seven rather than by a report
#   · `standsAlone` was repaired for X (§396a) and never carried to Instagram or
#     Telegram, so both went on drawing post cards squeezed into a merged run of
#     bare rows — a card by anatomy with no card under it, twice, unreported
#   · the roster's accounts were a `Farcaster ? … : Bluesky` TERNARY, so any
#     third network reaching it would have been handed Bluesky's watched
#     accounts: a rail of the wrong faces, filtering to handles matching nothing
#
# Every failure this catches renders as a perfectly ordinary room. A post drawn
# as a band still lists; a shared article drawn as a post still reads; a rail of
# the wrong people still fills. That is why the guard has to be mechanical and
# not a rule somebody remembers — and why the LAST block here is the one that
# matters in six months: every drift above has one shape, a source joining the
# catalog, the ingest and the sheet while nobody remembered the room.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

ROOM="Casberi/Casberi/Model/SocialRoom.swift"
SOURCE="Casberi/Casberi/Model/SocialRoomSource.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
SHELL_="Casberi/Casberi/Shell/MainSurface.swift"
RAIL="Casberi/Casberi/Shell/FaceScopeRail.swift"
CATALOG="Casberi/Casberi/Model/BridgeCatalog.swift"
HEATMAP="Casberi/Casberi/Model/FeedHeatmap.swift"
INSIGHT="Casberi/Casberi/Model/FeedInsight.swift"
for f in "$ROOM" "$SOURCE" "$FEED" "$SHELL_" "$RAIL" "$CATALOG" "$HEATMAP" "$INSIGHT"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A comment-stripped copy for the NEGATIVE guards, and here the lesson is
# earned twice over: all three of these files DOCUMENT the dialects they
# replaced by NAMING them — `SocialRoom`'s header lists `isXPostRow` and
# `isTelegramPostRow` as the things it exists to delete, `FeedScreen.socialRow`
# says the same, and both quote the `Farcaster ? … : Bluesky` ternary verbatim.
# A guard grepping raw source fires against the prose explaining the fix (the
# Obsidian/Cursor lesson, eighth instance).
strip_comments() {
  python3 - "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r'^[ \t]*//.*$', '', src, flags=re.M)
src = re.sub(r'^[ \t]*///.*$', '', src, flags=re.M)
src = re.sub(r'//.*$', '', src, flags=re.M)
sys.stdout.write(src)
PY
}
strip_comments "$FEED"   > "$TMP/feed.nc"
strip_comments "$SHELL_" > "$TMP/shell.nc"
strip_comments "$ROOM"   > "$TMP/room.nc"

fail=0
present() {  # name pattern file
  grep -Eq -- "$2" "$3" || { echo "  ✗ $1"; fail=1; }
}
absent() {   # name pattern file
  grep -Eq -- "$2" "$3" && { echo "  ✗ $1"; fail=1; } || true
}

echo "Drift guards"

# --- the room reaches the table --------------------------------------------
# A perfect `rowKind` is worthless if no room calls it. These are the seams the
# compiled half structurally cannot prove about itself.

present "the five post shapes share ONE row branch" \
  'case \.social, \.x, \.telegram, \.instagram, \.tiktok:' "$TMP/feed.nc"
present "…and that branch draws through socialRow" \
  'socialRow\(thing, replies: replies' "$TMP/feed.nc"
present "socialRow has no rules of its own — it switches on the table's answer" \
  'switch SocialRoomSource\.rowKind\(thing, hasReplies:' "$TMP/feed.nc"
present "standsAlone reads the same table the anatomy came from" \
  'return SocialRoomSource\.standsAlone\(thing\)' "$TMP/feed.nc"
present "the day header's noun reads it too" \
  'SocialRoomSource\.groupIsPosts\(rows\)' "$TMP/feed.nc"
present "the thread fold is table-driven, not shape-driven" \
  'SocialRoom\.foldsThreads\(source\)' "$TMP/feed.nc"
present "the person filter is gated on the roster set" \
  'guard SocialRoom\.hasRoster\(source\), let scope = chrome\.personScope' "$TMP/feed.nc"
present "the fresh rings are gated on the same set" \
  'guard SocialRoom\.hasRoster\(source\), let since = newSince' "$TMP/feed.nc"
present "the rail's own gate asks SocialRoom, not Shape" \
  'SocialRoom\.hasRoster\(source\)' "$TMP/feed.nc"
present "the rail still asks the feed whether this is a social room" \
  'FeedScreen\.isSocialRoom\(source\)' "$RAIL"

# --- ONE account dispatch ---------------------------------------------------
# THE SHARPEST GUARD HERE. The room's roster and the rail above it must name
# the same people, and they were two different lookups that disagreed — one a
# ternary with two faces, one a two-case switch that failed closed. A third
# reader appearing is the drift returning.
present "the room's roster reads the one dispatch" \
  'SocialRoomSource\.accounts\(for: source\)' "$TMP/feed.nc"
present "the rail above it reads the same one" \
  'SocialRoomSource\.accounts\(for: filter\.source\)' "$TMP/shell.nc"
absent "FeedScreen reaches a network store directly again" \
  '(Farcaster|Bluesky|Nostr)Store\.shared\.socialAccounts' "$TMP/feed.nc"
absent "MainSurface reaches a network store directly again" \
  '(Farcaster|Bluesky|Nostr)Store\.shared\.socialAccounts' "$TMP/shell.nc"
present "the dispatch refuses a source with no roster rather than guessing" \
  'guard SocialRoom\.hasRoster\(source\) else \{ return \[\] \}' "$SOURCE"

# --- the dialects stay dead -------------------------------------------------
absent "isXPostRow came back to FeedScreen" \
  'func isXPostRow' "$TMP/feed.nc"
absent "isTelegramPostRow came back to FeedScreen" \
  'func isTelegramPostRow' "$TMP/feed.nc"
# The grid tests are NOT this file's business and must stay where they are —
# they read `previewImageData`, they are layout, and each room answers
# differently for a stated reason. A guard both ways, so neither half drifts
# into the other.
present "the photo-tile tests stay in the view layer" \
  'func isXPhotoTile' "$TMP/feed.nc"
absent "a grid test moved into the rules half" \
  'PhotoTile' "$TMP/room.nc"

# --- the two rooms that had no case at all ----------------------------------
present "Nostr resolves to the social room" \
  'case "Farcaster", "Bluesky", "Nostr": self = \.social' "$TMP/feed.nc"
present "TikTok resolves to a room of its own" \
  'case "TikTok":              self = \.tiktok' "$TMP/feed.nc"
# A room with one watched account draws no rail (the rail needs two), so
# without this entry a single-account Nostr room has nothing above its rows at
# all — no head, no board, no grid.
present "Nostr has an activity grid to fall back to" \
  '"Nostr": *Label\(' "$HEATMAP"
present "Telegram has a head instead of leading with the year grid" \
  'title: "Which channels fill this"' "$INSIGHT"

[[ $fail -eq 0 ]] || { echo "social-room-selftest: ✗ drift guard(s) failed"; exit 1; }

# --- THE CATALOG GUARD ------------------------------------------------------
# The one that matters in six months. Every drift this pass fixed has one shape:
# a source joined the catalog, joined the ingest, joined the sheet — and nobody
# remembered the room. `social-sheet-selftest.sh` already makes that mechanical
# for the SHEET, which is why the sheet was the only surface that had not
# drifted. This is the same assertion for the room.
#
# Block-splitting rather than one reaching regex, for the reason that harness
# records: `finditer` returns non-overlapping matches, so a preceding
# non-Network offer's `name:` opens a span that swallows the real one.
python3 - "$CATALOG" "$ROOM" <<'PY' || exit 1
import re, sys
catalog, room = (open(p).read() for p in sys.argv[1:3])
# A seat may be deliberately absent — but it must be NAMED here with a reason,
# never silently missing. Empty by design: every Network seat has a room today.
KNOWN_NO_ROOM: dict[str, str] = {}
offers = set()
for block in catalog.split("Offer(")[1:]:
    block = block.split("needsSetup")[0]
    name = re.search(r'name:\s*"([^"]+)"', block)
    if name and re.search(r'group:\s*"Network"', block):
        offers.add(name.group(1))
if not offers:
    print("  ✗ no Network seats parsed out of the catalog — the guard is looking at nothing")
    sys.exit(1)
table = re.search(r'static let table: \[String: Facts\] = \[(.*?)\n    \]', room, re.S)
if not table:
    print("  ✗ SocialRoom.table moved — this guard can no longer read it")
    sys.exit(1)
listed = set(re.findall(r'"([^"]+)":\s*Facts\(', table.group(1)))
missing = offers - listed - set(KNOWN_NO_ROOM)
if missing:
    print("  ✗ catalog Network seats with no room: " + ", ".join(sorted(missing)))
    print("    Add them to SocialRoom.table, or to KNOWN_NO_ROOM here with a written reason.")
    sys.exit(1)
stale = set(KNOWN_NO_ROOM) & listed
if stale:
    print("  ✗ KNOWN_NO_ROOM names a seat that now HAS a room: " + ", ".join(sorted(stale)))
    sys.exit(1)
orphan = listed - offers
if orphan:
    print("  ✗ SocialRoom.table names a source with no Network seat: " + ", ".join(sorted(orphan)))
    sys.exit(1)
print("  ✓ every catalog Network seat resolves in SocialRoom.table (%d)" % len(offers))
PY

# --- assertions -------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

typealias Row = SocialRoom.RowFacts
typealias Kind = SocialRoom.RowKind

func kind(_ r: Row, replies: Bool = false) -> Kind {
    SocialRoom.rowKind(r, hasReplies: replies)
}

// A post as each room actually lands one. These mirror the ingests: the three
// live networks land a post as `.chat` by kind, X and Instagram as `.note`,
// Telegram's channel posts as `.note` carrying a live ref.
func cast(_ source: String, context: String? = nil) -> Row {
    Row(source: source, kind: "chat", socialContext: context)
}

print("The table")
check("the three live networks have a roster",
      ["Bluesky", "Farcaster", "Nostr"].allSatisfy(SocialRoom.hasRoster))
check("…and nothing else does",
      ["X", "Instagram", "Telegram", "TikTok", "Snapchat"].allSatisfy { !SocialRoom.hasRoster($0) })
check("a source outside the table has no roster", !SocialRoom.hasRoster("Wallet"))
check("threads fold only where a parent can be named exactly",
      ["Bluesky", "Farcaster", "Nostr", "X"].allSatisfy(SocialRoom.foldsThreads)
        && ["Instagram", "Telegram", "TikTok", "Snapchat"].allSatisfy { !SocialRoom.foldsThreads($0) })
check("Snapchat is in the table so the catalog guard sees it decided",
      SocialRoom.facts(for: "Snapchat") != nil)
check("…and draws no posts, which is what being decided means here",
      !SocialRoom.drawsPosts("Snapchat"))
check("the other seven draw posts",
      ["Bluesky", "Farcaster", "Nostr", "X", "Instagram", "Telegram", "TikTok"]
        .allSatisfy(SocialRoom.drawsPosts))
check("an unknown source draws no posts", !SocialRoom.drawsPosts("Kalshi"))
check("…and its rows fall back to the band rather than trapping",
      kind(Row(source: "Kalshi", kind: "link")) == .band)

print("")
print("The three live networks — and NOSTR IS ONE OF THEM")
for net in ["Bluesky", "Farcaster", "Nostr"] {
    check("\(net): a cast is a post card", kind(cast(net)) == .post(whole: false))
    check("\(net): a cast with self-replies folds into a thread",
          kind(cast(net), replies: true) == .thread(whole: false))
    // An article a post shared lands as its own thing and reads like the
    // reading list it is, not like a post with no author of its own.
    check("\(net): a shared article is a reading row",
          kind(Row(source: net, kind: "link")) == .reading)
    // A FOLLOWER IS A PERSON. Landed as a `.link`, so without this test the
    // rule above reads "Sam started following you" as an article.
    check("\(net): a new follower is not an article",
          kind(cast(net, context: "follow")) == .band)
    check("\(net): a follower landed as a link is not one either",
          kind(Row(source: net, kind: "link", socialContext: "follow")) == .band)
}
// The point of the whole pass, stated as one assertion: the third network is
// not a special case, it is the same room.
check("Nostr's rows are byte-identical to Bluesky's, row for row",
      [cast("Nostr"), Row(source: "Nostr", kind: "link"), cast("Nostr", context: "follow")]
        .map { kind($0) }
      == [cast("Bluesky"), Row(source: "Bluesky", kind: "link"), cast("Bluesky", context: "follow")]
        .map { kind($0) })

print("")
print("X — an archive of somebody's own writing")
let xPost = Row(source: "X", kind: "note")
check("a post is drawn WHOLE, not clamped", kind(xPost) == .post(whole: true))
check("a thread is drawn whole too", kind(xPost, replies: true) == .thread(whole: true))
check("a liked post is still a post", kind(Row(source: "X", kind: "link")) == .post(whole: true))
check("a DM is a transcript", kind(Row(source: "X", kind: "chat")) == .excerpt(lines: 2))
// A post card over one of these would draw a face and a handle over a fact
// about the account.
check("a connected app is a fact about the account, not a post",
      kind(Row(source: "X", kind: "link", tags: ["Access"])) == .band)
check("so is the day you joined",
      kind(Row(source: "X", kind: "note", tags: ["Account"])) == .band)
check("our own note about the import is never a post",
      kind(Row(source: "X", kind: "note", isImportReceipt: true)) == .band)

print("")
print("Telegram — live and import under one source")
check("a channel broadcast is drawn whole",
      kind(Row(source: "Telegram", kind: "note", arrivedLive: true, hasPostText: true))
        == .post(whole: true))
check("a broadcast with no words is still the broadcast",
      kind(Row(source: "Telegram", kind: "note", arrivedLive: true)) == .post(whole: true))
// A saved message is usually a bare link you sent yourself.
check("a saved message with words reads as a saved link",
      kind(Row(source: "Telegram", kind: "link", hasPostText: true)) == .reading)
check("a saved message with nothing but a date is a band",
      kind(Row(source: "Telegram", kind: "link")) == .band)
check("an imported conversation is a transcript",
      kind(Row(source: "Telegram", kind: "chat", hasPostText: true)) == .excerpt(lines: 2))
check("a live ref does not turn a conversation into a post",
      kind(Row(source: "Telegram", kind: "chat", arrivedLive: true)) == .excerpt(lines: 2))
check("our own note about the import is a band even when live",
      kind(Row(source: "Telegram", kind: "note", isImportReceipt: true, arrivedLive: true)) == .band)

print("")
print("Instagram")
check("a post with words is a post card",
      kind(Row(source: "Instagram", kind: "note", hasPostText: true)) == .post(whole: false))
check("a save whose caption came back is a post card",
      kind(Row(source: "Instagram", kind: "link", hasPostText: true)) == .post(whole: false))
// Without this the row prints the handle TWICE — once as the byline and once as
// the body, since `PostCard.words` falls back to the title.
check("a save with no caption yet is an excerpt, not a card",
      kind(Row(source: "Instagram", kind: "link")) == .excerpt(lines: 2))
// The export does not carry the post a comment was left on.
check("a comment is not a post",
      kind(Row(source: "Instagram", kind: "note", tags: ["Comment"], hasPostText: true))
        == .excerpt(lines: 3))
check("a picture post whose thumbnail never landed shows the band",
      kind(Row(source: "Instagram", kind: "note", tags: ["Photo"])) == .band)
check("…and one whose thumbnail did land is a card",
      kind(Row(source: "Instagram", kind: "note", tags: ["Photo"],
               hasPostText: true, hasPreviewImage: true)) == .post(whole: false))
check("a saved conversation is a transcript",
      kind(Row(source: "Instagram", kind: "chat", hasPostText: true)) == .excerpt(lines: 2))
check("our own note about the import is a band",
      kind(Row(source: "Instagram", kind: "note", isImportReceipt: true, hasPostText: true)) == .band)

print("")
print("TikTok — a room of saved videos, and NO post cards")
// `TikTokImport` stamps no `postText` on any row, so a post card would print
// the row's own face as its body — and before `fetchFaces` has run that face is
// the raw share URL.
check("a saved video reads as a saved link",
      kind(Row(source: "TikTok", kind: "link")) == .reading)
check("so does one the face pass has already named",
      kind(Row(source: "TikTok", kind: "link", hasPreviewImage: true)) == .reading)
check("a comment you left is an excerpt",
      kind(Row(source: "TikTok", kind: "note", tags: ["Comment"])) == .excerpt(lines: 3))
check("our own note about the import is a band",
      kind(Row(source: "TikTok", kind: "link", isImportReceipt: true)) == .band)
check("no TikTok row is ever a post card",
      [Row(source: "TikTok", kind: "link"),
       Row(source: "TikTok", kind: "note", tags: ["Comment"]),
       Row(source: "TikTok", kind: "note")]
        .allSatisfy { !kind($0).isPost })

print("")
print("A card never merges — derived, never spelled twice")
check("a post stands alone", Kind.post(whole: false).standsAlone)
check("a whole post stands alone", Kind.post(whole: true).standsAlone)
check("a thread stands alone", Kind.thread(whole: false).standsAlone)
check("a band does not", !Kind.band.standsAlone)
check("an excerpt does not", !Kind.excerpt(lines: 2).standsAlone)
check("a reading row does not", !Kind.reading.standsAlone)
// THE §396a REPAIR, in the two rooms it was never carried to. Both of these
// were false in the shipped app while the row drew a card.
check("an Instagram post card stands alone",
      SocialRoom.standsAlone(Row(source: "Instagram", kind: "note", hasPostText: true)))
check("a Telegram channel post stands alone",
      SocialRoom.standsAlone(Row(source: "Telegram", kind: "note", arrivedLive: true)))
check("an X post still does",
      SocialRoom.standsAlone(Row(source: "X", kind: "note")))
check("a Nostr post does now",
      SocialRoom.standsAlone(cast("Nostr")))
// A deliberate change: `.social` used to return true for EVERY row, so a
// shared article and a follow notification each got a card of their own.
check("a shared article no longer takes a card of its own",
      !SocialRoom.standsAlone(Row(source: "Bluesky", kind: "link")))
check("neither does a follow notification",
      !SocialRoom.standsAlone(cast("Farcaster", context: "follow")))
check("nor a TikTok reading row",
      !SocialRoom.standsAlone(Row(source: "TikTok", kind: "link")))

print("")
print("The day header's noun")
check("nothing is not posts", !SocialRoom.groupIsPosts([]))
check("a day of casts is posts", SocialRoom.groupIsPosts([cast("Nostr"), cast("Nostr")]))
// X's rule (§396a) generalised. One article among twelve casts makes "13 posts"
// a claim about the article too.
check("one shared article in the group is not posts",
      !SocialRoom.groupIsPosts([cast("Bluesky"), Row(source: "Bluesky", kind: "link")]))
check("one import receipt in the group is not posts",
      !SocialRoom.groupIsPosts([Row(source: "X", kind: "note"),
                                Row(source: "X", kind: "note", isImportReceipt: true)]))
check("a day of X posts is posts",
      SocialRoom.groupIsPosts([Row(source: "X", kind: "note"), Row(source: "X", kind: "link")]))
check("a TikTok day is never posts",
      !SocialRoom.groupIsPosts([Row(source: "TikTok", kind: "link")]))

print("")
if failures > 0 {
    print("social-room-selftest: \(failures) FAILED")
    exit(1)
}
print("assertions: all pass")
SWIFT

if ! swiftc -O -o "$TMP/run" "$ROOM" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ the harness did not compile against the shipped source:"
  cat "$TMP/build.log"
  exit 1
fi
"$TMP/run" || exit 1

# --- mutations --------------------------------------------------------------
# Each is a silent wrong answer that renders as a perfectly ordinary room. A
# mutation the harness still passes means nothing was testing that behaviour.
mutate() {
  local name="$1" from="$2" to="$3"
  local target="$TMP/mut.swift"
  cp "$ROOM" "$target"
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

# THE BUG THIS PASS EXISTS FOR, put back: Nostr drops out of the live-network
# case and every one of its rows falls to the band.
mutate "Nostr falls out of the social room again" \
  'case "Bluesky", "Farcaster", "Nostr":' \
  'case "Bluesky", "Farcaster":'
# "Sam started following you" drawn as a reading-list row, with their face on
# the record and the source glyph on screen.
mutate "a follower is read as an article" \
  'if row.socialContext == "follow" { return .band }' \
  'if row.socialContext == "nobody-sends-this" { return .band }'
# A shared article claiming to be a cast, with no author of its own.
mutate "a shared article is drawn as a post" \
  '''            if row.kind == "link" { return .reading }
            return hasReplies ? .thread(whole: false) : .post(whole: false)''' \
  '''            return hasReplies ? .thread(whole: false) : .post(whole: false)'''
# An archive of somebody's writing, clamped — the words are the whole content of
# every row in that room.
mutate "the X archive is clamped instead of drawn whole" \
  'return hasReplies ? .thread(whole: true) : .post(whole: true)' \
  'return hasReplies ? .thread(whole: false) : .post(whole: false)'
# A connected app drawn as a post card, face and handle over a fact.
mutate "an account record is drawn as a post" \
  'if row.tags.contains("Access") || row.tags.contains("Account") { return .band }' \
  'if row.tags.contains("Access") && row.tags.contains("nope") { return .band }'
# A channel's broadcast demoted to a saved link.
mutate "a Telegram broadcast is not recognised as live" \
  'if row.arrivedLive { return .post(whole: true) }' \
  'if row.hasPreviewImage { return .post(whole: true) }'
# A saved message with words losing them, and one with none claiming some.
mutate "the Telegram saved-message fork is inverted" \
  'return row.hasPostText ? .reading : .band' \
  'return row.hasPostText ? .band : .reading'
# The handle printed TWICE — as the byline and as the body.
mutate "an uncaptioned Instagram save is drawn as a card" \
  'if row.kind == "link" && !row.hasPostText { return .excerpt(lines: 2) }' \
  'if row.kind == "link" && row.hasPostText { return .excerpt(lines: 2) }'
# A card whose entire body is the placeholder word "Photo".
mutate "a picture post with no picture is drawn as a card" \
  'if row.tags.contains("Photo") && !row.hasPreviewImage { return .band }' \
  'if row.tags.contains("Photo") && row.hasPreviewImage { return .band }'
# A comment drawn as a card claiming to show the post it was left on.
# ONE line, and `mutate` replaces the FIRST occurrence — which is Instagram's,
# since its case precedes TikTok's in the file. TikTok's identical line is
# mutated separately below, by a two-line anchor that is unique to it.
mutate "an Instagram comment is drawn as a post" \
  'if row.tags.contains("Comment") { return .excerpt(lines: 3) }' \
  'if row.tags.contains("Comment") && row.hasPreviewImage { return .excerpt(lines: 3) }'
# The raw share URL as a post's body.
mutate "a saved TikTok video is drawn as a post card" \
  '''            if row.tags.contains("Comment") { return .excerpt(lines: 3) }
            if row.kind == "link" { return .reading }''' \
  '''            if row.tags.contains("Comment") { return .excerpt(lines: 3) }
            if row.kind == "link" { return .post(whole: false) }'''
# Our own note about a sync, wearing somebody's byline.
mutate "the import receipt is treated as a post" \
  'if row.isImportReceipt { return .band }' \
  'if row.isImportReceipt && row.kind == "never" { return .band }'
# §396a, back in all seven rooms at once: post cards squeezed into a merged run
# of bare rows.
mutate "post cards merge into a run again" \
  'case .post, .thread: return true' \
  'case .post, .thread: return false'
# Every row on a card, which is the same feed with no rhythm at all.
mutate "reading rows take cards of their own" \
  'case .band, .excerpt, .reading: return false' \
  'case .band, .excerpt, .reading: return true'
# "13 posts" over twelve casts and an article.
mutate "one post in the group makes it a day of posts" \
  'return rows.allSatisfy { rowKind($0).isPost }' \
  'return rows.contains { rowKind($0).isPost }'
# "0 posts" under an empty day header.
mutate "an empty group is called posts" \
  'guard !rows.isEmpty else { return false }' \
  'guard true else { return false }'
# A rail of faces above a room that cannot filter to any of them.
mutate "an import room claims a roster" \
  '"X":         Facts(foldsThreads: true,  hasRoster: false)' \
  '"X":         Facts(foldsThreads: true,  hasRoster: true)'
# A thread fold over a room whose export names no parent — every self-reply
# swallowed under whichever row happened to precede it.
mutate "Instagram claims it can fold threads" \
  '"Instagram": Facts(foldsThreads: false, hasRoster: false)' \
  '"Instagram": Facts(foldsThreads: true,  hasRoster: false)'
# Snapchat's rows re-entering the post switch, which would put its memories and
# saved chats through an anatomy built for casts.
mutate "Snapchat is treated as a post room" \
  'facts(for: source) != nil && source != "Snapchat"' \
  'facts(for: source) != nil'

echo ""
echo "social-room-selftest: OK — assertions pass and every mutation is caught."
