#!/bin/zsh
# Makes sure a build has your Aztec account's engine (prd §1700):
#   - Aztec's native iOS prover, the official v6 static libraries, downloaded
#     from Aztec's GitHub release into Casberi/vendor/aztec/{ios,sim};
#   - the engine page, built from tools/aztec-engine into Casberi/AztecEngine.
# Neither is committed (72 MB and 57 MB). scripts/xcb.sh runs `ensure` before
# every build; it does nothing when both are current.
#
#   scripts/aztec-engine.sh ensure     fetch / build what is missing or stale
#   scripts/aztec-engine.sh --self-test
set -euo pipefail
cd "${0:A:h}/.."
VERSION=v6.0.0
BASE="https://github.com/AztecProtocol/aztec-packages/releases/download/$VERSION"
VENDOR=Casberi/vendor/aztec
ENGINE=Casberi/AztecEngine
SRC=tools/aztec-engine

stamp() { # what the engine build is made from
  # Shield's interfaces are there only once fetched: no match is no input,
  # never zsh's "no matches found" (which failed the self-test's bare copy).
  local shield=($SRC/shield/*.json(N))
  { cat $SRC/package-lock.json $SRC/vite.config.js $SRC/index.html; cat $SRC/src/*.js; (( $#shield )) && cat $shield; true; } | shasum -a 256 | cut -c1-16
}

ensure_prover() {
  local slice
  for slice in ios sim; do
    local dir=$VENDOR/$slice
    [[ -f $dir/libbb-external.a && "$(cat $dir/VERSION 2>/dev/null)" == $VERSION ]] && continue
    local name=barretenberg-static-arm64-ios.tar.gz
    [[ $slice == sim ]] && name=barretenberg-static-arm64-ios-sim.tar.gz
    print -u2 "aztec-engine: fetching Aztec's $slice prover ($VERSION)"
    rm -rf $dir && mkdir -p $dir
    curl -fsSL "$BASE/$name" | tar xz -C $dir
    [[ -f $dir/libbb-external.a ]] || { print -u2 "aztec-engine: no libbb-external.a in $name"; exit 1; }
    print $VERSION > $dir/VERSION
  done
}

lock_stamp() { shasum -a 256 $SRC/package-lock.json | cut -c1-16; }

# The packages the lockfile names, installed again whenever it changes: a
# checkout that already had `node_modules` would otherwise build against the
# old set and fail on a package added since (prd §1700aa added one).
ensure_packages() {
  local want; want=$(lock_stamp)
  [[ -d $SRC/node_modules && "$(cat $SRC/node_modules/.lock-stamp 2>/dev/null)" == $want ]] && return
  print -u2 "aztec-engine: installing the engine's packages"
  (cd $SRC && npm ci --no-audit --no-fund >/dev/null)
  print $want > $SRC/node_modules/.lock-stamp
}

ensure_engine() {
  # Shield's Aztec interfaces, fetched from its own site and pinned to the
  # classes mainnet runs (prd §1700d); kept once fetched.
  ensure_packages
  (cd $SRC && node fetch-shield.mjs) || { print -u2 "aztec-engine: Shield's interfaces could not be fetched and pinned"; exit 1; }
  local want; want=$(stamp)
  [[ -f $ENGINE/index.html && "$(cat $ENGINE/.stamp 2>/dev/null)" == $want ]] && return
  print -u2 "aztec-engine: building the engine page"
  (cd $SRC && npx vite build >/dev/null)
  # The page relay: Aztec's content-script half, one classic script the app
  # adds to an Aztec app's page in an isolated world (AztecBrowser).
  (cd $SRC && node_modules/.bin/esbuild src/relay.js --bundle --format=iife --target=safari17 \
     --outfile=../../$ENGINE/relay.js --log-level=warning)
  print $want > $ENGINE/.stamp
}

case ${1:-ensure} in
  ensure) ensure_prover; ensure_engine ;;
  --self-test)
    # The stamp must move when a source moves, or a stale engine ships.
    # Probed on a copy: a tracked file is never edited (a peer's commit could take it).
    T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
    mkdir -p $T/src && cp $SRC/package-lock.json $SRC/vite.config.js $SRC/index.html $T/ && cp $SRC/src/*.js $T/src/
    SRC=$T
    a=$(stamp); touch $SRC/src/main.js; b=$(stamp)
    [[ $a == $b ]] || { print "FAIL: the stamp moved without a change"; exit 1; }
    print "// probe" >> $SRC/src/main.js; c=$(stamp)
    [[ $a != $c ]] || { print "FAIL: the stamp did not see main.js change"; exit 1; }
    print "// probe" >> $SRC/src/net-shim.js; d=$(stamp)
    [[ $c != $d ]] || { print "FAIL: the stamp did not see net-shim.js change"; exit 1; }
    print "aztec-engine self-test: ok" ;;
  *) print -u2 "usage: $0 ensure|--self-test"; exit 2 ;;
esac
