#!/bin/zsh
# Casberi GitHub row-tag self-test — the SHIPPED pure logic behind the GitHub
# room's two derivations (user ruling, 2026-09-11):
#
#   Casberi/Casberi/Model/GitHubRowTag.swift
#     — kind / word        (WHAT a row is: the tag under its timestamp)
#     — matches            (WHOSE it is: the face rail's scope)
#     — railShows          (whether the rail is drawn at all)
#
# Compiled WHOLE AND UNMODIFIED alongside `GitHubLinks.swift`, which it reads
# URLs through — both are Foundation-only by design, so every assertion below
# is about the bytes the app runs. No extraction, no `private ` stripping, no
# copy.
#
# WHY A HARNESS. This replaces `github-room-selftest.sh`, which went with the
# §401 head card it guarded. Nothing here can be seen from a build or a screen
# sweep, and every failure renders perfectly:
#
#   • a tag read off the wrong URL segment calls a pull request an issue. The
#     row draws, the word is plausible, and it is simply wrong;
#   • the ref table walked in the wrong ORDER — `gh:` prefixes every namespace
#     in it, so one misplaced entry claims every row in the room;
#   • a scope that matches loosely paints a full, believable feed about
#     somebody else;
#   • a NOTIFICATION scoped by person. Its face is the REPOSITORY's owner
#     (`GitHubFeedFetch.notifications` says so in its own comment, because
#     GitHub's payload names no actor), so reading that field as "who did this"
#     files every notification from an org under a watched person who happens
#     to own it. This is the one rule here nobody would guess;
#   • the rail drawn with nothing watched — a control with one option, wearing
#     a band row the feed could have had (user: "if it is just themselves that
#     would suck to see a third row").
#
# WHAT IT DELIBERATELY DOES NOT PROVE. It never reaches GitHub, so it says
# nothing about whether a row's `content` is still the html_url GitHub serves,
# and it draws nothing, so it says nothing about where the tag lands on screen.
#
# Pure, local, deterministic — no network, no simulator, no token. Exit
# non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="Casberi/Casberi/Model/GitHubRowTag.swift"
LINKS="Casberi/Casberi/Model/GitHubLinks.swift"
FEEDS="Casberi/Casberi/Model/GitHubFeeds.swift"
ROWS="Casberi/Casberi/Screens/ShapedRows.swift"
FEEDSCREEN="Casberi/Casberi/Screens/FeedScreen.swift"
RAIL="Casberi/Casberi/Shell/FaceScopeRail.swift"
SHELL_="Casberi/Casberi/Shell/MainSurface.swift"
WATCH="Casberi/Casberi/Model/GitHubRepoWatch.swift"
for f in "$TAG" "$LINKS" "$FEEDS" "$ROWS" "$FEEDSCREEN" "$RAIL" "$SHELL_" "$WATCH"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/github-rowtag-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
WORK="$TMP/work"

# A COMMENT-STRIPPED copy for every negative guard. `GitHubRowTag` documents
# its rules by naming what it must not do — its header explains why a
# notification may NOT be scoped by person — so a guard grepping raw source
# fires on the prose explaining it (the Obsidian/Cursor lesson).
strip() {
  python3 - "$1" <<'PY'
import re, sys
for line in open(sys.argv[1]).read().split("\n"):
    if line.strip().startswith("//"):
        continue
    print(re.sub(r'\s//(?!/).*$', '', line))
PY
}
strip "$TAG" > "$TMP/tag.stripped"
strip "$FEEDSCREEN" > "$TMP/feedscreen.stripped"
strip "$ROWS" > "$TMP/rows.stripped"

# --- drift guards -----------------------------------------------------------
# Facts the compiled functions cannot prove: a perfect derivation is worthless
# if nothing draws it, or if the room still draws the head it replaced.

# THE MIRROR. Every prefix in `refKinds` must be one `GitHubFeedFetch` really
# stamps. These two files cannot import each other's reasoning, and a renamed
# namespace on one side leaves the tag silently absent on every row of that
# kind — §311's failure shape, which this project keeps re-learning.
python3 - "$TMP/tag.stripped" "$FEEDS" "$LINKS" "$WATCH" <<'PY' || exit 1
import re, sys
tag, feeds, links, watch = (open(p).read() for p in sys.argv[1:5])
# The namespaces are stamped in TWO files — the feed fetch stamps what a feed
# lands, `GitHubRepoWatch` stamps the watch row itself — so the mirror is
# checked against both.
feeds = feeds + watch
table = re.search(r'refKinds: \[\(prefix: String, kind: Kind\)\] = \[(.*?)\n    \]', tag, re.S)
if not table:
    print("✗ GitHubRowTag.refKinds is gone — the ref half of the tag with it"); sys.exit(1)
prefixes = re.findall(r'\("([^"]+)"', table.group(1))
if "GitHubLinks.personRefPrefix" not in table.group(1):
    print("✗ refKinds no longer reads the person prefix from GitHubLinks — a second")
    print("  spelling is how a watched person's row silently loses its tag"); sys.exit(1)
person = re.search(r'personRefPrefix = "([^"]+)"', links)
if not person:
    print("✗ GitHubLinks.personRefPrefix is gone"); sys.exit(1)
for p in prefixes:
    if f'"{p}' not in feeds and f'ref: "{p}' not in feeds and p not in feeds:
        print(f"✗ GitHubFeedFetch no longer stamps the {p!r} namespace that refKinds reads")
        sys.exit(1)
# ORDER: `gh:` prefixes them all, so a bare one placed anywhere in this table
# claims every row after it.
if "gh:" in prefixes:
    print("✗ refKinds carries a bare \"gh:\" — it prefixes every namespace here and")
    print("  would claim every row in the room"); sys.exit(1)
PY

# The tag is DRAWN. A derivation nothing reads is a feature nobody has.
grep -q 'GitHubRowTag.word(ref: thing.sourceRef, url: thing.content)' "$TMP/rows.stripped" \
  || { echo "✗ the GitHub row no longer draws its tag in the trailing slot"; exit 1; }

# The scope is APPLIED, and through this file rather than a second rule.
grep -q 'GitHubRowTag.matches(scope: scope' "$TMP/feedscreen.stripped" \
  || { echo "✗ the feed no longer applies the GitHub scope through GitHubRowTag"; exit 1; }
grep -q 'githubScopeAllows(thing)' "$TMP/feedscreen.stripped" \
  || { echo "✗ githubScopeAllows is no longer in the feed's filter chain"; exit 1; }

# The room draws NO head (the ruling that deleted §401's card). A head card
# returning is the exact regression this ruling exists to prevent, and it would
# render perfectly.
grep -q 'githubGraphHero' "$TMP/feedscreen.stripped" \
  && { echo "✗ the contributions heatmap is back above the GitHub feed — it draws on"; \
       echo "  the ACCOUNT PAGE now (user ruling, 2026-09-11)"; exit 1; }
grep -q 'GitHubRoomCard' "$TMP/feedscreen.stripped" \
  && { echo "✗ the §401 GitHub head card is back — the room is one plain feed"; exit 1; }

# The rail is MOUNTED on the shell, not the screen (§357: a control declared on
# FeedScreen dies with the `.id(filter.source)` move it commands).
grep -q 'githubScopeRail' "$SHELL_" \
  || { echo "✗ the GitHub face rail is not mounted in MainSurface.roomControls"; exit 1; }
grep -q 'GitHubScopeRail' "$RAIL" \
  || { echo "✗ GitHubScopeRail is gone from the rail adapters"; exit 1; }

# The watched repo's open work is FETCHED. Without it the repo half of the rail
# scopes to a release every few weeks — §83's dead control with a face on it.
grep -q 'openWorkFor(watchedRepos, token: token)' "$FEEDS" \
  || { echo "✗ a watched repo no longer fetches its open issues and pull requests —"; \
       echo "  the repo half of the room's rail has nothing to show"; exit 1; }
# …in ONE call, and keeping the shared ref namespace so an issue that also
# involves you lands once rather than twice.
python3 - "$FEEDS" <<'PY' || exit 1
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'\n    private static func openWorkFor\(.*?\n    \}\n', src, re.S)
if not m:
    print("✗ openWorkFor is gone"); sys.exit(1)
body = m.group(0)
if 'ref: "gh:\\(id)"' not in body:
    print("✗ openWorkFor no longer lands under the shared gh:<id> namespace — an issue")
    print("  that is both open in a watched repo and assigned to you would land TWICE")
    sys.exit(1)
if body.count("IngestSupport.getJSON") != 1:
    print("✗ openWorkFor makes more than one request per repo — GitHub's /issues"
          " returns pull requests too, which is why it is one")
    sys.exit(1)
if "state=open" not in body:
    print("✗ openWorkFor no longer asks for OPEN work only — closed issues would land")
    print("  as news years after the fact"); sys.exit(1)
PY

# --- the driver -------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}

let gh = "https://github.com"

// ── the tag: what a row IS ────────────────────────────────────────────────
print("the tag — the object, never the reason")
check("a pull request by URL",
      GitHubRowTag.kind(ref: "gh:123", url: "\(gh)/tokio-rs/tokio/pull/7210") == .pullRequest)
check("an issue by URL",
      GitHubRowTag.kind(ref: "gh:123", url: "\(gh)/tokio-rs/tokio/issues/7201") == .issue)
check("a NOTIFICATION about a pull request is a pull request",
      GitHubRowTag.kind(ref: "gh:notif:9", url: "\(gh)/a/b/pull/4") == .pullRequest)
check("a notification about an issue is an issue",
      GitHubRowTag.kind(ref: "gh:notif:9", url: "\(gh)/a/b/issues/4") == .issue)
check("a release by ref",
      GitHubRowTag.kind(ref: "gh:release:88", url: "\(gh)/a/b/releases/tag/v1.0") == .release)
check("a star by ref", GitHubRowTag.kind(ref: "gh:star:5", url: "\(gh)/a/b") == .star)
check("a gist by ref",
      GitHubRowTag.kind(ref: "gh:gist:abc", url: "https://gist.github.com/x/abc") == .gist)
check("an event by ref", GitHubRowTag.kind(ref: "gh:event:77", url: "\(gh)/a/b") == .activity)
check("a watched repo by ref",
      GitHubRowTag.kind(ref: "gh:watchrepo:a/b", url: "\(gh)/a/b") == .watching)
check("a watched person by ref",
      GitHubRowTag.kind(ref: GitHubLinks.personRef("mia"), url: "\(gh)/mia") == .watching)

print("\nthe tag — what it refuses")
check("a bare gh: ref with no usable URL has no tag",
      GitHubRowTag.kind(ref: "gh:123", url: "\(gh)/a/b") == nil)
check("no ref and no URL is nil", GitHubRowTag.kind(ref: nil, url: nil) == nil)
check("an unknown namespace is nil", GitHubRowTag.kind(ref: "gh:future:1", url: nil) == nil)
check("a spoofed host is not read as a pull request",
      GitHubRowTag.kind(ref: "gh:1", url: "https://github.com.evil.example/a/b/pull/1") == nil)
check("every kind has a word", GitHubRowTag.Kind.allCases.allSatisfy { !$0.word.isEmpty })
check("the words are all different",
      Set(GitHubRowTag.Kind.allCases.map(\.word)).count == GitHubRowTag.Kind.allCases.count)
check("word() agrees with kind()",
      GitHubRowTag.word(ref: "gh:star:1", url: nil) == GitHubRowTag.Kind.star.word)

// ── the scope: whose a row IS ─────────────────────────────────────────────
let repoScope = "gh:watchrepo:tokio-rs/tokio"
let personScope = GitHubLinks.personRef("mia")

print("\nthe scope — a watched repo")
check("a row under the repo matches",
      GitHubRowTag.matches(scope: repoScope, ref: "gh:1",
                           url: "\(gh)/tokio-rs/tokio/pull/9", authorHandle: "nils"))
check("case is ignored",
      GitHubRowTag.matches(scope: "gh:watchrepo:Tokio-RS/Tokio", ref: "gh:1",
                           url: "\(gh)/tokio-rs/tokio/issues/9", authorHandle: nil))
check("the watch row itself is in its own scope",
      GitHubRowTag.matches(scope: repoScope, ref: repoScope,
                           url: "\(gh)/tokio-rs/tokio", authorHandle: nil))
// …and it holds WITHOUT the URL agreeing, which is the guarantee that line
// makes rather than a restatement of the path check under it: the watch row is
// the proof the watch exists, so a scope that could hide it would read as
// "nothing here" the moment you watch something quiet.
check("the watch row matches even with nothing else to go on",
      GitHubRowTag.matches(scope: repoScope, ref: repoScope, url: nil, authorHandle: nil))
check("another repo does not match",
      !GitHubRowTag.matches(scope: repoScope, ref: "gh:2",
                            url: "\(gh)/casberi/app/pull/9", authorHandle: nil))
check("a prefix collision does not match",
      !GitHubRowTag.matches(scope: repoScope, ref: "gh:2",
                            url: "\(gh)/tokio-rs/tokio-util/pull/9", authorHandle: nil))
check("a row with no URL does not match",
      !GitHubRowTag.matches(scope: repoScope, ref: "gh:2", url: nil, authorHandle: nil))
check("the author is irrelevant to a repo scope",
      GitHubRowTag.matches(scope: repoScope, ref: "gh:1",
                           url: "\(gh)/tokio-rs/tokio/pull/9", authorHandle: "anybody"))

print("\nthe scope — a watched person")
check("a row they authored matches",
      GitHubRowTag.matches(scope: personScope, ref: "gh:1",
                           url: "\(gh)/casberi/app/pull/9", authorHandle: "mia"))
check("case is ignored",
      GitHubRowTag.matches(scope: personScope, ref: "gh:1",
                           url: "\(gh)/casberi/app/pull/9", authorHandle: "MIA"))
check("the watch row itself is in its own scope",
      GitHubRowTag.matches(scope: personScope, ref: personScope,
                           url: "\(gh)/mia", authorHandle: "mia"))
check("…and with no handle stamped on it",
      GitHubRowTag.matches(scope: personScope, ref: personScope, url: nil, authorHandle: nil))
check("somebody else does not match",
      !GitHubRowTag.matches(scope: personScope, ref: "gh:1",
                            url: "\(gh)/casberi/app/pull/9", authorHandle: "uma"))
check("a row with no author does not match",
      !GitHubRowTag.matches(scope: personScope, ref: "gh:1",
                            url: "\(gh)/casberi/app/pull/9", authorHandle: nil))
check("an empty author does not match",
      !GitHubRowTag.matches(scope: personScope, ref: "gh:1", url: gh, authorHandle: ""))
// THE RULE NOBODY WOULD GUESS. A notification's face is the REPOSITORY's owner.
check("a NOTIFICATION is never scoped by person",
      !GitHubRowTag.matches(scope: personScope, ref: "gh:notif:4",
                            url: "\(gh)/mia/thing/issues/2", authorHandle: "mia"))
check("…but a notification IS scoped by its repo",
      GitHubRowTag.matches(scope: repoScope, ref: "gh:notif:4",
                           url: "\(gh)/tokio-rs/tokio/issues/2", authorHandle: "tokio-rs"))
check("a malformed scope matches nothing",
      !GitHubRowTag.matches(scope: "nonsense", ref: "gh:1", url: gh, authorHandle: "mia"))

// ── the rail ──────────────────────────────────────────────────────────────
print("\nthe rail — drawn only when there is a choice")
check("nothing watched draws no rail", !GitHubRowTag.railShows(source: "GitHub", watched: 0))
check("one watch is enough", GitHubRowTag.railShows(source: "GitHub", watched: 1))
check("another room never draws it", !GitHubRowTag.railShows(source: "Linear", watched: 4))

// ── the helpers the rail leans on ─────────────────────────────────────────
print("\nscope helpers")
check("a repo scope is named a repo", GitHubRowTag.scopeIsRepo(repoScope))
check("a person scope is not", !GitHubRowTag.scopeIsRepo(personScope))
check("repoName reads the slug", GitHubRowTag.repoName(scope: repoScope) == "tokio-rs/tokio")
check("repoName refuses a person", GitHubRowTag.repoName(scope: personScope) == nil)
check("an empty repo scope is nil", GitHubRowTag.repoName(scope: "gh:watchrepo:") == nil)

print("")
if failures > 0 { print("✗ \(failures) assertion(s) failed"); exit(1) }
print("✓ all assertions passed")
SWIFT

if ! swiftc -Onone -o "$TMP/run" "$TAG" "$LINKS" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ the shipped source did not compile:"; cat "$TMP/build.log"; exit 1
fi
"$TMP/run" || exit 1

# --- mutations --------------------------------------------------------------
# Every check above is worthless unless breaking the rule it describes makes it
# fail. Each mutation is a defect this file's header names.
echo
echo "mutations — each must be caught"

mutate() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$TAG" "$WORK/GitHubRowTag.swift"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/GitHubRowTag.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$WORK/GitHubRowTag.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -Onone -o "$TMP/mut" "$WORK/GitHubRowTag.swift" "$LINKS" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 1. The URL segment read one place off — every pull request becomes an issue.
mutate "the URL segment read off by one" \
  'if let url, let parts = GitHubLinks.webURLPathParts(url), parts.count >= 3 {
            switch parts[2] {' \
  'if let url, let parts = GitHubLinks.webURLPathParts(url), parts.count >= 4 {
            switch parts[3] {'

# 2. The ref consulted before the URL — a `gh:notif:` row has no ref entry, so
#    this silently drops the tag from the busiest feed in the room.
mutate "the pull/issue split removed" \
  'case "pull", "pulls": return .pullRequest' \
  'case "pulls": return .pullRequest'

# 3. A repo scope matched by prefix rather than by path — "tokio" would claim
#    "tokio-util", and the scoped feed fills with somebody else's work.
mutate "the repo scope matched loosely" \
  'return path.lowercased() == repo.lowercased()' \
  'return path.lowercased().hasPrefix(repo.lowercased())'

# 4. THE RULE NOBODY WOULD GUESS, removed: a notification scoped by the
#    repository owner it happens to carry.
mutate "a notification scoped by person" \
  'if let ref, ref.hasPrefix("gh:notif:") { return false }' \
  'if let ref, ref.isEmpty { return false }'

# 5. The person match made case-sensitive — GitHub logins are case-insensitive,
#    so a watch of "Mia" would match none of her rows.
mutate "the person match made case-sensitive" \
  'return handle.lowercased() == login.lowercased()' \
  'return handle == login'

# 6. The rail drawn with nothing watched — the third row the ruling removed.
mutate "the rail drawn with nothing watched" \
  'source == "GitHub" && watched > 0' \
  'source == "GitHub"'

# 7. The rail drawn in every room — a GitHub watch strip over Linear.
mutate "the rail drawn in every room" \
  'source == "GitHub" && watched > 0' \
  'watched > 0'

# 8. The watch row dropped from its own scope — watch something quiet and the
#    room reads empty with no way to tell whether the watch worked.
mutate "the watch row dropped from its own scope" \
  'if ref == scope { return true }' \
  'if ref == nil { return true }'

# 9. An unknown ref given a tag anyway — a guess printed as a fact.
mutate "an unknown ref guessed at" \
  'for entry in refKinds where ref.hasPrefix(entry.prefix) { return entry.kind }' \
  'for entry in refKinds where ref.hasPrefix(entry.prefix) { return entry.kind }
        if ref.hasPrefix("gh:") { return .issue }'

echo
echo "✓ github-rowtag-selftest passed"
