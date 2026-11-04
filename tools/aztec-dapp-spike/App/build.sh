#!/bin/zsh
# Builds AztecDapp.app for the simulator with swiftc alone (no Xcode project).
set -e
cd "${0:A:h}"
APP=build/AztecDapp.app
rm -rf build && mkdir -p $APP build/obj
# Aztec's native prover: the v6 static library, plus libdeflate's seven gzip
# calls over the system zlib (deflate_shim.c). vendor/ comes from
# `gh release download v6.0.0 -R AztecProtocol/aztec-packages -p 'barretenberg-static-arm64-ios*'`.
mkdir -p build/obj
xcrun -sdk iphonesimulator clang -c -O2 -target arm64-apple-ios17.0-simulator deflate_shim.c -o build/obj/deflate_shim.o
xcrun -sdk iphonesimulator swiftc -parse-as-library -O \
  -target arm64-apple-ios17.0-simulator \
  -import-objc-header Bridging.h \
  main.swift EngineServer.swift Prover.swift AztecRoot.swift build/obj/deflate_shim.o \
  vendor/sim/libbb-external.a -lc++ -lz \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __entitlements -Xlinker Spike.entitlements \
  -o $APP/AztecDapp
cp Info.plist $APP/Info.plist
cp ../dist/relay.js $APP/
cp -R ../dist/engine $APP/Engine
codesign --force --sign - $APP >/dev/null 2>&1
echo "built $APP"
