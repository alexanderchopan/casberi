#!/bin/bash
# Public Beta handoff — the macOS-platform sibling of testflight-public-beta.sh.
#
# That script now filters its build lookup to filter[preReleaseVersion.platform]=IOS
# (commit 77bf0b0, 2026-07-29) because Mac Catalyst ships share the same
# pbxproj CURRENT_PROJECT_VERSION counter as iOS: two platforms can legitimately
# claim the same version number, and an unfiltered lookup already picked the
# wrong platform's build once. This is the same script with MAC_OS instead —
# do not "unify" them by dropping the platform filter from either.
#
# Run this AFTER scripts/testflight-mac.sh has uploaded a build. It:
#   1. Polls App Store Connect until the MACOS build finishes processing (VALID).
#   2. Sets the beta "What to Test" release notes (locale en-US).
#   3. Assigns the build to the "Casberi Public Beta" external group.
#   4. Submits it for Beta App Review.
#
# Usage:
#   ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=/tmp/asc.p8 \
#     scripts/testflight-public-beta-mac.sh <build-version> "<release notes>"

set -euo pipefail

VERSION="${1:?usage: testflight-public-beta-mac.sh <build-version> <release-notes>}"
NOTES="${2:?usage: testflight-public-beta-mac.sh <build-version> <release-notes>}"
BUNDLE_ID="com.casberi.app"
PUBLIC_BETA_GROUP_NAME="Casberi Public Beta"
API="https://api.appstoreconnect.apple.com/v1"
JWT_GEN="$(dirname "$0")/asc-jwt.py"

: "${ASC_KEY_ID:?ASC_KEY_ID not set}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID not set}"
: "${ASC_KEY_PATH:?ASC_KEY_PATH not set}"

jwt() { python3 "$JWT_GEN" "$ASC_KEY_ID" "$ASC_ISSUER_ID" "$ASC_KEY_PATH"; }

api() {
  local method="$1" path="$2" body="${3:-}"
  if [ -n "$body" ]; then
    curl -s -g -X "$method" \
      -H "Authorization: Bearer $(jwt)" \
      -H "Content-Type: application/json" \
      -d "$body" \
      "$API$path"
  else
    curl -s -g -X "$method" \
      -H "Authorization: Bearer $(jwt)" \
      "$API$path"
  fi
}

api_checked() {
  local method="$1" path="$2" body="${3:-}" resp http
  if [ -n "$body" ]; then
    resp=$(curl -s -g -w $'\n%{http_code}' -X "$method" \
      -H "Authorization: Bearer $(jwt)" \
      -H "Content-Type: application/json" \
      -d "$body" \
      "$API$path")
  else
    resp=$(curl -s -g -w $'\n%{http_code}' -X "$method" \
      -H "Authorization: Bearer $(jwt)" \
      "$API$path")
  fi
  http=$(echo "$resp" | tail -1)
  resp=$(echo "$resp" | sed '$d')
  case "$http" in
    2??) echo "$resp" ;;
    *) echo "FAIL: $method $path -> HTTP $http" >&2; echo "$resp" >&2; exit 1 ;;
  esac
}

echo "-- Looking up app $BUNDLE_ID..."
APP_ID=$(api GET "/apps?filter%5BbundleId%5D=$BUNDLE_ID" | jq -r '.data[0].id')
[ -n "$APP_ID" ] && [ "$APP_ID" != "null" ] || { echo "FAIL: app not found"; exit 1; }
echo "  app id: $APP_ID"

echo "-- Looking up the $PUBLIC_BETA_GROUP_NAME group..."
GROUP_ID=$(api GET "/apps/$APP_ID/betaGroups?fields%5BbetaGroups%5D=name" \
  | jq -r --arg name "$PUBLIC_BETA_GROUP_NAME" '.data[] | select(.attributes.name == $name) | .id')
[ -n "$GROUP_ID" ] && [ "$GROUP_ID" != "null" ] || { echo "FAIL: beta group '$PUBLIC_BETA_GROUP_NAME' not found"; exit 1; }
echo "  group id: $GROUP_ID"

echo "-- Waiting for MAC_OS build $VERSION to finish processing..."
BUILD_ID=""
for i in $(seq 1 20); do
  RESP=$(api GET "/builds?filter%5Bapp%5D=$APP_ID&filter%5Bversion%5D=$VERSION&filter%5BpreReleaseVersion.platform%5D=MAC_OS&fields%5Bbuilds%5D=version,processingState")
  STATE=$(echo "$RESP" | jq -r '.data[0].attributes.processingState // "NOT_FOUND"')
  BUILD_ID=$(echo "$RESP" | jq -r '.data[0].id // empty')
  echo "  [$i/20] state: $STATE"
  if [ "$STATE" = "VALID" ]; then break; fi
  if [ "$STATE" = "INVALID" ] || [ "$STATE" = "FAILED" ]; then
    echo "FAIL: build $VERSION processing ended in $STATE"; exit 1
  fi
  sleep 60
done
[ -n "$BUILD_ID" ] || { echo "FAIL: MAC_OS build $VERSION never appeared / never finished processing"; exit 1; }
echo "  build id: $BUILD_ID"

echo "-- Setting beta release notes..."
LOC_RESP=$(api GET "/builds/$BUILD_ID/betaBuildLocalizations")
EXISTING_LOC=$(echo "$LOC_RESP" | jq -r '.data[] | select(.attributes.locale == "en-US") | .id' | head -1)
NOTES_JSON=$(jq -n --arg notes "$NOTES" '$notes')
if [ -n "$EXISTING_LOC" ]; then
  api_checked PATCH "/betaBuildLocalizations/$EXISTING_LOC" \
    "{\"data\":{\"type\":\"betaBuildLocalizations\",\"id\":\"$EXISTING_LOC\",\"attributes\":{\"whatsNew\":$NOTES_JSON}}}" > /dev/null
else
  api_checked POST "/betaBuildLocalizations" \
    "{\"data\":{\"type\":\"betaBuildLocalizations\",\"attributes\":{\"locale\":\"en-US\",\"whatsNew\":$NOTES_JSON},\"relationships\":{\"build\":{\"data\":{\"type\":\"builds\",\"id\":\"$BUILD_ID\"}}}}}" > /dev/null
fi
VERIFY=$(api GET "/builds/$BUILD_ID/betaBuildLocalizations" | jq -r '.data[] | select(.attributes.locale == "en-US") | .attributes.whatsNew')
[ "$VERIFY" = "$NOTES" ] || { echo "FAIL: release notes did not persist (readback mismatch)"; exit 1; }
echo "  OK: release notes set and verified"

echo "-- Assigning build to $PUBLIC_BETA_GROUP_NAME..."
HTTP=$(curl -s -g -o /dev/null -w "%{http_code}" -X POST \
  -H "Authorization: Bearer $(jwt)" \
  -H "Content-Type: application/json" \
  -d "{\"data\":[{\"type\":\"betaGroups\",\"id\":\"$GROUP_ID\"}]}" \
  "$API/builds/$BUILD_ID/relationships/betaGroups")
[ "$HTTP" = "204" ] || { echo "FAIL: group assignment failed (HTTP $HTTP)"; exit 1; }
echo "  OK: assigned"

echo "-- Submitting for Beta App Review..."
SUBMIT=$(api_checked POST "/betaAppReviewSubmissions" \
  "{\"data\":{\"type\":\"betaAppReviewSubmissions\",\"relationships\":{\"build\":{\"data\":{\"type\":\"builds\",\"id\":\"$BUILD_ID\"}}}}}")
STATE=$(echo "$SUBMIT" | jq -r '.data.attributes.betaReviewState // "unknown"')
echo "  betaReviewState: $STATE"
echo "OK: Public Beta handoff complete for MAC_OS build $VERSION."
