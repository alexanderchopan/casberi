#!/bin/zsh
# Casberi X self-test — verifies the SHIPPED pure logic behind the X room
# (prd §280, 2026-08-02):
#
#   Casberi/Casberi/Model/OEmbed.swift
#     — blockquoteText   (the words lifted out of an X embed, the ONLY reason
#                         an X link gets a face at all)
#   plus the X room's rendering, the person room, the ask's source and facet
#   filters and the topic reader.
#
# The archive importer (`XArchiveImport`, `XArchiveAccount`) is DELETED
# (prd §1579), and its guards and assertions went with it; what stays is what
# the live seat and the rooms still read.
#
# WHY A HARNESS AND NOT A SIM CHECK. Every failure mode here is a SILENT WRONG
# ANSWER rather than a crash: a post indexed as "Q&amp;A", a room whose map
# names `t.co`. All of those render and look plausible. The only way to know
# they're right is to feed them inputs whose answers are known.
#
# The files are far too entangled to compile as shipped (SwiftData models, a
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
SUPPORT="Casberi/Casberi/Model/IngestSupport.swift"
for f in "$OEMBED" "$SUPPORT"; do
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
grep -q '"X"' Casberi/Shared/Thing.swift \
  || { echo "✗ X is not a bulk-import source — its rows would flood All"; exit 1; }

# --- 2026-08-18, prd §396: the enrichment pass ------------------------------
# Every one of these is a wiring fact the compiled functions above cannot
# prove, and every one of them fails INVISIBLY — a room that renders perfectly
# while a category never landed, a video that tiles as a photograph, a thread
# that reads as twelve unrelated rows.
MEDIA="Casberi/Casberi/Model/ImportMedia.swift"
# FeedScreen is split across files (prd §718). Checks read the room as ONE text,
# so a guard can neither fail nor pass because its code moved next door.
FEEDSCREEN_395_DIR="$(mktemp -d)"
FEEDSCREEN_395="$FEEDSCREEN_395_DIR/FeedScreen.swift"
cat Casberi/Casberi/Screens/FeedScreen.swift Casberi/Casberi/Screens/FeedScreen+*.swift > "$FEEDSCREEN_395"
RETRIEVER_395="Casberi/Casberi/Model/Retriever.swift"

# (1) VIDEO. A video post once landed with no pixels at all and fell out of the
# room's grid wearing the placeholder word "Photo"; the archive reader is gone
# (prd §1579), and the shared poster reader and the grid's own test stay.
grep -q 'static func posterFrame' "$MEDIA" \
  || { echo "✗ ImportMedia can no longer read a frame from a video — every video post lands with no pixels"; exit 1; }
grep -qF 'ImportMedia.posterFrame(url: fileURL, folder: folder)' Casberi/Casberi/Model/FilesBridge.swift \
  || { echo "✗ a connected folder no longer shares the one poster reader — two frame grabs drift"; exit 1; }
# Grid membership is `postText == nil`, NOT the tag: `Video` rides captioned
# posts too, and a captioned post is a card whose caption is the post.
grep -qF '&& thing.postText == nil' "$FEEDSCREEN_395" \
  || { echo "✗ the X grid no longer tests for a WORDLESS post — a captioned video would be torn out of its card and tiled"; exit 1; }
grep -q 'VideoMark(size: 22)' Casberi/Casberi/Screens/ShapedRows.swift \
  || { echo "✗ a poster frame in the grid no longer says it is one — a still passing for a photograph"; exit 1; }

# (3) THREADS FOLD. The room folds a self-reply under the post it continues.
grep -qF 'let (roomThings, threadReplies) = foldThreadReplies(uncovered)' "$FEEDSCREEN_395" \
  || { echo "✗ the X room no longer folds its threads — a twelve-post thread reads as twelve rows"; exit 1; }

# (4) THE DOOR BACK TO X.
grep -q 'xPostVerb' Casberi/Casberi/Screens/ThingSheetView.swift \
  || { echo "✗ the sheet no longer offers the post's own link"; exit 1; }

# (5) THE FACETS. `Photo` was stamped from 2026-08-13 and prd §375 claimed in
# as many words that it made "photos I posted" a filter — and it never reached
# the vocabulary, so for five days the tag existed and no sentence could name
# it. That is what this guard exists for.
for tag in Photo Video Access; do
  grep -q "\"$tag\")," "$RETRIEVER_395" \
    || { echo "✗ the $tag facet is not in the ask vocabulary — the tag is stamped and unreachable (§375's own defect)"; exit 1; }
done

# (6) THE PERSON ROOM. A third source set, because it asks a third question:
# not "can this network be reached" but "can the corpus describe a person".
grep -q 'static let personSources' Casberi/Casberi/Model/SocialBridge.swift \
  || { echo "✗ the person-room source set is gone"; exit 1; }
grep -qF 'SocialThread.hasPersonRoom(parts[0])' Casberi/Casberi/Shell/RootShell.swift \
  || { echo "✗ casberi://person/X/<handle> no longer resolves"; exit 1; }
grep -qF 'XPersonSource.compose(room, handle: handle)' Casberi/Casberi/Screens/PersonRoomScreen.swift \
  || { echo "✗ the person room no longer composes X's own head"; exit 1; }
grep -qF 'src == XPersonSource.source' Casberi/Casberi/Screens/PersonRoomScreen.swift \
  || { echo "✗ the person room fetches X by authorHandle again — that answers with the LIKES alone and misses every reply"; exit 1; }
# "Who you reply to" was a ranked board and its rows were the door; §723
# deleted the board from every room, so that door is gone by ruling. The
# person room stays reachable through casberi://person/X/<handle> above.
# `SocialProfileCard` must stay gated on `isSocial`: its one verb is Watch and
# on X that can never succeed — the dead control the honesty law bans.
grep -qF 'private var facesAreDoors: Bool { SocialThread.isSocial(thing.source) }' Casberi/Casberi/Screens/ThingSheetView.swift \
  || { echo "✗ the profile card's gate moved — an X face opening a card whose only verb is impossible is a dead control"; exit 1; }

# (7) 2026-08-18, prd §396a — a post reads as a post.
# `standsAlone` is what decides whether a row keeps a SURFACE
# (`shapedListRow` passes `bare: !standsAlone(thing)`), and `.x` was never in
# it: the room drew post cards merged into a run of bare rows. Both halves are
# guarded, because either alone leaves the room looking wrong in a way no
# other check can see.
# AMENDED 2026-08-26 (prd §489), not deleted — the ruling is unchanged and the
# mechanism under it got stronger. `isXPostRow` is gone because it was one of
# five dialects of one question; `SocialRoom.rowKind` is the single answer now,
# and `standsAlone` is DERIVED from it rather than spelled beside it, so the
# "renderer and surface must read ONE predicate" clause below is enforced by
# construction rather than by these two greps. What still needs guarding is that
# the X room reaches that table at all, and that the table still says WHOLE for
# it — the room is an archive of somebody's own writing and the words are the
# entire content of every row.
grep -qF 'return SocialRoomSource.standsAlone(thing)' "$FEEDSCREEN_395" \
  || { echo "✗ the X room's posts no longer stand alone — a card by anatomy with no card under it"; exit 1; }
grep -qF 'case .social, .x, .telegram, .instagram, .tiktok:' "$FEEDSCREEN_395" \
  || { echo "✗ the X room left the shared row branch — its rows would fall to the generic band (§313's finding, again)"; exit 1; }
grep -qF 'return hasReplies ? .thread(whole: true) : .post(whole: true)' Casberi/Casberi/Model/SocialRoom.swift \
  || { echo "✗ the X room clamps its posts again — the longest tweets are exactly the ones cut, and a folded thread becomes an argument that never reaches its conclusion"; exit 1; }
grep -qF 'PostCard(thing: thing, whole: whole)' "$FEEDSCREEN_395" \
  || { echo "✗ the row no longer draws the table's own words rule"; exit 1; }
grep -qF 'SocialThreadCard(head: thing, replies: kids, whole: whole)' "$FEEDSCREEN_395" \
  || { echo "✗ a folded thread no longer draws the table's own words rule"; exit 1; }
# The ladder itself: whole up to a tweet, an excerpt past it. A bare `nil`
# would hand one long-form post the entire scroll.
grep -qF 'return words.count <= Self.wholeChars ? nil : Self.longformLines' Casberi/Casberi/Screens/ShapedRows.swift \
  || { echo "✗ PostCard's clamp is no longer a ladder — either a tweet is cut or an essay owns the scroll"; exit 1; }
grep -qF 'text.count <= PostCard.wholeChars ? nil : PostCard.longformLines' Casberi/Casberi/Screens/ShapedRows.swift \
  || { echo "✗ the thread card keeps its own copy of how long a tweet is — two cards that can disagree"; exit 1; }
# 600, not 280: `clean` expands t.co back to real URLs, so a 280-char tweet
# carrying links is stored well past 280.
python3 - <<'PYCHK' || exit 1
import re, sys
src = open("Casberi/Casberi/Screens/ShapedRows.swift", encoding="utf-8").read()
m = re.search(r'static let wholeChars = (\d+)', src)
if not m:
    print("✗ PostCard.wholeChars is gone"); sys.exit(1)
if int(m.group(1)) < 400:
    print("✗ PostCard.wholeChars is at or under a bare tweet limit — `clean` expands t.co "
          "back to real URLs, so a real 280-char tweet is stored well past 280 and would "
          "land on the excerpt rung"); sys.exit(1)
PYCHK

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
# 2026-08-06: the repair's done-flag must carry the epoch. Both halves of this
# are invisible at runtime and each one alone makes the other useless — a
# bumped `termsEpoch` reaches nothing on a device that already ran a repair
# under the old key, and an epoch-keyed flag re-arms nothing if the date never
# moves. The morning's own fix shipped with a bare `topics.restamp.<source>`
# and a midnight epoch, so it excluded every row it had itself restamped.
grep -q 'topics.restamp.\\(source).\\(Int(termsEpoch.timeIntervalSince1970))' "$TOPICS" \
  || { echo "✗ the restamp flag no longer carries the epoch — a rules change can never re-arm the repair"; exit 1; }
grep -q 'topicsAt ?? Date.distantPast) < termsEpoch' "$TOPICS" \
  || { echo "✗ restamp no longer selects rows read under the old rules"; exit 1; }
# The noun read itself, at its call site: `subjects` is what makes a writing
# room's map non-empty (proper nouns alone yielded a term for 2 rows in 12),
# and it must stay OFF for a screenshot corpus, where the domain is the answer.
grep -q 'if !includeDomains {' "$TOPICS" \
  || { echo "✗ the noun read is no longer forked on the writing/pixels split"; exit 1; }
# THE GRID IS GONE AND MUST STAY GONE (prd §817, user: "i don't ever want to
# see this. it should just show most recent notification"). This guard is the
# inverse of the one it replaces: "Your X year" was a WHEN card over a room
# that is mostly the live notifications door, so one column of recent weeks lit
# a year of black. A label here is all it takes to bring it back — the registry
# can never decline the slot the way the derived heads do — and what it would
# cover is the newest notice. The room's On This Day rode inside that card and
# went with it, deliberately.
[ -e Casberi/Casberi/Model/FeedHeatmap.swift ] \
  && { echo "✗ the year-heatmap registry is back (prd §817, §832) — the room leads with a year grid instead of the newest notification"; exit 1; }
grep -qF '"X":         Facts(foldsThreads: true,  hasRoster: false, leadsWithNewest: true)' Casberi/Casberi/Model/SocialRoom.swift \
  || { echo "✗ X no longer leads with its newest thing (SocialRoom.leadsWithNewest, §821)"; exit 1; }
grep -q 'connected("x")' Casberi/Casberi/Model/BridgeRefresh.swift \
  || { echo "✗ X does no foreground work — topics stop draining and authors are never fetched"; exit 1; }
grep -q '"pbs.twimg.com"' Casberi/Casberi/Model/NetworkReach.swift \
  || { echo "✗ the avatar CDN is not declared — the privacy screen is wrong and this is a ship gate"; exit 1; }

# --- 2026-08-06: the room reads as a room -----------------------------------
# The reported symptom was two things at once: "just a long list" and "the
# treemap seems incorrect". Both were wiring, and both failed invisibly — a
# BandRow renders perfectly over a room of prose, and a treemap of `t.co`
# renders perfectly over anybody's writing. Each guard below is the specific
# line whose absence brings one of them back.
# FeedScreen is split across files (prd §718). Checks read the room as ONE text,
# so a guard can neither fail nor pass because its code moved next door.
FEEDSCREEN_DIR="$(mktemp -d -t feedscreen)"
FEEDSCREEN="$FEEDSCREEN_DIR/FeedScreen.swift"
cat Casberi/Casberi/Screens/FeedScreen.swift Casberi/Casberi/Screens/FeedScreen+*.swift > "$FEEDSCREEN"
grep -q 'case "X":                   self = .x' "$FEEDSCREEN" \
  || { echo "✗ X has no room shape again — it falls to .plain and the room is a wall of 80-char BandRows"; exit 1; }
# …and the shape must still hand the room's newest thing to the cover (prd
# §817). Read off the `.x` case alone, on a comment-stripped copy: the same
# ternary is spelled in the Instagram and Files cases beside it, so a file-wide
# grep would pass with this branch's cover deleted.
X_CASE=$(python3 - "$FEEDSCREEN" <<'XCASE'
import re, sys
src = re.sub(r'//.*$', '', open(sys.argv[1]).read(), flags=re.M)
cut = src[src.find("\n        case .x:"):]
print(cut[:cut.find("\n        case .instagram:")])
XCASE
)
case "$X_CASE" in
  *ledeThingID*|*newestLead\(*) ;;
  *) echo "✗ the X room no longer covers its newest thing (prd §817) — with the year"; \
     echo "  grid deleted, nothing else leads this room."; exit 1;;
esac
# AMENDED 2026-08-26 (prd §489): the five post rooms draw through one call, so
# the words rule is the table's (`whole:`) rather than four literal call sites.
# The ruling is unchanged — something must still render a post as a post.
grep -qF 'PostCard(thing: thing, whole: whole)' "$FEEDSCREEN" \
  || { echo "✗ nothing renders a post as a post"; exit 1; }
# An IMPORT has no media URL to give — `ImportMedia` decodes the archive's own
# file to bytes on the row, inside the folder grant. Without a stored-bytes
# branch the card draws none of them: pixels in the store and none on screen,
# which is §283's Files bug in a new room.
# RE-SPELLED twice: §626 moved the decode behind `StoredPixels`, and §658
# made it `probe` + `StoredPicture` (decoded off main). The old spelling kept
# passing on PhotoWell's load function — a guard satisfied by the wrong line,
# the fix-recorded-once class — so this names the PostCard branch itself.
grep -q '} else if let stored = StoredPixels.probe(thing) {' Casberi/Casberi/Screens/ShapedRows.swift \
  || { echo "✗ PostCard can't draw a picture the app already holds — every imported post loses its media"; exit 1; }
# The other half of the same fix: a hostname is not a subject in a room of
# writing. If X's TopicSource says otherwise, every link a person shared reads
# as what they wrote about.
grep -q 'case "X":         return TopicSource(kinds: \[.note\], needsOCR: false, includeDomains: false)' "$TOPICS" \
  || { echo "✗ X counts domains as topics again — the map goes back to naming hosts"; exit 1; }
# Anchored on the fork being PASSED, not on the call shape that passes it. It
# read `terms(in: thing.content, includeDomains: spec.includeDomains)` until the
# sweep moved its extraction off the main actor and behind a batched
# `extract(_:includeDomains:)` — at which point the guard matched nothing and
# `verify.sh` went red while the behaviour it protects was perfectly intact.
# A drift guard has to name the invariant, not the line it happened to live on.
grep -q 'includeDomains: spec.includeDomains' "$TOPICS" \
  || { echo "✗ the sweep no longer passes the writing/pixels fork — every room reads domains again"; exit 1; }
# The repair. Without it the fix reaches only rows imported AFTER it, which for
# a bulk import room — where everything landed on one afternoon — is nothing.
grep -q 'private static func restamp' "$TOPICS" \
  || { echo "✗ no re-read for rows stamped under the old term rules — an existing room keeps its old map forever"; exit 1; }
# Matched on X's MEMBERSHIP rather than on the whole literal (2026-08-18):
# `contextSources` gains members — Instagram joined it the same afternoon this
# guard was written — and a guard pinned to the exact set fires every time
# somebody else's room joins, which is a guard that cries wolf about a change
# it has no opinion on. What it must prove is that X is still in there.
grep -qE 'static let contextSources.*union\(\[.*"X".*\]\)' Casberi/Casberi/Model/SocialBridge.swift \
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
# These are checked HERE rather than in new scripts because they are one
# ruling with several instances, and a rule split across files drifts. X's and
# Instagram's importers are deleted (prd §1579); TikTok and Snapchat remain.
TT="Casberi/Casberi/Model/TikTokImport.swift"
SC="Casberi/Casberi/Model/SnapchatImport.swift"
python3 - "$TT" "$SC" <<'PY' || exit 1
import re, sys
tt, sc = sys.argv[1:3]
# (file, constant, floor) — floors, not exact values: the numbers should stay
# free to move, but never back under the ones that truncated a real export.
for path, name, floor in (
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
for path in (tt, sc):
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
# TikTok's topic map is DELETED (prd §817): the room leads with its newest
# thing. The two-kind rule survives where the terms are still read — the topic
# heal, which feeds the Today brief's cluster map.
! grep -qE '^\s*case "TikTok":' Casberi/Casberi/Model/FeedInsight.swift \
  || { echo "✗ TikTok has a topic map again — the room leads with its newest thing (§817)"; exit 1; }
grep -q 'case "TikTok":    return TopicSource(kinds: \[.link, .note\]' Casberi/Casberi/Model/ScreenshotTopics.swift \
  || { echo "✗ TikTok's topic heal is back to one kind — it would read half the writing"; exit 1; }

# --- 2026-08-05: prd §310, the upkeep pass ---------------------------------
grep -q 'await ImportCommit.commit' "$TT" \
  || { echo "✗ TikTok lands in one transaction again"; exit 1; }
grep -q 'await Task.yield()' Casberi/Casberi/Model/ImportCommit.swift \
  || { echo "✗ ImportCommit no longer yields — chunking without a yield buys nothing at all"; exit 1; }
# The receipt must land AFTER the rows, or a partial import is crowned with a
# total it never reached.
python3 - "$TT" <<'PYEOF' || exit 1
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
# Removal is scoped to imports, never a live bridge.
grep -q 'Corpus.bulkImportSources.contains(source) else { return 0 }' Casberi/Casberi/Model/ImportRemoval.swift \
  || { echo "✗ per-source removal is no longer scoped to imports — a live bridge's rows are not a decision to undo"; exit 1; }

TMP=$(mktemp -d /tmp/x-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- 2026-08-13 (prd §375): the enrichment pass -----------------------------
# The room's half of it (the importer's half went with it, prd §1579): each
# fails INVISIBLY, leaving a room that renders perfectly and says less.
grep -q 'thing.tags.contains("Photo")' "$FEEDSCREEN" \
  || { echo "✗ the X grid no longer reads the tag (matching the localized title 'Photo' would empty the grid outside English)"; exit 1; }
grep -q 'isTile: Self.isXPhotoTile, tileShape: .square' "$FEEDSCREEN" \
  || { echo "✗ the X room lost its picture half — the wordless picture posts no longer tile under their day (prd §910)"; exit 1; }
grep -q 'if !words.isEmpty' Casberi/Casberi/Screens/SocialReceptionCard.swift \
  || { echo "✗ ReplyingToCard no longer draws the parent's words — the pass would fill a field nothing renders"; exit 1; }
# (4) THE BOARDS ARE DELETED (prd §723). X's room used to pick between "Who you
# reply to" and "Whose posts you like"; the ranked board is gone from every
# room, so both checks went with it. What the archive stamps is still checked
# below — `parent.handle` is read by the person room and the handle-scoped ask,
# not only by a board.
grep -q 'thing.parent?.handle' Casberi/Casberi/Model/XPersonSource.swift \
  || { echo "✗ the person room no longer reads the stored card (parsing the localized 'To @' title back apart is the failure it exists to avoid)"; exit 1; }

# --- extract the shipped functions -----------------------------------------
python3 - "$OEMBED" "$SUPPORT" "$TMP/extracted.swift" "$TOPICS" <<'PY'
import re, sys
oembed, support, out, topics = sys.argv[1:5]

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

def grabbracket(path, signature):
    """A multi-line `static let X: Set<String> = [ … ]`. Neither `grabvar` (it
    brace-matches from the next `{`, which for a bracket literal is the
    following FUNCTION's body) nor `grabline` (which stops at the first
    newline and hands the compiler an unterminated array) can read one."""
    src = open(path).read()
    i = src.find(signature)
    if i < 0:
        sys.exit(f"✗ extraction failed: {signature!r} not found in {path}")
    start = src.rfind("\n", 0, i) + 1
    j = src.index("[", i)
    depth, k = 0, j
    while k < len(src):
        if src[k] == "[": depth += 1
        elif src[k] == "]":
            depth -= 1
            if depth == 0: break
        k += 1
    return src[start:k+1].replace("private ", "")

def wholefile(path):
    """A file that is Foundation-only by construction, compiled AS SHIPPED
    rather than by extraction — the strongest form this harness has."""
    src = open(path).read()
    return "\n".join(l for l in src.splitlines() if not l.startswith("import "))

pieces = [
    "import Foundation",
    # `subjects(in:)` reads part of speech, so the topics half of this harness
    # links NaturalLanguage now. Everything else here stays Foundation-only.
    "import NaturalLanguage\n",
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
    # `facetFilter`'s vocabulary moved out of its body on 2026-08-14 so the
    # themes treemap could DERIVE its exclusion from it rather than keep a
    # second copy (`HomeComposition.mechanicalTags`). The table has to come
    # across with the function or nothing here compiles — and `facetTags` comes
    # with it, since it is the half the map actually reads.
    grabvar(retriever, "static let facetTable"),
    grabline(retriever, "static let facetTags"),
    grab(retriever, "static func facetFilter"),
    "}\n",
    # DateQuery is Foundation-only, so it compiles exactly as it ships.
    wholefile("Casberi/Casberi/Model/DateQuery.swift"),
    # Your years with one person (2026-08-18, prd §396). Same reason as
    # `XRoom`: every failure in this card renders as a perfectly good-looking
    # one, and no real archive has ever been read on this host.
    wholefile("Casberi/Casberi/Model/XPerson.swift"),
    # The treemap's reading surface for a room of WRITING (2026-08-06). Both
    # are Foundation-only — `terms(in:)` itself needs NLTagger and a model
    # whose output is nobody's contract, so what is asserted here is the part
    # that has a right answer: which spans reach the tagger at all. That is
    # exactly where the `t.co` cell came from.
    "enum ScreenshotTopics {",
    grabline(topics, "static let domainPattern"),
    grab(topics, "static func hashtags"),
    grab(topics, "static func prose"),
    # `subjects(in:)` DOES need NLTagger, unlike everything above it, and it is
    # extracted anyway (2026-08-06) because it is now what the writing map is
    # made of. What is asserted about it is only ever a contract of OUR code —
    # a generic noun never survives, a returned label is always a trim of a
    # word the person really typed — never a claim about which words Apple's
    # tagger happens to pick, which is nobody's contract and would rot.
    grab(topics, "static func terms"),
    grab(topics, "static func domains"),
    grab(topics, "static func subjects"),
    grab(topics, "static func normalize"),
    grabbracket(topics, "static let stop:"),
    grabbracket(topics, "static let genericNouns:"),
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

print("subjects — the words a writing room is actually about (2026-08-06)")
// WHY THIS EXISTS. Stripping domains fixed the `t.co` cell and left the
// tagger reading for PROPER nouns alone, which over ordinary sentences names
// almost nothing: a sample of tech posts yielded a term for 2 rows in 12, and
// `FeedInsight.topicMap` needs six carrying rows before it draws at all. A
// wrong map became no map. This is the read that makes the room say something.
let ordinary = "the retrieval layer rewrite paid off, search is instant now"
check("an ordinary sentence with no proper noun still has subjects",
      !ScreenshotTopics.subjects(in: ordinary).isEmpty)
check("…and the whole term reader returns them for a writing corpus",
      !ScreenshotTopics.terms(in: ordinary, includeDomains: false).isEmpty)
// The pixels fork must be BYTE-IDENTICAL to what it was — Photos and Files
// are not broken and this change must not reach them.
check("a screenshot's read is unchanged: domains, and no nouns",
      ScreenshotTopics.terms(in: "Order confirmed amazon.com delivery", includeDomains: true)
          == ["amazon.com"])
// THE HONESTY RULE, as a test, and the one assertion that is a contract of our
// code rather than of Apple's tagger: every label is a trim of a word the
// person really typed. The lemma is taken only when it is a PREFIX of the
// surface form, so "systems" may become "system" and "people" can never
// become "person".
// "analyses" is deliberate: its lemma is "analysis", which is NOT a prefix of
// it, so this sentence is the one that can tell a guarded fold from an
// unguarded one. A regular plural passes either way and proves nothing.
let sentence = "the analyses of design systems were mostly wrong"
let words = sentence.lowercased().split { !$0.isLetter }.map(String.init)
check("every subject is a prefix of a word that was actually written",
      ScreenshotTopics.subjects(in: sentence).allSatisfy { term in
          words.contains { $0.hasPrefix(term.lowercased()) } })
// Generic nouns are the whole reason a noun read is safe: a term wins a cell
// by RECURRING, and "thing" recurs in everything. Unfiltered, a map of
// somebody's writing is a map of English.
check("the nouns English builds sentences out of are not subjects",
      ScreenshotTopics.subjects(in: "the thing about the way people take time").isEmpty)
check("…and they are gone from the full reader too",
      ScreenshotTopics.terms(in: "someone said something about that thing",
                             includeDomains: false).isEmpty)
// A cell needs to RECUR, so a plural and its singular have to land together or
// each looks too small to draw.
// In a SENTENCE, not bare: a lone word carries no part of speech for the
// tagger to read, so `subjects(in: "dashboards")` is legitimately empty and an
// assertion built that way tests the tagger's context window, not our fold.
let folded = ScreenshotTopics.subjects(in: "the dashboards are slow")
check("an inflected noun folds to the form its singular shares",
      folded == ["dashboard"])

print("")
print("XPerson — your years with one person")

func met(_ years: [(Int, XPerson.Sighting.Kind, Int)]) -> [XPerson.Sighting] {
    years.flatMap { year, kind, n in
        (0..<n).map { _ in XPerson.Sighting(year: year, kind: kind) }
    }
}
check("one or two sightings are not a relationship",
      XPerson.compose(met([(2019, .reply, 2)])) == nil)
let friend = XPerson.compose(met([(2013, .reply, 12), (2016, .reply, 40),
                                  (2016, .liked, 5), (2019, .mention, 3)]))!
check("the three memberships are counted apart, never summed into one",
      friend.replies == 52 && friend.liked == 5 && friend.mentions == 3)
check("the span runs first year to last, silent years included",
      friend.years.map(\.year) == Array(2013...2019))
check("…and the silent ones are counted so the card can say so", friend.silent == 4)
check("the busiest year is the one with the most of anything", friend.busiest.year == 2016)
// TOTAL ordering, the `XRoom` lesson: two equally busy years must not race, or
// the headline renames itself between two identical opens.
check("a tie goes to the earlier year, deterministically",
      XPerson.compose(met([(2019, .reply, 9), (2021, .reply, 9)]))!.busiest.year == 2019
      && XPerson.compose(met([(2021, .reply, 9), (2019, .reply, 9)]))!.busiest.year == 2019)
// The headline names WHICH count it reports — folding likes into replies would
// make reading look like talking.
check("the biggest membership leads, and says which it is",
      XPerson.headline(friend, handle: "foo").contains("replied"))
check("a person you only ever liked says exactly that",
      XPerson.headline(XPerson.compose(met([(2019, .liked, 8)]))!, handle: "foo")
        .contains("liked"))
check("a person you only ever named says that instead",
      XPerson.headline(XPerson.compose(met([(2019, .mention, 8)]))!, handle: "foo")
        .contains("mentioned"))
// A YEAR IS NOT A QUANTITY. `String(localized: "\(year)")` groups an Int with
// the locale's separator — the defect `XRoom`'s harness caught rendering
// "2,019 was your loudest year", in the largest type on the card.
check("years print as four digits, never grouped",
      XPerson.plainYear(2019) == "2019" && !XPerson.note(friend).contains(","))
check("the note names both ends of the span", XPerson.note(friend).contains("2013")
      && XPerson.note(friend).contains("2019"))
check("a single-year relationship states one year, not a range",
      XPerson.note(XPerson.compose(met([(2019, .reply, 5)]))!) == "2019")
check("a bar is a share of the busiest year, and never divides by nothing",
      XPerson.share(10, of: 20) == 0.5 && XPerson.share(5, of: 0) == 0)
check("a share can't exceed the axis", XPerson.share(40, of: 30) == 1)
check("the axis is never zero, so no bar is ever a NaN width",
      XPerson.peak(XPerson.compose(met([(2019, .reply, 3)]))!) >= 1)

// The mention scan. Both bounds are load-bearing and each has its own way of
// being wrong: no leading @ merges a word into a handle, no trailing boundary
// merges two people into one relationship — and the card renders perfectly
// either way.
check("a plain mention is found", XPerson.mentions("thanks @foo!", handle: "foo"))
check("…case-insensitively, and with the @ optional in the query",
      XPerson.mentions("THANKS @FOO", handle: "@Foo"))
check("a longer handle does not match the shorter one",
      !XPerson.mentions("hey @foobar", handle: "foo"))
check("…and the shorter one does not match inside the longer",
      !XPerson.mentions("hey @foo_bar", handle: "foo"))
check("a bare word is not a mention", !XPerson.mentions("the foo of it", handle: "foo"))
check("an email address is not a mention", !XPerson.mentions("me@foo", handle: "foo"))
check("a handle at the very end of a post still counts",
      XPerson.mentions("cc @foo", handle: "foo"))
check("a handle followed by punctuation still counts",
      XPerson.mentions("@foo, hi", handle: "foo") && XPerson.mentions("(@foo)", handle: "foo"))
check("a dot ends a handle, the way X reads one",
      XPerson.mentions("see @foo.com", handle: "foo"))
check("an empty handle matches nothing at all",
      !XPerson.mentions("@ hello", handle: "") && !XPerson.mentions("anything", handle: "@"))

print("")
if failures > 0 { print("x-selftest: ✗ \(failures) assertion(s) failed"); exit(1) }
print("x-selftest: OK — every assertion passed against the shipped source.")
SWIFT

# `-Onone`, not `-O`: 97% of a pure-logic harness's wall time is the optimizer,
# and it buys nothing an assertion can see. NOT a blanket rule — `-O` can change
# a harness's OBSERVABLE behaviour (a trapping one prints NOTHING under `-O`) —
# so this file was proven equivalent run-for-run by
# `scripts/support/harness-opt-probe.sh` before the swap (2026-09-05, 3.6x faster).
# Re-probe before trusting it again after adding mutations.
if ! swiftc -Onone -o "$TMP/x-selftest" "$TMP/extracted.swift" "Casberi/Casberi/Model/TitleSeam.swift" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ harness failed to compile against the shipped source"
  grep -E 'error:' "$TMP/build.log" | head -20
  exit 1
fi
"$TMP/x-selftest"
