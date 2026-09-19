#!/bin/zsh
# Casberi feed-reading self-test — the §455 pass over the reading rooms
# (2026-08-23): the article you can actually read, the board that narrows its
# own room, and the feed that says when it stopped answering.
#
#   Casberi/Casberi/Model/FeedRoomHealth.swift
#     — standing   (what a reading room says about its own feeds, or nothing)
#
# That file is Foundation-only BY DESIGN, so it is compiled WHOLE AND
# UNMODIFIED here — no extraction, no copy. Every assertion below is about the
# bytes the app runs. `trouble` is injected because `FeedFreshness` reads
# UserDefaults and no harness can make a publisher stop answering.
#
# WHY A HARNESS. Every failure in this pass renders as a perfectly ordinary
# room, and not one of them can be seen from a build or a screen sweep:
#
#   • a health line that names a feed and prints ANOTHER feed's reason — one
#     dead address wearing a different blog's "quiet for five days";
#   • a line drawn for a follow whose feed URL was never resolved, which is the
#     app reporting a failure it has never once observed;
#   • the raw URL where the publisher's name belonged, so the one line in the
#     room reads as plumbing quoted at somebody;
#   • a board that narrows the room and then NARROWS ITSELF, collapsing to the
#     one bar you already picked with no way back — a control you cannot leave;
#   • the tap fetching a podcast's audio enclosure, downloading the whole file
#     to take its first 512KB as text.
#
# WHAT THIS CANNOT PROVE, stated rather than implied: whether `fetchReadable`
# returns good prose for a real publisher (no network here), and whether the
# Listen voice speaks (no audio device, and `AVSpeechSynthesizer` is not
# Foundation). Those are `-articleTextProbe` and a device.
#
# Pure, local, deterministic — no network, no simulator, no feeds. Exit
# non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

HEALTH="Casberi/Casberi/Model/FeedRoomHealth.swift"
SOURCE="Casberi/Casberi/Model/FeedRoomHealthSource.swift"
ARTICLE="Casberi/Casberi/Model/FeedArticleText.swift"
BODY="Casberi/Casberi/Screens/ArticleBody.swift"
CONTENT="Casberi/Casberi/Screens/ThingContent.swift"
INSIGHT="Casberi/Casberi/Model/FeedInsight.swift"
# The cover and the two post cards — §756's three readers of one answer.
LEDE="Casberi/Casberi/Screens/FeedLedeCard.swift"
ROWS="Casberi/Casberi/Screens/ShapedRows.swift"
SOCSRC="Casberi/Casberi/Model/SocialRoomSource.swift"
# FeedScreen is split across files (prd §718). Checks read the room as ONE text,
# so a guard can neither fail nor pass because its code moved next door.
FEED_DIR="$(mktemp -d -t feedscreen)"
FEED="$FEED_DIR/FeedScreen.swift"
cat Casberi/Casberi/Screens/FeedScreen.swift Casberi/Casberi/Screens/FeedScreen+WalletRoom.swift > "$FEED"
RENDER="Casberi/Casberi/GenUI/GenRenderer.swift"
for f in "$HEALTH" "$SOURCE" "$ARTICLE" "$BODY" "$CONTENT" "$INSIGHT" "$FEED" "$RENDER" \
         "$LEDE" "$ROWS" "$SOCSRC"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/feed-reading-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# A comment-stripped copy for every NEGATIVE guard below. These files document
# their rules by naming exactly what they must not do, so a guard grepping raw
# source fires on the prose explaining it (the Obsidian/Cursor lesson).
strip_comments() {
  python3 - "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
print("\n".join(l for l in src.splitlines() if not l.strip().startswith("//")))
PY
}
strip_comments "$ARTICLE" > "$TMP/article.nocomment"
strip_comments "$FEED"    > "$TMP/feed.nocomment"
strip_comments "$BODY"    > "$TMP/body.nocomment"
strip_comments "$LEDE"    > "$TMP/lede.nocomment"
strip_comments "$ROWS"    > "$TMP/rows.nocomment"

# --- drift guards -----------------------------------------------------------
# Facts the compiled function can't prove on its own.

# ── 1. The article, fetched because somebody opened it ─────────────────────
# ONE eligibility rule, shared. The whole reason `readableURL` was extracted is
# that a tap and the sweep disagreeing about WHAT is readable is how a podcast's
# audio file gets downloaded to be read as text.
grep -q 'static func readableURL(for thing: Thing) -> URL?' "$ARTICLE" \
  || { echo "✗ FeedArticleText.readableURL is gone — the sweep and the tap have"; \
       echo "  no shared rule for what is readable"; exit 1; }
grep -q 'readableURL(for: thing)' "$TMP/article.nocomment" \
  || { echo "✗ the sweep no longer runs its candidates through readableURL — the"; \
       echo "  two paths can now disagree about what is an article"; exit 1; }
grep -q 'FeedArticleText.readableURL(for: thing) != nil' "$BODY" \
  || { echo "✗ ArticleBody no longer gates its fetch on readableURL"; exit 1; }
grep -q 'FeedArticleText.readableURL(for: thing) != nil' "$CONTENT" \
  || { echo "✗ the sheet's article branch no longer gates on readableURL — it"; \
       echo "  would offer to read rows the fetcher refuses, and draw an empty"; \
       echo "  frame over every podcast enclosure"; exit 1; }
# The podcast fence lives inside the shared rule and is the expensive one.
grep -q 'thing.externalLink != thing.content' "$TMP/article.nocomment" \
  || { echo "✗ the podcast-enclosure fence is gone from readableURL — a tap"; \
       echo "  would download an entire audio file to read its first 512KB"; exit 1; }
# The tap must NOT read the attempt ledger (a person asking is not a robot
# re-asking) and MUST write it (so the background sweep learns). Both halves,
# because dropping either is a plausible "tidy-up".
python3 - "$TMP/article.nocomment" <<'PY' || exit 1
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r"static func fetchOnOpen\(.*?\n    \}\n", src, re.S)
if not m:
    print("✗ FeedArticleText.fetchOnOpen is gone — a tap no longer fetches"); sys.exit(1)
fn = m.group(0)
if "maxAttempts" in fn:
    print("✗ fetchOnOpen consults maxAttempts — a person re-opening a story is")
    print("  refused on the strength of two failures the app made unasked")
    sys.exit(1)
if "writeLedger" not in fn:
    print("✗ fetchOnOpen no longer records failures — the background sweep")
    print("  cannot learn from a page a tap already proved unreadable")
    sys.exit(1)
if "window" in fn:
    print("✗ fetchOnOpen applies the sweep's thirty-day window — you opened it,")
    print("  and its age is not the bound that belongs on a tap")
    sys.exit(1)
if "inFlight" not in fn:
    print("✗ fetchOnOpen has no in-flight guard — two windows on one story")
    print("  would each fetch it")
    sys.exit(1)
if "thing.isLive" not in fn:
    print("✗ fetchOnOpen no longer re-checks liveness — it holds a Thing across")
    print("  an eight-second await (docs/liveness.md corollary 6)")
    sys.exit(1)
PY
# `enrichedText` is retrieval-only by the 2026-07-15 ruling and this is a NAMED
# carve-out, so the vector must still be dropped when a body lands behind a
# headline it was built from.
grep -q 'thing.embedding = nil' "$TMP/article.nocomment" \
  || { echo "✗ the embedding is no longer cleared when an article lands — the"; \
       echo "  vector still describes the headline alone"; exit 1; }

# ── 2. Listen ──────────────────────────────────────────────────────────────
# It must exist only where there is something to read, and it must stop when
# the sheet goes. A voice with no visible control is a sound you cannot turn off.
grep -q 'onDisappear { if isMine { speech.stop() } }' "$BODY" \
  || { echo "✗ the Listen control no longer stops on disappear — the voice"; \
       echo "  outlives the only button that can stop it"; exit 1; }
grep -q 'speakingID' "$BODY" \
  || { echo "✗ ArticleSpeech no longer names which thing is speaking — every"; \
       echo "  article's button would read Stop while one of them speaks"; exit 1; }
# On-device, and nothing about it may reach the network — there is no host to
# declare in NetworkReach and there must never be one.
for banned in URLSession NetworkLedger; do
  grep -q "$banned" "$TMP/body.nocomment" \
    && { echo "✗ ArticleBody names $banned — reading aloud is on-device, and a"; \
         echo "  reach here would be undeclared on the receipts screen"; exit 1; }
done

# ── 3. The board is DELETED, and so is the scope it was the control for ────
# §455 made a reading room's board a switcher: tap a publisher, the room
# narrows to them. prd §723 deleted the board from every room, so the scope
# lost its only control and went with it — `ReadingScope`, `roomScoped`,
# `leaderboardPick`, `scopedBoard` and `LeaderboardHero` are all gone. These
# are the checks that they STAY gone; a `readingScope` with no board to set it
# is the dead control §83 bans, and a `roomScoped` that narrows nothing is a
# filter every room pays for and none uses.
for gone in 'FeedInsight.Leaderboard' 'LeaderboardHero' 'readingScope' 'roomScoped'; do
  grep -q "$gone" "$FEED" \
    && { echo "✗ FeedScreen still names $gone — the ranked board and its room"; \
         echo "  scope were deleted together (prd §723)"; exit 1; }
done
grep -qE '\bstruct Leaderboard\b|\bstatic func leaderboard\(' "$INSIGHT" \
  && { echo "✗ FeedInsight grew a ranked board back (prd §723)"; exit 1; }
grep -q 'LeaderboardHero' "$RENDER" \
  && { echo "✗ LeaderboardHero is back — nothing draws it (prd §723)"; exit 1; }
# What REPLACED it: a room with no head falls through to the All feed's own
# cover, on the All feed's own terms. `heroShown` is the whole mechanism.
grep -q 'memo.lede = heroShown ? nil : ledeThingID' "$FEED" \
  || { echo "✗ the newest-thing cover is no longer gated on heroShown — the"; \
       echo "  rooms the board used to head would draw no card at all"; exit 1; }
# A ROOM ALWAYS COVERS ITS NEWEST THING (prd §723). The age floor and the two
# row floors are the All feed's alone: a river's cover claims recency, a room's
# answers "the newest thing from this source", which is true at any age. Three
# checks because the floor is asked in three places and a room must clear all
# three — the first cut of this rule left the post-fold row floor behind, which
# would have taken the cover off exactly the quiet rooms it was added for.
grep -q 'let isRoom = source != "All"' "$FEED" \
  || { echo "✗ ledeThingID no longer distinguishes a room from the All feed"; exit 1; }
grep -q 'guard isRoom || Date.now.timeIntervalSince(thing.capturedAt) <= Self.ledeMaxAge' "$FEED" \
  || { echo "✗ a room's cover is gated on ledeMaxAge again — a room whose newest"; \
       echo "  item is a day old would draw no head at all"; exit 1; }
grep -q 'if memo.lede != nil, source == "All",' "$FEED" \
  || { echo "✗ the post-fold ledeMinRows floor applies to rooms again — a quiet"; \
       echo "  room would lose the cover this rule exists to give it"; exit 1; }
# …and the anatomy veto is NOT freshness, so it still applies in both. It is
# `coverDeclines` since prd §756 — `standsAlone` minus the posts — and it must
# stay a separate question from `standsAlone`, which the run layout still asks
# for every row. Since prd §763 a ROOM skips a declining row and covers the next
# one; the All feed still declines outright.
grep -q 'if coverDeclines(thing) {' "$FEED" \
  || { echo "✗ the cover no longer asks coverDeclines — a consent card or a token"; \
       echo "  pulse would draw twice, in two anatomies (prd §723/§756)"; exit 1; }
grep -A1 'if coverDeclines(thing) {' "$FEED" | grep -q 'guard isRoom else { return nil }' \
  || { echo "✗ the All feed's cover reaches past a declining row (prd §763 ruled for"; \
       echo "  rooms) — an older card would sit above a newer consent card"; exit 1; }
_veto=$(awk '/private func coverDeclines\(/{f=1} f{print} f&&/^    }$/{exit}' "$TMP/feed.nocomment")
case "$_veto" in
  *"guard standsAlone(thing) else { return false }"*) ;;
  *) echo "✗ coverDeclines no longer starts from standsAlone (prd §756) — a consent"; \
     echo "  card's verbs would be buried under a cover of the same thing."; exit 1;;
esac
case "$_veto" in
  *"SocialRoom.drawsPosts(thing.source)"*) ;;
  *) echo "✗ coverDeclines no longer lets a POST through (prd §756) — the rooms whose"; \
     echo "  newest thing is nearly always a post are exactly the ones the user asked"; \
     echo "  to cover."; exit 1;;
esac
case "$_veto" in
  *"SocialRoomSource.standsAlone(thing)"*) ;;
  *) echo "✗ coverDeclines decides what a post is by its SOURCE alone (prd §756) — a"; \
     echo "  like, a follow or an approval landed in a social room is not a post, and"; \
     echo "  the answer must come from rowKind (§489/§396a)."; exit 1;;
esac
# THE COVER DRAWS A POST AS A POST (prd §756): the author's face, the author's
# name, the whole postText. Each half fails invisibly — a cover under the wrong
# face still looks like a cover.
case "$(cat "$TMP/lede.nocomment")" in
  *"RemoteThumb(urlString: avatar"*) ;;
  *) echo "✗ the cover no longer leads a post with the author's picture (prd §756/§744)"; \
     echo "  — it would attribute the post to the network instead of the person."; exit 1;;
esac
_words=$(awk '/private var words: String/{f=1} f{print} f&&/^    }$/{exit}' "$TMP/lede.nocomment")
case "$_words" in
  *"SocialRoomSource.words(of: thing)"*) ;;
  *) echo "✗ the cover sets a post's 80-character title as its headline (prd §756) —"; \
     echo "  titleLine()'s clamp is built for a row with no room, and the cover has it."; exit 1;;
esac
grep -q 'Text(words)' "$TMP/lede.nocomment" \
  || { echo "✗ the cover's title block no longer draws \`words\` (prd §756) — the post"; \
       echo "  branch would be computed and thrown away."; exit 1; }
# THE COVER IS A LEAD LIKE ANY OTHER (prd §766): the head's block and well, the
# pinned foot, and words at `heading24` — never a length-picked `heading40`.
grep -q '\.dsRoomHeadBlock()' "$TMP/lede.nocomment" \
  || { echo "✗ the cover no longer draws the head template's block and well (prd §766)"; exit 1; }
grep -q 'LeadFooter()' "$TMP/lede.nocomment" \
  || { echo "✗ the cover lost the lead's pinned foot (prd §766)"; exit 1; }
grep -q 'heading40' "$TMP/lede.nocomment" \
  && { echo "✗ the cover sets its statement at heading40 again — a lead's words are"; \
       echo "  heading24 in every room (prd §766)"; exit 1; }
# THE ALL FEED'S COVER NEVER HOLDS THE BOX (prd §775). Both halves: the switch on
# the card gating `full`, and the one call site deciding it by feed.
grep -q 'let full = fillsLead && fillsTheBox(face, rungs: rungs)' "$TMP/lede.nocomment" \
  || { echo "✗ the cover's fixed box no longer yields to fillsLead — the All feed's"; \
       echo "  payout draws one line over an empty well again (prd §775)"; exit 1; }
grep -q 'fillsLead: source != "All"' "$TMP/feed.nocomment" \
  || { echo "✗ the cover's mount no longer decides fillsLead by feed — either the"; \
       echo "  All feed is held to leadHeight or a room stops being (prd §775)"; exit 1; }
# ONE COPY OF THE POST'S TWO FACTS (prd §756, the §396a class). Three readers
# now — the cover and the two post cards — and the two that existed before
# carried the same lines under a comment saying they were the same lines.
grep -q 'static func author(of thing: Thing)' "$SOCSRC" \
  || { echo "✗ SocialRoomSource no longer owns the author line (prd §756)"; exit 1; }
grep -q 'static func words(of thing: Thing)' "$SOCSRC" \
  || { echo "✗ SocialRoomSource no longer owns the post's words (prd §756)"; exit 1; }
for f in "$TMP/rows.nocomment" "$TMP/lede.nocomment"; do
  grep -q 'postText ?? ""' "$f" \
    && { echo "✗ $(basename "$f" .nocomment) unpacks postText by hand again (prd §756) —"; \
         echo "  that is the third copy of a two-line answer, which is how §396a's bug"; \
         echo "  reached three rooms. Read SocialRoomSource.words(of:)."; exit 1; }
done
grep -q 'leaderboard' "$TMP/feed.nocomment" \
  && { echo "✗ FeedScreen's code still mentions a leaderboard (prd §723)"; exit 1; }
# THE SHAPED ROOMS COVER TOO (prd §732). §723 reached only `bundledSections`;
# music and the reading list route through `groupedSections` and kept a count
# lede ("N songs today", "N saved this month") in the cover's slot.
grep -qE '\b(ListeningLede|ReadingLede|listeningLedeSection|readingLedeSection)\b' "$TMP/feed.nocomment" \
  && { echo "✗ a count lede is back in a shaped room — the newest thing is its head (prd §732)"; exit 1; }
# Music, the reading list and the generic room path (social, RSS, notes, media…).
[ "$(grep -c 'cover: heroShown ? nil : ledeThingID(in: days))' "$FEED")" -ge 3 ] \
  || { echo "✗ a headless room no longer covers its newest thing (prd §732)"; exit 1; }
# Every picture-grid room leads with its newest thing, lifted out ABOVE the
# grid (`newestLead`): X and Instagram since prd §821, Photos, Files, Snapchat
# and Telegram since §832. No grid declines the cover any more.
grep -qE 'cover: heroShown \|\| !(memoryTiles|tiles|photoTiles|imageTiles)\.isEmpty' "$FEED" \
  && { echo "✗ a picture grid declines the cover again (prd §832)"; exit 1; }
[ "$(grep -c 'let (cover, uncovered) = newestLead(visible, heroShown: heroShown)' "$FEED")" -eq 6 ] \
  || { echo "✗ a picture-grid room no longer leads with its newest thing above the grid (prd §821, §832)"; exit 1; }
grep -q 'photoGridSection(visible)' "$FEED" \
  && { echo "✗ the Photos room draws its whole grid with no cover again (prd §832)"; exit 1; }
grep -q 'if let coverThing, coverThing.isLive { ledeListRow(coverThing) }' "$FEED" \
  || { echo "✗ daySection no longer draws a shaped room's cover (prd §732)"; exit 1; }
# A SUPPRESSION TERM IS NOT A HEAD (prd §755). `rosterAccounts` belongs in every
# gate that picks a head card — it is why a social room draws no topic map, no
# mosaic, no distribution and no density grid — and it draws NOTHING itself, so
# `heroShown` may not carry it. It did for a month: the faces were a card in the
# feed when the term was written (§219), left for the shell in §362 and for the
# dock's own capsule in §753, and the term stayed. Every social room with two or
# more accounts drew no head and no cover — an empty slot at the top of the one
# room family whose newest thing is what you came for.
#
# Read off `heroShown`'s own expression, not the file: the term must still be
# present in the gates above it, so a file-wide grep would prove nothing.
_hero=$(awk '/let heroShown = /{f=1} f{print} f&&/distribution != nil/{exit}' "$TMP/feed.nocomment")
[ -n "$_hero" ] \
  || { echo "✗ could not read heroShown's expression — the §755 check below would"; \
       echo "  pass on nothing."; exit 1; }
case "$_hero" in
  *rosterAccounts*) echo "✗ heroShown counts rosterAccounts as a head again (prd §755) — the faces"; \
       echo "  have not drawn in the feed since §362, so this suppresses the cover in"; \
       echo "  every social room and puts nothing in its place."; exit 1;;
esac
# THE ANNIVERSARY, moved here from `journal-room-selftest.sh` when the journal
# head it outranked was deleted (prd §832). It may lead only a journal room —
# widen it and a nostalgia card covers something time-critical — and a text
# anniversary must draw words, or it suppresses the cover and draws nothing.
grep -q 'guard JournalRoomSource.sources.contains(source) else { return nil }' "$FEED" \
  || { echo "✗ the anniversary is no longer scoped to the journal rooms (§398)"; exit 1; }
grep -q 'if echo.thing.previewImageData != nil { picture } else { words }' Casberi/Casberi/GenUI/GenRenderer.swift \
  || { echo "✗ OnThisDayHero no longer falls back to words — a text anniversary would draw an empty slot"; exit 1; }
grep -qE 'static let sources: Set<String> = \[[^]]*"Obsidian"' Casberi/Casberi/Model/JournalRoomSource.swift \
  && { echo "✗ Obsidian joined the journal rooms — its dates are file edits"; exit 1; }
for gone in Model/AgentRoom Model/AgentRoomSource Screens/AgentRoomCard Model/JournalRoom Screens/JournalRoomCard; do
  if [ -e "Casberi/Casberi/$gone.swift" ]; then
    echo "✗ $gone is back (prd §832) — the chat and journal rooms lead with their newest thing"; exit 1
  fi
done
# The density grid that term suppressed is DELETED (prd §832), with every
# room figure that could stand in for the newest thing: the year-heatmap
# registry and the art wall. A room with no head leads with its cover.
[ -e Casberi/Casberi/Model/FeedHeatmap.swift ] \
  && { echo "✗ the year-heatmap registry is back (prd §832) — it held the slot the newest thing leads"; exit 1; }
grep -q 'static func mosaic(' Casberi/Casberi/Model/FeedInsight.swift \
  && { echo "✗ the art wall is back (prd §832) — it held the slot the newest thing leads"; exit 1; }
grep -qE 'ImageMosaicHero|calendarHeatmapSection|heatmapLabel' "$TMP/feed.nocomment" \
  && { echo "✗ the room can draw a wall or a year grid in its lead again (prd §832)"; exit 1; }

# ── 4. Feed health, in the room ────────────────────────────────────────────
grep -q 'FeedRoomHealthSource.standing(for: source)' "$FEED" \
  || { echo "✗ the room no longer computes its feeds' health"; exit 1; }
grep -q 'route.pushBridge(destination)' "$TMP/feed.nocomment" \
  || { echo "✗ the health note is a label again — the one useful response is to"; \
       echo "  open the followed list, and nothing else on screen offers it"; exit 1; }
# All five feed-following rooms, or a bridge silently loses the note.
for room in RSS Substack Reddit YouTube Podcasts; do
  grep -q "\"$room\"" "$SOURCE" \
    || { echo "✗ $room is not in FeedRoomHealthSource — its room can never say"; \
         echo "  that one of its feeds stopped answering"; exit 1; }
done
# NEGATIVE: the verdict must never be derived from the room's ROWS. The whole
# subject is a feed that stopped producing rows, so a row-derived verdict is
# structurally blind to it.
python3 - "$SOURCE" "$HEALTH" <<'PY' || exit 1
import re, sys
for path in sys.argv[1:]:
    src = "\n".join(l for l in open(path).read().splitlines()
                    if not l.strip().startswith("//"))
    if re.search(r"\bThing\b", src):
        print(f"✗ {path} reads Thing — a feed that stopped producing rows cannot")
        print("  be found by looking at the rows it stopped producing")
        sys.exit(1)
PY

# --- the driver -------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}
typealias Feed = FeedRoomHealth.Feed

/// The fixture stands in for `FeedFreshness.trouble(for:)`.
///
/// It answers for the EMPTY string on purpose. Without that, the guard that
/// skips a follow with no resolved feed URL could be deleted and every
/// assertion here would still pass — the rule would be tested by nothing. (A
/// fixture only tests the rule it names if it FAILS that rule and passes every
/// other one.)
let troubled: [String: String] = [
    "https://a.example/feed": "Hasn't answered in 12 days",
    "https://b.example/feed": "No feed at this address",
    "": "Hasn't answered yet",
]
func trouble(_ url: String) -> String? { troubled[url] }

// ── nothing to say ─────────────────────────────────────────────────────────
print("standing — silence is the common case")
check("every feed answering → nil",
      FeedRoomHealth.standing(
        feeds: [Feed(name: "Fine", url: "https://ok.example/feed")],
        trouble: trouble) == nil)
check("no feeds at all → nil",
      FeedRoomHealth.standing(feeds: [], trouble: trouble) == nil)

// ── one feed carries its own observed reason ───────────────────────────────
print("\nstanding — one feed is NAMED, with what was observed about it")
let one = FeedRoomHealth.standing(
    feeds: [Feed(name: "Fine", url: "https://ok.example/feed"),
            Feed(name: "Stratechery", url: "https://a.example/feed")],
    trouble: trouble)
check("the troubled feed is the only one named", one?.quiet == ["Stratechery"])
check("the line names it", one?.line.contains("Stratechery") == true)
check("…and states what was observed",
      one?.line.contains("Hasn't answered in 12 days") == true)
check("…and never says the feed is gone",
      one?.line.localizedCaseInsensitiveContains("gone") == false)

// ── several are counted, never merged ──────────────────────────────────────
print("\nstanding — several feeds are COUNTED, because their reasons differ")
// THREE feeds, TWO of them troubled — deliberately not two-of-two. The count
// printed is of what is BROKEN, and with an equal fixture a line counting the
// feeds you follow would read as correct.
let two = FeedRoomHealth.standing(
    feeds: [Feed(name: "Stratechery", url: "https://a.example/feed"),
            Feed(name: "Fine", url: "https://ok.example/feed"),
            Feed(name: "Old Blog", url: "https://b.example/feed")],
    trouble: trouble)
check("both are collected", two?.quiet == ["Stratechery", "Old Blog"])
check("the line counts them", two?.line.contains("2") == true)
check("…and counts the TROUBLED feeds, not the followed ones",
      two?.line.contains("3") == false)
// The failure this exists to stop: one feed's reason printed over two feeds.
check("no single feed's reason is applied to both",
      two?.line.contains("Hasn't answered in 12 days") == false)
check("…and not the other's either",
      two?.line.contains("No feed at this address") == false)

// ── an unresolved follow is not a failure we have observed ─────────────────
print("\nstanding — a follow with no resolved feed URL is never reported")
check("an empty URL is skipped even when trouble would answer for it",
      FeedRoomHealth.standing(feeds: [Feed(name: "New channel", url: "")],
                              trouble: trouble) == nil)
check("a whitespace-only URL is skipped too",
      FeedRoomHealth.standing(feeds: [Feed(name: "New channel", url: "   ")],
                              trouble: trouble) == nil)
check("…and it does not suppress a real one beside it",
      FeedRoomHealth.standing(
        feeds: [Feed(name: "New channel", url: ""),
                Feed(name: "Stratechery", url: "https://a.example/feed")],
        trouble: trouble)?.quiet == ["Stratechery"])

// ── the words are a name, never plumbing ───────────────────────────────────
print("\nstanding — the line reads as a name")
check("a nameless feed falls back to its address, not to nothing",
      FeedRoomHealth.standing(feeds: [Feed(name: "", url: "https://a.example/feed")],
                              trouble: trouble)?.quiet == ["https://a.example/feed"])
check("a name's own whitespace is trimmed",
      FeedRoomHealth.standing(feeds: [Feed(name: "  Stratechery  ",
                                           url: "https://a.example/feed")],
                              trouble: trouble)?.quiet == ["Stratechery"])
check("a whitespace-only name falls back to the address",
      FeedRoomHealth.standing(feeds: [Feed(name: "   ", url: "https://a.example/feed")],
                              trouble: trouble)?.quiet == ["https://a.example/feed"])

// ── order ──────────────────────────────────────────────────────────────────
print("\nstanding — the given order is kept")
check("the first troubled feed leads",
      FeedRoomHealth.standing(
        feeds: [Feed(name: "Old Blog", url: "https://b.example/feed"),
                Feed(name: "Stratechery", url: "https://a.example/feed")],
        trouble: trouble)?.quiet == ["Old Blog", "Stratechery"])
check("a single feed's reason is ITS reason, not the list's first entry",
      FeedRoomHealth.standing(
        feeds: [Feed(name: "Fine", url: "https://ok.example/feed"),
                Feed(name: "Old Blog", url: "https://b.example/feed")],
        trouble: trouble)?.line.contains("No feed at this address") == true)

print(failures == 0 ? "\nAll assertions passed." : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

# `-Onone`, not `-O`: 97% of a pure-logic harness's wall time is the optimizer,
# and it buys nothing an assertion can see. NOT a blanket rule — `-O` can change
# a harness's OBSERVABLE behaviour (a trapping one prints NOTHING under `-O`) —
# so this file was proven equivalent run-for-run by
# `scripts/support/harness-opt-probe.sh` before the swap (2026-09-05, 1.7x faster).
# Re-probe before trusting it again after adding mutations.
if ! swiftc -Onone -o "$TMP/run" "$HEALTH" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ the shipped FeedRoomHealth.swift did not compile against the harness"
  grep -E 'error:' "$TMP/build.log" | head -20
  exit 1
fi
"$TMP/run"

# --- mutations --------------------------------------------------------------
# A check that cannot fail proves nothing. Each mutation is a plausible
# "simplification" of the shipped source, and each must break the run.
echo
echo "mutations (each must be caught)"

WORK="$TMP/work"
mutate() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$HEALTH" "$WORK/FeedRoomHealth.swift"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/FeedRoomHealth.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$WORK/FeedRoomHealth.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -Onone -o "$TMP/mut" "$WORK/FeedRoomHealth.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 1. A follow with no resolved feed URL reported as a failure we never observed.
mutate "the unresolved-follow skip removed" \
  'guard !url.isEmpty else { continue }' \
  'if false { continue }'

# 2. One feed's reason printed over several — the merge the type doc refuses.
mutate "several feeds given one feed's reason" \
  'line = String(localized: "\(quiet.count.formatted()) feeds need a look")' \
  'line = String(localized: "\(quiet.count.formatted()) feeds · \(quiet[0].reason)")'

# 3. The name dropped, so the room's one line reads as a raw address.
mutate "the name fallback inverted" \
  'quiet.append((name.isEmpty ? url : name, reason))' \
  'quiet.append((url, reason))'

# 4. A healthy room made to speak — the note becomes permanent chrome.
mutate "silence removed" \
  'guard !quiet.isEmpty else { return nil }' \
  'if quiet.isEmpty { return Standing(quiet: [], line: "All feeds fine") }'

# 5. The lone troubled feed sent down the counting branch — it loses the one
#    thing that was actually observed about it and reads "1 feeds need a look".
mutate "a single feed counted instead of named" \
  'if quiet.count == 1 {' \
  'if quiet.count == 0 {'

# 6. The count line counting FOLLOWS rather than failures — "12 feeds need a
#    look" on a room where one blog went quiet.
mutate "the count line counting followed feeds" \
  'line = String(localized: "\(quiet.count.formatted()) feeds need a look")' \
  'line = String(localized: "\(feeds.count.formatted()) feeds need a look")'

# 7. The name's whitespace kept, so a trimmed fixture no longer matches.
mutate "name trimming dropped" \
  'let name = feed.name.trimmingCharacters(in: .whitespacesAndNewlines)' \
  'let name = feed.name'

echo
echo "✓ feed-reading self-test: assertions and mutations all passed"
