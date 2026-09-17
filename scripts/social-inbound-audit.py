#!/usr/bin/env python3
"""AN ACCOUNT MARKED `mine` LANDS ITS OWN REPLIES, OR THE INBOUND HALF IS BLIND.

**The bug this is the scar tissue for (2026-09-17).** §239 built the inbound
half — who replied to you, who liked your posts, who followed you — and it
reads through `SocialInbound.ownRecentPosts`, which walks YOUR posts *out of
the corpus* and asks the network what happened under each one. So everything
that half can see is decided somewhere else entirely: by whatever the
account's own page chose to land.

Both pages chose to land no replies. Farcaster's `refresh` passed
`topLevelOnly: true` and Bluesky's author feed asked for
`filter=posts_no_replies` — the same rule under two spellings, and a correct
rule for a stranger, whose replies are half of a conversation you are not in.
Applied to your own account it meant `ownRecentPosts` held only your top-level
posts, so `landReplies` asked "did anyone answer?" about those alone. On both
networks most conversation happens *under* a reply. Every answer to anything
you said in a thread — the commonest notification either network produces —
had no source at all, with the switch on, with nothing on any screen saying
so. It was reported as exactly what it looks like from outside: "I don't
always see my notifications from Farcaster."

Nothing failed to compile, nothing rendered wrong, and no other check here
could see it: two correct-looking filters, four files apart from the read they
silently emptied. That distance is the whole reason this exists.

**(1) Farcaster's account page does not decline replies unconditionally.**
A literal `topLevelOnly: true` in `FarcasterIngest.swift` is the bug as
written — `refresh` is the only caller that passes the flag, and it must gate
it on the account (`topLevelOnly: !account.mine`).

**(2) Bluesky's author feed does not ask for `posts_no_replies`
unconditionally.** The literal may stay — it is right for a watched stranger —
but only where `posts_with_replies` stands beside it, which is what a gate on
`mine` looks like.

**(3) `ownRecentPosts` still filters on a nil `socialContext`.** That filter
is what makes the list YOURS. Someone else's reply to you lands wearing
`"reply"`; drop the filter and the pass starts asking the network for replies
to *their* posts, under your name, spending the whole budget on the wrong
thread. It is also what admits your own replies, which land unmarked. Read
inside that function's braces, not across the file: the first draft of this
check grepped the whole file, so the filter could be deleted from the one
function that needs it and survive anywhere else — a guard reporting on a line
it was not looking at.

**(5) `share()` still tells a reply from a post.** The other half of check 3,
and the way the §804 fix could have swapped one blindness for the other.
`ownPostPage` is six; with replies landing, a plain newest-six would hand every
slot to whichever kind you produce more of — on these networks, replies — and
stop asking about your own posts entirely. Nothing would look wrong. So each
kind gets a floor, and the split turns on `parent`.

**(4) `NotifySweep` still keys `repliesReceived` on `socialContext ==
"reply"`.** This is the other side of check 3 and the one thing the fix could
have broken: your own replies now land, and if the notification keyed on
anything looser — the source, the kind, a parent — you would be notified that
you answered yourself, every time you post in a thread.

**STATED CEILINGS.**

  * It cannot prove the reads then WORK. That a reply landed says nothing
    about whether the node answered `castsByParent`, and only a device with a
    real thread under a real account shows that end to end (`-fcMine`,
    `-inboundProbe`).
  * Check 1 is a text match. A caller computing the flag into a variable first
    (`let only = true; landPage(topLevelOnly: only)`) passes it. What it
    catches is the shape the bug actually had, twice.
  * Check 2 cannot tell `posts_with_replies` is on the RIGHT arm of the
    ternary. Reversed, it passes here and lands a stranger's replies while
    still hiding yours.
  * Check 5 proves a split EXISTS and reads the right field. It does not prove
    the floor is a sensible size, and a floor of zero would pass it.
  * It says nothing about the OTHER three reasons a Farcaster notification
    never arrives: `mentions` and `mine` both default off with no screen
    saying so, `ownPostPage` asks about six posts and no more, and nobody
    recasting you is read at all. Those are rulings, not regressions.

`--self-test` runs first and is required, per this repo's rule that a check
which cannot demonstrate it catches anything certifies nothing.
"""
import re
import sys
import pathlib

SOURCES = ["Casberi/Casberi", "Casberi/Shared"]

FARCASTER = "FarcasterIngest.swift"
BLUESKY = "BlueskyIngest.swift"
INBOUND = "SocialInbound.swift"
SWEEP = "NotifySweep.swift"


def strip_comments(text):
    """Comments out, STRING LITERALS KEPT — checks 1 and 2 are about literals.

    Scanned rather than regexed because these files are full of
    `"https://…"`, and a naive `//` rule eats the rest of every line holding
    one.
    """
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == '"':
            out.append(c)
            i += 1
            while i < n:
                out.append(text[i])
                if text[i] == "\\" and i + 1 < n:
                    out.append(text[i + 1])
                    i += 2
                    continue
                if text[i] == '"':
                    i += 1
                    break
                if text[i] == "\n":      # unterminated; don't run away
                    i += 1
                    break
                i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def strip_all(text):
    """Comments AND string literals out — for brace matching, where a `{`
    inside a literal would throw the count off."""
    text = strip_comments(text)
    return re.sub(r'"(?:\\.|[^"\\\n])*"', '""', text)


def func_body(text, name):
    """The body of one `func <name>`, by brace matching.

    Check 3 used to grep the whole FILE for its filter, which meant the filter
    could be deleted from `ownRecentPosts` and the check would keep passing on
    any other function in the file that happened to compare a context to nil.
    A guard that reports on a line it is not looking at is worse than none.

    Returns "" when the function is absent, which the caller treats as a
    finding rather than a pass.
    """
    body = strip_all(text)
    m = re.search(r"\bfunc\s+" + re.escape(name) + r"\b", body)
    if not m:
        return ""
    open_at = body.find("{", m.end())
    if open_at < 0:
        return ""
    depth, i = 0, open_at
    while i < len(body):
        if body[i] == "{":
            depth += 1
        elif body[i] == "}":
            depth -= 1
            if depth == 0:
                return body[open_at:i + 1]
        i += 1
    return ""


def audit_text(name, text):
    out = []
    body = strip_comments(text)

    if name == FARCASTER:
        for m in re.finditer(r"topLevelOnly\s*:\s*true\b", body):
            line = body[:m.start()].count("\n") + 1
            out.append(f"{name}:{line}: topLevelOnly: true declines YOUR replies too — "
                       "gate it on the account (topLevelOnly: !account.mine)")

    if name == BLUESKY:
        for m in re.finditer(r'"posts_no_replies"', body):
            line = body[:m.start()].count("\n") + 1
            near = body[max(0, m.start() - 400):m.end() + 400]
            if '"posts_with_replies"' not in near:
                out.append(f"{name}:{line}: the author feed asks for posts_no_replies "
                           "unconditionally — an account marked mine needs "
                           "posts_with_replies, or the inbound half never sees a thread")

    if name == INBOUND:
        own = func_body(text, "ownRecentPosts")
        if not own:
            out.append(f"{name}: ownRecentPosts is gone or unparseable — "
                       "this check has lost its subject")
        elif not re.search(r"socialContext\s*==\s*nil", own):
            out.append(f"{name}: ownRecentPosts no longer filters on a nil socialContext — "
                       "a reply someone sent YOU would be read as a post of yours")
        # (5) neither kind may starve the other. With replies landing, a plain
        # newest-N would hand every slot to whichever kind you produce more of
        # — for most active accounts, replies — and silently stop asking about
        # the other half. The split reads `parent`, which is what tells them
        # apart.
        share = func_body(text, "share")
        if not share:
            out.append(f"{name}: no share() — ownPostPage is handed out newest-first, "
                       "so replies can take every slot from your own posts (or the reverse)")
        elif not re.search(r"\bparent\s*==\s*nil", share):
            out.append(f"{name}: share() no longer tells a reply from a post — "
                       "the floor it guarantees each kind cannot hold")

    if name == SWEEP:
        if not re.search(r'socialContext\s*==\s*"reply"', body):
            out.append(f"{name}: repliesReceived is not keyed on socialContext == \"reply\" — "
                       "your own replies land unmarked and would notify you about yourself")

    return out


# ---------------------------------------------------------------- fixtures

FIXED_FARCASTER = """
added += await landPage(messages, topLevelOnly: !account.mine, existing: &existing,
                        landed: landed, backfill: backfill, context: context)
let url = "https://farcaster.xyz/\\(username)/\\(short)"
"""

BROKEN_FARCASTER = """
added += await landPage(messages, topLevelOnly: true, existing: &existing,
                        landed: landed, backfill: backfill, context: context)
"""

COMMENTED_FARCASTER = """
// The old rule read `topLevelOnly: true` and that is the bug.
added += await landPage(messages, topLevelOnly: !account.mine, existing: &existing)
"""

FIXED_BLUESKY = """
comps.queryItems = [
    URLQueryItem(name: "actor", value: handle),
    URLQueryItem(name: "filter",
                 value: account.mine ? "posts_with_replies" : "posts_no_replies"),
]
"""

BROKEN_BLUESKY = """
comps.queryItems = [
    URLQueryItem(name: "actor", value: handle),
    URLQueryItem(name: "filter", value: "posts_no_replies"),
]
"""

DOC_ONLY_BLUESKY = """
/// The feed is fetched with `filter=posts_no_replies` — the one fact to check.
comps.queryItems = [URLQueryItem(name: "limit", value: "30")]
"""

SHARE = """
static func share(_ pool: [Thing]) -> [Thing] {
    var taken: [Thing] = []
    for thing in pool {
        if thing.parent == nil { taken.append(thing) }
    }
    return taken
}
"""

FIXED_INBOUND = """
static func ownRecentPosts(_ landed: [String: Thing]) -> [Thing] {
    let mine = landed.values.filter { thing in
        thing.isLive && thing.authorHandle == handle && thing.socialContext == nil
    }
    return share(mine)
}
""" + SHARE

BROKEN_INBOUND = """
static func ownRecentPosts(_ landed: [String: Thing]) -> [Thing] {
    let mine = landed.values.filter { thing in
        thing.isLive && thing.authorHandle == handle
    }
    return share(mine)
}
""" + SHARE

# The shape the file-wide grep passed: the filter is gone from the function
# that needs it, and survives in an unrelated one.
DECOY_INBOUND = """
static func ownRecentPosts(_ landed: [String: Thing]) -> [Thing] {
    let mine = landed.values.filter { $0.isLive && $0.authorHandle == handle }
    return share(mine)
}
static func somethingElse(_ t: Thing) -> Bool {
    t.socialContext == nil
}
""" + SHARE

NO_SHARE = """
static func ownRecentPosts(_ landed: [String: Thing]) -> [Thing] {
    let mine = landed.values.filter { $0.socialContext == nil }
    return Array(mine.prefix(ownPostPage))
}
"""

BLIND_SHARE = FIXED_INBOUND.replace("thing.parent == nil", "thing.isLive")

FIXED_SWEEP = """
if thing.socialContext == "follow" { return .followersGained }
if thing.socialContext == "reply" { return .repliesReceived }
"""

BROKEN_SWEEP = """
if thing.socialContext == "follow" { return .followersGained }
if thing.kind == .chat { return .repliesReceived }
"""

URL_HEAVY = """
let a = "https://hub.example/v1/castsByParent?fid=1"
let b = "https://hub.example/v1/reactionsByCast"
"""


def self_test():
    cases = [
        ("passes the gated Farcaster landing", FARCASTER, FIXED_FARCASTER, 0),
        ("flags  an unconditional topLevelOnly: true", FARCASTER, BROKEN_FARCASTER, 1),
        ("passes the rule named in a comment", FARCASTER, COMMENTED_FARCASTER, 0),
        ("passes a URL-heavy Farcaster file", FARCASTER, URL_HEAVY, 0),
        ("passes the gated Bluesky filter", BLUESKY, FIXED_BLUESKY, 0),
        ("flags  an unconditional posts_no_replies", BLUESKY, BROKEN_BLUESKY, 1),
        ("passes the filter named only in a doc line", BLUESKY, DOC_ONLY_BLUESKY, 0),
        ("passes ownRecentPosts keeping its nil filter", INBOUND, FIXED_INBOUND, 0),
        ("flags  ownRecentPosts losing the nil filter", INBOUND, BROKEN_INBOUND, 1),
        ("flags  the filter surviving only in another func", INBOUND, DECOY_INBOUND, 1),
        ("flags  a newest-N page with no share()", INBOUND, NO_SHARE, 1),
        ("flags  a share() that cannot spot a reply", INBOUND, BLIND_SHARE, 1),
        ("passes repliesReceived keyed on the marker", SWEEP, FIXED_SWEEP, 0),
        ("flags  repliesReceived keyed on anything looser", SWEEP, BROKEN_SWEEP, 1),
        ("passes an unrelated file", "A.swift", BROKEN_FARCASTER, 0),
        ("passes an empty file", FARCASTER, "", 0),
    ]
    ok = True
    for label, name, text, want in cases:
        got = len(audit_text(name, text))
        mark = "ok  " if got == want else "FAIL"
        if got != want:
            ok = False
            for f in audit_text(name, text):
                print(f"       · {f}")
        print(f"  {mark} {label} (expected {want}, got {got})")
    return ok


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    if "--self-test" in sys.argv:
        print("social-inbound-audit self-test")
        if not self_test():
            print("SELF-TEST FAILED")
            return 1
        print("  self-test passed")

    findings, scanned, seen = [], 0, set()
    for src in SOURCES:
        base = root / src
        if not base.exists():
            continue
        for path in sorted(base.rglob("*.swift")):
            scanned += 1
            seen.add(path.name)
            findings.extend(audit_text(path.name,
                                       path.read_text(encoding="utf-8", errors="replace")))

    # A check whose subject has been renamed away certifies nothing — say so
    # rather than reporting clean over four files that no longer exist.
    for needed in (FARCASTER, BLUESKY, INBOUND, SWEEP):
        if needed not in seen:
            findings.append(f"{needed}: not found — this check has lost its subject")

    if findings:
        print(f"social-inbound-audit: {len(findings)} finding(s) in {scanned} files")
        for f in findings:
            print(f"  ✗ {f}")
        return 1
    print(f"social-inbound-audit: clean ({scanned} files) — "
          "an account marked mine lands its own replies")
    return 0


if __name__ == "__main__":
    sys.exit(main())
