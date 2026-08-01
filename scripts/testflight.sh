#!/bin/bash
# testflight.sh — archive Casberi and upload it to App Store Connect (TestFlight).
#
# One-time setup (App Store Connect → Users and Access → Integrations →
# App Store Connect API → generate a Team key with the "App Manager" role):
#   • download the AuthKey_XXXXXXXXXX.p8 (you only get to download it once)
#   • note the Key ID and the Issuer ID shown on that page
#
# Then run (fill these in, or export them in your shell profile):
#   ASC_KEY_ID=XXXXXXXXXX \
#   ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
#   ASC_KEY_PATH="$HOME/asc/AuthKey_XXXXXXXXXX.p8" \
#   scripts/testflight.sh
#
# Why the copy dance: the repo lives in iCloud Drive, whose xattrs make
# codesign fail ("resource fork … not allowed"). We build from a stripped
# local copy — the same reason the debug builds use a custom derivedData path.

set -euo pipefail

# --- config ---------------------------------------------------------------
SRC="$(cd "$(dirname "$0")/../Casberi" && pwd)"          # the .xcodeproj folder
WORK="$HOME/CasberiBuild"                                 # local, NON-iCloud
ARCHIVE="$WORK/Casberi.xcarchive"
EXPORT_DIR="$WORK/export"
EXPORT_OPTS="$(cd "$(dirname "$0")" && pwd)/exportOptions.plist"
DD="$HOME/Library/Developer/CasberiReleaseDD"

# --- checks ---------------------------------------------------------------
for v in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH; do
  if [ -z "${!v:-}" ]; then echo "✗ missing env var: $v (see the header of this script)"; exit 1; fi
done
[ -f "$ASC_KEY_PATH" ] || { echo "✗ key file not found: $ASC_KEY_PATH"; exit 1; }

# --- sweep abandoned keys -------------------------------------------------
# The staged `.p8` is the ONE real secret in this flow — it grants upload
# access to the App Store Connect account. This script deletes its own copy on
# the way out, but a ship that fails, is interrupted, or is killed mid-archive
# never gets there, and the key is left readable on disk indefinitely. Found
# 2026-08-01: THREE copies in /tmp, the oldest a day old, from earlier ships
# that never reached their own cleanup.
#
# Two guards make this safe to run while another ship is in flight (the key
# paths are build-unique precisely because concurrent sessions happen):
#   • never the key THIS run is using, whatever it's named;
#   • only files untouched for 2h — an archive+upload is ~10 min and the
#     public-beta handoff caps at 20 more, so 2h is a 4× margin over the
#     slowest real ship. A live session's key is minutes old and survives.
# Nothing is lost either way: the Keychain copy is the source of truth
# (`dev-keys.sh get-file asc-p8 …` re-stages it in a second).
# BOTH paths are resolved with `pwd -P`, and that is load-bearing on macOS,
# where /tmp is a symlink to /private/tmp. Two ways this bites, both found by
# testing the sweep against decoy files rather than trusting it (2026-08-01):
#   • `find /tmp …` descends nothing at all — find does not follow a symlinked
#     start point without -L, so the sweep was a silent no-op that would have
#     "worked" forever while deleting nothing;
#   • fixing only that half is WORSE than not fixing it: find would then emit
#     /private/tmp/asc-N.p8 while a logical `pwd` gave /tmp/asc-N.p8 for the
#     current key, the guard would fail to match, and the sweep would delete
#     the key of the ship running right now.
TMP_DIR="$(cd /tmp && pwd -P)"
CURRENT_KEY="$(cd "$(dirname "$ASC_KEY_PATH")" && pwd -P)/$(basename "$ASC_KEY_PATH")"
while IFS= read -r stale; do
  [ "$stale" = "$CURRENT_KEY" ] && continue
  rm -f "$stale" && echo "  swept abandoned key: $stale"
done < <(find "$TMP_DIR" -maxdepth 1 -name 'asc-*.p8' -mmin +120 2>/dev/null)

# --- build number ---------------------------------------------------------
# Bump the SOURCE pbxproj (all targets share one build number — App Store
# requires the extensions to match the app). We bump before staging so the
# local copy carries the new number; commit the bump so runs never collide.
# Set SKIP_BUMP=1 to reuse the current number (e.g. re-uploading a fix).
PBXPROJ="$SRC/Casberi.xcodeproj/project.pbxproj"
if [ "${SKIP_BUMP:-0}" != "1" ]; then
  CUR=$(grep -oE 'CURRENT_PROJECT_VERSION = [0-9]+' "$PBXPROJ" | grep -oE '[0-9]+' | sort -n | tail -1)
  NEW=$((CUR + 1))
  sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $NEW;/g" "$PBXPROJ"
  echo "▶ Build number: $CUR → $NEW  (commit the pbxproj change so it sticks)"
else
  echo "▶ Reusing current build number (SKIP_BUMP=1)"
fi

echo "▶ Staging a local copy (iCloud xattrs break codesign)"
rm -rf "$WORK"; mkdir -p "$WORK"
rsync -a --exclude '.git' --exclude 'build' "$SRC/" "$WORK/project/" >/dev/null
xattr -rc "$WORK/project" 2>/dev/null || true

# Archive UNSIGNED — the dev profile a signed archive wants needs a
# registered device; App Store signing happens at export instead (no
# device needed). Needs an ADMIN App Store Connect API key.
echo "▶ Archiving (Release, unsigned; signed for App Store at export)"
xcodebuild \
  -project "$WORK/project/Casberi.xcodeproj" \
  -scheme Casberi \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -derivedDataPath "$DD" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  archive

echo "▶ Exporting + uploading to App Store Connect"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTS" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

echo "✓ Uploaded. It appears in TestFlight after ~5–30 min of processing."
echo "  App Store Connect → Casberi → TestFlight → add yourself as an internal tester."
