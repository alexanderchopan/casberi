#!/bin/zsh
# Casberi GitHub person-watch self-test — the SHIPPED pure logic behind
# watching a person on GitHub (prd §519, 2026-08-29):
#
#   Casberi/Casberi/Model/GitHubLinks.swift
#     — webURLPathParts / repoPath  (what a pasted github.com link addresses)
#     — personLogin / isValidLogin  (which strings name an account, and which
#                                    are refused rather than guessed at)
#     — personRef / personLogin(fromRef:)  (the watch's identity in the corpus)
#     — activityLogins              (whose events this pass reads)
#
# That file is Foundation-only BY DESIGN, so it is compiled WHOLE AND
# UNMODIFIED here — no extraction, no `private ` stripping, no copy. Every
# assertion below is about the bytes the app runs.
#
# WHY A HARNESS. Nothing here can be seen from a build or a screen sweep, no
# simulator can be handed a GitHub token, and every failure lands as a watch
# that looks like it worked:
#
#   • a REPO url read as a profile — "github.com/torvalds/linux" watches
#     torvalds. The watch resolves, the row lands, the activity arrives, and
#     none of it is what was asked for;
#   • a host matched loosely, so "github.com.evil.example/x" is trusted;
#   • a login taken on faith and interpolated into `/users/<login>/events` —
#     the one failure here that addresses an endpoint nobody asked for;
#   • a ref that isn't lowercased, so "Torvalds" and "torvalds" become two
#     watches of one account, each spending its own request every sweep;
#   • `activityLogins` dropping your own account unconditionally, which makes
#     watching yourself with the contributions feed OFF read nothing at all,
#     silently and forever.
#
# WHAT IT DELIBERATELY DOES NOT PROVE. It never reaches GitHub, so it says
# nothing about whether `/users/<login>/events` still answers, or in what
# shape. That is `-ghPeopleProbe`'s job (and the drift guards below only prove
# the app still ASKS the right question, never that the answer parses).
#
# Pure, local, deterministic — no network, no simulator, no token. Exit
# non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

LINKS="Casberi/Casberi/Model/GitHubLinks.swift"
WATCH="Casberi/Casberi/Model/GitHubPersonWatch.swift"
REPOWATCH="Casberi/Casberi/Model/GitHubRepoWatch.swift"
FEEDS="Casberi/Casberi/Model/GitHubFeeds.swift"
SCREEN="Casberi/Casberi/Screens/TokenSetupScreen.swift"
for f in "$LINKS" "$WATCH" "$REPOWATCH" "$FEEDS" "$SCREEN"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/github-person-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# A COMMENT-STRIPPED copy for every negative guard. These files document their
# own rules by naming what they must not do — `GitHubPersonWatch`'s header
# explains why it does NOT file the avatar as art, and `eventsFor`'s explains
# why it does NOT look a commit message up — so a guard grepping raw source
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
strip "$WATCH" > "$TMP/watch.stripped"
strip "$FEEDS" > "$TMP/feeds.stripped"

# --- drift guards -----------------------------------------------------------
# Facts the compiled functions can't prove: a perfect parser is worthless if
# nothing calls it, or if what it produces is read back by a different rule.

# The ref this file builds and the ref the corpus is scanned for must be one
# constant. Two spellings is §311 exactly — every row lands, nothing matches
# them back, and the room simply goes quiet.
grep -q 'GitHubLinks.personRef(person.login)' "$TMP/watch.stripped" \
  || { echo "✗ GitHubPersonWatch.add no longer builds its ref from GitHubLinks —"; \
       echo "  a second spelling of the prefix is how a watch lands and is never read back"; exit 1; }
grep -q 'compactMap(GitHubLinks.personLogin(fromRef:))' "$TMP/watch.stripped" \
  || { echo "✗ watchedPeople no longer reads its logins back through GitHubLinks"; exit 1; }

# The two watch prefixes must stay distinct AND neither a prefix of the other:
# `watchedRepos` and `watchedPeople` scan the same rows, so an overlap files
# every watched person as a repo slug (and asks GitHub for its releases).
python3 - "$LINKS" "$REPOWATCH" <<'PY' || exit 1
import re, sys
person = re.search(r'personRefPrefix = "([^"]+)"', open(sys.argv[1]).read())
repo = re.search(r'refPrefix = "([^"]+)"', open(sys.argv[2]).read())
if not person or not repo:
    print("✗ a watch ref prefix could not be found — the guard cannot run"); sys.exit(1)
p, r = person.group(1), repo.group(1)
if p == r or p.startswith(r) or r.startswith(p):
    print(f"✗ the watch prefixes overlap ({p!r} vs {r!r}) — one scan would claim the other's rows")
    sys.exit(1)
PY

# The pass must actually run, and must be gated on the real feed set. A literal
# here reads one endpoint twice forever, or never reads your own account at all.
grep -q 'let watchedPeople = GitHubPersonWatch.watchedPeople(context: context)' "$TMP/feeds.stripped" \
  || { echo "✗ GitHubFeedFetch.all no longer reads the watched people"; exit 1; }
grep -q '!watchedPeople.isEmpty else { return \[\] }' "$TMP/feeds.stripped" \
  || { echo "✗ all()'s early return no longer counts watched people — watching somebody"; \
       echo "  with every feed off would fetch nothing, silently"; exit 1; }
grep -q 'contributionsOn: feeds.contains(.contributions)' "$TMP/feeds.stripped" \
  || { echo "✗ activityLogins is no longer told the REAL state of the contributions"; \
       echo "  feed — a literal there either double-reads one endpoint or drops your own"; exit 1; }
grep -q 'eventsFor(activityPeople, token: token)' "$TMP/feeds.stripped" \
  || { echo "✗ nothing calls eventsFor — a watch would land its row and never any activity"; exit 1; }

# The endpoint itself. A watched person's events and your own contributions
# read the SAME path, which is what makes the shared `gh:event:` ref honest.
grep -c 'users/\\(login)/events?per_page=30' "$TMP/feeds.stripped" | grep -q '^2$' \
  || { echo "✗ the two event reads no longer ask the same endpoint the same way —"; \
       echo "  the shared gh:event: ref assumes they do"; exit 1; }
grep -q 'ref: "gh:event:\\(id)"' "$TMP/feeds.stripped" \
  || { echo "✗ eventThing no longer stamps gh:event: — a watched person's push and"; \
       echo "  your own would land as two rows for one event"; exit 1; }

# The tag. Filing somebody else's pushes under "Contributions" makes the one
# tag that answers "what have I been doing" stop answering it.
python3 - "$TMP/feeds.stripped" <<'PY' || exit 1
import re, sys
src = open(sys.argv[1]).read()
activity = re.search(r'activityTag = "([^"]+)"', src)
if not activity:
    print("✗ GitHubFeedFetch.activityTag is gone"); sys.exit(1)
tags = dict(re.findall(r'case \.(\w+):\s+"([^"]+)"', src))
if activity.group(1) in tags.values():
    print(f"✗ activityTag ({activity.group(1)!r}) collides with a feed's own tag —")
    print("  a watched person's rows would be filed as one of your feeds")
    sys.exit(1)
PY

# NEGATIVE, from the stripped copy: the stated cost bound. One request per
# watched person, and the commit-message follow-up deliberately NOT made —
# it multiplies by the number of people watched.
python3 - "$TMP/feeds.stripped" <<'PY' || exit 1
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'\n    private static func eventsFor\(.*?\n    \}\n', src, re.S)
if not m:
    print("✗ eventsFor is gone"); sys.exit(1)
if "commitMessage" in m.group(0):
    print("✗ eventsFor now looks commit messages up — that call is bounded at 15 for")
    print("  ONE account and multiplies by the number of people watched (prd §519)")
    sys.exit(1)
PY

# NEGATIVE, from the stripped copy: the avatar is a FACE, never the row's art
# (the 2026-08-14 ruling). `previewImageURL` here is the defect that ruling fixed.
grep -q 'thing.authorHandle = person.login' "$TMP/watch.stripped" \
  || { echo "✗ the watch row no longer stamps a handle — GitHub is in faceSources,"; \
       echo "  so the leading slot would draw the bridge glyph for a person"; exit 1; }
grep -q 'previewImageURL' "$TMP/watch.stripped" \
  && { echo "✗ GitHubPersonWatch files the avatar as the row's ART — an avatar is an"; \
       echo "  identity, not a picture (2026-08-14)"; exit 1; }

# The field exists and is wired. A parser nothing can reach is a feature nobody has.
grep -q 'action: watchPerson' "$SCREEN" \
  || { echo "✗ the setup screen has no Watch verb for a person"; exit 1; }
grep -q 'GitHubPersonWatch.add(resolved, context: modelContext)' "$SCREEN" \
  || { echo "✗ the screen's Watch verb no longer lands the watch"; exit 1; }

# --- the driver -------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}

// ── webURLPathParts / repoPath — the host rule, moved here 2026-08-29 ──────
print("web URLs — an exact host, or nothing")
check("a full URL splits", GitHubLinks.webURLPathParts("https://github.com/a/b") == ["a", "b"])
check("scheme-less is accepted", GitHubLinks.webURLPathParts("github.com/a/b") == ["a", "b"])
check("www is accepted", GitHubLinks.webURLPathParts("https://www.github.com/a") == ["a"])
check("a spoofed host is refused",
      GitHubLinks.webURLPathParts("https://github.com.evil.example/a/b") == nil)
check("a lookalike host is refused",
      GitHubLinks.webURLPathParts("https://notgithub.com/a/b") == nil)
check("repoPath takes the first two components",
      GitHubLinks.repoPath(fromWebURL: "https://github.com/a/b/issues/4") == "a/b")
check("repoPath needs two", GitHubLinks.repoPath(fromWebURL: "https://github.com/a") == nil)

// ── personLogin — which strings name an account ────────────────────────────
print("\npersonLogin — a person, never a guess")
check("a bare login", GitHubLinks.personLogin(from: "torvalds") == "torvalds")
check("an @login", GitHubLinks.personLogin(from: "@torvalds") == "torvalds")
check("whitespace is trimmed", GitHubLinks.personLogin(from: "  torvalds \n") == "torvalds")
check("a profile URL", GitHubLinks.personLogin(from: "https://github.com/torvalds") == "torvalds")
check("scheme-less profile URL", GitHubLinks.personLogin(from: "github.com/torvalds") == "torvalds")
check("a trailing slash", GitHubLinks.personLogin(from: "https://github.com/torvalds/") == "torvalds")
check("a query string",
      GitHubLinks.personLogin(from: "https://github.com/torvalds?tab=repositories") == "torvalds")
check("case is preserved — the row reads the way they write it",
      GitHubLinks.personLogin(from: "Torvalds") == "Torvalds")
check("hyphens are real logins", GitHubLinks.personLogin(from: "rust-lang") == "rust-lang")
check("digits are real logins", GitHubLinks.personLogin(from: "user2600") == "user2600")
check("39 characters is the ceiling, inclusive",
      GitHubLinks.personLogin(from: String(repeating: "a", count: 39)) != nil)

print("\npersonLogin — the refusals")
// THE ONE THAT MATTERS MOST: a repo link is not a person, and reading its
// owner out would watch somebody nobody asked to watch.
check("a repo URL is refused, not read as its owner",
      GitHubLinks.personLogin(from: "https://github.com/torvalds/linux") == nil)
check("an issue URL is refused",
      GitHubLinks.personLogin(from: "https://github.com/torvalds/linux/issues/1") == nil)
check("an org URL is refused", GitHubLinks.personLogin(from: "https://github.com/orgs/rust-lang") == nil)
check("a spoofed host is refused",
      GitHubLinks.personLogin(from: "https://github.com.evil.example/torvalds") == nil)
// The security rule: the login is interpolated into an API path.
check("a slash is refused", GitHubLinks.personLogin(from: "torvalds/linux") == nil)
check("a parent walk is refused", GitHubLinks.personLogin(from: "../orgs") == nil)
check("a dot is refused", GitHubLinks.personLogin(from: "tor.valds") == nil)
check("a query fragment is refused", GitHubLinks.personLogin(from: "tor?valds") == nil)
check("a space is refused", GitHubLinks.personLogin(from: "tor valds") == nil)
check("an underscore is refused", GitHubLinks.personLogin(from: "tor_valds") == nil)
check("non-ASCII is refused", GitHubLinks.personLogin(from: "torvaldß") == nil)
check("empty is refused", GitHubLinks.personLogin(from: "") == nil)
check("a bare @ is refused", GitHubLinks.personLogin(from: "@") == nil)
check("40 characters is over the ceiling",
      GitHubLinks.personLogin(from: String(repeating: "a", count: 40)) == nil)
check("a leading hyphen is refused", GitHubLinks.personLogin(from: "-torvalds") == nil)
check("a trailing hyphen is refused", GitHubLinks.personLogin(from: "torvalds-") == nil)

// ── the ref — one account, one row ─────────────────────────────────────────
print("\npersonRef — case-insensitive, like GitHub itself")
check("the ref is lowercased", GitHubLinks.personRef("Torvalds") == "gh:watchuser:torvalds")
check("two spellings are one ref",
      GitHubLinks.personRef("Torvalds") == GitHubLinks.personRef("torvalds"))
check("it round-trips",
      GitHubLinks.personLogin(fromRef: GitHubLinks.personRef("Torvalds")) == "torvalds")
check("a repo watch is not a person",
      GitHubLinks.personLogin(fromRef: "gh:watchrepo:torvalds/linux") == nil)
check("an event is not a person", GitHubLinks.personLogin(fromRef: "gh:event:123") == nil)
check("a bare issue ref is not a person", GitHubLinks.personLogin(fromRef: "gh:123") == nil)
check("an empty login in a ref → nil", GitHubLinks.personLogin(fromRef: "gh:watchuser:") == nil)

// ── activityLogins — whose events this pass reads ──────────────────────────
print("\nactivityLogins — one request per person, and no request twice")
check("everyone watched is read when none of them is you",
      GitHubLinks.activityLogins(watched: ["a", "b"], ownLogin: "me", contributionsOn: true)
        == ["a", "b"])
check("order is the order given",
      GitHubLinks.activityLogins(watched: ["b", "a"], ownLogin: nil, contributionsOn: false)
        == ["b", "a"])
check("your own account is dropped when the contributions feed already reads it",
      GitHubLinks.activityLogins(watched: ["a", "me"], ownLogin: "me", contributionsOn: true)
        == ["a"])
check("…case-insensitively, because GitHub logins are",
      GitHubLinks.activityLogins(watched: ["ME"], ownLogin: "me", contributionsOn: true) == [])
// The other half, and the one a careless "always drop yourself" would break.
check("your own account IS read when the contributions feed is off",
      GitHubLinks.activityLogins(watched: ["me"], ownLogin: "me", contributionsOn: false)
        == ["me"])
check("an unknown identity drops nobody",
      GitHubLinks.activityLogins(watched: ["a"], ownLogin: nil, contributionsOn: true) == ["a"])
check("a duplicate watch is read once",
      GitHubLinks.activityLogins(watched: ["a", "A"], ownLogin: nil, contributionsOn: false)
        == ["a"])
check("nothing watched reads nothing",
      GitHubLinks.activityLogins(watched: [], ownLogin: "me", contributionsOn: true) == [])

print(failures == 0 ? "\nAll assertions passed." : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

if ! swiftc -O -o "$TMP/run" "$LINKS" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ the shipped GitHubLinks.swift did not compile against the harness"
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
  cp "$LINKS" "$WORK/GitHubLinks.swift"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/GitHubLinks.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$WORK/GitHubLinks.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$WORK/GitHubLinks.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 1. A repo URL read as a profile — the wrong watch, working perfectly.
mutate "a repo URL read as its owner" \
  'guard parts.count == 1 else { return nil }' \
  'guard parts.count >= 1 else { return nil }'

# 2. The host matched loosely — the spoof this rule has always existed to stop.
mutate "the host matched by substring" \
  'url.host == "github.com" || url.host == "www.github.com"' \
  '(url.host ?? "").contains("github.com")'

# 3. The login taken on faith — it goes straight into an API path.
mutate "the login alphabet dropped" \
  'return isValidLogin(q) ? q : nil' \
  'return q.isEmpty ? nil : q'

# 4. The ceiling removed.
mutate "the length ceiling removed" \
  'guard !s.isEmpty, s.count <= 39,' \
  'guard !s.isEmpty,'

# 5. The hyphen edges allowed — GitHub has no such account, so it is a lookup
#    that can only ever fail, offered as though it might work.
mutate "leading and trailing hyphens allowed" \
  '!s.hasPrefix("-"), !s.hasSuffix("-") else { return false }' \
  'true else { return false }'

# 6. The ref left in whatever case was typed — one account, two watches, two
#    requests a sweep, forever.
mutate "the ref no longer lowercased" \
  '"\(personRefPrefix)\(login.lowercased())"' \
  '"\(personRefPrefix)\(login)"'

# 7. Every GitHub ref read as a person — a starred repo becomes somebody to
#    fetch events for.
mutate "the ref prefix no longer checked" \
  'guard ref.hasPrefix(personRefPrefix) else { return nil }' \
  'guard !ref.isEmpty else { return nil }'

# 8. Your own account dropped whatever the feed says — watching yourself with
#    the contributions feed off reads nothing, silently and forever.
mutate "your own account always dropped" \
  'let own = contributionsOn ? ownLogin?.lowercased() : nil' \
  'let own = ownLogin?.lowercased()'

# 9. …and never dropped — one endpoint read twice every sweep.
mutate "your own account never dropped" \
  'let own = contributionsOn ? ownLogin?.lowercased() : nil' \
  'let own: String? = nil'

# 10. The dedupe made case-sensitive, so two spellings of one login are two
#     requests — the same defect as 6, arriving from the other side.
mutate "the dedupe made case-sensitive" \
  'let key = login.lowercased()' \
  'let key = login'

echo
echo "✓ github-person-selftest passed"
