#!/bin/zsh
# Casberi feed-groups self-test — the All feed under app headers (prd §1103),
# and the provenance tier that outlived the folds (prd §378):
#
#   Casberi/Casberi/Model/AppGroups.swift
#     — every app gets a header, even an app that brought one thing
#     — an app stands as its NEWEST thing (`rowCap`), the header the door
#     — apps are ordered by their newest thing, so a section reads in time
#     — inside "Since you left" each day groups on its own (§879), and keeps
#       its name over its first app
#   Casberi/Casberi/Model/FeedFold.swift
#     — tier (made / concerns / arrived), which `FeedRow` stores and the feed
#       recedes by
#
# Replaces feed-fold-selftest.sh, whose strip/bundle decisions §1103 deleted.
#
# WHY A HARNESS. A grouping that goes wrong renders perfectly: an app's two
# days merged under one header, an older thing standing for an app, a lone
# thing drawn with no header, a day name pointing at a row that moved. None of
# it is visible to a build, and a screen sweep only sees whatever the demo
# happened to pour.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

GROUPS_SRC="Casberi/Casberi/Model/AppGroups.swift"
TIER_SRC="Casberi/Casberi/Model/FeedFold.swift"
# FeedScreen is split across files (prd §718). Guards read the room as ONE
# text, so a guard can neither fail nor pass because its code moved next door.
FEED_DIR="$(mktemp -d -t feedscreen)"
FEED="$FEED_DIR/FeedScreen.swift"
cat Casberi/Casberi/Screens/FeedScreen.swift Casberi/Casberi/Screens/FeedScreen+*.swift > "$FEED"
ICON="Casberi/Casberi/Design/BridgeIcon.swift"
for f in "$GROUPS_SRC" "$TIER_SRC" "$FEED" "$ICON"; do
  [[ -f "$f" ]] || { print -u2 "feed-groups-selftest: missing $f"; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" "$FEED_DIR"' EXIT

# ---------------------------------------------------------------- stubs
# A `Thing` with the stored properties `FeedFold.tier` reads, and nothing else.
cat > "$WORK/Stubs.swift" <<'SWIFT'
import Foundation

enum ThingKind {
    case note, screenshot, chat, event, link, reminder, mail, file, voice
    case job, run, output, skill, approval, transaction, contact, product, accessory
}

final class Thing {
    var kind: ThingKind
    var source: String
    var dueAt: Date?
    var isFlagged: Bool
    init(kind: ThingKind = .link, source: String = "RSS", dueAt: Date? = nil,
         isFlagged: Bool = false) {
        self.kind = kind
        self.source = source
        self.dueAt = dueAt
        self.isFlagged = isFlagged
    }
}
SWIFT

# ---------------------------------------------------------------- assertions
cat > "$WORK/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ok   \(what)") }
    else { print("  FAIL \(what)"); failures += 1 }
}

struct Row { let id: String; let source: String }
func rows(_ spec: String) -> [Row] {
    // "a1 b1 a2" → ids a1, b1, a2 from apps A, B, A — newest first.
    spec.split(separator: " ").map { Row(id: String($0), source: String($0.prefix(1)).uppercased()) }
}
func run(_ groups: [(String, [Row])], days: [String: String] = [:], cap: Int = AppGroups.rowCap)
    -> AppGroups.Result<Row> {
    AppGroups.group(groups, momentDays: days, cap: cap, id: \.id, source: \.source)
}
func ids(_ r: AppGroups.Result<Row>, _ i: Int = 0) -> [String] { r.groups[i].1.map(\.id) }

// ---- the rule ------------------------------------------------------------
check(AppGroups.rowCap == 1, "an app stands as its newest thing (the user's cap)")

let today = run([("Today", rows("a1 b1 a2 c1 b2 a3"))])
check(ids(today) == ["a1", "b1", "c1"], "one row per app, its newest, apps in order of their newest")
check(today.heads == ["a1": "A", "b1": "B", "c1": "C"], "every app gets a header, opened by its first row")

let lone = run([("Today", rows("a1"))])
check(lone.heads == ["a1": "A"], "an app that brought ONE thing still gets a header (\"consistent\")")

let three = run([("Today", rows("a1 b1 a2 a3 a4"))], cap: 3)
check(ids(three) == ["a1", "a2", "a3", "b1"], "a wider cap keeps an app's rows together, newest first")

let twoDays = run([("Today", rows("a1 b1")), ("Yesterday", rows("b2 a2"))])
check(ids(twoDays, 0) == ["a1", "b1"] && ids(twoDays, 1) == ["b2", "a2"],
      "sections never merge: each day groups on its own")
check(twoDays.heads.count == 4, "an app seen on two days heads both")

// "Since you left" spanning two days: openers a1 (Today) and b2 (Yesterday).
let away = run([("Since you left", rows("a1 b1 a2 b2 a3"))],
               days: ["a1": "Today", "b2": "Yesterday"])
check(ids(away) == ["a1", "b1", "b2", "a3"], "an away section groups each of its days apart")
check(away.days == ["a1": "Today", "b2": "Yesterday"],
      "each day keeps its name over its first app")

// ---- tier ------------------------------------------------------------------
check(FeedFold.tier(Thing(kind: .screenshot, source: "Photos")) == .made, "a screenshot is something you made")
check(FeedFold.tier(Thing(kind: .link, source: "You")) == .made, "anything from You is made")
check(FeedFold.tier(Thing(kind: .transaction, source: "Wallet")) == .concerns, "money moving concerns you")
check(FeedFold.tier(Thing(kind: .link, source: "Stripe", dueAt: Date())) == .concerns,
      "a deadline concerns you whatever its kind")
check(FeedFold.tier(Thing(kind: .link, source: "Wallet", isFlagged: true)) == .concerns,
      "a flagged row concerns you")
check(FeedFold.tier(Thing(kind: .link, source: "RSS")) == .arrived, "an article merely arrived")

print(failures == 0 ? "feed-groups-selftest: OK" : "feed-groups-selftest: \(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
SWIFT

swiftc -Onone -o "$WORK/run" "$WORK/Stubs.swift" "$GROUPS_SRC" "$TIER_SRC" "$WORK/main.swift" 2>&1 \
  || { print -u2 "feed-groups-selftest: the sources no longer compile against the inert stubs"; exit 1; }
"$WORK/run"

# ---------------------------------------------------------------- mutations
# A check that cannot fail proves nothing. Each mutation is a silent wrong
# answer this harness must catch.
mutate() {
  local name="$1" file="$2" from="$3" to="$4"
  local dir="$WORK/mut"; rm -rf "$dir"; mkdir -p "$dir"
  local base="${file:t}"
  python3 - "$file" "$dir/$base" "$from" "$to" <<'PY' || { echo "  ✗ STALE MUTATION: the applier exited non-zero (anchor not found — nothing was tested)"; exit 1; }
import sys
src, dst, a, b = sys.argv[1:5]
s = open(src).read()
if s.count(a) != 1:
    sys.stderr.write("MUTATION STALE (matched %d times): %s\n" % (s.count(a), a[:60]))
    sys.exit(2)
open(dst, "w").write(s.replace(a, b))
PY
  local g="$GROUPS_SRC" t="$TIER_SRC"
  [[ "$file" == "$GROUPS_SRC" ]] && g="$dir/$base"
  [[ "$file" == "$TIER_SRC" ]] && t="$dir/$base"
  if ! swiftc -Onone -o "$dir/run" "$WORK/Stubs.swift" "$g" "$t" "$WORK/main.swift" >/dev/null 2>&1; then
    print "  caught (no longer compiles): $name"; return 0
  fi
  if "$dir/run" >/dev/null 2>&1; then
    print -u2 "  MUTATION SURVIVED: $name"; return 1
  fi
  print "  caught: $name"
}

print "mutations:"
mutate "the cap is lifted (an app lists everything it brought)" "$GROUPS_SRC" \
       'static let rowCap = 1' 'static let rowCap = 99'
mutate "the cap is ignored where it is applied" "$GROUPS_SRC" \
       'members.prefix(max(cap, 1))' 'members'
mutate "an app keeps its OLDEST thing" "$GROUPS_SRC" \
       'members.prefix(max(cap, 1))' 'members.reversed().prefix(max(cap, 1))'
mutate "the away section's days merge under one header" "$GROUPS_SRC" \
       'if segments.isEmpty || momentDays[id(row)] != nil { segments.append([]) }' \
       'if segments.isEmpty { segments.append([]) }'
mutate "a day's name is lost under the away section" "$GROUPS_SRC" \
       'if i == 0, let opener { days[id(first)] = opener }' \
       'if i == 1, let opener { days[id(first)] = opener }'
mutate "apps are ordered A-Z instead of by their newest thing" "$GROUPS_SRC" \
       'for (i, app) in order.enumerated() {' \
       'for (i, app) in order.sorted().reversed().enumerated() {'
mutate "a transaction stops concerning you" "$TIER_SRC" \
       't.kind == .approval || t.kind == .transaction' \
       't.kind == .approval'

# ---------------------------------------------------------------- drift guards
# What the compiled functions cannot prove: that the feed still HANDS them the
# rows, in the right order, and draws what they answer.
strip_comments() { sed -E 's://.*$::' "$1"; }
guard() {
  local what="$1" file="$2" pat="$3"
  # `grep -E … >/dev/null`, never `grep -Eq`, in a pipeline under pipefail
  # (feed-fold-selftest's SIGPIPE lesson).
  if strip_comments "$file" | grep -E "$pat" >/dev/null; then print "  ok   $what"
  else print -u2 "  DRIFT: $what"; return 1; fi
}

print "drift guards:"
guard "the feed groups by app through AppGroups" \
      "$FEED" 'AppGroups\.group\('
guard "it groups AFTER the away split, which cuts by date" \
      "$FEED" 'groupedByApp\(split\.groups, momentDays: split\.days\)'
guard "the window reads the grouped rows, not the split's" \
      "$FEED" 'windowed\(byApp\.groups\)'
guard "the header draws before its app's first row" \
      "$FEED" 'if let app = heads\[row\.id\]'
guard "a row under a header is told whose header it stands under" \
      "$FEED" '\.environment\(\\\.dsGroupedSource, row\.source\)'
guard "BridgeIcon leaves the header's own mark out of the row" \
      "$ICON" 'groupedSource == name'
guard "AppGroups imports no SwiftUI or SwiftData — the reason it compiles here" \
      "$GROUPS_SRC" '^import Foundation$'
if strip_comments "$FEED" | grep -E 'case \.(bundle|strip)\(' >/dev/null; then
  print -u2 "  DRIFT: a fold row came back into the All feed (prd §1103 deleted them)"; exit 1
fi
print "  ok   no fold rows in the All feed"

print "feed-groups-selftest: OK"
