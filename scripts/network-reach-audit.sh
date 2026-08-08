#!/usr/bin/env bash
# network-reach-audit.sh — keeps the "What this app reaches" registry honest
# (prd §205). Casberi's privacy promise is "no server, nothing routes through
# us"; the NetworkReach registry (Model/NetworkReach.swift) is how a person
# verifies that. This audit makes the registry COMPLETE BY CONSTRUCTION: every
# host literal in the app must appear EITHER in the registry OR in the explicit
# non-reach denylist below — so a new fetch host added in code that nobody
# disclosed fails the build instead of shipping a silent, unlisted call.
#
# Runs in verify.sh (pure static text check, no build needed). Exit non-zero on
# any unaccounted host.
set -euo pipefail
cd "$(dirname "$0")/.."

REGISTRY="Casberi/Casberi/Model/NetworkReach.swift"

# Hosts that are legitimately NOT data-fetch reaches, so they need no registry
# entry. Three kinds: (1) permalink/display hosts a person opens in their OWN
# browser when they tap a thing — the browser makes that request, not us;
# (2) setup doors — the key/app-password page a connect screen OPENS for you
# (prd §218), which is the same browser-makes-it case wearing a button; the
# service's real API host is the registry entry, and it is a DIFFERENT host
# (api.linear.app vs linear.app, api.privacy.com vs app.privacy.com), so a
# door here can never stand in for an undisclosed fetch; (3) demo/placeholder
# hosts used only in seeded sample content. Adding a host here is a conscious
# "this is not a call this app makes for your data."
KNOWN_NON_REACH=(
  # Block explorers & app permalinks — opened in the browser on tap
  etherscan.io basescan.org arbiscan.io optimistic.etherscan.io
  polygonscan.com solscan.io revoke.cash robinhoodchain.blockscout.com
  gnosisscan.io njump.me
  app.0xbow.io app.cal.com app.todoist.com kalshi.com opensea.io
  dexscreener.com twitch.tv reddit.com stocktwits.com farcaster.xyz
  privacy.com polymarket.com app.safe.global app.uniswap.org
  aerodrome.finance app.hyperliquid.xyz
  # ether.fi's own app — where an unstake row's "claim" and a Cash row open on
  # tap. Never fetched: the reads are public RPC hosts, and those ARE disclosed
  # in NetworkReach (the "ether.fi" and "ether.fi Cash" entries).
  app.ether.fi
  # Setup doors — `setupURL`/`openURL` only, never fetched. Each is the page
  # that mints the key you then paste, opened in your browser.
  app.privacy.com app.raindrop.io calendly.com linear.app www.notion.so
  venice.ai bankr.bot www.kraken.com portal.cdp.coinbase.com
  www.binance.com exchange.gemini.com console.x.ai
  # id.atlassian.com — where a Jira API token is minted. Never fetched: the
  # read is the person's own Jira site, a fully dynamic host disclosed in
  # NetworkReach as prose ("your Jira site"), a different host by construction.
  id.atlassian.com
  # Stripe's dashboard — where a landed row opens on tap, and where you mint
  # the restricted key. Never fetched; `api.stripe.com` is the read, and it
  # IS disclosed in NetworkReach.
  dashboard.stripe.com
  # PagerDuty's and Vercel's own sites — the pages that mint the key, plus
  # (Vercel) the inspector URL a failed build opens on tap. Never fetched;
  # `api.pagerduty.com` and `api.vercel.com` are the reads, and both ARE
  # disclosed in NetworkReach.
  pagerduty.com vercel.com
  # An npm package's own page — where a landed release row opens on tap. Never
  # fetched: the read is `registry.npmjs.org`, which IS disclosed. (PyPI's
  # permalink host and its read host are the same `pypi.org`, so it needs no
  # entry here.)
  www.npmjs.com
  # Circle's own service catalog — the last-resort permalink an x402 row opens
  # on tap, for a provider whose directory entry names no website of its own.
  # Never fetched: the read is `api.circle.com`, a DIFFERENT host, and it IS
  # disclosed in NetworkReach — so this door can't stand in for the call.
  agents.circle.com
  # Mail app-password pages, and the Google Takeout page you download your
  # own Gemini export from — all opened in the browser, none read by us.
  appleid.apple.com myaccount.google.com takeout.google.com
  # The wallet picker's universal links (2026-08-01). Each is a DOOR the person
  # taps to hand the pairing URI to their own wallet app — iOS routes it to the
  # installed app, or to that wallet's web page if it isn't installed. Casberi
  # never fetches any of them. The relay it DOES talk to
  # (relay.walletconnect.org) is the registry entry, and it is a different host,
  # so a door here can't stand in for an undisclosed call.
  metamask.app.link rnbwapp.com go.cb-w.com link.trustwallet.com
  wallet.zerion.io uniswap.org
  # Instagram's own export page — openURL only, the same shape as Takeout
  # above. The bare `instagram.com` literal is NOT here any more: as of
  # 2026-08-02 `InstagramCaptions` really does fetch it (one request per
  # imported save, for the caption), so it belongs in the registry and is
  # disclosed there. `graph.facebook.com` is gone from both lists — the
  # oEmbed entry that reached it was measured dead and removed.
  accountscenter.instagram.com
  # X, and BOTH of its literals are doors rather than calls (2026-08-02).
  # `x.com/settings/download_your_data` is the archive-request page the setup
  # screen opens in your browser, and `x.com/i/web/status/<id>` is the
  # permalink an imported like is STORED as — opened on tap, never fetched:
  # the importers don't run `LinkTitle.enrich`, and a liked row wears the
  # post's own words as its title, so nothing would enrich it anyway.
  #
  # `publish.x.com` is deliberately NOT here. That one IS a call this app
  # makes (the oEmbed read for a saved X link) and it is disclosed in the
  # registry under "Link previews". Different host, so this door can't stand
  # in for that fetch — the property the whole denylist rests on.
  x.com
  # TikTok's export link host — the ONE entry here that is never opened either.
  # A TikTok export writes its links as `www.tiktokv.com/share/video/<id>/`, and
  # `TikTokLink.video` exists to RECOGNISE that form and rewrite it to
  # `www.tiktok.com/video/<id>` before anything is requested — measured
  # 2026-08-02, the share form answers 400 at the oEmbed endpoint and the
  # canonical one answers 200. So this host appears in the source as a string we
  # match against and deliberately never send to. The host we DO reach for these
  # rows is `www.tiktok.com`, disclosed in the registry as "TikTok video names".
  www.tiktokv.com tiktokv.com tiktokv.us
  # Demo / placeholder content only. These are the URLs the furnished demo
  # SEEDS as saved links — rows a person taps to open in their own browser.
  # The demo reaches nothing by design (`BridgeRefresh.refreshAllConnected`
  # returns immediately while `DemoMode.isActive`), so none of these is ever
  # fetched by us.
  picsum.photos www.allbirds.com www.google.com www.nasa.gov
  developer.apple.com developer.mozilla.org www. example.com
)

# Every host literal the app references (app + shared sources), minus our own
# domain and localhost. Excludes the registry file itself. (bash 3.2-portable —
# no mapfile; macOS ships the old bash.)
HOSTS=$(
  grep -rohE "https://[a-zA-Z0-9.-]+" --include="*.swift" \
    Casberi/Casberi Casberi/Shared \
    | sed 's|https://||' \
    | grep -viE "casberi\.app|localhost|127\.0\.0\.1|w3\.org|apple\.com/DTD" \
    | sort -u
)

missing=()
for host in $HOSTS; do
  # In the registry?
  if grep -q "\"$host\"" "$REGISTRY"; then continue; fi
  # On the explicit non-reach denylist?
  skip=""
  for known in "${KNOWN_NON_REACH[@]}"; do
    [[ "$host" == "$known" ]] && { skip=1; break; }
  done
  [[ -n "$skip" ]] && continue
  missing+=("$host")
done

if (( ${#missing[@]} > 0 )); then
  echo "network-reach-audit: ✗ ${#missing[@]} host(s) reach out but aren't disclosed."
  echo "  Add each to NetworkReach.swift (a data-fetch call this app makes) OR"
  echo "  to KNOWN_NON_REACH in this script (a browser permalink / demo host):"
  for h in "${missing[@]}"; do echo "    · $h"; done
  exit 1
fi

# ── Hosts BUILT at runtime (2026-08-03) ────────────────────────────────────
# The scan above reads literals, and `"https://\(chain.network)" + ".g" + …`
# is not one: it starts with an interpolation, so `https://[a-z.-]+` matched
# NOTHING and five Alchemy RPC hosts the wallet reaches on every sweep went
# undisclosed until the receipts screen caught them in the field. Same class as
# the vendored WalletConnect SDK's hosts — a reach the source scan structurally
# cannot see — so it gets its own checks. Two, because one isn't enough:
#
#   A. Every interpolated form must name a family the registry declares. This
#      is coarse ON PURPOSE and its ceiling is real: it proves SOME host in the
#      family is disclosed, not that every host the code can build is. It could
#      not have caught the shipped bug on its own — `api.g.alchemy.com` was
#      declared, and it is a one-label child of the same tail as the five that
#      weren't. It catches a whole family nobody named at all.
#   B. …so the family that actually drifted is checked against its own source
#      of truth: the wallet's chain table. Every `Chain(network: "x")` there
#      becomes `x.g.alchemy.com`, so a new chain must disclose its host the day
#      it lands — the SwiftData-liveness-audit trick of parsing the model
#      instead of remembering it.
#
# A FULLY dynamic build (`https://\(host)/…`, no literal tail at all) can be
# checked by neither and declared by nobody: the host is the person's own
# input. Those are reported as info — each one's record call names its service
# to NetworkLedger instead, which is what the receipts screen reads.
declared_hosts=$(grep -oE '"[a-z0-9-]+(\.[a-z0-9-]+)+"' "$REGISTRY" | tr -d '"' | sort -u)

# Is one interpolated tail (e.g. ".g.alchemy.com") covered by the registry?
# Either the tail is itself a declared host (a parent domain, which covers
# every subdomain exactly as NetworkReach.service(forHost:) does), or some
# declared host is the tail plus ONE label — the label the interpolation
# fills. The label count is the part that matters: without it a single
# `query1.finance.yahoo.com` entry would silently vouch for a code path
# building any `\(x).yahoo.com` it liked.
tail_disclosed() {
  local tail="$1" bare="${1#.}" h
  local want=$(( $(tr -cd '.' <<< "$bare" | wc -c) + 1 ))
  for h in $declared_hosts; do
    [[ "$h" == "$bare" ]] && return 0
    case "$h" in
      *"$tail") [[ $(tr -cd '.' <<< "$h" | wc -c) -eq $want ]] && return 0 ;;
    esac
  done
  return 1
}

# Check C: the hosts this app reaches that are NOT https at all.
#
# The scan at the top of this file is `https://…`, so it is blind by
# construction to a host handed straight to a socket — and the app has exactly
# one of those: `IMAPClient` speaks IMAP itself over NWConnection on port 993,
# and `MailProvider.host` is a bare string. Result (found 2026-08-06, prd
# §324): Apple's and Google's mail servers had been reached since 2026-07-08
# while the screen that lists every host this app reaches named neither. The
# §289 class in a different protocol — a host the literal scan cannot see.
#
# Matched on the `imap.` prefix rather than by parsing `MailProvider`, because
# the failure to catch is a NEW mail host anywhere in the tree, not a
# refactor of that one enum.
imap_hosts() {
  grep -rohE '"imap\.[a-z0-9.-]+"' --include="*.swift" \
    --exclude="$(basename "$REGISTRY")" \
    Casberi/Casberi Casberi/Shared | tr -d '"' | sort -u
}

# Check B's source of truth: the chain table every Alchemy URL is built from.
CHAINS_FILE="Casberi/Casberi/Model/WalletIngest.swift"
alchemy_hosts() {
  grep -oE 'Chain\(network: "[a-z0-9-]+"' "$CHAINS_FILE" \
    | sed -E 's|.*"(.*)"|\1.g.alchemy.com|' | sort -u
}

if [[ "${1:-}" == "--self-test" ]]; then
  # A check that can't fail proves nothing.
  fails=0
  declared_hosts="substack.com eth-mainnet.g.alchemy.com query1.finance.yahoo.com"
  for good in .substack.com .g.alchemy.com .finance.yahoo.com; do
    tail_disclosed "$good" || { echo "self-test ✗ $good should be disclosed"; fails=1; }
  done
  for bad in .g.alchemy.co .yahoo.com .example.com substack.com.evil.example; do
    tail_disclosed "$bad" && { echo "self-test ✗ $bad should NOT be disclosed"; fails=1; }
  done
  # Check A's stated ceiling, asserted rather than assumed: the one-label rule
  # CANNOT tell the declared `api` child from an undeclared `eth-mainnet` one.
  # If this ever starts failing, check A got stronger and check B may be
  # redundant — which is a good day, not a broken test.
  declared_hosts="api.g.alchemy.com"
  tail_disclosed ".g.alchemy.com" || { echo "self-test ✗ check A's ceiling changed"; fails=1; }

  # Check B on the real bug: a chain table with a chain the registry never
  # named must fail, and the same table fully declared must pass.
  CHAINS_FILE=$(mktemp); REGISTRY_REAL="$REGISTRY"; REGISTRY=$(mktemp)
  printf 'Chain(network: "eth-mainnet", explorer: "x")\nChain(network: "base-mainnet", explorer: "y")\n' > "$CHAINS_FILE"
  printf '"api.g.alchemy.com", "eth-mainnet.g.alchemy.com"\n' > "$REGISTRY"
  grep -q "base-mainnet.g.alchemy.com" "$REGISTRY" && { echo "self-test ✗ fixture is wrong"; fails=1; }
  undeclared=$(alchemy_hosts | while read -r h; do grep -q "\"$h\"" "$REGISTRY" || echo "$h"; done)
  [[ "$undeclared" == "base-mainnet.g.alchemy.com" ]] || {
    echo "self-test ✗ check B missed an undeclared chain (saw: ${undeclared:-none})"; fails=1; }
  printf '"eth-mainnet.g.alchemy.com", "base-mainnet.g.alchemy.com"\n' > "$REGISTRY"
  undeclared=$(alchemy_hosts | while read -r h; do grep -q "\"$h\"" "$REGISTRY" || echo "$h"; done)
  [[ -z "$undeclared" ]] || { echo "self-test ✗ check B flagged a declared chain: $undeclared"; fails=1; }
  rm -f "$CHAINS_FILE" "$REGISTRY"; REGISTRY="$REGISTRY_REAL"

  # Check C on the real bug: an IMAP host the registry never named must fail,
  # and the same host declared must pass. The scan itself is exercised against
  # the real tree below (it must find the three mail hosts) — a membership
  # test that runs over an empty host list passes for the wrong reason, which
  # is precisely how this gap survived a year of green audits.
  found=$(imap_hosts | wc -l | tr -d ' ')
  (( found >= 1 )) || { echo "self-test ✗ the IMAP scan found no hosts at all"; fails=1; }
  REGISTRY_REAL="$REGISTRY"; REGISTRY=$(mktemp)
  printf '"imap.gmail.com"\n' > "$REGISTRY"
  undeclared=$(printf 'imap.gmail.com\nimap.example.com\n' \
    | while read -r h; do grep -q "\"$h\"" "$REGISTRY" || echo "$h"; done)
  [[ "$undeclared" == "imap.example.com" ]] || {
    echo "self-test ✗ check C missed an undeclared IMAP host (saw: ${undeclared:-none})"; fails=1; }
  printf '"imap.gmail.com", "imap.example.com"\n' > "$REGISTRY"
  undeclared=$(printf 'imap.gmail.com\nimap.example.com\n' \
    | while read -r h; do grep -q "\"$h\"" "$REGISTRY" || echo "$h"; done)
  [[ -z "$undeclared" ]] || { echo "self-test ✗ check C flagged a declared host: $undeclared"; fails=1; }
  rm -f "$REGISTRY"; REGISTRY="$REGISTRY_REAL"

  (( fails )) && exit 1
  echo "network-reach-audit: self-test OK"
  exit 0
fi

# The registry is excluded: it makes no calls, and its own prose describes
# these very URL shapes (a comment that wraps mid-host would otherwise read
# as a half-host nobody declared).
BUILT=$(
  grep -rohE 'https://\\\([^)]*\)[a-zA-Z0-9.-]+' --include="*.swift" \
    --exclude="$(basename "$REGISTRY")" \
    Casberi/Casberi Casberi/Shared \
    | sed -E 's|https://\\\([^)]*\)||' \
    | sort -u
)

undisclosed_tails=()
for tail in $BUILT; do
  tail_disclosed "$tail" || undisclosed_tails+=("$tail")
done

if (( ${#undisclosed_tails[@]} > 0 )); then
  echo "network-reach-audit: ✗ ${#undisclosed_tails[@]} host family(ies) built at runtime aren't disclosed."
  echo "  A host assembled from a variable is invisible to the literal scan above."
  echo "  Name the real hosts in NetworkReach.swift (list them out, or the parent"
  echo "  domain when any subdomain is fair game):"
  for t in "${undisclosed_tails[@]}"; do echo "    · *$t"; done
  exit 1
fi

undeclared_chains=()
while read -r host; do
  [[ -z "$host" ]] && continue
  grep -q "\"$host\"" "$REGISTRY" || undeclared_chains+=("$host")
done <<< "$(alchemy_hosts)"

if (( ${#undeclared_chains[@]} > 0 )); then
  echo "network-reach-audit: ✗ ${#undeclared_chains[@]} Alchemy chain host(s) aren't disclosed."
  echo "  Every chain in $CHAINS_FILE builds its own RPC host; add each to the"
  echo "  Wallet entry in NetworkReach.swift:"
  for h in "${undeclared_chains[@]}"; do echo "    · $h"; done
  exit 1
fi

undeclared_imap=()
while read -r host; do
  [[ -z "$host" ]] && continue
  grep -q "\"$host\"" "$REGISTRY" || undeclared_imap+=("$host")
done <<< "$(imap_hosts)"

if (( ${#undeclared_imap[@]} > 0 )); then
  echo "network-reach-audit: ✗ ${#undeclared_imap[@]} mail server(s) reached but not disclosed."
  echo "  IMAP isn't https, so the literal scan above cannot see these at all."
  echo "  Add each to the Mail section of NetworkReach.swift:"
  for h in "${undeclared_imap[@]}"; do echo "    · $h"; done
  exit 1
fi

DYNAMIC=$(
  grep -rlE 'https://\\\([a-zA-Z0-9_.]+\)(/|"|\?)' --include="*.swift" \
    Casberi/Casberi Casberi/Shared | sort -u
)
if [[ -n "$DYNAMIC" ]]; then
  echo "network-reach-audit: info — host comes from the person's own input in:"
  echo "$DYNAMIC" | sed 's|^|    · |'
  echo "    (not declarable; each must name its service to NetworkLedger.record)"
fi

echo "network-reach-audit: OK — every host is disclosed in the reach registry or the non-reach denylist."
