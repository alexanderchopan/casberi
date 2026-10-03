#!/bin/zsh
# Casberi work-ask self-test — what leads Work's Coming up as "Needs you"
# (prd §1080):
#
#   Casberi/Casberi/Model/WorkAsk.swift    (compiled whole)
#   Casberi/Casberi/Model/WorkStage.swift  (compiled whole: the failed tone)
#
# WHY A HARNESS. Both failures render as a calm list. Too loose, and every
# open ticket and last month's red build sits under "Needs you", so the group
# says nothing; too tight, and a review request never reaches it. Which rows
# are asks is a table of stable signals per service, and only a case-by-case
# statement of it can say the table is right.
#
# Pure, local, deterministic. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

ASK="Casberi/Casberi/Model/WorkAsk.swift"
STAGE="Casberi/Casberi/Model/WorkStage.swift"
for f in "$ASK" "$STAGE"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done
grep -q 'WorkAsk.needsYou(' Casberi/Casberi/Screens/FeedScreen+MergedRoom.swift \
  || { echo "✗ Work's Coming up no longer leads with what needs you"; exit 1; }
grep -q 'workAsks(visible)' Casberi/Casberi/Screens/FeedScreen+MergedRoom.swift \
  || { echo "✗ the asks no longer read the folded room — a resolved incident would still need you"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$ASK" "$STAGE" "$TMP/"
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { failures += 1; print("✗ \(what)") }
}
let now = Date(timeIntervalSince1970: 2_000_000_000)
let fresh = now.addingTimeInterval(-3_600)
func asks(_ source: String, tags: [String] = [], ref: String? = nil, mark: String = "none",
          at: Date = fresh) -> Bool {
    WorkAsk.needsYou(.init(source: source, sourceRef: ref, title: "x", tags: tags, mark: mark),
                     at: at, now: now)
}

// ── Asks addressed to you ────────────────────────────────────────────
check(asks("GitHub", tags: ["Notifications", "Review"]), "a review request needs you")
check(asks("GitHub", tags: ["Notifications", "Assigned"]), "an assignment needs you")
check(asks("GitHub", tags: ["Notifications", "Mentioned"]), "a mention needs you")
check(!asks("GitHub", tags: ["Notifications"]), "a notification that asks nothing does not")
check(!asks("GitHub", mark: "todo"), "an open issue is not an ask — the to-do mark means open")
check(!asks("Linear", mark: "doing"), "a ticket in progress is not an ask")

// ── Things that broke ────────────────────────────────────────────────
check(asks("Vercel", tags: ["Build failure"]), "a failed build needs you")
check(!asks("Vercel", tags: ["Deploy"]), "a deploy that landed does not")
check(asks("Sentry", tags: ["Regression"]), "a regression needs you")
check(asks("PagerDuty", tags: ["Incident"]), "a triggered incident needs you")
check(!asks("PagerDuty", tags: ["Incident", "Resolved"]), "a resolved incident does not")
check(asks("Stripe", tags: ["Dispute"]), "an open Stripe dispute needs you")
check(!asks("Stripe", tags: ["Dispute", "Won"]), "a won dispute does not")
check(asks("App Store Connect", ref: "asc:version:1:REJECTED"), "a rejection needs you")
check(!asks("App Store Connect", ref: "asc:version:1:IN_REVIEW"), "a version in review is Apple's desk, not yours")
check(asks("AWS", ref: "aws:alarm:prod-api-5xx:ALARM:1700000000"), "an alarm firing needs you")
check(!asks("AWS", ref: "aws:alarm:prod-api-5xx:OK:1700000000"), "a cleared alarm does not")
check(asks("AWS", tags: ["Deploy", "Failed"], ref: "aws:pipeline:e-1"), "a failed pipeline run needs you")
check(!asks("AWS", tags: ["Deploy", "Succeeded"], ref: "aws:pipeline:e-2"), "a green pipeline run does not")
check(!asks("AWS", tags: ["Cost"]), "a cost reading is not an ask")
check(asks("Polar", tags: ["Dispute", "Opened"]), "an open Polar dispute needs you")
check(!asks("Polar", tags: ["Dispute", "Won"]), "a won Polar dispute does not")
check(asks("Dodo Payments", tags: ["Subscription", "Failed"]), "a failed Dodo payment needs you")
check(asks("Polar", tags: ["Subscription", "PastDue"]), "a past-due Polar subscription needs you")
check(!asks("Dodo Payments", tags: ["Subscription", "Cancelled"]), "a cancellation is news, not an ask")
check(!asks("Dodo Payments", tags: ["Payment"]), "a sale is not an ask")

// ── A week, then it goes ─────────────────────────────────────────────
let lastWeek = now.addingTimeInterval(-WorkAsk.window - 60)
check(!asks("GitHub", tags: ["Review"], at: lastWeek), "a review request older than a week has left 'now'")
check(asks("GitHub", tags: ["Review"], at: now.addingTimeInterval(-WorkAsk.window + 60)),
      "a review request inside the week stands")

if failures > 0 { print("✗ work ask: \(failures) failing"); exit(1) }
print("✓ work ask self-test passed")
SWIFT

swiftc -O -o "$TMP/workask" "$TMP/WorkAsk.swift" "$TMP/WorkStage.swift" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/workask" ]] || { echo "✗ work ask harness did not compile"; exit 1; }
"$TMP/workask"
