#!/bin/zsh
# Builds the Aztec dApp spike for the paired iPhone, installs it and runs the
# private-send flow with the console attached; every `aztecDapp|` line lands
# here and in results.log. The test app's page is bundled and served by the app
# itself (127.0.0.1:8489), so the phone needs no Mac on the network.
#
#   Device/run.sh            approve each sheet by hand on the phone
#   Device/run.sh --auto     -autoApprove YES (unattended)
#   Device/run.sh --wasm     bb.js's WebAssembly prover, to compare
set -euo pipefail
cd "${0:A:h}"
root=$(git rev-parse --show-toplevel)
spike=..
[[ -f $spike/App/vendor/ios/libbb-external.a ]] || { echo "fetch the prover: see ../README.md (round four)"; exit 1; }

# Stage what the synced group and the Bundle folder hold (generated, not committed).
rm -rf AztecDapp Bundle && mkdir -p AztecDapp Bundle/Dapp
cp $spike/App/main.swift AztecDapp/AztecDappApp.swift && cp $spike/App/EngineServer.swift $spike/App/Prover.swift $spike/App/AztecRoot.swift \
   $spike/App/Bridging.h $spike/App/deflate_shim.c AztecDapp/  # main.swift is renamed: in Xcode that name means top-level code
cat > AztecDapp/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
cp -R $spike/dist/engine Bundle/Engine
cp $spike/dist/relay.js Bundle/
cp $spike/dist/ios.html $spike/dist/dapp.js Bundle/Dapp/
mkdir -p vendor && rm -rf vendor/ios && cp -R $spike/App/vendor/ios vendor/ios

device=$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && /available/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]+-[0-9A-F]+$/) { print $i; exit } }')
[[ -n "$device" ]] || { echo "no iPhone available (unlock it, or pair it in Xcode › Devices)"; exit 1; }

dd="${TMPDIR:-/tmp}/aztec-dapp-device-dd"
"$root/scripts/xcb.sh" -project AztecDapp.xcodeproj -scheme AztecDapp -configuration Release \
  -destination "id=$device" -derivedDataPath "$dd" -allowProvisioningUpdates build 2>&1 | tail -3
xcrun devicectl device install app --device "$device" "$dd/Build/Products/Release-iphoneos/AztecDapp.app" >/dev/null

typeset -a launch
for a in "$@"; do
  [[ $a == --auto ]] && launch+=(-autoApprove YES)
  [[ $a == --wasm ]] && launch+=(-url "http://127.0.0.1:8489/ios.html?auto=send&prover=wasm")
done
echo "running on $device — results also in results.log"
[[ ${BUILD_ONLY:-0} == 1 ]] && exit 0
xcrun devicectl device process launch --device "$device" --console --terminate-existing \
  com.casberi.aztecdapp -- $launch 2>&1 | grep --line-buffered 'aztecDapp|' | tee -a results.log
