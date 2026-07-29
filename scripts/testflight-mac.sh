#!/bin/bash
# testflight-mac.sh — archive Casberi's Mac Catalyst build and upload it to
# App Store Connect (TestFlight). Same credentials/setup as testflight.sh
# (see its header) — this is the macOS-platform sibling.
#
# Same app record, same CURRENT_PROJECT_VERSION counter as the iOS ship
# (App Store requires it to match across a platform's own extensions, and we
# keep ONE shared counter across both platforms for simplicity) — but a
# macOS build and an iOS build are separate ASC "platforms", so App Store
# Connect is fine with them sharing a number. We still bump by default so
# every ship (either platform) gets a fresh number and two ships never race.
#
# Usage: same env vars as testflight.sh:
#   ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=/tmp/asc.p8 \
#     scripts/testflight-mac.sh

set -euo pipefail

# --- config ---------------------------------------------------------------
SRC="$(cd "$(dirname "$0")/../Casberi" && pwd)"          # the .xcodeproj folder
WORK="$HOME/CasberiBuildMac"                               # local, NON-iCloud, separate from the iOS work dir
ARCHIVE="$WORK/Casberi.xcarchive"
EXPORT_DIR="$WORK/export"
EXPORT_OPTS="$(cd "$(dirname "$0")" && pwd)/exportOptions.plist"
DD="$HOME/Library/Developer/CasberiReleaseDDMac"

# --- checks ---------------------------------------------------------------
for v in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH; do
  if [ -z "${!v:-}" ]; then echo "✗ missing env var: $v (see testflight.sh's header)"; exit 1; fi
done
[ -f "$ASC_KEY_PATH" ] || { echo "✗ key file not found: $ASC_KEY_PATH"; exit 1; }

# --- build number ---------------------------------------------------------
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

# Archive SIGNED (automatic, local dev identity) — UNLIKE the iOS ship.
# The iOS unsigned-archive-then-sign-at-export trick loses the platform-
# conditional entitlements override here: exporting an unsigned Mac Catalyst
# archive re-signed with app-sandbox absent on all three binaries even though
# Casberi-Catalyst.entitlements/ShareExtension-Catalyst.entitlements/
# CasberiWidgets-Catalyst.entitlements all declare it (measured 2026-07-28,
# ASC rejected upload: "App sandbox not enabled" + missing application
# identifier in the re-signed binary). Signing at archive time embeds the
# entitlements the CODE_SIGN_ENTITLEMENTS[sdk=macosx*] override actually
# resolves to; export then re-signs for distribution but preserves them.
# No registered-device requirement for Mac Catalyst (unlike iOS), so this
# doesn't need the unsigned workaround the iOS script exists for.
echo "▶ Archiving (Release, Mac Catalyst, signed automatic)"
xcodebuild \
  -project "$WORK/project/Casberi.xcodeproj" \
  -scheme Casberi \
  -configuration Release \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' \
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

echo "✓ Uploaded. It appears in TestFlight (macOS platform) after ~5–30 min of processing."
