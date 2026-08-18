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

# --- 2026-08-18, prd §396: the enrichment pass ------------------------------
# Every one of these is a wiring fact the compiled functions above cannot
# prove, and every one of them fails INVISIBLY — a room that renders perfectly
# while a category never landed, a video that tiles as a photograph, a thread
# that reads as twelve unrelated rows.
MEDIA="Casberi/Casberi/Model/ImportMedia.swift"
FEEDSCREEN_395="Casberi/Casberi/Screens/FeedScreen.swift"
RETRIEVER_395="Casberi/Casberi/Model/Retriever.swift"

# (1) VIDEO. The whole defect was that `xMediaIndex` indexed mp4s and the
# thumbnail reader could not open one, so a video post landed with no pixels at
# all and fell out of the room's grid wearing the placeholder word "Photo".
grep -q 'static func posterFrame' "$MEDIA" \
  || { echo "✗ ImportMedia can no longer read a frame from a video — every video post lands with no pixels"; exit 1; }
grep -qF 'await posterFrame(url: job.file, folder: folder)' "$MEDIA" \
  || { echo "✗ decode no longer routes a video job to the poster reader — CGImageSource cannot open an mp4"; exit 1; }
grep -qF 'isVideo: media.isVideo' "$XARCH" \
  || { echo "✗ the media job no longer carries which MEDIUM it is"; exit 1; }
grep -qF 'ImportMedia.posterFrame(url: fileURL, folder: folder)' Casberi/Casberi/Model/FilesBridge.swift \
  || { echo "✗ a connected folder no longer shares the one poster reader — two frame grabs drift"; exit 1; }
grep -qF 'tags.append(row.video ? "Video" : "Photo")' "$XARCH" \
  || { echo "✗ a video post is filed as a photo — one facet meaning two media"; exit 1; }
grep -qF 'community_tweet_media' "$MEDIA" \
  || { echo "✗ a Community post's pictures are no longer found — those rows land titled with a t.co shortlink (§375's defect, second file)"; exit 1; }
# Grid membership is `postText == nil`, NOT the tag: `Video` rides captioned
# posts too, and a captioned post is a card whose caption is the post.
grep -qF '&& thing.postText == nil' "$FEEDSCREEN_395" \
  || { echo "✗ the X grid no longer tests for a WORDLESS post — a captioned video would be torn out of its card and tiled"; exit 1; }
grep -q 'VideoMark(size: 22)' Casberi/Casberi/Screens/ShapedRows.swift \
  || { echo "✗ a poster frame in the grid no longer says it is one — a still passing for a photograph"; exit 1; }

# (2) THE ACCOUNT'S OWN RECORD. Three categories, each read from a file nothing
# opened before this pass.
grep -qF 'readSeries("connected-application"' "$XARCH" \
  || { echo "✗ connected-application.js is no longer read — the apps that can post as you are invisible again"; exit 1; }
grep -qF 'readSeries("community-tweet"' "$XARCH" \
  || { echo "✗ community-tweet.js is no longer read — your own writing, not imported"; exit 1; }
grep -qF 'readSeries("screen-name-change"' "$XARCH" \
  || { echo "✗ screen-name-change.js is no longer read"; exit 1; }
grep -qF 'XArchiveAccount.settingsURL' "$XARCH" \
  || { echo "✗ a connected app no longer opens the page that revokes it — a row with nothing to do"; exit 1; }
# `foundAnyCategory` must NOT be set by account.js: it is in every archive and
# in nothing else, so counting it makes "this isn't an X archive" unreachable.
python3 scripts/support/x-run-shape.py "$XARCH" || exit 1

# (3) THREADS FOLD. The parent ref is set for a SELF-reply only, and the room
# is what folds on it — either half alone changes nothing on screen.
grep -qF 'ref: row.parentID.flatMap { textByID[$0] == nil ? nil : "x:tweet:\($0)" }' "$XARCH" \
  || { echo "✗ a self-reply no longer names its parent — the room cannot fold a thread"; exit 1; }
grep -qF 'let (roomThings, threadReplies) = foldThreadReplies(rest)' "$FEEDSCREEN_395" \
  || { echo "✗ the X room no longer folds its threads — a twelve-post thread reads as twelve rows"; exit 1; }

# (4) THE DOOR BACK TO X, and the one that heals rows landed before it existed.
grep -qF 'if let mine { thing.externalLink = permalink(handle: mine, id: row.id) }' "$XARCH" \
  || { echo "✗ your own posts no longer carry a permalink — the room has no door onto the post"; exit 1; }
grep -qF 'XArchiveImport.healLinks(context: context)' Casberi/Casberi/Model/BridgeRefresh.swift \
  || { echo "✗ healLinks never runs — rows imported before today keep no door forever"; exit 1; }
grep -q 'xPostVerb' Casberi/Casberi/Screens/ThingSheetView.swift \
  || { echo "✗ the sheet no longer offers the post's own link"; exit 1; }

# (5) THE FACETS. `Photo` was stamped from 2026-08-13 and prd §375 claimed in
# as many words that it made "photos I posted" a filter — and it never reached
# the vocabulary, so for five days the tag existed and no sentence could name
# it. That is what this guard exists for.
for tag in Photo Video Access Community; do
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
grep -qF 'feedSheet = .person(source: XPersonSource.source' "$FEEDSCREEN_395" \
  || { echo "✗ 'Who you reply to' is no longer a door"; exit 1; }
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
grep -qF 'if shape == .x { return Self.isXPostRow(thing) }' "$FEEDSCREEN_395" \
  || { echo "✗ the X room's posts no longer stand alone — a card by anatomy with no card under it"; exit 1; }
grep -q 'private static func isXPostRow' "$FEEDSCREEN_395" \
  || { echo "✗ the post test is gone — the renderer and the surface must read ONE predicate or they drift"; exit 1; }
grep -qF 'PostCard(thing: thing, whole: true)' "$FEEDSCREEN_395" \
  || { echo "✗ the X room clamps its posts again — the longest tweets are exactly the ones cut"; exit 1; }
grep -qF 'SocialThreadCard(head: thing, replies: kids, whole: true)' "$FEEDSCREEN_395" \
  || { echo "✗ a folded thread clamps each part — an argument that never reaches its conclusion"; exit 1; }
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
# (2026-08-13: the composition moved into `face(reply:text:wordless:)` so a
# re-import could rebuild a repaired title with the same rule. It is compiled
# and asserted below; this guard still has to say the shipped LANDING calls it,
# because the Swift checks can only prove the function is right.)
grep -qF 'return reply.map { "To @\($0) · \(text)" } ?? text' "$XARCH" \
  || { echo "✗ a reply's recipient no longer LEADS its title — titleLine's 80-char clamp eats a trailing one (§303)"; exit 1; }
grep -qF 'face(reply: row.replyTo, text: row.text,' "$XARCH" \
  || { echo "✗ the landing no longer builds its title through face(reply:text:wordless:video:)"; exit 1; }
grep -qF 'wordless: row.wordless, video: row.video)' "$XARCH" \
  || { echo "✗ the landing no longer tells face() which MEDIUM it has — every video post is titled Photo"; exit 1; }
# The avatar, same reasoning: `accountAvatarURL` is compiled and tested below,
# but `landTweets` builds `Thing`s and can't be, so only a text guard can say
# the face reaches a row at all. Three separate facts, each able to fail alone.
grep -qF 'thing.authorAvatarURL = avatar' "$XARCH" \
  || { echo "✗ your own posts no longer carry your avatar — every row falls back to the X logo"; exit 1; }
grep -qF 'let face = accountAvatarURL(under: folder)' "$XARCH" \
  || { echo "✗ the archive's profile.js is no longer read — the avatar is nil for every row"; exit 1; }
grep -qF 'if existingRow.authorAvatarURL == nil, let avatar { existingRow.authorAvatarURL = avatar }' "$XARCH" \
  || { echo "✗ a re-import no longer repairs rows on the dedupe hit — a room imported before the face existed can never get one (the folder is a temporary scoped pick, so no foreground sweep can)"; exit 1; }
# A liked post's author is somebody else and X publishes no face for them, so
# `landLikes` must never be handed this.
grep -q 'landLikes(data, summary' "$XARCH" \
  || { echo "✗ landLikes' call shape changed — check it did not gain the avatar (a stranger's post wearing your face)"; exit 1; }
grep -q '"pbs.twimg.com"' Casberi/Casberi/Model/NetworkReach.swift \
  || { echo "✗ the avatar CDN is not declared — the privacy screen is wrong and this is a ship gate"; exit 1; }
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
grep -q 'await XArchiveImport.healRoom(context: context)' Casberi/Casberi/Model/BridgeRefresh.swift \
  || { echo "✗ rows landed before the room had a shape never gain the fields it draws (and a re-import can't: landTweets skips a seen ref)"; exit 1; }
# What the card DRAWS. `postText` is `PostCard`'s body, `parent` is its
# "Replying to @…" line, `socialContext` is the word that tells your own
# writing from a post you liked.
grep -q 'thing.postText = row.text' "$XARCH" \
  || { echo "✗ a post's full sentence is no longer in the field the card renders"; exit 1; }
grep -qF 'thing.parent = SocialCard(' "$XARCH" \
  || { echo "✗ a reply no longer says who it answers — the card doesn't draw the title's 'To @' lead"; exit 1; }
grep -q 'thing.socialContext = "liked"' "$XARCH" \
  || { echo "✗ a liked post is no longer marked — half the room stops being distinguishable from your own writing"; exit 1; }
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

# --- 2026-08-13 (prd §375): the enrichment pass -----------------------------
# Five changes, each of which fails INVISIBLY — every one of them leaves a room
# that renders perfectly and says less than it knows. The Swift assertions
# below prove the judgement; these prove the shipped app still reaches it.
#
# (1) LONG POSTS. `note-tweet.js` holds the body of every post over 280
# characters; `tweets.js` holds a copy cut mid-sentence. Reading only the
# second is what shipped from 2026-08-02, and a clipped post and a whole one
# are both "1 post" in every count on every screen.
grep -q 'let notes = noteTexts(under: folder)' "$XARCH" \
  || { echo "✗ note-tweet.js is no longer read — every long post lands clipped again"; exit 1; }
grep -qF 'if let long = notes[id], long.count > text.count {' "$XARCH" \
  || { echo "✗ the long body is no longer preferred (or no longer only when LONGER — a wrong join must never be able to shorten a post)"; exit 1; }
grep -q 'notes: notes' "$XARCH" \
  || { echo "✗ the note bodies never reach the landing"; exit 1; }
# (2) PICTURE POSTS. `wordsWithoutMedia` answering empty is the whole signal.
grep -q 'let wordless = wordsWithoutMedia(raw, entities: entities).isEmpty' "$XARCH" \
  || { echo "✗ a wordless post is no longer detected — a photo post lands titled with its own t.co shortlink"; exit 1; }
# 2026-08-18: the index answers with the MEDIUM now, not just membership, so
# the test reads `isVideo != nil` — still "is there a file for this post", and
# still the thing that separates a photograph from an empty row.
grep -q 'let isVideo = media\[id\]' "$XARCH" \
  || { echo "✗ the landing no longer looks the post's own file up — it cannot tell a photo post from an empty row, nor a video from a photo"; exit 1; }
grep -q 'isVideo != nil' "$XARCH" \
  || { echo "✗ the wordless test no longer requires a real picture in the export — an empty row would land as a photograph"; exit 1; }
# 2026-08-18: the tag is the MEDIUM now (`Photo` or `Video`), and grid
# membership moved off it onto `postText == nil` — see the §396 block above.
grep -qF 'if row.wordless { tags.append(row.video ? "Video" : "Photo") }' "$XARCH" \
  || { echo "✗ a wordless media post is no longer tagged with its medium"; exit 1; }
grep -q 'thing.tags.contains("Photo")' "$FEEDSCREEN" \
  || { echo "✗ the X grid no longer reads the tag (matching the localized title 'Photo' would empty the grid outside English)"; exit 1; }
grep -q 'photoGridSection(photoTiles)' "$FEEDSCREEN" \
  || { echo "✗ the X room lost its picture half"; exit 1; }
# (3) REPLY CONTEXT. Two halves: the free one (a self-reply's parent is in the
# same file) and the one that costs a request. Either can be lost alone.
grep -q 'text: parentPreview(row.parentID.flatMap { textByID' "$XARCH" \
  || { echo "✗ a self-reply no longer carries the post it continues — the free half of the context is gone"; exit 1; }
grep -q 'url: row.parentID.map { permalink(handle: replyTo, id: \$0) }' "$XARCH" \
  || { echo "✗ a reply's parent has no permalink — the sheet's door dies and fetchReplyContext has nothing to ask about"; exit 1; }
grep -q 'static func fetchReplyContext' "$XARCH" \
  || { echo "✗ the reply-context pass is gone"; exit 1; }
# A gone parent must lose its DOOR, not gain a tag: "Gone" already means the
# row itself has died (a liked post), and one facet meaning two things is worse
# than no facet. Clearing the url is also what takes the row out of the queue.
grep -q 'card.url = nil' "$XARCH" \
  || { echo "✗ a deleted parent keeps its door (a control that opens nothing) and is re-asked forever"; exit 1; }
grep -q 'parent.text.isEmpty && !(parent.url ?? "").isEmpty' "$XARCH" \
  || { echo "✗ the pending test changed — check it still skips self-replies (already filled) and rows with no permalink"; exit 1; }
grep -q 'if !words.isEmpty' Casberi/Casberi/Screens/SocialReceptionCard.swift \
  || { echo "✗ ReplyingToCard no longer draws the parent's words — the pass would fill a field nothing renders"; exit 1; }
# (4) THE BOARDS. "Whose posts you like" is empty until the face pass runs, so
# the room's only leaderboard could never render for someone who never tapped
# it. The reply board needs nothing but the archive.
grep -q 'case "X":' Casberi/Casberi/Model/FeedInsight.swift \
  || { echo "✗ X has no leaderboard at all"; exit 1; }
grep -q 'return xBoard(things)' Casberi/Casberi/Model/FeedInsight.swift \
  || { echo "✗ X no longer picks between its two boards — the likes board alone is empty until the face pass runs"; exit 1; }
grep -q 'thing.parent?.handle' Casberi/Casberi/Model/FeedInsight.swift \
  || { echo "✗ the reply board no longer reads the stored card (parsing the localized 'To @' title back apart is the failure it exists to avoid)"; exit 1; }
# (5) THE ROOM HEAD. `XRoom` is compiled whole below; these are the three
# wiring facts it can't prove about itself — that it is asked at all, that the
# probe mirrors the chain (`-roomInsightProbe`'s own rule), and that the demo
# check knows about it.
grep -q 'XRoomSource.compose(things: visible).map { .x(\$0) }' "$FEEDSCREEN" \
  || { echo "✗ the X room head is never composed"; exit 1; }
grep -q 'XRoomCard(room: room)' "$FEEDSCREEN" \
  || { echo "✗ nothing draws the X room head"; exit 1; }
grep -q 'note("xHead"' Casberi/Casberi/Shell/ProbeHooks.swift \
  || { echo "✗ -roomInsightProbe doesn't know about the X head — it would report the room as leading with the treemap it displaced"; exit 1; }
grep -q 'xHead             "X"' scripts/verify.sh \
  || { echo "✗ the demo room-head coverage check has no X row — a head that stops composing over the demo goes unnoticed"; exit 1; }
# `RoomFigure`'s chain mirrors `shapedSections`, and this is the first
# per-source head that is a FIGURE rather than a text hero — so without a
# branch there the chip PEEK previews the treemap while the room draws a year
# strip, which that chain's contract calls worse than no preview at all.
# (Lived in `Composer.buildPanel` until prd §386p deleted the agent panel; the
# per-room function survived for the peek, and so does this invariant.)
grep -q 'XRoomSource.compose(things: things), source == XRoomSource.source' Casberi/Casberi/Model/RoomFigure.swift \
  || { echo "✗ the X chip peek no longer mirrors the room's head — it would preview a figure the room doesn't draw"; exit 1; }
# The displacement itself (§349's rule): this card takes the treemap's slot, so
# the year ROWS carrying each year's subject are what keeps it from drawing
# less than what it replaced.
grep -q 'mostly \\(subject)' Casberi/Casberi/Model/XRoom.swift \
  || { echo "✗ the year rows no longer name each year's subject — the head now draws LESS than the treemap it displaces (§349)"; exit 1; }

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
    # …and so is `XRoom` (2026-08-13, prd §375), by design: the room head's
    # whole judgement — which year is loudest, what a year was about, which
    # years are silent — compiled AS SHIPPED. It is the only proof these
    # numbers are right, since no real archive has ever been imported here and
    # every failure in it renders as a perfectly good-looking card.
    wholefile("Casberi/Casberi/Model/XRoom.swift"),
    # The half of the archive that isn't posts (2026-08-18, prd §396) — the
    # connected-app inventory, the account's own beginning, every rename, and
    # BOTH date parsers, which moved here from `XArchiveImport` precisely so
    # they could be compiled as shipped rather than extracted by name.
    wholefile("Casberi/Casberi/Model/XArchiveAccount.swift"),
    # Your years with one person (2026-08-18, prd §396). Same reason as
    # `XRoom`: every failure in this card renders as a perfectly good-looking
    # one, and no real archive has ever been read on this host.
    wholefile("Casberi/Casberi/Model/XPerson.swift"),
    "\nenum XThreads {",
    grab(xarch, "static func threadTexts"),
    grabline(xarch, "static let threadCap"),
    grab(xarch, "static func parentIdentifier"),
    grab(xarch, "static func metric"),
    "}\n",
    "enum XArchiveImport {",
    grab(xarch, "static func snowflakeDate"),
    grab(xarch, "static func parseArray"),
    # The avatar fence (2026-08-06). `accountAvatarURL` is the one reader here
    # that turns a line in somebody's data file into a host the app connects
    # to, so its allowlist is worth a test of its own.
    grab(xarch, "static func accountAvatarURL"),
    grabline(xarch, "static let avatarHost"),
    grab(xarch, "static func readSeries"),
    grab(xarch, "static func read(_ relative"),
    grab(xarch, "static func clean"),
    # The 2026-08-13 split of `clean` (prd §375). `wordsWithoutMedia` is the
    # emptiness test that tells a photo-only post from an empty row, and
    # `expandedText` is the half both of them share — extracted rather than
    # stubbed, because a stub would let this harness pass over a `clean` that
    # no longer expands a t.co link at all.
    grab(xarch, "static func wordsWithoutMedia"),
    grab(xarch, "static func expandedText"),
    grab(xarch, "static func face(reply"),
    grab(xarch, "static func permalink"),
    grab(xarch, "static func parentPreview"),
    grabline(xarch, "static let parentPreviewChars"),
    grab(xarch, "static func noteTarget"),
    grab(xarch, "static func noteEntities"),
    grab(xarch, "static func identifier"),
    grab(xarch, "static func created"),
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

print("your own face, out of the archive (2026-08-06)")
// A real folder with a real `data/profile.js`, because the whole point of this
// reader is what it does with bytes off somebody's disk.
func profileFolder(_ body: String) -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "x-avatar-\(UUID().uuidString)/data")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? ("window.YTD.profile.part0 = " + body).write(
        to: dir.appending(path: "profile.js"), atomically: true, encoding: .utf8)
    return dir.deletingLastPathComponent()
}
func avatar(_ url: String) -> String? {
    XArchiveImport.accountAvatarURL(under: profileFolder(
        #"[{"profile":{"avatarMediaUrl":"\#(url)"}}]"#))
}
check("your avatar is read from profile.js",
      avatar("https://pbs.twimg.com/profile_images/1/a.jpg")
          == "https://pbs.twimg.com/profile_images/1/a.jpg")
// THE FENCE. This URL is a line in a file the person picked, and it goes
// straight into a fetch — so an unfenced read lets a data file name any host
// it likes for the app to call. Matched on the LABEL boundary, the same rule
// `OEmbed.handles` uses, or a lookalike domain walks straight through.
check("a lookalike host is refused",
      avatar("https://pbs.twimg.com.attacker.example/a.jpg") == nil)
check("an unrelated host is refused", avatar("https://evil.example/a.jpg") == nil)
check("plain http is refused", avatar("http://pbs.twimg.com/a.jpg") == nil)
check("a subdomain of the real CDN is allowed",
      avatar("https://x.pbs.twimg.com/a.jpg") != nil)
check("a file with no avatar in it yields nil",
      XArchiveImport.accountAvatarURL(under: profileFolder(#"[{"profile":{}}]"#)) == nil)
// An EMPTY directory of its own, never the shared temp root: `read` looks one
// level down as well (an archive unzips into a named folder and picking either
// one has to work), so pointing this at the temp root makes it find the
// fixtures the checks above just wrote there. That is the test being wrong,
// not the reader — but it fails intermittently, which is worse.
let barren = URL(fileURLWithPath: NSTemporaryDirectory())
    .appending(path: "x-avatar-empty-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: barren, withIntermediateDirectories: true)
check("a folder with no profile.js yields nil",
      XArchiveImport.accountAvatarURL(under: barren) == nil)

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

// ── 2026-08-13 (prd §375): the enrichment pass ─────────────────────────────
print("")
print("the picture posts — a photo is a photo, not its own shortlink")
// The archive puts a bare t.co in `full_text` for an attached image and files
// the image under `entities.media`. With WORDS beside it the post keeps them;
// with nothing beside it the post is a photograph, and `wordsWithoutMedia`
// answering EMPTY is the only signal that says so.
let photoEntities: [String: Any] = ["media": [["url": "https://t.co/pic1"]]]
check("a photo-only post reads as wordless",
      XArchiveImport.wordsWithoutMedia("https://t.co/pic1", entities: photoEntities).isEmpty)
check("…and `clean` still refuses to hand back nothing for it",
      XArchiveImport.clean("https://t.co/pic1", entities: photoEntities) == "https://t.co/pic1")
check("a captioned photo keeps its caption and loses the shortlink",
      XArchiveImport.wordsWithoutMedia("at the studio https://t.co/pic1", entities: photoEntities)
          == "at the studio")
check("…and `clean` agrees with it",
      XArchiveImport.clean("at the studio https://t.co/pic1", entities: photoEntities)
          == "at the studio")
// A post with a real LINK in it is not a photo post: `entities.urls` is a
// different key, and confusing the two would file every link-sharing post as a
// picture and drop its words.
let linkOnly: [String: Any] = ["urls": [["url": "https://t.co/abc",
                                         "expanded_url": "https://example.com/x"]]]
check("a link-only post is not wordless",
      XArchiveImport.wordsWithoutMedia("https://t.co/abc", entities: linkOnly)
          == "https://example.com/x")
check("the picture post's face is the word, not the URL",
      XArchiveImport.face(reply: nil, text: "", wordless: true) == "Photo")
check("a reply's recipient still leads its face",
      XArchiveImport.face(reply: "lindsey", text: "yes exactly", wordless: false)
          == "To @lindsey · yes exactly")
// §303 as a test, kept from the day the lead landed: the clamp is what makes
// the lead necessary, so both halves are asserted through the SHIPPED clamp.
let wordyReply = String(repeating: "a considered answer ", count: 8)
let ledFace = IngestSupport.titleLine(
    XArchiveImport.face(reply: "lindsey", text: wordyReply, wordless: false))
let trailingFace = IngestSupport.titleLine(wordyReply + " — to @lindsey")
check("…and it survives the 80-char clamp where a trailing one would not",
      ledFace.contains("@lindsey") && !trailingFace.contains("@lindsey"))

print("")
print("the reply's parent — a permalink, and what it said")
check("a permalink is built from the two facts the archive states",
      XArchiveImport.permalink(handle: "lindsey", id: "1701")
          == "https://x.com/lindsey/status/1701")
check("a parent with no words in the file stays empty, never guessed",
      XArchiveImport.parentPreview(nil).isEmpty
      && XArchiveImport.parentPreview("   ").isEmpty)
check("a short parent is carried whole",
      XArchiveImport.parentPreview("the post being answered") == "the post being answered")
// Clamped, because this text is stored inside the reply's own row: a thread of
// forty self-replies would otherwise keep thirty-nine copies of its own chain.
let hugeParent = String(repeating: "x", count: 900)
check("a long parent is clamped and says it was clamped",
      XArchiveImport.parentPreview(hugeParent).count == 281
      && XArchiveImport.parentPreview(hugeParent).hasSuffix("…"))

print("")
print("note-tweet — the long posts, joined to the right post")
check("a note joins on lifecycle.initialTweetId",
      XArchiveImport.noteTarget(["lifecycle": ["initialTweetId": "1701"]]) == "1701")
// The note's OWN id is not the tweet's, so accepting it would file a body
// against a post that never had one. This is the assertion that a plausible
// "fall back to noteTweetId" would break.
check("a note's own id is NEVER used as the join key",
      XArchiveImport.noteTarget(["noteTweetId": "999"]) == nil)
check("a numeric join key survives (a snowflake is past Double's exact range)",
      XArchiveImport.noteTarget(["lifecycle": ["initialTweetId": UInt64(1701)]]) == "1701")
check("a shape with no join key at all yields nil rather than a guess",
      XArchiveImport.noteTarget(["core": ["text": "hi"]]) == nil)
// note-tweet spells the same fact in camelCase where tweets.js uses snake —
// the field-case drift these exports are known for. Both must expand.
let camel: [String: Any] = ["urls": [["url": "https://t.co/n1",
                                      "expandedUrl": "https://example.com/long"]]]
check("a note's camelCase link expands like a post's snake_case one",
      XArchiveImport.clean("see https://t.co/n1",
                           entities: XArchiveImport.noteEntities(camel)) == "see https://example.com/long")
let snake: [String: Any] = ["urls": [["url": "https://t.co/n1",
                                      "expanded_url": "https://example.com/long"]]]
check("…and so does the snake_case spelling of a note's own links",
      XArchiveImport.clean("see https://t.co/n1",
                           entities: XArchiveImport.noteEntities(snake)) == "see https://example.com/long")

print("")
print("XRoom — the years, and which one was loudest")
// Built as a table so the expected answers are readable: (year, count).
func sightings(_ table: [(Int, Int)], terms: [Int: [String]] = [:],
               likes: [Int: [Int]] = [:]) -> [XRoom.Sighting] {
    var out: [XRoom.Sighting] = []
    for (year, count) in table {
        let yearLikes: [Int] = likes[year] ?? []
        for i in 0..<count {
            let like: Int? = i < yearLikes.count ? yearLikes[i] : nil
            out.append(XRoom.Sighting(ref: "x:tweet:\(year)-\(i)", year: year,
                                      terms: terms[year] ?? [], likes: like))
        }
    }
    return out
}
check("a room under the post floor declines",
      XRoom.compose(sightings([(2019, 5), (2020, 5), (2021, 5)])) == nil)
check("a room under the year floor declines, however big",
      XRoom.compose(sightings([(2019, 400), (2020, 400)])) == nil)
let deep = XRoom.compose(sightings([(2019, 30), (2021, 12), (2022, 5)]))!
// The SILENT year is the assertion that matters here: 2020 has no rows, and it
// must still take its column — dropping it would put 2019 and 2021 side by
// side and silently rescale the axis.
check("the span runs first year to last, gaps included",
      deep.years.map(\.year) == [2019, 2020, 2021, 2022])
check("a silent year is drawn, at zero",
      deep.years.first { $0.year == 2020 }?.posts == 0 && deep.silent == 1)
check("the busiest year is the one with the most posts", deep.busiest.year == 2019)
check("the total counts every sighting", deep.total == 47)
check("the headline names the year and its count",
      XRoom.headline(deep).contains("2019") && XRoom.headline(deep).contains("30"))
check("the note says how much of the span you wrote in",
      XRoom.note(deep).contains("3") && XRoom.note(deep).contains("4"))
// A TOTAL order. Two years tied on posts must resolve the same way every time
// or the card renames its own headline between two identical opens.
let tied = XRoom.compose(sightings([(2019, 20), (2020, 20), (2021, 20)]))!
check("a tie goes to the earlier year, deterministically",
      tied.busiest.year == 2019
      && XRoom.compose(sightings([(2021, 20), (2020, 20), (2019, 20)]))!.busiest.year == 2019)
check("rows are biggest first and never include a silent year",
      XRoom.rows(deep).map(\.year) == [2019, 2021, 2022])
// The subject floor — `topicMap`'s recurrence rule in miniature. One mention
// does not make a year's subject, which is the whole difference between a
// reading and a label.
let subjects = XRoom.compose(sightings([(2019, 30), (2020, 30), (2021, 30)],
                                        terms: [2019: ["Design"], 2020: [], 2021: []]))!
check("a term said in every post of a year is that year's subject",
      subjects.years.first { $0.year == 2019 }?.subject == "Design")
check("a year with no terms has no subject rather than a blank one",
      subjects.years.first { $0.year == 2020 }?.subject == nil)
check("one mention in a big year is not a subject",
      XRoom.subject(["Lisbon": 1], posts: 300) == nil)
check("…and two mentions in a small year is",
      XRoom.subject(["Lisbon": 2], posts: 6) == "Lisbon")
check("a subject tie breaks alphabetically, deterministically",
      XRoom.subject(["Berlin": 4, "Athens": 4], posts: 10) == "Athens")
// The tap target. `likes` nil is NOT zero — an archive vintage that recorded
// no counts must not make the first post it sees the year's loudest.
let loud = XRoom.compose(sightings([(2019, 8), (2020, 8), (2021, 8)],
                                    likes: [2019: [4, 91, 7]]))!
check("a year's loudest post is the one with the most likes",
      loud.years.first { $0.year == 2019 }?.loudestRef == "x:tweet:2019-1")
check("a year with no counts names no loudest post rather than picking one",
      loud.years.first { $0.year == 2020 }?.loudestRef == nil)
check("a bar is a share of the busiest year, and never divides by nothing",
      XRoom.share(posts: 15, of: 30) == 0.5 && XRoom.share(posts: 5, of: 0) == 0)
check("a share can't exceed the axis", XRoom.share(posts: 40, of: 30) == 1)
// The footnote separates "not read yet" from "nothing recurred", which is the
// difference between a card that will heal and one that never will.
check("a card with no subjects at all says the room hasn't been read",
      XRoom.footnote(deep)?.contains("read") == true)
check("a card with every subject named has no footnote",
      XRoom.footnote(XRoom.compose(sightings([(2019, 30), (2020, 30), (2021, 30)],
                                              terms: [2019: ["A"], 2020: ["B"], 2021: ["C"]]))!) == nil)

// ---------------------------------------------------------------------------
// 2026-08-18, prd §396 — the account's own record, and your years with one
// person. Both files are compiled WHOLE and unmodified above.
// ---------------------------------------------------------------------------

print("")
print("XArchiveAccount — the reach ladder, and the two date shapes")

func app(_ fields: [String: Any]) -> XArchiveAccount.App? {
    XArchiveAccount.apps([["connectedApplication": fields]]).first
}
check("an app with no name is dropped rather than landed unnamed",
      XArchiveAccount.apps([["connectedApplication": ["id": "1"]]]).isEmpty)
check("a write grant says it can post as you",
      app(["id": "1", "name": "Tweetbot", "permissions": ["read", "write"]])?.reach == .write)
check("a read-only grant is never upgraded",
      app(["id": "1", "name": "Reader", "permissions": ["read"]])?.reach == .read)
// The single-string era. An enum match against a fixed vocabulary reads
// `permissions: ["read","write"]` and answers `unknown` for this one, which
// UNDER-states a write grant — the one direction that must never happen.
check("the one-string form reads the same as the array form",
      app(["id": "1", "name": "Old", "accessType": "Read and Write"])?.reach == .write)
check("a message scope outranks write, however it is spelled",
      app(["id": "1", "name": "DMs", "permissions": ["read", "write", "dm"]])?.reach == .messages
      && app(["id": "2", "name": "DMs", "accessType": "Read, Write and Direct Messages"])?.reach == .messages)
check("a permission field naming nothing we know stays unknown, never a guess",
      app(["id": "1", "name": "Mystery", "permissions": ["frobnicate"]])?.reach == .unknown)
check("an absent permission field is unknown too",
      app(["id": "1", "name": "Mystery"])?.reach == .unknown)
// Every grade gets its own sentence, and the REACH LEADS — §303's clamp
// ruling: `titleLine` cuts at 80 characters, so a trailing "can post as you"
// on a long app name is exactly what the cut eats.
for probe in [(XArchiveAccount.Reach.messages, "messages"), (.write, "write"),
              (.read, "read"), (.unknown, "unknown")] {
    let a = XArchiveAccount.App(id: "1", name: "Zed", organization: nil, detail: nil,
                                reach: probe.0, approvedAt: nil)
    check("the \(probe.1) grade leads with its reach and names the app",
          XArchiveAccount.appTitle(a).hasSuffix("Zed")
          && XArchiveAccount.appTitle(a).count > 4)
}
check("an unknown grant does not claim it can post as you",
      !XArchiveAccount.appTitle(
        XArchiveAccount.App(id: "1", name: "Zed", organization: nil, detail: nil,
                            reach: .unknown, approvedAt: nil)).contains("post"))
check("an organisation that repeats the app's own name is dropped",
      app(["id": "1", "name": "Tweetbot",
           "organization": ["name": "Tweetbot"]])?.organization == nil)
check("…and one that differs is kept, ahead of the app's own blurb",
      XArchiveAccount.appDetail(
        XArchiveAccount.App(id: "1", name: "Tweetbot", organization: "Tapbots",
                            detail: "A Twitter client.", reach: .write, approvedAt: nil))
        == "Tapbots · A Twitter client.")
check("no organisation and no blurb draws no second line at all",
      XArchiveAccount.appDetail(
        XArchiveAccount.App(id: "1", name: "Zed", organization: nil, detail: nil,
                            reach: .read, approvedAt: nil)) == nil)
check("the same app twice in one file lands once",
      XArchiveAccount.apps([["connectedApplication": ["id": "7", "name": "A"]],
                            ["connectedApplication": ["id": "7", "name": "A"]]]).count == 1)
// TOTAL ordering. Without the name and id terms two grants approved the same
// second race, and the inventory reshuffles between two identical opens.
let ordered = XArchiveAccount.apps([
    ["connectedApplication": ["id": "1", "name": "B", "approvedAt": "2013-05-01T12:00:00.000Z"]],
    ["connectedApplication": ["id": "2", "name": "A", "approvedAt": "2019-05-01T12:00:00.000Z"]],
    ["connectedApplication": ["id": "3", "name": "A", "approvedAt": "2013-05-01T12:00:00.000Z"]],
])
check("apps rank newest grant first, then by name — a total order",
      ordered.map(\.name) == ["A", "A", "B"] && ordered.map(\.id) == ["2", "3", "1"])
check("an id arriving as a JSON number is still read",
      XArchiveAccount.apps([["connectedApplication": ["id": 42, "name": "N"]]]).first?.id == "42")

// The two date shapes, both accepted everywhere outside the tweet files. This
// is the one measured fact about this export's dates: they are not consistent.
check("an ISO stamp parses",
      XArchiveAccount.stamp("2013-05-01T12:00:00.000Z") != nil)
check("an ISO stamp with no fractional seconds parses too",
      XArchiveAccount.stamp("2013-05-01T12:00:00Z") != nil)
check("X's own post stamp parses through the same door",
      XArchiveAccount.stamp("Wed Mar 21 20:50:14 +0000 2006") != nil)
check("both shapes agree to the second on the same instant",
      XArchiveAccount.stamp("2006-03-21T20:50:14Z")
        == XArchiveAccount.stamp("Wed Mar 21 20:50:14 +0000 2006"))
check("nonsense is refused rather than dated", XArchiveAccount.stamp("last tuesday") == nil)
check("an empty or missing stamp is nil, never now",
      XArchiveAccount.stamp("") == nil && XArchiveAccount.stamp(nil) == nil)

check("the account's beginning is read, handle and all",
      XArchiveAccount.origin([["account": ["username": "@me", "accountId": "9",
                                           "createdAt": "2009-03-01T00:00:00.000Z"]]])?.handle == "me")
check("an account with no createdAt yields nothing rather than today",
      XArchiveAccount.origin([["account": ["username": "me"]]]) == nil)

// The doubled nesting is genuinely in X's own file: the wrapper key and the
// inner key are both `screenNameChange`.
let renames = XArchiveAccount.renames([
    ["screenNameChange": ["screenNameChange": ["changedFrom": "old", "changedTo": "new",
                                               "changedAt": "2016-01-01T00:00:00.000Z"]]],
    ["screenNameChange": ["screenNameChange": ["changedTo": "@newer",
                                               "changedAt": "2011-01-01T00:00:00.000Z"]]],
])
check("renames come back oldest first", renames.map(\.to) == ["newer", "new"])
check("an @ is stripped from either handle", renames.first?.to == "newer")
check("a rename with no date is dropped rather than undated",
      XArchiveAccount.renames([["screenNameChange": ["changedTo": "x"]]]).isEmpty)
check("a rename naming both handles says both — the old one is the half you'd search for",
      XArchiveAccount.renameTitle(renames[1]).contains("old")
      && XArchiveAccount.renameTitle(renames[1]).contains("new"))
check("…and one naming only the new handle does not invent an old one",
      !XArchiveAccount.renameTitle(renames[0]).contains("old"))

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

if ! swiftc -O -o "$TMP/x-selftest" "$TMP/extracted.swift" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ harness failed to compile against the shipped source"
  grep -E 'error:' "$TMP/build.log" | head -20
  exit 1
fi
"$TMP/x-selftest"
