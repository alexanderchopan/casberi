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
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
RENDER="Casberi/Casberi/GenUI/GenRenderer.swift"
for f in "$HEALTH" "$SOURCE" "$ARTICLE" "$BODY" "$CONTENT" "$INSIGHT" "$FEED" "$RENDER"; do
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
    print("  an eight-second await (CLAUDE.md corollary 6)")
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

# ── 3. The board that narrows its own room ─────────────────────────────────
grep -q 'case publisher' "$INSIGHT" \
  || { echo "✗ FeedInsight.Leaderboard.Scope is gone — a reading board can no"; \
       echo "  longer say which field it ranked, so the room cannot narrow"; exit 1; }
# The two reading rooms that pick a board at RUNTIME must carry the scope down
# BOTH arms, or the corpora that took the other branch narrow to nothing.
grep -q 'scope: .writer, key: writer' "$INSIGHT" \
  || { echo "✗ the bylines board no longer carries the writer scope"; exit 1; }
grep -q 'scope: .publisher, key: handle' "$INSIGHT" \
  || { echo "✗ a publisher board no longer carries the publisher scope"; exit 1; }
grep -q 'scope: board.scope' "$INSIGHT" \
  || { echo "✗ bylines' re-wrap drops the scope — a bylined room's board would"; \
       echo "  silently lose the scope the board it wraps was built with"; exit 1; }
# THE INVARIANT: the rows narrow and the BOARD does not. A board recomputed
# over one publisher's rows is one bar naming the choice you already made.
grep -q 'narrowingToPublisher: false' "$TMP/feed.nocomment" \
  || { echo "✗ the room's board is computed over the narrowed rows — it would"; \
       echo "  collapse to the one publisher you picked, with no way back"; exit 1; }
grep -q 'readingScope?.key ?? ""' "$FEED" \
  || { echo "✗ the reading scope is not in headIdentity — the head memo would"; \
       echo "  serve a card describing rows that are no longer on screen"; exit 1; }
grep -q 'selected: readingScope?.label' "$FEED" \
  || { echo "✗ the board no longer shows which row the room is narrowed to"; exit 1; }
grep -q 'var selected: String?' "$RENDER" \
  || { echo "✗ LeaderboardHero cannot draw a selection"; exit 1; }
# Tapping the selected row must CLEAR it: the board is this scope's only
# control, so it has to be able to undo itself.
grep -q 'readingScope?.label == row.label' "$TMP/feed.nocomment" \
  || { echo "✗ tapping the scoped row no longer clears the scope — a narrowing"; \
       echo "  with no way out is the dead end §83 forbids"; exit 1; }

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

if ! swiftc -O -o "$TMP/run" "$HEALTH" "$TMP/main.swift" 2>"$TMP/build.log"; then
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
  if ! swiftc -O -o "$TMP/mut" "$WORK/FeedRoomHealth.swift" "$TMP/main.swift" 2>/dev/null; then
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
