#!/bin/zsh
# Casberi Dodo Payments self-test — verifies the SHIPPED pure judgement behind
# the Dodo Payments feed-room head (2026-09-01, prd §558):
#
#   Casberi/Casberi/Model/DodoPaymentsRoom.swift
#
# The THIRD Merchant of Record head, and the sharpest of the three, because it
# is the only one that states a REVENUE FIGURE. Stripe and Polar both refuse
# one; this room may state it only because `DodoPaymentsBridge` lands every
# succeeded payment inside its window, so the sample is the population. That
# licence is what makes every failure here expensive, and every one of them
# renders as a perfectly ordinary money card —
#
#   · an unsettled refund subtracted from revenue, so a pending return the
#     customer may never receive is already deducted from what you kept
#   · two currencies summed into one figure, stating a conversion nobody made
#   · a payment with no readable amount counted as zero rather than named
#   · a window-on-window claim made against a window the room never observed —
#     "up 400%" against an absence of data, on the screen where money is the
#     subject
#   · a NEGATIVE prior window dividing the delta, so growth prints as a fall
#   · a dispute joined to the wrong half of its own ref, so it never closes and
#     the card leads forever with trouble that ended weeks ago
#   · the two `windowDays` constants drifting apart across two files, so the
#     card states a 30-day total over a fortnight of rows
#
# `DodoPaymentsRoom.swift` is Foundation-only BY DESIGN, so it is compiled WHOLE
# AND UNMODIFIED — the strongest form of "the harness ran the shipped logic".
# Everything touching `Thing` or `UserDefaults` lives in
# `DodoPaymentsRoomSource.swift`, which no harness can compile; the wiring facts
# it carries are covered by the drift guards below instead.
#
# Pure, local, deterministic — no network, no token, no simulator. Exit non-zero
# on failure. Accepts an optional `--self-test` argument (ignored — every
# assertion and mutation below already runs on every invocation).
set -euo pipefail
cd "$(dirname "$0")/.."

ROOM="Casberi/Casberi/Model/DodoPaymentsRoom.swift"
SOURCE="Casberi/Casberi/Model/DodoPaymentsRoomSource.swift"
BRIDGE="Casberi/Casberi/Model/DodoPaymentsBridge.swift"
CARD="Casberi/Casberi/Screens/DodoPaymentsRoomCard.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
PROBES="Casberi/Casberi/Shell/ProbeHooks.swift"
THING="Casberi/Shared/Thing.swift"
DEMO="Casberi/Casberi/Model/DemoSeedAll.swift"
for f in "$ROOM" "$SOURCE" "$BRIDGE" "$CARD" "$FEED" "$PROBES" "$THING" "$DEMO"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/dodo-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- drift guards ------------------------------------------------------------
# Wiring facts the compiled functions cannot prove about themselves. A perfect
# `ordered` is worthless if the card draws its own order, and a perfect
# `compose` is worthless if nothing ever calls it.

# THE WINDOW PIN. The room states "in N days" and the bridge decides how many
# days of rows exist; they live in two files and nothing but this ties them.
# Drift states a 30-day total over a fortnight of rows and looks correct.
ROOM_WINDOW=$(grep -oE 'static let windowDays = [0-9]+' "$ROOM" | grep -oE '[0-9]+' | head -1)
BRIDGE_WINDOW=$(grep -oE 'static let windowDays = [0-9]+' "$BRIDGE" | grep -oE '[0-9]+' | head -1)
[[ -n "$ROOM_WINDOW" && -n "$BRIDGE_WINDOW" ]] \
  || { echo "✗ could not read windowDays from both files — the pin cannot be checked"; exit 1; }
[[ "$ROOM_WINDOW" == "$BRIDGE_WINDOW" ]] \
  || { echo "✗ DodoPaymentsRoom.windowDays ($ROOM_WINDOW) != DodoPaymentsAccount.windowDays ($BRIDGE_WINDOW) — the card would state a $ROOM_WINDOW-day total over $BRIDGE_WINDOW days of rows"; exit 1; }

grep -q 'case .dodoPayments(let room)' "$FEED" \
  || { echo "✗ the Dodo Payments head is no longer rendered from the sourceHead chain"; exit 1; }
grep -q 'DodoPaymentsRoomSource.compose(things: visible)' "$FEED" \
  || { echo "✗ the Dodo Payments head is not wired into sourceHead — it can never draw"; exit 1; }
grep -q 'DodoPaymentsRoom.position(days: retry.days, span: span)' "$CARD" \
  || { echo "✗ the retry rail no longer places marks through the shipped position()"; exit 1; }
grep -q 'DodoPaymentsRoom.share(payments: currency.payments, of: top)' "$CARD" \
  || { echo "✗ the currency bars no longer use the shipped share() — a bar could state a cross-currency comparison"; exit 1; }
grep -q 'things.live' "$SOURCE" \
  || { echo "✗ DodoPaymentsRoomSource no longer filters live at the boundary (corollary 4)"; exit 1; }
grep -q 'Hook(key: "dodoPaymentsRoomProbe")' "$PROBES" \
  || { echo "✗ -dodoPaymentsRoomProbe is gone — the head would have no headless verification"; exit 1; }
grep -q 'note("dodoHead"' "$PROBES" \
  || { echo "✗ roomInsightProbe has no dodoHead line — it would report 'leads with NOTHING' about a room that leads with a card"; exit 1; }
grep -q 'dodoHead          "Dodo Payments"' scripts/verify.sh \
  || { echo "✗ Dodo Payments is not in verify.sh's ROOM_HEADS — demo coverage would never assert this head composes"; exit 1; }

# THE §374 MASK. The room is in the Wallet catalog group, so hide-balances must
# reach it — and the mask is PASSED IN rather than read, which is what keeps
# the room Foundation-only and compilable whole. Both halves are guarded: the
# room must accept a mask, and the card must actually supply one.
grep -q 'mask: String? = nil' "$ROOM" \
  || { echo "✗ DodoPaymentsRoom no longer takes a mask — §374 hide-balances cannot reach this card"; exit 1; }
grep -q 'BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil' "$CARD" \
  || { echo "✗ the card no longer supplies the §374 mask — money would draw with balances hidden"; exit 1; }

# THE DEMO. `verify.sh`'s room-head coverage hard-fails when a head cannot
# compose over the demo corpus, and a demo dispute row whose ref loses its
# `:opened` suffix lands fine and joins to nothing — the head then correctly
# reports no open dispute and the coverage step passes anyway, so nothing else
# would notice.
grep -q 'dodopayments:dispute:dis_9a2c4e6b8d0f:opened' "$DEMO" \
  || { echo "✗ the demo's Dodo dispute lost its ':opened' ref — openDisputes joins on that suffix and would find nothing"; exit 1; }

# The comment-stripped copy: three of these files document these rules by
# naming the very thing they must not do (the Obsidian/Cursor lesson), so a
# negative guard grepping raw source fires against the prose explaining it.
CODE="$TMP/code-only.swift"
strip_comments() {
  python3 - "$1" "$2" <<'PY'
import sys
src = open(sys.argv[1]).read()
out, i, n = [], 0, len(src)
in_string = in_line = False
block = 0
while i < n:
    two = src[i:i+2]
    if in_line:
        if src[i] == "\n": in_line = False; out.append("\n")
        i += 1; continue
    if block:
        if two == "/*": block += 1; i += 2; continue
        if two == "*/": block -= 1; i += 2; continue
        if src[i] == "\n": out.append("\n")
        i += 1; continue
    if in_string:
        if src[i] == "\\": out.append(src[i:i+2]); i += 2; continue
        if src[i] == '"': in_string = False
        out.append(src[i]); i += 1; continue
    if two == "//": in_line = True; i += 2; continue
    if two == "/*": block = 1; i += 2; continue
    if src[i] == '"': in_string = True
    out.append(src[i]); i += 1
open(sys.argv[2], "w").write("".join(out))
PY
}

# THE NO-CURVE GUARD. `StripeRoom`'s ban survives the revenue licence — thirty
# days of an occasional-payment account is a handful of points, and a line
# through them draws a trend the data cannot support. The room's type doc says
# so by name, which is exactly why this reads the stripped copy.
strip_comments "$ROOM" "$CODE"
for banned in 'series' 'curve' 'sparkline' 'trend'; do
  grep -qi -- "$banned" "$CODE" \
    && { echo "✗ DodoPaymentsRoom.swift now names '$banned' in CODE — the no-revenue-curve ban is broken"; exit 1; }
done

# THE ARITHMETIC GUARD. Every figure must come off `priceValue`/`priceCurrency`
# as DATA. Re-parsing a formatted amount back out of a title is the exact thing
# `StripeRoom` cannot do and the reason it has no figure at all; committing it
# here would make this card wrong in whatever way the bridge's own prose is.
#
# Narrow ON PURPOSE, and measured rather than guessed: `thing.title` IS read
# here, legitimately, for a retry's NAME — banning it outright fires on correct
# code, and a lint that cries wolf gets turned off within a week. What is banned
# is the shape of turning prose back into a NUMBER.
strip_comments "$SOURCE" "$TMP/source-code.swift"
for banned in 'transferAmount' 'Double(thing' 'Double(t.' 'title.range(of:' 'PriceFormat'; do
  grep -qF -- "$banned" "$TMP/source-code.swift" \
    && { echo "✗ DodoPaymentsRoomSource.swift now reads money out of prose ($banned) — amounts must come off priceValue/priceCurrency"; exit 1; }
done
# The positive half: the money really is read off the stored fields. Without
# this the loop above is satisfied by a file that reads no money at all.
grep -q 'amount: thing.priceValue' "$SOURCE" \
  || { echo "✗ DodoPaymentsRoomSource no longer reads priceValue — the figure has no source"; exit 1; }
grep -q 'currency: thing.priceCurrency' "$SOURCE" \
  || { echo "✗ DodoPaymentsRoomSource no longer reads priceCurrency — amounts could be summed across codes"; exit 1; }

# THE REVENUE-IS-NOT-SPEND GUARD. Dodo lands `.transaction` rows carrying both
# money fields, so it PASSES `Corpus.cardSpendSources`' stated data test and
# joining it looks correct. It must not: money arriving is not money spent, and
# folding it in answers "what did I spend?" with the opposite sign.
strip_comments "$THING" "$TMP/thing-code.swift"
grep -qE 'cardSpendSources: Set<String> = \["Apple Wallet", "Gnosis Pay", "ether.fi"\]' "$TMP/thing-code.swift" \
  || { echo "✗ Corpus.cardSpendSources changed — if Dodo Payments or Polar joined it, revenue is now being counted as spending (prd §558)"; exit 1; }

# --- compile DodoPaymentsRoom.swift WHOLE, unmodified ------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

let cal = Calendar.current
let t0 = cal.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000))
func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: t0)! }
let en = Locale(identifier: "en_US")

func pay(_ amount: Double?, _ code: String?, _ n: Int) -> DodoPaymentsRoom.Sighting {
    DodoPaymentsRoom.Sighting(amount: amount, currency: code, at: day(n),
                              isRefund: false, settled: true)
}
func refund(_ amount: Double?, _ code: String?, _ n: Int,
            settled: Bool = true) -> DodoPaymentsRoom.Sighting {
    DodoPaymentsRoom.Sighting(amount: amount, currency: code, at: day(n),
                              isRefund: true, settled: settled)
}
func retry(_ name: String, days: Int) -> DodoPaymentsRoom.Retry {
    DodoPaymentsRoom.Retry(id: name, name: name, due: day(days), days: days)
}
func dispute(_ id: String, _ amount: Double? = 29, _ code: String? = "USD",
             _ n: Int = -2) -> DodoPaymentsRoom.Dispute {
    DodoPaymentsRoom.Dispute(id: id, amount: amount, currency: code, at: day(n))
}
func compose(_ sightings: [DodoPaymentsRoom.Sighting],
             disputes: [DodoPaymentsRoom.Dispute] = [],
             retries: [DodoPaymentsRoom.Retry] = []) -> DodoPaymentsRoom {
    DodoPaymentsRoom.compose(sightings: sightings, disputes: disputes,
                             retries: retries, now: t0)
}

print("Dodo — the window")
check("a payment inside the window counts",
      compose([pay(49, "USD", -3)]).lead?.gross == 49)
check("a payment older than two windows counts toward neither total",
      compose([pay(49, "USD", -3), pay(999, "USD", -80)]).lead?.gross == 49)
check("a payment in the PRIOR window does not inflate this one",
      compose([pay(49, "USD", -3), pay(500, "USD", -40)]).lead?.gross == 49)
check("the window boundary is inclusive at exactly N days back",
      compose([pay(10, "USD", -30)]).lead?.gross == 10)
check("one day past the window is out",
      compose([pay(10, "USD", -31)]).lead == nil)

print("")
print("Dodo — refunds")
check("a settled refund subtracts from the net",
      compose([pay(49, "USD", -3), refund(12, "USD", -2)]).lead?.net == 37)
check("gross survives the subtraction, so the card can state both",
      compose([pay(49, "USD", -3), refund(12, "USD", -2)]).lead?.gross == 49)
// THE fixture that matters: an unsettled refund must change nothing at all.
check("an UNSETTLED refund subtracts nothing",
      compose([pay(49, "USD", -3), refund(12, "USD", -2, settled: false)]).lead?.net == 49)
check("an unsettled refund is not even counted as a refund",
      compose([pay(49, "USD", -3), refund(12, "USD", -2, settled: false)]).lead?.refunds == 0)
check("a refund never CREATES a currency, so no total can go negative",
      compose([pay(49, "USD", -3), refund(80, "EUR", -2)]).currencies.count == 1)
check("a refund in a currency with no payments is counted, never dropped silently",
      compose([pay(49, "USD", -3), refund(80, "EUR", -2)]).unmatchedRefunds == 1)
check("an unsettled orphan refund is not counted either",
      compose([pay(49, "USD", -3), refund(80, "EUR", -2, settled: false)]).unmatchedRefunds == 0)

print("")
print("Dodo — unpriced")
check("a payment with no amount is counted, never zero",
      compose([pay(nil, "USD", -3)]).unpriced == 1)
check("a payment with no currency is counted, never zero",
      compose([pay(49, nil, -3)]).unpriced == 1)
check("a payment with an empty currency string is counted, never bucketed",
      compose([pay(49, "", -3)]).unpriced == 1)
check("an unreadable payment contributes nothing to a total",
      compose([pay(nil, "USD", -3), pay(10, "USD", -3)]).lead?.gross == 10)
// An unreadable REFUND is not "revenue missing" — it is a subtraction we
// failed to make, which overstates nothing the reader is shown. Counting it
// under `unpriced` would put a false apology under a correct figure.
check("an unreadable REFUND is not counted as unpriced revenue",
      compose([pay(10, "USD", -3), refund(nil, "USD", -2)]).unpriced == 0)
check("an unpriced payment outside the window is not counted",
      compose([pay(nil, "USD", -40)]).unpriced == 0)

print("")
print("Dodo — currencies are never summed")
let two = compose([pay(100, "USD", -1), pay(100, "USD", -2), pay(900, "EUR", -3)])
check("two currencies stay two readings", two.currencies.count == 2)
check("the lead is the one with MORE PAYMENTS, not the bigger number",
      two.lead?.code == "USD")
check("the bigger currency is still present, just not leading",
      two.currencies.contains { $0.code == "EUR" })
// The tie-breaks, each isolated so a mutation to one cannot pass on another.
let tie = DodoPaymentsRoom.ordered([
    DodoPaymentsRoom.Currency(code: "AAA", gross: 1, payments: 2, refunded: 0,
                              refunds: 0, prior: nil, newest: day(-5)),
    DodoPaymentsRoom.Currency(code: "BBB", gross: 1, payments: 2, refunded: 0,
                              refunds: 0, prior: nil, newest: day(-1)),
])
check("equal counts break on recency, newest first", tie.first?.code == "BBB")
let tie2 = DodoPaymentsRoom.ordered([
    DodoPaymentsRoom.Currency(code: "ZZZ", gross: 1, payments: 2, refunded: 0,
                              refunds: 0, prior: nil, newest: day(-1)),
    DodoPaymentsRoom.Currency(code: "AAA", gross: 1, payments: 2, refunded: 0,
                              refunds: 0, prior: nil, newest: day(-1)),
])
check("equal counts and equal recency break on code, so the order is TOTAL",
      tie2.first?.code == "AAA")

print("")
print("Dodo — the prior window is refused unless observed")
check("a young room claims no comparison",
      compose([pay(49, "USD", -3)]).lead?.prior == nil)
check("a room reaching past two windows may compare",
      compose([pay(49, "USD", -3), pay(20, "USD", -70)]).lead?.prior != nil)
check("knowsPriorWindow is false with no history at all",
      DodoPaymentsRoom.knowsPriorWindow(oldest: nil, now: t0) == false)
check("knowsPriorWindow is false for a row inside the prior window",
      DodoPaymentsRoom.knowsPriorWindow(oldest: day(-40), now: t0) == false)
check("knowsPriorWindow is true at exactly the prior window's start",
      DodoPaymentsRoom.knowsPriorWindow(oldest: day(-60), now: t0) == true)
// The prior total is a NET, like the figure it is compared against — a prior
// gross against a current net would report a fall every time a refund landed.
let priorNet = compose([pay(100, "USD", -3),
                        pay(200, "USD", -40), refund(50, "USD", -41),
                        pay(1, "USD", -70)])
check("the prior window subtracts its own refunds", priorNet.lead?.prior == 150)

print("")
print("Dodo — the change")
func withPrior(_ net: Double, _ prior: Double?) -> DodoPaymentsRoom.Currency {
    DodoPaymentsRoom.Currency(code: "USD", gross: net, payments: 3, refunded: 0,
                              refunds: 0, prior: prior, newest: t0)
}
check("a quarter more reads as a quarter more",
      DodoPaymentsRoom.delta(withPrior(125, 100)).map { abs($0 - 0.25) < 0.0001 } == true)
check("an unknown prior has no delta", DodoPaymentsRoom.delta(withPrior(125, nil)) == nil)
check("a ZERO prior has no delta — coming back from nothing has no percentage",
      DodoPaymentsRoom.delta(withPrior(125, 0)) == nil)
check("a NEGATIVE prior has no delta — dividing by it would flip the sign",
      DodoPaymentsRoom.delta(withPrior(125, -50)) == nil)
check("a small move is noise and earns no word",
      DodoPaymentsRoom.deltaLabel(withPrior(105, 100)) == nil)
check("a real rise is stated", DodoPaymentsRoom.deltaLabel(withPrior(150, 100)) != nil)
check("a real fall is stated as less, not as more",
      DodoPaymentsRoom.deltaLabel(withPrior(50, 100))?.contains("less") == true)
check("a real rise is stated as more",
      DodoPaymentsRoom.deltaLabel(withPrior(150, 100))?.contains("more") == true)

print("")
print("Dodo — the bar")
check("the leader fills the bar", DodoPaymentsRoom.share(payments: 5, of: 5) == 1)
check("half is half", abs(DodoPaymentsRoom.share(payments: 2, of: 4) - 0.5) < 0.0001)
check("a zero top cannot divide by zero", DodoPaymentsRoom.share(payments: 3, of: 0) == 0)

print("")
print("Dodo — the retry rail")
check("a span floors at a week", DodoPaymentsRoom.span(days: [1, 2]) == 7)
check("span reflects the FURTHEST day among several, not the nearest",
      DodoPaymentsRoom.span(days: [1, 90]) == 90)
check("today sits at the start", DodoPaymentsRoom.position(days: 0, span: 30) == 0)
check("a passed date pins to the start", DodoPaymentsRoom.position(days: -9, span: 30) == 0)
check("a date past the span clamps to the end", DodoPaymentsRoom.position(days: 99, span: 30) == 1)
check("a zero span cannot divide by zero", DodoPaymentsRoom.position(days: 5, span: 0) == 0)
check("a span label reads in months where it divides", DodoPaymentsRoom.spanLabel(span: 60) == "2 mo")
check("a span label reads in days otherwise", DodoPaymentsRoom.spanLabel(span: 14) == "14 days")
check("today is named", DodoPaymentsRoom.value(days: 0) == "today")
check("tomorrow is named", DodoPaymentsRoom.value(days: 1) == "tomorrow")
check("further out counts days", DodoPaymentsRoom.value(days: 5) == "5 days")
// THE RULING THAT DIVERGES FROM POLAR: a passed billing date is not a missed
// one. This bridge reads `next_billing_date` and has no signal for whether the
// attempt happened, so "Missed" would state an outcome nobody measured.
check("a passed date is never called overdue", DodoPaymentsRoom.value(days: -3) == "due")
check("a passed retry says Retrying, NEVER Missed",
      DodoPaymentsRoom.retryChip(retry("a", days: -1)) == "Retrying")
check("an upcoming retry names the next attempt",
      DodoPaymentsRoom.retryChip(retry("a", days: 2)) == "Next attempt")
let manyRetries = compose([pay(10, "USD", -1)],
                          retries: [retry("a", days: 1), retry("b", days: 2),
                                    retry("c", days: 3), retry("d", days: 4)])
check("retries are capped to what the rail draws", manyRetries.retries.count == 3)
check("the uncapped total survives, so the headline cannot disagree with the note",
      manyRetries.retryTotal == 4)
check("retries sort soonest first", manyRetries.retries.first?.name == "a")
check("the coverage note names what the cap dropped",
      DodoPaymentsRoom.coverageNote(manyRetries)?.contains("1 more") == true)

print("")
print("Dodo — the headline ranking (trouble first)")
let quiet = compose([pay(49, "USD", -3)])
check("money leads a healthy room",
      DodoPaymentsRoom.headline(quiet, locale: en).contains("49"))
let oneRetry = compose([pay(49, "USD", -3)], retries: [retry("a", days: 2)])
check("a subscription needing you outranks the money",
      DodoPaymentsRoom.headline(oneRetry) == "A subscription needs you")
let disputed = compose([pay(49, "USD", -3)], disputes: [dispute("d1")],
                       retries: [retry("a", days: 2)])
check("an open dispute outranks a subscription",
      DodoPaymentsRoom.headline(disputed, locale: en).hasPrefix("A dispute is open"))
check("a single open dispute names its amount",
      DodoPaymentsRoom.headline(disputed, locale: en).contains("29"))
check("an unpriced dispute states the fact without inventing a figure",
      DodoPaymentsRoom.headline(compose([], disputes: [dispute("d1", nil, nil)]))
        == "A dispute is open")
check("several disputes are counted rather than named",
      DodoPaymentsRoom.headline(compose([], disputes: [dispute("d1"), dispute("d2")]))
        == "2 disputes are open")
check("several retries are counted",
      DodoPaymentsRoom.headline(compose([], retries: [retry("a", days: 1), retry("b", days: 2)]))
        == "2 subscriptions need you")
check("a quiet window on real history says so",
      DodoPaymentsRoom.headline(compose([pay(49, "USD", -80)]))
        == "Nothing came in over 30 days")
check("an empty room says something different from a quiet one",
      DodoPaymentsRoom.headline(compose([])) == "Nothing has come in yet")
check("a second currency is named in the headline rather than folded in",
      DodoPaymentsRoom.headline(two, locale: en).contains("plus another currency"))

print("")
print("Dodo — the note is never a restatement")
check("when a dispute leads, the note carries the money",
      DodoPaymentsRoom.note(disputed, locale: en).contains("49"))
check("when money leads, the note does NOT repeat it",
      DodoPaymentsRoom.note(quiet, locale: en).contains("49") == false)
check("when money leads with no comparison, the note says so out loud",
      DodoPaymentsRoom.note(quiet).contains("not watching long enough"))
let comparable = compose([pay(150, "USD", -3), pay(100, "USD", -40), pay(1, "USD", -70)])
check("a real change replaces the payment count in the note",
      DodoPaymentsRoom.note(comparable).contains("more than"))

print("")
print("Dodo — the mask (§374)")
check("the headline's money is withheld when balances are hidden",
      DodoPaymentsRoom.headline(quiet, locale: en, mask: "••••").contains("49") == false)
check("a masked headline still says the window",
      DodoPaymentsRoom.headline(quiet, locale: en, mask: "••••").contains("30 days"))
check("a disputed amount is masked too",
      DodoPaymentsRoom.headline(disputed, locale: en, mask: "••••").contains("29") == false)
check("the payment COUNT survives the mask — it is not a balance",
      DodoPaymentsRoom.currencyLine(withPrior(125, nil), locale: en, mask: "••••")
        .contains("3 payments"))

print("")
print("Dodo — the footnotes")
check("an unpriced payment is named under the figure it is missing from",
      DodoPaymentsRoom.footnote(compose([pay(10, "USD", -1), pay(nil, "USD", -1)]), now: t0)?
        .contains("no readable amount") == true)
check("a healthy room carries no footnote",
      DodoPaymentsRoom.footnote(quiet, now: t0) == nil)
check("a long silence is named once it outruns the window",
      DodoPaymentsRoom.idleNote(newest: day(-40), now: t0)?.contains("40") == true)
check("a silence inside the window is not named — it would contradict the headline",
      DodoPaymentsRoom.idleNote(newest: day(-5), now: t0) == nil)
check("the refund note states what came back",
      DodoPaymentsRoom.refundNote(compose([pay(49, "USD", -3), refund(12, "USD", -2)]),
                                  locale: en)?.contains("12") == true)
check("no refunds means no refund note",
      DodoPaymentsRoom.refundNote(quiet) == nil)

print("")
print("Dodo — isEmpty")
check("an empty room is empty", compose([]).isEmpty)
check("a dispute alone keeps the card alive",
      compose([], disputes: [dispute("d1")]).isEmpty == false)
check("a retry alone keeps the card alive",
      compose([], retries: [retry("a", days: 2)]).isEmpty == false)
// Keyed on the ROOM, not the window: an account busy last quarter and quiet
// this month has a real thing to say, and hiding the head would leave the room
// looking as though it had never been used.
check("a quiet window on real history is NOT empty",
      compose([pay(49, "USD", -80)]).isEmpty == false)

print("")
if failures == 0 {
    print("✓ dodo self-test: all assertions passed")
} else {
    print("✗ dodo self-test: \(failures) assertion(s) failed")
    exit(1)
}
SWIFT

if ! swiftc -O -o "$TMP/run" "$ROOM" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ DodoPaymentsRoom.swift did not compile"
  grep -E 'error:' "$TMP/build.log" | head -20
  exit 1
fi
"$TMP/run"

# --- mutations ----------------------------------------------------------------
echo
echo "mutations (each must be caught)"

WORK="$TMP/work"
mutate() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$ROOM" "$WORK/DodoPaymentsRoom.swift"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/DodoPaymentsRoom.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$WORK/DodoPaymentsRoom.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$WORK/DodoPaymentsRoom.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 1. The single most expensive failure: a pending refund deducted from money the
#    account still holds.
mutate "an unsettled refund is allowed to subtract" \
  'if sighting.isRefund, !sighting.settled { continue }' \
  'if sighting.isRefund, !sighting.settled, false { continue }'

# 2. A refund in a currency that took no payments is dropped in silence rather
#    than counted — the money vanishes with nothing on screen to say so.
mutate "an orphan refund is dropped instead of counted" \
  'unmatchedRefunds += cell.count' \
  'unmatchedRefunds += 0 * cell.count'

# 3. Currencies ranked by AMOUNT — the cross-currency sum wearing a sort.
mutate "currencies rank by amount instead of payment count" \
  'if a.payments != b.payments { return a.payments > b.payments }' \
  'if a.gross != b.gross { return a.gross > b.gross }'

# 4. The prior window claimed without ever observing it.
mutate "a prior window is claimed on a room too young to have seen it" \
  'return oldest <= windowStart(now, back: 2, calendar: calendar)' \
  'return true'

# 5. A negative prior dividing the delta, so growth prints as a fall.
mutate "a negative prior window is allowed to divide the delta" \
  'guard let prior = currency.prior, prior > 0 else { return nil }' \
  'guard let prior = currency.prior, prior != 0 else { return nil }'

# 6. An unpriced payment counted as zero rather than named.
mutate "an unreadable payment is silently dropped instead of counted" \
  'if sighting.at >= start, !sighting.isRefund { unpriced += 1 }' \
  'if sighting.at >= start, !sighting.isRefund, false { unpriced += 1 }'

# 7. Trouble stops leading — the §349 ranking inverted, so a card leads with
#    revenue while a subscription is failing beneath it.
mutate "a subscription needing you no longer outranks the money" \
  'if room.retryTotal > 0 {' \
  'if room.retryTotal > 0, false {'

# 7b. Several open disputes collapse onto the first, so a card says "a dispute"
#     while four are running.
mutate "several open disputes collapse onto one" \
  'if room.disputes.count > 1 {' \
  'if room.disputes.count > 1, false {'

# 8. The note becomes a restatement of the headline.
mutate "the note repeats the headline instead of carrying the other fact" \
  'if room.leadsWithTrouble {' \
  'if room.leadsWithTrouble, false {'

# 9. The rail's clamp removed — a passed retry runs off the left edge and
#    vanishes, hiding the row that most needs seeing.
mutate "a passed retry no longer clamps to the start of the rail" \
  'return min(max(Double(days) / Double(span), 0), 1)' \
  'return Double(days) / Double(span)'

# 10. The span takes the nearest rather than the furthest day.
mutate "span no longer takes the FURTHEST day" \
  'let furthest = days.max() ?? 0' \
  'let furthest = days.min() ?? 0'

# 11. A passed billing date called Missed — an outcome this bridge cannot know.
mutate "a passed retry is called Missed, stating an outcome nobody measured" \
  'retry.days < 0 ? String(localized: "Retrying") : String(localized: "Next attempt")' \
  'retry.days < 0 ? String(localized: "Missed") : String(localized: "Next attempt")'

# 12. isEmpty keyed on the window, so a quiet month hides a room with history.
mutate "isEmpty is keyed on the window instead of on the room" \
  'var isEmpty: Bool { allTime == 0 && disputes.isEmpty && retryTotal == 0 }' \
  'var isEmpty: Bool { currencies.isEmpty && disputes.isEmpty && retryTotal == 0 }'

# 13. The retry cap silently truncating rather than reporting.
mutate "the uncapped retry total collapses onto the drawn count" \
  'retryTotal: sortedRetries.count,' \
  'retryTotal: min(sortedRetries.count, retryCap),'

echo
echo "✓ dodo self-test: assertions and mutations all passed"
