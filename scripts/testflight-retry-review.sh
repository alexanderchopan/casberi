#!/bin/bash
# testflight-retry-review.sh — re-attempt the ONE step that Apple's rolling
# beta-review submission limit can block (2026-07-30).
#
# When that limit trips, `testflight-public-beta*.sh` has already done
# everything else: the build is uploaded, processed, carries its release
# notes, and is assigned to the Casberi Public Beta group. It sits at
# "Ready to Submit" in App Store Connect, which means external testers do
# NOT have it. The only missing call is creating the betaAppReviewSubmission,
# and that re-runs on its own — hence this script rather than re-running a
# whole ship (which would archive and upload a redundant build).
#
# Four builds reached testers late this way before it was noticed (183, 185,
# 203, 205), because the handoff script aborted AFTER the assignment and the
# ship read as failed.
#
# Usage — with the build's App Store Connect id (the handoff script prints it,
# and the failure message above hands you this exact line):
#
#   scripts/testflight-retry-review.sh <build-id>
#
# Or resolve it from a build NUMBER and platform:
#
#   scripts/testflight-retry-review.sh --version 205 --platform MAC_OS
#   scripts/testflight-retry-review.sh --version 204 --platform IOS
#
# Credentials: same as every other ship script. Stage the key first —
#   scripts/dev-keys.sh get-file asc-p8 /tmp/asc-retry.p8
#   ASC_KEY_ID=TR287WZD72 ASC_ISSUER_ID=2152ec98-0a7c-477a-9c4a-e1c478a3a106 \
#     ASC_KEY_PATH=/tmp/asc-retry.p8 scripts/testflight-retry-review.sh <build-id>
#   rm -f /tmp/asc-retry.p8

set -euo pipefail

API="https://api.appstoreconnect.apple.com/v1"
APP_ID="6788637831"
JWT_GEN="$(cd "$(dirname "$0")" && pwd)/asc-jwt.py"

: "${ASC_KEY_ID:?ASC_KEY_ID not set}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID not set}"
: "${ASC_KEY_PATH:?ASC_KEY_PATH not set}"
[ -f "$ASC_KEY_PATH" ] || { echo "✗ key file not found: $ASC_KEY_PATH"; exit 1; }

jwt() { python3 "$JWT_GEN" "$ASC_KEY_ID" "$ASC_ISSUER_ID" "$ASC_KEY_PATH"; }

BUILD_ID=""
VERSION=""
PLATFORM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --version)  VERSION="$2"; shift 2 ;;
    --platform) PLATFORM="$2"; shift 2 ;;
    *)          BUILD_ID="$1"; shift ;;
  esac
done

if [ -z "$BUILD_ID" ]; then
  [ -n "$VERSION" ] && [ -n "$PLATFORM" ] || {
    echo "usage: testflight-retry-review.sh <build-id>"
    echo "   or: testflight-retry-review.sh --version <n> --platform <IOS|MAC_OS>"
    exit 1
  }
  echo "-- Resolving $PLATFORM build $VERSION..."
  # The platform filter is load-bearing: iOS and Catalyst share one build-number
  # counter, so both platforms can legitimately carry the same version and an
  # unfiltered lookup submits whichever came back first.
  BUILD_ID=$(curl -s -g -H "Authorization: Bearer $(jwt)" \
    "$API/builds?filter[app]=$APP_ID&filter[version]=$VERSION&filter[preReleaseVersion.platform]=$PLATFORM" \
    | jq -r '.data[0].id // empty')
  [ -n "$BUILD_ID" ] || { echo "✗ no $PLATFORM build $VERSION found"; exit 1; }
  echo "  build id: $BUILD_ID"
fi

# Already through? Then there is nothing to retry and re-POSTing would only
# earn another 422 — report the real state instead of manufacturing a failure.
EXISTING=$(curl -s -g -H "Authorization: Bearer $(jwt)" \
  "$API/builds/$BUILD_ID/betaAppReviewSubmission" \
  | jq -r '.data.attributes.betaReviewState // empty')
if [ -n "$EXISTING" ]; then
  echo "Already submitted — betaReviewState: $EXISTING. Nothing to do."
  exit 0
fi

echo "-- Submitting for Beta App Review..."
RESP=$(curl -s -g -w $'\n%{http_code}' -X POST \
  -H "Authorization: Bearer $(jwt)" -H "Content-Type: application/json" \
  -d "{\"data\":{\"type\":\"betaAppReviewSubmissions\",\"relationships\":{\"build\":{\"data\":{\"type\":\"builds\",\"id\":\"$BUILD_ID\"}}}}}" \
  "$API/betaAppReviewSubmissions")
HTTP=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')

if [ "$HTTP" = "201" ]; then
  echo "  betaReviewState: $(echo "$BODY" | jq -r '.data.attributes.betaReviewState // "unknown"')"
  echo "OK: submitted for Beta App Review."
  exit 0
fi

if [ "$(echo "$BODY" | jq -r '.errors[0].code // empty')" = "ENTITY_UNPROCESSABLE.SUBMISSION_LIMIT_REACHED" ]; then
  echo "  ⚠ Still rate-limited by Apple. The build stays \"Ready to Submit\" and"
  echo "    external testers don't have it. Try again later — the window is"
  echo "    rolling, and past builds cleared it within a day."
  exit 2
fi

echo "✗ HTTP $HTTP"
echo "$BODY" | head -20
exit 1
