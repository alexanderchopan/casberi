#!/bin/zsh
# Casberi notification self-test — the SHIPPED pure judgement behind every
# notification the app will ever send (prd §306, 2026-08-05):
#
#   Casberi/Casberi/Model/NotifyPlan.swift
#
# Foundation-only BY DESIGN, so it is compiled WHOLE AND UNMODIFIED rather than
# extracted — the strongest form of "the harness ran the shipped logic".
# Everything needing a framework (permission, attachments, UNNotificationRequest)
# lives in `Notifications.swift`, which makes no decisions and so has no
# judgement to test.
#
# WHY A HARNESS AND NOT A LIVE CHECK. **The simulator never runs a
# BGAppRefreshTask at all**, so the pass that decides what fires cannot be
# exercised there by any means; and on a real device the wrong answer arrives
# hours later on a lock screen, where nobody is holding a debugger. Every
# failure in this file is a silent wrong notification that renders perfectly:
#
#   · a 3am buzz for a like, because quiet hours failed to wrap past midnight
#   · a dispute that never fires, because the deadline window rejected it
#   · a deadline that fires forever after it passed — the worst possible time
#     to be told about it
#   · the same like announced eleven times, because the ledger let it re-arm
#   · eleven alarms in one sweep instead of the worst one and a count, which
#     is the thing that makes a person switch notifications off for good
#   · the LEAST urgent of those eleven chosen as the one to send
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

PLAN="Casberi/Casberi/Model/NotifyPlan.swift"
SWEEP="Casberi/Casberi/Model/NotifySweep.swift"
NOTIFY="Casberi/Casberi/Model/Notifications.swift"
for f in "$PLAN" "$SWEEP" "$NOTIFY"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

fail=0
guard() {  # guard <description> <grep-args...>
  local desc="$1"; shift
  if grep -qE "$@" 2>/dev/null; then
    printf '  ✓ %s\n' "$desc"
  else
    printf '  ✗ DRIFT: %s\n' "$desc"; fail=1
  fi
}

echo "── drift guards (wiring the compiled functions cannot prove) ──"

# The never-fires list is only enforceable because ONE file classifies. If a
# bridge starts calling `Notifications.submit` directly, the rules in NotifyPlan
# stop being the whole story and this harness stops covering the feature.
# `Notifications.likes` is the ONE documented exception (a like never lands as a
# row, so the sweep structurally cannot see it) and BlueskyIngest is its caller.
callers=$(grep -rn --include='*.swift' 'Notifications\.submit' Casberi/ \
  | grep -vE '^[^:]+:[0-9]+: *(///|//|\*)' \
  | cut -d: -f1 | sort -u \
  | grep -vE 'Notifications\.swift|ProbeHooks\.swift|WalletBackgroundRefresh\.swift' || true)
if [[ -z "$callers" ]]; then
  printf '  ✓ only the sweep and the probe submit plans\n'
else
  printf '  ✗ DRIFT: an unexpected file submits notifications: %s\n' "$callers"; fail=1
fi

# §306: the ask happens at the first real alarm, never at launch. A
# `requestAuthorization` anywhere but `askIfNeeded` is that rule broken.
askers=$(grep -rn --include='*.swift' -B2 'requestAuthorization' Casberi/ \
  | grep -E 'UNUserNotificationCenter|notificationCenter' \
  | cut -d: -f1 | sort -u | grep -v 'Notifications.swift' || true)
if [[ -z "$askers" ]]; then
  printf '  ✓ permission is asked from exactly one place\n'
else
  printf '  ✗ DRIFT: permission asked outside Notifications.swift: %s\n' "$askers"; fail=1
fi

# The classifier must never read a title: several are `String(localized:)`, so a
# title match works in English and silently classifies nothing on a translated
# device — a notification that never arrives, with no error anywhere.
if grep -nE 'thing\.title\.(hasPrefix|contains|hasSuffix)' "$SWEEP" >/dev/null 2>&1; then
  printf '  ✗ DRIFT: NotifySweep matches on a title (localized — see §306)\n'; fail=1
else
  printf '  ✓ classification never matches on a localized title\n'
fi

guard "time-sensitive is claimed by the deadline alarms alone" \
      'self == \.disputeOpened \|\| self == \.deadlineNear' "$PLAN"
guard "the deadline window rejects the past (> 0, not just <= window)" \
      'delta > 0 && delta <= deadlineWindow' "$PLAN"
guard "quiet hours HOLD rather than drop (a trigger, not a return)" \
      'UNTimeIntervalNotificationTrigger' "$NOTIFY"
guard "the whisper is one-shot and re-scheduled, never repeating" \
      'repeats: false' "$NOTIFY"
guard "the attachment ladder falls to the source mark before nothing" \
      'brandAsset\(source\)' "$NOTIFY"
guard "payouts stay unwired while paid and failed are indistinguishable" \
      'NOT WIRED, deliberately' "$SWEEP"

echo "── compiling the shipped file whole ──"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

run_case() {  # run_case <label> <sed-program-or-empty>
  local label="$1" mutation="${2:-}"
  if [[ -n "$mutation" ]]; then
    perl -0pe "$mutation" "$PLAN" > "$work/NotifyPlan.swift"
    # A mutation that matched NOTHING leaves the file identical, so the shipped
    # logic runs and "passes" — which reads as `NOT CAUGHT` and sends you
    # hunting a bug that isn't there. This is how a mutation suite silently
    # stops testing after a refactor renames what it targeted: it happened here
    # the same session, when `collapse` was split into `collapseGroup` and two
    # perl programs quietly became no-ops.
    if cmp -s "$PLAN" "$work/NotifyPlan.swift"; then
      echo "  ✗ $label: mutation matched nothing (stale target)"; return 3
    fi
  else
    cp "$PLAN" "$work/NotifyPlan.swift"
  fi
  cat > "$work/main.swift" <<'SWIFT'
import Foundation

var checks = 0, bad = 0
func ok(_ cond: Bool, _ what: String) {
    checks += 1
    if !cond { bad += 1; print("  ✗ \(what)") }
}

let cal = Calendar(identifier: .gregorian)
func at(_ h: Int, _ m: Int = 0) -> Date {
    var c = DateComponents(); c.year = 2026; c.month = 8; c.day = 5; c.hour = h; c.minute = m
    return cal.date(from: c)!
}
func plan(_ kind: NotifyKind, id: String = "x", at when: Date = at(12)) -> NotifyPlan {
    NotifyPlan(id: id, kind: kind, title: "t", body: "b", occurredAt: when)
}

// ── every kind routes, and to the class §306 named ──────────────────────────
for k in NotifyKind.allCases {
    ok(NotifyClass.allCases.contains(k.cls), "\(k) routes to a class")
}
ok(NotifyKind.disputeOpened.cls == .alarm, "dispute is an alarm")
ok(NotifyKind.moneyIn.cls == .arrival, "money in is an arrival")
ok(NotifyKind.likesReceived.cls == .arrival, "likes are an arrival")
ok(NotifyKind.repliesReceived.cls == .arrival, "replies are an arrival")
ok(NotifyKind.followersGained.cls == .arrival, "followers are an arrival")
ok(NotifyKind.whisper.cls == .whisper, "the whisper is its own class")

// ── time-sensitive is claimed by exactly two kinds ──────────────────────────
let ts = NotifyKind.allCases.filter(\.isTimeSensitive)
ok(Set(ts) == [.disputeOpened, .deadlineNear], "only the deadline alarms are time-sensitive")
ok(!NotifyKind.moneyIn.isTimeSensitive, "money arriving never breaks a Focus")
ok(!NotifyKind.whisper.isTimeSensitive, "the whisper never breaks a Focus")

// ── severity: the ranking that picks WHICH alarm survives a batch ───────────
ok(NotifyKind.disputeOpened.severity > NotifyKind.deadlineNear.severity, "dispute outranks deadline")
ok(NotifyKind.deadlineNear.severity > NotifyKind.approvalGranted.severity, "deadline outranks approval")
ok(NotifyKind.approvalGranted.severity > NotifyKind.poolProofNeeded.severity, "approval outranks proof")
ok(NotifyKind.poolProofNeeded.severity > NotifyKind.paymentsSilent.severity, "proof outranks silence")
ok(NotifyKind.paymentsSilent.severity > NotifyKind.poolCleared.severity, "silence outranks good news")
ok(NotifyKind.moneyIn.severity == 0, "arrivals never compete for the alarm slot")

// ── the deadline window ─────────────────────────────────────────────────────
let now = at(12)
ok(NotifyRules.deadlineIsNear(now.addingTimeInterval(3600), now: now), "1h out is near")
ok(NotifyRules.deadlineIsNear(now.addingTimeInterval(71 * 3600), now: now), "71h out is near")
ok(NotifyRules.deadlineIsNear(now.addingTimeInterval(72 * 3600), now: now), "exactly 72h is near")
ok(!NotifyRules.deadlineIsNear(now.addingTimeInterval(73 * 3600), now: now), "73h out is not yet")
ok(!NotifyRules.deadlineIsNear(now.addingTimeInterval(-60), now: now), "a passed deadline never fires")
ok(!NotifyRules.deadlineIsNear(now, now: now), "this instant is not ahead of us")

// ── quiet hours, including the wrap that is the NORMAL case ─────────────────
let night = NotifyRules.Quiet(startMinute: 22 * 60, endMinute: 8 * 60, enabled: true)
ok(night.contains(minute: 23 * 60), "23:00 is inside a 22→08 window")
ok(night.contains(minute: 3 * 60), "03:00 is inside a 22→08 window (past midnight)")
ok(night.contains(minute: 22 * 60), "22:00 exactly is inside")
ok(!night.contains(minute: 8 * 60), "08:00 exactly is outside — the window is half-open")
ok(!night.contains(minute: 12 * 60), "midday is outside")
let day = NotifyRules.Quiet(startMinute: 9 * 60, endMinute: 17 * 60, enabled: true)
ok(day.contains(minute: 12 * 60), "a NON-wrapping window still works")
ok(!day.contains(minute: 20 * 60), "…and excludes what is outside it")
var off = night; off.enabled = false
ok(!off.contains(minute: 23 * 60), "disabled quiet hours contain nothing")

// ── holding, and the exemption that is the point of time-sensitive ──────────
ok(NotifyRules.holdUntil(plan: plan(.disputeOpened), now: at(3), quiet: night, calendar: cal) == nil,
   "a dispute at 03:00 is NEVER held")
ok(NotifyRules.holdUntil(plan: plan(.deadlineNear), now: at(3), quiet: night, calendar: cal) == nil,
   "a deadline at 03:00 is never held")
ok(NotifyRules.holdUntil(plan: plan(.moneyIn), now: at(12), quiet: night, calendar: cal) == nil,
   "midday needs no hold")
let heldEarly = NotifyRules.holdUntil(plan: plan(.likesReceived), now: at(3), quiet: night, calendar: cal)
ok(heldEarly == at(8), "a 03:00 like waits until 08:00 TODAY, not tomorrow")
let heldLate = NotifyRules.holdUntil(plan: plan(.likesReceived), now: at(23), quiet: night, calendar: cal)
ok(heldLate == cal.date(byAdding: .day, value: 1, to: at(8)),
   "a 23:00 like waits until 08:00 TOMORROW")

// ── batching: the worst alarm, and an honest count of the rest ──────────────
let one = [plan(.poolCleared, id: "a")]
ok(NotifyRules.collapse(one).count == 1, "one alarm passes through untouched")
ok(NotifyRules.collapse(one)[0].body == "b", "…and its body is not rewritten")
let many = [plan(.poolCleared, id: "a"), plan(.disputeOpened, id: "b"),
            plan(.approvalGranted, id: "c")]
let collapsed = NotifyRules.collapse(many)
ok(collapsed.count == 1, "three alarms collapse to one")
ok(collapsed[0].kind == .disputeOpened, "the WORST alarm is the one sent")
ok(collapsed[0].body.contains("2 more"), "the other two are counted, never dropped")
let two = [plan(.poolCleared, id: "a"), plan(.disputeOpened, id: "b")]
ok(NotifyRules.collapse(two)[0].body.contains("1 more"), "singular reads '1 more'")
ok(!NotifyRules.collapse(two)[0].body.contains("1 more need "), "…and agrees with its verb")
// Arrivals ride alongside — they collapse per-post by id, not here.
let mixed = [plan(.poolCleared, id: "a"), plan(.disputeOpened, id: "b"),
             plan(.moneyIn, id: "m"), plan(.likesReceived, id: "l")]
let mixedOut = NotifyRules.collapse(mixed)
ok(mixedOut.count == 3, "one alarm plus both arrivals survive")
ok(mixedOut.filter { $0.cls == .arrival }.count == 2, "no arrival is ever collapsed away")
// Money arrivals collapse too — four dust transfers in one window is four
// buzzes otherwise, which is the alarm failure wearing better news. Found by
// `-notifyProbe` on a real corpus, not by reasoning.
let coins = [plan(.moneyIn, id: "m1", at: at(9)), plan(.moneyIn, id: "m2", at: at(10)),
             plan(.moneyIn, id: "m3", at: at(11))]
let coined = NotifyRules.collapse(coins)
ok(coined.count == 1, "three transfers collapse to one")
ok(coined[0].body.contains("2 more transfers"), "…and the rest are counted, in money's own noun")
ok(NotifyRules.collapse([plan(.moneyIn, id: "m1")]).count == 1, "a lone transfer is untouched")
ok(NotifyRules.collapse([plan(.moneyIn, id: "m1")])[0].body == "b", "…and keeps its own body")
// Attention never collapses here: two likers of two different posts are two
// events, and each already replaces itself by id.
let attention = [plan(.likesReceived, id: "p1"), plan(.likesReceived, id: "p2"),
                 plan(.followersGained, id: "f1")]
ok(NotifyRules.collapse(attention).count == 3, "likes and followers are never batched together")
// The two groups collapse INDEPENDENTLY — an alarm must never absorb a
// transfer's count, or the body would claim money needed a response.
let both = [plan(.disputeOpened, id: "d"), plan(.approvalGranted, id: "a"),
            plan(.moneyIn, id: "m1", at: at(9)), plan(.moneyIn, id: "m2", at: at(10))]
let bothOut = NotifyRules.collapse(both)
ok(bothOut.count == 2, "one alarm and one arrival survive")
ok(bothOut.contains { $0.cls == .alarm && $0.body.contains("1 more needs you") },
   "the alarm counts only alarms")
ok(bothOut.contains { $0.kind == .moneyIn && $0.body.contains("1 more transfer") },
   "the transfer counts only transfers")

// Determinism: same input, same choice, every run.
let tie = [plan(.approvalGranted, id: "z", at: at(9)), plan(.approvalGranted, id: "a", at: at(9))]
ok(NotifyRules.collapse(tie)[0].id == "a", "a tie breaks on id, so the choice is stable")
let byTime = [plan(.approvalGranted, id: "old", at: at(9)),
              plan(.approvalGranted, id: "new", at: at(11))]
ok(NotifyRules.collapse(byTime)[0].id == "new", "equal severity prefers the newer event")

// ── deadline phrasing: plain words, never "in 71 hours" ─────────────────────
ok(NotifyRules.deadlinePhrase(at(18), now: at(9), calendar: cal) == "today", "same day reads 'today'")
ok(NotifyRules.deadlinePhrase(cal.date(byAdding: .day, value: 1, to: at(9))!,
                              now: at(9), calendar: cal) == "tomorrow", "next day reads 'tomorrow'")
ok(NotifyRules.deadlinePhrase(cal.date(byAdding: .day, value: 3, to: at(9))!,
                              now: at(9), calendar: cal) == "in 3 days", "further out counts days")
ok(NotifyRules.deadlinePhrase(cal.date(byAdding: .day, value: -1, to: at(9))!,
                              now: at(9), calendar: cal) == "overdue", "the past reads 'overdue'")

// ── the ledger: fires once, ever ────────────────────────────────────────────
let suite = "casberi.notify.selftest"
UserDefaults.standard.removePersistentDomain(forName: suite)
let d = UserDefaults(suiteName: suite)!
let led = NotifyLedger(defaults: d)
ok(led.claim(["a", "b"]) == ["a", "b"], "first sight claims both")
ok(led.claim(["a", "b"]).isEmpty, "a second pass claims nothing")
ok(led.claim(["b", "c"]) == ["c"], "…and only the genuinely new id survives")
ok(led.hasFired("a"), "a claimed id reads as fired")
ok(!led.hasFired("zzz"), "an unseen id does not")
led.release("a")
ok(!led.hasFired("a"), "release re-arms exactly one id")
ok(led.hasFired("b"), "…and leaves its neighbours alone")
// The cap prunes the OLDEST, so a long-lived install can't grow without bound.
led.reset()
_ = led.claim((0..<(NotifyLedger.cap + 10)).map { "n\($0)" })
ok(!led.hasFired("n0"), "the oldest ids fall off the end at the cap")
ok(led.hasFired("n\(NotifyLedger.cap + 9)"), "the newest is kept")
ok(led.claim(["n0"]) == ["n0"], "…so a very old id could fire again, as documented")
UserDefaults.standard.removePersistentDomain(forName: suite)

if bad == 0 { print("  \(checks) assertions passed"); exit(0) }
print("  \(bad) of \(checks) FAILED")
exit(1)
SWIFT
  rm -f "$work/harness"
  ( cd "$work" && swiftc -O -o harness NotifyPlan.swift main.swift 2>&1 | grep -E 'error:' || true )
  [[ -x "$work/harness" ]] || { echo "  ✗ $label: did not compile"; return 2; }
  "$work/harness"
}

echo "── the shipped logic ──"
if ! run_case "shipped"; then fail=1; fi

# ── mutation pass ───────────────────────────────────────────────────────────
# A check that cannot fail proves nothing. Each mutation is a real bug someone
# could plausibly introduce, and the harness must REJECT every one.
echo "── mutations (each must FAIL) ──"
#
# A mutation that fails to COMPILE is NOT a catch — it is a broken mutation, and
# scoring it green is how a mutation suite quietly stops testing anything. This
# harness's own first run hid a real defect exactly that way: the shipped case
# did not compile (`exit 0` is shell, not Swift) while all twelve mutations
# reported "caught", because every one of them failed for the same reason the
# real code did. Compile failure is its own outcome here.
mutate() {  # mutate <label> <perl-program>
  local label="$1" prog="$2" out rc
  # `set -e` would kill the script on the very first CORRECTLY failing
  # mutation, silently skipping the rest — the run then prints nothing under
  # this heading and exits 0, which reads as a clean pass. Capture the status
  # inside an `if` so a non-zero is data rather than a fatal.
  if out="$(run_case "$label" "$prog" 2>&1)"; then rc=0; else rc=$?; fi
  case $rc in
    0) printf '  ✗ NOT CAUGHT: %s\n' "$label"; fail=1 ;;
    2) printf '  ✗ BROKEN MUTATION (did not compile): %s\n' "$label"; fail=1 ;;
    3) printf '  ✗ STALE MUTATION (matched nothing): %s\n' "$label"; fail=1 ;;
    *) printf '  ✓ caught: %s\n' "$label" ;;
  esac
}

mutate "a passed deadline still fires" \
       's/delta > 0 && delta <= deadlineWindow/delta <= deadlineWindow/'
mutate "the deadline window widens to a month" \
       's/72 \* 3600/720 * 3600/'
mutate "quiet hours stop wrapping past midnight" \
       's/minute >= startMinute \|\| minute < endMinute/minute >= startMinute \&\& minute < endMinute/'
mutate "a time-sensitive alarm gets held until morning" \
       's/guard !plan\.isTimeSensitive else \{ return nil \}//'
mutate "the batch keeps every alarm instead of the worst" \
       's/guard group\.count > alarmsPerSweep else \{ return plans \}/return plans/'
mutate "the batch picks the LEAST urgent alarm" \
       's/return a\.kind\.severity > b\.kind\.severity/return a.kind.severity < b.kind.severity/'
mutate "the batch drops the others silently instead of counting them" \
       's/lead\.body \+= more\(ranked\.count - 1\)/_ = more(ranked.count - 1)/'
mutate "severity collapses so every alarm ties" \
       's/case \.disputeOpened:    return 100/case .disputeOpened:    return 50/'
mutate "the ledger never prunes, growing without bound" \
       's/if order\.count > Self\.cap \{ order\.removeFirst\(order\.count - Self\.cap\) \}//'
mutate "the ledger re-claims ids it already spent" \
       's/for id in ids where !seen\.contains\(id\)/for id in ids/'
mutate "money arriving claims the time-sensitive level" \
       's/self == \.disputeOpened \|\| self == \.deadlineNear/self != .whisper/'
mutate "a held notification waits a full day too long" \
       's/return today > now \? today : cal/return cal/'
mutate "money arrivals stop collapsing (four dust transfers, four buzzes)" \
       's/matching: \{ \$0\.kind == \.moneyIn \}/matching: { _ in false }/'
mutate "the two groups share one count, so an alarm absorbs transfers" \
       's/matching: \{ \$0\.kind == \.moneyIn \}/matching: { \$0.cls != .whisper }/'

if [[ $fail -eq 0 ]]; then
  echo "✓ notify self-test passed"
else
  echo "✗ notify self-test FAILED"
fi
exit $fail
