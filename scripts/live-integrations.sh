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

# Kalshi (KalshiWatch) — http_ping can't cover it: the browse room's failure
# mode is a 200 with the WRONG SHAPE, not an unreachable host. Reported
# 2026-08-03 as "Kalshi says can't reach order book" on a screen whose category
# strip was fully populated — i.e. the listing answered, and something between
# it and a quoted price had moved. Three fields carry the whole room and each
# one is a single point of failure, so each is asserted on its own:
#
#   * `event_ticker` on the listing  — phase 1's only key; without it there are
#     no candidates to hydrate and the book is empty with the categories intact
#     (categories read `category`, a different field on the same payload).
#   * `markets` on the per-event read — phase 2's payload.
#   * a yes bid/ask pair on a market  — `markets(inEvent:)` DROPS every market
#     whose quote it can't read, so a rename here empties the book silently.
#
# The event ticker is discovered at runtime rather than pinned: Kalshi's open
# events turn over constantly, and a hardcoded one would go red the day its
# market settled and say nothing about the app.
KALSHI_API='https://api.elections.kalshi.com/trade-api/v2'
kresp=$(curl -s --max-time "$TIMEOUT" -H 'Accept: application/json' \
  "$KALSHI_API/events?status=open&limit=20&with_nested_markets=false" 2>/dev/null)
if [[ -z "$kresp" ]]; then
  fail "Kalshi discovery (unreachable)"
elif [[ "$kresp" != *'"event_ticker"'* ]]; then
  fail "Kalshi discovery — 200 but no \`event_ticker\`: phase 1 matches nothing, book goes empty"
else
  pass "Kalshi discovery — open events listing carries event_ticker"
  KTICKER=$(print -r -- "$kresp" | sed -E 's/.*"event_ticker":"([^"]*)".*/\1/' | head -1)
  kmkt=$(curl -s --max-time "$TIMEOUT" -H 'Accept: application/json' \
    "$KALSHI_API/events/$KTICKER?with_nested_markets=true" 2>/dev/null)
  if [[ -z "$kmkt" ]]; then
    fail "Kalshi event hydration $KTICKER (unreachable)"
  elif [[ "$kmkt" != *'"markets"'* ]]; then
    fail "Kalshi event hydration $KTICKER — 200 but no \`markets\` array"
  # The app reads `yes_bid_dollars`/`yes_ask_dollars` first and falls back to
  # the integer-cent `yes_bid`/`yes_ask`. Either pair keeps the room alive;
  # LOSING THE DOLLARS PAIR is worth an amber even while the fallback holds,
  # because that is the migration finishing and the fallback is all that is
  # left between the book and empty.
  elif [[ "$kmkt" == *'"yes_bid_dollars"'* && "$kmkt" == *'"yes_ask_dollars"'* ]]; then
    pass "Kalshi market quotes — yes_bid_dollars/yes_ask_dollars present ($KTICKER)"
  elif [[ "$kmkt" == *'"yes_bid"'* && "$kmkt" == *'"yes_ask"'* ]]; then
    warn "Kalshi market quotes — \`_dollars\` pair GONE, running on the yes_bid/yes_ask fallback ($KTICKER)"
  else
    fail "Kalshi market quotes — neither yes_bid_dollars nor yes_bid on $KTICKER; every market drops, book empties silently"
  fi
fi

# YouTube (FeedFollowBridges) — the bridge whose every read is a SCRAPE or an
# undocumented feed, i.e. the one with no contract behind it at all. Three
# single points of failure, each asserted on its own because each fails
# silently and differently:
#
#   * the handle page's `<link rel="canonical" …/channel/UC…>` — how
#     `resolveYouTubeChannelID` learns which channel an @handle IS. This check
#     exists because reading the WRONG field here shipped: the resolver took
#     the first `"channelId"` in the page, which belongs to another channel
#     entirely (measured 2026-08-05, wrong for 3 of 3 handles), so following an
#     @handle followed a stranger — with real videos landing under that
#     stranger's real name, so nothing looked broken anywhere.
#   * `feeds/videos.xml?channel_id=…` still serving `<entry>` — the whole
#     bridge.
#   * `media:statistics views=` on an entry — the only per-video number any
#     feed this app follows carries, and the sole input to the view-doubling
#     moment (FeedFollowMoments.checkYouTubeBreakout). It vanishes silently:
#     the moment simply stops firing.
#
# A 404 here is AMBER, not red, and that is measured rather than lenient:
# YouTube answers a client it has decided to throttle with a plain 404 (not a
# 429), so a nightly that goes red on one would cry wolf. The two readings are
# named in the row so a real removal isn't mistaken for a throttle.
YT_HANDLE='MrBeast'
ythtml=$(curl -s --max-time "$TIMEOUT" -A 'Mozilla/5.0 (compatible; Casberi/1.0; +https://casberi.app)' \
  "https://www.youtube.com/@$YT_HANDLE" 2>/dev/null)
YTID=$(print -r -- "$ythtml" | grep -o 'rel="canonical" href="https://www.youtube.com/channel/UC[A-Za-z0-9_-]\{22\}' | head -1 | grep -o 'UC[A-Za-z0-9_-]\{22\}')
if [[ -z "$ythtml" ]]; then
  fail "YouTube channel page @$YT_HANDLE (unreachable)"
elif [[ -z "$YTID" ]]; then
  fail "YouTube @$YT_HANDLE — no rel=canonical channel link: every @handle follow resolves to nothing"
else
  pass "YouTube @$YT_HANDLE — canonical channel link resolves ($YTID)"
  # The naive read the resolver used to make. Informational: it is EXPECTED to
  # disagree, and a row saying so is what keeps the fix from being quietly
  # reverted by someone who finds `"channelId"` and assumes it means this
  # channel.
  YTNAIVE=$(print -r -- "$ythtml" | grep -o '"channelId":"UC[A-Za-z0-9_-]\{22\}"' | head -1 | grep -o 'UC[A-Za-z0-9_-]\{22\}')
  if [[ -n "$YTNAIVE" && "$YTNAIVE" == "$YTID" ]]; then
    warn "YouTube — first \"channelId\" now AGREES with canonical ($YTNAIVE); the 2026-08-05 measurement may no longer hold"
  fi
  ytfeed=$(curl -s --max-time "$TIMEOUT" "https://www.youtube.com/feeds/videos.xml?channel_id=$YTID" 2>/dev/null)
  if [[ -z "$ytfeed" ]]; then
    fail "YouTube videos.xml $YTID (unreachable)"
  elif [[ "$ytfeed" != *'<entry>'* ]]; then
    warn "YouTube videos.xml $YTID — no <entry>: either the endpoint moved, or this host is being throttled (YouTube answers a throttled client 404, not 429)"
  elif [[ "$ytfeed" != *'media:statistics'* ]]; then
    warn "YouTube videos.xml $YTID — entries serve, but no \`media:statistics views\`: the view-doubling moment stops firing silently"
  else
    pass "YouTube videos.xml — entries + media:statistics views serve ($YTID)"
  fi
fi

# YouTube Shorts (YouTubeShorts) — the discriminator the Shorts tag rides.
# There is no field anywhere in videos.xml that says a video is a Short (the
# feed's media:content is a fixed 640x390 flash placeholder and its thumbnail a
# fixed 480x360, on every entry), so the only keyless read is what
# `/shorts/<id>` answers: 200 for a Short, 303 to /watch for a regular video —
# measured 4/4 on 2026-08-05. If that ever collapses to one status, every video
# reads as the same thing and the tag becomes noise rather than a filter.
yt_shorts_status() {   # $1 video id → status code, redirects NOT followed
  curl -s -o /dev/null -I --max-time "$TIMEOUT" \
    -A 'Mozilla/5.0 (compatible; Casberi/1.0; +https://casberi.app)' \
    -w '%{http_code}' "https://www.youtube.com/shorts/$1" 2>/dev/null
}
#
# Both samples are DERIVED, never pinned — a hardcoded video id goes red the
# day it is deleted and says nothing about the app. The channel's own Shorts
# tab names the Shorts; the regular video is the newest feed entry that ISN'T
# one of them. (The naive version of this — "first entry in the feed" — read
# amber on its very first run: MrBeast's newest upload was itself a Short, so
# the two samples were the same video.)
YTSHORTIDS=$(curl -s --max-time "$TIMEOUT" -A 'Mozilla/5.0 (compatible; Casberi/1.0; +https://casberi.app)' \
  "https://www.youtube.com/@$YT_HANDLE/shorts" 2>/dev/null \
  | grep -o '"videoId":"[A-Za-z0-9_-]\{11\}"' \
  | sed -E 's/.*:"([A-Za-z0-9_-]{11})"/\1/' | sort -u)
YTSHORT=$(print -r -- "$YTSHORTIDS" | head -1)
YTLONG=''
for cand in $(print -r -- "${ytfeed:-}" | grep -o '<yt:videoId>[A-Za-z0-9_-]\{11\}' | sed 's/.*>//'); do
  print -r -- "$YTSHORTIDS" | grep -qx "$cand" && continue
  YTLONG="$cand"; break
done
if [[ -z "$YTSHORT" || -z "$YTLONG" ]]; then
  warn "YouTube Shorts probe — couldn't sample one of each (short:${YTSHORT:-none} long:${YTLONG:-none}); check skipped"
else
  sc=$(yt_shorts_status "$YTSHORT"); lc=$(yt_shorts_status "$YTLONG")
  if [[ "$sc" == 200 && "$lc" == 30* ]]; then
    pass "YouTube Shorts probe — short=200, regular video=$lc (discriminator holds)"
  else
    warn "YouTube Shorts probe — short=$sc regular=$lc: /shorts/<id> no longer separates the two, every video would classify alike"
  fi
fi

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
