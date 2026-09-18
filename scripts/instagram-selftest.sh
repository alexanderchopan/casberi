#!/bin/zsh
# Casberi Instagram self-test — the wiring the Instagram room rests on (prd
# §395), and the room's lead (prd §821).
#
# The room's HEAD MODEL (`InstagramRoom` / `InstagramRoomSource`) is DELETED
# (prd §821, §723): no view had drawn it since §751, only a probe line read it,
# and the room leads with its newest thing (user: "it should just show newest
# notification"). This harness used to compile that model whole; what is left
# is every guard on something still alive, and a guard that the model stays
# gone.
#
# WHY A HARNESS AND NOT A LIVE CHECK. The export half has never been imported
# on this host (prd §245), so every failure here is a SILENT WRONG ANSWER that
# renders perfectly: a photo room drawn as text, a cover URL that 404s within
# the week, a year of reels never imported, a wordless picture counted as
# writing.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

IMPORT="Casberi/Casberi/Model/InstagramImport.swift"
CAPTIONS="Casberi/Casberi/Model/InstagramCaptions.swift"
# FeedScreen is split across files (prd §718). Checks read the room as ONE text,
# so a guard can neither fail nor pass because its code moved next door.
FEED_DIR="$(mktemp -d -t feedscreen)"
FEED="$FEED_DIR/FeedScreen.swift"
cat Casberi/Casberi/Screens/FeedScreen.swift Casberi/Casberi/Screens/FeedScreen+WalletRoom.swift > "$FEED"
INSIGHT="Casberi/Casberi/Model/FeedInsight.swift"
HEATMAP="Casberi/Casberi/Model/FeedHeatmap.swift"
SOCIAL="Casberi/Casberi/Model/SocialRoom.swift"
RETRIEVER="Casberi/Casberi/Model/Retriever.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
for f in "$IMPORT" "$CAPTIONS" "$FEED" "$INSIGHT" "$HEATMAP" "$SOCIAL" "$RETRIEVER" "$REACH"; do
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

# THE HEAD MODEL STAYS GONE (prd §821, §723). A model no view draws is a dead
# control one layer down; the card went in §751 and the model in §821.
for gone in Casberi/Casberi/Model/InstagramRoom.swift Casberi/Casberi/Model/InstagramRoomSource.swift; do
  [[ ! -e "$gone" ]] || { echo "✗ $gone is back — the Instagram room has no head model (§821)"; exit 1; }
done
# Code only: the comments that record the deletion name it on purpose.
if grep -rhE 'InstagramRoom(Source)?\b|instagramRoomProbe|note\("instagramHead"|instagramHead +"' \
     Casberi/Casberi scripts/verify.sh | grep -qvE '^\s*(//|#)'; then
  echo "✗ something references the deleted Instagram head model again (§821)"; exit 1
fi
grep -qF 'InstagramRoomCard(' "$TMP/feed.nc" \
  && { echo "✗ the Instagram head card is drawn again (§751)"; exit 1; }

# THE ROOM LEADS WITH ITS NEWEST THING (prd §821): no topic map, no year
# heatmap, and the picture grid never declines the cover.
grep -qF '"Instagram": Facts(foldsThreads: false, hasRoster: false, leadsWithNewest: true)' "$SOCIAL" \
  || { echo "✗ Instagram no longer leads with its newest thing (SocialRoom.leadsWithNewest)"; exit 1; }
if grep -qE '^\s*"Instagram":\s+Label\(' "$HEATMAP"; then
  echo "✗ Instagram has a year heatmap again — the room leads with its newest thing (§821)"; exit 1
fi
if grep -qE '^\s*case "Instagram":' "$INSIGHT"; then
  echo "✗ Instagram has a topic map again — the room leads with its newest thing (§821)"; exit 1
fi
grep -qF 'let (photoTiles, rest) = Self.splitTiles(uncovered, by: Self.isInstagramPhotoTile)' "$TMP/feed.nc" \
  || { echo "✗ the Instagram grid is split before the cover is lifted out — the grid would decline the cover again"; exit 1; }

# THE FIELDS the rows read, stamped where the post card expects them.
grep -qF 'thing.socialContext = marker' "$TMP/import.nc" \
  || { echo "✗ saves/likes no longer carry their act as socialContext — the post card loses its Saved/Liked word"; exit 1; }
grep -qF '"Instagram"' Casberi/Casberi/Model/SocialBridge.swift \
  || { echo "✗ Instagram is not a context source — contextLabel returns nil for every save"; exit 1; }
grep -qF 'if !row.handle.isEmpty { thing.authorHandle = row.handle }' "$TMP/import.nc" \
  || { echo "✗ saves no longer stamp authorHandle — a save's card has nobody to name"; exit 1; }
grep -qF 'thing.tags.append("Gone")' "$TMP/captions.nc" \
  || { echo "✗ a deleted saved post is no longer tagged Gone"; exit 1; }

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
# (The topic map's own exclusion of wordless pictures went with the map, §821.)

echo "instagram-selftest: drift guards ✓"

echo ""
echo "instagram-selftest: OK"
