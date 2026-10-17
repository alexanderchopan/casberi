#!/bin/zsh
# Builds the spike for a connected iPhone, installs it and runs it with the
# console attached, so every timing line lands here and in results.log.
#
#   scripts/run-on-phone.sh                 open the app; tap the steps yourself
#   scripts/run-on-phone.sh --all           run every step at launch
#   scripts/run-on-phone.sh --all --wasm    the same with bb.js's WebAssembly prover
#
# The first run registers com.casberi.aztecspike under the team (automatic
# signing). The phone must be unlocked for the launch.
set -euo pipefail
cd "${0:A:h}/.."
root=$(git rev-parse --show-toplevel)
[[ -f App/vendor/ios/libbb-external.a ]] || scripts/fetch-prover.sh
[[ -d web/node_modules ]] || (cd web && npm install --no-audit --no-fund)
(cd web && npm run build >/dev/null)

device=$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && /available/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]+-[0-9A-F]+$/) { print $i; exit } }')
[[ -n "$device" ]] || { echo "no iPhone connected (plug it in, or pair it in Xcode › Devices)"; exit 1; }

dd="${TMPDIR:-/tmp}/aztec-spike-device-dd"
"$root/scripts/xcb.sh" -project App/AztecSpike.xcodeproj -scheme AztecSpike -configuration Release \
  -destination "id=$device" -derivedDataPath "$dd" -allowProvisioningUpdates build | tail -3
xcrun devicectl device install app --device "$device" "$dd/Build/Products/Release-iphoneos/AztecSpike.app" >/dev/null

typeset -a launch
for a in "$@"; do
  [[ $a == --all ]] && launch+=(-autorun YES)
  [[ $a == --wasm ]] && launch+=(-prover wasm)
done
echo "running on $device — results also in results.log"
xcrun devicectl device process launch --device "$device" --console --terminate-existing \
  com.casberi.aztecspike -- $launch 2>&1 | grep --line-buffered '\[spike\]' | tee -a results.log
