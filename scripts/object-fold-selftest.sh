#!/bin/zsh
# Casberi object-fold self-test — which rows in Work and Reading are ONE thing
# (prd §1079):
#
#   Casberi/Casberi/Model/ObjectFold.swift   (compiled whole)
#   Casberi/Casberi/Model/ThingLinks.swift   (compiled whole: the canonicaliser)
#
# WHY A HARNESS. Every failure this catches renders as an ordinary room. A
# dashboard link treated as an object folds a week of distinct PostHog readings
# into one row and nothing looks wrong; an AWS alarm keyed without its fragment
# folds every alarm in the account into the newest; a Walletbeat rating folded
# as an article hides the change you came to read. The fold HIDES rows, so the
# only way to know it hid the right ones is to state, case by case, which links
# name an object and which do not.
#
# Pure, local, deterministic. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

FOLD="Casberi/Casberi/Model/ObjectFold.swift"
LINKS="Casberi/Casberi/Model/ThingLinks.swift"
for f in "$FOLD" "$LINKS"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# The room uses the fold, and the sheet lists what it folded: a fold with no
# way back to the rows it hid is a deletion.
FEED_DIR="$(mktemp -d -t objectfold)"
trap 'rm -rf "$FEED_DIR"' EXIT
cat Casberi/Casberi/Screens/FeedScreen.swift Casberi/Casberi/Screens/FeedScreen+*.swift > "$FEED_DIR/FeedScreen.swift"
grep -q 'objectFolded(' "$FEED_DIR/FeedScreen.swift" \
  || { echo "✗ no merged room folds its rows through ObjectFold any more"; exit 1; }
grep -q 'ObjectFold.key(' Casberi/Casberi/Screens/ThingSheetView.swift \
  || { echo "✗ the thing sheet no longer lists the rows folded under it — the fold would hide them for good"; exit 1; }

cp "$FOLD" "$LINKS" "$FEED_DIR/"
cat > "$FEED_DIR/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { failures += 1; print("✗ \(what)") }
}
func work(_ link: String) -> String? { ObjectFold.key(room: .work, source: "x", link: link) }
func reading(_ link: String, _ source: String = "RSS") -> String? {
    ObjectFold.key(room: .reading, source: source, link: link)
}

// ── Work: one object, many events ────────────────────────────────────
let pr = work("https://github.com/acme/api/pull/12")
check(pr == "github:acme/api#12", "a GitHub PR keys on repo and number (got \(pr ?? "nil"))")
check(work("https://github.com/Acme/API/pull/12#issuecomment-99") == pr,
      "a comment on the PR is the PR (case and fragment fold)")
check(work("https://github.com/acme/api/pull/12/files") == pr, "the PR's files tab is the PR")
check(work("https://github.com/acme/api/issues/12") == pr,
      "an issue and a PR share GitHub's one number space")
check(work("https://github.com/acme/api/pull/13") != pr, "a different PR is a different object")
check(work("https://github.com/acme/api/commit/ABC123") == "github:acme/api@abc123", "a commit keys on its sha")
check(work("https://github.com/acme/api") == nil, "a repo page is not an object")
check(work("https://github.com/acme/api/releases/tag/v1") == nil, "a release is its own event, never folded")
check(work("https://github.com/settings/tokens") == nil, "GitHub's token page is not an object")
check(work("https://gitlab.com/g/sub/proj/-/merge_requests/7") == "gitlab:gitlab.com/g/sub/proj!7", "a GitLab MR")
check(work("https://gitlab.com/g/proj/-/issues/7") == "gitlab:gitlab.com/g/proj#7", "a GitLab issue")
check(work("https://linear.app/acme/issue/eng-42/fix-login") == "linear:ENG-42", "a Linear issue keys on its id")
check(work("https://acme.atlassian.net/browse/OPS-9") == "jira:acme.atlassian.net:OPS-9", "a Jira ticket")
check(work("https://trello.com/c/AbC123/14-ship-it") == "trello:AbC123", "a Trello card")
check(work("https://www.notion.so/acme/Roadmap-0123456789abcdef0123456789abcdef")
      == "notion:0123456789abcdef0123456789abcdef", "a Notion page keys on its id")
check(work("https://www.notion.so/acme") == nil, "a Notion workspace is not a page")
check(work("https://acme.sentry.io/issues/4455/?project=1") == "sentry:4455", "a Sentry issue")
check(work("https://sentry.io/organizations/acme/issues/4455/") == "sentry:4455", "a Sentry issue, old host")
check(work("https://acme.pagerduty.com/incidents/Q1ABC") == "pagerduty:acme.pagerduty.com:Q1ABC", "a PagerDuty incident")
check(work("https://api-abc123-acme.vercel.app") == "vercel:api-abc123-acme.vercel.app", "a Vercel deployment host")
check(work("https://vercel.com/acme/api/9xYz") == "vercel:acme/api/9xyz", "a Vercel inspector link")
check(work("https://vercel.com") == nil, "Vercel's home is not a deployment")
check(work("https://appstoreconnect.apple.com/apps/1/testflight/ios/777") == "asc:build:777", "a TestFlight build")
check(work("https://appstoreconnect.apple.com/apps/1/appstore") == nil,
      "the App Store page is the app's, never one version's — two versions' reviews must not fold")
check(work("https://dashboard.stripe.com/disputes/dp_1") == "stripe:dp_1", "a Stripe dispute")
check(work("https://dashboard.stripe.com/test/payouts/po_1") == "stripe:po_1", "a Stripe test-mode payout")
check(work("https://dashboard.stripe.com/balance") == nil, "Stripe's balance page is a reading, not an object")
check(work("https://polar.sh/dashboard/acme/sales/ord_1") == "polar:sale:ord_1", "a Polar sale")
check(work("https://polar.sh/dashboard/acme/finance/refunds") == nil, "Polar's refunds list is not an object")

// The alarm's NAME is in the fragment. A key without it folds every alarm.
let a1 = work("https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#alarmsV2:alarm/api-5xx")
let a2 = work("https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#alarmsV2:alarm/db-cpu")
check(a1 == "aws:alarm:us-east-1:api-5xx", "an AWS alarm keys on region and name (got \(a1 ?? "nil"))")
check(a1 != a2, "two AWS alarms are two objects")
check(work("https://console.aws.amazon.com/codesuite/codepipeline/pipelines/p/executions/e-1/timeline?region=x")
      == "aws:run:e-1", "a pipeline run")
check(work("https://console.aws.amazon.com/cost-management/home#/cost-explorer") == nil, "Cost Explorer is a reading")

// Dashboards and messages: never an object.
check(work("https://us.posthog.com/project/12") == nil, "PostHog's project page stamps every reading")
check(work("https://acme.slack.com/archives/C1/p1700000000") == nil, "a Slack message is never folded")
check(work("https://dash.cloudflare.com/abc/example.com/dns") == nil, "a Cloudflare dashboard")
check(work("not a link") == nil, "a row with no link names nothing")

// ── Reading: one article, many saves ─────────────────────────────────
let art = reading("https://www.example.com/posts/why-rust?utm_source=rss")
check(art == "read:example.com/posts/why-rust", "an article keys on its canonical link (got \(art ?? "nil"))")
check(reading("http://example.com/posts/why-rust/", "Raindrop") == art, "a save of it elsewhere is the same article")
check(reading("https://example.com/posts/why-rust", "L2BEAT") == nil, "L2BEAT's rows are ratings, never articles")
check(reading("https://example.com/posts/why-rust", "Walletbeat") == nil, "Walletbeat's rows are ratings, never articles")
check(reading("https://example.com") == nil, "a bare site is not an article")
check(reading("https://example.com/posts/a") != reading("https://example.com/posts/b"), "two articles stay two")
check(ObjectFold.Room(room: "Work") == .work && ObjectFold.Room(room: "Reading") == .reading
      && ObjectFold.Room(room: "Social") == nil, "only Work and Reading fold")

// ── The fold: the newest member stands ───────────────────────────────
let t0 = Date(timeIntervalSince1970: 1_000)
let rows: [ObjectFold.Row<String>] = [
    .init(id: "merged", key: "pr", at: t0.addingTimeInterval(300)),
    .init(id: "slack", key: nil, at: t0.addingTimeInterval(250)),
    .init(id: "review", key: "pr", at: t0.addingTimeInterval(200)),
    .init(id: "other", key: "pr2", at: t0.addingTimeInterval(150)),
    .init(id: "opened", key: "pr", at: t0.addingTimeInterval(100)),
]
let hidden = ObjectFold.folded(rows)
check(hidden == ["review", "opened"], "the PR's older events fold under its newest (got \(hidden.sorted()))")
let shuffled = [rows[4], rows[2], rows[0], rows[1], rows[3]]
check(ObjectFold.folded(shuffled) == hidden, "the newest stands whatever order the rows arrive in")
check(ObjectFold.folded([rows[1], rows[3]]).isEmpty, "a row alone, or with no key, always stands")

if failures > 0 { print("✗ object fold: \(failures) failing"); exit(1) }
print("✓ object fold self-test passed")
SWIFT

swiftc -O -o "$FEED_DIR/objectfold" "$FEED_DIR/ObjectFold.swift" "$FEED_DIR/ThingLinks.swift" "$FEED_DIR/main.swift" 2>&1 \
  | grep -v "^$" || true
[[ -x "$FEED_DIR/objectfold" ]] || { echo "✗ object fold harness did not compile"; exit 1; }
"$FEED_DIR/objectfold"
