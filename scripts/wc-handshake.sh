#!/usr/bin/env bash
#
# wc-handshake.sh — run Casberi's WalletConnect handshake end-to-end against a
# real wallet, and assert that nothing survives it.
#
# WHY THIS EXISTS
#
# `-wcConnectProbe` alone stubs the `open` step, because no wallet app exists on
# the simulator. That proves the mint (a genuine relay round-trip) and prints
# the proposal, and it can prove nothing about the half that carries the
# promise: settle → read → teardown. This script supplies the missing half — a
# wallet-side client (scripts/wc-wallet) that pairs with the minted URI,
# approves, and then checks, from the side that would have been asked to sign,
# that the app killed the session.
#
# It is the difference between "we tore the session down" and "a wallet watched
# us tear the session down". Every measured quirk in CLAUDE.md's
# Wallet/WalletConnect section was caught by running this, not by reading code.
#
# USAGE
#
#   scripts/wc-handshake.sh                  # multichain wallet: EVM + Solana
#   APPROVE_NS=eip155 scripts/wc-handshake.sh    # EVM-only wallet refusing solana
#   APPROVE_NS=solana SOL_CHAIN_FILTER=solana:4sGjMW1sUnHzSxGspuhpqLDx6wiyjNtZ \
#     scripts/wc-handshake.sh                    # wallet keyed to the LEGACY id
#
# Other env: EVM_ACCOUNTS / SOL_ACCOUNTS (comma lists), DELETE_WAIT_MS.
#
# Requires: a booted simulator with the app installed (scripts/verify.sh, or
# xcodebuild + simctl install), node, and a `wc-project-id` in the login
# Keychain (scripts/dev-keys.sh set wc-project-id). The id is fetched INLINE so
# it never lands in a shell variable or the log.
#
# Exit: 0 = handshake completed and nothing survived. Non-zero = look at the
# output; a surviving session means the Wallet screen's read-only promise is
# false, which is the one thing this file exists to catch.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WALLET_DIR="$REPO/scripts/wc-wallet"
APP_ID="com.casberi.app"
# The probe's approval window. Wider than the 20s default because a human isn't
# the bottleneck here, the wallet client is — but far under the proposal's real
# 300s expiry, so a broken run fails fast instead of hanging a nightly.
WC_TIMEOUT="${WC_TIMEOUT:-120}"

fail() { echo "wc-handshake: $*" >&2; exit 3; }

command -v node >/dev/null || fail "node not found — needed for the wallet-side client"
xcrun simctl list devices booted 2>/dev/null | grep -q "(Booted)" \
  || fail "no booted simulator — boot one and install the app first"
xcrun simctl get_app_container booted "$APP_ID" app >/dev/null 2>&1 \
  || fail "$APP_ID isn't installed on the booted simulator"

PROJECT_ID="$("$REPO/scripts/dev-keys.sh" get wc-project-id 2>/dev/null)"
[ -n "$PROJECT_ID" ] || fail "no wc-project-id in the Keychain — scripts/dev-keys.sh set wc-project-id"

if [ ! -d "$WALLET_DIR/node_modules" ]; then
  echo "--- first run: installing the wallet-side client ---"
  (cd "$WALLET_DIR" && npm install --silent) || fail "npm install failed"
fi

APPLOG="$(mktemp -t wc-handshake)"
cleanup() {
  [ -n "${LOGPID:-}" ] && kill "$LOGPID" 2>/dev/null
  rm -f "$APPLOG"
}
trap cleanup EXIT

xcrun simctl terminate booted "$APP_ID" >/dev/null 2>&1
xcrun simctl spawn booted log stream --style compact \
  --predicate 'processImagePath CONTAINS "Casberi"' > "$APPLOG" 2>&1 &
LOGPID=$!
sleep 2

echo "--- launching the app's handshake probe (${WC_TIMEOUT}s window) ---"
xcrun simctl launch booted "$APP_ID" \
  -wcConnectProbe YES -wcTimeout "$WC_TIMEOUT" -onboarded YES >/dev/null 2>&1

# Wait for the mint. The probe logs the URI from inside the stubbed `open`, so
# its presence already means the relay round-trip succeeded.
URI=""
for _ in $(seq 1 30); do
  URI=$(grep -ao 'wc:[^ ]*' "$APPLOG" | head -1)
  [ -n "$URI" ] && break
  sleep 1
done
[ -n "$URI" ] || { echo "--- app side ---"; grep -a "WalletConnect probe" "$APPLOG"; \
                   fail "no URI minted — check the project id and the relay"; }

echo "--- URI minted; handing it to the wallet-side client ---"
(cd "$WALLET_DIR" && node wallet.js "$URI" "$PROJECT_ID")
WALLET_RC=$?

sleep 2
echo
echo "=== APP SIDE ==="
# symKey is the session secret; it has no business in a terminal scrollback.
grep -a "WalletConnect probe" "$APPLOG" | sed 's/symKey=[0-9a-f]*/symKey=‹redacted›/'
echo
case "$WALLET_RC" in
  0) echo "wc-handshake: PASS — the wallet saw the session die, nothing survived" ;;
  1) echo "wc-handshake: FAIL — a session survived, or the promise was broken" ;;
  2) echo "wc-handshake: FAIL — the wallet never received the proposal" ;;
  *) echo "wc-handshake: FAIL — wallet client exited $WALLET_RC" ;;
esac
exit $WALLET_RC
