#!/bin/zsh
# TDLib, Telegram's own client library, for the Telegram messages seat.
#
# Built from Telegram's source at a PINNED commit into a Mac-wide cache and
# linked into the tree as Vendor/TDLib/TDJSON.xcframework (gitignored). Never
# committed: the repo is public and the library is ~100 MB a version.
#
#   scripts/tdlib.sh           build if the cache lacks this commit (~1h once,
#                              then instant), link it, write the app id header
#   scripts/tdlib.sh --check   exit 1 unless the framework is linked here
#
# One static library per slice (device, simulator, Mac Catalyst), TDLib and
# OpenSSL merged, with a module map so Swift says `import TDJSON` and links
# libc++ and zlib on its own.
#
# The app id: Telegram issues it per app, and a leaked one that gets abused
# is banned for every install, so it never enters git. It is read from the
# login Keychain (`dev-keys.sh`, `telegram-api-id`/`telegram-api-hash`) into
# a header inside the framework on every run. Absent, the header says 0 and
# the seat says it cannot sign in, rather than failing to build.
set -euo pipefail

TDLIB_COMMIT=4c6377aa7386c39217878a9a56d581922ad37ca4
# Upstream's own OpenSSL recipe pin (td/example/ios/build-openssl.sh).
MIN_IOS=18.0
JOBS=${TDLIB_JOBS:-4}

REPO=$(cd "$(dirname "$0")/.." && pwd)
CACHE=${TDLIB_CACHE:-$HOME/Library/Caches/casberi/tdlib}/$TDLIB_COMMIT
SRC=$CACHE/src
XCF=$CACHE/TDJSON.xcframework
LINK=$REPO/Vendor/TDLib/TDJSON.xcframework

if [[ ${1:-} == --check ]]; then
  [[ -e $LINK/Info.plist ]] && exit 0
  echo "tdlib: Vendor/TDLib/TDJSON.xcframework is missing — run scripts/tdlib.sh" >&2
  exit 1
fi

say() { print -r -- "tdlib: $*"; }

# MARK: source

fetch_source() {
  [[ -d $SRC/.git ]] && [[ $(git -C $SRC rev-parse HEAD) == $TDLIB_COMMIT ]] && return
  rm -rf $SRC; mkdir -p $SRC
  git -C $SRC init -q
  git -C $SRC remote add origin https://github.com/tdlib/td.git
  git -C $SRC fetch -q --depth 1 origin $TDLIB_COMMIT
  git -C $SRC checkout -q FETCH_HEAD
}

generate_sources() {
  [[ -f $SRC/td/generate/auto/td/telegram/td_api.h ]] && return
  say "generating sources"
  cmake -S $SRC -B $SRC/native-build -DTD_GENERATE_SOURCE_FILES=ON > /dev/null
  cmake --build $SRC/native-build -j $JOBS > /dev/null
}

# MARK: OpenSSL

# Device and simulator through upstream's recipe (Python-Apple-support at its
# pin), iOS only rather than its five platforms.
openssl_ios() {
  [[ -f $SRC/example/ios/third_party/openssl/iOS-simulator/lib/libcrypto.a ]] && return
  say "building OpenSSL for iOS"
  cd $SRC/example/ios
  sed 's/^platforms=.*/platforms="iOS"/' build-openssl.sh > build-openssl-ios.sh
  chmod +x build-openssl-ios.sh
  rm -rf Python-Apple-support
  ./build-openssl-ios.sh > $CACHE/openssl-ios.log 2>&1
  cd $REPO
}

# Mac Catalyst has no upstream recipe: the same OpenSSL tarball, configured
# for each Mac arch with a macabi target, then made fat.
openssl_catalyst() {
  local out=$SRC/example/ios/third_party/openssl/catalyst
  [[ -f $out/lib/libcrypto.a ]] && return
  say "building OpenSSL for Mac Catalyst"
  local tarball=($SRC/example/ios/Python-Apple-support/downloads/openssl-*.tar.gz)
  local sdk=$(xcrun --sdk macosx --show-sdk-path)
  local arch work
  for arch in arm64 x86_64; do
    work=$CACHE/openssl-catalyst-$arch
    rm -rf $work; mkdir -p $work
    tar -xzf $tarball[1] -C $work --strip-components 1
    (cd $work && CC="xcrun --sdk macosx clang" \
      CFLAGS="-target $arch-apple-ios$MIN_IOS-macabi -isysroot $sdk" \
      ./Configure darwin64-$arch-cc no-shared no-tests no-module \
        --prefix=$work/install > $work/configure.log 2>&1 &&
      make -j $JOBS build_libs > $work/make.log 2>&1)
  done
  mkdir -p $out/lib $out/include
  for lib in libssl libcrypto; do
    lipo -create $CACHE/openssl-catalyst-{arm64,x86_64}/$lib.a -output $out/lib/$lib.a
  done
  cp -R $CACHE/openssl-catalyst-arm64/include/openssl $out/include/
}

# MARK: TDLib

# $1 slice name, $2 OpenSSL dir, then cmake options for the platform.
build_slice() {
  local slice=$1 ssl=$2; shift 2
  local build=$CACHE/build-$slice
  [[ -f $CACHE/out/$slice/libTDJSON.a ]] && return
  say "building TDLib for $slice (the long part)"
  cmake -S $SRC -B $build -DCMAKE_BUILD_TYPE=Release \
    -DOPENSSL_FOUND=1 -DOPENSSL_INCLUDE_DIR=$ssl/include \
    -DOPENSSL_CRYPTO_LIBRARY=$ssl/lib/libcrypto.a -DOPENSSL_SSL_LIBRARY=$ssl/lib/libssl.a \
    -DOPENSSL_LIBRARIES="$ssl/lib/libcrypto.a;$ssl/lib/libssl.a" \
    "$@" > $CACHE/cmake-$slice.log 2>&1
  ZERO_AR_DATE=1 cmake --build $build --target tdjson_static -j $JOBS > $CACHE/build-$slice.log 2>&1
  # Every library the static target pulls in, the generators' own excepted,
  # merged with OpenSSL into one archive.
  local libs=(${(f)"$(find $build -name '*.a' ! -name 'libtdtl.a' ! -name 'libtl_writer_cpp.a')"})
  mkdir -p $CACHE/out/$slice
  libtool -static -no_warning_for_no_symbols -o $CACHE/out/$slice/libTDJSON.a \
    $libs $ssl/lib/libssl.a $ssl/lib/libcrypto.a
}

# OpenSSL's simulator and Catalyst libraries are fat, so a slice's merge is
# too, with the other arch's half holding OpenSSL alone: keep the arch TDLib
# was built for.
thin() {
  local lib=$1 arch=$2
  [[ $(lipo -archs $lib) == $arch ]] && return
  lipo $lib -thin $arch -output $lib.thin && mv $lib.thin $lib
}

build_all() {
  local ios=$SRC/example/ios/third_party/openssl
  local toolchain=$SRC/CMake/iOS.cmake
  build_slice ios $ios/iOS -DCMAKE_TOOLCHAIN_FILE=$toolchain \
    -DIOS_PLATFORM=OS -DIOS_DEPLOYMENT_TARGET=$MIN_IOS
  # arm64 only: every simulator here runs on Apple silicon.
  build_slice ios-simulator $ios/iOS-simulator -DCMAKE_TOOLCHAIN_FILE=$toolchain \
    -DIOS_PLATFORM=SIMULATOR -DIOS_ARCH=arm64 -DIOS_DEPLOYMENT_TARGET=$MIN_IOS
  thin $CACHE/out/ios-simulator/libTDJSON.a arm64
  local arch
  # SQLite's proxy locking calls `gethostuuid`, which Catalyst does not have.
  # A named system makes it a cross-compile, so TDLib uses the generated
  # sources instead of running an x86_64 generator on an arm64 host.
  for arch in arm64 x86_64; do
    build_slice catalyst-$arch $ios/catalyst \
      -DCMAKE_OSX_SYSROOT=macosx -DCMAKE_OSX_ARCHITECTURES=$arch \
      -DCMAKE_SYSTEM_NAME=Darwin -DCMAKE_SYSTEM_PROCESSOR=$arch \
      "-DCMAKE_C_FLAGS=-target $arch-apple-ios$MIN_IOS-macabi -DHAVE_GETHOSTUUID=0" \
      "-DCMAKE_CXX_FLAGS=-target $arch-apple-ios$MIN_IOS-macabi"
    thin $CACHE/out/catalyst-$arch/libTDJSON.a $arch
  done
  if [[ ! -f $CACHE/out/catalyst/libTDJSON.a ]]; then
    mkdir -p $CACHE/out/catalyst
    lipo -create $CACHE/out/catalyst-{arm64,x86_64}/libTDJSON.a -output $CACHE/out/catalyst/libTDJSON.a
  fi
}

# MARK: framework

headers() {
  local dir=$CACHE/headers/TDJSON
  rm -rf $CACHE/headers; mkdir -p $dir
  # Flattened: the client header names its export header by its source path.
  sed 's|#include "td/telegram/tdjson_export.h"|#include "tdjson_export.h"|' \
    $SRC/td/telegram/td_json_client.h > $dir/td_json_client.h
  cp $CACHE/build-ios/td/telegram/tdjson_export.h $dir/
  : > $dir/casberi_telegram_app.h
  cat > $dir/module.modulemap <<'EOF'
module TDJSON {
  header "td_json_client.h"
  header "casberi_telegram_app.h"
  link "c++"
  link "z"
  export *
}
EOF
}

assemble() {
  [[ -e $XCF/Info.plist ]] && return
  headers
  rm -rf $XCF
  xcodebuild -create-xcframework \
    -library $CACHE/out/ios/libTDJSON.a -headers $CACHE/headers \
    -library $CACHE/out/ios-simulator/libTDJSON.a -headers $CACHE/headers \
    -library $CACHE/out/catalyst/libTDJSON.a -headers $CACHE/headers \
    -output $XCF > /dev/null
}

# Written on every run, so a key stored after the build still lands. Values
# reach the file through command substitution only, never this terminal.
app_id_header() {
  local h
  local id=0 hash=""
  # Both, or neither: a half-stored pair must not stop every build here.
  local stored=$("$REPO/scripts/dev-keys.sh" list 2>/dev/null || true)
  if print -r -- $stored | grep -qx telegram-api-id && print -r -- $stored | grep -qx telegram-api-hash; then
    id=$("$REPO/scripts/dev-keys.sh" get telegram-api-id)
    hash=$("$REPO/scripts/dev-keys.sh" get telegram-api-hash)
  fi
  for h in $XCF/*/Headers/TDJSON/casberi_telegram_app.h; do
    {
      print -r -- "// Written by scripts/tdlib.sh from the login Keychain. Never commit."
      print -r -- "#define CASBERI_TELEGRAM_API_ID $id"
      print -r -- "#define CASBERI_TELEGRAM_API_HASH \"$hash\""
    } > $h.new
    cmp -s $h.new $h && rm $h.new || mv $h.new $h
  done
  [[ $id == 0 ]] && say "no telegram-api-id in the Keychain; the seat will not sign in"
  return 0
}

if [[ ! -e $XCF/Info.plist ]]; then
  for tool in cmake gperf; do
    command -v $tool > /dev/null || { say "needs $tool (brew install $tool)"; exit 1; }
  done
  mkdir -p $CACHE
  fetch_source
  generate_sources
  openssl_ios
  openssl_catalyst
  build_all
  assemble
fi
mkdir -p ${LINK:h}
ln -sfn $XCF $LINK
app_id_header
say "linked $(du -sh $XCF/ios-arm64/libTDJSON.a | cut -f1) device library at commit ${TDLIB_COMMIT:0:7}"
