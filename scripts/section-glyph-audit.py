#!/usr/bin/env python3
"""Section-glyph audit — every section name's glyph stands in ONE column.

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
            if not HEADING.search(ahead):
                continue
            if not any(m.startswith(".frame(width: DSRoomChassis.headGlyph)") for m in mods):
                out.append(f"{path}:{i + 1}")
    return out


SELF_TEST = '''
struct A: View {
    var body: some View {
        HStack(spacing: DS.Space.s2) {
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
    return ok


def main():
    if "--self-test" in sys.argv:
        sys.exit(0 if self_test() else 1)
    if not self_test():
        print("✗ section-glyph-audit's own self-test failed")
        sys.exit(1)
    files = [(str(p.relative_to(ROOT)), p.read_text(encoding="utf-8"))
             for p in sorted(SRC.rglob("*.swift"))]
    hits = findings(files)
    if hits:
        for h in hits:
            print(f"✗ {h}: a section name's glyph at its own width — frame it at DSRoomChassis.headGlyph")
        print(f"section-glyph-audit: {len(hits)} header(s) off the one column")
        sys.exit(1)
    print("✓ section-glyph audit: every section name's glyph stands in one column")


if __name__ == "__main__":
    main()
