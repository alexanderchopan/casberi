#!/bin/zsh
# Builds AztecDapp.app for the simulator with swiftc alone (no Xcode project).
set -e
cd "${0:A:h}"
APP=build/AztecDapp.app
rm -rf build && mkdir -p $APP
xcrun -sdk iphonesimulator swiftc -parse-as-library -O \
  -target arm64-apple-ios17.0-simulator \
  main.swift EngineServer.swift -o $APP/AztecDapp
cp Info.plist $APP/Info.plist
cp ../dist/relay.js $APP/
cp -R ../dist/engine $APP/Engine
codesign --force --sign - $APP >/dev/null 2>&1
echo "built $APP"
