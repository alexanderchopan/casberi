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

echo "▶ Staging a local copy (iCloud xattrs break codesign)"
rm -rf "$WORK"; mkdir -p "$WORK"
rsync -a --exclude '.git' --exclude 'build' "$SRC/" "$WORK/project/" >/dev/null
xattr -rc "$WORK/project" 2>/dev/null || true

echo "▶ Archiving (Release, App Store distribution)"
xcodebuild \
  -project "$WORK/project/Casberi.xcodeproj" \
  -scheme Casberi \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -derivedDataPath "$DD" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
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
