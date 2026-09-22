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
#   · a like that claims the level which breaks a Sleep Focus, because a kind
#     drifted into `isTimeSensitive` — the app runs no night rule of its own
#     since §870, so that level is the WHOLE of what may wake somebody
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
CARD="Casberi/Shared/NotifyCard.swift"
SWEEP="Casberi/Casberi/Model/NotifySweep.swift"
NOTIFY="Casberi/Casberi/Model/Notifications.swift"
for f in "$PLAN" "$CARD" "$SWEEP" "$NOTIFY"; do
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
guard "the digest still schedules for a future slot (a trigger, not a fire-now)" \
      'UNTimeIntervalNotificationTrigger' "$NOTIFY"
# The daily whisper was cut (prd §706) — a pending one from an older install
# must be pulled, or it fires once more with a tap that lands nowhere.
guard "a retired install's pending whisper is pulled by id" \
      'removePendingNotificationRequests\(withIdentifiers: \["whisper\.next"\]\)' "$NOTIFY"
guard "the attachment ladder falls to the source mark before nothing" \
      'brandAsset\(source\)' "$NOTIFY"
# Asset names here are plain ASCII, so a source with an accent in it ("Ethrex
# Hegotá") resolves to nothing and falls to rung 3 — an honest blank slot for a
# mark that exists. Silent, and it looks exactly like a source we never drew.
guard "the source mark folds diacritics, so an accented seat still finds its asset" \
      'diacriticInsensitive' "$NOTIFY"
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
  printf '  ✗ DRIFT: the settings copy promises break-through with no entitlement (§83)\n'; fail=1
elif [[ "$promises" -gt 0 ]]; then
  printf '  ✓ the break-through promise is backed by the entitlement\n'
else
  printf '  ✓ the settings copy claims no break-through\n'
fi

# §870 deleted quiet hours — switch, window and hold. It may not creep back in
# as an unswitched internal rule, which is the shape it would take: a `Quiet`
# window nobody can see, holding the two standsAlone kinds that have no clock
# (a liquidation, a Safe signature) until a morning that is hours too late.
# iOS's own Focus is the night rule now, and `.timeSensitive` is the one lever
# into it — guarded above, against the entitlement.
back=0
for f in "$PLAN" "$NOTIFY" "$SETTINGS"; do
  # The identifiers only, and `quiet:` ANCHORED to an argument position — a
  # bare `quiet:` matches ordinary prose ("payments went quiet: …", which this
  # tree already writes elsewhere) and would red a ship gate over a comment.
  if grep -nE 'holdUntil|NotifyRules\.Quiet|quiet(On|Start|End)"|[(,][[:space:]]*quiet:' "$f" >/dev/null 2>&1; then
    printf '  ✗ DRIFT: quiet hours are back in %s (§870 deleted them)\n' "$f"; fail=1; back=1
  fi
done
# An `&&` list rather than an `if` would return non-zero when drift IS found,
# and `set -e` would take the whole script down there — the right verdict by
# the wrong door, with every later check skipped.
if [[ "$back" -eq 0 ]]; then
  printf '  ✓ no quiet-hours hold anywhere (§870)\n'
fi

# ── the two devnets (prd §522) ──────────────────────────────────────────────
# The compiled half above proves the RULES. These guard the wiring it cannot
# see — and the wiring is where both seats failed before this pass: Hegotá
# lands no `Thing` at all (§500), so nothing it learned could ever reach a lock
# screen, and no audit in this repo could have reported that as a gap.
DEVNET="Casberi/Casberi/Model/DevnetNotify.swift"
VIB="Casberi/Casberi/Model/VibenetBridge.swift"
HEG="Casberi/Casberi/Model/HegotaBridge.swift"
FRAMESB="Casberi/Casberi/Model/FramesBridge.swift"
DRIVER="Casberi/Casberi/Model/VibenetUnlockActivityDriver.swift"
BG="Casberi/Casberi/Model/WalletBackgroundRefresh.swift"
for f in "$DEVNET" "$VIB" "$HEG" "$FRAMESB" "$DRIVER" "$BG"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

guard "the headline has ONE authority, forwarded from the sweep" \
      'static func headline\(_ kind: NotifyKind\) -> String \{ kind\.headline \}' "$SWEEP"

# A seat name that does not equal the source the bridge really stamps fails at
# NEITHER end: the notification arrives with a blank right-hand slot and its tap
# opens the All feed. Derived from the bridges rather than typed twice here.
for pair in "vibenet:$VIB" "Hegotá:$HEG" "Frames:$FRAMESB"; do
  label="${pair%%:*}"; file="${pair#*:}"
  src=$(grep -oE 'static let source = "[^"]+"' "$file" | head -1 | sed 's/.*"\(.*\)"/\1/')
  if [[ -n "$src" ]] && grep -qF "return \"$src\"" "$PLAN"; then
    printf '  ✓ %s'"'"'s seat name is the source its bridge really stamps\n' "$label"
  else
    printf '  ✗ DRIFT: NotifyDevnet.Seat does not spell %s'"'"'s source (%s) the way %s does\n' \
           "$label" "$src" "$file"; fail=1
  fi
done

# Both windows are restated in the Foundation-only file because it cannot see
# the other two. Restated is fine; DIVERGED is a notification that outlives the
# sentence it points at, or one the corpus sweep would have called stale.
guard "the devnet news window is the corpus sweep's own 36 hours" \
      'static let newsWindow: TimeInterval = 36 \* 3600' "$PLAN"
guard "…and the corpus sweep still uses that number" \
      'static let newsWindow: TimeInterval = 36 \* 3600' "$SWEEP"
guard "a reset stays sayable exactly as long as the room keeps saying it" \
      'static let sayItFor: TimeInterval = 7 \* 86_400' "$VIB"
guard "…and the notification uses that same week" \
      'static let resetWindow: TimeInterval = 7 \* 86_400' "$PLAN"

# ONE submit, so a devnet alarm competes in the same batch as every other alarm
# instead of arriving as a second buzz beside a dispute.
guard "the devnet plans ride the corpus sweep's one submit" \
      'Notifications\.submit\(plans \+ devnet' "$BG"
guard "the unlock book is pruned only after that submit" \
      'DevnetNotify\.prune\(\)' "$BG"

# §522's two halves of the sticky record: without the KEY the ledger cannot tell
# one wipe from the next, and the room's own date alone would announce the same
# reset on every pass forever.
guard "a reset stores the key that makes it announceable once" \
      'UserDefaults\.standard\.set\(key, forKey: resetKeyKey\)' "$VIB"
guard "…and Hegotá stamps its relaunch once per genesis hash, not per sweep" \
      'if UserDefaults\.standard\.string\(forKey: Self\.restartHashKey\) != hash' "$HEG"
guard "accepting the relaunch forgets the observation with it" \
      'removeObject\(forKey: Self\.restartHashKey\)' "$HEG"

# §473's control, as the notification's consent record.
guard "tracking is recorded only when an activity really started" \
      'VibenetUnlockBook\.record\(address: address, name: name, unlocksAt: unlocksAt\)' "$DRIVER"
# The forget must come BEFORE the `guard let activity`, or stopping a tracker
# whose handle died with the process leaves the notification armed.
forget_line=$(grep -nF 'VibenetUnlockBook.forget(address: address)' "$DRIVER" | head -1 | cut -d: -f1)
guard_line=$(grep -nF 'guard let activity = live.removeValue' "$DRIVER" | head -1 | cut -d: -f1)
if [[ -n "$forget_line" && -n "$guard_line" && "$forget_line" -lt "$guard_line" ]]; then
  printf '  ✓ stopping forgets the consent even with no handle left to end\n'
else
  printf '  ✗ DRIFT: finish() returns before forgetting the unlock book (§522)\n'; fail=1
fi
# A ROOM READ is not the person's tap. `reconcile` calling `finish` with the
# default would forget an entry whose delay had just ELAPSED — silently deleting
# the one thing that pass was about to announce, on the pass where it mattered.
guard "a room reconcile forgets a PENDING entry only, never a finished one" \
      'finish\(address: address, withdrawingConsent: false\)' "$DRIVER"

# THE GATHERER HOLDS NO RULE. Every threshold lives in the compiled file; one
# that drifted down here would be a rule no harness could ever reach — which is
# the whole reason this feature is split the way it is. Read from a
# COMMENT-STRIPPED copy: the file documents these rules by naming them.
devnet_code=$(sed 's://.*::' "$DEVNET")
if print -r -- "$devnet_code" | grep -qE 'TimeInterval|86_400|3600'; then
  printf '  ✗ DRIFT: DevnetNotify carries a window of its own — the rules belong in NotifyPlan.swift\n'; fail=1
else
  printf '  ✓ the gathering half holds no thresholds of its own\n'
fi

# ── the digest's wiring (prd §770) ──────────────────────────────────────────
# The compiled half proves the queue and the words; these guard the one door
# that decides which plans go where, and the promise the settings page makes.
guard "submit sends alone only the kinds that stand alone" \
      'eligible\.filter \{ \$0\.kind\.standsAlone \}' "$NOTIFY"
guard "…and everything else goes through the digest's one step" \
      'NotifyDigest\.advance\(previous' "$NOTIFY"
guard "a category switched off filters the digest's queue too" \
      'allowed: \{ s\.allows\(category: \$0\.category\) \}' "$NOTIFY"
guard "the digest is scheduled for the learned reading hour (prd §809)" \
      'slots: NotifyDigest\.readingSlots\(opens: opens' "$NOTIFY"
guard "…which learns from every foreground activation" \
      'Notifications\.recordOpen\(\)' Casberi/Casberi/Shell/RootShell.swift
guard "the digest is ranked by the most urgent thing inside it" \
      'content\.relevanceScore = NotifyDigest\.relevance\(group\)' "$NOTIFY"
guard "a several-thing digest carries its card and answers to the extension's category" \
      'content\.categoryIdentifier = NotifyCard\.category' "$NOTIFY"
guard "the extension answers to the same category the app sets" \
      '<string>digest</string>' Casberi/NotificationContent/Info.plist
guard "the card's pictures ride the notification as attachments, the tile sheet first (§809a)" \
      'identifier: NotifyCard\.headAttachment' "$NOTIFY"
guard "the extension reads its pictures from the notification's attachments" \
      'Self\.images\(notification\.request\.content\.attachments\)' Casberi/NotificationContent/NotificationViewController.swift
# §809a: the extension needs NO app group. Linking one to a new identifier is a
# portal-only step no API can do, and it blocked the first iOS ship of this
# target; an entitlement, a shared suite or a shared folder brings it back.
if [[ -e Casberi/NotificationContent/NotificationContent.entitlements ]] \
   || grep -qE 'SharedStore\.|suiteName|containerURL' Casberi/NotificationContent/*.swift \
   || grep -q 'NotificationContent/NotificationContent.entitlements' Casberi/Casberi.xcodeproj/project.pbxproj; then
  printf '  ✗ DRIFT: the NotificationContent extension reaches for an app group again (§809a)\n'; fail=1
else
  printf '  ✓ the NotificationContent extension carries no entitlement and reads no shared store (§809a)\n'
fi
guard "the settings footnote names the four kinds that stand alone" \
      'A dispute, a deadline, a liquidation or a Safe signature comes at once' "$SETTINGS"
# `hasOwnApp` only orders the names, so a misspelt seat fails at nothing: that
# app is simply named first as if it had no lock screen of its own.
CATALOG="Casberi/Casberi/Model/BridgeCatalog.swift"
own=$(perl -0ne 'print $1 if /static let hasOwnApp: Set<String> = \[(.*?)\n    \]/s' "$PLAN" | grep -oE '"[^"]+"' | tr -d '"' || true)
if [[ -z "$own" ]]; then
  printf '  ✗ DRIFT: NotifyDigest.hasOwnApp could not be read\n'; fail=1
else
  missing=()
  for n in ${(f)own}; do
    grep -qF "name: \"$n\"" "$CATALOG" || missing+=("$n")
  done
  if (( ${#missing} == 0 )); then
    printf '  ✓ every app named as having its own lock screen is a catalog seat\n'
  else
    printf '  ✗ DRIFT: NotifyDigest.hasOwnApp names seats the catalog lacks: %s\n' "${missing[*]}"; fail=1
  fi
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
ok(NotifyClass.allCases.count == 2, "two classes and no third (the whisper is cut, prd §706)")

// ── time-sensitive is claimed by exactly two kinds ──────────────────────────
let ts = NotifyKind.allCases.filter(\.isTimeSensitive)
ok(Set(ts) == [.disputeOpened, .deadlineNear], "only the deadline alarms are time-sensitive")
ok(!NotifyKind.moneyIn.isTimeSensitive, "money arriving never breaks a Focus")

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
// Arrivals ride alongside. Since prd §770 they never reach `collapse` in the
// app (the digest takes them), and the rule still leaves them untouched.
let mixed = [plan(.poolCleared, id: "a"), plan(.disputeOpened, id: "b"),
             plan(.moneyIn, id: "m"), plan(.likesReceived, id: "l")]
let mixedOut = NotifyRules.collapse(mixed)
ok(mixedOut.count == 3, "one alarm plus both arrivals survive")
ok(mixedOut.filter { $0.cls == .arrival }.count == 2, "no arrival is ever collapsed away")
let coins = [plan(.moneyIn, id: "m1", at: at(9)), plan(.moneyIn, id: "m2", at: at(10))]
ok(NotifyRules.collapse(coins).count == 2,
   "money no longer collapses here: the digest counts it (prd §770)")

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

// ── the two devnets (prd §522) ──────────────────────────────────────────────
// Hegotá lands no `Thing` at all (§500) and vibenet's two chain-wide clocks
// belong to no row, so `NotifySweep.classify` structurally cannot reach any of
// this — and nothing in this repo can make a devnet reset, a timelock elapse or
// a timelock elapse on demand. These fixtures are not the best proof the rules
// hold; they are the only one.
let dnow = at(12)

func reset(_ seat: NotifyDevnet.Seat, key: String = "id-1-2",
           observed: Date = at(11), watching: Int = 2) -> NotifyDevnet.Reset {
    NotifyDevnet.Reset(seat: seat, key: key, observedAt: observed, watching: watching)
}
ok(NotifyDevnet.plan(reset: reset(.vibenet), now: dnow) != nil,
   "a reset observed an hour ago is news")
ok(NotifyDevnet.plan(reset: reset(.vibenet, watching: 0), now: dnow) == nil,
   "NOBODY WATCHING, NOTHING TO SAY — a reset is only news about someone who had something there")
ok(NotifyDevnet.plan(reset: reset(.vibenet, observed: dnow.addingTimeInterval(60)), now: dnow) == nil,
   "an observation from the FUTURE never fires (a clock that moved under us)")
ok(NotifyDevnet.plan(reset: reset(.vibenet, observed: dnow.addingTimeInterval(-8 * 86_400)), now: dnow) == nil,
   "a reset older than the week the room keeps explaining it never fires")
ok(NotifyDevnet.plan(reset: reset(.vibenet, observed: dnow.addingTimeInterval(-6 * 86_400)), now: dnow) != nil,
   "…and one inside that week still does")
// The id is the whole of "fires once, ever" — and of a SECOND wipe being news.
let dr1 = NotifyDevnet.plan(reset: reset(.vibenet, key: "id-1-2", observed: at(9)), now: dnow)!
let dr2 = NotifyDevnet.plan(reset: reset(.vibenet, key: "id-1-2", observed: at(11)), now: dnow)!
ok(dr1.id == dr2.id, "the same reset keeps ONE id however often the sticky record is re-read")
let dr3 = NotifyDevnet.plan(reset: reset(.vibenet, key: "id-2-3"), now: dnow)!
ok(dr3.id != dr1.id, "a SECOND reset is a different id, so it is new news")
let drh = NotifyDevnet.plan(reset: reset(.hegota), now: dnow)!
ok(drh.id != dr1.id, "the two seats never share an id")
ok(dr1.source == "Base Vibenet" && drh.source == "Hegotá UTXO",
   "each plan carries its own seat's source, so the right-hand slot gets its mark")
ok(dr1.body.contains("addresses"),
   "vibenet's body says the ADDRESS survives — §515a's easily-missed half")
ok(dr1.cls == .alarm && !dr1.isTimeSensitive,
   "a devnet reset is an alarm that never breaks a Focus")

func unlock(tracked: Bool = true, opensAt: Date = at(11),
            address: String = "0xAbCd") -> NotifyDevnet.Unlock {
    NotifyDevnet.Unlock(address: address, name: "Treasury", unlocksAt: opensAt, tracked: tracked)
}
ok(NotifyDevnet.plan(unlock: unlock(), now: dnow) != nil, "a timelock that ended an hour ago is news")
ok(NotifyDevnet.plan(unlock: unlock(tracked: false), now: dnow) == nil,
   "§473: an account merely WATCHED never reaches a lock screen")
ok(NotifyDevnet.plan(unlock: unlock(opensAt: at(13)), now: dnow) == nil,
   "a delay still running is the Live Activity's job, not a notification's")
ok(NotifyDevnet.plan(unlock: unlock(opensAt: dnow.addingTimeInterval(-40 * 3600)), now: dnow) == nil,
   "a window that opened days ago is not news")
let du1 = NotifyDevnet.plan(unlock: unlock(address: "0xAbCd"), now: dnow)!
let du2 = NotifyDevnet.plan(unlock: unlock(address: "0xabcd"), now: dnow)!
ok(du1.id == du2.id, "the id is case-folded — an RPC's casing is not a promise")
ok(NotifyDevnet.plan(unlock: unlock(opensAt: at(11, 30)), now: dnow)!.id != du1.id,
   "a SECOND unlock at a new instant is new news")
ok(du1.body.contains("Treasury"), "the body names the account")

// Each seat's door must PARSE. Both names carry a space and one an accent, so
// an unencoded link is one `URL(string:)` hands back as nil — a tap that opens
// the app on whatever room it was already showing.
for seat in NotifyDevnet.Seat.allCases {
    ok(URL(string: seat.link)?.pathComponents.last == seat.source,
       "\(seat) links to its own room, percent-encoded so URL() can parse it back")
}

// Composed together, in a stable order, and then batched like any other alarm.
let dAll = NotifyDevnet.plans(resets: [reset(.vibenet)], unlocks: [unlock()], now: dnow)
ok(dAll.count == 2, "both compose together")
ok(dAll.map(\.kind) == [.chainReset, .unlockReady], "…in a stable order")
let dCollapsed = NotifyRules.collapse(dAll)
ok(dCollapsed.count == 1, "two devnet alarms collapse to one, like any other alarm")
ok(dCollapsed[0].kind == .chainReset, "…and the reset is the one that survives")

// ── where the three sit on the ladder, both boundaries each ─────────────────
ok(NotifyKind.paymentsSilent.severity > NotifyKind.chainReset.severity,
   "a devnet reset never outranks revenue that stopped — no real money is involved")
ok(NotifyKind.chainReset.severity > NotifyKind.poolCleared.severity,
   "…and it outranks good news you can act on whenever")
ok(NotifyKind.poolCleared.severity > NotifyKind.unlockReady.severity,
   "real money out of a pool outranks a devnet's timelock")
ok(NotifyKind.unlockReady.severity > NotifyKind.priceRose.severity,
   "…which still outranks a charge already taken")
for k: NotifyKind in [.chainReset, .unlockReady] {
    ok(k.cls == .alarm, "\(k) is an alarm")
    ok(k.severity > 0, "\(k) has a real severity, not the default 0 that ties with arrivals")
    ok(!k.isTimeSensitive, "\(k) never breaks a Focus — none of them states a clock still running")
}
// The headline moved onto the kind (§522) and `NotifySweep.headline` forwards,
// so EVERY kind must answer — not only the ones a switch happened to list.
for k in NotifyKind.allCases { ok(!k.headline.isEmpty, "\(k) has a non-empty headline") }

// ── the dateline: the event's own time, only when delivery lags it (prd §713) ─
var gmt = Calendar(identifier: .gregorian); gmt.timeZone = TimeZone(identifier: "UTC")!
gmt.locale = Locale(identifier: "en_US_POSIX")
func utc(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
    var c = DateComponents(); c.year = 2026; c.month = 8; c.day = d; c.hour = h; c.minute = m
    return gmt.date(from: c)!
}
ok(NotifyRules.datelinePhrase(occurredAt: utc(5, 9, 0), deliveredAt: utc(5, 9, 40), calendar: gmt) == nil,
   "inside an hour the OS's own stamp is enough — no dateline")
ok(NotifyRules.datelinePhrase(occurredAt: utc(4, 23, 52), deliveredAt: utc(5, 8, 0), calendar: gmt) == "last night at 11:52",
   "a like found by a late-running background task says last night, not now")
ok(NotifyRules.datelinePhrase(occurredAt: utc(5, 9, 14), deliveredAt: utc(5, 13, 0), calendar: gmt) == "this morning at 9:14",
   "a same-day lag names the part of the day")
ok(NotifyRules.datelinePhrase(occurredAt: utc(4, 15, 5), deliveredAt: utc(5, 8, 0), calendar: gmt) == "yesterday afternoon at 3:05",
   "yesterday before nine at night is yesterday, not last night")
ok(NotifyRules.datelinePhrase(occurredAt: utc(1, 10, 0), deliveredAt: utc(5, 10, 0), calendar: gmt)?.hasPrefix("Saturday") == true,
   "within a week the weekday is named")
ok(NotifyRules.datelinePhrase(occurredAt: utc(5, 9, 0), deliveredAt: utc(5, 8, 0), calendar: gmt) == nil,
   "an event stamped after delivery never draws a dateline")

// ── the digest (prd §770) ───────────────────────────────────────────────────
// Everything that does not stand alone becomes ONE notification per category,
// all at one slot a day. Each failure here renders as an ordinary notification:
// the same things told twice, a digest at 03:00, a category switched off that
// still speaks, two categories folded into one, or a second delivery in a day
// the settings footnote promised would not come.
ok(Set(NotifyKind.allCases.filter(\.standsAlone)) ==
   [.disputeOpened, .deadlineNear, .positionAtRisk, .safeSignatureNeeded],
   "exactly four kinds stand alone; everything else waits for the digest")
ok(Set(ts).isSubset(of: Set(NotifyKind.allCases.filter(\.standsAlone))),
   "a kind that pierces a Focus never waits for the evening slot")
ok(NotifyKind.digest.cls == .arrival && !NotifyKind.digest.standsAlone,
   "the digest's own kind is an arrival and never stands alone")
ok(NotifyDigest.slots.count == 1, "one slot a day, and no second")

func tomorrow(_ d: Date) -> Date { cal.date(byAdding: .day, value: 1, to: d)! }
ok(NotifyDigest.nextSlot(after: at(7), calendar: cal) == at(18),
   "the morning waits for the evening slot")
ok(NotifyDigest.nextSlot(after: at(18), calendar: cal) == tomorrow(at(18)),
   "a slot that is now has passed, so tomorrow evening is next")
ok(NotifyDigest.nextSlot(after: at(19), calendar: cal) == tomorrow(at(18)),
   "after the evening slot, tomorrow evening")
// The learned reading hour (§770) is the only thing that moves a slot since
// §870, and it is handed in — so the walk must honour a slot that is not the
// default, on both sides of it.
ok(NotifyDigest.nextSlot(after: at(12), calendar: cal, slots: [17 * 60]) == at(17),
   "a learned earlier hour is the slot, not the default 18:00")
ok(NotifyDigest.nextSlot(after: at(19), calendar: cal, slots: [17 * 60]) == tomorrow(at(17)),
   "…and once it has passed, tomorrow's")
// Every slot this file can choose is inside the evening window, which is the
// reason §870's deletion costs nothing: a digest cannot land at night.
ok(NotifyDigest.slots.allSatisfy { NotifyDigest.readingWindow.contains($0) },
   "the fixed slot is inside the evening window")
// Unreachable today, and it may not fail LOUD if it ever becomes reachable:
// the caller schedules on `slot - now`, so a `now` here would fire the digest
// on the spot.
ok(NotifyDigest.nextSlot(after: at(12), calendar: cal, slots: []) > at(23),
   "no slot at all waits a day rather than buzzing now")

func item(_ id: String, _ seat: String, at when: Date, category: String = "Work") -> NotifyDigest.Item {
    NotifyDigest.Item(id: id, seat: seat, name: seat, category: category,
                      kind: NotifyKind.moneyIn.rawValue, title: "t-\(id)", body: "b-\(id)",
                      link: "casberi://thing/\(id)", occurredAt: when, source: seat)
}
let everything: (NotifyDigest.Item) -> Bool = { _ in true }
let s0 = NotifyDigest.State()
let s1 = NotifyDigest.advance(s0, adding: [item("a", "Stripe", at: at(10))], allowed: everything,
                              now: at(10), calendar: cal)
ok(s1.queue.count == 1 && s1.slot == at(18), "the first arrival queues for the evening slot")
let s2 = NotifyDigest.advance(s1, adding: [item("b", "GitHub", at: at(12))], allowed: everything,
                              now: at(12), calendar: cal)
ok(s2.queue.count == 2 && s2.slot == at(18), "a second arrival joins the same slot")
var grown = item("a", "Stripe", at: at(13)); grown.title = "grown"
let s2b = NotifyDigest.advance(s2, adding: [grown], allowed: everything,
                               now: at(13), calendar: cal)
ok(s2b.queue.count == 2 && s2b.queue.contains { $0.title == "grown" },
   "the same id REPLACES its queued item, so a growing like is one line")
let s3 = NotifyDigest.advance(s2, adding: [], allowed: everything,
                              now: at(19), calendar: cal)
ok(s3.queue.isEmpty && s3.slot == nil, "after its slot, a delivered digest is never announced again")
let s4 = NotifyDigest.advance(s2, adding: [item("c", "X", at: at(19))], allowed: everything,
                              now: at(19), calendar: cal)
ok(s4.queue.map(\.id) == ["c"] && s4.slot == tomorrow(at(18)),
   "an arrival after the evening slot starts tomorrow's digest on its own")
let s5 = NotifyDigest.advance(s2, adding: [], allowed: { $0.category != "Work" },
                              now: at(12), calendar: cal)
ok(s5.queue.isEmpty && s5.slot == nil, "switching a category off takes its queued items with it")
// A slot still ahead of us is KEPT, learned hour and all: the queue grew, but
// the evening it waits for did not move. `at(17)` is a slot only the learned
// reading hour can produce, so a re-chosen one would read as 18:00 and be
// caught.
let s6 = NotifyDigest.advance(NotifyDigest.State(queue: [item("a", "Stripe", at: at(9))], slot: at(17)),
                              adding: [item("b", "GitHub", at: at(12))], allowed: everything,
                              now: at(12), calendar: cal)
ok(s6.slot == at(17) && s6.queue.count == 2, "a slot still ahead of us is kept, not re-chosen")
let big = (0..<(NotifyDigest.cap + 5)).map { item("n\($0)", "RSS", at: at(10)) }
let s7 = NotifyDigest.advance(s0, adding: big, allowed: everything, now: at(10), calendar: cal)
ok(s7.queue.count == NotifyDigest.cap && s7.queue.first?.id == "n5",
   "the queue is bounded, oldest dropped first")

ok(NotifyDigest.plan([]) == nil, "an empty queue sends nothing")
let lone = NotifyDigest.plan([item("a", "Stripe", at: at(10))])!
ok(lone.title == "t-a" && lone.body == "b-a" && lone.link == "casberi://thing/a",
   "one item is simply that item: its own words and its own door")
ok(lone.place == "Stripe", "…and it says where it came from")
let oneApp = NotifyDigest.plan([item("a", "Stripe", at: at(10)), item("b", "Stripe", at: at(11))])!
ok(oneApp.kind == .digest && oneApp.title == "Stripe: 2 transfers in",
   "one app with several things says its name, a colon, and the count by kind")
ok(oneApp.body == "t-b\nt-a", "…and when each thing fits on a line, the body is the things themselves, newest first")
ok(oneApp.link == "casberi://feed/source/Stripe", "…and opens that app's room")
let four = NotifyDigest.plan([item("s", "Stripe", at: at(10)), item("g", "GitHub", at: at(11)),
                              item("w", "Wallet", at: at(9)), item("x", "X", at: at(12))])!
ok(four.title == "Work: 4 transfers in",
   "several apps say their category, a colon, and how many")
ok(four.link == "casberi://feed", "…and open All")
ok(four.body == "Wallet: 1 transfer in\nAnd 3 more",
   "several apps are a line each, an app with no lock screen of its own first, and past the cap the rest is counted")
let six = NotifyDigest.plan(["A", "B", "C", "D", "E", "F"].enumerated().map {
    item("i\($0.offset)", $0.element, at: at(8 + $0.offset))
})!
ok(six.body.components(separatedBy: "\n").count == NotifyDigest.bodyLineCap,
   "however many apps, the body holds no more lines than the banner shows")

ok(NotifyDigest.plans([]).isEmpty, "no category queued, no notification")
let split = NotifyDigest.plans([item("s", "Stripe", at: at(10), category: "Money"),
                                item("g", "GitHub", at: at(11)), item("l", "Linear", at: at(12))])
ok(split.map(\.title) == ["t-s", "Work: 2 transfers in"],
   "one notification per category, in name order, never one for all of them")
let twoRooms = NotifyDigest.plans([item("a", "Stripe", at: at(10), category: "Money"),
                                   item("b", "Stripe", at: at(11), category: "Money"),
                                   item("c", "GitHub", at: at(10)), item("d", "GitHub", at: at(11))])
ok(twoRooms.count == 2 && Set(twoRooms.map(\.id)).count == 2,
   "two categories' digests never share an id, so neither replaces the other")

let headlined = NotifyDigest.plan((0..<5).map { item("h\($0)", "Bluesky", at: at(8 + $0)) })!
ok(headlined.body == "t-h4 and 4 more",
   "more things than lines: the newest one, and how many more")

func pictured(_ id: String, _ seat: String, at when: Date,
              picture: String? = nil, mark: String? = nil) -> NotifyDigest.Item {
    var i = item(id, seat, at: when); i.picture = picture; i.mark = mark; return i
}
let thumb: [NotifyDigest.Tile] = NotifyDigest.tiles([
    pictured("p1", "Stripe", at: at(10)), pictured("p2", "Stripe", at: at(11)),
    pictured("f1", "Bluesky", at: at(12), picture: "https://a/1.jpg"),
    pictured("f2", "Bluesky", at: at(13), picture: "https://a/1.jpg"),
    pictured("u", "Wallet", at: at(9), mark: "USDC"),
    pictured("f3", "X", at: at(14), picture: "https://b/2.jpg"),
    pictured("g", "GitHub", at: at(8)),
])
ok(thumb.count == NotifyDigest.tileCap && !thumb.contains(.mark("GitHub")),
   "the thumbnail holds four tiles, and the oldest is left out")
ok(thumb.first == .picture(url: "https://b/2.jpg", source: "X"),
   "a face leads when the newest thing has one, mixed with the marks")
ok(thumb.filter { $0 == .picture(url: "https://a/1.jpg", source: "Bluesky") }.count == 1
   && thumb.filter { $0 == .mark("Stripe") }.count == 1,
   "the same face or the same mark is drawn once")
ok(thumb.contains(.mark("USDC")) && !thumb.contains(.mark("Wallet")),
   "an item's own mark wins over its app's")

func kinded(_ id: String, _ seat: String, _ kind: NotifyKind, title: String? = nil,
            body: String, who: String? = nil, usd: Double? = nil,
            at when: Date, category: String = "Social") -> NotifyDigest.Item {
    var i = item(id, seat, at: when, category: category)
    i.kind = kind.rawValue; i.title = title ?? kind.headline; i.body = body; i.who = who; i.usd = usd; return i
}

// ── words that fit (prd §809) ───────────────────────────────────────────────
// "No truncation ellipsis in the title or the bodies" and no app named twice.
let people = ["linda", "jesse", "anna", "rafa", "sam"]
let replies = people.enumerated().map {
    kinded("r\($0.offset)", "Farcaster", .repliesReceived,
           body: "a reply long enough that it would never fit on a lock screen line on its own",
           who: $0.element, at: at(12 - $0.offset))
} + [kinded("f0", "Farcaster", .followersGained, body: "mira.eth followed you", who: "mira.eth", at: at(7)),
     kinded("f1", "Farcaster", .followersGained, body: "kai followed you", who: "kai", at: at(6))]
let social = NotifyDigest.plan(replies)!
ok(social.title == "Farcaster: 5 replies +2",
   "the title steps down to the top kind and how many more when both kinds do not fit")
ok(social.body == "linda, jesse and 3 more replied\nmira.eth and kai followed you",
   "a kind with people says who, as many names as fit, instead of pasting a reply that runs past the edge")
ok(NotifyDigest.named(["a", "b"], verb: "replied").first == "a and b replied",
   "two names are joined as a list, not counted")
let liked = kinded("l", "Bluesky", .likesReceived, title: "Liked by linda and 4 others", body: "my post", at: at(9))
ok(liked.line == "Liked by linda and 4 others", "a title the plan wrote itself is the news, and stays")
ok(kinded("e", "X", .repliesReceived, body: "", at: at(9)).line == NotifyKind.repliesReceived.headline,
   "…and a row with no words of its own keeps its headline rather than a blank line")

let paid = [kinded("m1", "Wallet", .moneyIn, body: "0.42 ETH from mira.eth", usd: 980, at: at(10), category: "Wallet"),
            kinded("m2", "Wallet", .moneyIn, body: "250 USDC from coinbase.eth", usd: 250, at: at(11), category: "Wallet"),
            kinded("m3", "Wallet", .moneyIn, body: "10 USDC from a.eth", usd: 10, at: at(9), category: "Wallet")]
let money = NotifyDigest.plan(paid)!
ok(money.title == "Wallet: +$1,240", "money arrived leads with the dollars")
ok(money.body == "Largest: 0.42 ETH from mira.eth",
   "several transfers that do not all fit say the largest")
var unpriced = paid; unpriced[2].usd = nil
ok(NotifyDigest.plan(unpriced)!.title == "Wallet: 3 transfers in",
   "one transfer without a price and there is no total, because a partial sum is not the total")

// The property the user asked for, over every fixture above and a worst case.
let long = (0..<9).map { kinded("z\($0)", "App\($0 % 4)", NotifyKind.allCases[$0 % NotifyKind.allCases.count],
                                body: String(repeating: "word ", count: 20), at: at(8), category: "Work") }
for p in [oneApp, four, six, social, money, headlined, NotifyDigest.plan(long)!] {
    let bodyLines = p.body.components(separatedBy: "\n")
    ok(p.title.count <= NotifyDigest.titleBudget, "a digest title fits one line: \(p.title)")
    ok(bodyLines.count <= NotifyDigest.bodyLineCap && bodyLines.allSatisfy { $0.count <= NotifyDigest.lineBudget },
       "a digest body fits the banner, no line past the edge: \(p.body)")
}
let apps4 = NotifyDigest.plan(long)!.body
let appLinesOnly = apps4.components(separatedBy: "\n").filter { $0.contains(":") }
ok(Set(appLinesOnly.compactMap { $0.components(separatedBy: ":").first }).count == appLinesOnly.count,
   "no app is named on two lines")
ok(NotifyDigest.plan(long)!.title == "Work: 9 new",
   "a top kind that is a sliver of the day does not lead the title")

ok(NotifyKind.repliesReceived.counted(1) == "1 reply" && NotifyKind.repliesReceived.counted(3) == "3 replies",
   "one is singular and more is plural, spelled out rather than inflected")

// ── the rank (prd §809) ─────────────────────────────────────────────────────
ok(NotifyDigest.relevance([kinded("a", "W", .moneyIn, body: "a", at: at(9)),
                           kinded("b", "W", .approvalGranted, body: "b", at: at(9))])
   == Double(NotifyKind.approvalGranted.severity) / 100,
   "a digest ranks by the most urgent thing inside it")
ok(NotifyDigest.relevance([kinded("a", "W", .likesReceived, body: "a", at: at(9))])
   < NotifyDigest.relevance([kinded("b", "W", .moneyIn, body: "b", at: at(9))]),
   "…so money outranks a like in the summary")
ok(NotifyKind.allCases.filter { $0.severity == 0 }.allSatisfy { $0.digestRank < NotifyKind.runningLow.severity },
   "every arrival ranks below every alarm")

// ── the reading hour (prd §809) ─────────────────────────────────────────────
func evening(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
    cal.date(byAdding: .day, value: -day, to: cal.date(bySettingHour: hour, minute: minute, second: 0, of: at(12))!)!
}
let habit = [evening(1, 20, 10), evening(1, 21, 30), evening(2, 20, 40), evening(3, 19, 55), evening(4, 8, 0)]
ok(NotifyDigest.readingSlots(opens: habit, now: at(12), calendar: cal) == [19 * 60 + 30],
   "the digest waits half an hour before the usual first evening open (20:10), on the quarter hour")
ok(NotifyDigest.readingSlots(opens: Array(habit.prefix(2)), now: at(12), calendar: cal) == NotifyDigest.slots,
   "two evenings are not a habit, and the fixed slot stands")
ok(NotifyDigest.readingSlots(opens: [evening(1, 16, 5), evening(2, 16, 10), evening(3, 16, 0)],
                             now: at(12), calendar: cal) == [NotifyDigest.readingWindow.lowerBound],
   "an early reader still gets the digest in the evening")
// The window's OTHER edge, untested until §870 and the reason that deletion
// costs nothing: no slot this file can choose lands at night, so the app needs
// no night rule of its own on top of iOS's Focus.
ok(NotifyDigest.readingSlots(opens: [evening(1, 21, 30), evening(2, 21, 40), evening(3, 21, 30)],
                             now: at(12), calendar: cal) == [NotifyDigest.readingWindow.upperBound],
   "a late reader is still read to in the evening — 21:30 learns 21:00, not 21:15")
ok(NotifyDigest.readingSlots(opens: [evening(20, 20, 0), evening(21, 20, 0), evening(22, 20, 0)],
                             now: at(12), calendar: cal) == NotifyDigest.slots,
   "a habit older than the lookback no longer counts")
let learned = NotifyDigest.advance(NotifyDigest.State(), adding: [item("x", "Stripe", at: at(10))],
                                   allowed: everything, now: at(10), calendar: cal,
                                   slots: [19 * 60 + 45])
ok(learned.slot == cal.date(bySettingHour: 19, minute: 45, second: 0, of: at(10)),
   "the learned hour is the slot the digest is scheduled for")

// ── the card (prd §809) ─────────────────────────────────────────────────────
ok(NotifyDigest.card([replies[0]]) == nil,
   "one thing has no card; its long press is its own picture")
let card = NotifyDigest.card(replies + [pictured("p", "X", at: at(20), picture: "https://a/1.jpg")])!
ok(card.title == NotifyDigest.plan(replies + [pictured("p", "X", at: at(20), picture: "https://a/1.jpg")])!.title,
   "the card's title is the banner's")
ok(NotifyDigest.card((0..<12).map { kinded("c\($0)", "Bluesky", .repliesReceived, body: "c\($0)", at: at(8)) })!.rows.count == NotifyDigest.cardRowCap,
   "the card draws no more than its cap")
ok(card.rows.first?.app == "X" && card.rows[1].who == "linda",
   "the card reads in the banner's order, and a row carries who acted")
ok(NotifyDigest.card([pictured("w", "Wallet", at: at(8)), pictured("x", "X", at: at(20))])!
     .rows.first?.app == "Wallet",
   "an app with no lock screen of its own leads the card, however old its news")
ok(card.rows.first(where: { $0.app == "X" })?.round == true && card.rows[1].round == false,
   "a row with a picture draws round, a mark square")
ok(card.rows.allSatisfy { $0.face == nil } && card.head == nil,
   "faces and the head are the scheduler's to attach, never invented here")
ok(NotifyCard.faceAttachment(0) != NotifyCard.headAttachment
   && NotifyCard.faceAttachment(0) != NotifyCard.faceAttachment(1),
   "every attachment the card names has its own identifier")
ok(card.encoded().flatMap { NotifyCard.decoded(from: [NotifyCard.userInfoKey: $0]) } == card,
   "the card survives the trip through userInfo")

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
  # `-Onone`, not `-O`: 97% of a pure-logic harness's wall time is the optimizer,
  # and it buys nothing an assertion can see. NOT a blanket rule — `-O` can change
  # a harness's OBSERVABLE behaviour (a trapping one prints NOTHING under `-O`) —
  # so this file was proven equivalent run-for-run by
  # `scripts/support/harness-opt-probe.sh` before the swap (2026-09-05, 2.6x faster).
  # Re-probe before trusting it again after adding mutations.
  cp "$CARD" "$work/NotifyCard.swift"
  ( cd "$work" && swiftc -Onone -o harness NotifyPlan.swift NotifyCard.swift main.swift 2>&1 | grep -E 'error:' || true )
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
       's/self == \.disputeOpened \|\| self == \.deadlineNear/self != .likesReceived/'
# The two boundaries of §422's rank, each mutated on its own — moving it to the
# top of the ladder is as wrong as burying it, and one fixture cannot say both.
mutate "a wallet incident sinks below a revocable approval" \
       's/case \.walletIncident:   return 82/case .walletIncident:   return 5/'
mutate "a wallet incident outranks a live liquidation" \
       's/case \.walletIncident:   return 82/case .walletIncident:   return 99/'
mutate "a wallet incident claims the Focus-breaking level" \
       's/self == \.disputeOpened \|\| self == \.deadlineNear/self == .disputeOpened || self == .deadlineNear || self == .walletIncident/'


# ── the two devnets (prd §522) ──────────────────────────────────────────────
# Every one of these renders as a perfectly ordinary notification — or as
# silence, which is worse, because silence here is also the healthy answer.
mutate "a devnet reset alarms someone who watches nothing on it" \
       's/guard r\.watching > 0 else \{ return nil \}//'
mutate "a reset stays news forever, long after the room stops explaining it" \
       's/static let resetWindow: TimeInterval = 7 \* 86_400/static let resetWindow: TimeInterval = 3650 * 86_400/'
mutate "the same reset is announced again on every sweep (the key leaves the id)" \
       's/:\\\(r\.key\)//'
mutate "§473 breaks: an account merely WATCHED reaches the lock screen" \
       's/guard u\.tracked else \{ return nil \}//'
mutate "an unlock fires while its timelock is still running" \
       's/guard since >= 0 else \{ return nil \}//'
mutate "one unlock announces itself again after a re-lock (the instant leaves the id)" \
       's/:\\\(stamp\)//'
mutate "stale news fires — the devnet window widens past every sweep" \
       's/static let newsWindow: TimeInterval = 36 \* 3600/static let newsWindow: TimeInterval = 3600 * 3600/'
mutate "a devnet reset outranks a dispute" \
       's/case \.chainReset:       return 55/case .chainReset:       return 200/'
mutate "the dateline draws even when delivery is on time (the lag floor is lost)" \
       's/static let datelineLag: TimeInterval = 3600/static let datelineLag: TimeInterval = -1_000_000/'
mutate "last night and yesterday collapse into one phrase" \
       's/return hour >= 21\n                \? String\(localized: "last night at/return hour >= 99\n                ? String(localized: "last night at/'
mutate "a kind loses its headline, so a notification arrives with an empty title" \
       's/case \.chainReset:       return String\(localized: "A devnet was reset"\)/case .chainReset:       return ""/'

# ── the digest (prd §770) ───────────────────────────────────────────────────
mutate "money arriving stands alone again, one buzz per transfer" \
       's/case \.disputeOpened, \.deadlineNear, \.positionAtRisk, \.safeSignatureNeeded:/case .disputeOpened, .deadlineNear, .positionAtRisk, .safeSignatureNeeded, .moneyIn:/'
mutate "a Safe signature waits for the evening digest" \
       's/case \.disputeOpened, \.deadlineNear, \.positionAtRisk, \.safeSignatureNeeded:/case .disputeOpened, .deadlineNear, .positionAtRisk:/'
mutate "a second digest a day" \
       's/static let slots = \[18 \* 60\]/static let slots = [9 * 60, 18 * 60]/'
mutate "every category folds into one digest again" \
       's/Dictionary\(grouping: queue, by: \\\.category\)/Dictionary(grouping: queue, by: { _ in "" })/'
mutate "two categories' app digests share one id and replace each other" \
       's/requestPrefix \+ newest\.category \+ ":app"/requestPrefix + ":app"/'
mutate "a delivered digest is announced again at the next slot" \
       's/if let slot = state\.slot, slot <= now \{ queue = \[\] \}//'
mutate "a growing like queues a second line instead of replacing its own" \
       's/if let i = queue\.firstIndex\(where: \{ \$0\.id == item\.id \}\) \{ queue\[i\] = item \} else \{ queue\.append\(item\) \}/queue.append(item)/'
mutate "a category switched off still speaks through what it already queued" \
       's/queue = queue\.filter\(allowed\)//'
mutate "apps with their own lock screen are named first" \
       's/if aOwn != bOwn \{ return !aOwn \}/if aOwn != bOwn { return aOwn }/'
mutate "the thumbnail draws the same Stripe mark once per payout" \
       's/guard seen\.insert\(key\)\.inserted else \{ continue \}/_ = seen.insert(key)/'
mutate "the thumbnail draws every tile, too small to read" \
       's/if out\.count == tileCap \{ break \}//'
mutate "a face never makes the thumbnail" \
       's/if let picture = item\.picture, !picture\.isEmpty \{/if let picture = item.picture, picture.isEmpty {/'
mutate "an item's own mark loses to its app's" \
       's/let mark = item\.mark \?\? item\.seat/let mark = item.seat/'
mutate "a title runs past the edge of the lock screen" \
       's/static let titleBudget = 28/static let titleBudget = 99/'
mutate "a body line runs past the edge" \
       's/static let lineBudget = 32/static let lineBudget = 99/'
mutate "the body grows past the two lines the banner shows" \
       's/static let bodyLineCap = 2/static let bodyLineCap = 4/'
mutate "a partial sum is stated as the money that arrived" \
       's/money\.allSatisfy\(\{ \$0\.usd != nil \}\)/money.contains(where: { \$0.usd != nil })/'
mutate "names never shrink to fit, so the fewest are always shown" \
       's/\(1\.\.\.min\(3, people\.count\)\)\.reversed\(\)/(1...min(3, people.count))/'
mutate "a sliver of the day leads the title" \
       's/guard first\.items\.count >= rest else \{ return nil \}//'
mutate "every app is named on every line again" \
       's/parts = names\.map \{ app in/parts = items.map { \$0.name }.map { app in/'
mutate "the digest lists every row's generic headline again" \
       's/return generic && !body\.isEmpty \? body : title/return title/'
mutate "the digest ranks by its least urgent thing" \
       's/\?\.digestRank \}\.max\(\)/?.digestRank }.min()/'
mutate "a like outranks money in the summary" \
       's/case \.likesReceived:        return 3/case .likesReceived:        return 19/'
mutate "an arrival outranks an alarm in the summary" \
       's/case \.moneyIn, \.payoutPaid: return 15/case .moneyIn, .payoutPaid: return 25/'
mutate "a single evening decides the reading hour" \
       's/static let readingDaysNeeded = 3/static let readingDaysNeeded = 1/'
mutate "the reading hour counts every open, not each evening's first" \
       's/firstByDay\[day\] = min\(firstByDay\[day\] \?\? \.max, minute\)/firstByDay[open] = minute/'
mutate "the learned hour leaves the evening" \
       's/return \[min\(max\(slot, readingWindow\.lowerBound\), readingWindow\.upperBound\)\]/return [slot]/'
mutate "the digest ignores the learned hour" \
       's/slot: nextSlot\(after: now, calendar: calendar, slots: slots\)/slot: nextSlot(after: now, calendar: calendar)/'
# §870: the two halves of the simplified slot walk, each on its own.
mutate "a slot still ahead of us is thrown away and re-chosen" \
       's/if let slot = state\.slot, slot > now \{ return State\(queue: queue, slot: slot\) \}//'
mutate "a slot already past today is scheduled anyway" \
       's/second: 0, of: day\), when > now else \{ continue \}/second: 0, of: day) else { continue }/'
mutate "the card draws every row, however many" \
       's/ordered\(group\)\.prefix\(cardRowCap\)/ordered(group).prefix(999)/'
mutate "the card and the banner read in different orders" \
       's/\(rank\[\$0\.element\.name\] \?\? \.max, \$0\.offset\) < \(rank\[\$1\.element\.name\] \?\? \.max, \$1\.offset\)/\$0.offset < \$1.offset/'

# ── NotifySweep.classify() — the actual bridge-specific dispatch ───────────
#
# Everything above tests NotifyPlan.swift's PURE judgement (severity, batching,
# the digest slot) — it has never once exercised NotifySweep.swift's classify(),
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
    var authorHandle: String?
    var isFlagged: Bool = false
    var isLive: Bool = true
    var capturedAt: Date = Date()
    var title: String = ""
    var previewImageData: Data?
    var authorAvatarURL: String?
    var previewImageURL: String?
    var imageURLs: [String] = []
    var transferAmount: String?
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
    // ── the picture ladder, rung 1 and the refined rung 2 (prd §714) ────────────
    // Every picture a row HOLDS reaches the slot, in a fixed order: the person who
    // acted, then stored bytes, then the row's own art by URL. A row with none is
    // `.none`, honestly.
    do {
        let t = row(ref: "x", source: "X")
        ok(NotifySweep.art(for: t) == .none, "a row with no picture draws none")
        t.imageURLs = ["https://a/img.jpg"]
        ok(NotifySweep.art(for: t) == .remote("https://a/img.jpg"), "the row's first image reaches rung one")
        t.previewImageURL = "https://a/cover.jpg"
        ok(NotifySweep.art(for: t) == .remote("https://a/cover.jpg"), "the row's own art outranks an inline image")
        t.previewImageData = Data([1])
        ok(NotifySweep.art(for: t) == .thing(t.id.uuidString), "stored bytes outrank a URL")
        t.authorAvatarURL = "https://a/face.jpg"
        ok(NotifySweep.art(for: t) == .remote("https://a/face.jpg"), "the person who acted outranks everything")
    }
    ok(NotifySweep.mark(for: row(ref: "wallet:defi:morpho:base:0xabc:")) == "morpho", "a position wears its protocol")
    ok(NotifySweep.mark(for: row(ref: "wallet:defi:uniswap:range:base:v3:1:")) == "uniswap", "a range wears Uniswap")
    ok(NotifySweep.mark(for: row(ref: "hyperliquid:risk:0xabc")) == "Hyperliquid", "a perp at risk wears Hyperliquid")
    ok(NotifySweep.mark(for: row(ref: "wallet:safe:1")) == "Safe", "a signature wears Safe")
    do {
        let t = row(ref: "wallet:tx:1"); t.transferDirection = "received"; t.transferAmount = "1,250 USDC"
        ok(NotifySweep.mark(for: t) == "USDC", "money in wears its token")
        t.transferAmount = "USDC"
        ok(NotifySweep.mark(for: t) == "USDC", "…even with no amount on the row")
        t.transferDirection = "sent"
        ok(NotifySweep.mark(for: t) == nil, "money out is not an event and names no mark")
    }
    ok(NotifySweep.mark(for: row(ref: "stripe:dispute:1", source: "Stripe")) == nil, "a dispute keeps the source's own mark")
}

MainActor.assumeIsolated { runFixtures() }


if bad == 0 { print("  \(checks) assertions passed"); exit(0) }
print("  \(bad) of \(checks) FAILED")
exit(1)
SWIFT

cp "$PLAN" "$sweepwork/NotifyPlan.swift"
cp "$CARD" "$sweepwork/NotifyCard.swift"
cp "$SWEEP" "$sweepwork/NotifySweep.swift"
rm -f "$sweepwork/harness"
( cd "$sweepwork" && swiftc -Onone -o harness Stubs.swift NotifyPlan.swift NotifyCard.swift NotifySweep.swift main.swift 2>&1 | grep -E 'error:' || true )
if [[ -x "$sweepwork/harness" ]]; then
  "$sweepwork/harness" || fail=1
else
  echo "  ✗ classify() fixtures: did not compile"; fail=1
fi

# The fixed names `NotifySweep.mark` can answer with must each be a bundled
# `brand-*` asset (prd §714): `AssetMark.image` returns nil for a missing one
# and the source's mark stands, so a typo here would never fail — it would
# quietly put the Wallet mark where Hyperliquid's belongs.
for name in hyperliquid safe morpho uniswap; do
  if [[ -d "Casberi/Casberi/Assets.xcassets/brand-${name}.imageset" ]]; then
    printf '  ✓ bundled mark for %s\n' "$name"
  else
    printf '  ✗ DRIFT: NotifySweep.mark can name %s but no brand-%s.imageset is bundled\n' "$name" "$name"; fail=1
  fi
done

if [[ $fail -eq 0 ]]; then
  echo "✓ notify self-test passed"
else
  echo "✗ notify self-test FAILED"
fi
exit $fail
