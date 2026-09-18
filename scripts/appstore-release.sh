#!/bin/bash
# appstore-release.sh — open a NEW App Store version, attach a build, set
# What's New, and submit it for review. The sibling of appstore-swap-build.sh
# (which replaces the build on a version already in review).
#
# Usage:
#   ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=/tmp/asc.p8 \
#     appstore-release.sh --version 1.0.28 --platform IOS --build 615 \
#       --notes "$(cat notes.txt)"
set -euo pipefail
API="https://api.appstoreconnect.apple.com/v1"
APP_ID="6788637831"
JWT_GEN="$(cd "$(dirname "$0")" && pwd)/asc-jwt.py"
[ -x "$JWT_GEN" ] || JWT_GEN="$HOME/Developer/casberi/scripts/asc-jwt.py"
jq_() { python3 -c "import sys,json;$1"; }
T="$("$JWT_GEN" "$ASC_KEY_ID" "$ASC_ISSUER_ID" "$ASC_KEY_PATH")"

VERSION="" PLATFORM="IOS" BUILD="" NOTES="" DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift 2;;
    --platform) PLATFORM="$2"; shift 2;;
    --build) BUILD="$2"; shift 2;;
    --notes) NOTES="$2"; shift 2;;
    --dry-run) DRY=1; shift;;
    *) echo "unknown arg: $1"; exit 2;;
  esac
done
: "${VERSION:?--version required}"; : "${BUILD:?--build required}"; : "${NOTES:?--notes required}"

# ── 1 · the build must exist and be VALID on THIS platform ──────────────────
BJSON="$(curl -fsS -H "Authorization: Bearer $T" \
  "$API/builds?filter%5Bapp%5D=$APP_ID&filter%5Bversion%5D=$BUILD&filter%5BpreReleaseVersion.platform%5D=$PLATFORM&limit=1")"
BUILD_ID="$(printf '%s' "$BJSON" | jq_ "d=json.load(sys.stdin)['data']; print(d[0]['id'] if d else '')")"
BUILD_STATE="$(printf '%s' "$BJSON" | jq_ "d=json.load(sys.stdin)['data']; print(d[0]['attributes'].get('processingState','?') if d else '')")"
[ -n "$BUILD_ID" ] || { echo "✗ no $PLATFORM build $BUILD found"; exit 1; }
[ "$BUILD_STATE" = "VALID" ] || { echo "✗ build $BUILD is $BUILD_STATE, not VALID"; exit 1; }
echo "build     $BUILD — VALID ($BUILD_ID)"

# ── 2 · the version record: reuse an editable one, else create it ───────────
VJSON="$(curl -fsS -H "Authorization: Bearer $T" \
  "$API/apps/$APP_ID/appStoreVersions?filter%5BversionString%5D=$VERSION&filter%5Bplatform%5D=$PLATFORM&limit=1")"
VER_ID="$(printf '%s' "$VJSON" | jq_ "d=json.load(sys.stdin)['data']; print(d[0]['id'] if d else '')")"
VER_STATE="$(printf '%s' "$VJSON" | jq_ "d=json.load(sys.stdin)['data']; print(d[0]['attributes']['appStoreState'] if d else '')")"
if [ -n "$VER_ID" ]; then
  echo "version   $VERSION exists — $VER_STATE ($VER_ID)"
  case "$VER_STATE" in
    READY_FOR_SALE|APPROVED) echo "✗ $VERSION's train is closed — bump MARKETING_VERSION"; exit 1;;
  esac
else
  [ "$DRY" = "1" ] && { echo "— dry run: would CREATE $PLATFORM $VERSION —"; exit 0; }
  BODY="$(mktemp)"
  CODE="$(curl -s -o "$BODY" -w '%{http_code}' -X POST -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
    -d "{\"data\":{\"type\":\"appStoreVersions\",\"attributes\":{\"platform\":\"$PLATFORM\",\"versionString\":\"$VERSION\",\"releaseType\":\"AFTER_APPROVAL\"},\"relationships\":{\"app\":{\"data\":{\"type\":\"apps\",\"id\":\"$APP_ID\"}}}}}" \
    "$API/appStoreVersions")"
  [ "$CODE" = "201" ] || { echo "✗ create-version failed (HTTP $CODE)"; cat "$BODY"; exit 1; }
  VER_ID="$(jq_ "print(json.load(sys.stdin)['data']['id'])" < "$BODY")"; rm -f "$BODY"
  echo "version   $VERSION created ($VER_ID)"
fi
[ "$DRY" = "1" ] && { echo "— dry run, nothing further changed —"; exit 0; }

# ── 3 · What's New (en-US) ──────────────────────────────────────────────────
LOC_ID="$(curl -fsS -H "Authorization: Bearer $T" "$API/appStoreVersions/$VER_ID/appStoreVersionLocalizations" \
  | jq_ "d=json.load(sys.stdin)['data']; print(next((l['id'] for l in d if l['attributes']['locale']=='en-US'),''))")"
[ -n "$LOC_ID" ] || { echo "✗ no en-US localization on $VERSION"; exit 1; }
NOTES_JSON="$(NOTES="$NOTES" python3 -c "import json,os;print(json.dumps(os.environ['NOTES']))")"
curl -fsS -X PATCH -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
  -d "{\"data\":{\"type\":\"appStoreVersionLocalizations\",\"id\":\"$LOC_ID\",\"attributes\":{\"whatsNew\":$NOTES_JSON}}}" \
  "$API/appStoreVersionLocalizations/$LOC_ID" >/dev/null
READBACK="$(curl -fsS -H "Authorization: Bearer $T" "$API/appStoreVersionLocalizations/$LOC_ID" \
  | jq_ "print(json.load(sys.stdin)['data']['attributes']['whatsNew'] or '')")"
[ "$READBACK" = "$NOTES" ] || { echo "✗ What's New did not persist (readback mismatch)"; exit 1; }
echo "✓ What's New set and read back"

# ── 4 · attach the build ────────────────────────────────────────────────────
for a in 1 2 3 4 5; do
  CODE="$(curl -s -o /dev/null -w '%{http_code}' -X PATCH -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
    -d "{\"data\":{\"type\":\"builds\",\"id\":\"$BUILD_ID\"}}" "$API/appStoreVersions/$VER_ID/relationships/build")"
  [ "$CODE" = "204" ] && break
  [ "$CODE" = "409" ] || { echo "✗ attach-build failed (HTTP $CODE)"; exit 1; }
  [ "$a" = "5" ] && { echo "✗ attach-build still 409 after 5 tries"; exit 1; }
  echo "  409 — retrying ($a)"; sleep 6
done
echo "✓ $PLATFORM $VERSION carries build $BUILD"

# ── 5 · submit (reviewSubmissions pair; appStoreVersionSubmissions is retired) ─
open_sub() {
  curl -fsS -H "Authorization: Bearer $T" \
    "$API/apps/$APP_ID/reviewSubmissions?filter%5Bplatform%5D=$PLATFORM&filter%5Bstate%5D=READY_FOR_REVIEW&limit=10" \
    | jq_ "d=json.load(sys.stdin).get('data',[]); print(next((s['id'] for s in d if not s['attributes'].get('submittedDate')),''))"
}
NEW_SUB="$(open_sub)"
if [ -z "$NEW_SUB" ]; then
  BODY="$(mktemp)"
  CODE="$(curl -s -o "$BODY" -w '%{http_code}' -X POST -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
    -d "{\"data\":{\"type\":\"reviewSubmissions\",\"attributes\":{\"platform\":\"$PLATFORM\"},\"relationships\":{\"app\":{\"data\":{\"type\":\"apps\",\"id\":\"$APP_ID\"}}}}}" \
    "$API/reviewSubmissions")"
  if [ "$CODE" = "200" ] || [ "$CODE" = "201" ]; then
    NEW_SUB="$(jq_ "print(json.load(sys.stdin)['data']['id'])" < "$BODY")"
  else
    sleep 3; NEW_SUB="$(open_sub)"
    [ -n "$NEW_SUB" ] || { echo "✗ create-submission failed (HTTP $CODE)"; cat "$BODY"; exit 1; }
  fi
  rm -f "$BODY"
fi
echo "review sub $NEW_SUB"
item_attached() {
  curl -fsS -H "Authorization: Bearer $T" "$API/reviewSubmissions/$NEW_SUB/items" 2>/dev/null \
    | VER_ID="$VER_ID" python3 -c "
import sys, json, os
want = os.environ['VER_ID']
d = json.load(sys.stdin).get('data', [])
ids = []
for i in d:
    rel = (i.get('relationships') or {}).get('appStoreVersion') or {}
    data = rel.get('data') or {}
    if data.get('id'): ids.append(data['id'])
print('yes' if want in ids else 'no')
" 2>/dev/null
}
if [ "$(item_attached)" != "yes" ]; then
  for a in 1 2 3; do
    CODE="$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
      -d "{\"data\":{\"type\":\"reviewSubmissionItems\",\"relationships\":{\"reviewSubmission\":{\"data\":{\"type\":\"reviewSubmissions\",\"id\":\"$NEW_SUB\"}},\"appStoreVersion\":{\"data\":{\"type\":\"appStoreVersions\",\"id\":\"$VER_ID\"}}}}}" \
      "$API/reviewSubmissionItems")"
    [ "$CODE" = "201" ] && break
    [ "$(item_attached)" = "yes" ] && { echo "  already attached"; break; }
    [ "$a" = "3" ] && { echo "✗ attach-item failed (HTTP $CODE)"; exit 1; }
    sleep 5
  done
fi
echo "✓ version attached to the submission"
submitted() { curl -fsS -H "Authorization: Bearer $T" "$API/reviewSubmissions/$NEW_SUB" \
  | jq_ "print('yes' if json.load(sys.stdin)['data']['attributes'].get('submittedDate') else 'no')"; }
if [ "$(submitted)" != "yes" ]; then
  for a in 1 2 3; do
    CODE="$(curl -s -o /dev/null -w '%{http_code}' -X PATCH -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
      -d "{\"data\":{\"type\":\"reviewSubmissions\",\"id\":\"$NEW_SUB\",\"attributes\":{\"submitted\":true}}}" \
      "$API/reviewSubmissions/$NEW_SUB")"
    { [ "$CODE" = "200" ] || [ "$CODE" = "204" ]; } && break
    [ "$(submitted)" = "yes" ] && break
    [ "$a" = "3" ] && { echo "✗ submit failed (HTTP $CODE)"; exit 1; }
    sleep 5
  done
fi
FINAL="$(curl -fsS -H "Authorization: Bearer $T" "$API/appStoreVersions/$VER_ID" \
  | jq_ "print(json.load(sys.stdin)['data']['attributes']['appStoreState'])")"
echo "✓ submitted — $PLATFORM $VERSION is $FINAL"
