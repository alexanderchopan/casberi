#!/bin/zsh
# Casberi widget self-test — the contract between the app and its Home Screen
# (prd §382, 2026-08-14):
#
#   Casberi/Shared/WidgetPayload.swift
#     — WidgetPayload.write/read   (the publish round trip, and the reload budget)
#     — WidgetAsks.published       (a question is durable, a READING is not)
#     — WidgetDeadline.isOverdue   (decided at draw time, never published)
#     — WidgetWalletLine.normalizedPoints  (a flat curve draws down the MIDDLE)
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
#   • **A stale READING printed as a current one.** `KeptAskStore` refuses to
#     persist deltas at all ("restoring 'ETH is up 2.1%' from UserDefaults at
#     launch would put a stale number in the largest type on the screen"). A
#     widget has no choice but to persist them, so the freshness window is the
#     only thing standing between a tile and exactly that — and a window that
#     silently stops being applied looks identical to one that works.
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
KEPTW="Casberi/CasberiWidgets/KeptAskWidget.swift"
TODAYW="Casberi/CasberiWidgets/TodayWidget.swift"
ROOT="Casberi/Casberi/Shell/RootShell.swift"
COMMIT="Casberi/Casberi/Model/ImportCommit.swift"
PANEL="Casberi/Casberi/Model/AgentPanel.swift"
for f in "$PAYLOAD" "$MONEY" "$PUBLISH" "$BUNDLE" "$WALLETW" "$KEPTW" "$TODAYW" \
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
strip_comments "$KEPTW"   > "$TMP/keptw.nc"
strip_comments "$TODAYW"  > "$TMP/todayw.nc"
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

# Each widget must take its kind from the shared constant, never a literal.
# The app reloads BY KIND (`WidgetCenter.reloadTimelines(ofKind:)`), so a
# hardcoded string that drifts leaves the tile listening on a channel nobody
# writes — it keeps drawing, forever, whatever it last had. `WidgetLede.kind`
# already carries this note for the hero; these are the same rule.
grep -q 'kind: WidgetAsks.kind' "$TMP/keptw.nc" \
  || { print -u2 "✗ the kept-ask widget no longer uses WidgetAsks.kind — reloads would never reach it"; exit 1; }
grep -q 'kind: WidgetToday.kind' "$TMP/todayw.nc" \
  || { print -u2 "✗ the Today widget no longer uses WidgetToday.kind"; exit 1; }
# prd §877: Today KEEPS the hero's kind, so a "Your day" tile already on a Home
# Screen becomes Today instead of the system's "unable to load" placeholder.
grep -q 'static let kind = "casberi.hero"' "$PAYLOAD" \
  || { print -u2 "✗ WidgetToday.kind is no longer the hero's — every placed Your day tile would break"; exit 1; }
# Every payload the tile reads must reload the tile's OWN kind. Needs you's kind
# is not registered any more, so a reload aimed at it reaches nothing.
[[ "$(grep -c 'stale.append(WidgetToday.kind)' "$TMP/publish.nc")" -ge 4 ]] \
  || { print -u2 "✗ requests, people, deadlines and the Safe call must each reload WidgetToday.kind"; exit 1; }
# Lead pictures reach the tile only as files the APP writes; the widget reads
# them by key. A face fetched on a bare URLSession with no ledger entry is a
# host nothing discloses.
grep -q 'NetworkLedger.shared.record(host: host, as: service)' "Casberi/Casberi/Model/WidgetLeadImages.swift" \
  || { print -u2 "✗ the Today face fetch no longer names its host to the ledger"; exit 1; }
grep -q 'WidgetLeadImages.refresh(' "$TMP/publish.nc" \
  || { print -u2 "✗ nothing writes the Today tile's lead pictures — every row would be a monogram"; exit 1; }
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
grep -qE 'for kind in (Set\()?stale' "$TMP/publish.nc" \
  || { print -u2 "✗ publishAll no longer reloads only the changed kinds — it would spend the"; \
       print -u2 "  system's refresh budget rewriting identical bytes on every foreground."; exit 1; }

# §374, and the reason it is a WITHHOLD rather than a mask: a Home Screen is the
# most stood-next-to surface the OS has, and the threat §374 exists for is
# exactly somebody standing next to you.
grep -q 'hidden ? nil : last.usd' "$TMP/publish.nc" \
  || { print -u2 "✗ the wallet payload no longer withholds the total under Hide wallet balances (§374)"; exit 1; }
grep -q 'points: points' "$TMP/publish.nc" \
  || { print -u2 "✗ the wallet payload no longer publishes the curve — §374 rule 3 keeps the SHAPE"; exit 1; }

# The deadline scan must run its OWN fetch. Handed the foreground pass's
# newest-600-by-capture slice it would silently stop seeing exactly the rows
# that matter most: a grant expiry or an ENS name lands months before its date.
grep -q 'FetchDescriptor<Thing>' "$TMP/publish.nc" \
  || { print -u2 "✗ deadlines no longer run their own fetch — long-dated rows would drop out of view"; exit 1; }
grep -q 'thing.mark != .done' "$TMP/publish.nc" \
  || { print -u2 "✗ the deadline scan no longer excludes done rows"; exit 1; }

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
for w in TodayWidget WalletWidget ComposeControl; do
  grep -q "        $w()" "$TMP/bundle.nc" \
    || { print -u2 "✗ $w is not in the widget bundle — it would never appear in the gallery"; exit 1; }
done
# ...and the two the ask took with it must STAY out (prd §697b, 2026-09-11).
# `KeptAskWidget` was a gallery full of doors onto an ask that is deprecated,
# and `BriefControl` was the Control Center button onto the brief. Their files
# stay in the target and stay compiling, so listing either again is a one-line
# mistake with no compiler to catch it — which is what this guard is for.
for w in KeptAskWidget BriefControl; do
  grep -q "        $w()" "$TMP/bundle.nc" \
    && { print -u2 "✗ $w is back in the bundle — the ask is deprecated (prd §697b)"; exit 1; }
done

# The large family is the only one with room for all three sections.
grep -q '.systemLarge' "$TMP/todayw.nc" \
  || { print -u2 "✗ Today no longer offers the large family"; exit 1; }
# No ring on the circular lock-screen tile (user, 2026-09-22: "it's unnecessary
# and doesn't mean anything") — a count of open items is not a fraction.
grep -qE 'Gauge\(|accessoryCircularCapacity|stroke-dasharray' "$TMP/todayw.nc" \
  && { print -u2 "✗ the Today circular tile draws a gauge ring again"; exit 1; }

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
let cells = [WidgetAskCell(kind: "wallet", title: "What's my wallet doing?",
                           reading: "$12.5K · +2.1%", changed: true),
             WidgetAskCell(kind: "overdue", title: "What's overdue?",
                           reading: "3 things late", changed: false)]
check(WidgetPayload.write(cells, key: "k", stampKey: "kAt", defaults: d),
      "a first publish reports a change")
let back = WidgetPayload.read([WidgetAskCell].self, key: "k", stampKey: "kAt",
                              freshness: 3600, defaults: d)
eq(back?.count, 2, "the payload round-trips")
eq(back?[0].reading, "$12.5K · +2.1%", "a reading survives the round trip")
eq(back?[0].changed, true, "the changed flag survives the round trip")

// THE RELOAD BUDGET. Publishing identical bytes must report no change.
check(!WidgetPayload.write(cells, key: "k", stampKey: "kAt", defaults: d),
      "republishing identical bytes reports NO change")
// ...and the stamp must move anyway, or a payload republished unchanged would
// age out while the app is being used every day.
let stampAfter = d.double(forKey: "kAt")
check(stampAfter > 0, "the stamp is written even when the bytes did not change")

var changed = cells
changed[0] = WidgetAskCell(kind: "wallet", title: "What's my wallet doing?",
                           reading: "$12.6K · +2.4%", changed: true)
check(WidgetPayload.write(changed, key: "k", stampKey: "kAt", defaults: d),
      "a different reading reports a change")

// Clearing.
check(WidgetPayload.write(Optional<[WidgetAskCell]>.none, key: "k", stampKey: "kAt", defaults: d),
      "clearing a published payload reports a change")
check(!WidgetPayload.write(Optional<[WidgetAskCell]>.none, key: "k", stampKey: "kAt", defaults: d),
      "clearing an already-empty payload reports NO change")
check(WidgetPayload.read([WidgetAskCell].self, key: "k", stampKey: "kAt",
                         freshness: 3600, defaults: d) == nil,
      "a cleared payload reads as nothing")

// ── freshness ───────────────────────────────────────────────────────────────
_ = WidgetPayload.write(cells, key: "f", stampKey: "fAt", defaults: d)
let now = Date()
check(WidgetPayload.read([WidgetAskCell].self, key: "f", stampKey: "fAt",
                         freshness: 3600, now: now, defaults: d) != nil,
      "a fresh payload reads")
check(WidgetPayload.read([WidgetAskCell].self, key: "f", stampKey: "fAt",
                         freshness: 3600, now: now.addingTimeInterval(7200),
                         defaults: d) == nil,
      "a payload past its freshness window reads as nothing")
// A payload with NO stamp at all must not read — the pre-stamp legacy case,
// and the shape a partial write would leave behind.
d.set(d.data(forKey: "f"), forKey: "nostamp")
check(WidgetPayload.read([WidgetAskCell].self, key: "nostamp", stampKey: "missingAt",
                         freshness: 3600, defaults: d) == nil,
      "an unstamped payload reads as nothing")

// ── a question is durable, a READING is not ─────────────────────────────────
// The rule this whole contract exists for. Past `readingWindow` the questions
// stand and the numbers go; past `freshness` the questions go too.
_ = WidgetPayload.write(cells, key: WidgetAsks.key, stampKey: WidgetAsks.stampKey, defaults: d)
let fresh = WidgetAsks.published(now: now, defaults: d)
eq(fresh.count, 2, "fresh asks publish whole")
eq(fresh[0].reading, "$12.5K · +2.1%", "a fresh ask keeps its reading")

let aged = WidgetAsks.published(now: now.addingTimeInterval(WidgetAsks.readingWindow + 60),
                                defaults: d)
eq(aged.count, 2, "an aged ask KEEPS its question")
check(aged.first?.reading == nil, "an aged ask DROPS its reading")
check(aged.first?.changed == false,
      "an aged ask drops its changed dot too — a dot claiming 'this moved' is a reading")
eq(aged[1].title, "What's overdue?", "the aged questions keep their own titles, in order")

let expired = WidgetAsks.published(now: now.addingTimeInterval(WidgetAsks.freshness + 60),
                                   defaults: d)
check(expired.isEmpty, "past the outer freshness window even the questions go")
check(WidgetAsks.readingWindow < WidgetAsks.freshness,
      "the reading window is SHORTER than the payload's — otherwise stripping never happens")

// ── deadlines ───────────────────────────────────────────────────────────────
// Decided at draw time. A published boolean would be a claim about a `now` that
// has already passed by the time anyone sees the tile.
let due = WidgetDeadline(id: "a", title: "Respond to dispute", source: "Stripe",
                         due: now.addingTimeInterval(3600))
let late = WidgetDeadline(id: "b", title: "Renew name", source: "Wallet",
                          due: now.addingTimeInterval(-3600))
check(!due.isOverdue(now: now), "a future deadline is not overdue")
check(late.isOverdue(now: now), "a past deadline is overdue")
check(due.isOverdue(now: now.addingTimeInterval(7200)),
      "the SAME entry reads as overdue once its moment passes — no republish needed")

_ = WidgetPayload.write([due, late], key: WidgetDeadlines.key,
                        stampKey: WidgetDeadlines.stampKey, defaults: d)
eq(WidgetDeadlines.published(now: now, defaults: d).count, 2, "deadlines round-trip with their dates")
eq(WidgetDeadlines.published(now: now, defaults: d).first?.id, "a",
   "a deadline carries the id its row opens")

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

// ── Today (prd §877) ────────────────────────────────────────────────────────
// One list: what needs you, then who answered you, then what landed.
let dLate = WidgetDeadline(id: "late", title: "Dispute evidence", source: "Stripe",
                           due: now.addingTimeInterval(-2 * 3600))
let dSoon = WidgetDeadline(id: "soon", title: "Launch review", source: "Linear",
                           due: now.addingTimeInterval(30 * 3600))
let dFar = WidgetDeadline(id: "far", title: "casberi.eth renews", source: "Wallet",
                          due: now.addingTimeInterval(12 * 86_400))
let tSign = WidgetSafeCall(id: "safe", subject: "move 2 ETH to ops", awaitsYou: 1, ready: 0,
                          waitingDays: 2)
let ask = WidgetRequest(id: "req", title: "Review: Feed seam", source: "GitHub",
                        askedAt: now.addingTimeInterval(-3600))
let oldAsk = WidgetRequest(id: "old", title: "Review: tStale", source: "GitHub",
                           askedAt: now.addingTimeInterval(-8 * 86_400))
let r1 = WidgetReply(id: "r1", who: "ana", words: "where's the data from?", source: "Farcaster",
                     at: now.addingTimeInterval(-600), face: "face-a")
let r2 = WidgetReply(id: "r2", who: "mia", words: "saving this", source: "Bluesky",
                     at: now.addingTimeInterval(-3000), face: nil)
let crowd = WidgetPeople(replies: [r2, r1], likes: nil)
let things = (0..<6).map { i in
    WidgetLanded(id: "t\(i)", title: "thing \(i)", source: "Gmail",
                 at: now.addingTimeInterval(Double(-i * 900)), face: nil)
}

let tFull = WidgetTodayPlan.make(deadlines: [dSoon, dLate, dFar], safe: tSign, requests: [ask],
                                people: crowd, landed: things, capacity: 8, now: now)
eq(tFull.rows.map(\.id), ["late", "safe", "req", "soon", "r1", "r2", "t0", "t1"],
   "late, then the signature, then a request, then what is coming; then replies newest first; then landed")
check(tFull.next == nil, "a tile with something due this week names no 'Next'")
eq(tFull.late, 1, "one late")
eq(tFull.toSign, 1, "the Safe count is what waits on you — a request is not counted, it may be answered")
eq(tFull.faces, ["face-a"], "only replies WITH a face join the pile, newest first")
eq(tFull.repliers, ["ana", "mia"], "every replier is named, newest first")
if case .mark(let source) = tFull.rows[5].lead { eq(source, "Bluesky", "a face-less reply leads with its network's mark") }
else { check(false, "a face-less reply leads with its network's mark") }

// Half the tile is held for the other sections when they have something.
let medium = WidgetTodayPlan.make(deadlines: [dSoon, dLate], safe: tSign, requests: [ask],
                                  people: crowd, landed: things, capacity: 4, now: now)
eq(medium.rows.map(\.id), ["late", "safe", "r1", "r2"],
   "a medium tile keeps two rows for the people who answered you")
let onlyNeeds = WidgetTodayPlan.make(deadlines: [dSoon, dLate], safe: tSign, requests: [ask],
                                     people: WidgetPeople(replies: [], likes: nil), landed: [],
                                     capacity: 4, now: now)
eq(onlyNeeds.rows.count, 4, "with nothing else to show, what needs you takes the whole tile")

// A quiet day: nothing inside the week, so the next deadline is named on its
// own line, which takes one row.
let quiet = WidgetTodayPlan.make(deadlines: [dFar], safe: nil, requests: [oldAsk],
                                 people: crowd, landed: things, capacity: 4, now: now)
eq(quiet.next?.id, "far", "a quiet tile names the next deadline past the week")
eq(quiet.rows.count, 3, "…and that line takes one of the four rows")
check(!quiet.rows.contains { $0.id == "old" }, "a request older than a week is not drawn")
check(!quiet.rows.contains { $0.id == "far" }, "a deadline past the week is not a row")

// A Safe with nothing awaiting you is no row; a thing already shown as a reply
// is not shown again as landed.
let calm = WidgetTodayPlan.make(
    deadlines: [], safe: WidgetSafeCall(id: "s", subject: "x", awaitsYou: 0, ready: 1, waitingDays: nil),
    requests: [], people: crowd,
    landed: [WidgetLanded(id: "r1", title: "dup", source: "Farcaster", at: now, face: nil)] + things,
    capacity: 8, now: now)
check(!calm.rows.contains { $0.id == "s" }, "a Safe that waits on nobody draws no row")
eq(calm.rows.filter { $0.id == "r1" }.count, 1, "a reply is not repeated as a landed row")
check(WidgetTodayPlan.make(deadlines: [], safe: nil, requests: [], people: WidgetPeople(replies: [], likes: nil),
                           landed: [], capacity: 4, now: now).isEmpty, "nothing at all is an empty plan")

// The readers apply each row's own window at DRAW time.
_ = WidgetPayload.write([ask, oldAsk], key: WidgetToday.requestsKey,
                        stampKey: WidgetToday.requestsStampKey, defaults: d)
eq(WidgetToday.requests(now: now, defaults: d).map(\.id), ["req"],
   "the request reader drops one asked more than a week ago")
let tStale = WidgetReply(id: "r0", who: "old", words: "yesterday", source: "X",
                        at: now.addingTimeInterval(-26 * 3600), face: nil)
_ = WidgetPayload.write(WidgetPeople(replies: [r1, tStale],
                                     likes: WidgetLikes(line: "Liked by @mia", source: "Bluesky",
                                                        at: now.addingTimeInterval(-30 * 3600), id: nil)),
                        key: WidgetToday.peopleKey, stampKey: WidgetToday.peopleStampKey, defaults: d)
let readBack = WidgetToday.people(now: now, defaults: d)
eq(readBack.replies.map(\.id), ["r1"], "a reply older than a day is not news")
check(readBack.likes == nil, "…and neither is a like roll")

// The clock's span.
eq(WidgetSpan(20).minutes, 1, "under a minute reads as one minute, never zero")
eq(WidgetSpan(59 * 60).minutes, 59, "minutes under an hour")
eq(WidgetSpan(2 * 3600 + 50 * 60).hours, 2, "hours under a day")
eq([WidgetSpan(30 * 3600).days, WidgetSpan(30 * 3600).hours], [1, 6], "a day and hours while they matter")
eq(WidgetSpan(4 * 86_400 + 5 * 3600).hours, 0, "past three days the hours go")

// The picture keys must be the same in both processes: FNV-1a, never hashValue.
eq(WidgetImages.fnv(""), "cbf29ce484222325", "FNV-1a's offset basis for the empty string")
eq(WidgetImages.fnv("a"), "af63dc4c8601ec8c", "FNV-1a's published vector for \"a\"")
check(WidgetImages.markKey(source: "GitHub") != WidgetImages.faceKey(url: "GitHub"),
      "a mark and a face never share a file")

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

// ── the ask link ────────────────────────────────────────────────────────────
// A kept ask's title is whatever the person typed, and `CharacterSet
// .urlQueryAllowed` PERMITS `&` — legal in a query string, fatal inside a query
// ITEM, which is what the other end parses. The obvious spelling truncates the
// question at the ampersand and the tile silently asks something else.
func askedQuestion(_ title: String) -> String? {
    guard let url = WidgetAskLink.url(asking: title) else { return nil }
    return URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?.first { $0.name == "q" }?.value
}
eq(askedQuestion("What's new with M&S?"), "What's new with M&S?",
   "a question containing & survives the round trip WHOLE")
eq(askedQuestion("a + b = c?"), "a + b = c?",
   "so do +, = and ? — every sub-delimiter urlQueryAllowed lets through")
eq(askedQuestion("what's coming up"), "what's coming up",
   "an ordinary question is unharmed")
eq(askedQuestion("Recipes & 30% off?"), "Recipes & 30% off?",
   "a percent sign is not mistaken for an escape")
check(WidgetAskLink.url(asking: "   ") == nil,
      "a blank question mints no link at all — the far side returns early on it anyway")
check(WidgetAskLink.url(asking: "")?.absoluteString == nil, "…and neither does an empty one")

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
mutate "an aged reading is kept — a stale number in the largest type on the tile" \
  WidgetPayload.swift \
  'guard now.timeIntervalSince1970 - stamp < readingWindow else {|||if false {' || mfail=1
mutate "an aged ask keeps its changed dot — a dot claiming something moved is a reading too" \
  WidgetPayload.swift \
  'reading: nil, changed: false)|||reading: nil, changed: $0.changed)' || mfail=1
mutate "the reading window is as long as the payload's — stripping never happens" \
  WidgetPayload.swift \
  'static let readingWindow: TimeInterval = 6 * 3600|||static let readingWindow: TimeInterval = 7 * 24 * 3600' || mfail=1

# Draw-time facts.
mutate "isOverdue is frozen to the publish moment instead of read at draw time" \
  WidgetPayload.swift \
  'func isOverdue(now: Date = .now) -> Bool { due < now }|||func isOverdue(now: Date = .now) -> Bool { false }' || mfail=1

# Today (prd §877).
mutate "a signature outranks something already late" \
  WidgetPayload.swift \
  'var needs: [WidgetTodayRow] = overdue.map(deadlineRow)
        if let signing {|||var needs: [WidgetTodayRow] = []
        if let signing {' || mfail=1
mutate "what needs you takes the whole tile even when people answered you" \
  WidgetPayload.swift \
  'let held = min(others, room / 2)|||let held = 0' || mfail=1
mutate "the Next line is drawn even when something is due this week" \
  WidgetPayload.swift \
  'let next = needs.isEmpty ? byDue.first|||let next = true ? byDue.first' || mfail=1
mutate "a request older than a week still draws" \
  WidgetPayload.swift \
  'let asks = requests.filter { now.timeIntervalSince($0.askedAt) < WidgetToday.requestWindow }|||let asks = requests.filter { _ in true }' || mfail=1
mutate "a reply is drawn again as a landed row" \
  WidgetPayload.swift \
  '.filter { !shown.contains($0.id) }|||.filter { _ in true }' || mfail=1
mutate "requests are counted as waiting on you" \
  WidgetPayload.swift \
  'toSign: signing?.awaitsYou ?? 0,|||toSign: (signing?.awaitsYou ?? 0) + asks.count,' || mfail=1
mutate "the people reader keeps yesterday's replies" \
  WidgetPayload.swift \
  'let fresh = { (at: Date) in now.timeIntervalSince(at) < peopleWindow }|||let fresh = { (at: Date) in true }' || mfail=1
mutate "a span under a minute reads as zero" \
  WidgetPayload.swift \
  'days = 0; hours = 0; minutes = max(1, s / 60)|||days = 0; hours = 0; minutes = s / 60' || mfail=1
mutate "the hours ride beside the days forever" \
  WidgetPayload.swift \
  'hours = days < 3 ? (s % 86_400) / 3600 : 0|||hours = (s % 86_400) / 3600' || mfail=1
mutate "the picture key uses a different hash — the app and the widget name one file two ways" \
  WidgetPayload.swift \
  'hash = hash &* 0x0000_0100_0000_01b3|||hash = hash &* 0x0000_0100_0000_01b5' || mfail=1

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

# The ask link. THE SECOND BUG THIS HARNESS CAUGHT (2026-08-14): the shipped
# first cut used `.urlQueryAllowed` unmodified, so "What's new with M&S?"
# reached the app as "What's new with M".
mutate "the ask link uses urlQueryAllowed unmodified — a question with & is truncated" \
  WidgetPayload.swift \
  'set.remove(charactersIn: "&+=?")|||' || mfail=1

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
print "widget-selftest: OK — publish round trip, both freshness windows, the flat curve and the money table all pinned."
