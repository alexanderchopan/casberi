#!/usr/bin/env python3
"""Casberi face-ramp audit — every round identity mark takes a `DS.Face` tier
(prd §355b, 2026-08-11), never a raw number.

WHY THIS IS MECHANICAL AND NOT A NOTE IN A DOC. The ramp exists because these
sizes had drifted to SIXTEEN different literals across FORTY-SEVEN call sites
(14·16·18·20·22·24·26·28·32·36·38·40·50·52·56·60) — two horizontal face
shelves doing the identical job disagreed (52 against 60), and so did two
picker lists (32 against 36). Nobody chose that. It accumulated one screen at
a time, over months, because every call site spelled its own number and
NOTHING ANYWHERE COULD SEE THE SET. That is the exact failure mode this
codebase already answers with a script everywhere else (`catalog-sync.sh`,
the liveness audit, the keychain audit): a rule that lives only in someone's
memory is re-broken by the next screen that needs an avatar, and the drift is
invisible in every build, every screenshot and every review, because ANY of
these values renders perfectly on its own. You can only see it by listing all
47 at once, which is what this does.

WHAT COUNTS AS A FACE. `WalletFace` always (it draws nothing else), plus
`RemoteThumb`/`BridgeIcon` when `circular: true` — a round mark standing in
the same slot a person's avatar would, whether it is a face, a wallet
identicon, or an app icon covering for a missing picture.

DELIBERATELY NOT COVERED, so this can't become a lint that cries wolf: the
source strip's and Sources Tray's chip metrics (`iconSize`), which are sized
by their own grid rather than by adjacent text and are already named
constants; and any SQUARE `BridgeIcon`, which is a brand mark in a tile, not
a face — that one is not unchecked, it belongs to the OTHER ramp:
`design-ramp-audit.py` holds it to `DS.Mark`. The two ramps agree on their
first three rungs by construction (`DS.Mark.badge`/`.row`/`.list` are the
`DS.Face` values), because in a row a mark and a face stand in the same slot
and must never disagree; they diverge above it, where a brand mark heads a
card or a screen and a face never does. `circular:` is what tells the two
apart, which is why they stay two checks.

Static, self-tested, no build. Exit non-zero on failure.
"""
import re
import sys
import pathlib
import collections

CALL = re.compile(r'\b(WalletFace|RemoteThumb|BridgeIcon)\s*\((.{0,240}?)\)', re.S)
COMMENT = re.compile(r'^[ \t]*///?.*$|(?<![:"\w])//[^\n]*$', re.M)
SIZE = re.compile(r'size:\s*([A-Za-z0-9_.]+)')
TIERS = ("badge", "row", "list", "shelf")

# A named constant is allowed only if it RESOLVES to a tier — checked below by
# reading its own declaration. `iconSize` is the documented chip-metric escape.
CHIP_METRICS = {"iconSize", "Self.iconSize"}


def uncommented(src: str) -> str:
    """The source with comment BODIES blanked, lines and columns preserved.

    A file that DOCUMENTS this rule by naming what it must not do —
    "`WalletFace(size: someFunction())` is exactly how a raw number gets back
    onto a face" — used to fail against its own explanation (2026-08-21). Same
    class as the Obsidian, Cursor, Instagram, journal-room and one-inference
    guards, all of which read a comment-stripped copy for the same reason; this
    audit was the one that grepped raw source. Blanked rather than deleted so
    every reported line number still points where it did.
    """
    return COMMENT.sub(lambda m: " " * len(m.group(0)), src)


def faces(src: str):
    """Yield (kind, size_expr, line) for every face-shaped call in `src`."""
    src = uncommented(src)
    for m in CALL.finditer(src):
        kind, args = m.group(1), m.group(2)
        sz = SIZE.search(args)
        if not sz:
            continue
        if kind != "WalletFace" and "circular: true" not in args:
            continue
        yield kind, sz.group(1), src[: m.start()].count("\n") + 1


IDENT = re.compile(r'[A-Za-z_][A-Za-z0-9_.]*')


def resolves_to_tier(name: str, src: str, seen: frozenset = frozenset()) -> bool:
    """Does a named constant's own declaration read a DS.Face tier?

    ONE EXTRA HOP (2026-08-22, prd §444). `AddressFlightOverlay` interpolates a
    travelling face between two ends that ARE ramp tiers — but they arrive as
    parameters, so the local it computes reads `fromSize + (toSize - fromSize)
    * progress` and names no tier itself. The rule is satisfied and the first
    cut of this resolver could not see it: it read one declaration and stopped.

    So an expression naming no tier is followed through the identifiers it
    DOES name, depth-bounded and cycle-guarded. ANY of them resolving is
    enough, which is deliberately permissive — the alternative is demanding
    that every identifier resolve, and `progress` is a bare `let progress:
    CGFloat` parameter with no initialiser at all, so a strict rule would
    reject the one shape this hop exists for. A constant built out of a raw
    number and nothing else still resolves to nothing and is still flagged,
    which is the case the fixtures pin.
    """
    src = uncommented(src)
    bare = name.split(".")[-1]
    if bare in seen or len(seen) > 3:
        return False
    decl = re.search(
        r'(?:let|var)\s+%s\s*:?[^=\n]*=\s*([^\n]+)' % re.escape(bare), src)
    if not decl:
        decl = re.search(
            r'(?:let|var)\s+%s\s*:[^{\n]+\{\s*([^}\n]+)\}' % re.escape(bare), src)
    if not decl:
        return False
    expr = decl.group(1)
    if "DS.Face." in expr:
        return True
    return any(resolves_to_tier(ident, src, seen | {bare})
               for ident in IDENT.findall(expr)
               if ident.split(".")[-1] != bare)


def audit(root: pathlib.Path):
    findings, counts = [], collections.Counter()
    for f in sorted(root.rglob("*.swift")):
        src = f.read_text()
        for kind, size, line in faces(src):
            if size.startswith("DS.Face."):
                counts[size] += 1
                continue
            if size in CHIP_METRICS:
                continue
            if size.isdigit():
                findings.append(
                    f"{f}:{line} {kind}(size: {size}) — a raw number. Use a "
                    f"DS.Face tier ({', '.join(TIERS)}).")
            elif not resolves_to_tier(size, src):
                findings.append(
                    f"{f}:{line} {kind}(size: {size}) — `{size}` does not "
                    f"resolve to a DS.Face tier in this file.")
    return findings, counts


DIRTY_RAW = 'WalletFace(address: a, size: 44, circular: true)'
DIRTY_THUMB = 'RemoteThumb(urlString: u, size: 52,\n  circular: true)'
DIRTY_CONST = ('private let myFace: CGFloat = 60\n'
               'WalletFace(address: a, size: myFace, circular: true)')
CLEAN_TIER = 'WalletFace(address: a, size: DS.Face.shelf, circular: true)'
CLEAN_CONST = ('private let rosterFaceSize: CGFloat = DS.Face.shelf\n'
               'WalletFace(address: a, size: rosterFaceSize, circular: true)')
CLEAN_SQUARE = 'BridgeIcon(name: n, size: 46)'          # square mark, not a face
CLEAN_CHIP = 'BridgeIcon(name: n, size: iconSize, circular: true)'
# A face INTERPOLATED between two ramp tiers — the travelling face of
# `AddressFlightOverlay` (prd §441/§444). The ends are tiers; the local that
# mixes them names neither, so this only passes with the extra hop above.
CLEAN_INTERP = ('var fromSize: CGFloat = DS.Face.list\n'
                'var toSize: CGFloat = DS.Face.shelf\n'
                'let size = fromSize + (toSize - fromSize) * progress\n'
                'WalletFace(address: a, size: size, circular: true)')
# The same shape with neither end on the ramp — still a raw number reaching a
# face through two hops, and still flagged. Without this the hop above would be
# an unconditional pass wearing a resolver's clothes.
DIRTY_INTERP = ('var fromSize: CGFloat = 36\n'
                'var toSize: CGFloat = 56\n'
                'let size = fromSize + (toSize - fromSize) * progress\n'
                'WalletFace(address: a, size: size, circular: true)')
# A file that EXPLAINS the rule by naming what it must not do. Both halves are
# in the fixture on purpose: the comment names a dirty call and the real call
# below it is clean, so a fixture that only carried the comment would pass for
# the wrong reason (2026-08-21 — this audit's own first comment-blind run).
CLEAN_DOCUMENTED = ('// `WalletFace(size: someFunction())` is how a raw number\n'
                    '// gets back onto a face — never do this.\n'
                    '/// Nor `WalletFace(address: a, size: 44, circular: true)`.\n'
                    'WalletFace(address: a, size: DS.Face.list, circular: true)')


def self_test(tmp: pathlib.Path) -> None:
    """A check that cannot fail proves nothing — prove each shape."""
    cases = [
        ("a raw number", DIRTY_RAW, True),
        ("a raw number on a multi-line circular thumb", DIRTY_THUMB, True),
        ("a constant that resolves to a raw number", DIRTY_CONST, True),
        ("a tier used directly", CLEAN_TIER, False),
        ("a constant that resolves to a tier", CLEAN_CONST, False),
        ("a SQUARE brand mark (not a face)", CLEAN_SQUARE, False),
        ("the documented chip-metric escape", CLEAN_CHIP, False),
        ("a face interpolated between two tiers", CLEAN_INTERP, False),
        ("…the same interpolation between two raw numbers", DIRTY_INTERP, True),
        ("a comment that NAMES a dirty call", CLEAN_DOCUMENTED, False),
    ]
    for label, body, should_flag in cases:
        d = tmp / "selftest"
        d.mkdir(exist_ok=True)
        (d / "F.swift").write_text(body)
        found, _ = audit(d)
        if bool(found) != should_flag:
            sys.exit(f"✗ self-test FAILED: {label} — "
                     f"{'not flagged' if should_flag else 'wrongly flagged'}")
        print(f"  ✓ self-test: {label}")


def main() -> None:
    here = pathlib.Path(__file__).resolve().parent.parent
    import tempfile
    with tempfile.TemporaryDirectory() as t:
        print("face-ramp-audit: self-test…")
        self_test(pathlib.Path(t))

    findings, counts = audit(here / "Casberi")
    if findings:
        print("\nface-ramp-audit: FAILURES\n")
        for f in findings:
            print("  ✗ " + f)
        print("\n  The ramp is DS.Face.badge/row/list/shelf "
              "(Design/DesignTokens.swift). A face's size is decided by what "
              "it sits beside — see the tier docs before adding a value.")
        sys.exit(1)

    total = sum(counts.values())
    spread = " · ".join(f"{k.split('.')[-1]} {v}" for k, v in sorted(counts.items()))
    print(f"\nface-ramp-audit: OK — {total} face draws, all on the ramp ({spread}).")


if __name__ == "__main__":
    main()
