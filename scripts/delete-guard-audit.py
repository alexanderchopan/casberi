#!/usr/bin/env python3
"""Absence-driven delete audit (the `pruneDeleted` rule).

A PRUNE deletes a landed row because an upstream read did not mention it.
That is the right thing to do when the read succeeded and the row is really
gone, and it is a disaster when the read merely came back empty:

    an un-materialized iCloud folder ENUMERATES EMPTY. A revoked
    security-scoped bookmark enumerates empty. An unmounted network volume
    enumerates empty. A Photos library mid-hiccup answers with nothing.

Read as "everything was deleted upstream", any of those wipes the source out
of the corpus — and because the store is CloudKit-mirrored, it wipes it off
every other device the person owns before they can quit the app.

So the rule, which `ScreenshotIngest.pruneDeleted` states and every sibling is
supposed to copy: NEVER PRUNE ON AN EMPTY UPSTREAM READ. An empty read means
"we could not see", never "it is all gone". Erring toward KEEP costs a stale
row somebody can delete; erring the other way costs their data.

This is mechanical because it has already drifted once. `ObsidianBridge`
guards BOTH sides (`!existing.isEmpty && !outcome.allRefs.isEmpty`) and says
in a comment why. `FilesBridge` — the bridge it was modelled on, whose own
setup copy tells people to point it at iCloud Drive — guarded only `existing`
and shipped that way, so one empty walk deleted every Files row on every
device. Found by this audit's first run (2026-08-19), which is the same way
`FilesIngest`'s cap-ordering bug was found: as the sibling of an Obsidian fix
nobody carried across.

THE SHAPE IT LOOKS FOR is narrow on purpose — absence-driven deletion, and
nothing else:

    let gone = landed.subtracting(upstream)     …then delete
    for x in landed where !upstream.contains(x) …then delete

Both name the upstream collection right there, so the audit knows which
identifier must be proven non-empty. A delete that is NOT absence-driven — a
disconnect, an unwatch, a user-asked-for removal, a demo teardown — is
deliberately invisible here: those delete because somebody said so, and an
empty upstream read has nothing to do with it. That narrowness is what keeps
this from being a lint that cries wolf: it flags two shapes in one tree, and
both of them can lose a corpus.

WHAT IT DELIBERATELY DOES NOT CHECK:
  · That the guard is POSITIONED before the loop. It is line-order-blind, and
    a guard that returns early is the only way anyone writes this. Proving
    dominance means parsing Swift; a function that names the emptiness of its
    own upstream set is honest enough, and a function that never mentions it
    is the finding either way (`keychain-audit.py`'s file-scoped reasoning,
    one level tighter).
  · Whether the upstream read was CORRECT — only that its emptiness was
    considered.

Usage:  scripts/delete-guard-audit.py [--self-test]
Exit 0 = clean.
"""

import re
import sys
import pathlib
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = [ROOT / "Casberi/Casberi", ROOT / "Casberi/Shared",
           ROOT / "Casberi/ShareExtension", ROOT / "Casberi/CasberiWidgets"]

DELETE = re.compile(r"(?:context|modelContext)\s*\.\s*delete\s*\(")
# `landed.subtracting(upstream)` — the upstream set is the capture.
SUBTRACT = re.compile(r"\.subtracting\(\s*([A-Za-z_][\w.]*)\s*\)")
# `where !upstream.contains(x)` / `guard !upstream.contains(x)` — likewise.
ABSENT = re.compile(r"!\s*([A-Za-z_][\w.]*)\.contains\(")

# Prunes that are exempt from naming their upstream set's emptiness, each with
# the reason it cannot be wiped by an empty read. Empty by design — an entry
# is a conscious "an empty upstream read here cannot delete a corpus."
# Values are (why it is safe, the literal that PROVES it — or None). The
# second half exists because an exemption that merely switches the check off
# is a snooze: the mechanism its reason names could be deleted tomorrow with
# nothing noticing, which is the failure this whole audit exists to prevent,
# one level up. Caught by mutation on this audit's first run — removing the
# HomeKit ingest's `if !homes.isEmpty` guard left the tree green. (That entry,
# idiom (1) below, went with the HomeKit bridge on 2026-09-04; the numbering
# is left alone so the surviving reasons keep the labels they were written
# with.)
#
# A prune reaches this list only by proving its upstream read SUCCEEDED some
# other way than testing the named set's emptiness. The shapes in this tree do,
# by three surviving idioms, and naming which one is the whole value of the
# entry: the next person to touch one of these functions needs to know what
# they must not remove.
KNOWN_SAFE = {
    # (2) A reachability flag, which is STRONGER than an emptiness test: it
    #     separates 'the relay answered nothing' from 'no relay answered'.
    ("NostrIngest.swift", "heal"):
        ("guarded by `guard result.reached else { continue }` — a timed-out "
        "chunk is never treated as gone, so an empty `present` can only mean "
        "the relay answered and said so.",
         'guard result.reached else { continue }'),

    # (3) Success-gated accumulation: the prune's own domain is only widened
    #     after a good fetch, so a failed chunk is unreachable by the delete.
    ("BlueskyIngest.swift", "heal"):
        ("`attempted.formUnion(chunk)` runs only after the getPosts call "
        "returns, and the delete requires `attempted.contains(uri)` — a chunk "
        "that failed is never a candidate for pruning.",
         'attempted.formUnion(chunk)'),

    # (4) The failure path returns before the prune is reached at all.
    ("ContactsIngest.swift", "ingest"):
        ("`enumerateContacts` is wrapped in do/catch returning nil, so a failed "
        "walk never reaches the reconcile; an empty book really is empty.",
         'try store.enumerateContacts'),

    # Empty is MEANINGFUL here, and pruning on it is the intended behaviour —
    # the opposite of the rule this audit enforces, which is why they are
    # named rather than made to fake a guard.
    ("ScheduleIngest.swift", "ingestEvents"):
        "`seen` is the events AHEAD; empty legitimately means nothing is "
        "upcoming, and clearing rows that have slipped into the past is the "
        "point. Outright EventKit deletions are `healCalendar`'s job, which "
        "has its own guard.",
    ("ScheduleIngest.swift", "ingestReminders"):
        "the same forward-window reasoning as `ingestEvents`.",

    # Not absence-driven at all — these delete because somebody said so, or
    # because the upstream explicitly reported a deletion. The audit sees the
    # `!x.contains` shape and cannot tell what the collection MEANS.
    ("MailBridge.swift", "heal"):
        "`healRunning` is a re-entrancy flag (`Set<MailProvider>`), not an "
        "upstream read — `!healRunning.contains(provider)` is single-flight.",
    ("IngestSupport.swift", "removeWallet"):
        "`stillWatched` confirms a wallet the person UNWATCHED is really gone "
        "from the watch list; deleting its rows is the requested action.",
    ("DropboxBridge.swift", "refresh"):
        "deletes on Dropbox's own explicit `\".tag\" == \"deleted\"` delta "
        "entry, never on absence — that is what the delta cursor is for.",
}


def strip_comments(src):
    out = []
    for line in src.splitlines():
        cleaned, in_str, i = [], False, 0
        while i < len(line):
            c = line[i]
            if c == '"' and (i == 0 or line[i - 1] != "\\"):
                in_str = not in_str
            if not in_str and line.startswith("//", i):
                break
            cleaned.append(c)
            i += 1
        out.append("".join(cleaned))
    return re.sub(r"/\*.*?\*/", "", "\n".join(out), flags=re.S)


def functions(lines):
    """(name, start, end) per top-level-ish func, by brace depth of `func`."""
    spans = []
    for i, line in enumerate(lines):
        m = re.search(r"\bfunc\s+(\w+)", line)
        if not m:
            continue
        depth, started = 0, False
        for j in range(i, len(lines)):
            depth += lines[j].count("{") - lines[j].count("}")
            if "{" in lines[j]:
                started = True
            if started and depth <= 0:
                spans.append((m.group(1), i, j))
                break
        else:
            spans.append((m.group(1), i, len(lines) - 1))
    return spans


def audit(paths, known_safe=KNOWN_SAFE):
    findings = []
    for root in paths:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.swift")):
            code = strip_comments(path.read_text(errors="ignore"))
            if not DELETE.search(code):
                continue
            lines = code.splitlines()
            try:
                rel = path.relative_to(ROOT)
            except ValueError:
                rel = path
            for name, lo, hi in functions(lines):
                body = "\n".join(lines[lo:hi + 1])
                if not DELETE.search(body):
                    continue
                exempt = known_safe.get((path.name, name))
                if exempt is not None:
                    why, proof = exempt if isinstance(exempt, tuple) else (exempt, None)
                    if proof and proof not in code:
                        findings.append(
                            f"{rel}:{lo + 1}: `{name}` is exempt because {why} "
                            f"— but `{proof}` is gone, so nothing proves the "
                            f"upstream read succeeded any more")
                    continue
                upstream = set(SUBTRACT.findall(body)) | set(ABSENT.findall(body))
                for var in sorted(upstream):
                    # The identifier's own emptiness must be considered
                    # somewhere in the function. `a.b.c` may be guarded as
                    # `a.b.c.isEmpty` or via its root — accept either.
                    root_var = var.split(".")[0]
                    if re.search(rf"\b{re.escape(var)}\.isEmpty\b", body):
                        continue
                    if re.search(rf"\b{re.escape(root_var)}\.isEmpty\b", body):
                        continue
                    findings.append(
                        f"{rel}:{lo + 1}: `{name}` deletes rows absent from "
                        f"`{var}` without ever testing whether `{var}` is "
                        f"EMPTY — an upstream read that returns nothing would "
                        f"delete every row here, on every synced device")
    return findings


def self_test():
    D = "context.delete(thing)"
    cases = {
        "Unguarded.swift": (
            f"func prune() {{\n  let gone = existing.subtracting(walked)\n"
            f"  for r in gone {{ {D} }}\n}}\n",
            True, "a subtracting prune that never tests the upstream set"),
        "Guarded.swift": (
            f"func prune() {{\n  guard !walked.isEmpty else {{ return }}\n"
            f"  let gone = existing.subtracting(walked)\n"
            f"  for r in gone {{ {D} }}\n}}\n",
            False, "a subtracting prune that guards its upstream set"),
        # The exact FilesBridge shape: the LANDED side guarded, the UPSTREAM
        # side not. This is the bug; guarding one side must not clear it.
        "HalfGuarded.swift": (
            f"func prune() {{\n  if !existing.isEmpty {{\n"
            f"    let gone = existing.subtracting(walked)\n"
            f"    for r in gone {{ {D} }}\n  }}\n}}\n",
            True, "the landed side guarded and the upstream side not"),
        "Contains.swift": (
            f"func prune() {{\n  for t in things where !found.contains(t.ref) {{ {D} }}\n}}\n",
            True, "a !contains prune with no emptiness test"),
        "ContainsGuarded.swift": (
            f"func prune() {{\n  guard !found.isEmpty else {{ return }}\n"
            f"  for t in things where !found.contains(t.ref) {{ {D} }}\n}}\n",
            False, "a !contains prune that guards"),
        "Dotted.swift": (
            f"func prune() {{\n  guard !outcome.allRefs.isEmpty else {{ return }}\n"
            f"  let gone = existing.subtracting(outcome.allRefs)\n"
            f"  for r in gone {{ {D} }}\n}}\n",
            False, "an upstream set reached through a property path"),
        # Not absence-driven: somebody asked for this.
        "Disconnect.swift": (
            f"func disconnect() {{\n  for row in rows {{ {D} }}\n}}\n",
            False, "a disconnect, which deletes because somebody said so"),
        "NoDelete.swift": (
            "func prune() {\n  let gone = existing.subtracting(walked)\n  _ = gone\n}\n",
            False, "absence computed but nothing deleted"),
        # A comment claiming the guard must not stand in for one.
        "CommentOnly.swift": (
            f"func prune() {{\n  // guard !walked.isEmpty else {{ return }}\n"
            f"  let gone = existing.subtracting(walked)\n"
            f"  for r in gone {{ {D} }}\n}}\n",
            True, "a guard that exists only in a comment"),
    }
    ok = True
    with tempfile.TemporaryDirectory() as tmp:
        for name, (body, should_flag, why) in cases.items():
            d = pathlib.Path(tmp) / name.lower().replace(".swift", "")
            d.mkdir()
            (d / name).write_text(body)
            flagged = bool(audit([d]))
            if flagged != should_flag:
                ok = False
            print(f"  {'ok  ' if flagged == should_flag else 'FAIL'} "
                  f"{'flags' if should_flag else 'passes'} {why}")
    return ok


if "--self-test" in sys.argv:
    print("delete-guard self-test")
    sys.exit(0 if self_test() else 1)

problems = audit(SOURCES)
if problems:
    print("✗ absence-driven deletes:")
    for p in problems:
        print(f"  {p}")
    sys.exit(1)
print("✓ absence-driven deletes: every prune proves its upstream read was non-empty")
