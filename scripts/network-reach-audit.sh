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
  hyperevmscan.io monadscan.com
  gnosisscan.io njump.me
  # Hegota's EXPLORER only — a permalink the PERSON's browser opens on a
  # transaction row.
  #
  # **The faucet used to sit here and no longer may** (prd §531, 2026-08-30).
  # This entry said "the seat deliberately never touches it — the setup screen
  # links out so the person claims their own", which was true when it was
  # written and stopped being true on 2026-08-29, when §525 landed
  # `HegotaSend.claimFaucet` and the key sheet grew a Claim button that POSTs
  # to it. The audit stayed green throughout, because a denylist entry is
  # believed and nothing re-reads its REASON when the code underneath it
  # changes — so the privacy screen omitted a host the app really reaches,
  # which is the build-214 `api.stripe.com` failure this whole gate exists to
  # prevent (prd §205/§289). It is in the reach registry now.
  #
  # Standing lesson: a denylist entry is a claim about CONDUCT, and landing a
  # write is exactly the moment to re-read every entry that says a host is
  # never touched.
  dora.hegota.ethrex.xyz
  dora.frames.ethrex.xyz
  dora.privacy.ethrex.xyz
  # The privacy devnet's faucet PAGE (prd §593). Here for a reason its two
  # siblings' faucets no longer qualify for: this seat is WATCH-ONLY while its
  # type-0x6 envelope is unreproduced (§593a), so the app makes no key and has
  # no address to fund, and the only use of this host is a browser door. The
  # day sending lands, this entry is wrong — faucet.hegota.ethrex.xyz sat here
  # for a day after §525 gave it a Claim button that POSTs to it, so the
  # privacy screen omitted a host the app really reached. Move it to
  # NetworkReach in the same commit that lands the claim, not after.
  # vibenet's own explorer (VibenetExplorer) — a landed event's permalink
  # and the room's "Explorer" door, both `Link(destination:)` the person's
  # own browser opens; this app never fetches chain.base.org itself.
  chain.base.org
  app.0xbow.io app.cal.com app.todoist.com kalshi.com opensea.io
  dexscreener.com twitch.tv reddit.com stocktwits.com farcaster.xyz
  privacy.com polymarket.com app.safe.global app.uniswap.org
  aerodrome.finance app.hyperliquid.xyz
  explorer.altana.network
  cardpointers.com
  # CardPointers' own site (prd §420) — their sign-in page, which the device
  # flow opens in the person's browser, and their CardPointers+ page, offered
  # as the door when an account turns out not to have the subscription. NEVER
  # fetched: every request this app makes goes to `mcp.cardpointers.com`,
  # which IS declared, and that includes the device-flow endpoints.
  # Altana's public explorer (prd §403) — where an account's keys open on tap,
  # and the ONLY place a key can actually be revoked (§112: we read and state,
  # they act). NEVER fetched: the seat reads the keystore CONTRACTS over
  # JSON-RPC, and those hosts ARE disclosed in NetworkReach (the "Altana"
  # entry names all four). The explorer is only ever a link written into a row.
  # Radicle's public explorer (prd §400) — where a patch or issue row opens on
  # tap. NEVER fetched: the bridge reads a SEED NODE's `radicle-httpd` API, and
  # those hosts ARE disclosed in NetworkReach (the "Radicle" entry names both
  # default seeds). The explorer is only ever a link written into a row.
  radicle.network
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
  # AWS's console — where the IAM user and its key pair are created, and
  # where every landed CloudWatch/CodePipeline/Cost Explorer row opens on
  # tap. Never fetched by this app; the real reads are the various
  # `*.amazonaws.com` service hosts, disclosed as a parent domain in the
  # "AWS" NetworkReach entry.
  console.aws.amazon.com
  # PagerDuty's and Vercel's own sites — the pages that mint the key, plus
  # (Vercel) the inspector URL a failed build opens on tap. Never fetched;
  # `api.pagerduty.com` and `api.vercel.com` are the reads, and both ARE
  # disclosed in NetworkReach.
  pagerduty.com vercel.com
  # Conference services (`ConferenceLink.hosts`, 2026-08-14). The app never
  # fetches ONE BYTE from any of these: the list exists to decide whether a
  # link found in a calendar invite may become a "Join" disc, and the tap opens
  # it in the person's own browser or their Zoom/Teams/Meet app. So this is the
  # permalink case in its purest form — a host we recognize precisely so we can
  # hand it off rather than touch it.
  #
  # TRIPWIRE: if anything ever FETCHES one of these — resolving a meeting title,
  # checking whether a room is live — it stops being a permalink and belongs in
  # NetworkReach, because that would be this app reaching a third party on the
  # strength of a link a stranger put in an invite.
  meet.google.com teams.microsoft.com teams.live.com facetime.apple.com
  whereby.com chime.aws gotomeeting.com gotomeet.me bluejeans.com
  join.skype.com around.co riverside.fm
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
  # X's link shortener — appears ONLY in prose. Three comments in
  # XArchiveImport/ScreenshotTopics discuss the `https://t.co/…` shape
  # because handling it correctly is the whole point of those passages: an
  # X archive stores every link as its t.co shortening, and the importer
  # swaps in `entities.urls[].expanded_url` so the shortlink never becomes
  # a title, a topic-map term, or a request. We match against the form and
  # deliberately never send to it. (This scan reads raw source, comments
  # included — the "negative guards must read a comment-stripped copy"
  # lesson CLAUDE.md records for the Obsidian and Cursor self-tests, in a
  # third place. Stripping comments here would be the more general fix;
  # this entry is the narrow one.)
  t.co
)

# A GENERATED CITATION TABLE is excluded from the scan, and this is the one file-level
# exemption here (prd §428).
#
# `L2beatDirectory.swift` is written by `scripts/l2beat-snapshot.py` and holds L2BEAT's own
# `url` for every incident they have recorded — measured 2026-08-21, eleven third-party
# hosts (`forum.arbitrum.foundation`, `status.base.org`, `zksync.mirror.xyz`, …), every one
# of them a page the PERSON's browser opens on tap, never a request this app makes. They
# belong in KNOWN_NON_REACH by category, and listing them by name would be a check that
# cries wolf: the next snapshot regeneration brings a new set and turns this audit red at
# ship time for no reason at all.
#
# The exemption is GUARDED rather than trusted. The file is data by construction — the
# generator emits struct literals and nothing else — so it fails the audit outright if it
# ever gains a way to make a request. The bridge's OWN hosts live in `L2beatHost`, in a
# different file, which is scanned normally.
GENERATED_CITATIONS="L2beatDirectory.swift"
if [[ -f "Casberi/Casberi/Model/$GENERATED_CITATIONS" ]] \
   && grep -qE "URLSession|IngestSupport|getJSON|getText|dataTask|URLRequest" \
      "Casberi/Casberi/Model/$GENERATED_CITATIONS"; then
  echo "network-reach-audit: ✗ $GENERATED_CITATIONS makes a request."
  echo "  It is excluded from the host scan on the promise that it is data only."
  exit 1
fi

# Every host literal the app references (app + shared sources), minus our own
# domain and localhost. Excludes the registry file itself. (bash 3.2-portable —
# no mapfile; macOS ships the old bash.)
HOSTS=$(
  grep -rohE "https://[a-zA-Z0-9.-]+" --include="*.swift" \
    --exclude="$GENERATED_CITATIONS" \
    Casberi/Casberi Casberi/Shared \
    | sed 's|https://||' \
    | grep -viE "casberi\.app|localhost|127\.0\.0\.1|w3\.org|apple\.com/DTD" \
    | sort -u
)

missing=()
# `while read` and never `for host in $HOSTS` — in EVERY loop over a captured
# multi-line string in this file (2026-08-12).
#
# The old form depends on the shell splitting an unquoted expansion on
# whitespace, which bash does and **zsh does not**. Run as `zsh
# network-reach-audit.sh` — overriding the shebang, which is easy to do and
# looks harmless — the whole host list became ONE word, nothing ever matched,
# and the audit reported a FALSE ship-gate failure naming a family that was
# correctly declared two lines away in the registry.
#
# It cost more than an hour, and worse: a bisect "reproduced" the failure at
# every commit going back before the day's work, because each run repeated the
# same harness error. That reads exactly like a long-standing regression. This
# form behaves identically under bash, zsh and sh — checked, all three.
while read -r host; do
  [[ -z "$host" ]] && continue
  # In the registry?
  if grep -q "\"$host\"" "$REGISTRY"; then continue; fi
  # On the explicit non-reach denylist?
  skip=""
  for known in "${KNOWN_NON_REACH[@]}"; do
    [[ "$host" == "$known" ]] && { skip=1; break; }
  done
  [[ -n "$skip" ]] && continue
  missing+=("$host")
done <<< "$HOSTS"

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
  while read -r h; do
    [[ -z "$h" ]] && continue
    [[ "$h" == "$bare" ]] && return 0
    case "$h" in
      *"$tail") [[ $(tr -cd '.' <<< "$h" | wc -c) -eq $want ]] && return 0 ;;
    esac
  done <<< "$declared_hosts"
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
  # Newline-separated, like the real extractor above: the loop in
  # `tail_disclosed` reads LINES, so a space-separated fixture would test
  # a shape the function never actually sees.
  declared_hosts=$(printf '%s\n' substack.com eth-mainnet.g.alchemy.com query1.finance.yahoo.com)
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
while read -r tail; do
  [[ -z "$tail" ]] && continue
  tail_disclosed "$tail" || undisclosed_tails+=("$tail")
done <<< "$BUILT"

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
