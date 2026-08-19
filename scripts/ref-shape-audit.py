#!/usr/bin/env python3
"""Ref-shape audit — a room that matches a prefix nothing produces.

Every bridge keys its rows with a `sourceRef` in its own namespace
(`peer:sell:…`, `privacypools:dep:…`, `cloudflare:cert:…`), and the room heads
read those rows back by matching the prefix. The two halves live in different
files, are written months apart, and NOTHING has ever checked that they agree.

When they stop agreeing the room does not break — it goes QUIET. Every row is
still there, still landed, still correct; the head just matches none of them
and draws nothing, which from outside is indistinguishable from "you have no
deposits yet."

It has happened. §311's retag fetched `privacypools:deposit:` while deposits
land `privacypools:dep:`, so no state tag ever moved and every deposit read
`Pending` for life — cleared ones included — for as long as the feature had
existed. Nobody could see it: the alert row still landed, the rain still fell,
and the card rendered perfectly with the wrong word on it.

THE RULE: every ref prefix a CONSUMER matches must be produced by something.

Producers are ref-shaped string literals anywhere in the tree; consumers are
`hasPrefix("<ns>:…")` tests. Both are compared on their STATIC HEAD — the text
before the first `\\(` interpolation — because most refs are built
(`"privacypools:status:\\(label)"`). A consumer is satisfied when some head is
a prefix of it, or it is a prefix of some head.

That the head is compared rather than the whole literal is what makes this
usable, and it is also its ceiling, stated plainly: a producer that
interpolates EARLY (`"wallet:\\(viaPermit2 ? "permit2" : "approval"):…"`)
leaves a head of `wallet:`, which satisfies every `wallet:*` consumer. So this
catches a namespace that is wrong, not a namespace that is merely imprecise.
It would have caught `deposit:` vs `dep:` — measured, that pair is a mutation
below — because that producer's head is the whole specific prefix.

WHAT IT DELIBERATELY DOES NOT CHECK. The reverse direction — a row PRODUCED
under a ref no consumer will ever match — was built, measured, and REFUSED:
it reports 82 findings on a clean tree, because most demo rows legitimately
carry `demo:`-prefixed refs and most rooms filter by `source` rather than by
ref, so the orphans are overwhelmingly correct. Catching that class (§349's
Peer/Privacy Pools demo refs, §340's Cloudflare ones) needs a source→room-head
join this cannot do from text alone, and a check that fires 82 times on a
healthy tree gets turned off within a week. It is better to say so here than
to ship it behind an 82-entry exemption list, which is a snooze wearing a
registry's clothes.

Usage:  scripts/ref-shape-audit.py [--self-test]
Exit 0 = clean.
"""

import re
import sys
import pathlib
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = [ROOT / "Casberi"]

REF = re.compile(r"^[a-z][a-z0-9]*:")
LITERAL = re.compile(r'"((?:[a-z][a-z0-9]*:)[^"\n]*)"')
CONSUMER = re.compile(r'hasPrefix\(\s*"([^"\n]+)"\s*\)')

# Consumers that legitimately match a prefix nothing produces any more. Each
# entry is a conscious ruling, and the reason is the part that gets skipped
# when nothing enforces it.
KNOWN_UNPRODUCED = {
    "dexscreener:":
        "a MIGRATION. `RootShell` rewrites rows landed under the old "
        "`dexscreener:` namespace to `tokens:`, so the only things it can "
        "match are already in somebody's store and no code produces the shape "
        "any more. Deleting this consumer would strand those rows forever.",
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


def head(literal):
    """The static prefix — everything before the first interpolation."""
    return literal.split("\\(")[0]


def audit(paths, known=KNOWN_UNPRODUCED):
    produced, consumed = set(), {}
    for root in paths:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.swift")):
            code = strip_comments(path.read_text(errors="ignore"))
            # A consumer's OWN literal must not count as a producer, or every
            # `hasPrefix` trivially satisfies itself and the check can never
            # fail. Blank the match tests out before collecting producers.
            producing = CONSUMER.sub('hasPrefix("")', code)
            for m in LITERAL.finditer(producing):
                produced.add(head(m.group(1)))
            for m in CONSUMER.finditer(code):
                v = m.group(1)
                if REF.match(v):
                    try:
                        rel = path.relative_to(ROOT)
                    except ValueError:
                        rel = path
                    consumed.setdefault(head(v), set()).add(str(rel))

    findings = []
    for prefix, files in sorted(consumed.items()):
        if prefix in known:
            continue
        # A producer whose head IS the consumer, extends it, or is extended by
        # it. `p != prefix` would reject the consumer's own literal, but the
        # consumer literal is itself in `produced` — so require a producer that
        # is strictly longer, or a shorter head the consumer refines.
        if any(p.startswith(prefix) or prefix.startswith(p) for p in produced):
            continue
        findings.append(
            f"{prefix!r}: matched by {', '.join(sorted(files))} but nothing in "
            f"the tree produces a ref under it — this room can only ever draw "
            f"nothing, which reads as \"you have none yet\"")

    for prefix, why in known.items():
        if prefix not in consumed:
            findings.append(
                f"{prefix!r}: in KNOWN_UNPRODUCED ({why}) but nothing matches "
                f"it any more — the exemption now excuses nothing")
    return findings


def self_test():
    cases = {
        # THE §311 bug: the room matches `deposit:`, the bridge lands `dep:`.
        "Renamed.swift": ('let ref = "privacypools:dep:\\(label)"\n'
                          'if r.hasPrefix("privacypools:deposit:") { }\n',
                          True, "a consumer whose namespace the producer renamed"),
        "Agrees.swift": ('let ref = "privacypools:dep:\\(label)"\n'
                         'if r.hasPrefix("privacypools:dep:") { }\n',
                         False, "a consumer and producer that agree"),
        # The interpolated-producer case that must NOT flag.
        "Interpolated.swift": ('let ref = "instagram:\\(marker):\\(row.link)"\n'
                               'if r.hasPrefix("instagram:saved:") { }\n',
                               False, "a consumer refining an interpolated head"),
        "ViaConstant.swift": ('static let depositPrefix = "peer:sell:"\n'
                              'if r.hasPrefix("peer:sell:") { }\n',
                              False, "a prefix declared once and used both ways"),
        "NoProducer.swift": ('if r.hasPrefix("ghost:thing:") { }\n',
                             True, "a namespace nothing anywhere produces"),
        # Prose naming a dead prefix must not stand in for a producer.
        "CommentOnly.swift": ('// rows land as "ghost:thing:<id>"\n'
                              'if r.hasPrefix("ghost:thing:") { }\n',
                              True, "a producer that exists only in a comment"),
        "NotARef.swift": ('if s.hasPrefix("Hello") { }\n',
                          False, "a hasPrefix that is not a ref at all"),
    }
    ok = True
    with tempfile.TemporaryDirectory() as tmp:
        for name, (body, should_flag, why) in cases.items():
            d = pathlib.Path(tmp) / name.lower().replace(".swift", "")
            d.mkdir()
            (d / name).write_text(body)
            flagged = bool(audit([d], known={}))
            if flagged != should_flag:
                ok = False
            print(f"  {'ok  ' if flagged == should_flag else 'FAIL'} "
                  f"{'flags' if should_flag else 'passes'} {why}")
    return ok


if "--self-test" in sys.argv:
    print("ref-shape self-test")
    sys.exit(0 if self_test() else 1)

problems = audit(SOURCES)
if problems:
    print("✗ ref shapes:")
    for p in problems:
        print(f"  {p}")
    sys.exit(1)
print("✓ ref shapes: every matched prefix is produced by something")
