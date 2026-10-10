#!/bin/zsh
# Casberi widget self-test — the contract between the app and its Home Screen
# (prd §382, 2026-08-14):
#
#   Casberi/Shared/WidgetPayload.swift
#     — WidgetPayload.write/read   (the publish round trip, and the reload budget)
#     — WidgetWalletLine.normalizedPoints  (a flat curve draws down the MIDDLE)
#     — WidgetFlowBand             (the week's flow, and its disclosure)
#     — WidgetRunway.positions     (the dated rail's window always contains now)
#     — WidgetWatch.quote / carryForward / priceText  (the Watchlist tile, §1223:
#       a price is a reading — stamped past an hour, dropped past a day, and a
#       failed read keeps the last price with its own time)
#
# One widget since the ask retired (2026-10-01): the wallet. The Today and
# kept-ask tiles, and the asks, deadlines, Safe-call, requests and people
# payloads they read, went with it; the publisher clears what they left.
#   Casberi/Shared/MoneyFormat.swift
#     — compactUSD / isFlatPercent / percentLabel
#
# WHY A HARNESS. Every failure here renders as a perfectly good-looking tile,
# and the widget extension is the one surface in this project that NOTHING else
# can see: `xcodebuild` compiles it and never runs it, the static audits never
# looked at it until today, the screen sweep drives the app and not the Home
# Screen, and no probe can attach to another process's timeline. So:
#
#   • **A FLAT WALLET CURVE DRAWN ALONG THE FLOOR.** The obvious normalization
#     divides by a range that is zero for a flat series, and the obvious guard
#     against dividing by zero returns 0 — which draws a wallet that did nothing
#     as a wallet that went to zero, the most alarming possible way to say
#     nothing happened. `AgentPanel` has carried this rule since §334; this is
#     the same rule in another process.
#   • **A stale READING printed as a current one.** A widget has no choice but
#     to persist its readings, so the freshness window is the only thing
#     standing between a tile and a stale number in the largest type on the
#     screen — and a window that silently stops being applied looks identical
#     to one that works.
#   • **A publish that reloads on every foreground.** `reloadTimelines` is
#     budgeted by the system; spending it rewriting identical bytes is how a
#     tile stops updating when something REAL changes. Invisible on a desk,
#     expensive on a phone.
#   • **A change that rounds to zero, painted green.** §83's own corollary, in
#     the one place the app prints a figure it cannot annotate.
#   • **An encoder/decoder that disagree.** One `JSONEncoder` date strategy
#     changed on the writing side and every tile empties at once, with nothing
#     in any log to say why — a payload that fails to decode is indistinguishable
#     from one that was never published.
#
# Both files are Foundation-only BY DESIGN and are compiled WHOLE AND
# UNMODIFIED. The only stub is `SharedStore.appGroup` — a string constant these
# files name in default arguments — which is inert by construction.
#
# Pure, local, deterministic — no network, no simulator, no corpus.
set -euo pipefail
cd "$(dirname "$0")/.."

PAYLOAD="Casberi/Shared/WidgetPayload.swift"
MONEY="Casberi/Shared/MoneyFormat.swift"
PUBLISH="Casberi/Casberi/Model/WidgetPublish.swift"
BUNDLE="Casberi/CasberiWidgets/CasberiWidgets.swift"
WALLETW="Casberi/CasberiWidgets/WalletWidget.swift"
ROOT="Casberi/Casberi/Shell/RootShell.swift"
COMMIT="Casberi/Casberi/Model/ImportCommit.swift"
PANEL="Casberi/Casberi/Model/AgentPanel.swift"
for f in "$PAYLOAD" "$MONEY" "$PUBLISH" "$BUNDLE" "$WALLETW" \
         "$ROOT" "$COMMIT" "$PANEL"; do
  [[ -f "$f" ]] || { print -u2 "missing $f"; exit 1; }
done

if [[ "${1:-}" == "--self-test" ]]; then
  # Required of every discovered audit (verify.sh): a check that cannot
  # demonstrate it catches anything certifies nothing. The mutation pass below
  # IS this file's self-test — it proves each assertion is load-bearing by
  # breaking the shipped source and requiring the suite to go red.
  print "widget-selftest: --self-test runs the full suite (mutations included)"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Negative guards read a COMMENT-STRIPPED copy (the Obsidian/Cursor lesson,
# earned repeatedly in this tree). These files DOCUMENT the rules by naming the
# very spellings they forbid — "the naive guard against that returns 0", "never
# 'N of M'" — so a guard grepping raw source fires against the prose explaining
# the rule it protects.
strip_comments() {
  python3 - "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
src = re.sub(r'^\s*//.*$', '', src, flags=re.M)
src = re.sub(r'(?<!:)//.*$', '', src, flags=re.M)
print(src)
PY
}
strip_comments "$PUBLISH" > "$TMP/publish.nc"
strip_comments "$BUNDLE"  > "$TMP/bundle.nc"
strip_comments "$WALLETW" > "$TMP/walletw.nc"
strip_comments "$ROOT"    > "$TMP/root.nc"
strip_comments "$COMMIT"  > "$TMP/commit.nc"
strip_comments "$PANEL"   > "$TMP/panel.nc"

# --- drift guards -----------------------------------------------------------
# Wiring the compiled functions cannot prove on their own. A perfect payload is
# worthless if nothing publishes it, and a perfect freshness rule is worthless
# if a tile reads the defaults directly.

# THE CENTRAL INVARIANT of the whole widget target: it computes nothing and
# reaches nothing. The extension runs in a ~30MB budget; a network call there is
# both impossible in practice and a privacy claim broken in principle, since
# `NetworkReach` (§205) describes what the APP reaches and no screen in it can
# speak for another process.
if grep -rlE '\b(URLSession|URLRequest)\b' Casberi/CasberiWidgets >/dev/null 2>&1; then
  print -u2 "✗ a widget file reaches the network — the extension may only read the app group and the store"
  grep -rlE '\b(URLSession|URLRequest)\b' Casberi/CasberiWidgets >&2
  exit 1
fi

# The widget must take its kind from the shared constant, never a literal.
# The app reloads BY KIND (`WidgetCenter.reloadTimelines(ofKind:)`), so a
# hardcoded string that drifts leaves the tile listening on a channel nobody
# writes — it keeps drawing, forever, whatever it last had.
grep -q 'kind: WidgetWallet.kind' "$TMP/walletw.nc" \
  || { print -u2 "✗ the wallet widget no longer uses WidgetWallet.kind"; exit 1; }

# The publisher must run on BOTH sides of RootShell's DEBUG/release fork. The
# whole feature is dead in one configuration if it lands in only one — and the
# configuration people actually ship is the `#else` half, which no simulator
# run and no probe here would ever exercise.
[[ "$(grep -c 'WidgetPublish.publishAll(things:' "$TMP/root.nc")" -ge 2 ]] \
  || { print -u2 "✗ WidgetPublish.publishAll is not called on both branches of RootShell's DEBUG fork —"; \
       print -u2 "  every tile would be stale in whichever configuration is missing it."; exit 1; }

# Reload only what changed. See `WidgetPayload.write`'s own note.
grep -q 'if stale { WidgetCenter.shared.reloadTimelines(ofKind: WidgetWallet.kind) }' "$TMP/publish.nc" \
  || { print -u2 "✗ publishAll no longer reloads only when a payload changed — it would spend the"; \
       print -u2 "  system's refresh budget rewriting identical bytes on every foreground."; exit 1; }
# What the retired tiles left in the app group is cleared on every pass
# (2026-10-01) — a payload with no reader is a stale reading kept forever.
grep -q 'sweepRetired(group)' "$TMP/publish.nc" \
  || { print -u2 "✗ publishAll no longer clears the retired widgets' payloads"; exit 1; }
for k in widget.asks widget.deadlines widget.safe widget.requests widget.people; do
  grep -q "\"$k\"" "$TMP/publish.nc" \
    || { print -u2 "✗ the retired payload $k is no longer cleared"; exit 1; }
done

# §374, and the reason it is a WITHHOLD rather than a mask: a Home Screen is the
# most stood-next-to surface the OS has, and the threat §374 exists for is
# exactly somebody standing next to you.
grep -q 'hidden ? nil : last.usd' "$TMP/publish.nc" \
  || { print -u2 "✗ the wallet payload no longer withholds the total under Hide wallet balances (§374)"; exit 1; }
grep -q 'points: points' "$TMP/publish.nc" \
  || { print -u2 "✗ the wallet payload no longer publishes the curve — §374 rule 3 keeps the SHAPE"; exit 1; }

# The import Live Activity must end on BOTH exits. Ending only on success
# leaves a lock-screen count frozen forever after a failed import, with no way
# to tell that the run is over.
[[ "$(grep -c 'ImportActivityDriver.finish' "$TMP/commit.nc")" -ge 2 ]] \
  || { print -u2 "✗ ImportCommit no longer ends the Live Activity on its failure path —"; \
       print -u2 "  a failed import would leave a frozen count on the lock screen forever."; exit 1; }

# ONE money table. Two copies drift, and then the tile and the balance card
# print different figures for one wallet on one screen at the same moment.
grep -q 'MoneyFormat.compactUSD(usd)' "$TMP/panel.nc" \
  || { print -u2 "✗ AgentPanel.compactUSD no longer forwards to MoneyFormat — there are two tables again"; exit 1; }
grep -qE '\$%\.1fK' "$TMP/panel.nc" \
  && { print -u2 "✗ AgentPanel has grown its own compactUSD table back"; exit 1; }

# Every tile the bundle declares must actually be in the bundle. A widget
# struct that compiles and is never listed is invisible with no error anywhere.
for w in NotesWidget WalletWidget FeedWidget WatchlistWidget ComposeControl NoteControl; do
  grep -q "        $w()" "$TMP/bundle.nc" \
    || { print -u2 "✗ $w is not in the widget bundle — it would never appear in the gallery"; exit 1; }
done
# Three widgets, each a small tile (prd §1210). The Category widget went with it.
grep -q "        CategoryWidget()" "$TMP/bundle.nc" \
  && { print -u2 "✗ CategoryWidget is back in the bundle — §1210 replaced it with Notes and Feed"; exit 1; }
for wf in WalletWidget NotesWidget FeedWidget WatchlistWidget; do
  f="Casberi/CasberiWidgets/$wf.swift"
  [[ -f "$f" ]] || { print -u2 "missing $f"; exit 1; }
  strip_comments "$f" > "$TMP/$wf.nc"
  grep -q '.supportedFamilies(\[.systemSmall\])' "$TMP/$wf.nc" \
    || { print -u2 "✗ $wf offers a size other than the small tile (prd §1210)"; exit 1; }
done
grep -q 'kind: WidgetNotes.kind' "$TMP/NotesWidget.nc" \
  || { print -u2 "✗ the Notes widget no longer uses WidgetNotes.kind"; exit 1; }
grep -q 'kind: WidgetFeedTile.kind' "$TMP/FeedWidget.nc" \
  || { print -u2 "✗ the Feed widget no longer uses WidgetFeedTile.kind"; exit 1; }
grep -q 'kind: WidgetWatch.kind' "$TMP/WatchlistWidget.nc" \
  || { print -u2 "✗ the Watchlist widget no longer uses WidgetWatch.kind"; exit 1; }
# A price is a reading (§1223): the tile draws one only through the freshness
# rule, never straight off the row.
grep -q 'WidgetWatch.quote(row, now: entry.date)' "$TMP/WatchlistWidget.nc" \
  || { print -u2 "✗ the Watchlist widget draws a price without asking whether it is still fresh"; exit 1; }
grep -qE 'row\.price\b' "$TMP/WatchlistWidget.nc" \
  && { print -u2 "✗ the Watchlist widget reads row.price directly — a day-old price would draw as now's"; exit 1; }
# The publisher runs after the prices read, in the foreground and the background task.
strip_comments "Casberi/Casberi/Model/BridgeRefresh.swift" > "$TMP/refresh.nc"
strip_comments "Casberi/Casberi/Model/WalletBackgroundRefresh.swift" > "$TMP/bg.nc"
grep -q 'WidgetPublish.watchlist(context: context, read: true)' "$TMP/refresh.nc" \
  || { print -u2 "✗ the foreground refresh no longer publishes the watchlist after its prices read"; exit 1; }
grep -q 'WidgetPublish.watchlist(context: context, read: true)' "$TMP/bg.nc" \
  || { print -u2 "✗ the background task no longer publishes the watchlist"; exit 1; }
grep -q 'guard !DemoMode.isActive,' "$TMP/publish.nc" \
  || { print -u2 "✗ the watchlist publish no longer stands down in the demo (§217)"; exit 1; }
grep -q 'WidgetWatch.carryForward(' "$TMP/publish.nc" \
  || { print -u2 "✗ the watchlist publish no longer carries a price forward — a failed read would blank the tile"; exit 1; }
grep -q 'if WidgetPayload.write(list, key: WidgetWatch.key,' "$TMP/publish.nc" \
  || { print -u2 "✗ the watchlist publish no longer reloads only when its payload changed"; exit 1; }
# A count of today is a DATE's reading: the tile draws it only on that day.
grep -q 'feed.isCurrent(now: entry.date)' "$TMP/FeedWidget.nc" \
  || { print -u2 "✗ the Feed widget draws its counts without asking whether they are today's"; exit 1; }
# The Feed holds no money (§1208 item 7), so neither does its tile.
grep -q '"Wallet", "Markets", "Testnets"' "$TMP/publish.nc" \
  || { print -u2 "✗ the Feed widget's payload no longer leaves the money categories out"; exit 1; }
# The flow band's disclosure is the one piece the tile may not drop (WidgetFlowBand.owesDisclosure).
grep -q 'pricedNote(flow)' "$TMP/walletw.nc" \
  || { print -u2 "✗ the wallet tile no longer says how much of the week its bars are drawn from"; exit 1; }
for k in widget.shelves widget.shelvesAt; do
  grep -q "\"$k\"" "$TMP/publish.nc" \
    || { print -u2 "✗ the retired payload $k is no longer cleared"; exit 1; }
done
# ...and the three the ask took with it must STAY out (2026-10-01).
for w in TodayWidget KeptAskWidget BriefControl; do
  grep -q "        $w()" "$TMP/bundle.nc" \
    && { print -u2 "✗ $w is back in the bundle — it went with the ask"; exit 1; }
done

print "widget-selftest: drift guards OK"

# --- the compiled suite -----------------------------------------------------

cat > "$TMP/stub.swift" <<'SWIFT'
import Foundation
// Inert: the real `SharedStore` is a SwiftData container factory, and these
// files name only this one constant, in default arguments.
enum SharedStore { static let appGroup = "group.com.casberi.selftest" }
SWIFT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { failures += 1; print("  ✗ \(what)") }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ what: String) {
    if a != b { failures += 1; print("  ✗ \(what) — got \(a), wanted \(b)") }
}

// A private suite so the suite's own state can never touch the real app group.
let suiteName = "casberi.widget.selftest"
UserDefaults().removePersistentDomain(forName: suiteName)
let d = UserDefaults(suiteName: suiteName)!

// ── the publish round trip ──────────────────────────────────────────────────
// The encode and the decode are the one place the two processes can silently
// disagree; a payload that fails to decode looks exactly like one never sent.
let bands = [WidgetFlowBand(inWeight: 1, outWeight: 0.5, inUSD: 2400, outUSD: 1200,
                            unpriced: 0, predating: 0, priced: 9),
             WidgetFlowBand(inWeight: 0.25, outWeight: 1, inUSD: 300, outUSD: 1200,
                            unpriced: 1, predating: 0, priced: 3)]
check(WidgetPayload.write(bands, key: "k", stampKey: "kAt", defaults: d),
      "a first publish reports a change")
let back = WidgetPayload.read([WidgetFlowBand].self, key: "k", stampKey: "kAt",
                              freshness: 3600, defaults: d)
eq(back?.count, 2, "the payload round-trips")
eq(back?[0].inUSD, 2400, "a reading survives the round trip")
eq(back?[1].unpriced, 1, "the disclosure count survives the round trip")

// THE RELOAD BUDGET. Publishing identical bytes must report no change.
check(!WidgetPayload.write(bands, key: "k", stampKey: "kAt", defaults: d),
      "republishing identical bytes reports NO change")
// ...and the stamp must move anyway, or a payload republished unchanged would
// age out while the app is being used every day.
let stampAfter = d.double(forKey: "kAt")
check(stampAfter > 0, "the stamp is written even when the bytes did not change")

var changed = bands
changed[0] = WidgetFlowBand(inWeight: 1, outWeight: 0.6, inUSD: 2400, outUSD: 1440,
                            unpriced: 0, predating: 0, priced: 9)
check(WidgetPayload.write(changed, key: "k", stampKey: "kAt", defaults: d),
      "a different reading reports a change")

// Clearing.
check(WidgetPayload.write(Optional<[WidgetFlowBand]>.none, key: "k", stampKey: "kAt", defaults: d),
      "clearing a published payload reports a change")
check(!WidgetPayload.write(Optional<[WidgetFlowBand]>.none, key: "k", stampKey: "kAt", defaults: d),
      "clearing an already-empty payload reports NO change")
check(WidgetPayload.read([WidgetFlowBand].self, key: "k", stampKey: "kAt",
                         freshness: 3600, defaults: d) == nil,
      "a cleared payload reads as nothing")

// ── freshness ───────────────────────────────────────────────────────────────
_ = WidgetPayload.write(bands, key: "f", stampKey: "fAt", defaults: d)
let now = Date()
check(WidgetPayload.read([WidgetFlowBand].self, key: "f", stampKey: "fAt",
                         freshness: 3600, now: now, defaults: d) != nil,
      "a fresh payload reads")
check(WidgetPayload.read([WidgetFlowBand].self, key: "f", stampKey: "fAt",
                         freshness: 3600, now: now.addingTimeInterval(7200),
                         defaults: d) == nil,
      "a payload past its freshness window reads as nothing")
// A payload with NO stamp at all must not read — the pre-stamp legacy case,
// and the shape a partial write would leave behind.
d.set(d.data(forKey: "f"), forKey: "nostamp")
check(WidgetPayload.read([WidgetFlowBand].self, key: "nostamp", stampKey: "missingAt",
                         freshness: 3600, defaults: d) == nil,
      "an unstamped payload reads as nothing")

// ── the wallet curve ────────────────────────────────────────────────────────
// THE ONE THAT MATTERS MOST: a flat series draws down the MIDDLE. Along the
// floor it reads as a wallet that went to zero.
let flat = WidgetWalletLine(points: [500, 500, 500, 500], total: 500,
                            changePct: 0, hidden: false, asOf: now)
eq(flat.normalizedPoints, [0.5, 0.5, 0.5, 0.5],
   "a FLAT curve normalizes to the middle, never the floor")

let rising = WidgetWalletLine(points: [100, 150, 200], total: 200,
                              changePct: 100, hidden: false, asOf: now)
eq(rising.normalizedPoints, [0, 0.5, 1], "a rising curve spans the full height")
let falling = WidgetWalletLine(points: [200, 100], total: 100,
                               changePct: -50, hidden: false, asOf: now)
eq(falling.normalizedPoints, [1, 0], "a falling curve starts high and ends low")
let empty = WidgetWalletLine(points: [], total: nil, changePct: nil, hidden: false, asOf: now)
check(empty.normalizedPoints.isEmpty, "an empty series normalizes to nothing")
// A zero-valued flat line is the case where the naive guard and the correct one
// give different answers AND the naive one looks plausible.
let zeroes = WidgetWalletLine(points: [0, 0], total: 0, changePct: nil, hidden: false, asOf: now)
eq(zeroes.normalizedPoints, [0.5, 0.5], "a flat line AT zero still draws down the middle")

// §374: figures go, shapes stay.
let hidden = WidgetWalletLine(points: [100, 200], total: nil, changePct: nil,
                              hidden: true, asOf: now)
check(hidden.total == nil, "a hidden line carries no figure")
check(hidden.changePct == nil, "a hidden line carries no percent either")
eq(hidden.normalizedPoints, [0, 1], "a hidden line still carries its SHAPE")
_ = WidgetPayload.write(hidden, key: WidgetWallet.key, stampKey: WidgetWallet.stampKey, defaults: d)
check(WidgetWallet.published(now: now, defaults: d)?.total == nil,
      "the withheld figure is still absent after a round trip")

// ── the runway ──────────────────────────────────────────────────────────────
// THE INVARIANT: the window always CONTAINS now. Get it wrong and late items
// draw ahead of the marker — the exact distinction the tile exists to make.
let hourAgo = now.addingTimeInterval(-3600)
let inThree = now.addingTimeInterval(3 * 3600)
if let rail = WidgetRunway.positions(for: [hourAgo, inThree], now: now) {
    check(rail.dots[0] < rail.now, "an overdue deadline sits LEFT of the marker")
    check(rail.dots[1] > rail.now, "a future one sits right of it")
    check(rail.dots.allSatisfy { $0 >= 0 && $0 <= 1 }, "every dot is on the track")
    check(rail.now > 0 && rail.now < 1, "and so is the marker")
    // The ends are PADDED, so a dot at either extreme isn't clipped in half by
    // the track it sits on. Without this the earliest would sit at exactly 0
    // and render as a half-moon against the tile's edge.
    check(abs(rail.dots[0] - WidgetRunway.pad) < 0.0001,
          "the earliest deadline sits at the pad, not at the very edge")
    check(abs(rail.dots[1] - (1 - WidgetRunway.pad)) < 0.0001,
          "and the latest at one pad in from the other end")
    check(WidgetRunway.pad > 0, "the padding is real")
} else { check(false, "a two-deadline rail should place") }

// Every date in the past: now is still on the rail, at the far right.
if let allLate = WidgetRunway.positions(for: [now.addingTimeInterval(-7200), hourAgo], now: now) {
    check(allLate.dots.allSatisfy { $0 < allLate.now },
          "when everything is overdue, now is the right-hand end — nothing draws ahead of it")
    check(allLate.now <= 1, "and the marker is still on the track")
} else { check(false, "an all-overdue rail should place") }

// Every date in the future: now anchors the left.
if let allAhead = WidgetRunway.positions(for: [inThree, now.addingTimeInterval(9 * 3600)], now: now) {
    check(allAhead.dots.allSatisfy { $0 > allAhead.now },
          "when nothing is late, now is the left-hand end")
} else { check(false, "an all-ahead rail should place") }

check(WidgetRunway.positions(for: [], now: now) == nil, "no deadlines, no rail")
check(WidgetRunway.positions(for: [now], now: now) == nil,
      "a zero-width window has no shape to draw — the rows say it instead")

// ── the flow band ───────────────────────────────────────────────────────────
// Two bars, no counterparty names (the user's ruling) — but the DISCLOSURE
// could not be dropped with them: `WalletFlow.Band` states that a band drawn
// from 6 of 9 moves is a different claim from one drawn from all 9.
let full = WidgetFlowBand(inWeight: 1, outWeight: 0.5, inUSD: 2400, outUSD: 1200,
                          unpriced: 0, predating: 0, priced: 9)
check(!full.owesDisclosure, "a complete band says nothing — there is no gap to disclose")
check(!full.isPartial, "…and knows it isn't partial")
eq(full.total, 9, "a complete band's total is its priced legs")

let partial = WidgetFlowBand(inWeight: 1, outWeight: 0.5, inUSD: 2400, outUSD: 1200,
                             unpriced: 2, predating: 1, priced: 6)
check(partial.isPartial, "a band missing legs is partial")
eq(partial.total, 9, "the total counts unpriced AND predating legs, not just drawn ones")
check(partial.owesDisclosure, "…and SAYS so — the no-silent-caps rule")

// The weights are the shape, and they survive §374 losing the figures.
let (wIn, wOut) = WidgetFlowBand.weights(inUSD: 2400, outUSD: 1200)
eq(wIn, 1.0, "the larger side fills the track")
eq(wOut, 0.5, "and the smaller reads against it")
let (zIn, zOut) = WidgetFlowBand.weights(inUSD: 0, outUSD: 0)
eq(zIn, 0.0, "a week with no priced flow draws nothing")
eq(zOut, 0.0, "…on both sides")
let (oIn, oOut) = WidgetFlowBand.weights(inUSD: 0, outUSD: 900)
eq(oIn, 0.0, "a side of ZERO draws nothing, never a hairline —")
eq(oOut, 1.0, "…while the other still fills the track")

let hiddenBand = WidgetFlowBand(inWeight: 1, outWeight: 0.5, inUSD: nil, outUSD: nil,
                                unpriced: 0, predating: 0, priced: 4, hidden: true)
check(hiddenBand.inUSD == nil && hiddenBand.outUSD == nil,
      "§374 withholds the flow figures, exactly as it withholds the total")
eq(hiddenBand.inWeight, 1.0, "…and the RATIO stays, because a ratio is a shape")
eq(hiddenBand.outWeight, 0.5, "…on both bars")
_ = WidgetPayload.write(hiddenBand, key: WidgetWallet.flowKey,
                        stampKey: WidgetWallet.flowStampKey, defaults: d)
check(WidgetWallet.flow(now: now, defaults: d)?.inUSD == nil,
      "the withheld figures are still absent after a round trip")
eq(WidgetWallet.flow(now: now, defaults: d)?.outWeight, 0.5,
   "…and the shape still arrives")

// ── the Feed tile (§1210): today's counts are a DATE's reading ───────────────
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "UTC")!
let noon = Date(timeIntervalSince1970: 1_760_000_000)   // 2025-10-09 08:53 UTC
let feed = WidgetFeed(day: cal.startOfDay(for: noon),
                      sections: [WidgetFeed.Section(room: "Day", today: 4),
                                 WidgetFeed.Section(room: "Social", today: 12)])
check(feed.isCurrent(now: noon, calendar: cal), "the counts are today's on the day they were counted")
check(!feed.isCurrent(now: noon.addingTimeInterval(24 * 3600), calendar: cal),
      "the next day they are not — yesterday's counts never draw as today's")
check(!feed.isCurrent(now: noon.addingTimeInterval(-24 * 3600), calendar: cal),
      "nor the day before")
_ = WidgetPayload.write(feed, key: WidgetFeedTile.key, stampKey: WidgetFeedTile.stampKey, defaults: d)
eq(WidgetFeedTile.published(defaults: d)?.sections.map(\.room) ?? [], ["Day", "Social"],
   "the Feed order survives the round trip")

// ── the Watchlist tile (§1223): a price is a reading ─────────────────────────
let readAt = now.addingTimeInterval(-600)
let eth = WidgetWatchlist.Row(ref: "base:0xeth", symbol: "ETH", name: "Ethereum",
                              price: 4512.3, change: 0.023, at: readAt)
let aapl = WidgetWatchlist.Row(ref: "stocktwits:sym:AAPL", symbol: "AAPL", name: "Apple",
                               price: nil, change: nil, at: nil)
check(WidgetWatch.quote(eth, now: now) != nil, "a price read ten minutes ago draws")
eq(WidgetWatch.quote(eth, now: now)?.at, readAt, "…with the moment it was read, for the stamp")
check(WidgetWatch.quote(eth, now: readAt.addingTimeInterval(WidgetWatch.priceFreshness + 1)) == nil,
      "a price past a day does not draw — the symbol stands alone")
check(WidgetWatch.quote(aapl, now: now) == nil, "a row never priced draws no price")
check(WidgetWatch.priceFreshness > WidgetWatch.stampAfter,
      "a price is stamped before it is dropped")

// A failed read keeps the last price, stamped by its own time; a new read wins.
let prev = WidgetWatchlist(rows: [eth, WidgetWatchlist.Row(ref: "stocktwits:sym:AAPL", symbol: "AAPL",
                                                          name: "Apple", price: 254, change: -0.01,
                                                          at: readAt)])
let unread = WidgetWatchlist.Row(ref: "base:0xeth", symbol: "ETH", name: "Ethereum",
                                 price: nil, change: nil, at: nil)
let fresh = WidgetWatchlist.Row(ref: "stocktwits:sym:AAPL", symbol: "AAPL", name: "Apple",
                                price: 256, change: 0.004, at: now)
let carried = WidgetWatch.carryForward([unread, fresh], from: prev)
eq(carried[0].price, 4512.3, "an unpriced row keeps the last publish's price")
eq(carried[0].at, readAt, "…and that price's own time, so it ages out on time")
eq(carried[1].price, 256, "a row read this pass keeps its new price")
eq(WidgetWatch.carryForward([unread], from: nil)[0].price, nil, "nothing to carry, nothing carried")
let newcomer = WidgetWatchlist.Row(ref: "base:0xnew", symbol: "NEW", name: "New",
                                   price: nil, change: nil, at: nil)
eq(WidgetWatch.carryForward([newcomer], from: prev)[0].price, nil,
   "a price is carried by ref, never onto another row")

eq(WidgetWatch.priceText(254), "$254.00", "a stock's price keeps its cents")
eq(WidgetWatch.priceText(0.5), "$0.5000", "under a dollar, four places")
// The two below format in the reader's locale, so they assert the digits.
let tiny = WidgetWatch.priceText(0.00001234)
check(tiny.hasPrefix("$0") && tiny.hasSuffix("0000123"), "under a cent, three significant digits — got \(tiny)")
check(WidgetWatch.priceText(4512.3).hasSuffix("512"), "from $1,000 the cents go")

_ = WidgetPayload.write(WidgetWatchlist(rows: [eth, aapl]), key: WidgetWatch.key,
                        stampKey: WidgetWatch.stampKey, defaults: d)
eq(WidgetWatch.published(defaults: d)?.rows.map(\.symbol) ?? [], ["ETH", "AAPL"],
   "the watchlist's order survives the round trip")

// ── money ───────────────────────────────────────────────────────────────────
eq(MoneyFormat.compactUSD(0), "$0", "zero")
eq(MoneyFormat.compactUSD(950), "$950", "under a thousand keeps every digit")
eq(MoneyFormat.compactUSD(1_240), "$1.2K", "a small thousands figure keeps its decimal")
eq(MoneyFormat.compactUSD(47_300), "$47K", "a large thousands figure drops it")
eq(MoneyFormat.compactUSD(1_240_000), "$1.2M", "millions")
eq(MoneyFormat.compactUSD(2_500_000_000), "$2.5B", "billions")
// The sign lands INSIDE the currency mark — `$-1.2K`, not `-$1.2K`. That looks
// like a defect and is deliberate shipped behaviour, pinned independently by
// `agent-panel-selftest.sh` ("a negative keeps its tier", `$-7.3M`). Left alone
// on purpose: the widget's own figure is a wallet TOTAL and cannot be negative,
// so nothing here is served by changing money formatting app-wide.
eq(MoneyFormat.compactUSD(-1_240), "$-1.2K", "a negative keeps its rung (sign inside the mark)")

// §83's corollary: a change that rounds to zero has no direction.
check(MoneyFormat.isFlatPercent(0), "exactly zero is flat")
check(MoneyFormat.isFlatPercent(0.04), "0.04% is flat")
check(!MoneyFormat.isFlatPercent(0.06), "0.06% is not flat")
check(!MoneyFormat.isFlatPercent(-2.1), "a real fall is not flat")
eq(MoneyFormat.percentLabel(0.01), "0.0%", "a flat change is printed with NO sign")
eq(MoneyFormat.percentLabel(2.14), "+2.1%", "a rise carries a plus")
eq(MoneyFormat.percentLabel(-0.43), "−0.4%", "a fall carries a minus and no negative digits")

UserDefaults().removePersistentDomain(forName: suiteName)
if failures > 0 { print("\(failures) failure(s)"); exit(1) }
print("widget-selftest: the compiled suite passed")
SWIFT

print "widget-selftest: the shipped files, compiled whole…"
# `-Onone`, not `-O`: 97% of a pure-logic harness's wall time is the optimizer,
# and it buys nothing an assertion can see. NOT a blanket rule — `-O` can change
# a harness's OBSERVABLE behaviour (a trapping one prints NOTHING under `-O`) —
# so this file was proven equivalent run-for-run by
# `scripts/support/harness-opt-probe.sh` before the swap (2026-09-05, 1.8x faster).
# Re-probe before trusting it again after adding mutations.
xcrun swiftc -Onone -o "$TMP/run" "$PAYLOAD" "$MONEY" "$TMP/stub.swift" "$TMP/main.swift" 2>&1 \
  | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { print -u2 "✗ compile failed"; exit 1; }
"$TMP/run" || exit 1

# --- mutations --------------------------------------------------------------
# Each must FAIL the suite. A check that cannot fail proves nothing.
mutate() {
  local label="$1" file="$2" expr="$3"
  local dir="$TMP/mut"; rm -rf "$dir"; mkdir -p "$dir"
  cp "$PAYLOAD" "$dir/WidgetPayload.swift"
  cp "$MONEY" "$dir/MoneyFormat.swift"
  python3 - "$dir/$file" "$expr" <<'PY' || { echo "  ✗ STALE MUTATION: the applier exited non-zero (anchor not found — nothing was tested)"; exit 1; }
import sys
path, expr = sys.argv[1], sys.argv[2]
old, new = expr.split("|||")
src = open(path).read()
if old not in src:
    sys.exit("MUTATION ANCHOR MISSING: %r — this harness is testing stale code" % old)
open(path, "w").write(src.replace(old, new, 1))
PY
  if xcrun swiftc -Onone -o "$dir/run" "$dir/WidgetPayload.swift" "$dir/MoneyFormat.swift" \
       "$TMP/stub.swift" "$TMP/main.swift" >/dev/null 2>&1 \
     && "$dir/run" >/dev/null 2>&1; then
    print "  ✗ mutation SURVIVED: $label"
    return 1
  fi
  print "  ✓ mutation caught: $label"
}

print ""
print "widget-selftest: mutation pass…"
mfail=0

# The headline bug this file exists for.
mutate "a flat curve is drawn along the FLOOR instead of down the middle" \
  WidgetPayload.swift \
  'guard span > 0 else { return points.map { _ in 0.5 } }|||guard span > 0 else { return points.map { _ in 0 } }' || mfail=1

# The reload budget.
mutate "write always reports a change — every foreground would spend a reload" \
  WidgetPayload.swift \
  'return previous != value|||return true' || mfail=1
mutate "clearing an already-empty payload reports a change" \
  WidgetPayload.swift \
  'return stored != nil|||return true' || mfail=1
# THE BUG THIS HARNESS ACTUALLY CAUGHT (2026-08-14). The first cut of `write`
# compared the stored BYTES to the new bytes, which reads as obviously correct
# and is not: `JSONEncoder` is not byte-stable across calls for identical input,
# so it reported a change on every publish and the reload-budget rule this
# function exists for never once applied. Silent — tiles just refresh more.
mutate "write compares serialized BYTES instead of decoded values (THE SHIPPED-FIRST BUG)" \
  WidgetPayload.swift \
  'return previous != value|||return stored != data' || mfail=1

# Staleness, both windows.
mutate "read ignores the stamp — a payload never goes stale" \
  WidgetPayload.swift \
  'guard stamp > 0, now.timeIntervalSince1970 - stamp < freshness else { return nil }|||_ = stamp' || mfail=1
# The runway. Its whole invariant is that the window contains now.
mutate "the runway window excludes now — overdue items draw AHEAD of the marker" \
  WidgetPayload.swift \
  'let low = min(dates.min() ?? now, now)
        let high = max(dates.max() ?? now, now)|||let low = dates.min() ?? now
        let high = dates.max() ?? now' || mfail=1
mutate "the runway drops its end padding — a dot at either extreme is clipped in half" \
  WidgetPayload.swift \
  'static let pad = 0.05|||static let pad = 0.0' || mfail=1

# The flow band. Dropping the lane names was a ruling; dropping the disclosure
# would make two bars claim a completeness they don't have.
mutate "a partial band stops disclosing that legs are missing" \
  WidgetPayload.swift \
  'var owesDisclosure: Bool { isPartial && total > 0 }|||var owesDisclosure: Bool { false }' || mfail=1
mutate "the total counts only the drawn legs, so the disclosure understates the gap" \
  WidgetPayload.swift \
  'var total: Int { priced + unpriced + predating }|||var total: Int { priced }' || mfail=1
mutate "a zero side is drawn as a hairline instead of nothing" \
  WidgetPayload.swift \
  'guard scale > 0 else { return (0, 0) }
        return (inUSD / scale, outUSD / scale)|||guard scale > 0 else { return (0, 0) }
        return (max(0.08, inUSD / scale), max(0.08, outUSD / scale))' || mfail=1

# The Feed tile's day.
mutate "the Feed tile's counts stay current past midnight" \
  WidgetPayload.swift \
  'calendar.isDate(day, inSameDayAs: now)|||true' || mfail=1

# The Watchlist tile's prices.
mutate "a price never ages out — a week-old price draws as now's" \
  WidgetPayload.swift \
  'now.timeIntervalSince(at) < priceFreshness else { return nil }|||true else { return nil }' || mfail=1
mutate "a failed read blanks the last price instead of carrying it" \
  WidgetPayload.swift \
  'guard let previous else { return rows }|||return rows' || mfail=1
mutate "a carried price is stamped now, so it never ages out" \
  WidgetPayload.swift \
  'price: last.price, change: last.change, at: last.at)|||price: last.price, change: last.change, at: Date())' || mfail=1

# Money.
mutate "a change that rounds to zero is given a direction (§83)" \
  MoneyFormat.swift \
  'static func isFlatPercent(_ pct: Double) -> Bool { abs(pct) < 0.05 }|||static func isFlatPercent(_ pct: Double) -> Bool { false }' || mfail=1
mutate "the thousands rung loses its decimal split" \
  MoneyFormat.swift \
  'if v >= 10_000        { return String(format: "$%.0fK", usd / 1_000) }|||' || mfail=1
mutate "percentLabel drops the sign on a real move" \
  MoneyFormat.swift \
  'return String(format: "%@%.1f%%", pct > 0 ? "+" : "−", abs(pct))|||return String(format: "%.1f%%", abs(pct))' || mfail=1

[[ $mfail -eq 0 ]] || { print -u2 "widget-selftest: a mutation SURVIVED — a check above proves nothing"; exit 1; }
print "widget-selftest: OK — publish round trip, the freshness window, the flat curve, the flow band, the rail, the watchlist's prices and the money table all pinned."
