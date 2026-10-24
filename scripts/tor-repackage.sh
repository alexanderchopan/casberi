#!/bin/zsh
# tor-repackage.sh — rebuild Vendor/TorKit/tor.xcframework.zip (prd §1495).
#
# iCepa/Tor.framework ships tor as `tor-nolzma.xcframework`: STATIC archives
# wrapped in macOS-style deep framework bundles, 147 MB zipped. Xcode embeds a
# package's framework in the app and then refuses the deep layout on iOS
# ("expected Info.plist at the root level since the platform uses shallow
# bundles", build 2026-10-24), and the archive was never meant to be embedded.
# So this takes the release by its pinned checksum, lifts the archive out of
# the device slice and the simulator slice (arm64 only: every Mac here is
# Apple silicon), strips debug and local symbols, and wraps them as a LIBRARY
# xcframework, which is linked and never embedded — ~10 MB zipped, small
# enough to vendor like swift-secp256k1.
#
# Re-run to verify the vendored zip came from that release, or to move tor:
# change TAG and SUM, run, commit the zip, and update the versions in
# Vendor/TorKit/Package.swift and TorShim.h.
set -euo pipefail
cd "$(dirname "$0")/.."
TAG="v409.14.1"
SUM="3582f1ebaeeff3e0b7178de6ff536c54b61ca1b598332affd6631e34ecbdf531"
URL="https://github.com/iCepa/Tor.framework/releases/download/$TAG/tor-nolzma.xcframework.zip"
OUT="$PWD/Vendor/TorKit/tor.xcframework.zip"

WORK=$(mktemp -d /tmp/tor-repackage.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
echo "tor-repackage: $TAG"
curl -fsSL -o "$WORK/release.zip" "$URL"
echo "$SUM  $WORK/release.zip" | shasum -a 256 -c - >/dev/null \
  || { echo "✗ checksum mismatch for $URL"; exit 1; }
unzip -q "$WORK/release.zip" -d "$WORK/x"
X="$WORK/x/tor-nolzma.xcframework"
mkdir -p "$WORK/ios" "$WORK/sim"
cp "$X/ios-arm64/tor-nolzma.framework/tor-nolzma" "$WORK/ios/libtor.a"
lipo "$X/ios-arm64_x86_64-simulator/tor-nolzma.framework/tor-nolzma" -thin arm64 -output "$WORK/sim/libtor.a"
strip -S -x "$WORK/ios/libtor.a" "$WORK/sim/libtor.a"
xcodebuild -create-xcframework \
  -library "$WORK/ios/libtor.a" -library "$WORK/sim/libtor.a" \
  -output "$WORK/tor.xcframework" >/dev/null
(cd "$WORK" && zip -qry -X tor.xcframework.zip tor.xcframework)
mv "$WORK/tor.xcframework.zip" "$OUT"
echo "  ok   $OUT ($(du -h "$OUT" | cut -f1))"
