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

VERSION="" PLATFORM="IOS" BUILD="" DRY=0 NOSUB=0
while [ $# -gt 0 ]; do
  case "$1" in
    --version)  VERSION="$2"; shift 2 ;;
    --platform) PLATFORM="$2"; shift 2 ;;
    --build)    BUILD="$2"; shift 2 ;;
    --dry-run)  DRY=1; shift ;;
    # Swap the build and STOP, leaving the version editable and unsubmitted.
    # For the case this script otherwise cannot serve: replacing the build on
    # a version you are not ready to send back yet — new screenshots, changed
    # copy, anything reviewed alongside the binary. Without it the only way to
    # get a newer build onto a waiting version is to resubmit with whatever
    # metadata happens to be attached.
    --no-submit) NOSUB=1; shift ;;
    *) echo "✗ unknown argument: $1"; exit 1 ;;
  esac
done
[ -n "$VERSION" ] || { echo "✗ --version required (e.g. 1.0.5)"; exit 1; }
[ -n "$BUILD" ]   || { echo "✗ --build required (e.g. 311)"; exit 1; }

T="$(jwt)"

# A submission for this platform that's READY_FOR_REVIEW and has no
# submittedDate yet — the shape of both a submission this run just created
# and a STRANDED one left behind by an earlier run that died partway through
# step 5 below. Used twice: once so a re-run doesn't report "nothing to
# swap" and walk away from an unfinished submission (the build already
# matches, so step 1's early exit would otherwise never look further), and
# once inside step 5 itself so a retried create can't produce a duplicate.
review_submission_id() {
  curl -fsS -H "Authorization: Bearer $T" \
    "$API/apps/$APP_ID/reviewSubmissions?filter%5Bplatform%5D=$PLATFORM&filter%5Bstate%5D=READY_FOR_REVIEW&limit=10" \
    | jq_ "
d=json.load(sys.stdin).get('data',[]);
hits=[x['id'] for x in d if x['attributes'].get('submittedDate') is None];
print(hits[0] if hits else '')
"
}

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

STRANDED_SUB=""
if [ "$CUR" = "$BUILD" ]; then
  STRANDED_SUB="$(review_submission_id)"
  if [ -z "$STRANDED_SUB" ]; then
    echo "✓ already on build $BUILD — nothing to swap"
    exit 0
  fi
  # The build already matches, so nothing above needs doing — but a prior
  # run's step 5 (further down) got the build attached and then died before
  # finishing the resubmit, leaving this. Left alone it sits forever: every
  # future run of this command hits this same early branch and reports
  # "nothing to swap" without ever looking at it.
  echo "  build matches, but found an unfinished review submission"
  echo "  ($STRANDED_SUB) — finishing it instead of leaving it stuck."
  [ "$DRY" = "1" ] && { echo "— dry run, nothing changed —"; exit 0; }
fi

if [ -z "$STRANDED_SUB" ]; then
  # ── 2 · the replacement build must exist and be usable ────────────────────
  BJSON="$(curl -fsS -H "Authorization: Bearer $T" \
    "$API/builds?filter%5Bapp%5D=$APP_ID&filter%5Bversion%5D=$BUILD&filter%5BpreReleaseVersion.platform%5D=$PLATFORM&limit=1")"
  BUILD_ID="$(printf '%s' "$BJSON" | jq_ "d=json.load(sys.stdin)['data']; print(d[0]['id'] if d else '')")"
  BUILD_STATE="$(printf '%s' "$BJSON" | jq_ "d=json.load(sys.stdin)['data']; print(d[0]['attributes'].get('processingState','?') if d else '')")"
  [ -n "$BUILD_ID" ] || { echo "✗ no $PLATFORM build $BUILD found — has it finished uploading?"; exit 1; }
  echo "target    build $BUILD — $BUILD_STATE  ($BUILD_ID)"
  [ "$BUILD_STATE" = "VALID" ] || { echo "✗ build $BUILD is $BUILD_STATE, not VALID — wait for processing"; exit 1; }

  # ── 3 · the open review submission, which blocks the swap ─────────────────
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
  #
  # RETRIED, because cancelling is not instant (measured 2026-08-12, build 311).
  # The cancel above returns 200 while the version is still leaving
  # WAITING_FOR_REVIEW, and a PATCH issued into that window answers **409
  # Conflict** — which reads as "this version cannot take a new build" when it
  # actually means "ask again in a moment". The version settles to
  # DEVELOPER_REJECTED and the identical call then returns 204.
  #
  # This is the worst place in the script to fail, which is why it retries rather
  # than reporting: the queue position is already forfeited by the line above, so
  # an abort here leaves the version cancelled AND still carrying the old build —
  # the one state that is worse than either doing nothing or finishing.
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    CODE="$(curl -s -o /dev/null -w '%{http_code}' -X PATCH \
      -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
      -d "{\"data\":{\"type\":\"builds\",\"id\":\"$BUILD_ID\"}}" \
      "$API/appStoreVersions/$VER_ID/relationships/build")"
    [ "$CODE" = "204" ] && break
    if [ "$CODE" != "409" ]; then
      echo "✗ could not attach build $BUILD (HTTP $CODE)"
      echo "  the submission IS cancelled — re-run this command once the version"
      echo "  shows DEVELOPER_REJECTED to finish the swap."
      exit 1
    fi
    [ "$attempt" = "10" ] && { echo "✗ still 409 after 10 tries — see the note above"; exit 1; }
    echo "  409 — version still transitioning, retrying ($attempt)"
    sleep 6
  done
  echo "✓ $PLATFORM $VERSION now carries build $BUILD"

  if [ "$NOSUB" = "1" ]; then
    echo ""
    echo "— --no-submit: stopping here, the version is NOT back in review —"
    echo "  It carries build $BUILD and is editable. Finish the metadata, then"
    echo "  submit from App Store Connect (or re-run this without --no-submit)."
    exit 0
  fi
fi

# ── 5 · resubmit — the reviewSubmissions pair, NOT appStoreVersionSubmissions ─
#
# RETRIED AND VERIFIED-BEFORE-RETRIED, unlike step 4 above which can simply
# resend an idempotent PATCH. These three calls are not all idempotent, so a
# bare retry loop here would risk the failure it exists to prevent.
#
# Shipped without any of this once (2026-08-29, build 446): a bare
# `curl -fsS` on each of the three calls under `set -euo pipefail`. The
# create POST answered 409 Conflict, curl aborted the whole script, and the
# investigation afterward found the object HAD been created server-side — a
# reviewSubmission sitting in READY_FOR_REVIEW with zero items and
# submittedDate null. Re-running the script did nothing: step 1's "already
# on build $BUILD — nothing to swap" fires before this section is ever
# reached, so the stranded submission would have sat there forever. That
# early exit now checks for exactly this shape first (see STRANDED_SUB
# above).
#
# So each call below CHECKS for the effect it's trying to have before
# deciding a 409 means "try again" — a blind resend of a POST that actually
# landed would create a duplicate submission or double-attach a version,
# which is worse than the stall this replaces.
if [ -n "$STRANDED_SUB" ]; then
  NEW_SUB="$STRANDED_SUB"
else
  NEW_SUB="$(review_submission_id)"
fi

if [ -n "$NEW_SUB" ]; then
  echo "review sub $NEW_SUB (existing, unsubmitted) — finishing it"
else
  BODY="$(mktemp)"
  CODE="$(curl -s -o "$BODY" -w '%{http_code}' -X POST -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
    -d "{\"data\":{\"type\":\"reviewSubmissions\",\"attributes\":{\"platform\":\"$PLATFORM\"},\"relationships\":{\"app\":{\"data\":{\"type\":\"apps\",\"id\":\"$APP_ID\"}}}}}" \
    "$API/reviewSubmissions")"
  if [ "$CODE" = "200" ] || [ "$CODE" = "201" ]; then
    NEW_SUB="$(jq_ "print(json.load(sys.stdin)['data']['id'])" < "$BODY")"
    echo "review sub $NEW_SUB (created)"
  elif [ "$CODE" = "409" ]; then
    echo "  create-submission answered 409 — checking whether it landed anyway"
    sleep 3
    NEW_SUB="$(review_submission_id)"
    if [ -z "$NEW_SUB" ]; then
      echo "✗ create-submission 409'd and no submission appeared — re-run this command"
      rm -f "$BODY"; exit 1
    fi
    echo "  it did: $NEW_SUB"
  else
    echo "✗ create-submission failed (HTTP $CODE)"; cat "$BODY"; rm -f "$BODY"; exit 1
  fi
  rm -f "$BODY"
fi

item_attached() {
  curl -fsS -H "Authorization: Bearer $T" "$API/reviewSubmissions/$NEW_SUB/items" 2>/dev/null \
    | jq_ "
d=json.load(sys.stdin).get('data',[]);
vers=[i.get('relationships',{}).get('appStoreVersion',{}).get('data',{}).get('id') for i in d];
print('yes' if '$VER_ID' in vers else 'no')
" 2>/dev/null
}

if [ "$(item_attached)" = "yes" ]; then
  echo "  version already attached to $NEW_SUB"
else
  for attempt in 1 2 3; do
    CODE="$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
      -d "{\"data\":{\"type\":\"reviewSubmissionItems\",\"relationships\":{\"reviewSubmission\":{\"data\":{\"type\":\"reviewSubmissions\",\"id\":\"$NEW_SUB\"}},\"appStoreVersion\":{\"data\":{\"type\":\"appStoreVersions\",\"id\":\"$VER_ID\"}}}}}" \
      "$API/reviewSubmissionItems")"
    [ "$CODE" = "201" ] && break
    if [ "$CODE" != "409" ]; then echo "✗ attach-item failed (HTTP $CODE)"; exit 1; fi
    if [ "$(item_attached)" = "yes" ]; then
      echo "  409, but it's actually attached — continuing"
      break
    fi
    [ "$attempt" = "3" ] && { echo "✗ attach-item still 409 after 3 tries"; exit 1; }
    echo "  409 attaching the version, retrying ($attempt)"
    sleep 5
  done
fi

submission_submitted() {
  curl -fsS -H "Authorization: Bearer $T" "$API/reviewSubmissions/$NEW_SUB" 2>/dev/null \
    | jq_ "a=json.load(sys.stdin)['data']['attributes']; print('yes' if a.get('submittedDate') else 'no')" 2>/dev/null
}

if [ "$(submission_submitted)" = "yes" ]; then
  echo "  already marked submitted"
else
  for attempt in 1 2 3; do
    CODE="$(curl -s -o /dev/null -w '%{http_code}' -X PATCH -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
      -d "{\"data\":{\"type\":\"reviewSubmissions\",\"id\":\"$NEW_SUB\",\"attributes\":{\"submitted\":true}}}" \
      "$API/reviewSubmissions/$NEW_SUB")"
    { [ "$CODE" = "200" ] || [ "$CODE" = "204" ]; } && break
    if [ "$CODE" != "409" ]; then echo "✗ submit failed (HTTP $CODE)"; exit 1; fi
    if [ "$(submission_submitted)" = "yes" ]; then
      echo "  409, but it's actually submitted — continuing"
      break
    fi
    [ "$attempt" = "3" ] && { echo "✗ submit still 409 after 3 tries"; exit 1; }
    echo "  409 submitting, retrying ($attempt)"
    sleep 5
  done
fi
echo "✓ resubmitted for review ($NEW_SUB)"

FINAL="$(curl -fsS -H "Authorization: Bearer $T" "$API/appStoreVersions/$VER_ID" \
  | jq_ "print(json.load(sys.stdin)['data']['attributes']['appStoreState'])")"
echo "state     $PLATFORM $VERSION — $FINAL"
