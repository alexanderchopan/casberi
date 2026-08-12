#!/bin/bash
# appstore-swap-build.sh — point an App Store version that is ALREADY waiting
# for (or in) review at a different build, and re-submit it.
#
# WHY THIS IS A SCRIPT. It has been done by hand more than once, it is four
# calls in a strict order, and two of them are easy to get wrong in ways that
# read as "the API is broken":
#
#   • `POST /v1/appStoreVersionSubmissions` is RETIRED and answers 403. Every
#     older recipe (and most of the internet) still names it. Submission is the
#     reviewSubmissions + reviewSubmissionItems pair below.
#   • You cannot PATCH the build of a version that has an OPEN review
#     submission. The submission must be cancelled first, which is why the
#     order here is cancel → swap → resubmit and not swap → resubmit.
#
# WHAT IT COSTS, stated up front because it is not recoverable: cancelling the
# submission gives up your place in Apple's review queue. The new submission
# goes to the back. That is the price of replacing a build that is waiting, and
# it is why this is a deliberate command rather than part of a normal ship.
#
# It refuses to run against an APPROVED version: once a version is approved its
# train is closed, no further build can be attached, and the fix is a new
# MARKETING_VERSION rather than a swap (see docs/testflight-handoff.md).
#
# Usage:
#   scripts/dev-keys.sh get-file asc-p8 /tmp/asc-swap.p8
#   ASC_KEY_ID=TR287WZD72 ASC_ISSUER_ID=2152ec98-0a7c-477a-9c4a-e1c478a3a106 \
#     ASC_KEY_PATH=/tmp/asc-swap.p8 \
#     scripts/appstore-swap-build.sh --version 1.0.5 --platform IOS --build 311
#   rm -f /tmp/asc-swap.p8
#
# Add --dry-run to print what it WOULD do and change nothing.
set -euo pipefail

API="https://api.appstoreconnect.apple.com/v1"
APP_ID="6788637831"
JWT_GEN="$(cd "$(dirname "$0")" && pwd)/asc-jwt.py"

: "${ASC_KEY_ID:?ASC_KEY_ID not set}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID not set}"
: "${ASC_KEY_PATH:?ASC_KEY_PATH not set}"
[ -f "$ASC_KEY_PATH" ] || { echo "✗ key file not found: $ASC_KEY_PATH"; exit 1; }

jwt() { python3 "$JWT_GEN" "$ASC_KEY_ID" "$ASC_ISSUER_ID" "$ASC_KEY_PATH"; }
jq_() { python3 -c "import sys,json;$1"; }

VERSION="" PLATFORM="IOS" BUILD="" DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --version)  VERSION="$2"; shift 2 ;;
    --platform) PLATFORM="$2"; shift 2 ;;
    --build)    BUILD="$2"; shift 2 ;;
    --dry-run)  DRY=1; shift ;;
    *) echo "✗ unknown argument: $1"; exit 1 ;;
  esac
done
[ -n "$VERSION" ] || { echo "✗ --version required (e.g. 1.0.5)"; exit 1; }
[ -n "$BUILD" ]   || { echo "✗ --build required (e.g. 311)"; exit 1; }

T="$(jwt)"

# ── 1 · the version, and whether it may still be changed ────────────────────
VJSON="$(curl -fsS -H "Authorization: Bearer $T" \
  "$API/apps/$APP_ID/appStoreVersions?filter%5Bplatform%5D=$PLATFORM&filter%5BversionString%5D=$VERSION&limit=1")"
VER_ID="$(printf '%s' "$VJSON" | jq_ "d=json.load(sys.stdin)['data']; print(d[0]['id'] if d else '')")"
VER_STATE="$(printf '%s' "$VJSON" | jq_ "d=json.load(sys.stdin)['data']; print(d[0]['attributes']['appStoreState'] if d else '')")"
[ -n "$VER_ID" ] || { echo "✗ no $PLATFORM version $VERSION on this app"; exit 1; }
echo "version   $PLATFORM $VERSION — $VER_STATE  ($VER_ID)"

case "$VER_STATE" in
  READY_FOR_SALE|APPROVED|DEVELOPER_REMOVED_FROM_SALE|REPLACED_WITH_NEW_VERSION)
    echo "✗ $VER_STATE — this version's train is closed; a new build needs a new"
    echo "  MARKETING_VERSION, not a swap. See docs/testflight-handoff.md."
    exit 1 ;;
esac

CUR="$(curl -fsS -H "Authorization: Bearer $T" "$API/appStoreVersions/$VER_ID/build" \
  | jq_ "d=json.load(sys.stdin).get('data'); print(d['attributes']['version'] if d else 'none')")"
echo "attached  build $CUR"
[ "$CUR" = "$BUILD" ] && { echo "✓ already on build $BUILD — nothing to swap"; exit 0; }

# ── 2 · the replacement build must exist and be usable ──────────────────────
BJSON="$(curl -fsS -H "Authorization: Bearer $T" \
  "$API/builds?filter%5Bapp%5D=$APP_ID&filter%5Bversion%5D=$BUILD&filter%5BpreReleaseVersion.platform%5D=$PLATFORM&limit=1")"
BUILD_ID="$(printf '%s' "$BJSON" | jq_ "d=json.load(sys.stdin)['data']; print(d[0]['id'] if d else '')")"
BUILD_STATE="$(printf '%s' "$BJSON" | jq_ "d=json.load(sys.stdin)['data']; print(d[0]['attributes'].get('processingState','?') if d else '')")"
[ -n "$BUILD_ID" ] || { echo "✗ no $PLATFORM build $BUILD found — has it finished uploading?"; exit 1; }
echo "target    build $BUILD — $BUILD_STATE  ($BUILD_ID)"
[ "$BUILD_STATE" = "VALID" ] || { echo "✗ build $BUILD is $BUILD_STATE, not VALID — wait for processing"; exit 1; }

# ── 3 · the open review submission, which blocks the swap ───────────────────
SUB_ID="$(curl -fsS -H "Authorization: Bearer $T" \
  "$API/apps/$APP_ID/reviewSubmissions?filter%5Bplatform%5D=$PLATFORM&filter%5Bstate%5D=WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES,READY_FOR_REVIEW&limit=1" \
  | jq_ "d=json.load(sys.stdin).get('data',[]); print(d[0]['id'] if d else '')")"
if [ -n "$SUB_ID" ]; then
  echo "open sub  $SUB_ID — will be CANCELLED (this gives up the queue position)"
else
  echo "open sub  none"
fi

if [ "$DRY" = "1" ]; then echo "— dry run, nothing changed —"; exit 0; fi

if [ -n "$SUB_ID" ]; then
  curl -fsS -X PATCH -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
    -d "{\"data\":{\"type\":\"reviewSubmissions\",\"id\":\"$SUB_ID\",\"attributes\":{\"canceled\":true}}}" \
    "$API/reviewSubmissions/$SUB_ID" >/dev/null
  echo "✓ cancelled the open submission"
fi

# ── 4 · point the version at the new build ─────────────────────────────────
curl -fsS -X PATCH -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
  -d "{\"data\":{\"type\":\"builds\",\"id\":\"$BUILD_ID\"}}" \
  "$API/appStoreVersions/$VER_ID/relationships/build" >/dev/null
echo "✓ $PLATFORM $VERSION now carries build $BUILD"

# ── 5 · resubmit — the reviewSubmissions pair, NOT appStoreVersionSubmissions ─
NEW_SUB="$(curl -fsS -X POST -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
  -d "{\"data\":{\"type\":\"reviewSubmissions\",\"attributes\":{\"platform\":\"$PLATFORM\"},\"relationships\":{\"app\":{\"data\":{\"type\":\"apps\",\"id\":\"$APP_ID\"}}}}}" \
  "$API/reviewSubmissions" | jq_ "print(json.load(sys.stdin)['data']['id'])")"
curl -fsS -X POST -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
  -d "{\"data\":{\"type\":\"reviewSubmissionItems\",\"relationships\":{\"reviewSubmission\":{\"data\":{\"type\":\"reviewSubmissions\",\"id\":\"$NEW_SUB\"}},\"appStoreVersion\":{\"data\":{\"type\":\"appStoreVersions\",\"id\":\"$VER_ID\"}}}}}" \
  "$API/reviewSubmissionItems" >/dev/null
curl -fsS -X PATCH -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
  -d "{\"data\":{\"type\":\"reviewSubmissions\",\"id\":\"$NEW_SUB\",\"attributes\":{\"submitted\":true}}}" \
  "$API/reviewSubmissions/$NEW_SUB" >/dev/null
echo "✓ resubmitted for review ($NEW_SUB)"

FINAL="$(curl -fsS -H "Authorization: Bearer $T" "$API/appStoreVersions/$VER_ID" \
  | jq_ "print(json.load(sys.stdin)['data']['attributes']['appStoreState'])")"
echo "state     $PLATFORM $VERSION — $FINAL"
