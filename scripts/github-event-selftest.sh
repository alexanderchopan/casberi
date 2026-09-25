#!/bin/zsh
# Casberi GitHub event-shape self-test — the SHIPPED pure logic behind what a
# GitHub events row SAYS (prd §909, 2026-09-24):
#
#   Casberi/Casberi/Model/GitHubEventShape.swift
#     — row(type:repo:payload:)  (the title, the page a tap opens, the words)
#     — verb                     (Opened / Reopened / Merged / Closed / Updated)
#     — branchName / pathEncoded (a branch NAMED, and addressed under /tree/)
#     — clamp                    (the ONE body ceiling every GitHub body shares)
#
# That file is Foundation-only BY DESIGN, so it is compiled WHOLE AND
# UNMODIFIED here — no extraction, no `private ` stripping, no copy. Every
# assertion below is about the bytes the app runs.
#
# WHY A HARNESS. `GitHubFeeds.swift` touches `Thing` and no harness can compile
# it, which is why the wording lived unproven in `contributionLine` for two
# months and landed "Opened a pull request in owner/repo" — a row with no
# title, no body, and a door to the repository's front page — while the payload
# in hand carried all three. Every regression here renders perfectly:
#
#   • a merged pull request worded "Closed" — true, and the news is gone;
#   • the door falling back to the repo's front page, so the tap that should
#     open the pull request opens a README;
#   • a branch counted ("Created a branch") instead of named;
#   • a push pointing at the repo when its head sha names the commit whose page
#     carries the whole message;
#   • an EMPTY body landing as a blank block on the sheet, or an unbounded one
#     stored whole;
#   • the feed builder quietly growing a second ceiling, or a second wording,
#     beside this one.
#
# WHAT IT DELIBERATELY DOES NOT PROVE. It never reaches GitHub, so it says
# nothing about the payload's live shape (`-ghPeopleProbe` prints the titles
# for that), and it draws nothing, so it says nothing about where the tag or
# the body lands on screen.
#
# Pure, local, deterministic — no network, no simulator, no token. Exit
# non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SHAPE="Casberi/Casberi/Model/GitHubEventShape.swift"
# The one title seam (prd §915): a row's title is `object — qualifier`.
SEAM="Casberi/Casberi/Model/TitleSeam.swift"
FEEDS="Casberi/Casberi/Model/GitHubFeeds.swift"
for f in "$SHAPE" "$FEEDS"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/github-event-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# A COMMENT-STRIPPED copy for every negative guard: `GitHubFeeds.swift` names
# `contributionLine` in the prose explaining where it went (the Obsidian/Cursor
# lesson).
strip() {
  python3 - "$1" <<'PY'
import re, sys
for line in open(sys.argv[1]).read().split("\n"):
    if line.strip().startswith("//"):
        continue
    print(re.sub(r'\s//(?!/).*$', '', line))
PY
}
strip "$FEEDS" > "$TMP/feeds.stripped"

# --- drift guards -----------------------------------------------------------
# Facts the compiled functions cannot prove: a perfect shape is worthless if
# the feed builder does not read it, or reads it and drops a field.

grep -q 'GitHubEventShape.row(type: type, repo: repo, payload: payload)' "$TMP/feeds.stripped" \
  || { echo "✗ eventThing no longer reads GitHubEventShape — the wording is unproven again"; exit 1; }
grep -q 'title: shape.title, content: shape.url' "$TMP/feeds.stripped" \
  || { echo "✗ eventThing reads the shape and lands something else as the title or the door"; exit 1; }
grep -q 't.summary = shape.body' "$TMP/feeds.stripped" \
  || { echo "✗ eventThing drops the body — the pull request's words never reach the sheet"; exit 1; }
# NEGATIVE, from the stripped copy: ONE wording. A second `contributionLine`
# beside the shape is how two rows about one event come to read differently.
grep -q 'contributionLine' "$TMP/feeds.stripped" \
  && { echo "✗ contributionLine is back in GitHubFeeds — the wording now lives in two places"; exit 1; }
# ONE ceiling. The feed's clamp delegates here; a second literal is a second rule.
grep -q 'GitHubEventShape.clamp(text)' "$TMP/feeds.stripped" \
  || { echo "✗ GitHubFeeds.clampBody no longer delegates to GitHubEventShape.clamp"; exit 1; }
grep -q '4000' "$TMP/feeds.stripped" \
  && { echo "✗ GitHubFeeds carries its own body ceiling again beside GitHubEventShape.bodyCap"; exit 1; }
# The notification body read is BOUNDED, and the token goes to GitHub's host only.
grep -q 'bodyTargets.prefix(notificationBodyCap)' "$TMP/feeds.stripped" \
  || { echo "✗ the notification body read is no longer capped — 30 requests a sweep on the busiest feed"; exit 1; }
grep -q 'apiURL.hasPrefix("\\(api)/")' "$TMP/feeds.stripped" \
  || { echo "✗ the notification body read sends the bearer token wherever subject.url points"; exit 1; }

# --- the driver -------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}
typealias J = [String: Any]
let repo = "o/r"
let home = "https://github.com/o/r"
func row(_ type: String, _ payload: J) -> GitHubEventShape.Row? {
    GitHubEventShape.row(type: type, repo: repo, payload: payload)
}
func pr(_ action: String, merged: Bool? = nil, mergedAt: String? = nil,
        body: Any? = "Why this change.", url: Any? = "https://github.com/o/r/pull/9") -> J {
    var obj: J = ["title": "Fix the flaky test", "number": 9]
    if let body { obj["body"] = body }
    if let url { obj["html_url"] = url }
    if let merged { obj["merged"] = merged }
    if let mergedAt { obj["merged_at"] = mergedAt }
    return ["action": action, "pull_request": obj]
}

// ── pull requests — the title, the door, the words ─────────────────────────
print("PullRequestEvent — the pull request itself, not the repo")
let opened = row("PullRequestEvent", pr("opened"))
// The pull request is the OBJECT (prd §915): its title leads, and the verb
// and the repo are the qualifier after the seam, drawn on the row's line.
check("the title leads, then the verb and the repo after the seam",
      opened?.title == "Fix the flaky test — Opened · o/r")
check("the door is the pull request", opened?.url == "https://github.com/o/r/pull/9")
check("the body is the description", opened?.body == "Why this change.")
check("closed and merged reads Merged",
      row("PullRequestEvent", pr("closed", merged: true))?.title.hasSuffix(" — Merged · o/r") == true)
check("merged_at alone is enough for Merged",
      row("PullRequestEvent", pr("closed", mergedAt: "2026-09-24T10:00:00Z"))?.title.hasSuffix(" — Merged · o/r") == true)
check("closed without a merge reads Closed",
      row("PullRequestEvent", pr("closed", merged: false))?.title.hasSuffix(" — Closed · o/r") == true)
check("reopened reads Reopened",
      row("PullRequestEvent", pr("reopened"))?.title.hasSuffix(" — Reopened · o/r") == true)
check("housekeeping reads Updated, never a snake_case word",
      row("PullRequestEvent", pr("review_requested"))?.title.hasSuffix(" — Updated · o/r") == true)
check("labeled reads Updated",
      row("PullRequestEvent", pr("labeled"))?.title.hasSuffix(" — Updated · o/r") == true)
check("no html_url falls back to the repo",
      row("PullRequestEvent", pr("opened", url: nil))?.url == home)
check("an empty body is nil, never a blank block",
      row("PullRequestEvent", pr("opened", body: ""))?.body == nil)
check("a whitespace body is nil",
      row("PullRequestEvent", pr("opened", body: " \n\t"))?.body == nil)
check("a null body is nil",
      row("PullRequestEvent", pr("opened", body: NSNull()))?.body == nil)
check("the body is trimmed",
      row("PullRequestEvent", pr("opened", body: "  words \n"))?.body == "words")
let long = String(repeating: "x", count: 5000)
let clamped = row("PullRequestEvent", pr("opened", body: long))?.body
check("a long body is clamped to the ceiling plus an ellipsis",
      clamped?.count == GitHubEventShape.bodyCap + 1 && clamped?.hasSuffix("…") == true)
check("a payload with no pull_request keeps the old line",
      row("PullRequestEvent", ["action": "opened"])?.title == "Opened a pull request in o/r")
check("…and the repo as its door",
      row("PullRequestEvent", ["action": "opened"])?.url == home)

// ── issues — the same three fields ─────────────────────────────────────────
print("\nIssuesEvent — the issue itself")
let issue: J = ["action": "opened", "issue": ["title": "Crash on launch",
                                              "body": "Steps…",
                                              "html_url": "https://github.com/o/r/issues/4"]]
let opened4 = row("IssuesEvent", issue)
check("titled with the issue", opened4?.title == "Crash on launch — Opened · o/r")
check("the door is the issue", opened4?.url == "https://github.com/o/r/issues/4")
check("the body is the issue's", opened4?.body == "Steps…")
check("an issue is never Merged",
      row("IssuesEvent", ["action": "closed", "issue": ["title": "t", "merged": true]])?.title
        .hasSuffix(" — Closed · o/r") == true)
check("a payload with no issue keeps the old line",
      row("IssuesEvent", ["action": "closed"])?.title == "Closed an issue in o/r")

// ── pushes — the commit is the body a push has ─────────────────────────────
print("\nPushEvent — the branch named, the commit as the door")
let push = row("PushEvent", ["ref": "refs/heads/main", "head": "abc123"])
check("the branch is named", push?.title == "Pushed to main in o/r")
check("the door is the head commit", push?.url == "https://github.com/o/r/commit/abc123")
check("no body of its own — the commit message is the caller's bounded read", push?.body == nil)
let nested = row("PushEvent", ["ref": "refs/heads/feature/x", "head": ""])
check("a branch with a slash is one branch", nested?.title == "Pushed to feature/x in o/r")
check("no head → the branch page, slashes kept", nested?.url == "https://github.com/o/r/tree/feature/x")
check("neither → the repo, and no false branch",
      row("PushEvent", [:]) == GitHubEventShape.Row(title: "Pushed to o/r", url: home, body: nil))
check("a count, when the feed still has one",
      row("PushEvent", ["size": 3, "ref": "refs/heads/main"])?.title.hasPrefix("Pushed 3") == true)
check("a zero count names the branch instead of claiming 0 commits",
      row("PushEvent", ["size": 0, "ref": "refs/heads/main"])?.title == "Pushed to main in o/r")

// ── creates — a branch is named ────────────────────────────────────────────
print("\nCreateEvent — named, and addressed")
let branch = row("CreateEvent", ["ref_type": "branch", "ref": "fix/login"])
check("a branch is named", branch?.title == "Created branch fix/login in o/r")
check("its door is the branch", branch?.url == "https://github.com/o/r/tree/fix/login")
let tag = row("CreateEvent", ["ref_type": "tag", "ref": "v1.2.0"])
check("a tag is named", tag?.title == "Created tag v1.2.0 in o/r")
check("a tag's door is under /tree/, never /releases/ — a tag is not a release",
      tag?.url == "https://github.com/o/r/tree/v1.2.0")
check("a repository create names the repo",
      row("CreateEvent", ["ref_type": "repository"]) == GitHubEventShape.Row(title: "Created o/r", url: home, body: nil))
check("a branch with no name keeps the old line",
      row("CreateEvent", ["ref_type": "branch"])?.title == "Created a branch in o/r")
check("a name that needs encoding is encoded",
      row("CreateEvent", ["ref_type": "branch", "ref": "a b"])?.url == "https://github.com/o/r/tree/a%20b")

// ── the rest ───────────────────────────────────────────────────────────────
print("\nrelease, fork, star — the object where the payload names one")
let rel = row("ReleaseEvent", ["release": ["tag_name": "v2", "html_url": "https://github.com/o/r/releases/tag/v2"]])
check("a release is titled by its tag", rel?.title == "Released v2 in o/r")
check("its door is the release", rel?.url == "https://github.com/o/r/releases/tag/v2")
check("a release with no notes stored — they are read live on open", rel?.body == nil)
check("no release object keeps the old line and the repo",
      row("ReleaseEvent", [:]) == GitHubEventShape.Row(title: "Published a release in o/r", url: home, body: nil))
check("a fork's door is the fork",
      row("ForkEvent", ["forkee": ["html_url": "https://github.com/me/r"]])?.url == "https://github.com/me/r")
check("a fork with no forkee → the repo", row("ForkEvent", [:])?.url == home)
check("a star is the repo", row("WatchEvent", [:]) == GitHubEventShape.Row(title: "Starred o/r", url: home, body: nil))
check("a type with no clean line is skipped, not shown raw", row("DeleteEvent", ["ref": "x"]) == nil)
check("a review event is skipped", row("PullRequestReviewEvent", [:]) == nil)
check("an unknown type is skipped", row("SomethingNewEvent", [:]) == nil)

// ── the small pieces ───────────────────────────────────────────────────────
print("\nbranchName, pathEncoded, clamp")
check("refs/heads/ is stripped", GitHubEventShape.branchName("refs/heads/main") == "main")
check("a bare name passes", GitHubEventShape.branchName("main") == "main")
check("empty is nil", GitHubEventShape.branchName("") == nil)
check("refs/heads/ alone is nil", GitHubEventShape.branchName("refs/heads/") == nil)
check("a non-string is nil", GitHubEventShape.branchName(7) == nil)
check("slashes survive encoding", GitHubEventShape.pathEncoded("a/b") == "a/b")
check("a space is encoded", GitHubEventShape.pathEncoded("a b") == "a%20b")
check("a short body is untouched", GitHubEventShape.clamp("hi") == "hi")
check("the ceiling is inclusive",
      GitHubEventShape.clamp(String(repeating: "y", count: GitHubEventShape.bodyCap)).count == GitHubEventShape.bodyCap)
check("one over is clamped",
      GitHubEventShape.clamp(String(repeating: "y", count: GitHubEventShape.bodyCap + 1)).hasSuffix("…"))

print(failures == 0 ? "\nAll assertions passed." : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

# `-Onone`, the pure-logic harnesses' rule (see github-person-selftest.sh).
if ! swiftc -Onone -o "$TMP/run" "$SHAPE" "$SEAM" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ the shipped GitHubEventShape.swift did not compile against the harness"
  grep -E 'error:' "$TMP/build.log" | head -20
  exit 1
fi
"$TMP/run"

# --- mutations --------------------------------------------------------------
# A check that cannot fail proves nothing. Each mutation is a plausible
# "simplification" of the shipped source, and each must break the run.
echo
echo "mutations (each must be caught)"

WORK="$TMP/work"
mutate() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$SHAPE" "$WORK/GitHubEventShape.swift"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/GitHubEventShape.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$WORK/GitHubEventShape.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -Onone -o "$TMP/mut" "$WORK/GitHubEventShape.swift" "$SEAM" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 1. A merged pull request worded "Closed" — true, and the news is gone.
mutate "merged reads Closed" \
  'case "closed":   return merged ? String(localized: "Merged") : String(localized: "Closed")' \
  'case "closed":   return String(localized: "Closed")'

# 2. The door falling back to the repo's front page.
mutate "a pull request's door is the repo" \
  'url: string(pr["html_url"]) ?? home,' \
  'url: home,'

# 3. A branch counted instead of named.
mutate "a branch counted, not named" \
  'return Row(title: "Created \(kind) \(ref) in \(repo)", url: url, body: nil)' \
  'return Row(title: "Created a \(kind) in \(repo)", url: url, body: nil)'

# 4. A push pointing at the repo when the head names the commit.
mutate "a push ignores its head" \
  'url = "\(home)/commit/\(head)"' \
  'url = home'

# 5. A body stored whole.
mutate "the body is not clamped" \
  'body: string(pr["body"]).map(clamp))' \
  'body: string(pr["body"]))'

# 6. An empty body landing as a blank block.
mutate "an empty string is a body" \
  '              !s.isEmpty else { return nil }' \
  '              true else { return nil }'

# 7. The branch prefix kept — "Pushed to refs/heads/main".
mutate "refs/heads/ is not stripped" \
  'let name = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref' \
  'let name = ref'

# 8. merged_at ignored — a payload that says merged only by its stamp reads Closed.
mutate "merged_at is ignored" \
  '|| string(pr["merged_at"]) != nil' \
  '|| false'

echo
echo "✓ github-event self-test passed"
