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
#   * SCHEDULED since 2026-09-08 (prd §654): `scripts/nightly-live.sh` runs this
#     at 02:45 via `com.casberi.nightly-live` and writes one ledger row per night
#     to scripts/output/nightly-live.log, which verify.sh reads back and REPORTS.
#     Before that, every drift row here printed to a terminal nobody opened.
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
# ── Frames devnet (prd §548, §962) ──────────────────────────────────────────
# The seat's whole subject is a transaction TYPE, and this chain has no
# indexer and no contract behind its shape — so when the wire moves, the room
# does not break, it goes QUIET, drawing a transaction with no frames. That is
# indistinguishable from a transaction that had none (§311's failure).
#
# Since prd §962 (2026-09-27) the seat is on ethpandaops' frames-devnet-0: ONE
# public endpoint load-balanced across geth, nethermind, reth and ethrex. One
# of those answers a type-0x06 read with no frame fields (geth issue 35783,
# ~1 in 4), which the app re-asks (`FramesRPC.bareRetries`) — so every read
# below that needs frames asks up to four times, and reports how many came
# back bare. ethpandaops RELAUNCHES as devnet-1, -2 … with a new chain id: a
# chain-id miss here means edit `FramesNetwork`, re-pin this block, re-measure.
print -P "%F{45}Frames devnet%f (keyless, EIP-8141, frames-devnet-0)"
FR="https://rpc.frames-devnet-0.ethpandaops.io"
FR_ID="0x1a3453829"   # 7034189865 — FramesNetwork.devnet0.chainID
FR_TX="0xa8fb7f5e93869c16a6c93a13fe4b9137a00d6b5676953cac0a55bff144074ed1"   # frames-tx-selftest's vector D0

# Ask up to four times for an answer that carries its frame fields.
fr_full() {  # $1 method, $2 hash, $3 the field that must be there
  local i out
  for i in 1 2 3 4; do
    out=$(raw "$FR" "{\"id\":1,\"jsonrpc\":\"2.0\",\"method\":\"$1\",\"params\":[\"$2\"]}")
    if print -r -- "$out" | python3 -c "import sys,json;r=json.load(sys.stdin).get('result') or {};sys.exit(0 if '$3' in r else 1)" 2>/dev/null; then
      print -r -- "$out"; return 0
    fi
  done
  print -r -- "$out"
}

# 1. The chain id the encoder PINS. A host answering for another chain is a
#    signature sent to the wrong place — or ethpandaops relaunched.
id=$(raw "$FR" '{"id":1,"jsonrpc":"2.0","method":"eth_chainId","params":[]}' \
      | python3 -c 'import sys,json;print(json.load(sys.stdin).get("result",""))' 2>/dev/null)
if [[ "$id" == "$FR_ID" ]]; then
  pass "Frames — the endpoint serves frames-devnet-0 (chain 7034189865)"
  fr_up=1
elif [[ -n "$id" ]]; then
  fail "Frames — the endpoint serves chain $id, not frames-devnet-0; ethpandaops relaunched — edit FramesNetwork, re-pin this block"
  fr_up=0
else
  fail "Frames — the endpoint did not answer; the whole seat reads nothing"
  fr_up=0
fi

if (( fr_up > 0 )); then
  # 2. **The genesis hash.** A relaunch under the SAME id would answer every
  #    read perfectly and with nothing; this is what tells it apart.
  fgen=$(raw "$FR" '{"id":1,"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["0x0",false]}' \
          | python3 -c 'import sys,json;print((json.load(sys.stdin).get("result") or {}).get("hash",""))' 2>/dev/null)
  if [[ "$fgen" == "0xe0dd50fffe934d7f04262f097d24e7b5d286742fc13065c876fc5c683af18c42" ]]; then
    pass "Frames — genesis matches frames-devnet-0 as pinned on 2026-09-27"
  elif [[ -n "$fgen" ]]; then
    warn "Frames — THE DEVNET RESTARTED (genesis is now $fgen); re-pin FR_TX and the genesis here and re-run frames-tx-selftest against a live transaction"
  else
    warn "Frames — the genesis header did not read; the restart check could not run"
  fi

  # 2b. **THE TWO CONTRACTS THE SENDS DEPEND ON (prd §728b, §728d).** Every
  #     send leads with a deadline frame calling the expiry verifier at
  #     0x…8141; a passkey account is installed through the proxy at 0x4e59…
  fexp=$(raw "$FR" '{"id":1,"jsonrpc":"2.0","method":"eth_getCode","params":["0x0000000000000000000000000000000000008141","latest"]}' \
          | python3 -c 'import sys,json;print(json.load(sys.stdin).get("result",""))' 2>/dev/null)
  if [[ "$fexp" == "0x60083614600a575f5ffd5b5f3560c01c4211601657005b5f5ffd" ]]; then
    pass "Frames — the expiry verifier at 0x…8141 is the canonical code every send's deadline frame calls"
  elif [[ -n "$fexp" ]]; then
    fail "Frames — the expiry verifier at 0x…8141 is not the canonical code ($fexp); every send leads with a deadline frame that calls it"
  else
    warn "Frames — the expiry verifier's code did not read"
  fi
  fproxy=$(raw "$FR" '{"id":1,"jsonrpc":"2.0","method":"eth_getCode","params":["0x4e59b44847b379578588920ca78fbf26c0b4956c","latest"]}' \
          | python3 -c 'import sys,json;print(len(json.load(sys.stdin).get("result","0x"))//2-1)' 2>/dev/null)
  if [[ -n "$fproxy" ]] && (( fproxy > 0 )); then
    pass "Frames — the deployment proxy a passkey account is installed through holds code ($fproxy bytes)"
  else
    warn "Frames — the deployment proxy at 0x4e59…956c holds no code; a new passkey account can never be installed on this chain"
  fi

  # 3. **THE ENVELOPE'S OWN FIELD NAMES**, which the encoder is written
  #    against. `frames`/`signatures` on the transaction, and the frame's
  #    `gasLimit` — NOT Hegotá's `executionGasLimit`.
  fshape=$(fr_full eth_getTransactionByHash "$FR_TX" frames | python3 -c '
import sys, json
r = (json.load(sys.stdin).get("result") or {})
if not r: print("gone"); raise SystemExit
f = (r.get("frames") or [{}])[0]
print(":".join([
  r.get("type",""),
  "frames" if r.get("frames") else "-",
  "sigs" if r.get("signatures") else "-",
  "gasLimit" if "gasLimit" in f else ("executionGasLimit" if "executionGasLimit" in f else "-"),
  "stateGasLimit" if "stateGasLimit" in f else "-",
  "nonceKeys" if "nonceKeys" in r else "-",
]))' 2>/dev/null)
  case "$fshape" in
    gone|"")
      warn "Frames — the pinned type-0x06 transaction is gone (a reset, most likely); the envelope's field names are unverified tonight" ;;
    0x6:frames:sigs:gasLimit:stateGasLimit:-)
      pass "Frames — a type-0x06 still carries frames, signatures and both per-frame budgets under the names the encoder writes" ;;
    0x6:-:*)
      warn "Frames — four asks in a row came back without frames; the app re-asks four times too, so rows are going unread tonight" ;;
    *:*:*:executionGasLimit:*)
      fail "Frames — a frame's execution budget is now spelled executionGasLimit (Hegotá's name); every frame in the room draws with no budget" ;;
    *:*:*:*:*:nonceKeys)
      warn "Frames — the chain now serves keyed nonces; the 7-field envelope is wrong" ;;
    *)
      fail "Frames — the type-0x06 shape moved ($fshape); the encoder signs a list the chain no longer hashes" ;;
  esac

  # 4. **Per-frame outcomes**, the reading the whole seat exists for, with the
  #    payer and `stateGasUsed` — reported on every frame on this chain.
  frcpt=$(fr_full eth_getTransactionReceipt "$FR_TX" frameReceipts | python3 -c '
import sys, json
r = (json.load(sys.stdin).get("result") or {})
if not r: print("gone"); raise SystemExit
fr = r.get("frameReceipts") or []
print(":".join([
  str(len(fr)),
  "status" if fr and "status" in fr[0] else "-",
  "payer" if r.get("payer") else "-",
  "stateGasUsed" if fr and all("stateGasUsed" in x for x in fr) else "-",
]))' 2>/dev/null)
  case "$frcpt" in
    gone|"") warn "Frames — the pinned receipt did not read; per-frame outcomes are unverified tonight" ;;
    4:status:payer:stateGasUsed)
      pass "Frames — the receipt decomposes into per-frame outcomes, names its payer, and carries stateGasUsed" ;;
    0:-:-:-)
      warn "Frames — four asks in a row came back without frameReceipts; per-frame outcomes are unverified tonight" ;;
    4:status:payer:-)
      warn "Frames — stateGasUsed has GONE from the receipts; a client change, most likely" ;;
    *) fail "Frames — the receipt shape moved ($frcpt); a row can no longer say what each frame did" ;;
  esac

  # 5. The faucet PAGE is up (the app only opens it — proof-of-work plus
  #    hCaptcha). Its config is a keyless GET that spends nothing.
  fcfg=$(curl -s -m 12 https://faucet.frames-devnet-0.ethpandaops.io/api/getFaucetConfig 2>/dev/null \
          | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("faucetCoinType",""))' 2>/dev/null)
  if [[ "$fcfg" == "native" ]]; then
    pass "Frames — the faucet page is up (Top up opens it)"
  else
    warn "Frames — the faucet page did not answer; Top up opens a page that cannot fund anybody"
  fi
fi

hr
# ── web3.bio (prd §916) ──────────────────────────────────────────────────────
# The resolver behind `ENS` since 2026-09-24, keyless. When it stops answering
# the app falls back to ensideas for ENS and goes QUIET for Base/Linea/
# Farcaster/Lens names — no row breaks, the linked rows simply never draw
# (§311's shape). Pinned to a name whose ENS record cannot lapse quietly.
print -P "%Bweb3.bio%b  (keyless name lookup, api.web3.bio/ns)"
w3b=$(curl -s --max-time "$TIMEOUT" "https://api.web3.bio/ns/vitalik.eth" 2>/dev/null)
if [[ -z "$w3b" ]]; then
  warn "web3.bio — /ns/vitalik.eth did not answer; ENS falls back to ensideas, linked names go quiet"
elif [[ "$w3b" == \[* && "$w3b" == *'"platform":"ens"'* && "$w3b" == *'0xd8da6bf26964af9d7eed9e03e53415d37aa96045'* ]]; then
  pass "web3.bio — /ns answers an array with the ENS record at the measured address"
else
  fail "web3.bio — /ns/vitalik.eth answered in a shape the app does not parse: $(print -r -- "$w3b" | cut -c1-80)"
fi
hr

# ── Wei / Gwei name services (prd §597) ─────────────────────────────────────
# The drift class `wei-names-selftest.sh` structurally cannot see: that harness
# proves the ENCODING is right against fixtures, never that the two contracts
# still answer or still answer in that shape. And when a name service stops
# answering the app does not break, it goes QUIET — every row still draws, no
# name ever appears, which from outside is indistinguishable from "this address
# set no name" (§311's shape, and the reason this row exists).
#
# Pinned to REGISTERED names measured on 2026-09-04, and the expected answers
# are pinned with them: `vitalik.wei` → vitalik's own address, `donnoh.gwei` →
# 0xc046…f1a3. A registration cannot be un-made, so a changed answer here means
# the read moved, not that somebody let a name lapse.
print -P "%BWei / Gwei name registries%b  (keyless eth_call, Ethereum mainnet)"
WNS_C='0x0000000000696760E15f265e828DB644A0c242EB'
GNS_C='0x9D51D507BC7264d4fE8Ad1cf7Fe191933A0a81d6'
ETH_RPC='https://eth.api.onfinality.io/public'
# computeId("vitalik.wei") and computeId("donnoh.gwei"), byte for byte what the
# app builds — see the harness's pinned fixtures.
name_check() {   # $1 label  $2 contract  $3 computeId-calldata  $4 expected 0x address
  local idr addr
  idr=$(raw "$ETH_RPC" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_call\",\"params\":[{\"to\":\"$2\",\"data\":\"$3\"},\"latest\"]}" \
        | sed -nE 's/.*"result":"0x([0-9a-fA-F]{64})".*/\1/p')
  if [[ -z "$idr" ]]; then
    warn "$1 — computeId did not answer; the registry is unreachable tonight"
    return
  fi
  addr=$(raw "$ETH_RPC" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_call\",\"params\":[{\"to\":\"$2\",\"data\":\"0x4f896d4f$idr\"},\"latest\"]}" \
         | sed -nE 's/.*"result":"0x0{24}([0-9a-fA-F]{40})".*/0x\1/p')
  case "$addr" in
    "") warn "$1 — resolve did not answer in the shape we parse" ;;
    0x0000000000000000000000000000000000000000)
        fail "$1 — a name that WAS registered now resolves to the zero address; either the registry moved or resolve() changed" ;;
    "$4") pass "$1 — computeId → resolve still answers $4" ;;
    *)  fail "$1 — resolves to $addr, not the measured $4; the read has drifted" ;;
  esac
}
name_check "WNS · vitalik.wei" "$WNS_C" \
  "0xfb0219390000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000b766974616c696b2e776569000000000000000000000000000000000000000000" \
  "0xd8da6bf26964af9d7eed9e03e53415d37aa96045"
name_check "GNS · donnoh.gwei" "$GNS_C" \
  "0xfb0219390000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000b646f6e6e6f682e67776569000000000000000000000000000000000000000000" \
  "0xc04689227fa24785609b1174698dbe481437f1a3"
# reverseResolve, the half the address book draws. `0x1c0a…5a20` answered
# `ross.wei` when measured; an empty answer here would silently empty every
# name row in the book.
revname=$(raw "$ETH_RPC" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_call\",\"params\":[{\"to\":\"$WNS_C\",\"data\":\"0x9af8b7aa0000000000000000000000001c0aa8ccd568d90d61659f060d1bfb1e6f855a20\"},\"latest\"]}" \
          | python3 -c '
import sys, json, binascii
try:
    r = json.load(sys.stdin).get("result") or ""
    s = r[2:]
    off = int(s[0:64], 16) * 2
    ln = int(s[off:off+64], 16)
    print(binascii.unhexlify(s[off+64:off+64+ln*2]).decode())
except Exception:
    print("")' 2>/dev/null)
case "$revname" in
  ross.wei) pass "WNS · reverseResolve still names 0x1c0a…5a20 as ross.wei" ;;
  "")       warn "WNS — reverseResolve did not answer in the shape we parse; the book's name rows would be empty" ;;
  *)        warn "WNS — reverseResolve now answers '$revname' for 0x1c0a…5a20 (the owner may have changed their primary name)" ;;
esac

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
