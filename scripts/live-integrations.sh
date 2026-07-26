#!/bin/zsh
# Casberi live-integrations heartbeat — KEYLESS host-liveness check.
#
# Verifies the third-party hosts the wallet / approval / Peer / prepare paths
# depend on still BEHAVE: the public RPCs still serve the fee + receipt methods,
# and Peer's orchestrators still emit fills on Base. This catches DEPENDENCY
# DRIFT — an endpoint moved, a method dropped, a contract migrated, a rate-limit
# tightened — the one failure class the deterministic verify.sh can't see
# (it never leaves the device).
#
# CONTRACT (read before editing):
#   * WARN-ONLY. Always exits 0. A red row is INFORMATION, not a build failure:
#     a transient third-party 500 must never fail a nightly. Read the table.
#   * ZERO Alchemy credits. Every request here is keyless — there is no key in
#     any URL. It deliberately hits the same public hosts the app chose to dodge
#     Alchemy's 10-block eth_getLogs cap (see WalletApprovals). The credit-
#     spending metadata / holdings / activity calls (alchemy_getTokenMetadata,
#     Portfolio) live in the IN-APP pre-release probes, never here — so this can
#     run nightly without touching the shared-key budget.
#   * No build, no sim, no computer-use — safe for scheduled/non-interactive runs.
#
# Pairs with (does NOT replace): the heavy in-app end-to-end probes
# (-peerProbe / -approvalProbe / -prepareProbe) that land real things and DO
# spend Alchemy credits — run those by hand before cutting a build.
#
# Usage: scripts/live-integrations.sh
set -u

TIMEOUT=15
RED=0            # hard failures (unreachable / method rejected / contract silent)
AMBER=0          # soft flags (reachable but unexpectedly quiet)

hr()   { print -P "%F{240}────────────────────────────────────────────────────%f"; }
pass() { print -P "  %F{green}✓%f $1"; }
warn() { print -P "  %F{yellow}⚠%f $1"; (( AMBER++ )); }
fail() { print -P "  %F{red}✗%f $1"; (( RED++ )); }

# POST a JSON-RPC call; echo the raw response (empty on transport failure).
raw() { curl -s --max-time "$TIMEOUT" -X POST "$1" \
          -H 'Content-Type: application/json' --data "$2" 2>/dev/null; }

# One method → OK / ERROR:<msg> / UNREACHABLE / BAD.
rpc() {
  local resp; resp=$(raw "$1" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$2\",\"params\":$3}")
  [[ -z "$resp" ]] && { echo "UNREACHABLE"; return; }
  [[ "$resp" == *'"result"'* ]] && { echo "OK"; return; }
  [[ "$resp" == *'"error"'* ]]  && { echo "ERROR:$(print -r -- "$resp" | sed -E 's/.*"message":"([^"]*)".*/\1/' | cut -c1-48)"; return; }
  echo "BAD"
}

# A neutral 0-value self-transfer estimates to 21000 on any chain without needing balance.
NEUTRAL='0x0000000000000000000000000000000000000001'
GASTX="[{\"from\":\"$NEUTRAL\",\"to\":\"$NEUTRAL\",\"value\":\"0x0\"}]"
ZEROTX='["0x0000000000000000000000000000000000000000000000000000000000000000"]'

# The prepare / approval fee+receipt methods, per keyless host (WalletApprovals + WalletPrepare).
check_rpc_host() {   # $1 label  $2 host
  local g p r
  g=$(rpc "$2" eth_gasPrice '[]')
  p=$(rpc "$2" eth_estimateGas "$GASTX")
  r=$(rpc "$2" eth_getTransactionReceipt "$ZEROTX")   # valid host answers null, not error
  if [[ "$g" == OK && "$p" == OK && "$r" == OK ]]; then
    pass "$1 — gasPrice / estimateGas / getTransactionReceipt"
  else
    fail "$1 — gasPrice:$g  estimateGas:$p  getReceipt:$r"
  fi
}

print -P "%F{cyan}Casberi live-integrations heartbeat%f  ($(date '+%Y-%m-%d %H:%M'))  — keyless, warn-only"
hr
print -P "%BPrepare / approval RPC hosts%b  (fee + receipt methods)"
check_rpc_host "eth-mainnet · mevblocker"  "https://rpc.mevblocker.io"
check_rpc_host "eth-mainnet · onfinality"  "https://eth.api.onfinality.io/public"
check_rpc_host "base-mainnet"              "https://mainnet.base.org"
check_rpc_host "arb-mainnet"               "https://arb1.arbitrum.io/rpc"
check_rpc_host "opt-mainnet"               "https://mainnet.optimism.io"
check_rpc_host "matic-mainnet · onfinality" "https://polygon.api.onfinality.io/public"

hr
print -P "%BPeer%b  (IntentFulfilled fills still emitting on Base)"
# Orchestrators + topic from PeerBridge — if these drift, the whole seat goes silent.
BASE="https://mainnet.base.org"
FTOPIC="0xd50b3b21bc45b85ddfaec58dbf56fe9b88754d08f47dcf5143b63258a57ad944"
O1="0x88888883ed048ff0a415271b28b2f52d431810d0"
O2="0x888888359e981b5225ca48fbcdceff702fc3b888"
headhex=$(raw "$BASE" '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' \
            | sed -E 's/.*"result":"([^"]*)".*/\1/')
if [[ -z "$headhex" || "$headhex" != 0x* ]]; then
  fail "Peer — Base head unreadable (host down?)"
else
  fromhex=$(printf '0x%x' $(( $((headhex)) - 9000 )))   # ~5h window
  resp=$(raw "$BASE" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getLogs\",\"params\":[{\"fromBlock\":\"$fromhex\",\"toBlock\":\"$headhex\",\"address\":[\"$O1\",\"$O2\"],\"topics\":[\"$FTOPIC\"]}]}")
  if [[ "$resp" == *'"error"'* ]]; then
    fail "Peer — getLogs rejected: $(print -r -- "$resp" | sed -E 's/.*"message":"([^"]*)".*/\1/' | cut -c1-48)"
  else
    count=$(print -r -- "$resp" | grep -o '"transactionHash"' | wc -l | tr -d ' ')
    if (( count >= 1 )); then
      pass "Peer — $count fills in the last ~5h (orchestrators + topic live)"
    else
      warn "Peer — reachable but 0 fills in ~5h (unusually quiet; not proof of breakage)"
    fi
  fi
fi

hr
print -P "%BGnosis Pay%b  (card spends still settling, and the range ceiling holding)"
# Settlement Safe + spendable tokens from GnosisPayBridge. Both Transfer topics
# are indexed, so this is the app's own filter shape minus the wallet.
GNO="https://rpc.gnosischain.com"
TTOPIC="0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
SETTLE="0x0000000000000000000000004822521e6135cd2599199c83ea35179229a172ee"
GTOKENS='"0x420ca0f9b9b604ce0fd9c18ef134c705e5fa3430","0x5cb9073902f2035222b9749f8fb0c9bfe5527108","0x2a22f9c3b484c3629090feed35f17ff8f88f76f0"'
# $1 fromBlock hex  $2 toBlock hex  $3 wallet topic ("" = any) → raw response.
gnosis_raw() {
  local from_topic="null"
  [[ -n "$3" ]] && from_topic="\"$3\""
  raw "$GNO" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getLogs\",\"params\":[{\"fromBlock\":\"$1\",\"toBlock\":\"$2\",\"address\":[$GTOKENS],\"topics\":[\"$TTOPIC\",$from_topic,\"$SETTLE\"]}]}"
}
# Same arguments → the transfer count, or "ERR".
gnosis_logs() {
  local r; r=$(gnosis_raw "$1" "$2" "${3:-}")
  if [[ -z "$r" || "$r" == *'"error"'* ]]; then print -r -- "ERR"; return; fi
  print -r -- "$r" | grep -o '"transactionHash"' | wc -l | tr -d ' '
}
ghead=$(raw "$GNO" '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' \
          | sed -E 's/.*"result":"([^"]*)".*/\1/')
if [[ -z "$ghead" || "$ghead" != 0x* ]]; then
  fail "Gnosis Pay — Gnosis Chain head unreadable (host down?)"
else
  gresp_sample=$(gnosis_raw "$(printf '0x%x' $(( $((ghead)) - 1500 )))" "$ghead" "")   # ~2h
  if [[ -z "$gresp_sample" || "$gresp_sample" == *'"error"'* ]]; then
    gnear=ERR
  else
    gnear=$(print -r -- "$gresp_sample" | grep -o '"transactionHash"' | wc -l | tr -d ' ')
  fi
  if [[ "$gnear" == ERR ]]; then
    fail "Gnosis Pay — getLogs rejected on a 1500-block window"
  elif (( gnear >= 1 )); then
    pass "Gnosis Pay — $gnear card spends in the last ~2h (settlement Safe + tokens live)"
  else
    warn "Gnosis Pay — reachable but 0 spends in ~2h (settlement Safe may have moved)"
  fi
  # THE drift check that matters (prd §222). These hosts answer a too-expensive
  # scan with an EMPTY ARRAY rather than an error, so if the budget ever
  # tightens below our 250k chunk the bridge goes silent with nothing in the
  # logs to explain it. The invariant: one full-size chunk must return exactly
  # what the same range returns split into fifths. Run against a REAL card Safe
  # discovered from the window above (the app always filters by wallet, and an
  # unfiltered read truncates by design — comparing those two shapes would be
  # meaningless), so no stranger's address is baked into this file.
  gwallet=$(print -r -- "$gresp_sample" | grep -oE '0x0{24}[0-9a-f]{40}' \
              | grep -vi '4822521e6135cd2599199c83ea35179229a172ee' | head -1)
  if [[ -z "$gwallet" ]]; then
    warn "Gnosis Pay — no card Safe in the sample window; skipped the chunk-size check"
  else
    gsingle=$(gnosis_logs "$(printf '0x%x' $(( $((ghead)) - 250000 )))" "$ghead" "$gwallet")
    gsum=0; gbad=""
    for i in 0 1 2 3 4; do
      lo=$(( $((ghead)) - 250000 + i * 50000 ))
      part=$(gnosis_logs "$(printf '0x%x' $lo)" "$(printf '0x%x' $(( lo + 50000 )))" "$gwallet")
      [[ "$part" == ERR ]] && { gbad=1; break; }
      gsum=$(( gsum + part ))
    done
    if [[ "$gsingle" == ERR || -n "$gbad" ]]; then
      fail "Gnosis Pay — getLogs rejected on the chunk-size check"
    elif (( gsingle == gsum )); then
      pass "Gnosis Pay — 250k chunk is exact ($gsingle = 5×50k sum) — maxRange still safe"
    else
      fail "Gnosis Pay — 250k chunk returned $gsingle but 5×50k found $gsum — SCAN BUDGET TIGHTENED, drop GnosisPayBridge.maxRange"
    fi
  fi
fi

hr
print -P "%BKeyless discovery APIs%b  (used across bridges — no key, no credits)"
http_ping() {   # $1 label  $2 url
  local code; code=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$TIMEOUT" \
    -H 'User-Agent: Casberi-heartbeat' "$2" 2>/dev/null)
  if [[ "$code" == 2* ]]; then pass "$1 ($code)"
  elif [[ -z "$code" || "$code" == 000 ]]; then fail "$1 (unreachable)"
  else fail "$1 (HTTP $code)"; fi
}
http_ping "Dexscreener"    "https://api.dexscreener.com/latest/dex/tokens/0x912CE59144191C1204E64559FE8253a0e49E6548"
http_ping "GeckoTerminal"  "https://api.geckoterminal.com/api/v2/networks/eth/trending_pools"
http_ping "Jupiter"        "https://lite-api.jup.ag/tokens/v2/search?query=SOL"
http_ping "Bluesky public" "https://public.api.bsky.app/xrpc/app.bsky.actor.getProfile?actor=bsky.app"

# Morpho (MorphoDeFi) — POST GraphQL, so http_ping can't cover it. This sends
# the SAME field/enum shape the app's position + activity queries use against a
# neutral address, so schema drift (the class already caught once: market txs
# order by `Timestamp`, vault txs by `Time`) turns a row red before it turns
# the seat silent. Keyless by contract, like everything here.
MORPHO_Q='{"query":"{ marketPositions(first: 1, where: { userAddress_in: [\"0x000000000000000000000000000000000000dEaD\"], chainId_in: [1] }) { items { healthFactor state { collateralUsd supplyAssetsUsd borrowAssetsUsd } market { loanAsset { symbol } collateralAsset { symbol } morphoBlue { chain { id } } } } } vaultPositions(first: 1, where: { userAddress_in: [\"0x000000000000000000000000000000000000dEaD\"], chainId_in: [1] }) { items { state { assetsUsd } vault { name chain { id } asset { symbol } } } } marketTransactions(first: 1, orderBy: Timestamp, orderDirection: Desc, where: { chainId_in: [1] }) { items { txHash type data { __typename } } } vaultV1Transactions(first: 1, orderBy: Time, orderDirection: Desc, where: { chainId_in: [1] }) { items { txHash type assets } } }"}'
mresp=$(raw "https://blue-api.morpho.org/graphql" "$MORPHO_Q")
if [[ -z "$mresp" ]]; then
  fail "Morpho GraphQL (unreachable)"
elif [[ "$mresp" == *'"errors"'* ]]; then
  fail "Morpho GraphQL — schema drift: $(print -r -- "$mresp" | sed -E 's/.*"message":"([^"]*)".*/\1/' | cut -c1-64)"
elif [[ "$mresp" == *'"marketPositions"'* && "$mresp" == *'"vaultV1Transactions"'* ]]; then
  pass "Morpho GraphQL — position + activity query shapes serve"
else
  warn "Morpho GraphQL — reachable but unexpected body"
fi

hr
if (( RED == 0 && AMBER == 0 )); then
  print -P "%F{green}All live-integration hosts healthy.%f"
elif (( RED == 0 )); then
  print -P "%F{yellow}$AMBER soft flag(s), 0 failures — likely fine, glance at the ⚠ rows.%f"
else
  print -P "%F{red}$RED host issue(s)%f (+$AMBER soft) — a dependency may have drifted; investigate the ✗ rows."
fi
# Warn-only by contract: always green exit so a third-party hiccup never fails the run.
exit 0
