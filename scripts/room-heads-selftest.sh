#!/bin/zsh
# Casberi room-head self-test — the SHIPPED pure judgement behind the Stripe and
# PostHog feed-room heads (prd §298, 2026-08-04):
#
#   Casberi/Casberi/Model/StripeRoom.swift
#   Casberi/Casberi/Model/PostHogRoom.swift
#
# Both are Foundation-only BY DESIGN, so both are compiled WHOLE AND UNMODIFIED
# rather than extracted — the strongest form of "the harness ran the shipped
# logic". Everything that touches `Thing` or UserDefaults lives in the
# `…RoomSource.swift` half, which no harness can compile and which contains no
# judgement to test.
#
# WHY A HARNESS AND NOT A LIVE CHECK. Neither bridge has ever been measured
# against a live account (no Stripe key is stored; no PostHog project is
# reachable from this host), and every failure mode in these two files is a
# SILENT WRONG ANSWER that renders perfectly:
#
#   · a dispute due tomorrow placed at the far end of the rail
#   · an overdue evidence window sorted last, or off the left edge entirely
#   · a headline claiming "3 days" for a deadline that passed yesterday
#   · a balance snapshot hours old presented with no staleness clause
#   · a metric that STOPPED firing ranked below a busy one — the one ordering
#     §223 says is the whole value of watching a metric at all
#   · a week-over-week change divided by a zero prior week
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

STRIPE="Casberi/Casberi/Model/StripeRoom.swift"
# The runway arithmetic StripeRoom now forwards to.
SHARED_RUNWAY="Casberi/Casberi/Model/RoomRunway.swift"
POSTHOG="Casberi/Casberi/Model/PostHogRoom.swift"
QUIET="Casberi/Casberi/Model/RoomQuiet.swift"
for f in "$STRIPE" "$POSTHOG" "$QUIET"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards -----------------------------------------------------------
# Wiring facts the compiled functions cannot prove about themselves. A perfect
# `ranked` is worthless if the card draws its own order, and a perfect
# `position` is worthless if the source never filters the window.
SRC_STRIPE="Casberi/Casberi/Model/StripeRoomSource.swift"
SRC_POSTHOG="Casberi/Casberi/Model/PostHogRoomSource.swift"
CARD_STRIPE="Casberi/Casberi/Screens/StripeRoomCard.swift"
CARD_POSTHOG="Casberi/Casberi/Screens/PostHogRoomCard.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
PROBES="Casberi/Casberi/Shell/ProbeHooks.swift"

grep -q 'items.sort { $0.days < $1.days }' "$SRC_STRIPE" \
  || { echo "✗ Stripe deadlines no longer sort soonest-first — the rail and the rows would disagree about the lead"; exit 1; }
grep -q 'things.live' "$SRC_STRIPE" \
  || { echo "✗ StripeRoomSource no longer filters live at the boundary (corollary 4)"; exit 1; }
grep -q 'things.live' "$SRC_POSTHOG" \
  || { echo "✗ PostHogRoomSource no longer filters live at the boundary (corollary 4)"; exit 1; }
grep -q 'guard reading.fetchedAt != nil else { unread += 1; continue }' "$SRC_POSTHOG" \
  || { echo "✗ an unread metric is no longer counted separately — a fresh install would draw empty discs as data"; exit 1; }
grep -q 'PostHogRoom.ranked(metrics)' "$SRC_POSTHOG" \
  || { echo "✗ PostHog metrics are no longer ranked — a silent metric would sort by volume it no longer has"; exit 1; }
grep -q 'room.metrics.prefix(PostHogRoomSource.discCap)' "$CARD_POSTHOG" \
  || { echo "✗ the PostHog card no longer honours the disc cap"; exit 1; }
grep -q 'StripeRoom.position(days: item.days, span: span)' "$CARD_STRIPE" \
  || { echo "✗ the Stripe rail no longer places marks through the shipped position()"; exit 1; }
grep -q 'case .stripe(let room)' "$FEED" \
  || { echo "✗ the Stripe head is no longer rendered from the sourceHead chain"; exit 1; }
grep -q 'case .posthog(let room)' "$FEED" \
  || { echo "✗ the PostHog head is no longer rendered from the sourceHead chain"; exit 1; }
# The §219 failure inverted — see the probe's own comment.
grep -q 'note("stripeHead"' "$PROBES" \
  || { echo "✗ -roomInsightProbe no longer mirrors the Stripe head; it would report 'leads with NOTHING'"; exit 1; }
grep -q 'note("posthogHead"' "$PROBES" \
  || { echo "✗ -roomInsightProbe no longer mirrors the PostHog head; it would report 'leads with NOTHING'"; exit 1; }
# RoomQuiet.Seat MIRRORS BridgeApp.Status (which lives in a SwiftUI file and so
# can't be compiled here). A status added there without a case here would fall
# into `.none` and silently restore the generic "connect an app" copy for the
# very state that needed explaining.
STORE="Casberi/Casberi/Model/BridgeStore.swift"
grep -q 'case connected, attention, paused' "$STORE" \
  || { echo "✗ BridgeApp.Status changed — RoomQuiet.Seat no longer mirrors it"; exit 1; }
grep -q 'case .attention: .attention' "$FEED" \
  || { echo "✗ the feed no longer maps a broken bridge onto RoomQuiet.attention — a failed connection would read as an invitation to connect"; exit 1; }
grep -q 'private var invitationState' "$FEED" \
  || { echo "✗ the generic invitation state is gone — All would have nothing to say"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

let cal = Calendar.current
let t0 = cal.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000))
func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: t0)! }

func item(_ name: String, days: Int, dispute: Bool = true) -> StripeRoom.Item {
    StripeRoom.Item(id: name, name: name, due: day(days), days: days, dispute: dispute)
}
func room(available: String? = "£2,140.00", pending: String? = nil,
          arrivesAt: Date? = nil, asOf: Date? = t0,
          items: [StripeRoom.Item] = [], total: Int? = nil,
          stopped: Bool = false) -> StripeRoom {
    StripeRoom(available: available, pending: pending, arrivesAt: arrivesAt,
               asOf: asOf, items: items, total: total ?? items.count, stopped: stopped)
}

print("Stripe — days")
check("a deadline later today is zero days out", StripeRoom.days(from: t0, to: t0.addingTimeInterval(3600)) == 0)
// The whole reason this is calendar days and not interval/86400: an 11pm read
// the night before a deadline is ONE day out, not zero-point-oh-four.
check("11pm the night before is one day out, not a fraction",
      StripeRoom.days(from: t0.addingTimeInterval(23 * 3600), to: day(1)) == 1)
check("yesterday is negative", StripeRoom.days(from: t0, to: day(-1)) == -1)
check("a week out is seven", StripeRoom.days(from: t0, to: day(7)) == 7)

print("")
print("Stripe — the rail")
check("a span floors at a week", StripeRoom.span(days: [1, 2]) == 7)
check("a span steps to the next familiar horizon", StripeRoom.span(days: [9]) == 14)
check("a month spans thirty", StripeRoom.span(days: [21]) == 30)
check("beyond ninety it uses the real furthest", StripeRoom.span(days: [200]) == 200)
check("an empty set still spans a week", StripeRoom.span(days: []) == 7)
check("today sits at the start", StripeRoom.position(days: 0, span: 30) == 0)
check("the far end sits at one", StripeRoom.position(days: 30, span: 30) == 1)
check("halfway is halfway", abs(StripeRoom.position(days: 15, span: 30) - 0.5) < 0.0001)
// Overdue pins rather than running off the left edge, where the one deadline
// you most need to see would simply vanish.
check("an overdue deadline pins to the start", StripeRoom.position(days: -9, span: 30) == 0)
check("a deadline past the span clamps to the end", StripeRoom.position(days: 99, span: 30) == 1)
check("a zero span can't divide by zero", StripeRoom.position(days: 5, span: 0) == 0)
check("a span label reads in months where it divides", StripeRoom.spanLabel(span: 60) == "2 mo")
check("a span label reads in days otherwise", StripeRoom.spanLabel(span: 14) == "14 days")

print("")
print("Stripe — words")
check("overdue says so", StripeRoom.value(days: -3) == "overdue")
check("today is named", StripeRoom.value(days: 0) == "today")
check("tomorrow is named", StripeRoom.value(days: 1) == "tomorrow")
check("further out counts days", StripeRoom.value(days: 5) == "5 days")
check("only a dispute wears a chip", StripeRoom.chip(item("a", days: 3)) != nil)
check("a retry needs nothing from you and wears none",
      StripeRoom.chip(item("a", days: 3, dispute: false)) == nil)
// Sentence case since 2026-08-22 (prd §453) — §8 has no ALL-CAPS anything,
// and this chip was one of 29 labels that had drifted into caps. Pinned here
// so the shout cannot come back through the one room head that carries it;
// `allcaps-audit.py` holds the rest of the tree.
check("a missed dispute says Missed", StripeRoom.chip(item("a", days: -1)) == "Missed")
check("an upcoming dispute says Needs you", StripeRoom.chip(item("a", days: 2)) == "Needs you")
check("a retry explains itself as automatic",
      StripeRoom.kindLine(item("a", days: 2, dispute: false)).contains("retries"))

print("")
print("Stripe — the headline ranking")
// The ranking IS the judgement: overdue money first, then a stopped business,
// then upcoming deadlines, then the everyday balance.
check("an overdue window outranks everything",
      StripeRoom.headline(room(items: [item("a", days: -2)], stopped: true))
        == "Evidence was due 2 days ago")
check("one day overdue reads as yesterday",
      StripeRoom.headline(room(items: [item("a", days: -1)])) == "Evidence was due yesterday")
check("a stopped account outranks an upcoming deadline",
      StripeRoom.headline(room(items: [item("a", days: 4)], stopped: true))
        == "Payments have stopped")
check("a lone dispute names its window",
      StripeRoom.headline(room(items: [item("a", days: 4)])) == "Evidence due 4 days")
check("a lone retry says what it is",
      StripeRoom.headline(room(items: [item("a", days: 4, dispute: false)]))
        == "A payment retries 4 days")
check("several deadlines are counted",
      StripeRoom.headline(room(items: [item("a", days: 1), item("b", days: 4)]))
        == "2 deadlines ahead")
check("with nothing due, money leads",
      StripeRoom.headline(room()) == "£2,140.00 available")
check("with nothing read at all, the quiet card still says something",
      StripeRoom.headline(room(available: nil, asOf: nil)) == "Nothing needs you")

print("")
print("Stripe — the note never repeats the headline")
check("when a deadline leads, the note carries the money",
      StripeRoom.note(room(items: [item("a", days: 4)])) == "£2,140.00 available")
// Unread is not zero, and must never render as a number.
check("an unread balance says so rather than showing zero",
      StripeRoom.note(room(available: nil, asOf: nil, items: [item("a", days: 4)]))
        == "Balance not read yet")
check("when money leads, the note carries what's still moving",
      StripeRoom.note(room(pending: "$310.00")) == "$310.00 pending")
check("a quiet account with nothing pending says nothing needs you",
      StripeRoom.note(room()) == "Nothing needs you")

print("")
print("Stripe — staleness")
check("a fresh balance needs no apology", StripeRoom.staleNote(asOf: t0, now: t0.addingTimeInterval(600)) == nil)
check("just under an hour is still fresh",
      StripeRoom.staleNote(asOf: t0, now: t0.addingTimeInterval(3599)) == nil)
check("hours are stated", StripeRoom.staleNote(asOf: t0, now: t0.addingTimeInterval(3 * 3600)) == "Balance as of 3h ago")
check("a day is named as yesterday",
      StripeRoom.staleNote(asOf: t0, now: t0.addingTimeInterval(30 * 3600)) == "Balance as of yesterday")
check("older is counted in days",
      StripeRoom.staleNote(asOf: t0, now: t0.addingTimeInterval(72 * 3600)) == "Balance as of 3 days ago")
check("no snapshot, no claim", StripeRoom.staleNote(asOf: nil, now: t0) == nil)

print("")
print("Stripe — emptiness and coverage")
check("nothing read, nothing due, no outage = no card",
      room(available: nil, asOf: nil).isEmpty)
check("an outage alone earns a card",
      !room(available: nil, asOf: nil, stopped: true).isEmpty)
check("a deadline alone earns a card",
      !room(available: nil, asOf: nil, items: [item("a", days: 2)]).isEmpty)
check("money alone earns a card", !room().isEmpty)
// A swept account really does hold zero available, and availableText() filters
// zero buckets to nil — so read-and-zero must not read as never-read.
check("a read balance of zero still earns a card", !room(available: nil).isEmpty)
check("a read zero balance is stated as a fact, not an apology",
      StripeRoom.headline(room(available: nil)) == "Nothing available right now")
check("a read zero balance with a deadline doesn't apologise either",
      StripeRoom.note(room(available: nil, pending: "$1,200.00", items: [item("a", days: 1)]))
        == "$1,200.00 pending")
check("an UNREAD balance does apologise",
      StripeRoom.note(room(available: nil, asOf: nil, items: [item("a", days: 1)]))
        == "Balance not read yet")
check("a full set of drawn rows says nothing",
      StripeRoom.coverageNote(room(items: [item("a", days: 1)])) == nil)
check("undrawn deadlines are counted, never swallowed",
      StripeRoom.coverageNote(room(items: [item("a", days: 1)], total: 4))
        == "3 more further out — not drawn")
// The headline counts the WINDOW, not the drawn rows — a card saying
// "4 deadlines ahead" over "5 more further out" disagrees with itself.
check("the headline counts every deadline in the window, not just the drawn ones",
      StripeRoom.headline(room(items: [item("a", days: 1), item("b", days: 2),
                                       item("c", days: 3), item("d", days: 4)], total: 9))
        == "9 deadlines ahead")

print("")
print("PostHog — the ordering, which is the whole judgement")
func metric(_ name: String, _ series: [Int], total: Int = 500, silent: Bool = false) -> PostHogRoom.Metric {
    PostHogRoom.Metric(event: name, series: series, total: total,
                       change: PostHogRoom.change(series), silent: silent)
}
let busy = metric("signed_up", Array(repeating: 40, count: 14))
let quiet = metric("checkout", Array(repeating: 1, count: 14))
let stopped = metric("deploy", Array(repeating: 0, count: 14), silent: true)
// A metric that STOPPED is the finding, and it is exactly the one a volume
// sort buries — it has no volume left.
check("a silent metric leads a busy one",
      PostHogRoom.ranked([busy, stopped]).first?.event == "deploy")
check("otherwise the busiest week leads",
      PostHogRoom.ranked([quiet, busy]).first?.event == "signed_up")
check("ties fall back to the name so the roster can't reshuffle",
      PostHogRoom.ranked([metric("b", [1]), metric("a", [1])]).map(\.event) == ["a", "b"])
check("this week is the last seven days only",
      PostHogRoom.week([100, 100, 1, 1, 1, 1, 1, 1, 1]) == 7)

print("")
print("PostHog — the change may only be claimed when knowable")
check("under a fortnight there is no claim", PostHogRoom.change(Array(repeating: 5, count: 13)) == nil)
check("a zero prior week is not an infinite rise",
      PostHogRoom.change([0, 0, 0, 0, 0, 0, 0, 5, 5, 5, 5, 5, 5, 5]) == nil)
check("a real doubling reads as one",
      PostHogRoom.change([1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2]).map { abs($0 - 1) < 0.0001 } == true)
check("a real halving reads negative",
      (PostHogRoom.change([2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1]) ?? 0) < 0)

print("")
print("PostHog — words")
let oneSilent = PostHogRoom(metrics: [stopped, busy], unread: 0)
check("one silent metric is named",
      PostHogRoom.headline(oneSilent) == "deploy has stopped firing")
check("several silent metrics are counted",
      PostHogRoom.headline(PostHogRoom(metrics: [stopped, metric("x", [0], silent: true)], unread: 0))
        == "2 metrics have stopped firing")
check("a single healthy metric is named",
      PostHogRoom.headline(PostHogRoom(metrics: [busy], unread: 0)) == "Watching signed_up")
check("several healthy metrics are counted",
      PostHogRoom.headline(PostHogRoom(metrics: [busy, quiet], unread: 0)) == "Watching 2 metrics")
// Never read is not never happened.
check("a device that has read nothing says so",
      PostHogRoom.note(PostHogRoom(metrics: [metric("a", [], total: 0)], unread: 2),
                       nextRung: { _ in 100 }) == "Not read on this device yet")
check("a metric at zero doesn't claim progress",
      PostHogRoom.note(PostHogRoom(metrics: [metric("a", [0], total: 0)], unread: 0),
                       nextRung: { _ in 100 }) == "Nothing counted yet")
check("the leading metric states its next rung",
      PostHogRoom.note(PostHogRoom(metrics: [busy], unread: 0), nextRung: { _ in 1000 })
        == "signed_up is at 500 of 1K")
check("compact drops a trailing zero", PostHogRoom.compact(1000) == "1K")
check("compact keeps a real decimal", PostHogRoom.compact(1200) == "1.2K")
check("compact reaches millions", PostHogRoom.compact(2_000_000) == "2M")
check("small numbers stay plain", PostHogRoom.compact(940) == "940")
check("a full roster says nothing", PostHogRoom.coverageNote(shown: 3, total: 3, unread: 0) == nil)
check("undrawn and unread are named separately",
      PostHogRoom.coverageNote(shown: 4, total: 6, unread: 2) == "2 more watched · 2 not read yet")

print("")
print("RoomQuiet — what an empty room says")
// The case the old copy actively hid: a refused token rendering as a cheerful
// invitation to connect the thing that is already connected and broken.
let broken = RoomQuiet.words(source: "Trello", seat: .attention,
                             statusLine: "Token refused", emptyRead: nil)
check("a broken bridge says it needs attention", broken?.headline == "Trello needs attention.")
check("a broken bridge shows the real status line", broken?.detail == "Token refused")
check("a broken bridge offers a door to fix it", broken?.offersDoor == true)
check("a broken bridge with no status line still explains itself",
      RoomQuiet.words(source: "Trello", seat: .attention, statusLine: "", emptyRead: nil)?
        .detail.contains("what went wrong") == true)

let connected = RoomQuiet.words(source: "Bluesky", seat: .connected,
                                statusLine: "Synced 5m ago", emptyRead: nil)
check("a connected room says it is connected", connected?.headline == "Bluesky is connected.")
// The whole point: never invite someone to connect what they already connected.
check("a connected room offers NO connect door", connected?.offersDoor == false)
check("a connected room explains the emptiness",
      connected?.detail.contains("syncs on its own") == true)

// §291's ruling generalised: a bridge that knows WHY empty is legitimate says
// so, and beats anything generic.
check("a bridge's own empty-read note wins",
      RoomQuiet.words(source: "Trello", seat: .connected, statusLine: "Up to date",
                      emptyRead: "Trello answered — no cards are assigned to you.")?
        .detail == "Trello answered — no cards are assigned to you.")

check("a paused room names the state you chose",
      RoomQuiet.words(source: "Photos", seat: .paused, statusLine: "Paused", emptyRead: nil)?
        .headline == "Photos is paused.")
// All, and any room with no seat, keeps the original invitation.
check("a room with no seat keeps the generic invitation",
      RoomQuiet.words(source: "All", seat: .none, statusLine: "", emptyRead: nil) == nil)

print("")
if failures > 0 { print("room-heads-selftest: ✗ \(failures) assertion(s) failed"); exit(1) }
print("room-heads-selftest: OK — every assertion passed against the shipped source.")
SWIFT

build() {
  swiftc -O -o "$TMP/rh-selftest" "$1" "$2" "$3" "$SHARED_RUNWAY" "$TMP/main.swift" 2>"$TMP/build.log"
}

if ! build "$STRIPE" "$POSTHOG" "$QUIET"; then
  echo "✗ harness failed to compile against the shipped source"
  grep -E 'error:' "$TMP/build.log" | head -20
  exit 1
fi
"$TMP/rh-selftest"

# --- mutations --------------------------------------------------------------
# A check that cannot fail proves nothing. Each mutation below is a plausible
# "simplification" of the shipped logic, and each must break at least one
# assertion above.
echo ""
echo "Mutations (each must break something)"

mutate() {
  local name="$1" file="$2" from="$3" to="$4"
  local a="$TMP/mut-stripe.swift" b="$TMP/mut-posthog.swift" c="$TMP/mut-quiet.swift"
  cp "$STRIPE" "$a"; cp "$POSTHOG" "$b"; cp "$QUIET" "$c"
  local target="$a"
  [[ "$file" == "posthog" ]] && target="$b"
  [[ "$file" == "quiet" ]] && target="$c"
  # Literal, via argv — NOT interpolated into a regex. Both the shipped
  # snippets and their replacements are Swift, full of parentheses, slashes and
  # backslashes, and a regex-based replacer spends its life escaping them
  # (the first cut of this file died on exactly that).
  MUT_FROM="$from" MUT_TO="$to" python3 - "$target" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$target"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$a" "$b" "$c" "$SHARED_RUNWAY" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# Moved to `scripts/room-runway-selftest.sh` with the code it tests: the
# runway arithmetic is now shared, and this file's drift guard proves this room
# FORWARDS to it rather than carrying a second copy.
# Calendar days vs interval arithmetic — an 11pm read the night before a
# deadline reading as "today".
mutate "days measured by interval instead of calendar" stripe \
  'let a = calendar.startOfDay(for: now)' \
  'let a = now'
# The ranking that makes an overdue window matter.
mutate "an overdue window no longer outranks a stopped account" stripe \
  'if let overdue = room.overdue {' \
  'if room.stopped { return String(localized: "Payments have stopped") }; if let overdue = room.overdue {'
# The staleness clause disappearing means a six-hour-old balance reads as live.
mutate "staleness never stated" stripe \
  'guard elapsed >= 3600 else { return nil }' \
  'guard elapsed >= 3600 * 24 * 365 else { return nil }'
# Moved to `scripts/room-runway-selftest.sh` with the code it tests: the
# runway arithmetic is now shared, and this file's drift guard proves this room
# FORWARDS to it rather than carrying a second copy.
# Caught in review: the headline counted `items`, which is capped, so a nine-
# deadline account read "4 deadlines ahead" directly above "5 more further out".
mutate "the headline counts drawn rows instead of the window" stripe \
  'if room.total > 1 {
                return String(localized: "\(room.total) deadlines ahead")' \
  'if room.items.count > 1 {
                return String(localized: "\(room.items.count) deadlines ahead")'
# Also caught in review: a swept account holds zero available every day, and
# availableText() filters zero buckets to nil — so keying "unread" off the
# money made a healthy account apologise, or vanish entirely.
mutate "read-and-zero collapses back into never-read" stripe \
  'var isEmpty: Bool { !balanceRead && items.isEmpty && !stopped }' \
  'var isEmpty: Bool { available == nil && items.isEmpty && !stopped }'
# §223's whole point: the metric that stopped is the finding.
mutate "silent metrics no longer lead" posthog \
  'if a.silent != b.silent { return a.silent }' \
  'if a.silent != b.silent { return b.silent }'
# A zero prior week dividing into an infinite rise.
mutate "a zero prior week divides anyway" posthog \
  'guard lastWeek > 0 else { return nil }' \
  'let lastWeek = max(lastWeek, 1)'
# Fourteen days is the minimum that can support a week-over-week claim.
mutate "a change claimed on half the series it needs" posthog \
  'guard series.count >= 14 else { return nil }' \
  'guard series.count >= 7 else { return nil }'
# Unread and empty are indistinguishable, and only one of them is a fact.
mutate "an unread device no longer says so" posthog \
  'if room.unread > 0, room.metrics.allSatisfy({ $0.series.isEmpty }) {' \
  'if false {'

# The failure the whole RoomQuiet type exists to stop.
mutate "a broken bridge falls back to the generic invitation" quiet \
  'case .attention:' \
  'case .attention: return nil'

echo ""
echo "room-heads-selftest: OK — assertions pass and every mutation is caught."
