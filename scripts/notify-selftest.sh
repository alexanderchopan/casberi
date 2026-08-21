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

# ── the Walletbeat alarm's four gates (prd §422) ────────────────────────────
# `NotifySweep` is @MainActor + SwiftData, so it cannot be compiled here; these
# guard the wiring the compiled `NotifyPlan` half cannot see. Every one of them
# fails SILENTLY in the direction that matters most: drop the watch-list test
# and the app alarms about a wallet somebody has never opened, which is the
# fastest way to have notifications switched off for good.
guard "the Walletbeat alarm reads Walletbeat's own facts, never the row's title" \
      'WalletbeatIncidentBook\.facts\(ref: ref\)' "$SWEEP"
guard "only high and critical alarm" \
      'severity >= \.high' "$SWEEP"
guard "a resolved incident never alarms" \
      'facts\.status\.isOpen' "$SWEEP"
guard "the incident must name a wallet the person actually watches" \
      'facts\.wallets\.contains\(where: \{ watchedWallets\.contains\(\$0\) \}\)' "$SWEEP"
# The watch list comes from the CORPUS (§419's watch-is-a-Thing decision), so it
# can never disagree with the rows in the feed. A version that read a store
# instead would be one more thing to keep in step.
guard "the watch list is derived from the rows the sweep already holds" \
      'live\.compactMap \{ WalletbeatWatch\.walletID\(from: \$0\) \}' "$SWEEP"
# FOLLOWING ALONE MUST NEVER ALARM. The empty default is what makes that true
# for any caller that forgets, and it is the difference between this feature
# and a security-news firehose pointed at a lock screen.
guard "an unspecified watch list defaults to empty, so nothing alarms" \
      'watchedWallets: Set<String> = \[\]' "$SWEEP"
# A rating revision is Walletbeat changing its own mind, not something that
# happened to you — the same test that keeps a card spend quiet (§313).
if grep -qE 'WalletbeatWatch\.isRevisionRef' "$SWEEP"; then
  printf '  ✗ DRIFT: a Walletbeat rating REVISION reaches the classifier (§422 — it is not news about you)\n'; fail=1
else
  printf '  ✓ a rating revision never notifies\n'
fi

# ── the entitlement and the promise, tied together (prd §306, 2026-08-14) ──
# `interruptionLevel = .timeSensitive` is a line that COMPILES AND RUNS
# whether or not the app is allowed to mean it: without the entitlement iOS
# silently caps it to `.active`, nothing fails, no log line appears, and the
# notification arrives looking exactly right — it just stops piercing a Focus.
# That is the §83 fake-status shape in the one surface with no screen to
# inspect, and it is why the two halves are checked against each other here
# rather than trusted to stay in step. Nine days of "declared but not
# honoured" (the §306 amendment) is the measured cost of not having this.
TS_KEY='com.apple.developer.usernotifications.time-sensitive'
ENT_IOS="Casberi/Casberi/Casberi.entitlements"
ENT_MAC="Casberi/Casberi/Casberi-Catalyst.entitlements"
SETTINGS="Casberi/Casberi/Screens/AccountDetailSheet.swift"
for f in "$ENT_IOS" "$ENT_MAC" "$SETTINGS"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# The entitlement must be a real <key>, not a mention in a comment — the
# mac-parity audit's key regex is naive the same way, and "documenting" a
# capability by commenting it in would satisfy a lazier check than this.
ts_key_present() {  # ts_key_present <entitlements-file>
  grep -qE "^[[:space:]]*<key>${TS_KEY}</key>" "$1"
}
declares_ts=$(grep -cE 'interruptionLevel = plan\.isTimeSensitive \? \.timeSensitive' "$NOTIFY" || true)
if [[ "$declares_ts" -gt 0 ]]; then
  for pair in "iOS:$ENT_IOS" "Catalyst:$ENT_MAC"; do
    label="${pair%%:*}"; file="${pair#*:}"
    if ts_key_present "$file"; then
      printf '  ✓ %s entitlements carry the time-sensitive key\n' "$label"
    else
      printf '  ✗ DRIFT: %s sets .timeSensitive but %s lacks %s — iOS will cap it to .active silently\n' \
             "$NOTIFY" "$file" "$TS_KEY"; fail=1
    fi
  done
else
  printf '  ✓ nothing claims .timeSensitive (entitlement not required)\n'
fi

# And the copy may only promise break-through while the key is really there.
# This is the half a person can SEE, so it is the half that lies loudest.
promises=$(grep -cE 'break through' "$SETTINGS" || true)
if [[ "$promises" -gt 0 ]] && ! ts_key_present "$ENT_IOS"; then
  printf '  ✗ DRIFT: the quiet-hours row promises break-through with no entitlement (§83)\n'; fail=1
elif [[ "$promises" -gt 0 ]]; then
  printf '  ✓ the quiet-hours promise is backed by the entitlement\n'
else
  printf '  ✓ the quiet-hours row claims no break-through\n'
fi

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
// A price rise is an alarm, and the LOWEST-ranked one: the money already left,
// there is no clock on it, and it must never push a dispute or a deadline out
// of the one alarm slot a batch keeps. `severity` falls through to `default: 0`
// for anything unlisted, so an alarm added without its own case would silently
// tie with the arrivals and lose every tie-break — this asserts it didn't.
ok(NotifyKind.priceRose.cls == .alarm, "a price rise is an alarm")
ok(NotifyKind.priceRose.severity > 0, "a price rise has a real severity, not the default 0")

// ── the Walletbeat alarm's rank, and both of its boundaries (prd §422) ──────
// Asserted as a SANDWICH rather than against one neighbour: the ruling is that
// a flaw in the software holding your keys outranks one revocable approval and
// is outranked by a position actually about to be sold, and a test naming only
// one side would pass with the kind ranked off the end of the ladder.
ok(NotifyKind.walletIncident.cls == .alarm, "a wallet incident is an alarm")
ok(NotifyKind.walletIncident.severity > NotifyKind.approvalGranted.severity,
   "a flaw in the wallet itself outranks one revocable approval")
ok(NotifyKind.walletIncident.severity < NotifyKind.positionAtRisk.severity,
   "a disclosed risk is outranked by money actually about to be sold")
// No clock, so no Focus break — `positionAtRisk`'s own rule, for the same
// reason: a disclosure states no deadline, only a risk that may never land.
ok(!NotifyKind.walletIncident.isTimeSensitive,
   "a wallet incident never breaks a Focus — it carries no stated clock")
ok(NotifyKind.poolCleared.severity > NotifyKind.priceRose.severity, "good news outranks a rise already charged")
ok(!NotifyKind.priceRose.isTimeSensitive, "a price rise never breaks a Focus")

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
# The two boundaries of §422's rank, each mutated on its own — moving it to the
# top of the ladder is as wrong as burying it, and one fixture cannot say both.
mutate "a wallet incident sinks below a revocable approval" \
       's/case \.walletIncident:   return 82/case .walletIncident:   return 5/'
mutate "a wallet incident outranks a live liquidation" \
       's/case \.walletIncident:   return 82/case .walletIncident:   return 99/'
mutate "a wallet incident claims the Focus-breaking level" \
       's/self == \.disputeOpened \|\| self == \.deadlineNear/self == .disputeOpened || self == .deadlineNear || self == .walletIncident/'

mutate "the two groups share one count, so an alarm absorbs transfers" \
       's/matching: \{ \$0\.kind == \.moneyIn \}/matching: { \$0.cls != .whisper }/'

# ── NotifySweep.classify() — the actual bridge-specific dispatch ───────────
#
# Everything above tests NotifyPlan.swift's PURE judgement (severity, batching,
# quiet hours) — it has never once exercised NotifySweep.swift's classify(),
# the function that decides WHICH rows become notifications at all. That gap
# is real: classify() depends on the real `Thing` (a SwiftData @Model class)
# plus ASCVersionState/WalletIngest/StripeWatch/AppleWalletBridge, none of
# which a Foundation-only harness can compile against directly. This section
# compiles NotifySweep.swift and NotifyPlan.swift WHOLE AND UNMODIFIED against
# a plain stand-in Thing and minimal stubs for the other four types — the
# `retriever-selftest.sh`/`cursor-selftest.sh` shape, sized to what classify()
# actually touches.
#
# Scoped ON PURPOSE to the branches this pass ADDED (positionAtRisk,
# agentRunFailed, runningLow) — the pre-existing branches (ASC, wallet
# approvals, Privacy Pools, Peer, social, Apple Wallet, money-in, Stripe) are
# a real coverage gap too, but backfilling them is its own pass, not a side
# effect of this one; the stubs for those four types exist ONLY so the file
# compiles, and are not asserted against.
echo "── NotifySweep.classify() (the branches this pass added) ──"
sweepwork="$(mktemp -d)"
trap 'rm -rf "$sweepwork"' EXIT

cat > "$sweepwork/Stubs.swift" <<'SWIFT'
import Foundation

// A plain stand-in for the real `Thing` (Shared/Thing.swift) — every stored
// property `NotifySweep.swift` reads, nothing else. Not a SwiftData @Model:
// classify()/plans()/skipCensus()/art() never touch a ModelContext, only
// property values, so a plain class is the whole story.
final class Thing {
    var id = UUID()
    var sourceRef: String?
    var socialContext: String?
    var source: String = "You"
    var tags: [String] = []
    var dueAt: Date?
    var transferDirection: String?
    var transferUSD: Double?
    var isFlagged: Bool = false
    var isLive: Bool = true
    var capturedAt: Date = Date()
    var title: String = ""
    var previewImageData: Data?
    var authorAvatarURL: String?
}

// COMPILE-ONLY stand-ins for the four other types classify() names — real
// shapes live in AppStoreConnectBridge.swift/WalletIngest.swift/
// StripeBridge.swift/AppleWalletBridge.swift respectively. Good enough for
// the ASC/wallet-approval/Stripe/Apple-Wallet branches to COMPILE; this
// harness does not assert anything about those branches (see header above).
enum ASCVersionState: String {
    case rejected = "REJECTED", metadataRejected = "METADATA_REJECTED"
    case invalidBinary = "INVALID_BINARY", inReview = "IN_REVIEW"
    var alarming: Bool { self == .rejected || self == .metadataRejected || self == .invalidBinary }
}
enum WalletIngest { static let holdingFloor: Double = 1.0 }
enum StripeWatch { static let source = "Stripe" }
enum AppleWalletBridge { static let sourceName = "Apple Wallet" }

// Walletbeat (prd §422). These four ARE asserted against, unlike the
// compile-only stubs above, so each mirrors the real shape rather than merely
// satisfying the type checker. The BOOK is a plain in-memory dictionary here —
// the real one is UserDefaults-backed, which a harness cannot and should not
// reach; what is under test is the four gates, not the store.
enum WalletbeatSeverity: String, Comparable {
    case low = "LOW", medium = "MEDIUM", high = "HIGH", critical = "CRITICAL"
    private var order: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .critical: return 3
        }
    }
    static func < (a: Self, b: Self) -> Bool { a.order < b.order }
}
enum WalletbeatIncidentStatus: String {
    case ongoing = "ONGOING", mitigated = "MITIGATED"
    case resolved = "RESOLVED", unknown = "UNKNOWN"
    // Mirrors the shipped rule: mitigated is NOT resolved, and an unreadable
    // status is deliberately NOT open (the room head's conservative reading).
    var isOpen: Bool { self == .ongoing || self == .mitigated }
}
struct WalletbeatIncidentFacts {
    var slug: String
    var severity: WalletbeatSeverity?
    var status: WalletbeatIncidentStatus
    var wallets: [String]
}
enum WalletbeatNewsParse { static let refPrefix = "walletbeat:news:" }
enum WalletbeatWatch {
    static let walletPrefix = "walletbeat:wallet:"
    static func walletID(from thing: Thing) -> String? {
        guard let ref = thing.sourceRef, ref.hasPrefix(walletPrefix) else { return nil }
        return String(ref.dropFirst(walletPrefix.count))
    }
    static func isNewsRef(_ ref: String?) -> Bool {
        ref?.hasPrefix(WalletbeatNewsParse.refPrefix) ?? false
    }
}
enum WalletbeatIncidentBook {
    nonisolated(unsafe) static var stub: [String: WalletbeatIncidentFacts] = [:]
    static func all() -> [String: WalletbeatIncidentFacts] { stub }
    static func facts(ref: String?) -> WalletbeatIncidentFacts? {
        guard let ref, ref.hasPrefix(WalletbeatNewsParse.refPrefix) else { return nil }
        return stub[String(ref.dropFirst(WalletbeatNewsParse.refPrefix.count))]
    }
}
SWIFT

cat > "$sweepwork/main.swift" <<'SWIFT'
import Foundation

var checks = 0, bad = 0
func ok(_ cond: Bool, _ what: String) {
    checks += 1
    if !cond { bad += 1; print("  ✗ \(what)") }
}

func row(ref: String, source: String = "Wallet", tags: [String] = []) -> Thing {
    let t = Thing()
    t.sourceRef = ref
    t.source = source
    t.tags = tags
    return t
}

// `NotifySweep` is `@MainActor` (it drives real bridge reads elsewhere in the
// app); a bare command-line `main.swift`'s top-level code is nonisolated, so
// this runs the whole fixture pass through `assumeIsolated` — a runtime
// assertion that we're really on the main actor's executor, true here since
// this process is single-threaded and never hops.
@MainActor
func runFixtures() {
    let now = Date()

    // ── positionAtRisk: Aave/Morpho share `wallet:defi:`, Hyperliquid its own ──
    ok(NotifySweep.classify(row(ref: "wallet:defi:aave:ethereum:0xabc:1700000000"), now: now) == .positionAtRisk,
       "an Aave risk-crossing row classifies as positionAtRisk")
    ok(NotifySweep.classify(row(ref: "wallet:defi:morpho:base:0xabc:1700000000"), now: now) == .positionAtRisk,
       "a Morpho risk-crossing row classifies as positionAtRisk")
    ok(NotifySweep.classify(row(ref: "hyperliquid:risk:eth-0xabc:1700000000"), now: now) == .positionAtRisk,
       "a Hyperliquid liquidation-proximity row classifies as positionAtRisk")
    // A ROOM head or any other Wallet row outside the `wallet:defi:` namespace
    // must not be swallowed by a loose prefix.
    ok(NotifySweep.classify(row(ref: "wallet:approval:ethereum:0xabc:1700000000"), now: now) != .positionAtRisk,
       "an approval ref is not mistaken for a risk crossing")

    // ── agentRunFailed: Cursor, and ONLY the error outcome ────────────────────
    ok(NotifySweep.classify(row(ref: "cursor:agent:abc123", source: "Cursor", tags: ["Agent run", "Failed"]), now: now)
       == .agentRunFailed, "a Cursor run tagged Failed classifies as agentRunFailed")
    ok(NotifySweep.classify(row(ref: "cursor:agent:abc123", source: "Cursor", tags: ["Agent run", "Expired"]), now: now)
       == nil, "an Expired Cursor run does not alarm — administrative, not a failure")
    ok(NotifySweep.classify(row(ref: "cursor:agent:abc123", source: "Cursor", tags: ["Agent run", "Cancelled"]), now: now)
       == nil, "a Cancelled Cursor run does not alarm")
    ok(NotifySweep.classify(row(ref: "cursor:agent:abc123", source: "Cursor", tags: ["Agent run", "PR"]), now: now)
       == nil, "a successful Cursor run (no outcome tag) does not alarm")

    // ── runningLow: four bridges, one kind ─────────────────────────────────────
    ok(NotifySweep.classify(row(ref: "openrouter:credits:low:1700000000", source: "OpenRouter"), now: now)
       == .runningLow, "OpenRouter's low-credit crossing classifies as runningLow")
    ok(NotifySweep.classify(row(ref: "bitrefill:balance:low:1700000000", source: "Bitrefill"), now: now)
       == .runningLow, "Bitrefill's low-balance crossing classifies as runningLow")
    ok(NotifySweep.classify(row(ref: "stripe:runway:low:1700000000", source: "Stripe", tags: ["Runway"]), now: now)
       == .runningLow, "Stripe's runway-low crossing classifies as runningLow")
    ok(NotifySweep.classify(row(ref: "github:ratelimit:low:1700000000", source: "GitHub"), now: now)
       == .runningLow, "GitHub's rate-limit crossing classifies as runningLow")
    // The stripe:runway: prefix must win BEFORE the tag-based Stripe dispute/
    // silence block further down `classify` — a runway row carries no
    // "Dispute"/"Silence" tag, so if the prefix check didn't return early
    // this would fall through to nil instead.
    ok(NotifySweep.classify(row(ref: "stripe:runway:low:1700000000", source: "Stripe"), now: now) != nil,
       "a runway row is classified by its ref prefix, not by falling through to Stripe's tag checks")

    // ── Walletbeat: four gates, and each fixture fails ONE of them ────────────
    // Every case below is a real incident shape Walletbeat has published, and
    // each renders identically in the feed — the whole difference is whether
    // the right-hand slot is spent. `watched` deliberately holds a wallet that
    // is NOT the subject of most fixtures, so a gate that stops working shows
    // up as an alarm about somebody else's software.
    let watched: Set<String> = ["ledger", "rabby"]
    func incident(_ slug: String, _ severity: WalletbeatSeverity?,
                  _ status: WalletbeatIncidentStatus, _ wallets: [String]) -> Thing {
        WalletbeatIncidentBook.stub[slug] =
            WalletbeatIncidentFacts(slug: slug, severity: severity, status: status, wallets: wallets)
        return row(ref: "walletbeat:news:" + slug, source: "Walletbeat", tags: ["Vulnerability"])
    }

    ok(NotifySweep.classify(incident("a", .critical, .ongoing, ["ledger"]),
                            now: now, watchedWallets: watched) == .walletIncident,
       "a critical, ongoing incident naming a watched wallet alarms")
    ok(NotifySweep.classify(incident("b", .high, .mitigated, ["rabby"]),
                            now: now, watchedWallets: watched) == .walletIncident,
       "MITIGATED is still open — contained is not fixed, and your data is still out")
    ok(NotifySweep.classify(incident("c", .critical, .ongoing, ["safepal"]),
                            now: now, watchedWallets: watched) == nil,
       "a critical incident about a wallet you do not use never alarms")
    ok(NotifySweep.classify(incident("d", .critical, .ongoing, ["ledger"]),
                            now: now, watchedWallets: []) == nil,
       "FOLLOWING ALONE NEVER ALARMS — the whole free tier is feed rows")
    ok(NotifySweep.classify(incident("e", .medium, .ongoing, ["ledger"]),
                            now: now, watchedWallets: watched) == nil,
       "a medium-severity incident never alarms, however open")
    ok(NotifySweep.classify(incident("f", .critical, .resolved, ["ledger"]),
                            now: now, watchedWallets: watched) == nil,
       "a resolved incident never alarms")
    ok(NotifySweep.classify(incident("g", nil, .ongoing, ["ledger"]),
                            now: now, watchedWallets: watched) == nil,
       "an ungraded incident never alarms — an alarm we cannot grade, we do not send")
    // The BOOK, not `authorHandle`: an incident naming three wallets keeps only
    // the first on the row, so a join through the row would leave a Ledger user
    // unwarned about an incident filed under SafePal first.
    ok(NotifySweep.classify(incident("h", .critical, .ongoing, ["safepal", "ledger"]),
                            now: now, watchedWallets: watched) == .walletIncident,
       "a multi-wallet incident matches on ANY named wallet, not just the first")
    // A row whose facts were never recorded — a decode failure, or a book
    // cleared while its rows remain. Declines rather than guessing.
    ok(NotifySweep.classify(row(ref: "walletbeat:news:unknown-slug", source: "Walletbeat"),
                            now: now, watchedWallets: watched) == nil,
       "an incident with no recorded facts never alarms")
    // The OTHER two Walletbeat row shapes must not be swallowed by a loose
    // prefix — a watch row is a standing report card and a revision is
    // Walletbeat changing its own mind.
    ok(NotifySweep.classify(row(ref: "walletbeat:wallet:ledger", source: "Walletbeat"),
                            now: now, watchedWallets: watched) == nil,
       "a watched-wallet row is not an incident")
    ok(NotifySweep.classify(row(ref: "walletbeat:rev:ledger:keyStorage:FAIL:2026-08-20",
                                source: "Walletbeat", tags: ["Rating"]),
                            now: now, watchedWallets: watched) == nil,
       "a rating revision never alarms")

    // ── headline() never returns empty for a kind classify() can produce ──────
    for k: NotifyKind in [.positionAtRisk, .agentRunFailed, .runningLow, .walletIncident] {
        ok(!NotifySweep.headline(k).isEmpty, "\(k) has a non-empty headline")
    }
}

MainActor.assumeIsolated { runFixtures() }

if bad == 0 { print("  \(checks) assertions passed"); exit(0) }
print("  \(bad) of \(checks) FAILED")
exit(1)
SWIFT

cp "$PLAN" "$sweepwork/NotifyPlan.swift"
cp "$SWEEP" "$sweepwork/NotifySweep.swift"
rm -f "$sweepwork/harness"
( cd "$sweepwork" && swiftc -O -o harness Stubs.swift NotifyPlan.swift NotifySweep.swift main.swift 2>&1 | grep -E 'error:' || true )
if [[ -x "$sweepwork/harness" ]]; then
  "$sweepwork/harness" || fail=1
else
  echo "  ✗ classify() fixtures: did not compile"; fail=1
fi

if [[ $fail -eq 0 ]]; then
  echo "✓ notify self-test passed"
else
  echo "✗ notify self-test FAILED"
fi
exit $fail
