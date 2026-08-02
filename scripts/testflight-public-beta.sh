#!/bin/bash
# Public Beta handoff — the second half of every ship, not just internal.
#
# Run this AFTER scripts/testflight.sh has uploaded a build. It:
#   1. Polls App Store Connect until the build finishes processing (VALID).
#   2. Sets the beta "What to Test" release notes (locale en-US).
#   3. Assigns the build to the "Casberi Public Beta" external group.
#   4. Submits it for Beta App Review.
#
# This is a STANDARD step of every ship (user ruling 2026-07-21) — never
# ship without it, and never wait to be asked. See docs/testflight-handoff.md.
#
# Usage:
#   ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=/tmp/asc.p8 \
#     scripts/testflight-public-beta.sh <build-version> "<release notes>"
#
# <release notes> is the tester-facing "What to Test" text — write it
# fresh each ship from `git log` since the last shipped build number, in
# plain tester language (not raw commit messages).

set -euo pipefail

VERSION="${1:?usage: testflight-public-beta.sh <build-version> <release-notes>}"
NOTES="${2:?usage: testflight-public-beta.sh <build-version> <release-notes>}"
BUNDLE_ID="com.casberi.app"
PUBLIC_BETA_GROUP_NAME="Casberi Public Beta"
API="https://api.appstoreconnect.apple.com/v1"
JWT_GEN="$(dirname "$0")/asc-jwt.py"

: "${ASC_KEY_ID:?ASC_KEY_ID not set}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID not set}"
: "${ASC_KEY_PATH:?ASC_KEY_PATH not set}"

jwt() { python3 "$JWT_GEN" "$ASC_KEY_ID" "$ASC_ISSUER_ID" "$ASC_KEY_PATH"; }

api() {
  # api <method> <path> [json-body]
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

# api_checked <method> <path> [json-body] -- same as api(), but FAILS LOUDLY
# (prints the response and exits 1) on anything but a 2xx status. Every call
# that mutates state (PATCH/POST/DELETE) must go through this, never api() —
# api()'s bare response was being piped to /dev/null with no status check,
# which is exactly how the release-notes bug shipped silently for 20+ builds.
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

echo "-- Waiting for build $VERSION to finish processing..."
# filter[preReleaseVersion.platform]=IOS is load-bearing now that Mac
# Catalyst ships from this same pbxproj's build-number counter: two
# platforms can legitimately claim the same version number (a race, same
# as the historical same-number iOS collisions), and an unfiltered lookup
# silently picked the Mac build once already -- setting release notes,
# beta-group assignment, and review submission all onto the wrong platform's
# build (2026-07-29). Do not drop this filter.
BUILD_ID=""
for i in $(seq 1 20); do
  RESP=$(api GET "/builds?filter%5Bapp%5D=$APP_ID&filter%5Bversion%5D=$VERSION&filter%5BpreReleaseVersion.platform%5D=IOS&fields%5Bbuilds%5D=version,processingState")
  STATE=$(echo "$RESP" | jq -r '.data[0].attributes.processingState // "NOT_FOUND"')
  BUILD_ID=$(echo "$RESP" | jq -r '.data[0].id // empty')
  echo "  [$i/20] state: $STATE"
  if [ "$STATE" = "VALID" ]; then break; fi
  if [ "$STATE" = "INVALID" ] || [ "$STATE" = "FAILED" ]; then
    echo "FAIL: build $VERSION processing ended in $STATE"; exit 1
  fi
  sleep 60
done
[ -n "$BUILD_ID" ] || { echo "FAIL: build $VERSION never appeared / never finished processing"; exit 1; }
echo "  build id: $BUILD_ID"

echo "-- Setting beta release notes..."
# NOTE: "filter[locale]" is NOT a valid query param on this nested endpoint
# (confirmed live: HTTP 400 PARAMETER_ERROR.ILLEGAL) -- fetch all localizations
# for the build (there's normally exactly one, auto-provisioned) and select
# en-US client-side with jq instead. The old code filtered server-side, got a
# 400 error body back, found no .data, and silently fell through to POST-
# creating a duplicate -- which conflicts with the auto-provisioned row and
# fails. That failure was invisible because the response went to /dev/null
# with no status check. Confirmed live 2026-07-24: builds 102-123 all show
# whatsNew: null despite this script printing "release notes set" every time.
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
# Verify by reading back -- trust nothing this script says about ASC state
# without a re-fetch, given the history above.
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
# NOT `api_checked` — this one call is allowed to fail without failing the
# ship (2026-07-30, ported from the Mac sibling script 2026-08-01). Apple
# rate-limits beta-review submissions across a rolling window, and once it
# trips, every later build lands "Ready to Submit": assigned to the group,
# notes written, but never sent for review, so external testers don't get it.
# Four builds went out that way before anyone noticed (183, 185, 203, 205),
# because `api_checked` aborted the script AFTER the assignment had already
# succeeded — the ship looked failed, so the one recoverable step nobody knew
# to retry.
#
# The submission is the ONLY thing missing at that point, and it re-runs
# standalone, so say exactly that and hand over the command instead of dying.
SUBMIT=$(api POST "/betaAppReviewSubmissions" \
  "{\"data\":{\"type\":\"betaAppReviewSubmissions\",\"relationships\":{\"build\":{\"data\":{\"type\":\"builds\",\"id\":\"$BUILD_ID\"}}}}}")
STATE=$(echo "$SUBMIT" | jq -r '.data.attributes.betaReviewState // empty')
CODE=$(echo "$SUBMIT" | jq -r '.errors[0].code // empty')
if [ -n "$STATE" ]; then
  echo "  betaReviewState: $STATE"
  echo "OK: Public Beta handoff complete for build $VERSION."
elif [ "$CODE" = "ENTITY_UNPROCESSABLE.SUBMISSION_LIMIT_REACHED" ]; then
  cat <<MSG
  ⚠ Apple's beta-review submission limit is reached — NOT submitted.
    Build $VERSION is uploaded, processed, has its notes, and is assigned to
    Casberi Public Beta. It shows "Ready to Submit" and external testers do
    NOT have it yet. The limit is a rolling window; retry later with:

      scripts/testflight-retry-review.sh $BUILD_ID

    (or press Submit for Review on the build in App Store Connect.)
MSG
else
  echo "  ⚠ Submission failed and was not rate-limited — build $VERSION is"
  echo "    assigned but NOT submitted. Response:"
  echo "$SUBMIT" | head -20
fi
