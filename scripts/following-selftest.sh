#!/bin/zsh
# What you follow, listed where you read it (prd §1118), compiled AS SHIPPED.
#
# `Model/Following.swift` is Foundation-only and compiles WHOLE beside
# `ServiceIdentity.swift`, whose domain rule it reuses. It decides which
# landed row is which follow's, the figures a row and the box state, and
# which mailing list and plan a followed site is. Every failure is an
# ordinary-looking list:
#
#   • a YouTube row counted under an RSS feed of the same name
#   • "8 posts" counting a year, not thirty days
#   • a cadence from two posts ("Every 41 days" off an accident)
#   • a follow nothing landed for dropped, so the list says you follow less
#   • a feed joined to every list at gmail.com
#   • two plans on one site, and the first one's door drawn
#   • a feed on youtube.com or substack.com naming the platform as its site,
#     so every channel opens the same plan
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/Following.swift"
IDENTITY="Casberi/Casberi/Model/ServiceIdentity.swift"
for f in "$SRC" "$IDENTITY"; do
  [[ -f "$f" ]] || { print -u2 "✗ $f not found"; exit 1; }
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("FAIL: \(what)"); failures += 1 }
}

let now = Date(timeIntervalSince1970: 1_800_000_000)
func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

// ── Whose row is it ──────────────────────────────────────────────────
let followed = [
    Following.Followed(id: "rss:verge", name: "The Verge", seat: "RSS", site: "theverge.com",
                       handles: ["The Verge"], removeKey: "https://theverge.com/rss"),
    Following.Followed(id: "yt:verge", name: "The Verge", seat: "YouTube", handles: ["The Verge"],
                       removeKey: "@verge"),
    Following.Followed(id: "npm:react", name: "react", seat: "npm",
                       refPrefixes: ["npm:release:react:"], removeKey: "react"),
    Following.Followed(id: "gh:x", name: "x/y", seat: "GitHub", linkFragments: ["github.com/x/y/"],
                       removeKey: "gh:watchrepo:x/y"),
    Following.Followed(id: "rss:quiet", name: "Quiet Blog", seat: "RSS", handles: ["Quiet Blog"],
                       removeKey: "https://quiet.blog/feed"),
]
check(Following.owner(of: .init(source: "RSS", handle: "the verge", ref: nil, at: now), in: followed) == 0,
      "a feed's row is its by name, without case")
check(Following.owner(of: .init(source: "YouTube", handle: "The Verge", ref: nil, at: now), in: followed) == 1,
      "a YouTube row is the YouTube follow's, never the RSS feed of the same name")
check(Following.owner(of: .init(source: "npm", handle: nil, ref: "npm:release:react:19.1.0", at: now), in: followed) == 2,
      "a package's row is its by ref")
check(Following.owner(of: .init(source: "npm", handle: nil, ref: "npm:release:react-dom:19.1.0", at: now), in: followed) == nil,
      "react-dom is not react")
check(Following.owner(of: .init(source: "GitHub", handle: nil, ref: "gh:release:1", link: "https://github.com/x/y/releases/1", at: now), in: followed) == 3,
      "a repo's release is its by link")

// ── The figures ──────────────────────────────────────────────────────
let posts: [Following.Post] = [
    .init(source: "RSS", handle: "The Verge", ref: nil, at: ago(1)),
    .init(source: "RSS", handle: "The Verge", ref: nil, at: ago(8)),
    .init(source: "RSS", handle: "The Verge", ref: nil, at: ago(15)),
    .init(source: "RSS", handle: "The Verge", ref: nil, at: ago(200)),
    .init(source: "YouTube", handle: "The Verge", ref: nil, at: ago(3)),
    .init(source: "YouTube", handle: "The Verge", ref: nil, at: ago(40)),
    .init(source: "Elsewhere", handle: "The Verge", ref: nil, at: ago(1)),
]
let items = Following.compose(followed, posts: posts, now: now)
check(items.count == followed.count, "every follow lists, nothing landed or not")
let verge = items.first { $0.id == "rss:verge" }
check(verge?.lastMonth == 3, "thirty days, not the year: \(verge?.lastMonth ?? -1)")
check(verge?.count == 4, "every row counted in all")
check(verge?.cadenceDays == 7, "the median gap: \(verge?.cadenceDays ?? -1)")
check(verge?.last == ago(1) && verge?.since == ago(200), "last and since")
let yt = items.first { $0.id == "yt:verge" }
check(yt?.lastMonth == 1 && yt?.cadenceDays == nil, "two posts make no cadence")
check(items.first?.id == "rss:verge", "the busiest this month first")
let quiet = items.first { $0.id == "rss:quiet" }
check(quiet?.count == 0 && quiet?.last == nil, "a follow nothing landed for lists with nothing")
check(Following.Item(id: "t", name: "t", seat: "Twitch", count: 0, lastMonth: 0, arrivals: []).removable == false,
      "a follow read from an account cannot be stopped here")

// ── Its site ─────────────────────────────────────────────────────────
check(Following.site(ofFeed: "https://www.stratechery.com/feed") == "stratechery.com", "www comes off")
check(Following.site(ofFeed: "https://www.youtube.com/feeds/videos.xml?channel_id=UC1") == nil,
      "a platform's feed names no site")
check(Following.site(ofFeed: "https://small.substack.com/feed") == nil, "a Substack subdomain names no site")

// ── Its mail and its plan ────────────────────────────────────────────
let lists = [
    ServiceIdentity.List(id: "gm", name: "Stratechery", address: "ben@gmail.com"),
    ServiceIdentity.List(id: "s", name: "Ben", address: "email@stratechery.com"),
]
check(Following.list(site: "stratechery.com", lists: lists) == "s", "the list at the site's domain")
check(Following.list(site: "gmail.com", lists: lists) == nil, "a mailbox provider names no list")
check(Following.list(site: "other.com", lists: lists) == nil, "a display name never joins")
let plans = [
    ServiceIdentity.Plan(id: "p1", name: "STRATECHERY", site: nil),
    ServiceIdentity.Plan(id: "p2", name: "Netflix", site: "netflix.com"),
]
check(Following.plan(site: "stratechery.com", plans: plans) == "p1", "a plan named for the domain's label")
check(Following.plan(site: "netflix.com", plans: plans) == "p2", "a plan by the site you gave it")
check(Following.plan(site: "a.com", plans: [.init(id: "1", name: "x", site: "a.com"),
                                            .init(id: "2", name: "y", site: "a.com")]) == nil,
      "two plans on one site: no door")
check(Following.plan(site: "abc.com", plans: [.init(id: "1", name: "ABC", site: nil)]) == nil,
      "a label under four letters names nothing")

if failures > 0 { print("✗ \(failures) failed"); exit(1) }
print("  ok   whose row, the figures, the site, the list and the plan")
SWIFT

build() { swiftc -Onone -o "$work/run" "$1" "$work/ServiceIdentity.swift" "$work/main.swift" 2>"$work/err" || return 1 }

cp "$IDENTITY" "$work/ServiceIdentity.swift"
cp "$SRC" "$work/Following.swift"
build "$work/Following.swift" || { cat "$work/err"; fail "the shipped source does not compile"; }
"$work/run" || fail "assertions failed against the shipped source"

mutate() {
  local why="$1" expr="$2"
  cp "$SRC" "$work/m.swift"
  perl -0pi -e "$expr" "$work/m.swift"
  cmp -s "$SRC" "$work/m.swift" && fail "mutation matched nothing: $why"
  build "$work/m.swift" || { cat "$work/err"; fail "mutation does not compile: $why"; }
  if "$work/run" >/dev/null 2>&1; then
    fail "mutation SURVIVED — $why"
  fi
  echo "  ok   catches  $why"
}

mutate "a row matched across apps by name" \
  's/ where f\.seat == post\.source//'
mutate "the month counts every row" \
  's/\$0 >= monthStart && \$0 <= now/\$0 <= now/'
mutate "a cadence from two posts" \
  's/newestFirst\.count >= 3/newestFirst.count >= 2/'
mutate "a follow nothing landed for is dropped" \
  's/return items\.sorted \{/return items.filter { \$0.count > 0 }.sorted {/'
mutate "a mailbox provider joins a feed to its list" \
  's/,\n\s*!ServiceIdentity\.mailboxDomains\.contains\(sender\)//'
mutate "two plans on one site, the first drawn" \
  's/if bySite\.count > 1 \{ return nil \}//'
mutate "a platform's feed names the platform" \
  's/sharedHosts\.contains\(where: \{ bare == \$0 \|\| bare\.hasSuffix\("\." \+ \$0\) \}\) \? nil : bare/bare/'
