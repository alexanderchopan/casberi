#!/usr/bin/env python3
"""The elevated card has ONE caller left (prd §759, 2026-09-15).

`dsWidgetSurface` — the elevated widget card: the sheet fill at the widget
radius, lifted off the page by the ambient card shadow — was the app's default
way of saying "these things belong together". It has been taken off one kind of
block at a time, each after its own report:

  • §749  every row, and the reading cover's own deck
          ("i made a mistake by adding cards to rows i think it makes the app
           look worse")
  • §708  every account page ("nothing on an account page is boxed but the
          entry well")
  • §757  the wallet family's Actions and Readings ("they should not have
          cards")
  • §758  every room head ("again here, we don't want cards that are like this")
  • §759  the remaining forty-four — every gen-UI module, L2BEAT and Walletbeat
          and their sheets, the settings list, the two wallet cards, the themes
          lede, the wallet's coming-up section, the naming prompt, the address
          book's nudge, the X person card, Cloudflare's runway, vibenet's
          roster ("more cards, these gotta go")

WHY A MECHANICAL CHECK, AND NOT A LINE IN A DOC. Five passes of the same
deletion is five chances for the sixth session to paste a `.dsWidgetSurface()`
onto the next block it writes — the modifier is one line, it reads as harmless,
and it renders as a perfectly tidy card in every screenshot, every screen sweep
and every build. The only thing that can catch it is a grep that runs on every
verify.

WHAT IS ALLOWED: `Design/Glass.swift` — the definition itself, and
`dsCard`/`dsElevatedSurface` beside it. Nothing else, anywhere.

§759 reserved one exception for `DSScopeTiles`, on the grounds that a tile you
press needs an edge. It does; it just does not need THIS edge. §752b, landed the
same day from another session, had already made the tiles a flat `surfaceRaised`
fill with the tint on the pick, because at the big cards' pour and 18pt shadow a
row of them "smeared into dark columns". So the exception was empty when it was
written, and it is gone: the elevated card has no callers at all.

WHAT THIS DOES NOT CHECK, stated so it is not mistaken for a general
no-backgrounds rule: `dsWell` (the RECESSED rung — a block sunk into the page)
is untouched and says something different; so are glass (the floating layer's
own material), `dsGlass`, row fills, and every `background(…)` a component draws
for contrast. This audit is about ONE modifier and the lift it adds.

Usage:  scripts/plate-audit.py [--self-test]
Exit 0 = clean.
"""
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TREE = "Casberi"

# The elevated ladder's three spellings — `dsCard` and `dsElevatedSurface` are
# the same lift under other names, and a sweep that pinned only the third would
# be answered by renaming the call.
PLATE = re.compile(r"\.(dsWidgetSurface|dsCard|dsElevatedSurface)\(")

# file name → why it may still draw one. An entry is a RULING, not a snooze.
ALLOWED = {
    "Glass.swift": "the definitions themselves (prd §759)",
}


def strip_comments(src: str) -> str:
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    kept = [l for l in src.splitlines() if not l.strip().startswith("//")]
    return "\n".join(re.sub(r"(?<!:)//.*$", "", l) for l in kept)


def scan(root: Path, tree: str = TREE) -> list[tuple[str, int, str]]:
    findings: list[tuple[str, int, str]] = []
    for path in sorted((root / tree).rglob("*.swift")):
        if path.name in ALLOWED:
            continue
        code = strip_comments(path.read_text())
        for i, line in enumerate(code.splitlines(), start=1):
            if PLATE.search(line):
                rel = path.relative_to(root).as_posix()
                findings.append((rel, i, line.strip()))
    return findings


def report(findings: list[tuple[str, int, str]]) -> int:
    if not findings:
        print(f"plate audit: clean — the elevated card is drawn only by "
              f"{', '.join(sorted(ALLOWED))}")
        return 0
    print("✗ the elevated card is back on content (prd §759):")
    for rel, line, text in findings:
        print(f"    {rel}:{line}  {text}")
    print()
    print("  Five passes deleted this modifier from every kind of block in the app")
    print("  (§749 rows, §708 account pages, §757 the wallet family's lists, §758")
    print("  every room head, §759 the remaining forty-four). What separates two")
    print("  blocks is air. If a NEW surface genuinely needs a lift, that is a")
    print("  ruling in docs/prd.md and a row in this audit's ALLOWED, not a")
    print("  modifier on the end of a chain.")
    return 1


def self_test() -> int:
    """A planted tree: one clean file, one plate, one plate under another
    spelling, one inside a comment, and one in an allowed file."""
    ok = True
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        src = root / TREE / "Screens"
        src.mkdir(parents=True)
        design = root / TREE / "Design"
        design.mkdir(parents=True)
        (src / "CleanCard.swift").write_text(
            "struct CleanCard: View {\n"
            "    var body: some View { Text(\"hi\").padding(DS.Space.s4) }\n}\n")
        (src / "PlatedCard.swift").write_text(
            "struct PlatedCard: View {\n"
            "    var body: some View { Text(\"hi\").dsWidgetSurface() }\n}\n")
        (src / "RenamedCard.swift").write_text(
            "struct RenamedCard: View {\n"
            "    var body: some View { Text(\"hi\").dsCard() }\n}\n")
        (src / "TalksAboutIt.swift").write_text(
            "struct TalksAboutIt: View {\n"
            "    /// It used to wear `.dsWidgetSurface()` and no longer does.\n"
            "    var body: some View { Text(\"hi\") }\n}\n")
        (design / "Glass.swift").write_text(
            "extension View {\n"
            "    func dsWidgetSurface() -> some View { dsElevatedSurface() }\n}\n")

        found = {rel for rel, _, _ in scan(root)}
        cases = [
            ("a plated card is caught", f"{TREE}/Screens/PlatedCard.swift" in found),
            ("the same lift under another name is caught",
             f"{TREE}/Screens/RenamedCard.swift" in found),
            ("a clean card passes", f"{TREE}/Screens/CleanCard.swift" not in found),
            ("a file that only TALKS about the modifier passes",
             f"{TREE}/Screens/TalksAboutIt.swift" not in found),
            ("the definitions' own file is not flagged",
             f"{TREE}/Design/Glass.swift" not in found),
        ]
        for what, passed in cases:
            print(f"  {'ok  ' if passed else '✗   '} {what}")
            ok &= passed
    print("plate-audit self-test:", "ok" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(self_test())
    sys.exit(report(scan(ROOT)))
