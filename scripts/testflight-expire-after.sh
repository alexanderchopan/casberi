#!/bin/bash
# The last step of a beta ship (user ruling 2026-10-04): once the new build
# is approved for testers, every older TestFlight build expires, so nobody
# keeps asking about a build that is long fixed.
#
# Waits up to 10 minutes for <build-id> to reach APPROVED (a build on an
# existing version auto-approves in a minute or two), then runs
# testflight-expire-old.py --yes either way. That script never expires the
# newest APPROVED build, so if this one is still in review the previous build
# stays installable and the next ship's run catches it.
#
# Usage (the ASC_* variables as for the public-beta scripts):
#   scripts/testflight-expire-after.sh <build-id>

set -uo pipefail

BUILD_ID="${1:?usage: testflight-expire-after.sh <build-id>}"
DIR="$(cd "$(dirname "$0")" && pwd)"
: "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}" "${ASC_KEY_PATH:?}"

echo "-- Waiting for build to be approved for testers, then expiring older builds..."
for i in $(seq 1 20); do
  STATE=$(curl -s -g -H "Authorization: Bearer $(python3 "$DIR/asc-jwt.py" "$ASC_KEY_ID" "$ASC_ISSUER_ID" "$ASC_KEY_PATH")" \
    "https://api.appstoreconnect.apple.com/v1/builds/$BUILD_ID/betaAppReviewSubmission" \
    | jq -r '.data.attributes.betaReviewState // "NONE"')
  echo "  [$i/20] betaReviewState: $STATE"
  [ "$STATE" = "APPROVED" ] && break
  [ "$STATE" = "REJECTED" ] && break
  sleep 30
done
[ "$STATE" = "APPROVED" ] || echo "  not approved yet — the previous approved build stays; the next ship expires it"

# Never fails the ship: the build is out either way.
python3 "$DIR/testflight-expire-old.py" --yes || echo "  ⚠ expiry failed; re-run scripts/testflight-expire-old.py --yes"
