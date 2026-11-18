#!/bin/zsh
# Casberi widget self-test — the contract between the app and its Home Screen
# (prd §382, 2026-08-14):
#
#   Casberi/Shared/WidgetPayload.swift
#     — WidgetPayload.write/read   (the publish round trip, and the reload budget)
#     — WidgetWalletHome           (Home's figures; withheld under Hide balances)
#     — WidgetFeedTile.rows        (each app's newest thing today, and the rest)
#     — WidgetWatchlist.change     (a move that rounds to zero has no sign)
#     — WidgetRunway.positions     (the dated rail's window always contains now)
#
# Four small tiles (prd §1210, §1881): Notes, Wallet (Home's figures), Feed
# (Home's Activity rows) and Watchlist. The Today and kept-ask tiles and their
# payloads went with the ask (2026-10-01); the publisher clears what they left.
#   Casberi/Shared/MoneyFormat.swift
#     — compactUSD / isFlatPercent / percentLabel
#
# WHY A HARNESS. Every failure here renders as a perfectly good-looking tile,
# and the widget extension is the one surface in this project that NOTHING else
# can see: `xcodebuild` compiles it and never runs it, the static audits never
# looked at it until today, the screen sweep drives the app and not the Home
# Screen, and no probe can attach to another process's timeline. So:
#
#   • **THE TILE AND HOME STATING TWO TOTALS (prd §1881).** The tile drew the
#     followed addresses' line, a different sum from Home's. Home now hands
#     the tile the figures it draws; a publisher that re-derives them is how
#     the two drift apart again.
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
grep -q 'if WidgetPayload.write(figures, key: WidgetWallet.key,' "$TMP/publish.nc" \
  || { print -u2 "✗ the Wallet tile no longer reloads only when Home's figures changed — it would spend the"; \
       print -u2 "  system's refresh budget rewriting identical bytes on every pass."; exit 1; }
# The Wallet tile is Home's figures, handed over by Home (prd §1881): never
# re-derived in the publisher, or the tile and Home state two totals.
FEEDSCREEN="Casberi/Casberi/Screens/FeedScreen.swift"
HOMEHEAD="Casberi/Casberi/Screens/FeedScreen+HomeHead.swift"
strip_comments "$FEEDSCREEN" > "$TMP/feedscreen.nc"
strip_comments "$HOMEHEAD" > "$TMP/homehead.nc"
grep -q '.onChange(of: homeWidgetFigures, initial: true)' "$TMP/feedscreen.nc" \
  || { print -u2 "✗ Home no longer hands its figures to the Wallet tile (prd §1881)"; exit 1; }
grep -q 'total: shown.totalUSD,' "$TMP/homehead.nc" \
  || { print -u2 "✗ the Wallet tile's total is no longer the balance Home prints (prd §1881)"; exit 1; }
grep -qE 'combinedValueSamples|WidgetWalletLine' "$TMP/publish.nc" \
  && { print -u2 "✗ the publisher derives a wallet figure of its own again — the tile and Home would state two totals"; exit 1; }
# The Watchlist tile is republished when its prices land, not only on a foreground.
grep -q 'WidgetPublish.watchlist()' Casberi/Casberi/Model/Watchlist.swift \
  || { print -u2 "✗ the Watchlist tile is no longer republished when its prices land"; exit 1; }
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
grep -q 'if BalancePrivacy.shared.hidden { return .withheld(asOf: asOf) }' "$TMP/homehead.nc" \
  || { print -u2 "✗ Home's figures no longer withhold the balance under Hide account balances (§374)"; exit 1; }

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
grep -q 'kind: WidgetWatchlist.kind' "$TMP/WatchlistWidget.nc" \
  || { print -u2 "✗ the Watchlist widget no longer uses WidgetWatchlist.kind"; exit 1; }
# The pinned price left with Markets (prd §1529); the Watchlist tile came back (§1881).
grep -qE "        PriceActivity\(\)" "$TMP/bundle.nc" \
  && { print -u2 "✗ the pinned price is back in the bundle (prd §1529)"; exit 1; }
# A count of today is a DATE's reading: the tile draws it only on that day.
grep -q 'feed.isCurrent(now: entry.date)' "$TMP/FeedWidget.nc" \
  || { print -u2 "✗ the Feed widget draws its counts without asking whether they are today's"; exit 1; }
# The Feed holds no money (§1208 item 7), so neither does its tile.
grep -q '"Wallet", "Markets", "Testnets"' "$TMP/publish.nc" \
  || { print -u2 "✗ the Feed widget's payload no longer leaves the money categories out"; exit 1; }
# A reading past the normal cadence says when it was read (§825).
grep -q 'WidgetStamp.text(for: home.asOf' "$TMP/walletw.nc" \
  || { print -u2 "✗ the wallet tile no longer stamps an old reading"; exit 1; }
for k in widget.shelves widget.shelvesAt widget.wallet widget.flow widget.feed; do
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
let now = Date()
let homes = [WidgetWalletHome(total: 52_600, dayPct: 0.9, publicUSD: 41_300, privateUSD: 11_300, asOf: now),
             WidgetWalletHome(total: 900, dayPct: nil, publicUSD: 900, privateUSD: nil, asOf: now)]
check(WidgetPayload.write(homes, key: "k", stampKey: "kAt", defaults: d),
      "a first publish reports a change")
let back = WidgetPayload.read([WidgetWalletHome].self, key: "k", stampKey: "kAt",
                              freshness: 3600, defaults: d)
eq(back?.count, 2, "the payload round-trips")
eq(back?[0].total, 52_600, "a reading survives the round trip")
eq(back?[0].privateUSD, 11_300, "the Private head survives the round trip")
check(back?[1].privateUSD == nil, "a side Home draws none of stays absent")

// THE RELOAD BUDGET. Publishing identical bytes must report no change.
check(!WidgetPayload.write(homes, key: "k", stampKey: "kAt", defaults: d),
      "republishing identical bytes reports NO change")
let stampAfter = d.double(forKey: "kAt")
check(stampAfter > 0, "the stamp is written even when the bytes did not change")

var changed = homes
changed[0] = WidgetWalletHome(total: 52_700, dayPct: 1.0, publicUSD: 41_400, privateUSD: 11_300, asOf: now)
check(WidgetPayload.write(changed, key: "k", stampKey: "kAt", defaults: d),
      "a different reading reports a change")

// Clearing.
check(WidgetPayload.write(Optional<[WidgetWalletHome]>.none, key: "k", stampKey: "kAt", defaults: d),
      "clearing a published payload reports a change")
check(!WidgetPayload.write(Optional<[WidgetWalletHome]>.none, key: "k", stampKey: "kAt", defaults: d),
      "clearing an already-empty payload reports NO change")
check(WidgetPayload.read([WidgetWalletHome].self, key: "k", stampKey: "kAt",
                         freshness: 3600, defaults: d) == nil,
      "a cleared payload reads as nothing")

// ── freshness ───────────────────────────────────────────────────────────────
_ = WidgetPayload.write(homes, key: "f", stampKey: "fAt", defaults: d)
check(WidgetPayload.read([WidgetWalletHome].self, key: "f", stampKey: "fAt",
                         freshness: 3600, now: now, defaults: d) != nil,
      "a fresh payload reads")
check(WidgetPayload.read([WidgetWalletHome].self, key: "f", stampKey: "fAt",
                         freshness: 3600, now: now.addingTimeInterval(7200),
                         defaults: d) == nil,
      "a payload past its freshness window reads as nothing")
d.set(d.data(forKey: "f"), forKey: "nostamp")
check(WidgetPayload.read([WidgetWalletHome].self, key: "nostamp", stampKey: "missingAt",
                         freshness: 3600, defaults: d) == nil,
      "an unstamped payload reads as nothing")

// ── Hide balances (§374): the figures are never published ───────────────────
let hidden = WidgetWalletHome.withheld(asOf: now)
check(hidden.hidden, "a withheld reading says it is hidden")
check(hidden.total == nil && hidden.publicUSD == nil && hidden.privateUSD == nil && hidden.dayPct == nil,
      "a withheld reading carries no figure at all")
_ = WidgetPayload.write(hidden, key: WidgetWallet.key, stampKey: WidgetWallet.stampKey, defaults: d)
check(WidgetWallet.published(now: now, defaults: d)?.total == nil,
      "the withheld figure is still absent after a round trip")
check(WidgetWallet.published(now: now, defaults: d)?.hidden == true,
      "and the tile still knows to draw it as hidden, never as zero")

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
    check(abs(rail.dots[0] - WidgetRunway.pad) < 0.0001,
          "the earliest deadline sits at the pad, not at the very edge")
    check(abs(rail.dots[1] - (1 - WidgetRunway.pad)) < 0.0001,
          "and the latest at one pad in from the other end")
    check(WidgetRunway.pad > 0, "the padding is real")
} else { check(false, "a two-deadline rail should place") }
if let allLate = WidgetRunway.positions(for: [now.addingTimeInterval(-7200), hourAgo], now: now) {
    check(allLate.dots.allSatisfy { $0 < allLate.now },
          "when everything is overdue, now is the right-hand end — nothing draws ahead of it")
    check(allLate.now <= 1, "and the marker is still on the track")
} else { check(false, "an all-overdue rail should place") }
if let allAhead = WidgetRunway.positions(for: [inThree, now.addingTimeInterval(9 * 3600)], now: now) {
    check(allAhead.dots.allSatisfy { $0 > allAhead.now },
          "when nothing is late, now is the left-hand end")
} else { check(false, "an all-ahead rail should place") }
check(WidgetRunway.positions(for: [], now: now) == nil, "no deadlines, no rail")
check(WidgetRunway.positions(for: [now], now: now) == nil,
      "a zero-width window has no shape to draw — the rows say it instead")

// ── the Feed tile (§1881): each app's newest thing today ────────────────────
func item(_ id: String, _ source: String, _ minutes: Double) -> WidgetFeed.Row {
    WidgetFeed.Row(id: id, source: source, title: id, at: now.addingTimeInterval(-minutes * 60))
}
let today = [item("a1", "Bluesky", 5), item("a2", "Bluesky", 1), item("g1", "GitHub", 3),
             item("x1", "X", 10), item("r1", "RSS", 20), item("a3", "Bluesky", 30)]
let cut = WidgetFeedTile.rows(today)
eq(cut.rows.map(\.id), ["a2", "g1", "x1"], "one row per app, its NEWEST, newest first, three at most")
eq(cut.more, 3, "the rest of today is counted, every thing not drawn")
eq(WidgetFeedTile.rows([]).more, 0, "an empty day counts nothing")
eq(WidgetFeedTile.markFile("Apple Wallet"), "apple-wallet.png", "an app's icon file is a safe name")

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "UTC")!
let noon = Date(timeIntervalSince1970: 1_760_000_000)   // 2025-10-09 08:53 UTC
let feed = WidgetFeed(day: cal.startOfDay(for: noon), rows: cut.rows, more: cut.more)
check(feed.isCurrent(now: noon, calendar: cal), "the rows are today's on the day they were read")
check(!feed.isCurrent(now: noon.addingTimeInterval(24 * 3600), calendar: cal),
      "the next day they are not — yesterday's rows never draw as today's")
check(!feed.isCurrent(now: noon.addingTimeInterval(-24 * 3600), calendar: cal),
      "nor the day before")
_ = WidgetPayload.write(feed, key: WidgetFeedTile.key, stampKey: WidgetFeedTile.stampKey, defaults: d)
eq(WidgetFeedTile.published(defaults: d)?.rows.map(\.source) ?? [], ["Bluesky", "GitHub", "X"],
   "the rows survive the round trip")

// ── the Watchlist tile (§1881) ──────────────────────────────────────────────
eq(WidgetWatchlist.change(2.44).words, "+2.4%", "a rise carries a plus")
check(WidgetWatchlist.change(2.44).up == true, "and reads as up")
eq(WidgetWatchlist.change(-1.75).words, "\u{2212}1.8%", "a fall carries a minus")
check(WidgetWatchlist.change(-1.75).up == false, "and reads as down")
eq(WidgetWatchlist.change(0.04).words, "0.0%", "a move that rounds to zero has no sign (§83)")
check(WidgetWatchlist.change(0.04).up == nil, "and no direction")
let watch = WidgetWatch(rows: [.init(symbol: "ETH", dayPct: 2.4), .init(symbol: "SOL", dayPct: nil)])
_ = WidgetPayload.write(watch, key: WidgetWatchlist.key, stampKey: WidgetWatchlist.stampKey, defaults: d)
eq(WidgetWatchlist.published(defaults: d)?.rows.map(\.symbol) ?? [], ["ETH", "SOL"],
   "the watchlist survives the round trip, in its order")
check(WidgetWatchlist.published(defaults: d)?.rows[1].dayPct == nil, "an unread move stays unread, never zero")

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

# The Feed tile: one row per app, and the rest counted.
mutate "the Feed tile draws one app's things over and over" \
  WidgetPayload.swift \
  'for item in items where (newest[item.source]?.at ?? .distantPast) < item.at {
            newest[item.source] = item
        }|||for item in items { newest[item.id] = item }' || mfail=1
mutate "the Feed tile's count of the rest leaves out what one app held back" \
  WidgetPayload.swift \
  'return (rows, items.count - rows.count)|||return (rows, newest.count - rows.count)' || mfail=1
# The Watchlist tile.
mutate "a watchlist move that rounds to zero is given a sign (§83)" \
  WidgetPayload.swift \
  'guard tenths != 0, percent.isFinite else { return ("0.0%", nil) }|||guard percent.isFinite else { return ("0.0%", nil) }' || mfail=1
# Hide balances.
mutate "a withheld wallet reading still carries its total" \
  WidgetPayload.swift \
  'WidgetWalletHome(total: nil, dayPct: nil, publicUSD: nil, privateUSD: nil,|||WidgetWalletHome(total: 1, dayPct: nil, publicUSD: nil, privateUSD: nil,' || mfail=1

# The Feed tile's day.
mutate "the Feed tile's counts stay current past midnight" \
  WidgetPayload.swift \
  'calendar.isDate(day, inSameDayAs: now)|||true' || mfail=1

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
print "widget-selftest: OK — publish round trip, the freshness window, Hide balances, the Feed and Watchlist tiles, the rail and the money table all pinned."
