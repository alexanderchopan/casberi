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
  # Setup doors — `setupURL`/`openURL` only, never fetched. Each is the page
  # that mints the key you then paste, opened in your browser.
  app.privacy.com app.raindrop.io calendly.com linear.app www.notion.so
  venice.ai bankr.bot www.kraken.com portal.cdp.coinbase.com
  www.binance.com exchange.gemini.com
  # Mail app-password pages, and the Google Takeout page you download your
  # own Gemini export from — all opened in the browser, none read by us.
  appleid.apple.com myaccount.google.com takeout.google.com
  # Demo / placeholder content only
  picsum.photos www.allbirds.com www.google.com www.nasa.gov
  developer.apple.com www. example.com
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

echo "network-reach-audit: OK — every host is disclosed in the reach registry or the non-reach denylist."
