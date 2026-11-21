#!/usr/bin/env python3
"""Section-glyph audit — a section name draws NO glyph (prd §1814).

WHY THIS EXISTS. From 2026-10-23 (prd §1496) every section name led with a
pink 17pt symbol framed in the row's lead column, and this audit held the
column, the rung and the gap. The user, 2026-11-15: "right now with the
glyphs everywhere it can bleed all together"; "drop and put to left edge".
The symbol stood in the column the rows' icons and their own pink verbs stand
in, so a title stopped reading as a title. A section name is its name alone
now, at the left edge, hanging left of the rows' words.

THE CHECK. An `Image(systemName:)` inside an `HStack`, followed within its
first six lines by a `.dsGlyph(.body…)` and, within thirty, by a `Text` in a
heading rung (`heading20` and up), is a section name wearing a glyph again:
a finding. `ALLOW` lists the files where that shape is something else, each
with its reason. A warning callout (`heading17`, a `.subhead` glyph) is not a
section name.

THE SECOND CHECK (prd §1496, kept). The chassis still defines the lead
column as the row's (`DS.Mark.row`) and its gap as the row's (`DS.Space.s3`):
rows indent their words by it under a name that no longer does.

WHAT IT DOES NOT CHECK. A row's lead (`DSFeedRow` and the room rows own
theirs), a glyph after the title (a door's chevron), a header built without
an HStack, or the rung of a name that has no glyph to find it by.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "Casberi" / "Casberi"
HEADING = re.compile(r"dsText\(\.heading(2\d|3\d)\)")


# The same shape, not a section name.
ALLOW = {
    "Casberi/Casberi/Design/DSTraySearchField.swift": "a field's own glyph beside its words",
    "Casberi/Casberi/Screens/MoveBack.swift": "a back row: the chevron is the control; and `MoveRowGlyph`, "
                                              "a Move row's lead on its disc, never a section name (prd §1892)",
    "Casberi/Casberi/Design/DSSeenStamp.swift": "Risks' state line (\"N new\", \"All seen\"): its shield is the "
                                                "stamp the user picked, a fact over the findings, not a section name (prd §1919)",
}


def findings(files):
    out = []
    for path, text in files:
        if path in ALLOW:
            continue
        lines = text.split("\n")
        for i, line in enumerate(lines):
            if line.strip().startswith("//") or "Image(systemName:" not in line:
                continue
            back = "\n".join(lines[max(0, i - 5):i])
            if "HStack" not in back:
                continue
            own = lines[i:i + 6]
            if not any(".dsGlyph(.body" in l for l in own):
                continue
            ahead = "\n".join(l for l in lines[i:i + 30] if not l.strip().startswith("//"))
            if HEADING.search(ahead):
                out.append((f"{path}:{i + 1}", "glyph"))
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
            Text("Activity")
                .dsText(.heading24)
            Image(systemName: "chevron.right")
                .dsGlyph(.tick, weight: .bold)
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

GLYPH = '''            Image(systemName: "clock")
                .dsGlyph(.body)
                .foregroundStyle(DS.brandInk)
                .frame(width: DSRoomChassis.headGlyph)
'''


def self_test():
    ok = True
    def case(name, text, want, path="t.swift"):
        nonlocal ok
        got = len(findings([(path, text)]))
        mark = "ok  " if got == want else "FAIL"
        if got != want:
            ok = False
        print(f"  {mark} {name} ({got} finding(s))")
    print("section-glyph-audit self-test")
    led = SELF_TEST.replace('            Text("Activity")', GLYPH + '            Text("Activity")', 1)
    assert led != SELF_TEST
    case("a bare section name with a door's chevron is clean", SELF_TEST, 0)
    case("a section name led by a glyph is flagged (prd §1814)", led, 1)
    case("a glyph before a name on the title's rung is flagged too",
         led.replace(".dsText(.heading24)", ".dsText(.heading20)", 1), 1)
    case("a COMMENTED glyph is not one",
         led.replace('            Image(systemName: "clock")', '            // Image(systemName: "clock")', 1), 0)
    case("an allowed file's glyph is left alone", led, 0, path=next(iter(ALLOW)))
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
            if why == "glyph":
                print(f"✗ {where}: a section name led by a glyph — a section name is its name alone, at the left edge (prd §1814)")
            elif why == "column":
                print(f"✗ {where}: the lead column is not the row's, DS.Mark.row (prd §1496)")
            else:
                print(f"✗ {where}: the lead gap is not the row's, DS.Space.s3 (prd §1496)")
        print(f"section-glyph-audit: {len(hits)} finding(s)")
        sys.exit(1)
    print("✓ section-glyph audit: no section name wears a glyph, and the rows' column is the chassis's")


if __name__ == "__main__":
    main()
