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
  # Presence is NOT the test — NON-EMPTINESS is, and the difference is the
  # whole 2026-08-06 bug. This endpoint answers with a top-level `markets`
  # sibling that is ALWAYS `[]` and the real markets nested under
  # `event.markets`. A grep for the key name matched that empty sibling, so
  # this row ran green for the entire life of a room that was reading zero
  # markets on every request. Count the objects, don't spot the key.
  elif ! print -r -- "$kmkt" | grep -qE '"markets":\[[[:space:]]*\{'; then
    fail "Kalshi event hydration $KTICKER — 200 but no NON-EMPTY \`markets\` array (the key alone proves nothing; the top-level sibling is always [])"
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
#     feed this app follows carries. Nothing renders it since the in-app
#     moment bus was removed (2026-08-19); it is still parsed, and still
#     watched here, because it is the one number a YouTube row could ever
#     show and its disappearance would be silent.
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

# Telegram (FeedFollowBridges + TelegramChannel, prd §456) — the SCRAPE with the
# weakest contract of anything in this file. YouTube at least serves a real
# feed document; `t.me/s/<channel>` is somebody's WEB PAGE, and every rule the
# parser follows is a class name or an attribute measured on 2026-08-23 rather
# than published anywhere. So this is the strongest block here: six assertions,
# each naming the silent failure it catches, because when any of these move the
# room does not break — it goes QUIET, which from outside is indistinguishable
# from a channel that stopped posting.
#
# @durov is the sample for the same reason MrBeast is YouTube's: it is the
# platform founder's own channel, so it is the last public channel on Telegram
# that will ever go away, and it posts often enough that an empty read means the
# read, not the channel.
TG_CHANNEL='durov'
TG_UA='Mozilla/5.0 (compatible; Casberi/1.0; +https://casberi.app)'
tgcode=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$TIMEOUT" -A "$TG_UA" \
  "https://t.me/s/$TG_CHANNEL" 2>/dev/null)
tghtml=$(curl -s --max-time "$TIMEOUT" -A "$TG_UA" "https://t.me/s/$TG_CHANNEL" 2>/dev/null)
if [[ -z "$tghtml" || "$tgcode" == 000 ]]; then
  fail "Telegram t.me/s/$TG_CHANNEL (unreachable)"
elif [[ "$tgcode" != 200 ]]; then
  # 1. A 302 on a channel that HAS a preview is the whole live half going dark:
  #    `parse` returns nil for a redirect body, so every followed channel would
  #    report itself as "not a channel" and no post would ever land again.
  fail "Telegram — t.me/s/$TG_CHANNEL answered http $tgcode, not 200: the web preview is the entire live read, and without it every followed channel goes silent"
else
  pass "Telegram — t.me/s/$TG_CHANNEL serves its web preview (http 200, ${#tghtml} bytes)"

  # 2. `data-post="<channel>/<id>"` is the ONLY stable identity on the page —
  #    not the DOM order, not the text — and it is what every `sourceRef` is
  #    built from. Lose it and `parsePost` drops every message: the page still
  #    200s, the channel still parses, and the room lands nothing.
  tgposts=$(print -r -- "$tghtml" | grep -o "data-post=\"$TG_CHANNEL/[0-9]\{1,\}\"" | wc -l | tr -d ' ')
  if (( tgposts >= 1 )); then
    pass "Telegram — $tgposts posts carry data-post=\"$TG_CHANNEL/<id>\" (the only per-post identity)"
  else
    fail "Telegram — no \`data-post=\"$TG_CHANNEL/<id>\"\` on the page: every post is dropped and the room lands nothing, with the channel still reading as reachable"
  fi

  # 3. The date. Asserted as a `datetime` ATTRIBUTE rather than as a `<time>`
  #    tag, and that distinction is a real measured bug: a video post opens with
  #    `<time class="message_video_duration">` carrying a clip's running time and
  #    NO datetime, so reading the first `<time>` blindly left 15 of 20 posts
  #    undated (@telegram, 2026-08-23) — and an undated post falls back to "now",
  #    filing a four-month-old broadcast as today's news. A row here that finds
  #    `<time>` but no `datetime=` is that bug arriving from their side.
  tgtimes=$(print -r -- "$tghtml" | grep -o '<time[^>]*datetime="[0-9]\{4\}-' | wc -l | tr -d ' ')
  if (( tgtimes >= 1 )); then
    pass "Telegram — $tgtimes <time> elements carry a datetime attribute (the parser's only date)"
  elif print -r -- "$tghtml" | grep -q '<time'; then
    fail "Telegram — <time> is present but NONE carries \`datetime\`: every post falls back to now, and months-old broadcasts file as today"
  else
    fail "Telegram — no <time> element at all: every post lands undated"
  fi

  # 4. The words. Without this container `parsePost` sees no text, and a post
  #    with no text, no photo and no video is DROPPED by design — so a rename
  #    here empties the room for every text-only channel while photo channels
  #    keep working, which reads as one channel being broken rather than a parse.
  if print -r -- "$tghtml" | grep -q 'tgme_widget_message_text'; then
    pass "Telegram — tgme_widget_message_text still wraps the post body"
  else
    fail "Telegram — no \`tgme_widget_message_text\`: posts land wordless and a text-only channel's rows are dropped entirely"
  fi

  # 5. The pictures, and the decoy. A real photograph is on `telesco.pe` and
  #    every emoji is a sprite on `telegram.org/img/emoji` — so the naive
  #    "first background-image" read files an emoji as the post's photograph.
  if print -r -- "$tghtml" | grep -qF "telesco.pe"; then
    pass "Telegram — photographs still come off telesco.pe"
  else
    warn "Telegram — no \`telesco.pe\` URL on the page: either this channel posted no pictures this week, or the media CDN moved and every photo post lands pictureless"
  fi
  # The anti-regression tell, mirroring the naive-`channelId` row above: the
  # emoji host exclusion (rule 5) is only worth its cost while the decoy is
  # really there. If Telegram ever stops serving sprite emoji, the exclusion is
  # guarding nothing and the measurement behind it should be re-taken before
  # anybody "simplifies" `isPhotograph` into a `contains`.
  if ! print -r -- "$tghtml" | grep -qF 'telegram.org/img/emoji'; then
    warn "Telegram — \`telegram.org/img/emoji\` has GONE from the page; the emoji-sprite exclusion in isPhotograph may now be guarding nothing (re-measure before removing it — it is what keeps an emoji from landing as a post's photograph)"
  fi

  # 6. The 302 DISCRIMINATOR — the one thing that lets an empty room explain
  #    itself. `/s/<name>` refusing to serve has three different causes and the
  #    landing page is the only place they are distinguishable: "subscribers" is
  #    a real channel with its preview switched off, "members" is a GROUP (which
  #    has no public preview and never will), and no counter at all is a name
  #    nobody has claimed. If those two words ever read alike, `standing(_:)`
  #    collapses to `.unknown` and the app can no longer tell somebody whether
  #    their name was wrong. @python is a group, and has been since 2013.
  #
  #    Redirects are deliberately NOT followed: it is the 302 itself that says
  #    "not a followable channel", and following it would answer 200 off the
  #    landing page and invert the test.
  TG_GROUP='python'
  tggroup=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$TIMEOUT" -A "$TG_UA" \
    "https://t.me/s/$TG_GROUP" 2>/dev/null)
  if [[ "$tggroup" != 30* ]]; then
    warn "Telegram — t.me/s/$TG_GROUP answered http $tggroup, not a redirect: a group now serves a /s/ preview, so 'not a channel' is no longer detectable by status alone"
  else
    tgextra_g=$(curl -s --max-time "$TIMEOUT" -A "$TG_UA" "https://t.me/$TG_GROUP" 2>/dev/null \
      | grep -o 'tgme_page_extra[^<]*' | head -1)
    tgextra_c=$(curl -s --max-time "$TIMEOUT" -A "$TG_UA" "https://t.me/$TG_CHANNEL" 2>/dev/null \
      | grep -o 'tgme_page_extra[^<]*' | head -1)
    if [[ -z "$tgextra_g" || -z "$tgextra_c" ]]; then
      fail "Telegram — no \`tgme_page_extra\` on a landing page: standing() reads .absent for every refused name, so a real channel with its preview off is reported as a typo"
    elif [[ "$tgextra_g" == *member* && "$tgextra_c" == *subscriber* ]]; then
      pass "Telegram — the 302 discriminator holds (group says \"members\", channel says \"subscribers\")"
    else
      fail "Telegram — the landing counters no longer separate a group from a channel (group:\"$(print -r -- "$tgextra_g" | cut -c17-48)\" channel:\"$(print -r -- "$tgextra_c" | cut -c17-48)\"); an empty room can no longer say why"
    fi
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
# Circle x402 (2026-08-06) — the marketplace directory. Four assertions, each a
# silent failure of its own: the room renders perfectly on a drifted read and
# only ever gets quieter, so nothing in a build or a screen sweep can see any
# of these.
#
# The fourth is the one to read carefully. Circle's `category` filter accepts
# SIX values while its own data carries SEVEN (`DATA_ENRICHMENT`, 185 of 955
# listings when measured), which is why the bridge fetches unfiltered and
# narrows on device. If Circle ever fixes that, this row goes amber — not to
# demand a change, but so the decision is made by someone who knows, rather
# than by whoever next assumes a server-side filter would be tidier.
x402=$(curl -s --max-time "$TIMEOUT" \
  "https://api.circle.com/v2/x402/discovery/resources?limit=5" 2>/dev/null)
if [[ -z "$x402" ]]; then
  fail "Circle x402 discovery (unreachable)"
else
  # 1. The envelope the walk pages on. Without `total` the walk reads page one
  #    and stops, which looks exactly like a directory with 5 entries in it.
  if [[ "$x402" == *'"items"'* && "$x402" == *'"total"'* ]]; then
    pass "Circle x402 — items[] + pagination.total serve"
  else
    fail "Circle x402 — envelope drift: the walk can't page (items/total missing)"
  fi
  # 2. Every shaping decision rests on these three fields. A rename empties the
  #    room or strips its prices with no error anywhere.
  if [[ "$x402" == *'"provider"'* && "$x402" == *'"category"'* && "$x402" == *'"amount"'* ]]; then
    pass "Circle x402 — provider/category/amount still on the wire"
  else
    fail "Circle x402 — listing shape drifted: provider, category or amount is gone"
  fi
  # 3. Keyless is the whole seat. A 401 here means the bridge needs an account
  #    it has never asked anyone for.
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$TIMEOUT" \
    "https://api.circle.com/v2/x402/discovery/resources?limit=1" 2>/dev/null)
  if [[ "$code" == "200" ]]; then
    pass "Circle x402 — still answers with no key (http 200)"
  else
    fail "Circle x402 — keyless read now answers http $code"
  fi
  # 4. The six-vs-seven gap. Amber either way it moves: still-broken is the
  #    status quo the bridge is built for, newly-fixed is a design input.
  dec=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$TIMEOUT" \
    "https://api.circle.com/v2/x402/discovery/resources?category=DATA_ENRICHMENT&limit=1" 2>/dev/null)
  if [[ "$dec" == "400" ]]; then
    pass "Circle x402 — category filter still refuses DATA_ENRICHMENT (on-device filtering stays right)"
  elif [[ "$dec" == "200" ]]; then
    warn "Circle x402 — category=DATA_ENRICHMENT now answers 200; the six-value filter may be fixed (see quirk 1 before changing the walk)"
  else
    warn "Circle x402 — category=DATA_ENRICHMENT answered http $dec (expected 400)"
  fi
fi

hr
# Walletbeat (prd §419) — the bundled directory still matches what they publish.
#
# `Model/WalletbeatDirectory.swift` is a SNAPSHOT: 32 wallets' rating counts,
# generated at ship time because fetching every wallet's ~342KB report to draw a
# list is 11MB for a screen that must open instantly and offline. So the whole
# directory ages silently — Walletbeat re-rates a wallet, our row keeps drawing
# yesterday's counts under their name, and nothing on the device can tell.
#
# It is HERE and not in verify.sh because `--check` regathers from
# `beta.walletbeat.eth.limo` — that pass is all-local and deterministic by
# contract. The generator's PURE half (`--self-test`) runs there instead.
#
# Amber, never red, and never a build failure: stale is a REGENERATE ERRAND for
# the next ship (docs/testflight-handoff.md), not a broken app — the snapshot in
# the tree is still Walletbeat's real judgment, just an older one.
#
# BOUNDED, unlike every curl row above. Those carry `--max-time`; this is a
# python walk of 32 documents with a 60s per-request timeout of its own, so a
# hung host could hold an unattended nightly for minutes. macOS ships no
# `timeout(1)` (verify-mac.sh's own lesson), so the watchdog is spelled out, and
# a signal death (> 128) is read as unreachable — which is what a hang means.
WB_OUT=$(mktemp)
"${0:h}/walletbeat-snapshot.py" --check >"$WB_OUT" 2>&1 &
WBPID=$!
( sleep 180; kill -9 $WBPID 2>/dev/null ) >/dev/null 2>&1 &
WBDOG=$!
wait $WBPID; WBRC=$?
kill $WBDOG 2>/dev/null
wb=$(<"$WB_OUT"); rm -f "$WB_OUT"
if (( WBRC > 128 )); then
  warn "Walletbeat snapshot — check timed out after 180s (their host is slow or hung); the bundled directory is unverified this run"
elif [[ "$wb" == *"walletbeat directory is current"* ]]; then
  pass "Walletbeat snapshot — the bundled directory matches what they publish today"
elif [[ "$wb" == *"STALE"* ]]; then
  # Split from the unreachable case on purpose. Stale is a fact about OUR tree
  # and is acted on; unreachable is a fact about THEIR host and is not, and a
  # single row for both would have somebody regenerating against a site that is
  # down (which `gather` refuses to do anyway — a partial snapshot would drop
  # wallets from the directory, reading as "Walletbeat doesn't rate it").
  warn "Walletbeat snapshot — STALE: their ratings moved since it was generated; run scripts/walletbeat-snapshot.py before the next ship"
else
  warn "Walletbeat snapshot — couldn't check (host or index unreachable): $(print -r -- "$wb" | tail -1 | cut -c1-80)"
fi

hr
# ---------------------------------------------------------------------------
# L2BEAT (prd §428) — the one bridge here whose read has NO CONTRACT behind it.
#
# `l2beat.com/api/*` is their SITE's own data endpoint, undocumented and
# unversioned; their documented API (`api.l2beat.com`) answers 401 without a
# key. Three single fields carry the whole room, and a rename to any of them
# empties it SILENTLY — a room with no chains and a room whose parse stopped
# matching render identically. Nothing else in this tree can see that.
# ---------------------------------------------------------------------------
print -P "%F{244}L2BEAT — the undocumented site endpoint the room rests on%f"
L2B=$(curl -s --max-time 30 "https://l2beat.com/api/scaling/summary" 2>/dev/null)
if [[ -z "$L2B" ]]; then
  fail "L2BEAT — the summary endpoint is unreachable"
else
  # 1. The envelope. No `projects` key and the directory reads as empty.
  n=$(print -r -- "$L2B" | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: print(-1); raise SystemExit
p=d.get("projects")
print(len(p) if isinstance(p,dict) else -1)' 2>/dev/null)
  if [[ "$n" == "-1" || -z "$n" ]]; then
    fail "L2BEAT — no \`projects\` map in the summary; the site API's shape changed"
  elif (( n < 50 )); then
    warn "L2BEAT — only $n projects (105 measured 2026-08-21); the walk may be truncating"
  else
    pass "L2BEAT — $n projects in one keyless request"
  fi
  # 2. The stage, which is the one composite this feature is allowed to show.
  # 3. The five axes and their sentiment, which is the whole strip.
  shape=$(print -r -- "$L2B" | python3 -c '
import json,sys,collections
d=json.load(sys.stdin); p=d.get("projects") or {}
staged=sum(1 for v in p.values() if v.get("stage"))
five=sum(1 for v in p.values() if len(v.get("risks") or [])==5)
axes={r["name"] for v in p.values() for r in (v.get("risks") or [])}
sent={r.get("sentiment") for v in p.values() for r in (v.get("risks") or [])}
want={"Sequencer Failure","State Validation","Data Availability","Exit Window","Proposer Failure"}
print(staged, five, int(want <= axes), "|".join(sorted(s for s in sent if s not in ("good","warning","bad","neutral"))))' 2>/dev/null)
  staged=${shape%% *}; rest=${shape#* }; five=${rest%% *}; rest2=${rest#* }
  hasaxes=${rest2%% *}; oddsent=${rest2#* }
  if [[ "$staged" == "0" || -z "$staged" ]]; then
    fail "L2BEAT — no project carries a \`stage\`; the ladder this room cites is gone"
  else
    pass "L2BEAT — $staged projects still carry a stage"
  fi
  if [[ "$hasaxes" != "1" ]]; then
    fail "L2BEAT — one of the five risk axes was renamed; the strip drops a cell silently"
  else
    pass "L2BEAT — all five risk axes still named as the app matches them"
  fi
  if [[ "$five" != "$n" ]]; then
    # Not fatal: a project with fewer than five is still a real chain and still
    # lands. But the five-cell strip is drawn WITHOUT a coverage gate on the
    # measured fact that every project has five, so this is the day that gets
    # revisited (see §428's own note).
    warn "L2BEAT — $five of $n projects carry all five risks; the strip's no-gate assumption is weakening"
  else
    pass "L2BEAT — every project still carries all five risks"
  fi
  if [[ -n "$oddsent" && "$oddsent" != " " ]]; then
    warn "L2BEAT — unrecognised sentiment(s): $oddsent (they read as 'not read', never as good)"
  fi
  # 4. Is the BUNDLED snapshot still what L2BEAT publishes? Warn-only and here
  #    rather than in `verify.sh`, which is all-local by contract. A stale
  #    bundle is not a bug — it is exactly as current as the last ship, and the
  #    room says so — but it is the signal to regenerate before cutting a build.
  if python3 scripts/l2beat-snapshot.py --check >/dev/null 2>&1; then
    pass "L2BEAT — the bundled directory still matches what they publish"
  else
    warn "L2BEAT — the bundled directory is STALE; run scripts/l2beat-snapshot.py before shipping"
  fi
  # 5. The milestone door, joined on the REPO ID and not the slug — the ten
  #    divergent projects are why (§428). OP Mainnet is one of them, so it is
  #    the right canary: if this 404s, the join has been flipped back.
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$TIMEOUT" \
    "https://raw.githubusercontent.com/l2beat/l2beat/main/packages/config/src/projects/optimism/optimism.ts" 2>/dev/null)
  if [[ "$code" == "200" ]]; then
    pass "L2BEAT — the milestone file resolves by repo id (optimism, whose slug is op-mainnet)"
  else
    fail "L2BEAT — the milestone file for OP Mainnet answered http $code; the repo layout moved"
  fi
fi

hr
# ── Ethrex Hegotá (prd §500/§504) ────────────────────────────────────────────
# **The most drift-prone dependency in the catalog, and it had no row.** This is
# an experimental devnet with no contract behind anything the seat reads: the
# EIP-7708 transfer emitter, the `UtxoCreated` topic, `payer` on a type-`0x6`
# receipt, `nonceKeys`, and two predeploys. When any of it moves the room does
# not break — it goes QUIET, which from outside is indistinguishable from an
# address that simply has no history (§311's class).
#
# Everything here is keyless and free. The reconciliation row is the sharpest:
# it is the seat's own self-proof — every unspent coin on the chain, summed,
# against the vault's balance — run nightly, so a drifted parse or a relaunched
# devnet is caught by the same arithmetic the app gates its Coins card on.
print -P "%F{45}Ethrex Hegotá%f (keyless devnet)"
HEG="https://rpc1.hegota.ethrex.xyz"
HEG_VAULT="0x0000000000000000000000000000000000008312"
HEG_NONCE="0x0000000000000000000000000000000000008250"
HEG_UTXO_TOPIC="0x3b19241465a47bc187f1d9c7db70834855a907183742a4b63aa824c576296f5e"

# 1. All three hosts, and the chain id the app pins (3151908 = 0x301824). A host
#    answering for some OTHER chain is the failure `HegotaGenesis` exists for.
heg_up=0
for h in rpc1 rpc2 rpc3; do
  id=$(raw "https://$h.hegota.ethrex.xyz" '{"id":1,"jsonrpc":"2.0","method":"eth_chainId","params":[]}' \
        | python3 -c 'import sys,json;print(json.load(sys.stdin).get("result",""))' 2>/dev/null)
  [[ "$id" == "0x301824" ]] && (( heg_up++ ))
done
if (( heg_up == 3 )); then
  pass "Hegotá — all three RPC hosts serve chain 3151908"
elif (( heg_up > 0 )); then
  warn "Hegotá — only $heg_up of 3 hosts answered with chain 3151908 (the seat retries, so this is survivable)"
else
  fail "Hegotá — no host served chain 3151908; the whole seat reads nothing"
fi

if (( heg_up > 0 )); then
  # 2. **The genesis hash.** A relaunched devnet answers everything perfectly and
  #    with NOTHING, so this is the only signal that separates "quiet" from
  #    "this is a different chain now". Recorded rather than asserted — a change
  #    is expected eventually and is news, not a failure.
  gen=$(raw "$HEG" '{"id":1,"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["0x0",false]}' \
        | python3 -c 'import sys,json;print((json.load(sys.stdin).get("result") or {}).get("hash",""))' 2>/dev/null)
  if [[ "$gen" == "0xc2a34ac020910de9fa78b5089eb9eb91b913fb0f95370ec42601ddb95a5cb213" ]]; then
    pass "Hegotá — same chain as when the seat was built (genesis unchanged)"
  elif [[ -n "$gen" ]]; then
    warn "Hegotá — THE DEVNET RESTARTED (genesis is now $gen); watched history is gone and the worked examples need re-measuring"
  else
    warn "Hegotá — the genesis header did not read; the restart check could not run"
  fi

  # 3. Both predeploys still carry code. A predeploy that vanished takes the
  #    Coins scope and every `sender` frame's counterparty with it.
  for pair in "vault:$HEG_VAULT" "nonce manager:$HEG_NONCE"; do
    label="${pair%%:*}"; addr="${pair#*:}"
    code=$(raw "$HEG" "{\"id\":1,\"jsonrpc\":\"2.0\",\"method\":\"eth_getCode\",\"params\":[\"$addr\",\"latest\"]}" \
           | python3 -c 'import sys,json;print(json.load(sys.stdin).get("result",""))' 2>/dev/null)
    if [[ ${#code} -gt 4 ]]; then
      pass "Hegotá — the $label predeploy still carries code"
    else
      fail "Hegotá — the $label predeploy has NO code; the scope it feeds goes silently empty"
    fi
  done

  # 4. **The reconciliation — the seat's own gate, run against live state.**
  #    Reconstructs every unspent coin on the chain from the logs plus the spent
  #    bitmap and compares the total with the vault's balance, exactly as
  #    `HegotaCoins.reconciles` does. A mismatch means the topic, the log layout
  #    or the storage slot moved — and in the app that renders as a Coins card
  #    that just stops drawing.
  heg_recon=$(python3 - "$HEG" "$HEG_VAULT" "$HEG_UTXO_TOPIC" <<'PY' 2>/dev/null
import json,sys,urllib.request
host,vault,topic=sys.argv[1],sys.argv[2],sys.argv[3]
def call(m,p):
    r=urllib.request.urlopen(urllib.request.Request(host,
        json.dumps({"id":1,"jsonrpc":"2.0","method":m,"params":p}).encode(),
        {"Content-Type":"application/json"}),timeout=20)
    return json.load(r).get("result")
logs=call("eth_getLogs",[{"address":vault,"topics":[topic],"fromBlock":"0x0","toBlock":"latest"}]) or []
coins=[]
for l in logs:
    d=l["data"][2:]
    coins.append((int(d[0:64],16),int(d[64:128],16),"0x"+l["topics"][2][-40:]))
words={}
for w in sorted({i>>8 for i,_,_ in coins}):
    words[w]=int(call("eth_getStorageAt",[vault,hex((1<<129)+w),"latest"]),16)
unspent=[c for c in coins if not (words[c[0]>>8]>>(c[0]&0xFF))&1]
bal=int(call("eth_getBalance",[vault,"latest"]),16)
total=sum(v for _,v,_ in unspent)
print(f"{len(coins)} {len(unspent)} {len({o for _,_,o in unspent})} {int(total==bal)}")
PY
)
  if [[ -n "$heg_recon" ]]; then
    read -r hc hu ho hok <<< "$heg_recon"
    if [[ "$hok" == "1" ]]; then
      pass "Hegotá — the UTXO set reconciles to the wei ($hu unspent of $hc, $ho owners)"
    else
      fail "Hegotá — the UTXO set NO LONGER reconciles against the vault balance; the Coins card will stop drawing"
    fi
  else
    warn "Hegotá — the reconciliation walk did not complete; the seat's own gate is unverified tonight"
  fi

  # 5. **Frame transactions still look like frame transactions.** Everything the
  #    Frames scope draws comes off a type-`0x6` receipt's `frames` array, and
  #    nothing about that shape is contractual.
  #
  #    **READ THE LOGS, NOT THE BLOCKS — §500's own lesson, re-earned here.**
  #    The first cut of this row walked the newest 600 blocks and found zero
  #    transactions, then reported the frame shape "unverified". That is exactly
  #    the mistake §500 records: this chain is mostly idle at the tip, so
  #    sampling blocks measures the sampling and not the chain. The transfer
  #    logs are the thing that ACCUMULATES, and every one of them names a
  #    transaction, so the newest few give real receipts to check.
  heg_frames=$(python3 - "$HEG" <<'PY' 2>/dev/null
import json,sys,urllib.request
host=sys.argv[1]
def call(m,p):
    r=urllib.request.urlopen(urllib.request.Request(host,
        json.dumps({"id":1,"jsonrpc":"2.0","method":m,"params":p}).encode(),
        {"Content-Type":"application/json"}),timeout=25)
    return json.load(r).get("result")
logs=call("eth_getLogs",[{"address":"0xfffffffffffffffffffffffffffffffffffffffe",
    "topics":["0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"],
    "fromBlock":"0x0","toBlock":"latest"}]) or []
seen=set()
for l in reversed(logs):
    seen.add(l["transactionHash"])
    if len(seen)>=25: break
typed=framed=paired=payer=keys=0
for h in list(seen):
    tx=call("eth_getTransactionByHash",[h]) or {}
    if tx.get("type")!="0x6": continue
    typed+=1
    r=call("eth_getTransactionReceipt",[h]) or {}
    # **`frames` is on the TRANSACTION, `frameReceipts` on the receipt.** Read
    # straight out of `HegotaRead.frames(tx:receipt:)` rather than guessed: the
    # first cut of this row looked for `receipt.frames`, found none, and
    # reported the shape as drifted on a chain where it was perfectly intact —
    # a check that cries wolf gets turned off within a week.
    fr=tx.get("frames") or []
    rr=r.get("frameReceipts") or []
    if fr: framed+=1
    # The app pairs a frame with its receipt BY POSITION and only when the
    # counts agree, so a divergence is what makes every pip go hollow.
    if fr and len(fr)==len(rr): paired+=1
    if r.get("payer"): payer+=1
    if isinstance(tx.get("nonceKeys"),list): keys+=1
print(f"{len(logs)} {typed} {framed} {paired} {payer} {keys}")
PY
)
  if [[ -n "$heg_frames" ]]; then
    read -r flogs ftyped fframed fpaired fpayer fkeys <<< "$heg_frames"
    if [[ "$fframed" -gt 0 ]]; then
      pass "Hegotá — frame transactions still carry frames ($fframed of $ftyped sampled; payer on $fpayer, nonceKeys on $fkeys)"
      if [[ "$fpaired" != "$fframed" ]]; then
        # Counts disagreeing is not a missing field, so it passes every
        # existence check — and in the app it makes EVERY pip draw hollow,
        # because a frame whose receipt cannot be paired is never claimed as a
        # success it cannot support.
        warn "Hegotá — $((fframed - fpaired)) sampled transaction(s) have frames and frameReceipts of different lengths; their steps draw as unknown"
      fi
    elif [[ "$ftyped" -gt 0 ]]; then
      fail "Hegotá — $ftyped type-0x6 transactions carry NO frames array; the Frames scope goes silently empty"
    else
      warn "Hegotá — no type-0x6 transaction among the newest sampled transfers ($flogs logs); the frame shape is unverified tonight"
    fi
  else
    warn "Hegotá — the frame-shape walk did not complete"
  fi
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
