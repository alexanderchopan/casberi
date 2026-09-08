#!/usr/bin/env python3
"""Reading a `@Query` array is a FETCH PLUS A PER-MODEL SNAPSHOT (prd §646).

Build 537 died `0x8BADF00D` process-exit — "failed to terminate gracefully
after 5.0s", 5.588s of application CPU at 16%, 99 seconds into a cold launch —
and, unlike §614's pair, it symbolicates. Against 537's own dSYM the main thread
resolves to `FeedScreen.roomBody.getter` at the `Corpus.hasSurfaced(things)`
term, with `_SwiftData_SwiftUI` → `SwiftData` → `Encodable.encode(to:)` →
`memmove` underneath it: the `@Query` getter re-fetching AND `Codable`-
snapshotting every model it returns. On iOS 18.6 a source room's query carries
no `propertiesToFetch` at all (`sourceRoomLightColumns` is iOS 26+, §623), so
each of those rows arrives with its heavy inline text.

**The count was the finding, not the line.** A built page materialised the same
array FOUR times per body pass — twice for `safetyNetKey` (two `.task(id:)`
modifiers share it, so SwiftUI evaluates it once each), once for
`roomHasContent`, once for the `visible` the rows are drawn from — on every page
`everBuilt` has latched, on every one of the ~30 graph updates a cold-launch
bridge burst fires. The line that died was simply the first of the four.

Nothing in the pass can see this: the build is clean, every static audit passed
on the crashing binary, the screen sweep photographs a healthy app, and the
simulator will not ask an app to terminate under a real CPU quota. So the rule
is held here.

WHAT IT FLAGS

  CHECK 1 — a `.task(id:)` / `.onChange(of:)` key that reads a `@Query`
    property INLINE (`things.count`, `things.isEmpty`). There is nowhere to put
    a guard in an argument expression, so the read happens on every body pass
    for every room, including the rooms whose task returns immediately. This is
    the shape `corpusRevision` was written to replace on 2026-08-11, and it came
    back through a different key.

  CHECK 2 — a member USED as such a key that reads a `@Query` property with no
    early return above the read. `corpusRevision` states the ruling — "the room
    guard lives HERE rather than at the `.task(id:)` below, so a per-source room
    doesn't even run the COUNT" — and `safetyNetKey` owed it twice over, being
    shared by two tasks.

  CHECK 3 — a member that reads the same `@Query` property more than once. One
    body pass, one read; bind it and pass the value down, the way `listBody`
    hands `rows` to `roomBody` and to `listRevision`.

WHAT IT DELIBERATELY DOES NOT FLAG, so it cannot become a lint that cries wolf:

  * Reads inside a `.task { }` / `.onChange { }` CLOSURE. Those run on an event,
    not on a body pass, and are where the safety nets legitimately compare the
    live query against a raw fetch.
  * An accessor that reads the query once and hands the array on (`feedThings`,
    `liveVisible`, `visible`). Those are the binding; the rule is that callers
    read the binding rather than the query.
  * Prose. Every check reads a comment-stripped copy, because this file's own
    source documents the rule by naming the very expressions it bans — the
    Obsidian/Cursor lesson, which this audit would otherwise fail on its first
    run against the code it was written for.

**CHECK 3 WOULD NOT HAVE CAUGHT 537, and that is worth saying out loud.** The
four reads that killed it were spread across four MEMBERS — `safetyNetKey`,
`roomHasContent`, `listRevision`, and the `visible` the rows are drawn from —
and three of them reached the query through an accessor rather than by name, so
no per-member text check could see the total. Checks 1 and 2 catch the two
shapes that shipped; check 3 guards the fix against the obvious regression,
which is a second direct read landing back in one member. It is a ratchet, not
a proof.

CEILING, stated rather than discovered: it follows a key ONE level, from the
`.task(id:)` argument to a member of the same type. A key built by a helper that
calls another helper is invisible to it, and so is any read reached through a
function this file does not name. It catches the two shapes that actually
shipped; it does not prove the property.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = [
    ROOT / "Casberi" / "Casberi" / "Screens",
    ROOT / "Casberi" / "Casberi" / "Shell",
]

QUERY_DECL = re.compile(r"@Query(?:\([^)]*\))?\s+(?:private\s+|fileprivate\s+)?var\s+([A-Za-z_][A-Za-z0-9_]*)")
KEY_MODIFIER = re.compile(r"\.(?:task|onChange)\(\s*(?:id|of)\s*:\s*")
MEMBER_HEAD = re.compile(
    r"^[ \t]*(?:@\w+(?:\([^)]*\))?[ \t]*)*(?:private\s+|fileprivate\s+|internal\s+|public\s+)?"
    r"(?:var|func)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE)


def strip_comments(text: str) -> str:
    """Blank out `//` comments and `/* */` blocks, keeping line numbering."""
    out = []
    i, n = 0, len(text)
    in_line = in_block = in_str = False
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if in_line:
            if c == "\n":
                in_line = False
                out.append(c)
            else:
                out.append(" ")
        elif in_block:
            if c == "*" and nxt == "/":
                in_block = False
                out.append("  ")
                i += 2
                continue
            out.append("\n" if c == "\n" else " ")
        elif in_str:
            out.append(c)
            if c == "\\" and nxt:
                out.append(nxt)
                i += 2
                continue
            if c == '"':
                in_str = False
        else:
            if c == "/" and nxt == "/":
                in_line = True
                out.append("  ")
                i += 2
                continue
            if c == "/" and nxt == "*":
                in_block = True
                out.append("  ")
                i += 2
                continue
            if c == '"':
                in_str = True
            out.append(c)
        i += 1
    return "".join(out)


def query_names(text: str):
    return set(QUERY_DECL.findall(text))


def balanced(text: str, open_at: int) -> int:
    """Index just past the `}` matching the `{` at `open_at`."""
    depth = 0
    i = open_at
    while i < len(text):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return len(text)


def members(text: str):
    """(name, body_source, start_offset) for every `var`/`func` with a body.

    The `{` is searched for only up to the NEXT member head. A stored property
    (`@Query private var things: [Thing]`) has no body, and without that bound
    it would adopt the brace of whatever member follows it — which made the
    query declaration itself read as a member that reads the query twice, on the
    first run of this audit.
    """
    heads = list(MEMBER_HEAD.finditer(text))
    out = []
    for i, m in enumerate(heads):
        limit = heads[i + 1].start() if i + 1 < len(heads) else len(text)
        brace = text.find("{", m.end())
        if brace < 0 or brace >= limit:
            continue
        end = balanced(text, brace)
        out.append((m.group(1), text[m.start():brace], text[brace:end], brace))
    return out


# A read is the identifier used as a VALUE — `things.count`, and equally
# `Corpus.hasSurfaced(things)`, which materialises the whole array and was the
# expression build 537 died in. `things:` (an argument label or a parameter) and
# `things =` (a declaration) are not reads.
def read_lines(body: str, name: str):
    """The distinct LINE numbers, within `body`, on which `name` is read.

    Distinct lines rather than raw hits, because a ternary reads the name twice
    and evaluates it once — `feedThings`'s own
    `isPinnedRoom ? things : Corpus.surfaced(things)` is one read, and counting
    text would make the file's single legitimate accessor the audit's first
    finding.
    """
    lines = body.split("\n")
    hit = sorted({body.count("\n", 0, m.start())
                  for m in re.finditer(rf"(?<![.\w]){name}\b(?!\s*[:=])", body)})
    # A read on a line that OPENS with `return` or `guard` is terminal: at most
    # one path reaches it, so several of them are one read, not several.
    # `WalletHistoryScreen.visible` is `guard let scope else { return all }` and
    # then `return all.filter { … }`; `feedThings` is two `return`s. Both are one
    # evaluation and both were this check's first false findings.
    terminal = [n for n in hit if lines[n].lstrip()[:6] in ("return", "guard ")]
    live = [n for n in hit if n not in terminal]
    return live + terminal[:1]


def shadows(sig: str, body: str, name: str) -> bool:
    """Does this member bind its own `name`, so uses inside are not the query?"""
    return bool(re.search(rf"\b{name}\s*:", sig)
                or re.search(rf"\b(?:let|var)\s+{name}\b", body))


def key_expression(text: str, at: int) -> str:
    """The argument expression of a `.task(id:` / `.onChange(of:` at `at`."""
    depth = 1
    i = at
    while i < len(text) and depth:
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                break
        elif text[i] == "," and depth == 1:
            break
        i += 1
    return text[at:i]


def line_of(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def inline_query_key(text: str):
    """CHECK 1 — findings as (line, key expression)."""
    src = strip_comments(text)
    names = query_names(src)
    if not names:
        return []
    out = []
    for m in KEY_MODIFIER.finditer(src):
        expr = key_expression(src, m.end())
        for name in names:
            if re.search(rf"\b{name}\b\s*\.", expr):
                out.append((line_of(src, m.start()), expr.strip()))
                break
    return out


def key_members(text: str):
    """The member names used as a `.task(id:)` / `.onChange(of:)` key."""
    src = strip_comments(text)
    out = set()
    for m in KEY_MODIFIER.finditer(src):
        expr = key_expression(src, m.end()).strip()
        head = re.match(r"([A-Za-z_][A-Za-z0-9_]*)", expr)
        if head and expr == head.group(1):
            out.add(head.group(1))
    return out


def unguarded_key_member(text: str):
    """CHECK 2 — findings as (line, member name)."""
    src = strip_comments(text)
    names = query_names(src)
    if not names:
        return []
    keys = key_members(text)
    out = []
    for name, sig, body, start in members(src):
        if name not in keys:
            continue
        read = None
        for q in names:
            if shadows(sig, body, q):
                continue
            m = re.search(rf"(?<![.\w]){q}\b(?!\s*[:=])", body)
            if m and (read is None or m.start() < read):
                read = m.start()
        if read is None:
            continue
        before = body[:read]
        # An early exit is a `guard`, or a `return` on an EARLIER LINE. A
        # `return` on the read's own line is the statement CONTAINING the read,
        # not an exit above it — 537's own key is exactly that shape, and the
        # first cut of this check waved it through.
        if re.search(r"\bguard\b", before):
            continue
        last_return = before.rfind("return")
        if last_return >= 0 and "\n" in before[last_return:]:
            continue
        out.append((line_of(src, start), name))
    return out


EVENT_MODIFIER = re.compile(
    r"\.(?:task|onChange|onAppear|onDisappear|onReceive|onSubmit|refreshable|"
    r"onOpenURL|onContinueUserActivity|swipeActions|contextMenu|confirmationDialog|"
    r"alert|sheet|fullScreenCover|onDrop|onLongPressGesture|onTapGesture)\b")


def strip_event_closures(body: str) -> str:
    """Blank the bodies of event closures, keeping line numbering.

    A `.task { }` runs on an EVENT, not on a body pass, and the two staleness
    nets read the live query inside theirs on purpose — comparing it against a
    raw fetch is the whole point of them. Counting those as body reads made
    `listBody` report four, which is how this exclusion got written down.
    """
    out = list(body)
    for m in EVENT_MODIFIER.finditer(body):
        i = m.end()
        # Skip the modifier's own argument list, then take the trailing closure.
        while i < len(body) and body[i] in " \t\n":
            i += 1
        if i < len(body) and body[i] == "(":
            depth = 0
            while i < len(body):
                if body[i] == "(":
                    depth += 1
                elif body[i] == ")":
                    depth -= 1
                    if depth == 0:
                        i += 1
                        break
                i += 1
            while i < len(body) and body[i] in " \t\n":
                i += 1
        if i >= len(body) or body[i] != "{":
            continue
        end = balanced(body, i)
        for j in range(i, end):
            if out[j] != "\n":
                out[j] = " "
    return "".join(out)


def repeated_read(text: str):
    """CHECK 3 — findings as (line, member name, query name, count)."""
    src = strip_comments(text)
    names = query_names(src)
    if not names:
        return []
    out = []
    for name, sig, body, start in members(src):
        body = strip_event_closures(body)
        for q in names:
            if shadows(sig, body, q):
                continue
            hits = len(read_lines(body, q))
            if hits > 1:
                out.append((line_of(src, start), name, q, hits))
    return out


def self_test() -> bool:
    ok = True

    def check(label, got, want):
        nonlocal ok
        if got != want:
            ok = False
            print(f"  FAIL {label}: got {got!r}, want {want!r}")
        else:
            print(f"  ok   {label}")

    decl = "@Query private var things: [Thing]\n"

    # --- CHECK 1 ---
    # The shape `corpusRevision` was written to replace, verbatim.
    check("inline `things.count` key is a finding",
          len(inline_query_key(decl + ".task(id: things.count) { f() }")), 1)
    check("inline `things.isEmpty` in onChange is a finding",
          len(inline_query_key(decl + ".onChange(of: things.isEmpty) { _, _ in f() }")), 1)
    check("a member-name key is not an inline read",
          inline_query_key(decl + ".task(id: corpusRevision) { f() }"), [])
    check("a read inside the CLOSURE is not a key read",
          inline_query_key(decl + ".task(id: scenePhase) { let n = things.count }"), [])
    # Prose naming the banned expression must never score as the ban broken.
    check("a comment is not a finding",
          inline_query_key(decl + "// .task(id: things.count) { f() }"), [])
    check("a file with no @Query is out of scope",
          inline_query_key(".task(id: things.count) { f() }"), [])

    # --- CHECK 2 ---
    # `safetyNetKey` as it shipped in 537: read first, no guard anywhere.
    shipped = (decl +
               'private var safetyNetKey: String {\n'
               '  let drawn = false\n'
               '  return "x" + (drawn || !things.isEmpty ? "|rows" : "|empty")\n'
               '}\n'
               '.task(id: safetyNetKey) { f() }\n')
    check("537's unguarded key is a finding", len(unguarded_key_member(shipped)), 1)
    guarded = (decl +
               'private var safetyNetKey: String {\n'
               '  let base = "x"\n'
               '  guard served else { return base + "|idle" }\n'
               '  return base + (things.isEmpty ? "|empty" : "|rows")\n'
               '}\n'
               '.task(id: safetyNetKey) { f() }\n')
    check("the guarded key passes", unguarded_key_member(guarded), [])
    # `corpusRevision`'s own shape: guard, early return, then the read.
    rev = (decl +
           'private var corpusRevision: Int {\n'
           '  guard source == "All" else { return 0 }\n'
           '  return things.count\n'
           '}\n'
           '.task(id: corpusRevision) { f() }\n')
    check("corpusRevision's shape passes", unguarded_key_member(rev), [])
    # A member that is never used as a key is not this check's business.
    check("an unused member is not a finding", unguarded_key_member(
        decl + 'private var loose: Int { things.count }\n'), [])

    # --- CHECK 3 ---
    # `roomBody` before §646: the emptiness test and the rows, one member apart.
    twice = (decl +
             'private var roomBody: some View {\n'
             '  let a = things.count\n'
             '  let b = things.first\n'
             '  return t(a, b)\n'
             '}\n')
    check("two reads in one member is a finding", len(repeated_read(twice)), 1)
    once = (decl +
            'private var roomBody: some View {\n'
            '  let rows = visible\n'
            '  return t(rows.count, things.isEmpty)\n'
            '}\n')
    check("one read passes", repeated_read(once), [])
    # A property whose NAME merely ends in the query's is a different property.
    # `Corpus.hasSurfaced(things)` hands the WHOLE array over — the expression
    # 537 died in — so a bare use is a read, not only a `things.` member access.
    check("passing the array whole is a read", len(repeated_read(
        decl + 'private var m: some View {\n  let a = Corpus.hasSurfaced(things)\n'
               '  let b = Corpus.surfaced(things)\n  return t(a, b)\n}\n')), 1)
    # A ternary reads the name twice and evaluates it once — `feedThings`.
    check("a ternary is one read", repeated_read(
        decl + 'private var feedThings: [Thing] {\n'
               '  return isPinned ? things : Corpus.surfaced(things)\n}\n'), [])
    # Mutually exclusive returns are one read.
    check("two returns are one read", repeated_read(
        decl + 'private var visible: [Thing] {\n'
               '  guard let scope else { return all }\n'
               '  return all.filter { m($0) }\n}\n'
               .replace("all", "things")), [])
    # A parameter of the same name is not the query.
    check("a shadowing parameter is not the query", repeated_read(
        decl + 'private func k(_ things: [Thing]) -> Int {\n'
               '  h(things.count)\n  return h2(things.first)\n}\n'), [])
    check("a suffix match is not the query", repeated_read(
        decl + 'private var m: Int { a.things.count + b.things.count }\n'), [])
    check("prose does not count as a read", repeated_read(
        decl + 'private var m: Int {\n  // things.count and things.first\n'
               '  return things.count\n}\n'), [])
    # The two staleness nets read the live query inside their own `.task`
    # closures on purpose — that is an event, not a body pass. `listBody` holds
    # four such reads and must stay green.
    check("reads inside event closures do not count", repeated_read(
        decl + 'private func listBody() -> some View {\n'
               '  return List { rowBody }\n'
               '  .task(id: k) { let a = things.count }\n'
               '  .task(id: k) { if things.isEmpty { f() } }\n'
               '}\n'), [])
    check("a body read beside event closures is still a finding", len(repeated_read(
        decl + 'private func listBody() -> some View {\n'
               '  let n = things.count\n'
               '  return List { t(n, things.first) }\n'
               '  .task(id: k) { let a = things.count }\n'
               '}\n')), 1)

    return ok


def main() -> int:
    if "--self-test" in sys.argv:
        good = self_test()
        print("query-read audit self-test:", "ok" if good else "FAILED")
        return 0 if good else 1

    if not self_test():
        print("query-read audit: its OWN self-test failed — the check is broken, not the code")
        return 1

    findings = []
    scanned = 0
    for root in SOURCES:
        for path in sorted(root.rglob("*.swift")):
            text = path.read_text(encoding="utf-8")
            if not query_names(strip_comments(text)):
                continue
            scanned += 1
            rel = path.relative_to(ROOT)
            for line, expr in inline_query_key(text):
                findings.append(
                    f"{rel}:{line}: a `.task(id:)`/`.onChange(of:)` key reads the @Query "
                    f"inline (`{expr}`) — that is a fetch and a per-model snapshot on EVERY "
                    f"body pass, for every room, including the ones whose task returns at "
                    f"its first line. Key it on a member that guards first (prd §646).")
            for line, name in unguarded_key_member(text):
                findings.append(
                    f"{rel}:{line}: `{name}` is used as a `.task(id:)` key and reads the "
                    f"@Query with no early return above it — so a room whose task declines "
                    f"still materialises itself to be told so, twice over when two tasks "
                    f"share the key. `corpusRevision` states the ruling (prd §646).")
            for line, name, q, hits in repeated_read(text):
                findings.append(
                    f"{rel}:{line}: `{name}` reads `{q}` {hits} times — a @Query read is not "
                    f"cached between reads, so that is {hits} fetches and {hits} rounds of "
                    f"per-model Codable snapshotting in one body pass. Bind it once and pass "
                    f"the array down (prd §646).")

    if findings:
        print("query-read audit: FAIL")
        for f in findings:
            print("  " + f)
        return 1
    print(f"query-read audit: ok ({scanned} @Query-holding views swept)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
