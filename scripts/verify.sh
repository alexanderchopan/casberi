#!/bin/zsh
# Casberi deterministic verify: build → install → screen sweep → answer probe.
# Exit 0 = everything green. Screenshots land in scripts/output/<timestamp>/.
#
# Usage: scripts/verify.sh [--build-only]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="$HOME/Library/Developer/CasberiDD"          # NEVER build inside iCloud Drive (codesign xattr failure)
DEVICE="iPhone 17 Pro"
BUNDLE="com.casberi.app"
OUT="$ROOT/scripts/output/$(date +%Y%m%d-%H%M%S)"
# Created HERE, not at the screenshot sweep that used to be its first writer
# (2026-08-13). Any earlier step that wants to keep a log — the category-fold
# self-test does — otherwise redirects into a directory that does not exist
# yet, and under `set -e` the failed redirect fails the step it was meant to
# make diagnosable.
mkdir -p "$OUT"

step() { print -P "%F{cyan}▶ $1%f"; }
fail() { print -P "%F{red}✗ $1%f"; exit 1; }

# ── 0. Catalog sync (static, fast — fails before the slow build) ────
# Enforces BridgeCatalog.offers as the single source of truth for the app
# catalog, the website #catalog shelf, and the onboarding tiles. See the
# catalog-sync RULE in CLAUDE.md.
step "Catalog sync"
"$ROOT/scripts/catalog-sync.sh" || fail "catalog surfaces drifted — run scripts/catalog-sync.sh"
print -P "%F{green}✓ catalog sync%f"

# Keeps the "What this app reaches" registry complete (prd §205): every host
# the app calls must be disclosed in NetworkReach.swift or the explicit
# non-reach denylist — an undisclosed fetch host fails here.
step "Network-reach audit"
"$ROOT/scripts/network-reach-audit.sh" --self-test >/dev/null \
  || fail "the network-reach audit's own self-test failed — the check is broken, not the code"
"$ROOT/scripts/network-reach-audit.sh" || fail "a network host isn't disclosed — see scripts/network-reach-audit.sh"
print -P "%F{green}✓ network-reach audit%f"

# THE DEMO REACHES NOTHING, checked at the function that reads the network,
# not at whichever caller happens to be gated today (2026-08-15). This is
# ENS.swift's own version of the rule `WalletIngest.holdings()` already
# follows: `resolve`/`reverseName`/`avatar` are the ONLY doors to
# api.ensideas.com, and every one of them must refuse before its network
# read when `DemoMode.isActive`. Caught live: `WalletScreen.onAppear` calls
# `WalletStore.loadAvatars()` directly, bypassing `BridgeRefresh`'s demo
# early-return, and nothing downstream noticed until the dynamic "Demo
# reaches nothing" step (further down) had its own false-positive fixed —
# a dirty NetworkLedger from real testing had been hiding a real leak
# behind 29 lines of noise. This static check is cheap insurance against
# a FOURTH caller doing the same thing silently: it can't prove the demo
# reaches nothing (only the dynamic step, on-device, can), but it can prove
# the one choke point every caller goes through still refuses.
step "ENS demo gate"
ENS_FILE="$ROOT/Casberi/Casberi/Model/ENS.swift"
for fn in "static func resolve" "static func reverseName" "static func avatar"; do
  # The guard must appear in the ~3 lines after the signature — right at the
  # top, before any network read, not merely somewhere in the function body.
  if ! awk -v fn="$fn" 'index($0, fn) { found=1; count=0 }
       found && count<=3 { if (index($0, "DemoMode.isActive")) { print "OK"; exit }; count++ }' \
       "$ENS_FILE" | grep -q OK; then
    fail "ENS.$(echo "$fn" | awk '{print $NF}') has no DemoMode.isActive guard at its top — see scripts/verify.sh's own comment above this check"
  fi
done
print -P "%F{green}✓ ens demo gate (resolve/reverseName/avatar all refuse in demo)%f"

# Keeps every catalogued Info.plist key carrying a real source-language value
# (ITMS-90738). Static, no build — and the only gate that can see this class:
# a key with no `en` entry compiles to its own key NAME in en.lproj and
# overrides the target's INFOPLIST_KEY_* string, so builds 267/268 shipped
# every permission prompt reading "NSPhotoLibraryUsageDescription" and the
# app name reading "CFBundleDisplayName". xcodebuild succeeded, the sweep
# passed, and App Store Connect caught it hours after upload, by email.
step "Info.plist strings audit"
"$ROOT/scripts/infoplist-strings-audit.py" --self-test >/dev/null \
  || fail "the Info.plist strings audit's own self-test failed — the check is broken, not the code"
"$ROOT/scripts/infoplist-strings-audit.py" || fail "a purpose string resolves to its own key name — see the output above"
print -P "%F{green}✓ infoplist strings audit%f"

# Keeps the product ledger navigable (docs/prd.md). Static, no build. Every
# rule in this repo is cited by `§N` from CLAUDE.md, the audits and ~200 places
# in the source, and until 2026-08-11 nothing checked that one of them resolved:
# twenty-two numbers named two unrelated rulings each, two sections shipped as
# H1, and a whole day of work (nine commits on 2026-08-08) landed with no entry
# at all while forty-eight comments cited its number. All of it invisible — a
# wrong `§N` in a comment builds, ships, and answers confidently and wrongly.
step "PRD index audit"
"$ROOT/scripts/prd-index-audit.py" --self-test >/dev/null \
  || fail "the PRD index audit's own self-test failed — the check is broken, not the ledger"
"$ROOT/scripts/prd-index-audit.py" || fail "the PRD ledger's numbering or citations drifted — see the output above"
print -P "%F{green}✓ prd index audit%f"

# The Themes treemap draws every tag it isn't told to exclude, so a bridge's own
# state label ("Post", "Watchlist", "Pending") clusters as a THEME — and being
# machine-stamped on every row it lands, it outnumbers any real subject by
# orders of magnitude and takes the cells. Mechanical because the failure is
# invisible: the map renders perfectly, and only someone who knows what their
# own corpus is about can see the cell is bookkeeping. `mechanicalTags`'s facet
# half derives from `Retriever.facetTags`; this is what keeps its hand half —
# the bridge status labels, which have no registry to read — provably complete.
step "Theme tags audit"
"$ROOT/scripts/theme-tags-audit.py" --self-test >/dev/null \
  || fail "the theme-tags audit's own self-test failed — the check is broken, not the tree"
"$ROOT/scripts/theme-tags-audit.py" || fail "a stamped tag is ruled neither subject nor mechanical — see the output above"
print -P "%F{green}✓ theme tags audit%f"

# Keeps the connect pages from regrowing their wall of text (prd §315).
# Static, no build. It is mechanical for the reason every rule in this file is
# mechanical: the copy has now been de-walled twice from memory (§218b's "one
# gray sentence", §314's single footer) and grown back both times — by §315
# Instagram's connect page ran ~145 words before you had done anything, and the
# fact that mattered most ("this is an import, nothing syncs") was last on the
# screen in the tier reserved for timestamps.
step "Setup copy audit"
"$ROOT/scripts/setup-copy-audit.py" --self-test >/dev/null \
  || fail "the setup copy audit's own self-test failed — the check is broken, not the code"
"$ROOT/scripts/setup-copy-audit.py" || fail "a connect page drifted past its copy budget — see the output above"
print -P "%F{green}✓ setup copy audit%f"

# Keeps every Keychain write device-only and non-syncing (prd §277). Static,
# no build. The failure it catches is invisible at runtime — a key stored with
# the wrong accessibility works perfectly and also rides an encrypted backup
# onto another device — so it can only ever be caught mechanically.
# Keeps the "Hide wallet balances" toggle's promise true (prd §374). A wallet
# view that calls a raw formatter instead of `WalletValue` renders perfectly
# and leaks the figure the setting says it hides, while the toggle still sits
# in Privacy claiming otherwise — invisible at runtime, so mechanical or not at
# all. Static, no build.
step "Hide-balances audit"
python3 "$ROOT/scripts/hide-balances-audit.py" --self-test >/dev/null \
  || fail "the hide-balances audit's own self-test failed — the check is broken, not the code"
python3 "$ROOT/scripts/hide-balances-audit.py" \
  || fail "a wallet view prints a figure outside the §374 gate — see the output above"
print -P "%F{green}✓ hide-balances audit%f"

step "Keychain policy audit"
"$ROOT/scripts/keychain-audit.py" --self-test >/dev/null \
  || fail "the keychain audit's own self-test failed — the check is broken, not the code"
"$ROOT/scripts/keychain-audit.py" || fail "a keychain write isn't device-only — see the output above"
print -P "%F{green}✓ keychain audit%f"

# Keeps the receipts screen's coverage claim true (prd §277). A new bridge
# written with its own URLSession is invisible to the ledger, and the screen
# goes on implying it saw everything — which is exactly how the first version
# of this feature shipped.
step "Receipts coverage audit"
"$ROOT/scripts/receipts-coverage-audit.py" --self-test >/dev/null \
  || fail "the receipts audit's own self-test failed — the check is broken, not the code"
"$ROOT/scripts/receipts-coverage-audit.py" || fail "a network call isn't recorded — see the output above"
print -P "%F{green}✓ receipts coverage audit%f"

# Every stored `Thing` property has a CloudKit field (docs/cloudkit-deploy.md).
# A TestFlight/App Store build mirrors to PRODUCTION and CloudKit never
# auto-creates schema there, so an undeployed field doesn't fail loudly — plain
# notes keep syncing while every voice note, social post and screenshot fails
# its export forever. Found 25 fields behind on 2026-08-01, invisible for
# months. Static: it proves the model matches the checked-in snapshot, which
# makes the deploy impossible to FORGET; `--live production` is what proves it
# HAPPENED, and stays out of here because it needs network.
step "CloudKit schema audit"
"$ROOT/scripts/cloudkit-schema-audit.py" --self-test >/dev/null \
  || fail "the CloudKit schema audit's own self-test failed — the check is broken, not the code"
"$ROOT/scripts/cloudkit-schema-audit.py" || fail "a Thing property has no CloudKit field — see the output above"
print -P "%F{green}✓ cloudkit schema audit%f"

# The credential tripwire's fixtures (prd §277) — that the shipped patterns and
# thresholds still hide a recovery phrase and still leave an ordinary shopping
# list alone. Reads both out of the Swift source, so re-tuning a number here
# fails rather than silently changing what the app hides.
step "Secret-scan self-test"
"$ROOT/scripts/secret-scan-selftest.py" || fail "the credential tripwire changed behaviour — see the output above"
print -P "%F{green}✓ secret-scan self-test%f"

# The recurring "reads a dead Thing" crash class (builds 137/138/139/142/150 —
# five TestFlight-found crashes, one defect). The rule was written down and
# re-broken twice because memory was enforcing it; this makes it mechanical.
# `--self-test` runs first on purpose: a check that cannot fail proves nothing,
# so the audit demonstrates it catches each shape before it certifies the tree.
step "SwiftData liveness audit"
"$ROOT/scripts/swiftdata-liveness-audit.py" --self-test >/dev/null \
  || fail "the liveness audit's own self-test failed — the check is broken, not the code"
"$ROOT/scripts/swiftdata-liveness-audit.py" || fail "a Thing is read without a liveness guard — see the output above"
print -P "%F{green}✓ swiftdata liveness audit%f"

# A BOUNDED `@Query`'s `.count` is not a change signal (2026-08-12). Static,
# self-tested, no build. It exists because the failure is SILENT and unreachable
# from here: past the fetch bound the count stops changing, so the watcher keyed
# on it simply never fires again — which shipped in both `FeedScreen` and
# `MainSurface` for five days, on corpora larger than any simulator carries.
# See the script's own header.
"$ROOT/scripts/query-count-signal-audit.py" --self-test >/dev/null \
  || fail "the query-count-signal audit's own self-test failed — the check is broken, not the code"
"$ROOT/scripts/query-count-signal-audit.py" || fail "a bounded @Query's count is used as a change signal — see the output above"
print -P "%F{green}✓ query-count-signal audit%f"

# The parity a Catalyst COMPILE cannot see (2026-08-12). Step 1b proves the
# Mac still BUILDS; this is the half that proves nothing quietly went
# Mac-shaped-but-broken — a screen no pass ever opens, an entitlement that
# fails a signed archive weeks later at ship time, a ⌘-digit aimed at a room
# the strip no longer shows there. All three read a REGISTRY IN THE SOURCE
# rather than a hand list, so a new screen/capability/shortcut is covered the
# day it lands and nobody has to remember to flag it.
step "Mac parity audit"
python3 "$ROOT/scripts/mac-parity-audit.py" --self-test >/dev/null \
  || fail "the Mac parity audit's own self-test failed — the check is broken, not the code"
python3 "$ROOT/scripts/mac-parity-audit.py" || fail "Mac parity drifted — see the output above"
print -P "%F{green}✓ mac parity audit%f"

# Demo↔bridge parity: does the demo produce the same SHAPE of record the real
# bridge produces? `demo-selftest.py` checks the demo against itself and the
# catalog; this asks whether a seeded row could pass for a real one. Its own
# self-test runs first — a check that cannot fail proves nothing.
step "Demo parity audit"
python3 "$ROOT/scripts/demo-parity-audit.py" --self-test >/dev/null \
  || fail "the demo parity audit's own self-test failed — the check is broken, not the code"
python3 "$ROOT/scripts/demo-parity-audit.py" || fail "demo parity drifted — see the output above"
print -P "%F{green}✓ demo parity audit%f"

# ── Self-test COMPLETENESS guard (2026-08-12) ───────────────────────
# The self-tests below are hand-listed, because the comment above each one is
# the only written record of WHY that harness exists and what silent wrong
# answer it catches — collapsing them into a glob would run the same checks
# and throw all of that away. A hand list is fine; a hand list nobody proves
# COMPLETE is not, and this one had quietly drifted: `address-safety`,
# `chatimport`, `claudecode`, `cursor-room`, `frontpage`, `keccak256` and
# `wallet-viz` all existed in `scripts/` and were never run by this pass, so
# seven harnesses someone wrote to protect seven features had been dead
# weight — passing or failing, nobody would have known. `verify-mac.sh` ran
# them the whole time (it globs), so the MAC pass had strictly more logic
# coverage than the iOS one.
#
# So: keep the list, keep the reasons, and make the list provable. This is
# `catalog-sync.sh`'s own shape — a hand-curated set is allowed, as long as
# every member resolves and nothing real is missing from it. A new harness
# fails this pass until it is named below WITH its reason, which is the point:
# the reason is the part that gets skipped when it isn't enforced.
step "Self-test completeness"
typeset -a UNWIRED
for _st in "$ROOT"/scripts/*-selftest.sh; do
  grep -q "${_st:t}" "$0" || UNWIRED+=("${_st:t}")
done
(( ${#UNWIRED} == 0 )) \
  || fail "self-test never run by verify.sh: ${UNWIRED[*]} — add it below with a comment saying what it catches"
print -P "%F{green}✓ self-test completeness ($(ls "$ROOT"/scripts/*-selftest.sh | wc -l | tr -d ' ') wired)%f"

# ── The seven the guard above found unwired (2026-08-12) ────────────
# Each existed in `scripts/` and had never once run in this pass. Grouped
# rather than scattered so the gap they came from stays legible.

# Keccak-256 (`Model/Keccak256.swift`), checked against pycryptodome ground
# truth and EIP-55's four published vectors. A hand-rolled crypto primitive
# that drifts from a separately-maintained copy of its tests is worse than no
# primitive: a wrong checksum is a DIFFERENT BUT VALID address, with no crash
# and no warning — and the wrong wallet/Safe label rides along with it.
step "Keccak-256 self-test"
"$ROOT/scripts/keccak256-selftest.sh" >/dev/null \
  || fail "the Keccak-256 self-test failed — run scripts/keccak256-selftest.sh"
print -P "%F{green}✓ keccak256 self-test%f"

# Address safety (`Model/AddressSafety.swift`). Both functions are pure and
# both fail SILENTLY: a checksum check that answers `unavailable` for
# everything simply never warns, and a lookalike test with a mis-shaped
# display key finds nothing. Neither has any on-screen symptom — the screen
# looks exactly as safe as it did before.
step "Address-safety self-test"
"$ROOT/scripts/address-safety-selftest.sh" >/dev/null \
  || fail "the address-safety self-test failed — run scripts/address-safety-selftest.sh"
print -P "%F{green}✓ address-safety self-test%f"

# Wallet visualizations — the flow band's grouping, the distance-to-liquidation
# axis, the stable share. Arithmetic behind three cards that render perfectly
# whatever number is in them (it already caught an unparseable allowance
# printing "$0", i.e. "reaches nothing" for a grant we had failed to read).
step "Wallet-visualization self-test"
"$ROOT/scripts/wallet-viz-selftest.sh" >/dev/null \
  || fail "the wallet-visualization self-test failed — run scripts/wallet-viz-selftest.sh"
print -P "%F{green}✓ wallet-viz self-test%f"

# The WalletConnect picker's arithmetic (`Model/WalletConnectPlan.swift`, prd
# §376). The bug it replaces was unreportable, not merely unnoticed: the
# connect door looped `WalletStore.add` over every shared account and flagged
# trouble only when EVERY add failed, so the 5-wallet cap ate the overflow in
# silence — and nobody knows how many accounts their wallet chose to share, so
# there was no number to notice was wrong. `overflow` is that number, and
# nothing in the app represented it before this. No simulator can reach the
# real path (no wallet app claims `wc:` there, so `-wcConnectProbe` can only
# ever time out), which makes this harness the only proof these numbers hold.
step "WalletConnect-picker self-test"
"$ROOT/scripts/wallet-connect-plan-selftest.sh" >/dev/null \
  || fail "the WalletConnect-picker self-test failed — run scripts/wallet-connect-plan-selftest.sh"
print -P "%F{green}✓ wallet-connect-plan self-test%f"

# The three chat import rooms (ChatGPT / Claude / Gemini) — the shared flatten
# and clamp, plus ChatGPT's GRAPH walk, which must recover conversation order
# rather than dictionary order. A transcript in the wrong order still reads as
# a transcript.
step "Chat-import self-test"
"$ROOT/scripts/chatimport-selftest.sh" >/dev/null \
  || fail "the chat-import self-test failed — run scripts/chatimport-selftest.sh"
print -P "%F{green}✓ chat-import self-test%f"

# Claude Code import (`ClaudeCodeSession`, compiled WHOLE — Foundation-only by
# design, which is why it is a separate type from the SwiftData landing beside
# it).
step "Claude Code import self-test"
"$ROOT/scripts/claudecode-selftest.sh" >/dev/null \
  || fail "the Claude Code import self-test failed — run scripts/claudecode-selftest.sh"
print -P "%F{green}✓ claude code self-test%f"

# The Cursor feed-room head (prd §340), compiled WHOLE and unmodified. Its
# room is the one whose rows are grouped by a field the bridge stamps
# elsewhere, so a nil head and a correct empty room look identical.
step "Cursor-room self-test"
"$ROOT/scripts/cursor-room-selftest.sh" >/dev/null \
  || fail "the Cursor-room self-test failed — run scripts/cursor-room-selftest.sh"
print -P "%F{green}✓ cursor-room self-test%f"

# The brief's two-column front page (prd §274) — the chapter parse, the ref
# segments cut at each opener, and what spans full width. A mis-cut segment
# lays out cleanly and silently drops or duplicates a chapter's refs.
step "Front-page self-test"
"$ROOT/scripts/frontpage-selftest.sh" >/dev/null \
  || fail "the front-page self-test failed — run scripts/frontpage-selftest.sh"
print -P "%F{green}✓ front-page self-test%f"

# Pure-logic self-test for the X work (prd §280). Static, no build, no
# network: the archive importer was authored against no real X archive, and
# its failure mode is a silent wrong answer — a misdated like, a file that
# parses to zero rows and reads as an empty account. Runs here with the rest
# of the static head so it's part of `verify.sh` rather than something to
# remember (the reach-audit lesson, 2026-07-31).
step "X pure-logic self-test"
"$ROOT/scripts/x-selftest.sh" >/dev/null \
  || fail "the X logic self-test failed — run scripts/x-selftest.sh"
print -P "%F{green}✓ x self-test%f"

# The All feed's fold decisions (prd §377/§378/§379). Every failure it catches
# is a silent wrong answer on the LANDING SCREEN that renders perfectly: a
# screenshot run collapsing into a sentence about it, five songs off one record
# drawn as four identical covers, the next-up calendar event folded away (§35
# ruled that must never happen and until §377 nothing enforced it), or a
# transaction receding because the fold was scored on its first member. These
# rules lived as private methods inside a 5,000-line SwiftUI view until §379
# pulled them into `Model/FeedFold.swift` for exactly this reason — §255 is the
# record of what an unprovable fold rule costs (a gate that measured THINGS
# while the feed drew ROWS, wrong for a month, found by eye).
step "Feed-fold self-test"
"$ROOT/scripts/feed-fold-selftest.sh" >/dev/null \
  || fail "the feed-fold self-test failed — run scripts/feed-fold-selftest.sh"
print -P "%F{green}✓ feed-fold self-test%f"

# "Is this address a feed?" — the discriminator every RSS follow hangs off
# (2026-08-16), from a user report of following a site that publishes none.
# Every failure it catches is invisible to a build, a screen sweep AND a landed
# count, because the address answers 200 with zero failures: a follow that can
# never produce a post reading as perfectly healthy forever (§83), a web page's
# own `<title>` adopted as the feed's name, a real-but-empty feed sending an
# eight-request crawl off its host on every refresh, and a crawl cut short by
# its own time budget muting a good address for a week. It also guards the two
# bounds — a per-candidate timeout and a total crawl budget — that keep one
# slow host from pinning the whole bridge, which is the reported symptom.
step "RSS discovery self-test"
"$ROOT/scripts/rss-discovery-selftest.sh" >/dev/null \
  || fail "the RSS discovery self-test failed — run scripts/rss-discovery-selftest.sh"
print -P "%F{green}✓ RSS discovery self-test%f"

# Pure-logic self-test for the Cloudflare DNS change detector (prd §296). Same
# reasoning as the X harness above: the bridge was authored against Cloudflare's
# published API reference with no token and no authenticated access, and every
# failure in `diffDNS` is a silent wrong answer that renders perfectly — a
# partial read reporting live records as deleted, a proxy flag flipped off
# passing as no change, a second change to a record deduping into the first.
step "Cloudflare pure-logic self-test"
"$ROOT/scripts/cloudflare-selftest.sh" >/dev/null \
  || fail "the Cloudflare logic self-test failed — run scripts/cloudflare-selftest.sh"
print -P "%F{green}✓ cloudflare self-test%f"

# Pure-logic self-test for the Cursor bridge (prd §303). Stronger reason than
# the two above: those bridges COULD be measured by someone who mints a key,
# while Cursor's own docs and forum contradict each other on whether an
# individual on a personal plan can mint a Cloud Agents key at all — so
# `-cursorProbe` may be unavailable to this project indefinitely and this is
# the only proof the bridge will ever have. It also carries the CONDUCT guard:
# a Cursor key has no scopes, so the catalog's "never starts one, follows one
# up, stops one, or deletes one" is kept only by that file issuing GET alone.
# That promise was prose in the source; here it is mechanical.
step "Cursor pure-logic self-test"
"$ROOT/scripts/cursor-selftest.sh" >/dev/null \
  || fail "the Cursor logic self-test failed — run scripts/cursor-selftest.sh"
print -P "%F{green}✓ cursor self-test%f"

# Circle x402 (2026-08-06). Unlike the harnesses above this bridge IS
# measurable — the directory is keyless — and that is exactly why it needs one:
# a live curl proves the wire shape and proves nothing about the arithmetic
# downstream of it. Every failure it catches renders perfectly. It also carries
# two guards worth more than the assertions: the read must never go back to the
# API's own `category` filter (which accepts six of the seven values its own
# data carries, so a server-side filter silently drops 19% of the marketplace),
# and the file must never gain a write verb or read a `payTo` — this is a
# PAYMENT protocol, and "Casberi never pays for a call" is kept by conduct.
# App Store Connect (2026-08-06, prd §323). Its conduct guard is the strongest
# reason any harness here exists: an App Store Connect key carries a ROLE, not
# scopes, and no role is read-only for what this bridge reads — the narrowest
# one that works can also upload a build and submit a version. "Casberi only
# ever reads" is kept by that one file issuing GET alone. It also pins the
# claim set: `iss` and `sub` are mutually exclusive in Apple's token spec, and
# getting it wrong is a 401 indistinguishable from a wrong key.
step "App Store Connect pure-logic self-test"
"$ROOT/scripts/appstoreconnect-selftest.sh" >/dev/null \
  || fail "the App Store Connect logic self-test failed — run scripts/appstoreconnect-selftest.sh"
print -P "%F{green}✓ app store connect self-test%f"

step "Circle x402 pure-logic self-test"
"$ROOT/scripts/x402-selftest.sh" >/dev/null \
  || fail "the x402 logic self-test failed — run scripts/x402-selftest.sh"
print -P "%F{green}✓ x402 self-test%f"

# The contract between the app and its Home Screen (prd §382, 2026-08-14).
# Mechanical because the widget extension is the ONE surface nothing else in
# this pass can see: `xcodebuild` compiles it and never runs it, the screen
# sweep drives the app rather than the Home Screen, and no probe can attach to
# another process's timeline. Every failure it catches draws a perfectly
# good-looking tile — a flat wallet curve along the FLOOR (which reads as "went
# to zero"), a reading from yesterday printed as current, a change that rounds
# to zero painted green, or a publish that spends the system's reload budget on
# every foreground. It found that last one on its first run: comparing the
# serialized BYTES of two identical payloads reports a change every time,
# because `JSONEncoder` is not byte-stable.
step "Widget payload self-test"
"$ROOT/scripts/widget-selftest.sh" >/dev/null \
  || fail "the widget self-test failed — run scripts/widget-selftest.sh"
print -P "%F{green}✓ widget self-test%f"

# The sources tray's row packer (2026-08-10). Mechanical because the failure is
# INVISIBLE: a tray packed one row worse than it could be renders perfectly, it
# is just taller — and past the 620pt resting cap "taller" means the picker
# scrolls, which is the one thing this tray has been redesigned three times to
# avoid. The harness carries the exact optimiser the app deliberately does NOT
# ship, and proves the three-line sort still ties it.
step "Sources-tray packing self-test"
"$ROOT/scripts/source-packing-selftest.sh" >/dev/null \
  || fail "the sources-tray packing self-test failed — run scripts/source-packing-selftest.sh"
print -P "%F{green}✓ source packing self-test%f"

# Every folded chip's ordering and resolution rules (prd §351, 2026-08-11 —
# supersedes the Markets-only harness this line used to run, generalizing it
# to every catalog category, unconditionally folded). Mechanical for the
# reason every rule in this file is: the failures render as a perfectly good
# strip. A fold that lands at the TAIL silently moves the one chip whose
# position you had learned; a `chipLabel` that hands back the raw source lights
# no chip at all while you stand in the room; and a category LABEL reaching
# `FeedFilter.source` puts that name into every query and deep link, where it
# matches nothing forever with no error anywhere.
step "Category fold self-test"
# Output KEPT, not discarded (2026-08-13). This test has now failed twice
# inside a full run and passed standalone every time it was re-checked
# afterwards — including with this exact `>/dev/null` invocation — so the
# failure is intermittent and load-related, not a defect in the fold logic.
# Both times the run died having printed nothing but the ✗ line: stdout went
# to /dev/null and stderr was empty, so two ~20-minute runs were spent
# learning nothing. Keeping the output makes the next occurrence
# diagnosable instead of a third mystery.
"$ROOT/scripts/category-fold-selftest.sh" >"$OUT/category-fold-selftest.log" 2>&1 \
  || fail "the category fold self-test failed — see $OUT/category-fold-selftest.log (it often passes standalone: scripts/category-fold-selftest.sh)"
print -P "%F{green}✓ category fold self-test%f"

# What a chip tap is allowed to FETCH (PERF 2026-08-13). Tapping an agent chip
# used to materialise the entire store twice on the main actor — once in
# `answerDocument` before any composer ran, once in the settle path above the
# line that paints the answer — which is why opening the agent felt fast (its
# board fetch moved off the critical path in the 2026-08-11 pass) and tapping a
# chip did not. The fix scopes the first fetch per KIND, and that trade is only
# safe while the declared scope keeps matching what the composer actually
# reads. Every way it can rot is silent: a `.none` kind handed `things` reads an
# EMPTY corpus and answers "nothing" over a full room; a `moneyFlow` leg added
# without its source reaching the fetch quietly stops counting; a `showtag:`
# scope narrowed to a `#Predicate` over the transformable `tags` attribute
# compiles clean and TRAPS at runtime; and the settle bookkeeping drifting back
# above the paint restores half the latency with nothing on screen to say so.
# None of it is visible to the build, the sweep, or the nightly perf pass —
# which times launch, RSS and answer latency, all of them upstream of this work.
step "Ask-scope self-test"
"$ROOT/scripts/ask-scope-selftest.sh" >/dev/null \
  || fail "the ask-scope self-test failed — run scripts/ask-scope-selftest.sh"
print -P "%F{green}✓ ask-scope self-test%f"

# The deterministic figure above a free-text answer's prose (2026-08-15) — the
# app's own arithmetic over the rows the model is about to read. Every way it
# fails renders as a perfectly good-looking answer, and three of them render as
# a perfectly good-looking CHART: `dailyBars` floors on the count it is HANDED
# rather than what falls inside its seven-day window, so an archive retrieval
# clears the floor and draws seven columns of zero (the exact rendering
# `archiveRecap` cites as its reason to carry no bars at all); a floor that
# drifts, a ranking that always picks the emitter that declined, or an eyebrow
# that stops being passed all show up as "no figure", which is indistinguishable
# from the answer shape we had yesterday; and the splice is string surgery on
# `root = Stack([…])`, where one wrong bracket makes GenParser drop the prose and
# the grounding rows along with the chart. Plus the standing promise: the figure
# is composed BEFORE the model call, so no model output can reach the component
# grammar and no `Thing` is read across that suspension (build 250's class, in
# this very function). Unreachable by every other check here — the synthesis
# branch needs Apple Intelligence, which no simulator has.
step "Answer-figure self-test"
"$ROOT/scripts/answer-figure-selftest.sh" >/dev/null \
  || fail "the answer-figure self-test failed — run scripts/answer-figure-selftest.sh"
print -P "%F{green}✓ answer-figure self-test%f"

# Whether the All feed's source tint is READABLE (2026-08-14). A `BandRow`'s
# trailing label wears its source's own brand hue, and this is the second time
# that slot has been colored: the first ink was pulled on 2026-07-30 having
# measured ~3.4:1 at `label11`, under the 4.5:1 bar `DS.textTertiary` was raised
# to meet. Nothing caught it, because nothing here CAN — a contrast failure
# compiles, launches, screenshots and ships looking exactly like a success, and
# the type ramp's own audits check size, not legibility. So the arithmetic is
# extracted from the shipped source and held to the bar on every page the seven
# themes can produce, in both appearances. Its sharpest assertion is the one a
# surviving mutation forced: clearing the bar is necessary and NOT sufficient —
# a search that bails to the identity floor also clears it, while washing Wallet
# blue, Stripe indigo and Aerodrome blue into the same pale tint.
step "Legible-ink self-test"
"$ROOT/scripts/legible-ink-selftest.sh" >/dev/null \
  || fail "the legible-ink self-test failed — run scripts/legible-ink-selftest.sh"
print -P "%F{green}✓ legible-ink self-test%f"

# What anatomy a social thing sheet wears, and the reading under it (prd §363,
# 2026-08-12). INVISIBLE, and shipped invisible for months: the gate asked
# `SocialThread.isSocial` — three source NAMES — so an X post drew its own
# 80-character clamp in display type, an X like drew a link card over a page
# that serves no og: tags, and a new follower drew a link preview of a person.
# Every one of those renders perfectly. So do the failures this guards against
# now: a save classified as a post sets a URL as somebody's sentence, and a
# 2019 archive's counts shown with no date read as numbers just measured.
step "Social sheet self-test"
"$ROOT/scripts/social-sheet-selftest.sh" >/dev/null \
  || fail "the social sheet self-test failed — run scripts/social-sheet-selftest.sh"
print -P "%F{green}✓ social sheet self-test%f"

# An event's enrichment (`Model/EventDetails.swift`, 2026-08-14) — which link
# in an invite is the way to JOIN the call, and how a collapsed series says it
# repeats. UNTESTABLE ANY OTHER WAY: every input is a real invite, and the
# simulator's calendar cannot be seeded with one (`EKParticipant` is read-only
# and has no initializer), so no sweep and no launch-arg hook touches a line of
# it. It carries this pass's only host allowlist applied to text a STRANGER
# wrote — a join link is dug out of the invite BODY and becomes a one-tap disc
# — so a `contains` in place of a label-boundary match hands that disc to
# `zoom.us.attacker.example`. The rest are silent wrong answers that render
# perfectly: a Teams "Join" opening the settings page, a Meet link filed as a
# location running a Maps SEARCH for a URL, and "Every Tuesday" on a rule that
# means every OTHER Tuesday.
step "Calendar self-test"
"$ROOT/scripts/calendar-selftest.sh" >/dev/null \
  || fail "the calendar self-test failed — run scripts/calendar-selftest.sh"
print -P "%F{green}✓ calendar self-test%f"

# `MailMIME.attachmentNames` (2026-08-14) — the names of what somebody emailed
# you, read out of bytes THEY wrote. Every header it parses is attacker-
# controlled, and nothing else in this pass can see a filename read wrongly:
# a name drawn from `../../etc/passwd`, a `text/plain; name="body.txt"` part
# reported as a file you were sent, or the inverse — a PDF sent
# `Content-Disposition: inline`, which is extremely common — silently reporting
# nothing attached. All three render as a perfectly ordinary row.
step "MIME self-test"
"$ROOT/scripts/mailmime-selftest.sh" >/dev/null \
  || fail "the MIME self-test failed — run scripts/mailmime-selftest.sh"
print -P "%F{green}✓ MIME self-test%f"

# What a NOTE thing sheet shows (prd §366, 2026-08-12) — the category whose
# whole job is to show you words and which showed the fewest of them. Same
# class again: a word count taken over a clamped body understates a real note
# by thousands and looks exactly like a measurement; a marked passage
# classified as an entry puts our clock on somebody else's sentence; a read
# time on a twelve-word note is the app padding itself out. Nothing in a build
# or a screen sweep can see any of it. Its drift guards also hold the Kindle
# data-loss fix in place — the passage on `content`, the work where a room can
# rank it, and the heal that is the only thing able to give back the words the
# old importer threw away.
step "Note sheet self-test"
"$ROOT/scripts/note-sheet-selftest.sh" >/dev/null \
  || fail "the note sheet self-test failed — run scripts/note-sheet-selftest.sh"
print -P "%F{green}✓ note sheet self-test%f"

# What a WORK thing sheet says HAPPENED (prd §364, 2026-08-12). Same class as
# the social sheet above and the same reason: every failure renders as a
# perfectly good-looking receipt. A dispute that reads "won" when it was lost,
# a build that wears green when it broke, a row labelled "Project:" holding
# half a commit subject — `xcodebuild` is happy with all of them and the
# screen sweep passes. The sharpest one it guards is §340's: the outcome must
# come from a stable English tag or a raw state in the ref, NEVER from the
# localized title, or a device that changed language reports every past
# failure as a success.
step "Work sheet self-test"
"$ROOT/scripts/work-stage-selftest.sh" >/dev/null \
  || fail "the Work sheet self-test failed — run scripts/work-stage-selftest.sh"
print -P "%F{green}✓ Work sheet self-test%f"

# What an AGENT thing sheet shows (prd §367, 2026-08-12) — the category holding
# more text than any other and drawing the least of it. The parse is the sharp
# part: the speaker labels in a stored transcript are a WIRE FORMAT four
# importers write, in stable English, and every way of getting it wrong is
# silent. A renamed label parses nothing and falls back to the one-line
# rendering this pass exists to end; the seat name used as the speaker name
# ("Claude Code" for a transcript that says "Claude") does the same; splitting
# on every newline turns one answer's paragraphs into six messages; and a
# missing assistant label folds the agent's words into a turn attributed to
# YOU. It also holds the clamp clause honest in both directions — an 84-turn
# chat must say what it is missing, and a chat that was never clamped must not
# claim turns went missing that never existed.
step "Agent sheet self-test"
"$ROOT/scripts/agent-sheet-selftest.sh" >/dev/null \
  || fail "the agent sheet self-test failed — run scripts/agent-sheet-selftest.sh"
print -P "%F{green}✓ agent sheet self-test%f"

# What a PURCHASE sheet says (prd §368, 2026-08-12) — the shopping category's
# receipt, and the card behind a product you're only watching. Same class as
# the two above: an authorization stated as settled, a deal introduced as "a
# store you follow", a Nutri-Score beside a food this app never graded, a
# merchant that is really the first half of somebody's product name — every one
# of them renders as a perfectly good-looking card. The sharpest guard is the
# fork itself: the obvious "does it carry a price" test dresses Railgun, Peer
# and Bitcoin transfers as card purchases, so the archetype must come from a
# `sourceRef` prefix this app wrote.
step "Purchase sheet self-test"
"$ROOT/scripts/purchase-stage-selftest.sh" >/dev/null \
  || fail "the purchase sheet self-test failed — run scripts/purchase-stage-selftest.sh"
print -P "%F{green}✓ purchase sheet self-test%f"

# Pure-logic self-test for the retriever's scoring primitives (prd §318): term
# rarity, query coverage, phrase adjacency, match-centered snippets. The
# failure mode here is the one no build or sweep can see — a RANKING being
# wrong: a grounding set diluted by one-common-word matches still paints 16
# plausible rows, and the model's general prose over them reads as an answer.
step "Retriever pure-logic self-test"
"$ROOT/scripts/retriever-selftest.sh" >/dev/null \
  || fail "the retriever logic self-test failed — run scripts/retriever-selftest.sh"
print -P "%F{green}✓ retriever self-test%f"

# The vault reader (2026-08-06), plus the drift guards for the wiring it can't
# prove. Two of those guards cover SILENT TRUNCATIONS — this bridge and the
# Files bridge both capped their walk BEFORE filtering what they already held,
# so neither could ever land past its first hundred items — and nothing in a
# build, a screen sweep or a landed count can see that: the room renders
# perfectly and the sync reports success. The parsing half is the same class,
# one layer up: a note whose excerpt is its YAML frontmatter looks like a note.
# The picked-NFT shelf (prd §387). This feature's whole justification is that
# it costs LESS than the shelf it revives — §72/§124a's version was cut on
# 2026-07-19 as one of the two biggest credit sinks on the wallet path — and
# that claim rests entirely on wiring no build can check: the spam allowlist and
# the picker must stay ONE cached read with two projections, and the shelf's
# read must stay narrowed to picked contracts. Fork either and the app still
# builds, still renders, and quietly spends double. The pure half is the same
# silent class: an unsorted contract list is the shelf's own cache key, so it
# misses its cache at random and re-buys the read the window exists to avoid.
step "Wallet-NFT pure-logic self-test"
"$ROOT/scripts/wallet-nft-selftest.sh" >/dev/null \
  || fail "the wallet-NFT logic self-test failed — run scripts/wallet-nft-selftest.sh"
print -P "%F{green}✓ wallet-nft self-test%f"

step "Obsidian pure-logic self-test"
"$ROOT/scripts/obsidian-selftest.sh" >/dev/null \
  || fail "the Obsidian logic self-test failed — run scripts/obsidian-selftest.sh"
print -P "%F{green}✓ obsidian self-test%f"

# The four bridges added 2026-08-04. Three of them (Sentry, Vercel, PagerDuty)
# have never run against a live account from this host, so these harnesses are
# the only proof their shaping is right — and every failure in them is a silent
# wrong answer that renders perfectly: a failed build reading as a ship, a
# resolved incident reading as one still burning, a second regression swallowed
# by the first. Vercel's also carries a CONDUCT GUARD (its token cannot be
# scoped read-only, so the catalog's promise is kept only by that file's
# behaviour) and the package harness carries a COST guard (the obvious npm
# endpoint is 6.8 MB and is exactly what a future simplification would reach
# for).
# The foreground-sweep instrument (2026-08-06). It measures the one regression
# class this whole script is blind to — a sweep holding the main actor after
# launch — so its own correctness has no other check: `perf.sh` reports launch,
# RSS and answer latency, and a wrong number here moves none of them. Also
# carries the drift guards tying the instrument to the sweeps it names and to
# the off-main-actor hop that fixed them.
step "Sweep-clock self-test"
"$ROOT/scripts/sweep-clock-selftest.sh" >/dev/null \
  || fail "the sweep-clock self-test failed — run scripts/sweep-clock-selftest.sh"
print -P "%F{green}✓ sweep-clock self-test%f"

# The one check a live probe can never replace: no key for most of these
# bridges exists on any machine this is built on, so nothing here or on a
# device can produce the 401 the feature exists to notice. Also carries the
# drift guards tying the state machine to the transport funnel that feeds it
# and the sweep that surfaces it.
step "Bridge-health self-test"
"$ROOT/scripts/bridge-health-selftest.sh" >/dev/null \
  || fail "the bridge-health self-test failed — run scripts/bridge-health-selftest.sh"
print -P "%F{green}✓ bridge-health self-test%f"

step "Sentry pure-logic self-test"
"$ROOT/scripts/sentry-selftest.sh" >/dev/null \
  || fail "the Sentry logic self-test failed — run scripts/sentry-selftest.sh"
print -P "%F{green}✓ sentry self-test%f"

step "Vercel pure-logic self-test"
"$ROOT/scripts/vercel-selftest.sh" >/dev/null \
  || fail "the Vercel logic self-test failed — run scripts/vercel-selftest.sh"
print -P "%F{green}✓ vercel self-test%f"

step "PagerDuty pure-logic self-test"
"$ROOT/scripts/pagerduty-selftest.sh" >/dev/null \
  || fail "the PagerDuty logic self-test failed — run scripts/pagerduty-selftest.sh"
print -P "%F{green}✓ pagerduty self-test%f"

step "npm/PyPI pure-logic self-test"
"$ROOT/scripts/packages-selftest.sh" >/dev/null \
  || fail "the package-registry logic self-test failed — run scripts/packages-selftest.sh"
print -P "%F{green}✓ packages self-test%f"

# Apple Wallet / FinanceKit (prd §313). Carries more weight than the other
# room harnesses: NO SIMULATOR SHIPS FINANCEKIT DATA, so the sweep below can
# never exercise one line of this room — `isDataAvailable` is false there and
# every path takes its unavailable branch. Stripe and PostHog could at least be
# measured by anyone who mints a key; this needs a real device, a real Apple
# Card and a US account. Until then this file IS the verification. It also
# guards the entitlement's own terms (the disconnect that deletes, the
# no-server line on the setup screen, FinanceKit staying out of the Catalyst
# entitlements) — those are promises on file with Apple, not preferences.
step "Apple Wallet pure-logic self-test"
"$ROOT/scripts/applewallet-selftest.sh" >/dev/null \
  || fail "the Apple Wallet logic self-test failed — run scripts/applewallet-selftest.sh"
print -P "%F{green}✓ apple wallet self-test%f"

# Pure-logic self-test for notifications (prd §306). The ONLY automated check
# this feature can have: the simulator never runs a BGAppRefreshTask, so the
# pass that decides what fires cannot be exercised there by any means, and on a
# device the wrong answer arrives hours later on a lock screen with nobody
# watching. A 3am buzz because quiet hours failed to wrap past midnight, a
# dispute that never fires, eleven alarms where there should be one and a count.
step "Notification pure-logic self-test"
"$ROOT/scripts/notify-selftest.sh" >/dev/null \
  || fail "the notification logic self-test failed — run scripts/notify-selftest.sh"
print -P "%F{green}✓ notify self-test%f"

# Pure-logic self-test for the Stripe and PostHog room heads (prd §298). Neither
# bridge has ever run against a live account from this host, and every failure
# here is a silent wrong answer: a dispute due tomorrow placed at the far end of
# the rail, an overdue window sorted last, a metric that stopped firing ranked
# below a busy one.
step "Room-head pure-logic self-test"
"$ROOT/scripts/room-heads-selftest.sh" >/dev/null \
  || fail "the room-head logic self-test failed — run scripts/room-heads-selftest.sh"
print -P "%F{green}✓ room-head self-test%f"

# Pure-logic self-test for the three WALLET-RIDING room heads — Peer, Privacy
# Pools, Gnosis Pay (prd §349). These seats ride the watched wallets, so there
# is no key to mint and nothing on this host can make a fill settle, a screener
# rule, or a card get swiped: the harness is the only proof these numbers are
# right. Every failure is a silent wrong answer — every SALE counted as a
# purchase (`peer:sell:` also starts `peer:`), a deposit with no state tag
# claimed as "in review", EUR added to GBP, "up 400%" against a window the room
# never observed.
step "Wallet-room pure-logic self-test"
"$ROOT/scripts/wallet-rooms-selftest.sh" >/dev/null \
  || fail "the wallet-room logic self-test failed — run scripts/wallet-rooms-selftest.sh"
print -P "%F{green}✓ wallet-room self-test%f"

# Pure-logic self-test for the MONEY RECEIPT — every money thing's sheet hero
# (prd §369). This pass replaced a labelled spec table with SENTENCES, and a
# sentence is exactly what nothing else here can check: the build is happy
# either way, and a screen sweep photographs fluent prose without being able to
# tell whether it is true. Every failure is a silent wrong answer that renders
# beautifully — a receive wearing a minus, a PENDING authorization drawn with a
# torn edge (a claim of finality over an amount that can still change), "mostly
# them sending you" over a 3–2 split, a mean reported as "usually", a phishing
# domain promoted into the currency slot beside the figure.
step "Money-receipt pure-logic self-test"
"$ROOT/scripts/money-receipt-selftest.sh" >/dev/null \
  || fail "the money-receipt logic self-test failed — run scripts/money-receipt-selftest.sh"
print -P "%F{green}✓ money-receipt self-test%f"

# Pure-logic self-test for the agent's open (prd §332). This is the first screen
# a person sees every day, and every failure in it renders perfectly: a tile
# printing a tally, a tile drawn from a reading nobody took, a row filed under
# two threads, threads that reshuffle between opens over identical data. No
# crash, no empty state, no log line — a build succeeds and the room simply
# says something untrue in the largest type on it.
step "Agent-panel pure-logic self-test"
"$ROOT/scripts/agent-panel-selftest.sh" >/dev/null \
  || fail "the agent-panel logic self-test failed — run scripts/agent-panel-selftest.sh"
print -P "%F{green}✓ agent-panel self-test%f"

# Pure-logic self-test for the receipts screen's reach map (prd §300). The
# card's whole job is to be checkable, so a silent wrong answer here is worse
# than in any other visualization in the app: an undeclared host folded into
# "3 more" hides the one row the screen exists to surface, and a truncated tail
# makes a nine-service ledger look exactly like a six-service one.
step "Receipts-insight pure-logic self-test"
"$ROOT/scripts/receipts-insight-selftest.sh" >/dev/null \
  || fail "the receipts-insight logic self-test failed — run scripts/receipts-insight-selftest.sh"
print -P "%F{green}✓ receipts-insight self-test%f"

# The design system's first mechanical check (prd §299). Every other rule in
# this file is enforced by a script; the design system was enforced by memory,
# which is how fourteen data drawings shipped with no entrance and how the
# app's two most-used entrances (`SettleIn`, `RowEntrance`) ignored Reduce
# Motion from the day they shipped. Neither is visible in a build or a
# screenshot.
step "Design-motion audit"
python3 "$ROOT/scripts/design-motion-audit.py" >/dev/null \
  || fail "the design-motion audit failed — run python3 scripts/design-motion-audit.py"
print -P "%F{green}✓ design-motion audit%f"

# The design system's SECOND mechanical check, and it exists for the same
# reason the first one does: the rule lived in memory and memory lost. Face
# sizes had drifted to sixteen literals across forty-seven call sites — two
# face shelves doing the identical job disagreed, and so did two picker lists
# — because every call site spelled its own number and nothing could see the
# set. Invisible in a build and in a screenshot: any single value renders
# perfectly on its own.
step "Face-ramp audit"
python3 "$ROOT/scripts/face-ramp-audit.py" >/dev/null \
  || fail "the face-ramp audit failed — run python3 scripts/face-ramp-audit.py"
print -P "%F{green}✓ face-ramp audit%f"

# The design system's THIRD mechanical check, and the complement of the one
# above: `DS.Face` is the ramp for a ROUND identity mark, `DS.Mark` the ramp
# for a SQUARE brand mark, which that audit's own header leaves out by name.
# Same failure shape — `BridgeIcon` had drifted to fourteen literals, and two
# were real defects: a token row's leading square CHANGED SIZE depending on
# whether its art had loaded (thumbnail 36, fallback mark 38, same HStack), and
# a bridge's setup header drew at 60 while its connected header drew at 54.
# It also carries the glyph half: an SF Symbol sized with a frozen
# `.font(.system(size:))` does not grow with the label beside it, so at an
# accessibility size the words grow and the icons don't. All of it renders
# perfectly in a build and in a default-size screenshot.
step "Design-ramp audit"
python3 "$ROOT/scripts/design-ramp-audit.py" --self-test >/dev/null \
  || fail "the design-ramp audit's own self-test failed — the check is broken, not the code"
python3 "$ROOT/scripts/design-ramp-audit.py" >/dev/null \
  || fail "a glyph is frozen or a brand mark is off the DS.Mark ramp — run python3 scripts/design-ramp-audit.py"
print -P "%F{green}✓ design-ramp audit%f"

# The VoiceOver and touch-target half of the same system (2026-08-13). The
# design-ramp and design-motion audits already cover Dynamic Type and Reduce
# Motion, and `ContrastStore` covers Increase Contrast — what nothing covered
# was whether a control ANNOUNCES itself and whether it can be HIT. The sweep
# that produced this found seven room heads whose whole face was
# `contentShape` + `onTapGesture` (a pair that carries no trait and no action,
# so VoiceOver never offered them at all — and on four of them the card's lead
# has no row of its own, so that was the only route to it), ten icon buttons
# under the 44pt floor in a repo that had already written that rule down three
# times, and two icon-only buttons with no label. Every one of them renders
# perfectly, builds clean, and works for whoever is testing it.
step "Accessibility audit"
python3 "$ROOT/scripts/accessibility-audit.py" --self-test >/dev/null \
  || fail "the accessibility audit's own self-test failed — the check is broken, not the code"
python3 "$ROOT/scripts/accessibility-audit.py" >/dev/null \
  || fail "a control is unlabelled, untraited or under the 44pt floor — run python3 scripts/accessibility-audit.py"
print -P "%F{green}✓ accessibility audit%f"

# A localization sweep (2026-08-04) found 194 previously-translated strings
# had regressed into bare Swift literals — unreachable, rendering English in
# every language — plus missing InfoPlist/AppShortcuts catalogs and 44
# hand-composed English-only plurals. All three render perfectly in a build
# or a screen sweep. See scripts/localization-audit.py.
step "Localization audit"
python3 "$ROOT/scripts/localization-audit.py" --self-test >/dev/null \
  || fail "the localization audit's own self-test failed — the check is broken, not the code"
python3 "$ROOT/scripts/localization-audit.py" >/dev/null \
  || fail "a translation is unreachable, a catalog is missing, or a plural is hand-composed — see the output above"
print -P "%F{green}✓ localization audit%f"

# Pure-logic self-test for the on-device-intelligence pass (prd §282). Static,
# no build, no network — and the ONLY automated check that pass can have: the
# simulator ships no on-device language model, so every model path there runs
# its unavailable branch and a sim sweep exercises none of them. What it covers
# is the deterministic logic around the model, where every failure is a silent
# wrong answer: a vector header off by a byte makes every cosine 0 (which reads
# as "no related things" forever), an accepted status-bar clock puts "9:41
# today" on nearly every screenshot's calendar hand-off, and a permissive
# grounding check turns §218's honesty rail off while still logging that it ran.
# The main-thread profiler's PARSER, not the profiler (which needs a Mac app
# and a GUI, so it reports rather than gates — `perf.sh`'s contract). What is
# guarded here is the one part that can rot silently: a summariser whose regex
# stops matching prints "no hot spots" and reads as a healthy app. That is
# §257's lesson exactly — perf.sh spent three weeks recording a launch climbing
# 293→763ms while its own log predicate dropped the markers the app was
# emitting. Static, pure, sub-second.
step "Main-thread profiler self-test"
"$ROOT/scripts/main-thread-profile.sh" --self-test >/dev/null \
  || fail "the main-thread profiler's summariser failed — run scripts/main-thread-profile.sh --self-test"
print -P "%F{green}✓ main-thread profiler self-test%f"

step "On-device pure-logic self-test"
"$ROOT/scripts/ondevice-selftest.sh" >/dev/null \
  || fail "the on-device logic self-test failed — run scripts/ondevice-selftest.sh"
print -P "%F{green}✓ on-device self-test%f"

# The demo mode's guard rails (prd §217 amendment, 2026-08-07) — every check
# re-catches a bug that already shipped once during this feature's own
# development: `ChipMemory.seedDemo` inside `#if DEBUG` broke the Release
# build outright, invisible to every other check here (they all compile
# DEBUG); and two sessions independently re-fixed the same "eight seats
# furnish nothing" bug, which without `Thing.sourceRef`'s missing unique
# constraint would have silently landed duplicate rows. `--self-test` first,
# same reason as every sibling: a check that can't fail proves nothing.
step "Demo mode guard rails"
python3 "$ROOT/scripts/demo-selftest.py" --self-test >/dev/null \
  || fail "the demo guard's own self-test failed — run scripts/demo-selftest.py --self-test --verbose"
python3 "$ROOT/scripts/demo-selftest.py" >/dev/null \
  || fail "the demo guard found a real violation — run scripts/demo-selftest.py --verbose"
print -P "%F{green}✓ demo guard rails%f"

# ── 1. Build ────────────────────────────────────────────────────────
step "Building Casberi (derivedData: $DD)"
xcodebuild -project "$ROOT/Casberi/Casberi.xcodeproj" -scheme Casberi \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath "$DD" build -quiet || fail "build failed"
print -P "%F{green}✓ build%f"

# ── 1b. Mac parity (Catalyst COMPILE only) ──────────────────────────
# The one platform gap this pass had: everything above builds and runs for
# iOS alone, so a mobile change that breaks Mac Catalyst sailed through green
# and was caught only by `verify-mac.sh` — a nightly LaunchAgent that drives a
# real GUI app, so a closed lid means the night is SKIPPED, not queued — or by
# a failing archive at ship time. Twenty-two files carry a
# `#if targetEnvironment(macCatalyst)` branch that no iOS build ever compiles,
# and the ReownAppKit `platformFilter = ios` in the pbxproj (measured
# 2026-08-01: without it Catalyst fails on `'NSColor' is not a member type of
# class 'ReownAppKit.AppKit'`) is one careless project edit from gone, with
# nothing else asserting it.
#
# COMPILE ONLY, and that ceiling is the point — this proves the Mac still
# BUILDS, never that it still WORKS. Running it is `verify-mac.sh`'s job and
# none of its plumbing transfers (see its header: `open -n` not `simctl`,
# `open --stderr` not `log stream`, the app screenshotting itself). This is the
# cheap half that belongs on every pass; that is the expensive half that
# belongs on a nightly.
#
# Its OWN derivedData, never `$DD`: a shared dir would make the iOS build and
# this one evict each other's module cache, so each pass would pay a cold
# build. Warm and separate, this is incremental (measured 2026-08-12: 101s
# from an EMPTY dir, all SPM dependencies included — that is the worst case,
# not the per-run cost). `SKIP_CATALYST=1` skips it, the LAUNCH_CYCLES=0
# escape hatch for a run that is only chasing an iOS-side answer.
if [[ -z "${SKIP_CATALYST:-}" ]]; then
  CATDD="$HOME/Library/Developer/CasberiCatalystDD"
  step "Mac parity (Catalyst compile, derivedData: $CATDD)"
  CATLOG="$(mktemp -t casberi-catalyst)"
  # NOT `xcodebuild … | grep error:` the way verify-mac.sh spells it. That
  # script runs under `set -uo pipefail` and this one under `set -euo
  # pipefail`, so here a SUCCESSFUL build is what kills the run: grep finds no
  # `error:`, exits 1, and pipefail hands that to `set -e`. Gate on
  # xcodebuild's own exit, then print the errors out of the log — which also
  # keeps the verify-mac.sh 2026-08-01 lesson (an incremental dir keeps
  # yesterday's bundle, so an exit code is the only honest gate; a bundle
  # existing proves nothing).
  if ! xcodebuild -project "$ROOT/Casberi/Casberi.xcodeproj" -scheme Casberi \
       -destination 'platform=macOS,variant=Mac Catalyst' \
       -derivedDataPath "$CATDD" build -quiet >"$CATLOG" 2>&1; then
    grep -E "error:" "$CATLOG" | head -20 || true
    fail "Mac Catalyst build failed (errors above, full log: $CATLOG) — the Mac has drifted; iOS is green"
  fi
  rm -f "$CATLOG"
  print -P "%F{green}✓ mac parity (catalyst compiles)%f"
fi

# Localization COVERAGE (2026-08-13). Distinct from the "Localization audit"
# above, which catches a translation that EXISTS and became UNREACHABLE. This
# one catches the opposite and, until it existed, invisible case: a string that
# never reached the catalog at all, and so ships English in every language.
#
# It is here rather than in the static head because it reads the `.stringsdata`
# the compiler just emitted — the only honest input. A regex over Swift source
# was tried and reported 57 false positives on a clean tree (a literal `%` is
# `%%` in the catalog key, a nested string literal ends the match early,
# `\u{201c}` is not decoded), and a lint that cries wolf gets turned off within
# a week. Sitting BEFORE the `--build-only` exit means that flag still gets it.
#
# BOTH platforms' dirs are passed on purpose: 22 files carry a
# `#if targetEnvironment(macCatalyst)` branch no iOS build ever compiles, so an
# iOS-only run cannot see the Mac-only strings — that is exactly how five MCP
# settings strings stayed untranslated through the 2026-08-13 sweep until a
# Catalyst pass was added. Under `SKIP_CATALYST=1` the Catalyst dir simply
# isn't there; the audit skips missing dirs and NAMES what it checked, so a
# narrower run can never read as a complete one.
#
# Why it caught nothing for nine days before it existed: Xcode's IDE syncs a
# String Catalog on build, `xcodebuild` from the CLI does NOT. Every session
# here builds from the CLI, so the catalog only advanced when somebody ran
# `xcstringstool sync` by hand — and on 2026-08-13 it was 767 keys and 248
# commits behind, with every string of nine days' features English-only.
step "Localization coverage"
python3 "$ROOT/scripts/localization-coverage-audit.py" --self-test >/dev/null \
  || fail "the localization coverage audit's own self-test failed — the check is broken, not the code"
# The paths are ONE CONFIGURATION'S dir each, never the `Intermediates.noindex`
# root, and that is a measured fix rather than tidiness: a long-lived
# derivedData accumulates stringsdata from every configuration ever built into
# it, and those are never recompiled again. Pointing this at the root of a real
# `CasberiDD` reported 102 false findings — it held a months-old
# `Release-iphonesimulator` (157 files) and a stray `Debug-maccatalyst` (477)
# beside the fresh `Debug-iphonesimulator`, so strings deleted long ago (e.g.
# `ADD A FEED`, which the design system banned in July 2026) still had live
# stringsdata. Filtering on "the source file still exists" does NOT fix it: 86
# of the 102 came from files that are still in the tree and had simply been
# edited since that configuration was last built. Within a single config dir
# the data is exact, because an incremental build rewrites the stringsdata of
# every file it recompiles.
python3 "$ROOT/scripts/localization-coverage-audit.py" --stringsdata \
    "$DD/Build/Intermediates.noindex/Casberi.build/Debug-iphonesimulator" \
    "${CATDD:-$HOME/Library/Developer/CasberiCatalystDD}/Build/Intermediates.noindex/Casberi.build/Debug-maccatalyst" \
  || fail "a string never reached the catalog, or is missing a shipped translation — see the output above"
print -P "%F{green}✓ localization coverage%f"

[[ "${1:-}" == "--build-only" ]] && exit 0

# ── 2. Boot sim + install ──────────────────────────────────────────
step "Booting $DEVICE"
xcrun simctl bootstatus "$DEVICE" -b >/dev/null 2>&1 || xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null

APP="$DD/Build/Products/Debug-iphonesimulator/Casberi.app"
[[ -d "$APP" ]] || fail "app bundle not found at $APP"
xcrun simctl install "$DEVICE" "$APP" || fail "install failed"
print -P "%F{green}✓ installed%f"

mkdir -p "$OUT"

# ── 2.5 Cold-launch survival loop ───────────────────────────────────
# The first-frame stack-overflow class (CLAUDE.md: recurred 2026-07-10 /
# 07-13 / 07-15) is INTERMITTENT and worst on the first launch after
# `simctl install` — one green launch proves nothing. Reinstall + cold
# launch LAUNCH_CYCLES times (default 10, the confidence bar from the
# 07-10 fix) and require the first-frame marker (launchTimer, the same
# line perf.sh times) on every cycle. A cycle with no marker fails the
# run: pid dead = the crash class; pid alive = frozen before first frame
# (the 07-15 symptom). LAUNCH_CYCLES=0 skips (e.g. quick doc-only runs).
CYCLES=${LAUNCH_CYCLES:-10}
if (( CYCLES > 0 )); then
  step "Cold-launch survival ($CYCLES cycles)"
  SURV="$OUT/launch-survival.log"
  CRASHDIR="$HOME/Library/Logs/DiagnosticReports"
  IPS_BEFORE=$(find "$CRASHDIR" -maxdepth 1 -name 'Casberi-*.ips' 2>/dev/null | wc -l | tr -d ' ')
  # One stream for the whole loop; cycle i waits for the i-th marker line.
  xcrun simctl spawn "$DEVICE" log stream \
    --predicate 'process == "Casberi" AND eventMessage CONTAINS "launchTimer"' \
    --style compact > "$SURV" 2>/dev/null &
  SURVPID=$!
  sleep 1
  for (( i=1; i<=CYCLES; i++ )); do
    xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
    xcrun simctl install "$DEVICE" "$APP" || { kill $SURVPID 2>/dev/null; fail "reinstall failed (cycle $i)"; }
    PID=$(xcrun simctl launch "$DEVICE" "$BUNDLE" -onboarded YES 2>/dev/null | awk -F': ' '{print $NF}')
    READY=""
    for (( t=0; t<15; t++ )); do
      sleep 1
      # Match the timing line, not log stream's predicate-echo header.
      (( $(grep -Ec 'launchTimer.*[0-9]+ms' "$SURV" 2>/dev/null || true) >= i )) && { READY=1; break; }
    done
    if [[ -z "$READY" ]]; then
      kill $SURVPID 2>/dev/null || true
      if [[ -n "${PID:-}" ]] && kill -0 "$PID" 2>/dev/null; then
        fail "cold-launch cycle $i: no first frame in 15s, pid $PID still alive — frozen at launch"
      else
        fail "cold-launch cycle $i: process died before first frame — the launch-crash class (check $CRASHDIR)"
      fi
    fi
  done
  kill $SURVPID 2>/dev/null || true
  IPS_AFTER=$(find "$CRASHDIR" -maxdepth 1 -name 'Casberi-*.ips' 2>/dev/null | wc -l | tr -d ' ')
  if (( IPS_AFTER > IPS_BEFORE )); then
    fail "cold-launch loop passed but $((IPS_AFTER - IPS_BEFORE)) new Casberi crash report(s) in $CRASHDIR"
  fi
  print -P "%F{green}✓ cold-launch survival ($CYCLES/$CYCLES)%f"
fi

# ── 3. Screen sweep via deeplink hook ───────────────────────────────
sweep() {  # sweep <name> <casberi-url>
  xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
  # -onboarded YES skips first-launch onboarding so the sweep sees the real screens
  xcrun simctl launch "$DEVICE" "$BUNDLE" -onboarded YES -deeplink "$2" >/dev/null || fail "launch failed ($1)"
  sleep 4
  xcrun simctl io "$DEVICE" screenshot "$OUT/$1.png" >/dev/null || fail "screenshot failed ($1)"
  print -P "%F{green}✓ $1%f"
}
step "Screen sweep"
sweep home    "casberi://home"
sweep feed    "casberi://feed"
sweep apps    "casberi://account"
# Settings was swept on the MAC and never here (found by mac-parity-audit.py,
# 2026-08-12) — the screen carrying the privacy copy, the sync toggle and both
# delete verbs had no iOS screenshot in any automated pass.
sweep settings "casberi://settings"

# ── 4. Answer-path probe (headless, logs to console) ────────────────
step "Answer probe"
xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
# Stream the app's log DURING the probe (log show --last is unreliable for
# fresh lines); on-device inference can take ~15s cold, so give it 25.
xcrun simctl spawn "$DEVICE" log stream --predicate 'process == "Casberi" AND eventMessage CONTAINS "answerProbe"' \
  --style compact > "$OUT/answer-probe.log" 2>/dev/null &
LOGPID=$!
xcrun simctl launch "$DEVICE" "$BUNDLE" -onboarded YES -answerProbe "what did I save about work" -probeDelay 2 >/dev/null
for i in {1..25}; do
  sleep 1
  grep -q "answerProbe(" "$OUT/answer-probe.log" 2>/dev/null && break
done
xcrun simctl io "$DEVICE" screenshot "$OUT/answer-probe.png" >/dev/null
kill $LOGPID 2>/dev/null || true
if [[ -s "$OUT/answer-probe.log" ]]; then
  print -P "%F{green}✓ answer probe logged%f"
else
  print -P "%F{yellow}⚠ no probe log lines captured (model may be unavailable on this host) — check $OUT/answer-probe.png%f"
fi

xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true

# ── 6. Demo room-head coverage (headless, HARD FAIL) ─────────────────
# Extends the same "does the demo have parity" question (2026-08-08 ruling)
# to a second surface: `FeedScreen.SourceHead` (prd §349's runway/stripeHead/
# posthogHead/appleWallet/x402/appStoreConnect/cursorHead/peerHead/
# privacyPoolsHead/gnosisPayHead) — the per-source hero card a room draws
# when you open it directly, read via `-roomInsightProbe <Source>` the same
# way the panel check above reads `-agentOpenProbe`.
#
# UNLIKE the panel check, this is a HARD FAIL, not a warning — and that's a
# considered difference, not an oversight. The agent panel caps at 20 cards
# ranked by affinity, so a kind that CAN compose can still lose one run's
# ranking race; a room head has no such competition; `sourceHead(_:)` is
# gated one-source-at-a-time (`case "Cloudflare": …`, `case "Stripe": …`),
# so exactly one candidate is ever even asked, and a demo corpus that can
# make it compose makes it compose every time. There's no ranking noise
# here to protect against — an absence is a real gap, full stop.
#
# It found SIX real gaps on its first real run (2026-08-10), not a
# hypothetical, and each was a distinct failure shape worth remembering:
#   • Peer/Privacy Pools rows carried "demo:"-prefixed refs, but their room
#     heads match on the REAL bridges' own ref shapes (`peer:…`,
#     `privacypools:dep:…`) — every seeded fill/deposit was silently
#     dropped before it was even counted.
#   • PostHog's demo seeded READINGS (`PostHogState.Metric`) but never a
#     WATCH row (`sourceRef: "posthog:metric:<event>"`) — the head has
#     nothing to iterate without one, and even with one the seeded readings
#     never stamped `fetchedAt`, so they read as permanently "unread".
#   • Apple Wallet's head gates on its own bespoke `connected` UserDefaults
#     flag, distinct from the generic catalog "connected" status every
#     other seat gets — nothing was setting it.
#   • App Store Connect's head gates on a REAL Keychain credential
#     (`ASCAuth.configured`), which a demo must never fake — so the gate
#     widens for `DemoMode.isActive` instead, and `ASCState` is seeded
#     directly.
#   • This probe's OWN card list (`ProbeHooks.swift`) had gone stale —
#     `appleWallet`/`x402`/`appStoreConnect` shipped without a line here,
#     which is the exact registry-drift class this probe's own header
#     warns about and would have reported three false "gaps" forever.
#
# `railgunHead` (2026-08-11) is the ELEVENTH source head, added by a
# concurrent session mid-way through this list's own life — added here the
# same day, the exact discipline the registry-drift finding above argues
# for: a new `SourceHead` case is a new line here in the SAME commit, not a
# later "oh, we forgot one." `safeHead`, the TWELFTH, landed the same day for
# the identical reason — Safe earning its own source in the same pass that
# gave it a room head.
#
# `xHead` (2026-08-13, prd §375) is the THIRTEENTH and the first over an
# IMPORT rather than a live bridge, which changes what this check is worth
# for it: every head above composes from bridge state or from rows a sync
# lands, while this one composes from an archive's own SPAN — so it is also
# the first whose demo coverage depends on the demo corpus having years in
# it. `DemoSeedAll.xArchive` was seven posts inside one season until the same
# commit; the card would have declined correctly and this check would have
# read that as a gap, which is exactly the conversation worth having in the
# commit that adds it rather than in a nightly three weeks later.
#
# The (name, source) pairs mirror `ProbeHooks.swift`'s `roomInsightProbe`
# hook and `FeedScreen.sourceHead(_:)`'s switch — change one, change all
# three (the same acknowledged fragility that hook's own header already
# carries; there is no clean way to derive a Swift `case` → source-string
# mapping from a shell script without hand-parsing the same switch this
# hook already mirrors by hand).
# FURNISH THE DEMO — its own step since 2026-08-15, and it has to be.
#
# This block used to live inside "Demo panel figure-kind coverage", which was
# RETIRED with the agent panel the same morning (prd §386p). That step owned the
# demo entry, the pour wait AND the `POURED` flag — and FIVE later steps read
# that flag. Deleting it left every one of them dereferencing an unset variable
# under `set -euo pipefail`, so `verify.sh` aborted at the first of them with
# `POURED: parameter not set` and could not complete AT ALL. The ship gate was
# down from that commit until this one, which is the worst possible thing for a
# gate to be, because a pass that cannot finish looks from outside exactly like
# a pass nobody has run.
#
# The lesson is the one §386p's own entry already states about guards moving
# files, one level up: **when a step is deleted, whatever LATER steps take from
# it moves too.** A retired check that was the only producer of shared state is
# not a subtraction of one step, it is a subtraction of every step downstream.
#
# Kept deliberately generic — it furnishes the demo and says whether the pour
# finished, and nothing about any one surface — so the next coverage check to be
# retired takes only itself.
step "Demo pour"
POUR_LOG="$OUT/demo-pour.log"
xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
xcrun simctl spawn "$DEVICE" log stream \
  --predicate 'process == "Casberi" AND eventMessage CONTAINS "demoMode:"' \
  --style compact > "$POUR_LOG" 2>/dev/null &
POURPID=$!
sleep 1
xcrun simctl launch "$DEVICE" "$BUNDLE" -fresh YES -onboarded YES -demoEnter YES >/dev/null 2>&1 || true
POURED=""
for i in {1..25}; do
  sleep 1
  grep -q "demoMode: poured" "$POUR_LOG" 2>/dev/null && { POURED=1; break; }
done
kill $POURPID 2>/dev/null || true
if [[ -z "$POURED" ]]; then
  print -P "%F{yellow}⚠ demo never finished pouring (see $POUR_LOG) — the demo coverage checks below will skip%f"
else
  sleep 2
  print -P "%F{green}✓ demo poured%f"
fi

step "Demo room-head coverage"
ROOMHEAD_LOG="$OUT/demo-roomhead-coverage.log"
if [[ -z "$POURED" ]]; then
  print -P "%F{yellow}⚠ demo never finished pouring (see the Demo pour step above) — skipping room-head coverage%f"
else
  xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
  typeset -A ROOM_HEADS=(
    runway            "Cloudflare"
    stripeHead        "Stripe"
    posthogHead       "PostHog"
    appleWallet       "Apple Wallet"
    x402              "Circle x402"
    appStoreConnect   "App Store Connect"
    cursorHead        "Cursor"
    peerHead          "Peer"
    privacyPoolsHead  "Privacy Pools"
    gnosisPayHead     "Gnosis Pay"
    railgunHead       "Railgun"
    safeHead          "Safe"
    xHead             "X"
  )
  MISSING_HEADS=()
  for name in "${(k)ROOM_HEADS[@]}"; do
    src="${ROOM_HEADS[$name]}"
    xcrun simctl spawn "$DEVICE" log stream --predicate 'process == "Casberi" AND eventMessage CONTAINS "roomInsight"' \
      --style compact > "$ROOMHEAD_LOG.$name" 2>/dev/null &
    RHPID=$!
    sleep 1
    xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
    xcrun simctl launch "$DEVICE" "$BUNDLE" -onboarded YES -roomInsightProbe "$src" >/dev/null 2>&1 || true
    for i in {1..10}; do
      sleep 1
      grep -q "roomInsight: leads with" "$ROOMHEAD_LOG.$name" 2>/dev/null && break
    done
    kill $RHPID 2>/dev/null || true
    grep -q "roomInsight: leads with $name\$" "$ROOMHEAD_LOG.$name" 2>/dev/null || MISSING_HEADS+=("$name ($src)")
  done
  xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
  if (( ${#MISSING_HEADS[@]} == 0 )); then
    print -P "%F{green}✓ demo room-head coverage (${#ROOM_HEADS[@]}/${#ROOM_HEADS[@]})%f"
  else
    fail "demo room head(s) never compose: ${MISSING_HEADS[*]} — see $ROOMHEAD_LOG.<name>"
  fi
fi

# ── 6b. THE DEMO REACHES NOTHING, measured (headless, HARD FAIL) ─────
# The empirical half of `demo-selftest.py`'s check J, and the reason it exists
# is that J is a HAND LIST. J names five per-view reads somebody thought to
# look for; this walks the demo and asks the app what it actually reached.
#
# Both reaches found on 2026-08-12 were found by READING, not by any check —
# `PredictionBrowseSection` fetching both exchanges' order books on a
# `.task(id:)`, and `LinkPreviewCard` scraping a linked page through
# `LPMetadataProvider`. Neither is in any foreground sweep, so `DemoMode`'s
# gate could not see them and no static check knew to look. `NetworkLedger`
# already records every request `IngestSupport`, `AgentAnswer` and `LinkTitle`
# make, and `-receiptsProbe` prints one `receipt|` line per host — so the
# question "did the demo reach anything?" has an answer the app can give
# directly, over whatever the rooms actually do rather than whatever we
# remembered to grep for.
#
# The ledger's own ceiling is stated on its screen and applies here: it does
# not see images loaded into rows, the two WebSocket paths, or the
# WalletConnect SDK's own hosts. So a clean run means "nothing the ledger can
# see", not "nothing at all" — which is still strictly more than a hand list
# of five entry points can promise.
step "Demo reaches nothing"
REACH_LOG="$OUT/demo-reaches-nothing.log"
if [[ -z "$POURED" ]]; then
  print -P "%F{yellow}⚠ demo never finished pouring (see the panel-coverage step above) — skipping the reach check%f"
else
  xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
  # CLEAR THE LEDGER FIRST (2026-08-15). `NetworkLedger` is cumulative and
  # persisted — correct for the screen it serves, fatal for a check that asks
  # "did the demo reach anything?", because without a baseline the answer covers
  # the whole life of the install. On a clean CI container that difference never
  # showed; on a dev machine that had spent an afternoon syncing a real wallet
  # this step failed naming 29 hosts, not one of them touched by the demo.
  # Measured immediately after, on a wiped container: the demo reaches ZERO.
  # A check that reports someone else's traffic as the demo's is worse than no
  # check, so the baseline is now established rather than assumed.
  xcrun simctl launch "$DEVICE" "$BUNDLE" -onboarded YES -receiptsForget YES >/dev/null 2>&1 || true
  sleep 2
  xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
  # Walk the rooms most likely to reach: both prediction books (the per-view
  # fetch that started this), the token room, and a thing sheet (the page
  # scrape). Each is a separate launch, because the reach we are hunting is
  # one a ROOM makes when it opens.
  for room in Kalshi Polymarket Tokens GeckoTerminal; do
    xcrun simctl launch "$DEVICE" "$BUNDLE" -onboarded YES \
      -deeplink "casberi://feed/source/$room" >/dev/null 2>&1 || true
    sleep 4
    xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
  done
  xcrun simctl spawn "$DEVICE" log stream --predicate 'process == "Casberi" AND eventMessage CONTAINS "receipt|"' \
    --style compact > "$REACH_LOG" 2>/dev/null &
  RPID=$!
  sleep 1
  xcrun simctl launch "$DEVICE" "$BUNDLE" -onboarded YES -receiptsProbe YES >/dev/null 2>&1 || true
  sleep 6
  # A plain `kill` (SIGTERM) only SIGNALS the background `log stream` — it
  # does not wait for it to die, and a killed process's buffered writes are
  # not guaranteed to be flushed to $REACH_LOG yet. Reading the file
  # immediately after raced that flush: two consecutive runs counted a real
  # match (REACHED != 0) that had vanished by the time the file was read
  # back a moment later by hand, and — under this script's own
  # set -e -o pipefail — the second grep (`-o`) finding nothing on the
  # now-drained file exits 1, which kills the WHOLE script right there,
  # before `fail` ever runs. A pure timing artifact looked like a silent
  # crash with no error message.
  #
  # The fix is NOT `wait $RPID` — tried first, and it hung the entire run
  # (measured: killed by the harness's own timeout, exit 143). `simctl spawn
  # … log stream`'s local process apparently does not exit on SIGTERM alone,
  # so an unbounded wait for it never returns. `kill -9` is unblockable and
  # a bounded sleep afterward is enough for the OS to deliver whatever was
  # already buffered — bounded beats correct-but-hangs here.
  kill -9 $RPID 2>/dev/null || true
  sleep 1
  xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
  # This capture has now produced FOUR different malformed shapes across
  # four separate runs, and every single one was this SCRIPT dying, never a
  # real reach: an empty extraction (pipefail killing the script before
  # `fail` ever ran), a literal two-line "0\n0" (failed the exact
  # string-equality test), an empty string ($REACH_LOG apparently never got
  # created/written that run, so grep found no file and `| head -1`'s own
  # success swallowed the `|| echo 0` fallback), and — the one that finally
  # explains all of it — this exact rewrite's own `REACHED=$(grep -c … )`
  # with NO fallback at all: `grep -c` matching zero times exits 1 like any
  # other grep, and under this script's own `set -e`, a bare command
  # substitution assignment inheriting a non-zero exit status kills the
  # WHOLE SCRIPT right there — before the validation regex below ever runs.
  # The common case (no reach at all) is the one that was crashing every
  # time. `|| echo 0` on the substitution itself is not optional here.
  REACHED=$(grep -c "receipt| " "$REACH_LOG" 2>/dev/null | head -1 || true)
  [[ "$REACHED" =~ ^[0-9]+$ ]] || REACHED=0
  if [[ "$REACHED" == "0" ]]; then
    print -P "%F{green}✓ demo reaches nothing (4 rooms walked, ledger empty)%f"
  else
    print -P "%F{red}hosts the demo reached:%f"
    # `|| true`: never let this listing itself be the reason `fail` below is
    # skipped — the exact failure mode this comment's incident describes.
    grep -o "receipt| .*" "$REACH_LOG" | sort -u | head -10 || true
    fail "the demo reached $REACHED host(s) — see $REACH_LOG"
  fi
fi

# ── 6c. Demo floor coverage (headless, WARN — see the note) ──────────
# The quietest demo failure: state that sits UNDER a control's minimum. A
# control gated on a count does not fail when the demo is short — it simply
# does not draw, and every other check passes. Four were found by eye this
# week, each needing a screenshot to notice.
#
# CURATED, not all 82 `.count >= N` gates in the tree — most are formatting
# (`parts.count > 1` choosing a separator) where being under is correct. The
# registry lives in `-floorProbe` and marks each entry required or optional,
# so "the demo need not satisfy this one" is written down rather than implied.
#
# WARN, NOT FAIL, AND ONLY FOR NOW: `wallet.addresses` is genuinely under its
# floor on the shipped demo (1 watched, 3 seeded — the face rail cannot draw),
# and that is an open bug, not a tuning problem. Flipping this to a hard fail
# is the right end state and should happen in the same change that fixes it;
# making main red first would only block whoever is mid-edit.
step "Demo floor coverage"
FLOOR_LOG="$OUT/demo-floor-coverage.log"
if [[ -z "$POURED" ]]; then
  print -P "%F{yellow}⚠ demo never finished pouring — skipping floor coverage%f"
else
  xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
  xcrun simctl spawn "$DEVICE" log stream --predicate 'process == "Casberi" AND eventMessage CONTAINS "floor|"' \
    --style compact > "$FLOOR_LOG" 2>/dev/null &
  FPID=$!
  sleep 1
  xcrun simctl launch "$DEVICE" "$BUNDLE" -onboarded YES -floorProbe YES >/dev/null 2>&1 || true
  for i in {1..12}; do
    sleep 1
    grep -q "controls checked" "$FLOOR_LOG" 2>/dev/null && break
  done
  sleep 2
  kill $FPID 2>/dev/null || true
  xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
  # See the reach check above for the full story: `grep -c` PRINTS "0" and
  # EXITS 1 on zero matches, so `|| echo 0` appends a SECOND "0" and the
  # value becomes the literal two-line "0\n0" — which fails the `== "0"`
  # test below and sends a perfectly healthy run into the warn branch, where
  # the follow-up `grep -o` finds nothing, exits 1, and kills the whole
  # script under `set -e`. `head -1` drops the duplicate, and the regex
  # normalises anything else (empty, missing file) to a real 0.
  UNDER=$(grep -c ") UNDER " "$FLOOR_LOG" 2>/dev/null | head -1 || true)
  [[ "$UNDER" =~ ^[0-9]+$ ]] || UNDER=0
  if [[ "$UNDER" == "0" ]]; then
    print -P "%F{green}✓ demo floor coverage (every required control clears its floor)%f"
  else
    print -P "%F{yellow}⚠ $UNDER required control(s) under their floor:%f"
    # `|| true`: this is a WARN-only step, so the listing must never be the
    # thing that fails the run.
    grep -o "floor| .*UNDER.*" "$FLOOR_LOG" | sort -u || true
  fi
fi

# ── 7. Demo sheet-anatomy coverage (headless, HARD FAIL) ─────────────
# The THIRD surface of the same 2026-08-08 parity ruling, and the one that
# covers the sheets rather than the rooms.
#
# Seven anatomies decide what a thing sheet IS, each by a DATA test over the
# record: `SocialSheet` (post/person/save/transcript), `NoteSheet`
# (entry/note/passage), `AgentSheet` (conversation/grant), `PurchaseStage`
# (receipt/watch), `WorkStage` (by FACE — words/code/money/stars),
# `MoneyReceipt`, and §365's structured `facts` behind the Life sheets. A
# shape no demo row can reach is a feature a first-time opener cannot see,
# and NOTHING else in the tree notices: the rows are all present, every
# static check passes, the room renders — the sheet just quietly takes a
# weaker branch.
#
# HARD FAIL for the room-head step's reason: a sheet's anatomy is a pure
# function of one record, decided the moment it opens. No ranking, no
# competition, no noise to protect against — an absence is a real gap.
#
# It found FIVE on its first real run (2026-08-12), each a different cause:
#   • `social.person` was 0 — the anatomy built to say a follower is a PERSON
#     and not a link to one needs `socialContext == "follow"`, and no demo
#     row set it.
#   • `note.note` was 0 — the vault's rows wore `demo:obsidian:N` refs while
#     `NoteSheetSource.isNamed` asks `ObsidianLink.relativePath` for an
#     `obsidian:` one, so every vault note degraded to `.entry`.
#   • `work.code`/`work.stars` were 0 — Sentry's rows carried no tag and
#     `WorkStage.outcome` is keyed on (source, TAG), while App Store
#     Connect's `demo:asc:N` refs could not satisfy `ascOutcome`, which
#     parses the outcome out of the ref itself.
#   • `work.money` was 0 in the WORST way: the demo landed Stripe as
#     `.transaction` where the bridge lands `.link`, so every row drew a
#     MONEY RECEIPT (an anatomy §369 built for the nine wallet sources, never
#     for Stripe) and `workReading` stood down because a receipt existed.
#     The demo showed the wrong anatomy and suppressed the right one, both
#     rendering perfectly. Parity runs in BOTH directions.
#
# Three of those five are the same underlying class — a gate that keys on a
# REF SHAPE cannot be satisfied by a row that merely looks right — which is
# the fourth, fifth and sixth time it has bitten (Peer, Privacy Pools and the
# Obsidian vault were the others).
step "Demo sheet-anatomy coverage"
SHEET_LOG="$OUT/demo-sheet-coverage.log"
if [[ -z "$POURED" ]]; then
  print -P "%F{yellow}⚠ demo never finished pouring (see the panel-coverage step above) — skipping sheet-anatomy coverage%f"
else
  # Every shape the app can draw. Hand-maintained against the five `Shape`
  # enums, `WorkStage.Face` and `MoneyReceipt` — the same contract the
  # room-head map above keeps, and the same rule: add a shape, add a row.
  EXPECTED_SHAPES=(
    social.post social.person social.save social.transcript
    note.entry note.note note.passage
    agent.conversation agent.grant
    purchase.receipt purchase.watch
    work.words work.code work.money work.stars
    money.receipt life.facts
  )
  xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
  xcrun simctl spawn "$DEVICE" log stream --predicate 'process == "Casberi" AND eventMessage CONTAINS "sheetShape"' \
    --style compact > "$SHEET_LOG" 2>/dev/null &
  SHPID=$!
  sleep 1
  xcrun simctl launch "$DEVICE" "$BUNDLE" -onboarded YES -sheetShapeProbe YES >/dev/null 2>&1 || true
  for i in {1..15}; do
    sleep 1
    grep -q "sheetShape| corpus=" "$SHEET_LOG" 2>/dev/null && break
  done
  sleep 2
  kill $SHPID 2>/dev/null || true
  xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
  MISSING_SHAPES=()
  for shape in "${EXPECTED_SHAPES[@]}"; do
    # `= 0` can't appear (the probe only emits shapes it counted), so the
    # test is presence of the line at all.
    grep -q "sheetShape| $shape = " "$SHEET_LOG" 2>/dev/null || MISSING_SHAPES+=("$shape")
  done
  if (( ${#MISSING_SHAPES[@]} == 0 )); then
    print -P "%F{green}✓ demo sheet-anatomy coverage (${#EXPECTED_SHAPES[@]}/${#EXPECTED_SHAPES[@]})%f"
  else
    fail "demo sheet anatomies unreachable: ${MISSING_SHAPES[*]} — see $SHEET_LOG"
  fi
fi

print -P "%F{green}✓ verify complete → $OUT%f"
