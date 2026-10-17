#!/bin/zsh
# Downloads Aztec's official iOS prover libraries (barretenberg, static, arm64)
# for the version the web half pins, into App/vendor/{ios,sim}.
set -euo pipefail
cd "${0:A:h}/.."
VERSION="v$(node -p 'require("./web/package.json").dependencies["@aztec/aztec.js"]')"
tmp=$(mktemp -d)
gh release download "$VERSION" -R AztecProtocol/aztec-packages -D "$tmp" \
  -p 'barretenberg-static-arm64-ios.tar.gz' -p 'barretenberg-static-arm64-ios-sim.tar.gz'
mkdir -p App/vendor/ios App/vendor/sim
tar xzf "$tmp/barretenberg-static-arm64-ios.tar.gz" -C App/vendor/ios
tar xzf "$tmp/barretenberg-static-arm64-ios-sim.tar.gz" -C App/vendor/sim
rm -rf "$tmp"
echo "prover $VERSION → App/vendor"
