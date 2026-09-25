#!/usr/bin/env python3
"""No plates: what separates two blocks is air (prd §759, §782).

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
  • §782  the plates that survived under OTHER spellings (user, of the wallet's
          "Worth a look" tray: "these plates"): `dsInkFill` on every row of
          that tray, `dsWell` around rows, paragraphs, fact tables and stat
          tiles in the thing sheet, the social sheet and a dozen cards, and
          `dsListCardRow` lifting every settings-side List section.

WHY A MECHANICAL CHECK, AND NOT A LINE IN A DOC. Six passes of the same
deletion is six chances for the next session to paste a plate onto the next
block it writes — the modifier is one line, it reads as harmless, and it renders
as a perfectly tidy card in every screenshot, every screen sweep and every
build. §759 pinned one spelling and §782 found three more. The only thing that
can catch it is a grep that runs on every verify.

THE THREE CHECKS

  1. THE LIFT — `dsWidgetSurface` / `dsCard` / `dsElevatedSurface`. Drawn only
     by `Design/Glass.swift`, the definitions. Nothing else, anywhere.
  2. THE INK FILL — `dsInkFill`, the card colour with the pour and no shadow.
     Allowed only on the floating layer (a landing's flight over the feed).
  3. THE WELL — `dsWell`, the recessed rung. A well holds something you TYPE
     into, a room's lead (§766) or a room scope's figure, a monospaced value,
     or a small control face. Every file allowed one is listed below with how
     many it may draw, so a new well in an allowed file fails as surely as a
     well in a new file. The ratchet also fails a STALE allowance: a file that
     draws fewer than it is allowed says so, and the number must come down.

WHAT THIS DOES NOT CHECK, stated so it is not mistaken for a general
no-backgrounds rule: glass (the floating layer's own material), chips, row
press fills, meters, figure cells, image clips, and `background(…)` fills a
component draws for contrast. A hand-drawn pill behind text is
`ds-template-audit.py`'s check C.

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
LIFT = re.compile(r"\.(dsWidgetSurface|dsCard|dsElevatedSurface)\(")
INK = re.compile(r"\.dsInkFill\(")
WELL = re.compile(r"\.dsWell\(")

# file name → why it may still draw the lift. An entry is a RULING, not a snooze.
LIFT_ALLOWED = {
    "Glass.swift": "the definitions themselves (prd §759)",
}

# file name → (ink fills it may draw, why).
INK_ALLOWED = {
    "Glass.swift": (0, "the definition itself"),
    "RootShell.swift": (1, "a landing's flight crossing the feed — the floating layer, not content"),
}

# file name → (wells it may draw, why). Counted, like ds-template-audit's ratchet.
WELL_ALLOWED = {
    "Glass.swift": (0, "the definition itself"),
    "DSRoomHead.swift": (1, "the room lead's well, `dsRoomHeadBlock` (prd §766)"),
    "DSRoomScopeChrome.swift": (1, "a room scope's figure well (prd §766)"),
    "Composer.swift": (2, "the composer's draft field and its live transcript — the floating layer"),
    "AgentChatView.swift": (1, "the agent room's entry field — the one thing §782 "
                               "leaves a well for, and the same shape the composer's "
                               "own draft field takes (prd §840)"),
    "VibenetAuthorizeSheet.swift": (2, "two entry fields: the address and the scope picker"),
    "VibenetAccountSheet.swift": (1, "the note entry field"),
    "AddressBookViews.swift": (3, "the name entry field, the compact copy button's face, and an action tile's face"),
    "ConnectWalletRow.swift": (1, "the pairing URI, a monospaced value with its copy button"),
    "SafeScreen.swift": (2, "two entry fields: a pairing link, a pasted signing request (prd §913)"),
    "SafeAskSheet.swift": (1, "the pasted statement, an entry field (prd §913)"),
    "ThingContent.swift": (1, "a monospaced text block"),
    "FeedLedeCard.swift": (1, "the media cover's well — art at its top, words on its ground (prd §915)"),
    "GenRenderer.swift": (1, "the live stream's cover, the same stacked well (prd §915)"),
    "NoteSheetViews.swift": (1, "a monospaced code block"),
}


def strip_comments(src: str) -> str:
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    kept = [l for l in src.splitlines() if not l.strip().startswith("//")]
    return "\n".join(re.sub(r"(?<!:)//.*$", "", l) for l in kept)


def scan(root: Path, tree: str = TREE) -> list[tuple[str, int, str]]:
    """Every finding as (relative path or file, line, message). Line 0 is a
    per-file finding (an over-count or a stale allowance)."""
    findings: list[tuple[str, int, str]] = []
    for path in sorted((root / tree).rglob("*.swift")):
        rel = path.relative_to(root).as_posix()
        code = strip_comments(path.read_text())
        lines = code.splitlines()
        # 1. the lift
        if path.name not in LIFT_ALLOWED:
            for i, line in enumerate(lines, start=1):
                if LIFT.search(line):
                    findings.append((rel, i, "the elevated card (§759): " + line.strip()))
        # 2 and 3. counted spellings
        for regex, allowed, name in ((INK, INK_ALLOWED, "dsInkFill"),
                                     (WELL, WELL_ALLOWED, "dsWell")):
            hits = [(i, l.strip()) for i, l in enumerate(lines, start=1)
                    for _ in regex.findall(l)]
            cap = allowed.get(path.name, (0, ""))[0]
            if len(hits) > cap:
                for i, text in hits:
                    findings.append((rel, i, f"{name} ({len(hits)} drawn, {cap} allowed, §782): {text}"))
            elif path.name in allowed and len(hits) < cap:
                findings.append((rel, 0, f"{name}: draws {len(hits)} of its {cap} — "
                                         f"lower the allowance in plate-audit.py"))
    return findings


def report(findings: list[tuple[str, int, str]]) -> int:
    if not findings:
        print("plate audit: clean — no lift outside Glass.swift, and every "
              "ink fill and well is on the allowance list")
        return 0
    print("✗ a plate is back on content (prd §759, §782):")
    for rel, line, text in findings:
        where = f"{rel}:{line}" if line else rel
        print(f"    {where}  {text}")
    print()
    print("  Six passes deleted plates from every kind of block in the app (§749")
    print("  rows, §708 account pages, §757 the wallet family's lists, §758 every")
    print("  room head, §759 the remaining forty-four, §782 the other spellings).")
    print("  What separates two blocks is air. A well holds only what you type")
    print("  into, a room's lead, a monospaced value or a small control face. If")
    print("  a NEW surface genuinely needs one, that is a ruling in docs/prd.md")
    print("  and a row in this audit's allowances, not a modifier on a chain.")
    return 1


def self_test() -> int:
    """A planted tree covering every check in both directions."""
    ok = True
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        src = root / TREE / "Screens"
        src.mkdir(parents=True)
        design = root / TREE / "Design"
        design.mkdir(parents=True)
        shell = root / TREE / "Shell"
        shell.mkdir(parents=True)

        def plant(folder: Path, name: str, body: str) -> None:
            (folder / name).write_text(f"struct X: View {{\n    var body: some View {{ {body} }}\n}}\n")

        plant(src, "CleanCard.swift", 'Text("hi").padding(DS.Space.s4)')
        plant(src, "PlatedCard.swift", 'Text("hi").dsWidgetSurface()')
        plant(src, "RenamedCard.swift", 'Text("hi").dsCard()')
        (src / "TalksAboutIt.swift").write_text(
            "struct TalksAboutIt: View {\n"
            "    /// It used to wear `.dsWidgetSurface()` and `.dsWell()` and no longer does.\n"
            "    var body: some View { Text(\"hi\") }\n}\n")
        (design / "Glass.swift").write_text(
            "extension View {\n"
            "    func dsWidgetSurface() -> some View { dsElevatedSurface() }\n}\n")
        plant(src, "InkedRow.swift", 'Text("hi").dsInkFill()')
        plant(shell, "RootShell.swift", 'Text("flight").dsInkFill()')
        plant(src, "WelledRow.swift", 'Text("hi").dsWell()')
        plant(src, "ThingContent.swift", 'VStack { Text("a").dsWell(); Text("b").dsWell() }')
        plant(src, "NoteSheetViews.swift", 'Text("code")')

        findings = scan(root)
        flagged = {rel for rel, _, _ in findings}

        def said(rel: str, fragment: str) -> bool:
            return any(r == rel and fragment in m for r, _, m in findings)

        cases = [
            ("a plated card is caught", f"{TREE}/Screens/PlatedCard.swift" in flagged),
            ("the same lift under another name is caught",
             f"{TREE}/Screens/RenamedCard.swift" in flagged),
            ("a clean card passes", f"{TREE}/Screens/CleanCard.swift" not in flagged),
            ("a file that only TALKS about a plate passes",
             f"{TREE}/Screens/TalksAboutIt.swift" not in flagged),
            ("the definitions' own file is not flagged",
             f"{TREE}/Design/Glass.swift" not in flagged),
            ("an ink fill on a row is caught", f"{TREE}/Screens/InkedRow.swift" in flagged),
            ("the flight's ink fill is allowed", f"{TREE}/Shell/RootShell.swift" not in flagged),
            ("a well around a row is caught", f"{TREE}/Screens/WelledRow.swift" in flagged),
            ("a second well in an allowed file is caught",
             said(f"{TREE}/Screens/ThingContent.swift", "2 drawn, 1 allowed")),
            ("a stale allowance is reported",
             said(f"{TREE}/Screens/NoteSheetViews.swift", "draws 0 of its 1")),
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
