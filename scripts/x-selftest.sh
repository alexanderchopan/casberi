#!/bin/zsh
# Casberi X self-test — verifies the SHIPPED pure logic behind both halves of
# the X work (prd §280, 2026-08-02):
#
#   Casberi/Casberi/Model/OEmbed.swift
#     — blockquoteText   (the words lifted out of an X embed, the ONLY reason
#                         an X link gets a face at all)
#   Casberi/Casberi/Model/XArchiveImport.swift
#     — snowflakeDate    (the only date a liked post will ever have)
#     — parseArray       (the archive's files are JavaScript, not JSON)
#     — clean            (t.co → real link, and the entity decode)
#     — identifier       (id_str vs a numeric id past Double's exact range)
#
# WHY A HARNESS AND NOT A SIM CHECK. The archive importer was authored against
# no real X archive, and every failure mode here is a SILENT WRONG ANSWER
# rather than a crash: a liked post dated to the snowflake epoch instead of
# refused, an archive that parses to zero rows and reads as an empty account,
# a post indexed as "Q&amp;A". All of those render and look plausible. The only
# way to know they're right is to feed them inputs whose answers are known.
#
# Both files are far too entangled to compile as shipped (SwiftData models, a
# ModelContext, SpotlightIndex), so the pure functions are EXTRACTED from the
# shipped source by name — never copied into this file — so the harness cannot
# pass against logic the app doesn't run. The only transformation is stripping
# `private `. If an extraction stops matching, the compile fails loudly rather
# than asserting nothing.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

OEMBED="Casberi/Casberi/Model/OEmbed.swift"
XARCH="Casberi/Casberi/Model/XArchiveImport.swift"
SUPPORT="Casberi/Casberi/Model/IngestSupport.swift"
for f in "$OEMBED" "$XARCH" "$SUPPORT"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards -----------------------------------------------------------
# Each of these is a wiring fact the extracted functions can't prove on their
# own: a perfect `blockquoteText` is worthless if `parse` stops calling it, and
# a perfect `snowflakeDate` is worthless if likes stop being dated by it.
grep -q '"https://publish.x.com/oembed' "$OEMBED" \
  || { echo "✗ OEmbed no longer carries the X endpoint"; exit 1; }
grep -q '"x.com", "twitter.com"' "$OEMBED" \
  || { echo "✗ OEmbed's X row no longer covers both hosts"; exit 1; }
grep -q 'text("title") ?? blockquoteText' "$OEMBED" \
  || { echo "✗ parse no longer falls back to the embed's blockquote"; exit 1; }
grep -q 'snowflakeDate(id)' "$XARCH" \
  || { echo "✗ likes are no longer dated from the post id"; exit 1; }
grep -q 'raw.hasPrefix("RT @")' "$XARCH" \
  || { echo "✗ reposts are no longer skipped"; exit 1; }
grep -q '"X"' Casberi/Shared/Thing.swift \
  || { echo "✗ X is not a bulk-import source — its rows would flood All"; exit 1; }

# --- 2026-08-05: the searchability pass -------------------------------------
# Each of these is a wiring fact behind "the room has 3,500 posts in it and an
# ask that names X comes back with five unrelated things". The extracted
# functions below prove the JUDGEMENT; these prove it is still reached.
RETRIEVER="Casberi/Casberi/Model/Retriever.swift"
COMPOSERS="Casberi/Casberi/Model/KeptAskComposers.swift"
grep -q 'Self.sourceFilter(in: query)' "$RETRIEVER" \
  || { echo "✗ rank no longer resolves a source from the query"; exit 1; }
grep -q 'thing.source != sourceMatch.source' "$RETRIEVER" \
  || { echo "✗ the resolved source is no longer used as a filter"; exit 1; }
grep -q 'sources: \[String\] = BridgeCatalog.offers.map(\\.name)' "$RETRIEVER" \
  || { echo "✗ the source vocabulary is no longer the catalog (a corpus-derived one can't name an archive outside the fetch window)"; exit 1; }
grep -q 'sourceMatch != nil || facetMatch != nil' "$RETRIEVER" \
  || { echo "✗ a BARE source or facet ask no longer lists that set"; exit 1; }
grep -q '!thing.tags.contains(facetMatch.tag)' "$RETRIEVER" \
  || { echo "✗ a named facet is no longer used as a filter"; exit 1; }
grep -q 'Corpus.bulkImportSources.contains(source)' "$COMPOSERS" \
  || { echo "✗ contextRecap no longer routes an imported room past the week window"; exit 1; }
grep -q 'scoped.predicate = #Predicate { \$0.source == source }' Casberi/Casberi/Shell/RootShell.swift \
  || { echo "✗ an ask naming a source is no longer fetched scoped to it"; exit 1; }
# The room's own registries. X was in NONE of these until 2026-08-05, so the
# room led with nothing at all — and `healTopics(source: "X")` had been called
# by the import screen the whole time against a switch that answered nil.
TOPICS="Casberi/Casberi/Model/ScreenshotTopics.swift"
grep -q 'case "X":         return TopicSource' "$TOPICS" \
  || { echo "✗ X has no topic source — its import screen's healTopics call is a no-op again"; exit 1; }
# 2026-08-06: the SAME registry gap, one room over. prd §309 gave TikTok a
# topic map whose writing spans two kinds and never taught this switch about
# it, so `healTopics(source: "TikTok")` returned 0 and the card could never
# render. A count of zero and a card that doesn't exist look identical.
grep -q 'case "TikTok":    return TopicSource' "$TOPICS" \
  || { echo "✗ TikTok has no topic source — its map can never get terms"; exit 1; }
grep -q '"X":             Label(title: "Your X year"' Casberi/Casberi/Model/FeedHeatmap.swift \
  || { echo "✗ X has no heatmap label — and with it goes the room's On This Day, which rides inside that card"; exit 1; }
grep -q 'connected("x")' Casberi/Casberi/Model/BridgeRefresh.swift \
  || { echo "✗ X does no foreground work — topics stop draining and authors are never fetched"; exit 1; }
# The reply lead is a DRIFT GUARD and not an extracted assertion, deliberately:
# `landTweets` builds `Thing`s and can't be compiled here, so the Swift checks
# below can only prove that a trailing recipient IS eaten by the clamp — not
# that the shipped importer leads with it. Reverting the composition alone left
# this harness fully green, which is the Cursor-selftest lesson (a guard must
# prove the real condition, not that the words appear somewhere).
grep -qF 'let face = row.replyTo.map { "To @\($0) · \(row.text)" } ?? row.text' "$XARCH" \
  || { echo "✗ a reply's recipient no longer LEADS its title — titleLine's 80-char clamp eats a trailing one (§303)"; exit 1; }
# The caps. Not an exact number — that should be free to move — but a floor far
# above the 1,000/500 that silently dropped two thirds of a real archive.
python3 - "$XARCH" <<'PY' || exit 1
import re, sys
src = open(sys.argv[1]).read()
for name, floor in (("postCap", 5_000), ("likeCap", 2_500)):
    m = re.search(rf"let {name} = ([\d_]+)", src)
    if not m:
        sys.exit(f"✗ {name} is gone — an archive's landing bound is unreadable")
    if int(m.group(1).replace("_", "")) < floor:
        sys.exit(f"✗ {name} is back below {floor:,} — a normal archive lands truncated")
PY
grep -q 'summary.droppedPosts += max(0, rows.count - postCap)' "$XARCH" \
  || { echo "✗ the cap no longer counts what it refused — a truncated import reads as a complete one"; exit 1; }

# --- 2026-08-06: the room reads as a room -----------------------------------
# The reported symptom was two things at once: "just a long list" and "the
# treemap seems incorrect". Both were wiring, and both failed invisibly — a
# BandRow renders perfectly over a room of prose, and a treemap of `t.co`
# renders perfectly over anybody's writing. Each guard below is the specific
# line whose absence brings one of them back.
FEEDSCREEN="Casberi/Casberi/Screens/FeedScreen.swift"
grep -q 'case "X":                   self = .x' "$FEEDSCREEN" \
  || { echo "✗ X has no room shape again — it falls to .plain and the room is a wall of 80-char BandRows"; exit 1; }
grep -q 'PostCard(thing: thing)' "$FEEDSCREEN" \
  || { echo "✗ nothing renders a post as a post"; exit 1; }
# An IMPORT has no media URL to give — `ImportMedia` decodes the archive's own
# file to bytes on the row, inside the folder grant. Without a stored-bytes
# branch the card draws none of them: pixels in the store and none on screen,
# which is §283's Files bug in a new room.
grep -q 'thing.previewImageData, let stored = UIImage(data: data)' Casberi/Casberi/Screens/ShapedRows.swift \
  || { echo "✗ PostCard can't draw a picture the app already holds — every imported post loses its media"; exit 1; }
# The treemap's root cause. `clean` expands `entities["urls"]` and used to stop
# there, so a picture's own shortlink rode into `content` on every post that
# had one, `t.co` read as a hostname, and `cells` — which credits each row to
# its single most common term — collapsed the room into one cell.
grep -q 'entities?\["media"\] as? \[\[String: Any\]\]' "$XARCH" \
  || { echo "✗ clean no longer strips a media shortlink — t.co returns as a topic"; exit 1; }
# The other half of the same fix: a hostname is not a subject in a room of
# writing. If X's TopicSource says otherwise, every link a person shared reads
# as what they wrote about.
grep -q 'case "X":         return TopicSource(kinds: \[.note\], needsOCR: false, includeDomains: false)' "$TOPICS" \
  || { echo "✗ X counts domains as topics again — the map goes back to naming hosts"; exit 1; }
grep -q 'terms(in: thing.content, includeDomains: spec.includeDomains)' "$TOPICS" \
  || { echo "✗ the sweep no longer passes the writing/pixels fork — every room reads domains again"; exit 1; }
# The repair. Without it the fix reaches only rows imported AFTER it, which for
# a bulk import room — where everything landed on one afternoon — is nothing.
grep -q 'private static func restamp' "$TOPICS" \
  || { echo "✗ no re-read for rows stamped under the old term rules — an existing room keeps its old map forever"; exit 1; }
grep -q 'await XArchiveImport.healRoom(context: context)' Casberi/Casberi/Model/BridgeRefresh.swift \
  || { echo "✗ rows landed before the room had a shape never gain the fields it draws (and a re-import can't: landTweets skips a seen ref)"; exit 1; }
# What the card DRAWS. `postText` is `PostCard`'s body, `parent` is its
# "Replying to @…" line, `socialContext` is the word that tells your own
# writing from a post you liked.
grep -q 'thing.postText = row.text' "$XARCH" \
  || { echo "✗ a post's full sentence is no longer in the field the card renders"; exit 1; }
grep -qF 'thing.parent = SocialCard(handle: replyTo, text: ""' "$XARCH" \
  || { echo "✗ a reply no longer says who it answers — the card doesn't draw the title's 'To @' lead"; exit 1; }
grep -q 'thing.socialContext = "liked"' "$XARCH" \
  || { echo "✗ a liked post is no longer marked — half the room stops being distinguishable from your own writing"; exit 1; }
grep -q 'sources.union(\["Slack", "X"\])' Casberi/Casberi/Model/SocialBridge.swift \
  || { echo "✗ X lost its context label — the 'Liked' marker it stamps would render nowhere"; exit 1; }
# S4's premise — every `.note` is a capture waiting to become an outcome —
# expired the day the import rooms landed published writing under that kind,
# and nothing said so. An X post from 2019 is not a task.
grep -q 'if !Corpus.bulkImportSources.contains(thing.source) {' Casberi/Casberi/Model/Verbs.swift \
  || { echo "✗ an imported post offers 'Send to Reminders' again — S4's capture rule reaching rows nobody captured"; exit 1; }
# The probe that could not have caught ANY of this. It filtered a room of
# `.note` posts down to `.screenshot` and reported "no card" on every run.
grep -q 'let screens = shots.filter { !Corpus.isImportReceipt($0) }' Casberi/Casberi/Shell/ProbeHooks.swift \
  || { echo "✗ -topicMapProbe is guessing a room's kinds again — it goes blind for every room whose map spans more than one"; exit 1; }

# --- 2026-08-05: the same guarantees for the other three import rooms --------
# prd §309. X's caps were found by a person noticing their room was short;
# Instagram, TikTok and Snapchat had the identical bug and nobody had looked.
# These are checked HERE rather than in three new scripts because they are one
# ruling with four instances, and a rule split across four files is a rule that
# drifts.
IG="Casberi/Casberi/Model/InstagramImport.swift"
TT="Casberi/Casberi/Model/TikTokImport.swift"
SC="Casberi/Casberi/Model/SnapchatImport.swift"
python3 - "$IG" "$TT" "$SC" <<'PY' || exit 1
import re, sys
ig, tt, sc = sys.argv[1:4]
# (file, constant, floor) — floors, not exact values: the numbers should stay
# free to move, but never back under the ones that truncated a real export.
for path, name, floor in (
    (ig, "writingCap", 5_000), (ig, "tapCap", 2_500),
    (tt, "writingCap", 5_000), (tt, "tapCap", 2_500),
    (sc, "chatCap", 1_000),    (sc, "memoryCap", 5_000),
):
    m = re.search(rf"let {name} = ([\d_]+)", open(path).read())
    if not m:
        sys.exit(f"✗ {name} is gone from {path.split('/')[-1]}")
    if int(m.group(1).replace("_", "")) < floor:
        sys.exit(f"✗ {path.split('/')[-1]}: {name} is back under {floor:,} — a real export lands truncated")
# Every one of them must COUNT what it refused. A raised cap without this is
# the same silent failure one order of magnitude further out.
for path in (ig, tt, sc):
    if "summary.dropped += max(0," not in open(path).read():
        sys.exit(f"✗ {path.split('/')[-1]} raises a cap but never counts what it dropped")
PY
grep -q 'thing.tags.append("Gone")' Casberi/Casberi/Model/InstagramCaptions.swift \
  || { echo "✗ Instagram stops asking about a gone post but no longer RECORDS it — the fact lives only in a UserDefaults ledger"; exit 1; }
grep -q 'OEmbed.meansGone(status)' "$TT" \
  || { echo "✗ TikTok's face pass is blind to a deletion again — a dead video is re-asked forever and reads as a broken endpoint"; exit 1; }
grep -q '!$0.tags.contains("Gone")' "$TT" \
  || { echo "✗ a gone TikTok row is pending again — one request per dead video, every pass, forever"; exit 1; }
grep -q 'tags: \["Conversation"\]' "$SC" \
  || { echo "✗ Snapchat's rows are untagged again — the one import room whose halves can't be named"; exit 1; }
grep -q 'already.tags.append("Memory")' "$SC" \
  || { echo "✗ Snapchat no longer repairs a row that predates the tag — the facet reaches only rows landed from today on"; exit 1; }
grep -q 'kinds = \[.link, .note\]' Casberi/Casberi/Model/FeedInsight.swift \
  || { echo "✗ TikTok's topic map is back to one kind — it would cover half the writing while claiming all of it"; exit 1; }

# --- 2026-08-05: prd §310, the upkeep pass ---------------------------------
grep -q 'await ImportCommit.commit' "$XARCH" \
  || { echo "✗ X lands in one transaction again — at the raised caps that holds the main thread for the whole import"; exit 1; }
grep -q 'await ImportCommit.commit' "$IG" \
  || { echo "✗ Instagram lands in one transaction again"; exit 1; }
grep -q 'await ImportCommit.commit' "$TT" \
  || { echo "✗ TikTok lands in one transaction again"; exit 1; }
grep -q 'await Task.yield()' Casberi/Casberi/Model/ImportCommit.swift \
  || { echo "✗ ImportCommit no longer yields — chunking without a yield buys nothing at all"; exit 1; }
# The receipt must land AFTER the rows, or a partial import is crowned with a
# total it never reached.
python3 - "$XARCH" "$IG" "$TT" <<'PYEOF' || exit 1
import sys
for path in sys.argv[1:]:
    src = open(path).read()
    commit = src.find("await ImportCommit.commit")
    receipt = src.find("ImportReceipt.land")
    if commit < 0 or receipt < 0:
        sys.exit(f"✗ {path.split('/')[-1]}: can't find the landing order")
    if receipt < commit:
        sys.exit(f"✗ {path.split('/')[-1]}: the receipt lands BEFORE the rows — a partial import would claim a total it never reached")
PYEOF
# Media is a THUMBNAIL, never a copied original into a mirrored store.
grep -q 'kCGImageSourceThumbnailMaxPixelSize: 480' Casberi/Casberi/Model/ImportMedia.swift \
  || { echo "✗ imported media is no longer a 480pt thumbnail — originals in a CloudKit-mirrored store is the thing this was careful not to do"; exit 1; }
grep -q 'resolved.path.hasPrefix(fence)' Casberi/Casberi/Model/ImportMedia.swift \
  || { echo "✗ a relative media path can escape the export folder — that path is data out of a file"; exit 1; }
# DMs stay OFF unless asked.
grep -q 'if ImportOptions.includeMessages' "$XARCH" \
  || { echo "✗ X imports messages unconditionally — §245's whole ruling is that this is a deliberate choice"; exit 1; }
grep -q 'if ImportOptions.includeMessages' "$IG" \
  || { echo "✗ Instagram imports messages unconditionally"; exit 1; }
grep -q 'UserDefaults.standard.bool(forKey: messagesKey)' Casberi/Casberi/Model/ImportOptions.swift \
  || { echo "✗ the messages default is no longer a plain false — off by default IS the safety property"; exit 1; }
# Removal is scoped to imports, never a live bridge.
grep -q 'Corpus.bulkImportSources.contains(source) else { return 0 }' Casberi/Casberi/Model/ImportRemoval.swift \
  || { echo "✗ per-source removal is no longer scoped to imports — a live bridge's rows are not a decision to undo"; exit 1; }

TMP=$(mktemp -d /tmp/x-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- extract the shipped functions -----------------------------------------
python3 - "$OEMBED" "$XARCH" "$SUPPORT" "$TMP/extracted.swift" "$TOPICS" <<'PY'
import re, sys
oembed, xarch, support, out, topics = sys.argv[1:6]

def grab(path, signature):
    """The whole function whose declaration line contains `signature`,
    brace-matched from the shipped source. Never a copy."""
    src = open(path).read()
    i = src.find(signature)
    if i < 0:
        sys.exit(f"✗ extraction failed: {signature!r} not found in {path}")
    start = src.rfind("\n", 0, i) + 1
    j = src.index("{", i)
    depth, k = 0, j
    while k < len(src):
        if src[k] == "{": depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0: break
        k += 1
    return src[start:k+1].replace("private ", "")

def grabvar(path, signature):
    """A computed/lazy `static let` initialised with a closure."""
    src = open(path).read()
    i = src.find(signature)
    if i < 0:
        sys.exit(f"✗ extraction failed: {signature!r} not found in {path}")
    start = src.rfind("\n", 0, i) + 1
    j = src.index("{", i)
    depth, k = 0, j
    while k < len(src):
        if src[k] == "{": depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0: break
        k += 1
    end = src.index("\n", k)
    return src[start:end].replace("private ", "")

retriever = "Casberi/Casberi/Model/Retriever.swift"

def grabline(path, signature):
    """A one-line `static let X = <literal>`. NOT `grabvar`, which brace-matches
    from the next `{` it sees — for a declaration with no closure that is the
    next FUNCTION's body, and it swallows it whole (which shows up as an
    invalid-redeclaration error, not as a missing constant)."""
    src = open(path).read()
    i = src.find(signature)
    if i < 0:
        sys.exit(f"✗ extraction failed: {signature!r} not found in {path}")
    start = src.rfind("\n", 0, i) + 1
    return src[start:src.index("\n", i)].replace("private ", "")

def wholefile(path):
    """A file that is Foundation-only by construction, compiled AS SHIPPED
    rather than by extraction — the strongest form this harness has."""
    src = open(path).read()
    return "\n".join(l for l in src.splitlines() if not l.startswith("import "))

pieces = [
    "import Foundation\n",
    "enum IngestSupport {",
    grab(support, "static func decodeHTMLEntities"),
    grab(support, "static func titleLine"),
    "}\n",
    "enum OEmbed {",
    grab(oembed, "static func blockquoteText"),
    grab(oembed, "static func handle(inAuthorURL"),
    "}\n",
    # `sourceFilter`'s default argument names the catalog, which drags in the
    # whole app. Stubbed to an empty list — every assertion below passes its
    # sources explicitly, and a drift guard above asserts the real default is
    # still `BridgeCatalog.offers`, which is the part a stub can't prove.
    "enum BridgeCatalog { struct Offer { let name: String }",
    "  static let offers: [Offer] = [] }\n",
    "enum Retriever {",
    grab(retriever, "static func sourceFilter"),
    grab(retriever, "static func facetFilter"),
    "}\n",
    # DateQuery is Foundation-only, so it compiles exactly as it ships.
    wholefile("Casberi/Casberi/Model/DateQuery.swift"),
    "\nenum XThreads {",
    grab(xarch, "static func threadTexts"),
    grabline(xarch, "static let threadCap"),
    grab(xarch, "static func parentIdentifier"),
    grab(xarch, "static func metric"),
    "}\n",
    "enum XArchiveImport {",
    grab(xarch, "static func snowflakeDate"),
    grab(xarch, "static func parseArray"),
    grab(xarch, "static func clean"),
    grab(xarch, "static func identifier"),
    grab(xarch, "static func created"),
    grabvar(xarch, "static let twitterDateFormatter"),
    "}\n",
    # The treemap's reading surface for a room of WRITING (2026-08-06). Both
    # are Foundation-only — `terms(in:)` itself needs NLTagger and a model
    # whose output is nobody's contract, so what is asserted here is the part
    # that has a right answer: which spans reach the tagger at all. That is
    # exactly where the `t.co` cell came from.
    "enum ScreenshotTopics {",
    grabline(topics, "static let domainPattern"),
    grab(topics, "static func hashtags"),
    grab(topics, "static func prose"),
    "}\n",
]
open(out, "w").write("\n".join(pieces))
PY

# --- the driver -------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}
func iso(_ d: Date?) -> String {
    guard let d else { return "nil" }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: d)
}

print("blockquoteText — the words out of an X embed")
// The exact payload publish.x.com returned for x.com/jack/status/20 (measured
// 2026-08-02), reproduced byte for byte.
let jack = "<blockquote class=\"twitter-tweet\"><p lang=\"en\" dir=\"ltr\">just setting up my twttr</p>&mdash; jack (@jack) <a href=\"https://x.com/jack/status/20?ref_src=twsrc%5Etfw\">March 21, 2006</a></blockquote>\n\n"
check("lifts the post's own words", OEmbed.blockquoteText(jack) == "just setting up my twttr")

// The @XDevelopers payload — <br><br> paragraphing and a trailing t.co anchor.
let devs = "<blockquote class=\"twitter-tweet\"><p lang=\"en\" dir=\"ltr\">API Posting will increase to $0.015 per post from $0.01.<br><br>More details: <a href=\"https://t.co/vdqTnQxJil\">https://t.co/vdqTnQxJil</a></p>&mdash; Developers (@XDevelopers) <a href=\"https://x.com/XDevelopers/status/2044919377544261979\">April 16, 2026</a></blockquote>"
let devText = OEmbed.blockquoteText(devs)
check("<br> becomes a space, not a join",
      devText == "API Posting will increase to $0.015 per post from $0.01. More details: https://t.co/vdqTnQxJil")
check("the attribution line is left out",
      !(devText ?? "").contains("XDevelopers") && !(devText ?? "").contains("April 16"))

// ORDER: entities are decoded AFTER tags are stripped. If that flips, an
// escaped tag somebody actually typed becomes a real tag and gets eaten.
let escaped = "<blockquote><p>use &lt;b&gt;bold&lt;/b&gt; sparingly &amp; well</p></blockquote>"
check("an escaped tag survives as text",
      OEmbed.blockquoteText(escaped) == "use <b>bold</b> sparingly & well")

check("no <p> at all (an iframe embed) → nil", OEmbed.blockquoteText("<iframe src=\"x\"></iframe>") == nil)
check("an empty <p> → nil", OEmbed.blockquoteText("<blockquote><p></p></blockquote>") == nil)
check("nil in → nil out", OEmbed.blockquoteText(nil) == nil)
check("a page-sized payload is refused",
      OEmbed.blockquoteText("<p>" + String(repeating: "a", count: 70_000) + "</p>") == nil)

print("snowflakeDate — the only date a like will ever have")
// LIVE-VERIFIED: publish.x.com independently reports "April 16, 2026" for this
// same post. If this assertion ever fails, the epoch or the shift is wrong and
// every imported like is silently misdated.
check("2044919377544261979 → 2026-04-16",
      iso(XArchiveImport.snowflakeDate("2044919377544261979")) == "2026-04-16")
// To the MILLISECOND, and deliberately so: the day alone is far too coarse to
// hold the epoch constant honest. A first pass of this harness asserted only
// the date, and a mutation that moved the epoch by 657ms passed it clean —
// the constant could have been meaningfully wrong with nothing to catch it.
check("…and to the exact millisecond (the epoch constant itself)",
      XArchiveImport.snowflakeDate("2044919377544261979")?.timeIntervalSince1970 == 1_776_381_747.028)
check("1738963372425732512 → 2023-12-24",
      iso(XArchiveImport.snowflakeDate("1738963372425732512")) == "2023-12-24")
// id 20 decodes to the epoch itself (2010-11-04) — a confident wrong answer,
// which is exactly why anything pre-snowflake is refused instead.
check("the first tweet (id 20) is refused, not dated to the epoch",
      XArchiveImport.snowflakeDate("20") == nil)
check("a pre-snowflake id just under the floor is refused",
      XArchiveImport.snowflakeDate("29999999999") == nil)
check("the first snowflake id is accepted",
      XArchiveImport.snowflakeDate("30000000000") != nil)
check("garbage → nil", XArchiveImport.snowflakeDate("not-an-id") == nil)
check("empty → nil", XArchiveImport.snowflakeDate("") == nil)

print("parseArray — the files are JavaScript, not JSON")
let js = "window.YTD.tweets.part0 = [{\"tweet\":{\"id_str\":\"1\"}}]"
check("the assignment prefix is cut",
      XArchiveImport.parseArray(Data(js.utf8))?.count == 1)
check("plain JSON still reads",
      XArchiveImport.parseArray(Data("[{\"a\":1}]".utf8))?.count == 1)
check("a multi-part file's own name doesn't matter",
      XArchiveImport.parseArray(Data("window.YTD.like.part17 = [{\"like\":{}},{\"like\":{}}]".utf8))?.count == 2)
check("not an archive file → nil",
      XArchiveImport.parseArray(Data("hello".utf8)) == nil)
check("empty → nil", XArchiveImport.parseArray(Data()) == nil)

print("clean — t.co expansion and the entity decode")
let entities: [String: Any] = ["urls": [["url": "https://t.co/abc",
                                         "expanded_url": "https://example.com/real-page"]]]
check("t.co is swapped for the real destination",
      XArchiveImport.clean("read this https://t.co/abc", entities: entities)
        == "read this https://example.com/real-page")
check("&amp; is decoded",
      XArchiveImport.clean("Q&amp;A tonight", entities: nil) == "Q&A tonight")
check("a link with no expansion is left, not dropped",
      XArchiveImport.clean("see https://t.co/zzz", entities: entities) == "see https://t.co/zzz")
check("whitespace is trimmed", XArchiveImport.clean("  hi  ", entities: nil) == "hi")
check("empty stays empty", XArchiveImport.clean("", entities: nil) == "")

print("identifier — a snowflake is past Double's exact range")
check("id_str is preferred",
      XArchiveImport.identifier(["id_str": "2044919377544261979", "id": 1]) == "2044919377544261979")
check("a string id is read when id_str is absent",
      XArchiveImport.identifier(["id": "123456789012345678"]) == "123456789012345678")
check("no id at all → nil", XArchiveImport.identifier(["full_text": "hi"]) == nil)

print("created — created_at, then the id")
check("X's own date format parses",
      iso(XArchiveImport.created(["created_at": "Wed Mar 21 20:50:14 +0000 2006"], id: "20")) == "2006-03-21")
check("a missing created_at falls back to the id",
      iso(XArchiveImport.created([:], id: "2044919377544261979")) == "2026-04-16")
check("neither → nil", XArchiveImport.created([:], id: "20") == nil)

// --- 2026-08-05: the searchability pass ------------------------------------

print("sourceFilter — a source name is a filter, not a search term")
let vocab = ["X", "Instagram", "Apple Health", "Apple Music", "Files", "Day One"]
func named(_ q: String) -> String? { Retriever.sourceFilter(in: q, sources: vocab)?.source }
// The reported failure, exactly as typed.
check("\"can you search my X stuff\" names X", named("can you search my X stuff") == "X")
check("a lone source name resolves", named("X") == "X")
check("case doesn't matter", named("what's in my instagram?") == "Instagram")
check("a source with real terms still resolves",
      named("what did I post about burnout on X") == "X")
// Word boundaries: the whole reason this isn't `contains`.
check("a substring is NOT a match", named("my profiles page") == nil)
check("a word ending in the name is NOT a match", named("send me the taxfiles") == nil)
check("punctuation is a boundary", named("what's new in X?") == "X")
// Longest-first: two catalog names share a word.
check("the two-word name wins over its own first word",
      named("how's my Apple Health looking") == "Apple Health")
check("its sibling is not confused for it",
      named("what's on Apple Music") == "Apple Music")
check("an unnamed query resolves nothing", named("what did I save about climate") == nil)
check("the matched WORDS are returned so the caller can strip them",
      Retriever.sourceFilter(in: "my apple health", sources: vocab)?.words == ["apple", "health"])

print("handle(inAuthorURL:) — the author X names only in a link")
func handle(_ u: String?) -> String? { OEmbed.handle(inAuthorURL: u) }
check("X's own shape yields the handle", handle("https://twitter.com/Interior") == "Interior")
check("the x.com spelling too", handle("https://x.com/paulg") == "paulg")
check("a leading @ is dropped", handle("https://www.youtube.com/@veritasium") == "veritasium")
check("SoundCloud's shape works", handle("https://soundcloud.com/artist") == "artist")
// Two components is the refusal that matters: a channel id is not a handle,
// and printing one beside a face would be a confident wrong answer.
check("a YouTube channel id is refused", handle("https://www.youtube.com/channel/UCabc123") == nil)
check("a /user/ path is refused", handle("https://www.youtube.com/user/Name") == nil)
check("a bare host names nobody", handle("https://x.com") == nil)
check("nil in, nil out", handle(nil) == nil)
// The value reaches the room's own chrome, so a hostile answer must not.
check("a hostile handle is refused",
      handle("https://x.com/" + String(repeating: "a", count: 40)) == nil)
check("markup in a handle is refused", handle("https://x.com/%3Cscript%3E") == nil)

print("the reply lead — §303's clamp ruling as a test")
// The bug: `titleLine` cuts at 80 characters, so a TRAILING recipient is what
// the cut eats. A reply of ordinary length lost the one word that made it
// findable, and the room showed no recipient on most of its replies.
let longReply = "I think the thing people keep missing about this is that it was never really about the money at all"
let leads = IngestSupport.titleLine("To @someone · \(longReply)")
let trails = IngestSupport.titleLine("\(longReply) — to @someone")
check("the recipient SURVIVES when it leads", leads.contains("@someone"))
check("the recipient is EATEN when it trails", !trails.contains("@someone"))
check("a plain post is untouched",
      IngestSupport.titleLine("just shipped it") == "just shipped it")

print("DateQuery — a year is a filter (an archive spans fifteen of them)")
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(secondsFromGMT: 0)!
let now2026 = cal.date(from: DateComponents(year: 2026, month: 8, day: 5))!
func range(_ q: String) -> ClosedRange<Date>? {
    DateQuery.match(in: q, now: now2026, calendar: cal)?.range
}
func inRange(_ q: String, _ y: Int, _ m: Int, _ d: Int) -> Bool {
    guard let r = range(q), let date = cal.date(from: DateComponents(year: y, month: m, day: d))
    else { return false }
    return r.contains(date)
}
check("a bare year scopes to that year", inRange("2019", 2019, 6, 1))
check("…and excludes its neighbours", !inRange("2019", 2020, 1, 1) && !inRange("2019", 2018, 12, 31))
check("\"in 2019\" reads the same", inRange("what did I post in 2019", 2019, 3, 3))
check("\"before 2020\" excludes 2020", inRange("before 2020", 2019, 12, 31) && !inRange("before 2020", 2020, 1, 1))
check("\"since 2021\" INCLUDES 2021", inRange("since 2021", 2021, 1, 1))
check("\"after 2015\" EXCLUDES 2015", !inRange("after 2015", 2015, 6, 1) && inRange("after 2015", 2016, 1, 1))
check("a span is inclusive at both ends",
      inRange("between 2015 and 2018", 2015, 1, 1) && inRange("between 2015 and 2018", 2018, 12, 31))
check("…and excludes outside it", !inRange("between 2015 and 2018", 2019, 1, 1))
// The guard that keeps an ordinary number from emptying an answer.
check("a number that isn't a plausible year is not a date", range("top 3000 things") == nil)
check("a three-digit number is not a year", range("all 999 of them") == nil)
check("a digit run inside an id is not a year", range("order 1234567890") == nil)
// Relative phrases still win — they're more specific and came first.
check("\"today\" still beats a stray year", range("what landed today")! .contains(now2026))
check("the year's WORDS are returned for stripping",
      DateQuery.match(in: "in 2019", now: now2026, calendar: cal)?.words.contains("2019") == true)

print("facetFilter — a half of a room, not a subject in it")
check("\"my replies\" names the Reply tag", Retriever.facetFilter(in: "my replies")?.tag == "Reply")
check("singular too", Retriever.facetFilter(in: "every reply I sent")?.tag == "Reply")
check("\"what I liked\" names Liked", Retriever.facetFilter(in: "what i liked on x")?.tag == "Liked")
check("\"my own posts\" names Post", Retriever.facetFilter(in: "just my own posts")?.tag == "Post")
check("\"gone\" is a facet — the read X can't answer",
      Retriever.facetFilter(in: "what's gone")?.tag == "Gone")
check("threads are a facet", Retriever.facetFilter(in: "my threads")?.tag == "Thread")
check("an ordinary subject names no facet",
      Retriever.facetFilter(in: "what did I say about climate") == nil)
check("a word CONTAINING a facet is not one",
      Retriever.facetFilter(in: "postal codes") == nil)

print("threadTexts — a self-reply chain, recognised without knowing whose archive this is")
func d(_ day: Int) -> Date { cal.date(from: DateComponents(year: 2020, month: 1, day: day))! }
// A three-post thread, one reply to a STRANGER (its parent is not in the file),
// and one standalone post.
let chain: [(id: String, parent: String?, text: String, date: Date)] = [
    ("1", nil,        "first",     d(1)),
    ("2", "1",        "second",    d(2)),
    ("3", "2",        "third",     d(3)),
    ("9", "999",      "to a stranger", d(4)),
    ("10", nil,       "standalone", d(5)),
]
let threads = XThreads.threadTexts(chain)
check("the head carries the whole chain", threads["1"]?.text == "first\n\nsecond\n\nthird")
check("…and its length", threads["1"]?.count == 3)
check("a continuation is NOT itself a head", threads["2"] == nil)
check("a reply to somebody else is not a thread", threads["9"] == nil)
check("a standalone post is not a thread", threads["10"] == nil)
// A mutual-parent pair has no HEAD (every node has a parent in the file), so
// it yields nothing — which is also why the `seen` set can never fire from a
// head, and why `threadCap` is the real bound. Asserted for what it actually
// proves: a malformed pair produces no thread rather than a wrong one.
let cycle: [(id: String, parent: String?, text: String, date: Date)] =
    [("a", "b", "x", d(1)), ("b", "a", "y", d(2))]
check("a mutual-parent pair yields no thread", XThreads.threadTexts(cycle).isEmpty)
// The bound that DOES stop a long walk. A 200-post chain is clamped.
var long: [(id: String, parent: String?, text: String, date: Date)] = []
for i in 0..<200 {
    long.append((String(i), i == 0 ? nil : String(i - 1), "p\(i)", d(1)))
}
check("a very long chain is clamped, not walked forever",
      XThreads.threadTexts(long)["0"]?.count == XThreads.threadCap)

print("metric / parentIdentifier — the archive's own spellings")
check("a count stored as a string reads", XThreads.metric(["favorite_count": "42"], "favorite_count") == 42)
check("a count stored as a number reads", XThreads.metric(["retweet_count": 7], "retweet_count") == 7)
// The distinction the leaderboard rests on: absent is not zero.
check("an absent count is nil, NOT zero", XThreads.metric([:], "favorite_count") == nil)
check("a parent id prefers the _str form",
      XThreads.parentIdentifier(["in_reply_to_status_id_str": "123",
                                 "in_reply_to_status_id": 1]) == "123")
check("no parent → nil", XThreads.parentIdentifier(["full_text": "hi"]) == nil)

print("prose / hashtags — what the topic map is allowed to read (2026-08-06)")
// THE BUG, as a test. A post with a picture keeps the picture's own shortlink,
// and `t.co` cleared every guard the term reader had: four characters, three
// letters, no stoplist entry, and it recurs across thousands of rows.
let withMedia = "shipping the new room today https://t.co/aB3xY9"
check("a media shortlink never reaches the tagger",
      !ScreenshotTopics.prose(of: withMedia).lowercased().contains("t.co"))
check("…and the sentence around it survives",
      ScreenshotTopics.prose(of: withMedia).contains("shipping the new room today"))
// A quote-tweet's expansion is a real URL and just as wrong a topic: nobody
// posts ABOUT twitter.com.
check("a quote-tweet expansion is stripped",
      !ScreenshotTopics.prose(of: "this is exactly right https://twitter.com/a/status/1")
          .contains("twitter"))
// A bare host with no scheme — what an expanded link often looks like after
// `clean`, and what the `\S*` tail on `domainPattern` exists for.
let bareHost = ScreenshotTopics.prose(of: "read this github.com/apple/swift/pull/1 tonight")
check("a bare host goes, and its path goes with it",
      !bareHost.contains("github") && !bareHost.contains("apple"))
check("…and the words on either side stay",
      bareHost.contains("read this") && bareHost.contains("tonight"))
// The reply prefix. `full_text` opens with the handles a reply answers, and
// NLTagger reads those as PEOPLE — which turned a room of replies into a map
// of the people replied TO, filed under "What you post about".
let reply = "@jack @dhh the tradeoff is latency, not throughput"
check("a reply's addressing prefix never reaches the tagger",
      !ScreenshotTopics.prose(of: reply).contains("jack")
          && !ScreenshotTopics.prose(of: reply).contains("dhh"))
check("…and its actual argument does",
      ScreenshotTopics.prose(of: reply).contains("latency"))
// A post that is nothing but a link has nothing to say. Empty, not a hostname.
check("a link-only post reads as no words at all",
      ScreenshotTopics.prose(of: "https://t.co/aB3xY9").isEmpty)
check("an ordinary sentence is untouched",
      ScreenshotTopics.prose(of: "Portland in October is underrated")
          == "Portland in October is underrated")

// Hashtags — the one place somebody states their own topic outright, and the
// signal that replaces the domains this room no longer counts.
check("a hashtag is a topic", ScreenshotTopics.hashtags(in: "counting down to #WWDC") == ["WWDC"])
check("the mark is dropped so it merges with a plain mention",
      ScreenshotTopics.hashtags(in: "#Swift and Swift are one subject") == ["Swift"])
check("two spellings are one topic",
      ScreenshotTopics.hashtags(in: "#swift then #Swift").count == 1)
// Three letters, matching `normalize` — else "#AI" and "#UK" become cells that
// say nothing and outrank real ones by sheer frequency.
check("a two-letter tag is not a topic", ScreenshotTopics.hashtags(in: "shipping #ai today").isEmpty)
// A URL fragment is not a hashtag, which is why the match refuses a word
// character before the mark.
check("a URL fragment is not a hashtag",
      ScreenshotTopics.hashtags(in: "see example.com/guide#installing").isEmpty)

print("")
if failures > 0 { print("x-selftest: ✗ \(failures) assertion(s) failed"); exit(1) }
print("x-selftest: OK — every assertion passed against the shipped source.")
SWIFT

if ! swiftc -O -o "$TMP/x-selftest" "$TMP/extracted.swift" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ harness failed to compile against the shipped source"
  grep -E 'error:' "$TMP/build.log" | head -20
  exit 1
fi
"$TMP/x-selftest"
