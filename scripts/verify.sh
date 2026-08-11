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

# Keeps the connect pages from regrowing their wall of text (prd §315).
# Static, no build. It is mechanical for the reason every rule in this file is
# mechanical: the copy has now been de-walled twice from memory (§218's "one
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
"$ROOT/scripts/category-fold-selftest.sh" >/dev/null \
  || fail "the category fold self-test failed — run scripts/category-fold-selftest.sh"
print -P "%F{green}✓ category fold self-test%f"

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

# ── 5. Demo panel figure-kind coverage (headless, WARN-only) ────────
# Asked directly (2026-08-08): "how do we make sure the demo has parity"
# with app features, specifically the agent panel. Checks D/E in
# demo-selftest.py answer the CATALOG-NAME half of that (a bridge that
# claims a demo seat must have real rows); this answers the RENDERING half
# for the one surface with the widest fan-in of figure kinds — does the
# furnished demo corpus actually exercise every `AgentPanel.Figure` case,
# or does some kind draw nothing because the demo never gives it enough to
# work with. Text checks can't answer that; only running the real
# composer over the real demo corpus can, which is why this lives in the
# simulator tail rather than in demo-selftest.py's static half.
#
# It found a real bug on its first real run, not a hypothetical: `runway`
# never appeared, because `CloudflareRunwaySource.compose` returns nil
# without a saved `CloudflareEstateStore` snapshot, which nothing seeded.
# Fixed in `DemoSeedAll.seedCloudflareEstate` (2026-08-08).
#
# WARN-ONLY, never `fail` — and that is a considered choice, not a
# shortcut. The panel caps at 20 cards, ranked by affinity, so a figure
# kind that genuinely CAN compose can still lose the ranking race on any
# single run (measured: PostHog's `curve` present in two runs, absent in a
# third, same build, same corpus). A hard fail on that would be exactly
# the "lint that cries wolf" class this codebase's own audits go out of
# their way to avoid — this check can prove a kind CAN'T draw (the
# Cloudflare bug), it can't prove a single run's absence means it can't.
step "Demo panel figure-kind coverage"
PANEL_LOG="$OUT/demo-panel-coverage.log"
xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
xcrun simctl spawn "$DEVICE" log stream \
  --predicate 'process == "Casberi" AND (eventMessage CONTAINS "demoMode:" OR eventMessage CONTAINS "agentPanel")' \
  --style compact > "$PANEL_LOG" 2>/dev/null &
PANELPID=$!
sleep 1
xcrun simctl launch "$DEVICE" "$BUNDLE" -fresh YES -onboarded YES -demoEnter YES >/dev/null 2>&1 || true
POURED=""
for i in {1..20}; do
  sleep 1
  grep -q "demoMode: poured" "$PANEL_LOG" 2>/dev/null && { POURED=1; break; }
done
if [[ -z "$POURED" ]]; then
  kill $PANELPID 2>/dev/null || true
  print -P "%F{yellow}⚠ demo never finished pouring — skipping coverage check (see $PANEL_LOG)%f"
else
  sleep 2
  xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
  sleep 1
  xcrun simctl launch "$DEVICE" "$BUNDLE" -openComposer YES -agentOpenProbe YES >/dev/null 2>&1 || true
  for i in {1..15}; do
    sleep 1
    grep -q "agentPanel|" "$PANEL_LOG" 2>/dev/null && break
  done
  kill $PANELPID 2>/dev/null || true
  xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true

  # The exhaustive kind list comes from AgentPanelProbe.swift's OWN switch —
  # the exact source of the log lines this parses — not a hand-maintained
  # copy that could drift from what the probe actually reports.
  ALL_KINDS=($(grep -oE 'case \.[a-z]+\(' "$ROOT/Casberi/Casberi/Model/AgentPanelProbe.swift" \
    | sed -E 's/case \.([a-z]+)\(/\1/' | sort -u))
  SEEN_KINDS=($(grep -oE 'agentPanelCard\| [^·]+· [a-z]+\(' "$PANEL_LOG" 2>/dev/null \
    | sed -E 's/.*· ([a-z]+)\(/\1/' | sort -u))
  # Documented, conscious exemptions — never a silent skip:
  #   pulse   — graded below everything by ruling (§336); a demo that fought
  #             that ruling would be showing a panel the app doesn't build.
  #   scatter — needs real on-device sentence embeddings (NLEmbedding), and
  #             the simulator ships no on-device model at all — structurally
  #             unavailable here regardless of demo data richness, same
  #             ceiling every on-device-intelligence probe in this file hits.
  EXEMPT=(pulse scatter)
  MISSING=()
  for k in "${ALL_KINDS[@]}"; do
    [[ " ${EXEMPT[*]} " == *" $k "* ]] && continue
    [[ " ${SEEN_KINDS[*]} " == *" $k "* ]] || MISSING+=("$k")
  done
  if (( ${#MISSING[@]} == 0 )); then
    print -P "%F{green}✓ demo panel figure-kind coverage (${#SEEN_KINDS[@]}/${#ALL_KINDS[@]}, ${#EXEMPT[@]} exempt)%f"
  else
    print -P "%F{yellow}⚠ demo panel missing figure kind(s): ${MISSING[*]} — could be this run's top-20 ranking, or a real gap like the Cloudflare one; check $PANEL_LOG, re-run to see if it's consistent%f"
  fi
fi

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
# The (name, source) pairs mirror `ProbeHooks.swift`'s `roomInsightProbe`
# hook and `FeedScreen.sourceHead(_:)`'s switch — change one, change all
# three (the same acknowledged fragility that hook's own header already
# carries; there is no clean way to derive a Swift `case` → source-string
# mapping from a shell script without hand-parsing the same switch this
# hook already mirrors by hand).
step "Demo room-head coverage"
ROOMHEAD_LOG="$OUT/demo-roomhead-coverage.log"
if [[ -z "$POURED" ]]; then
  print -P "%F{yellow}⚠ demo never finished pouring (see the panel-coverage step above) — skipping room-head coverage%f"
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

print -P "%F{green}✓ verify complete → $OUT%f"
