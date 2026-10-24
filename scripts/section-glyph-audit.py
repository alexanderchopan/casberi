#!/usr/bin/env python3
"""Section-glyph audit — every section name's glyph stands in ONE column, and
every section name is ONE rung (prd §1496).

WHY THIS EXISTS (user, 2026-10-23: "look how all this stuff has different
indentation on the headers"; "it's on home too. can you sweep the app and
check everywhere"). A section name is a pink 17pt symbol, then the name in a
heading rung. Drawn at its own width, each symbol pushed its title to a
different x: Signatures, Delegations and Approvals on Security, Overview and
Accounts on the Wallet's Home. Six headers drew the shape by hand; each now
frames its glyph at `DSRoomChassis.headGlyph`.

THE CHECK. An `Image(systemName:)` inside an `HStack`, followed within its
first six lines by a `.dsGlyph(.body…)` and, within fourteen, by a `Text`
in a heading rung (`heading20` and up), must carry
`.frame(width: DSRoomChassis.headGlyph)` among its own modifiers. A warning
callout (`heading17`, a `.subhead` glyph) is not a section name.

THE SECOND CHECK (prd §1496, user: "i don't want to be hand rolling any of
this. i want to use rules"). The heading the glyph introduces must be
`heading24`: the ramp's section rung, which the Feed's header, the Wallet's
doors (`walletDoor`) and Your account's Keys and Spending share. The Feed had
borrowed `heading28` (the lede's fit ladder), so every Feed section stood a
step over every other section in the app; a name on any other rung beside a
section glyph is that drift again, wherever it is written next.
THE THIRD CHECK (prd §1496, user: "should these share same indent?"). The
header's HStack must space the glyph from its name by `DSRoomChassis.headGap`,
and the chassis must define the column as the row's lead (`DS.Mark.row`) and
the gap as the row's (`DS.Space.s3`): then a name starts where every row's
title starts and the glyph is centred over the row's mark. It was 26 and 8,
so every name stood 8pt left of the words under it.

WHAT IT DOES NOT CHECK. A row's lead (`DSFeedRow` and the room rows own
theirs), a glyph after the title, or a header built without an HStack.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "Casberi" / "Casberi"
HEADING = re.compile(r"dsText\(\.heading(2\d|3\d)\)")


def findings(files):
    out = []
    for path, text in files:
        lines = text.split("\n")
        for i, line in enumerate(lines):
            if line.strip().startswith("//") or "Image(systemName:" not in line:
                continue
            back = "\n".join(lines[max(0, i - 5):i])
            if "HStack" not in back:
                continue
            stack = next((l for l in reversed(lines[max(0, i - 5):i]) if "HStack" in l), "")
            own = lines[i:i + 6]
            if not any(".dsGlyph(.body" in l for l in own):
                continue
            # The glyph's own modifiers run until the next view starts.
            mods = []
            for l in lines[i + 1:i + 8]:
                s = l.strip()
                if not s.startswith("."):
                    break
                mods.append(s)
            ahead = "\n".join(lines[i:i + 14])
            rung = HEADING.search(ahead)
            if not rung:
                continue
            if not any(m.startswith(".frame(width: DSRoomChassis.headGlyph)") for m in mods):
                out.append((f"{path}:{i + 1}", "column"))
            if rung.group(1) != "24":
                out.append((f"{path}:{i + 1}", f"rung heading{rung.group(1)}"))
            if "spacing: DSRoomChassis.headGap" not in stack:
                out.append((f"{path}:{i + 1}", "gap"))
    return out


def chassis_findings(text):
    """The column is the row's lead and the gap the row's (prd §1496)."""
    out = []
    if "static let headGlyph: CGFloat = DS.Mark.row" not in text:
        out.append(("DSRoomChassis.headGlyph", "column"))
    if "static let headGap: CGFloat = DS.Space.s3" not in text:
        out.append(("DSRoomChassis.headGap", "chassis-gap"))
    return out


SELF_TEST = '''
struct A: View {
    var body: some View {
        HStack(spacing: DSRoomChassis.headGap) {
            Image(systemName: "clock")
                .dsGlyph(.body)
                .foregroundStyle(DS.brandInk)
                .frame(width: DSRoomChassis.headGlyph)
                .accessibilityHidden(true)
            Text("Activity")
                .dsText(.heading24)
        }
    }
}
struct Callout: View {
    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .dsGlyph(.subhead)
            Text("Another address looks just like this one")
                .dsText(.heading17)
        }
    }
}
'''


def self_test():
    ok = True
    def case(name, text, want):
        nonlocal ok
        got = len(findings([("t.swift", text)]))
        mark = "ok  " if got == want else "FAIL"
        if got != want:
            ok = False
        print(f"  {mark} {name} ({got} finding(s))")
    print("section-glyph-audit self-test")
    case("healthy tree is clean", SELF_TEST, 0)
    case("a header glyph at its own width is flagged",
         SELF_TEST.replace("                .frame(width: DSRoomChassis.headGlyph)\n", "", 1), 1)
    case("a hand-picked width is flagged, not the shared column",
         SELF_TEST.replace("DSRoomChassis.headGlyph", "24", 1), 1)
    case("a COMMENTED frame does not satisfy it",
         SELF_TEST.replace(".frame(width: DSRoomChassis.headGlyph)", "// .frame(width: DSRoomChassis.headGlyph)", 1), 1)
    case("a section name on the lede's rung is flagged (prd §1496)",
         SELF_TEST.replace(".dsText(.heading24)", ".dsText(.heading28)", 1), 1)
    case("a section name on the screen's rung is flagged (prd §1496)",
         SELF_TEST.replace(".dsText(.heading24)", ".dsText(.heading34)", 1), 1)
    case("a header gapped by hand, off the row's gap, is flagged (prd §1496)",
         SELF_TEST.replace("HStack(spacing: DSRoomChassis.headGap)", "HStack(spacing: DS.Space.s2)", 1), 1)
    chassis = "static let headGlyph: CGFloat = DS.Mark.row\nstatic let headGap: CGFloat = DS.Space.s3"
    for name, text, want in [("the chassis on the row's column and gap is clean", chassis, 0),
                             ("a column narrower than the row's lead is flagged", chassis.replace("DS.Mark.row", "26"), 1),
                             ("a gap other than the row's is flagged", chassis.replace("DS.Space.s3", "DS.Space.s2"), 1)]:
        got = len(chassis_findings(text))
        print(f"  {'ok  ' if got == want else 'FAIL'} {name} ({got} finding(s))")
        ok = ok and got == want
    return ok


def main():
    if "--self-test" in sys.argv:
        sys.exit(0 if self_test() else 1)
    if not self_test():
        print("✗ section-glyph-audit's own self-test failed")
        sys.exit(1)
    files = [(str(p.relative_to(ROOT)), p.read_text(encoding="utf-8"))
             for p in sorted(SRC.rglob("*.swift"))]
    hits = findings(files) + chassis_findings(
        (SRC / "Design" / "DSRoomChassis.swift").read_text(encoding="utf-8"))
    if hits:
        for where, why in hits:
            if why == "column":
                print(f"✗ {where}: a section name's glyph off the row's lead column — frame it at DSRoomChassis.headGlyph, which is DS.Mark.row")
            elif why == "gap":
                print(f"✗ {where}: a section name's glyph gapped by hand — space the HStack by DSRoomChassis.headGap (prd §1496)")
            elif why == "chassis-gap":
                print(f"✗ {where}: the header gap is not the row's, DS.Space.s3 (prd §1496)")
            else:
                print(f"✗ {where}: a section name at {why.split()[1]} — every section name is heading24 (prd §1496)")
        print(f"section-glyph-audit: {len(hits)} header(s) off the one column or the one rung")
        sys.exit(1)
    print("✓ section-glyph audit: every section name on the row's column and gap, at heading24")


if __name__ == "__main__":
    main()
