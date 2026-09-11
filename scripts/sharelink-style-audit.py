#!/usr/bin/env python3
"""ShareLink style audit (prd §693, 2026-09-11).

WHY THIS EXISTS. Reported by the user: *"i have three rss feeds but am unable
to add another. when i go to paste one in a share sheet opens."*

`RSSScreen`'s act drew its OPML off-ramp as

    ShareLink(item: exportURL) { Text("Export as OPML") … }
        .simultaneousGesture(TapGesture().onEnded { DSHaptic.tap() })

with no `buttonStyle`. A `ShareLink` is a Button, and a Button left on the
AUTOMATIC style inside a `List` row is not merely a button in a row — SwiftUI
gives the ROW its action, so a tap anywhere in that cell fires it. An account
page draws its whole act as ONE row (`AccountPage.actSection`), so the export
link shared a cell with the follow field and took the field's taps: reaching
for the field raised the share sheet, and no feed could be pasted. With no
feeds followed the link is not drawn at all, which is why the empty state
worked and why the report reads "three feeds but unable to add another".

The rest of the tree already had it right — `HandleSetupScreen` carries the
same block, copied, WITH `.buttonStyle(.plain)`, and so do `ThingStage` and
`DiagnosticsScreen`. One site out of six was the whole bug, and nothing could
see it: the build is clean, a share sheet is a system surface no screenshot
sweep opens, and the screen renders pixel-identically either way.

ONE CHECK, static, no build:

    A share control drawn in CONTENT carries `.buttonStyle(.plain)`.

`ShareLink` and `ThingShareLink` (the wrapper over it) both count. Two
carve-outs, each for a decided reason:

  · **Inside a menu builder** (`Menu { }`, `.contextMenu { }`,
    `.swipeActions { }`, `.toolbar { }`) the automatic style is the RIGHT one
    — a menu row is not a `List` cell and a plain style there drops the
    system's own row chrome. Reported by `--census`, never failed on.
  · **A forwarder** — a `ShareLink` inside a wrapper view whose label is the
    caller's (`{ label() }`, i.e. `ThingShareLink`). The style belongs to the
    call site, which this check reads on its own.
  · **A menu extracted into its own View** — `FeedScreen`'s `RowVerbMenu`,
    whose body IS the row menu's items and which is raised from another file.
    Carved out by CALL SITE (a type constructed inside a menu builder
    anywhere), never by name: "it ends in Menu" is a convention, and a rule
    may not rest on one. The cost is stated below.

WHAT THIS DELIBERATELY DOES NOT CHECK, so it stays honest about its reach:

  · Every OTHER automatic-styled button in a `List` row. The same SwiftUI rule
    governs them all, and a sweep for `Button(` without a style would be
    mostly false alarms — a button outside a List is fine on the automatic
    style, and this file cannot tell which is which. The share sheet is
    singled out because it is the one whose misfire is SILENT and modal: the
    row does something dramatic and plausible instead of nothing.
  · A view drawn BOTH as menu content and as ordinary content. The menu call
    site carves the type out everywhere, so an unstyled share control inside
    it goes unreported on the half that is a `List` row. No such view exists
    today (the census names every carve-out, six of them, each checked by
    hand); the alternative — resolving which call site a body is being drawn
    for — is not something a text check can do.
  · `PasteButton`, which cannot comply — it refuses custom button styles by
    design. An entry row carrying one has the same row-wide behaviour, noted
    here rather than left to be rediscovered.
  · Whether the share sheet hands over the right thing. `ShareTargetMemo` is
    that rule, one layer down.
"""

import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIRS = ["Casberi/Casberi", "Casberi/Shared", "Casberi/CasberiWidgets"]

# The share controls this rule governs. `ThingShareLink` is in the list
# because it IS a `ShareLink` — exempting the wrapper would move the same
# nothing one level down, which is `dead-closure-audit.py`'s own lesson.
SHARE_NAMES = ("ShareLink", "ThingShareLink")

# A style that takes the button out of the row's hands. `.borderless` does it
# too, and is the older spelling of the same intent, so both pass.
OK_STYLE = re.compile(r"\.buttonStyle\(\s*\.(plain|borderless)\s*\)")

# An enclosing `{` whose opener says "this is a menu, not content".
MENU_OPENER = re.compile(
    r"(\bMenu\s*[({]|\.contextMenu\b|\.swipeActions\b|\.toolbar\b|\bToolbarItem\s*[({])"
)

IDENT = re.compile(r"[A-Za-z_]\w*")

TYPE_DECL = re.compile(r"\b(?:struct|class|enum|extension)\s+(\w+)")


def strip_comments(text: str) -> str:
    """Comments out, string literals kept.

    This repo documents its rules by NAMING the very symbols they govern, so a
    check reading raw source fires on the prose explaining it — the lesson
    `ondevice-selftest.sh`, `category-fold-selftest.sh` and
    `dead-closure-audit.py` each record paying for, and which this file would
    have paid again on its first run (the comment it just added to
    `RSSScreen` spells `ShareLink` twice). A `//` inside a string is not a
    comment, so the scan tracks quotes rather than cutting at the first slash.
    Line breaks are preserved so a reported line number is the real one.
    """
    out, line = [], []
    in_block = in_string = False
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if in_block:
            if ch == "*" and nxt == "/":
                in_block = False
                i += 2
                continue
            if ch == "\n":
                out.append("".join(line))
                line = []
            i += 1
            continue
        if in_string:
            if ch == "\\":
                line.append("  ")
                i += 2
                continue
            if ch == '"':
                in_string = False
            line.append(ch)
            i += 1
            continue
        if ch == '"':
            in_string = True
            line.append(ch)
            i += 1
            continue
        if ch == "/" and nxt == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if ch == "/" and nxt == "*":
            in_block = True
            i += 2
            continue
        if ch == "\n":
            out.append("".join(line))
            line = []
            i += 1
            continue
        line.append(ch)
        i += 1
    out.append("".join(line))
    return "\n".join(out)


def skip_string(text: str, i: int) -> int:
    """Past the string literal opening at `i`. Interpolation is skipped as
    string content, which is all this scan needs — a `)` inside `\\(…)` must
    not close an argument list."""
    i += 1
    while i < len(text):
        if text[i] == "\\":
            i += 2
            continue
        if text[i] == '"':
            return i + 1
        i += 1
    return i


def skip_balanced(text: str, i: int) -> int:
    """Past the bracket opening at `i`, whatever kind it is."""
    pairs = {"(": ")", "{": "}", "[": "]"}
    close = pairs[text[i]]
    depth = 0
    while i < len(text):
        ch = text[i]
        if ch == '"':
            i = skip_string(text, i)
            continue
        if ch in pairs:
            depth += 1
        elif ch in ")}]":
            depth -= 1
            if depth == 0:
                return i + 1 if ch == close else i + 1
        i += 1
    return i


def skip_space(text: str, i: int) -> int:
    while i < len(text) and text[i] in " \t\n":
        i += 1
    return i


def expression_end(text: str, i: int) -> int:
    """Past a share control's call — its argument list and any trailing
    closure — leaving `i` at the start of its modifier chain."""
    i = text.index("(", i)
    i = skip_balanced(text, i)
    j = skip_space(text, i)
    if j < len(text) and text[j] == "{":
        return skip_balanced(text, j)
    return i


def modifier_chain(text: str, i: int) -> str:
    """The `.modifier(…) .modifier { … }` run that follows, as one string."""
    start = i
    while True:
        j = skip_space(text, i)
        if j >= len(text) or text[j] != ".":
            break
        k = IDENT.match(text, j + 1)
        if not k:
            break
        i = k.end()
        j = skip_space(text, i)
        while j < len(text) and text[j] in "({":
            i = skip_balanced(text, j)
            j = skip_space(text, i)
    return text[start:i]


def trailing_closure(text: str, i: int) -> str:
    """A share control's label closure, or "" when it takes none."""
    i = text.index("(", i)
    i = skip_space(text, skip_balanced(text, i))
    if i < len(text) and text[i] == "{":
        return text[i:skip_balanced(text, i)]
    return ""


def calls(text: str):
    """Every `Name(` in the file, with the stack of `{` openers above it and
    the type declaration it sits in. One walk, so the two passes below read
    the tree the same way."""
    openers: list[str] = []
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch == '"':
            i = skip_string(text, i)
            continue
        if ch == "{":
            line_start = text.rfind("\n", 0, i) + 1
            openers.append(text[line_start:i + 1])
            i += 1
            continue
        if ch == "}":
            if openers:
                openers.pop()
            i += 1
            continue
        name = IDENT.match(text, i)
        if not name:
            i += 1
            continue
        after = skip_space(text, name.end())
        prev = text[i - 1] if i else " "
        if prev not in "._" and after < n and text[after] == "(":
            owner = ""
            for opener in openers:
                decl = TYPE_DECL.search(opener)
                if decl:
                    owner = decl.group(1)
            yield i, name.group(0), list(openers), owner
        i = name.end()


def sources(root: Path):
    for rel in SOURCE_DIRS:
        base = root / rel
        if not base.exists():
            continue
        for path in sorted(base.rglob("*.swift")):
            yield path, strip_comments(path.read_text(encoding="utf-8"))


def menu_views(root: Path) -> set:
    """Types CONSTRUCTED inside a menu builder — their bodies are menu
    content wherever they are declared.

    Found by running the check against the real tree: `FeedScreen`'s row menu
    is `RowVerbMenu`, a View whose whole body is the menu's items, raised by
    `.contextMenu { RowVerbMenu(…) }` one screen away from its declaration.
    A brace stack cannot see that, so the lexical carve-out alone reported a
    correct menu as a defect. Resolved by call site rather than by NAME: a
    type ending in "Menu" is a convention, and this rule may not rest on one.
    """
    found = set()
    for _, text in sources(root):
        for _, word, openers, _ in calls(text):
            if word[:1].isupper() and any(MENU_OPENER.search(o) for o in openers):
                found.add(word)
    return found


def audit(root: Path):
    findings, census = [], []
    in_menus = menu_views(root)
    for path, text in sources(root):
        for i, word, openers, owner in calls(text):
            if word not in SHARE_NAMES:
                continue
            lineno = text.count("\n", 0, i) + 1
            where = (path.relative_to(root), lineno, word)
            if any(MENU_OPENER.search(o) for o in openers):
                census.append((*where, "in a menu — automatic is right"))
            elif owner in in_menus:
                census.append((*where, f"inside {owner}, which is raised as a menu"))
            elif trailing_closure(text, i).strip("{} \n\t") == "label()":
                census.append((*where, "a forwarder — its call sites carry the style"))
            elif not OK_STYLE.search(modifier_chain(text, expression_end(text, i))):
                findings.append(where)
    return findings, census


SELF_TEST_FILES = {
    # The bug, verbatim in shape: an act row holding a field and an unstyled
    # export link, so the link takes the row and the field cannot be reached.
    "Casberi/Casberi/Screens/Feeds.swift": """
struct FeedsScreen: View {
    var body: some View {
        List {
            VStack {
                DSSlabField(placeholder: "Site or feed URL", text: $newFeed)
                ShareLink(item: exportURL) {
                    Text("Export as OPML")
                }
                .simultaneousGesture(TapGesture().onEnded { DSHaptic.tap() })
            }
        }
    }
}
""",
    # The same block, styled — passes.
    "Casberi/Casberi/Screens/Handles.swift": """
struct HandlesScreen: View {
    var body: some View {
        ShareLink(item: exportURL) {
            Text("Export as OPML")
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { DSHaptic.tap() })
    }
}
""",
    # In a menu: the automatic style is the right one — census, never failed.
    "Casberi/Casberi/Screens/Tray.swift": """
struct TrayScreen: View {
    var body: some View {
        Menu {
            ShareLink(item: exportURL) { Label("Everything", systemImage: "shippingbox") }
        } label: {
            Text("Export")
        }
        .contextMenu {
            ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
        }
    }
}
""",
    # A forwarder and its two call sites — the style belongs to the callers,
    # and one of them is missing it.
    "Casberi/Casberi/Screens/Thing.swift": """
struct ThingShareLink<Label: View>: View {
    @ViewBuilder let label: () -> Label
    var body: some View {
        ShareLink(item: url) { label() }
    }
}
struct Dial: View {
    var body: some View {
        ThingShareLink(thing: thing) { disc(icon: "square.and.arrow.up") }
            .buttonStyle(.plain)
    }
}
struct Card: View {
    var body: some View {
        ThingShareLink(thing: thing) { Text("Share") }
    }
}
""",
    # A menu extracted into its own View, raised from another file — the
    # real tree's `RowVerbMenu`, which the lexical carve-out alone called a
    # defect.
    "Casberi/Casberi/Screens/Row.swift": """
struct RowVerbMenu: View {
    var body: some View {
        Button("Pin") { pin() }
        ThingShareLink(thing: thing) { Label("Share", systemImage: "square.and.arrow.up") }
    }
}
""",
    "Casberi/Casberi/Screens/Room.swift": """
struct RoomScreen: View {
    var body: some View {
        List {
            row.contextMenu {
                RowVerbMenu(thing: thing)
            }
        }
    }
}
""",
    # A string carrying what looks like an argument list, and a `//` inside
    # one — neither may derail the scan.
    "Casberi/Casberi/Screens/Hero.swift": """
struct Hero: View {
    var body: some View {
        ShareLink(item: "\\(title) — see https://casberi.app/(x) 🍇", subject: Text(title)) {
            Image(systemName: "square.and.arrow.up")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share")
    }
}
""",
}


def self_test() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        for rel, body in SELF_TEST_FILES.items():
            path = root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(body, encoding="utf-8")

        failures = []
        findings, census = audit(root)
        got = sorted((p.name, w) for p, _, w in findings)
        if got != [("Feeds.swift", "ShareLink"), ("Thing.swift", "ThingShareLink")]:
            failures.append(f"expected the two unstyled controls flagged, got {got}")
        reasons = sorted(r for *_, r in census)
        if len(reasons) != 4 or reasons.count("in a menu — automatic is right") != 2:
            failures.append(
                f"expected 2 menu sites, 1 forwarder and 1 menu view in the census, got {reasons}")

        def flagged(name: str) -> bool:
            return any(p.name == name for p, _, _ in audit(root)[0])

        # MUTATION 1: style the reported link, and the finding must go — the
        # one-line fix this audit exists to hold in place.
        feeds = root / "Casberi/Casberi/Screens/Feeds.swift"
        kept = feeds.read_text()
        feeds.write_text(kept.replace(".simultaneousGesture",
                                      ".buttonStyle(.plain)\n                .simultaneousGesture"))
        if flagged("Feeds.swift"):
            failures.append("a styled ShareLink was still reported — the check does not clear")
        feeds.write_text(kept)

        # MUTATION 2: take the style OFF the passing screen, and it must fire.
        handles = root / "Casberi/Casberi/Screens/Handles.swift"
        kept_h = handles.read_text()
        handles.write_text(kept_h.replace("        .buttonStyle(.plain)\n", ""))
        if not flagged("Handles.swift"):
            failures.append("an unstyled ShareLink outside a menu was not reported")
        handles.write_text(kept_h)

        # MUTATION 3: `.borderless` is the same intent, older spelling.
        handles.write_text(kept_h.replace(".buttonStyle(.plain)", ".buttonStyle(.borderless)"))
        if flagged("Handles.swift"):
            failures.append(".borderless was not accepted")
        handles.write_text(kept_h)

        # MUTATION 4: a style on a DIFFERENT control in the same row does not
        # count — the chain read must be the share control's own.
        feeds.write_text(kept.replace('text: $newFeed)',
                                      'text: $newFeed).buttonStyle(.plain)'))
        if not flagged("Feeds.swift"):
            failures.append("a neighbour's buttonStyle cleared the finding")
        feeds.write_text(kept)

        # MUTATION 5: move the reported link INTO a menu and it becomes a
        # census line — the carve-out is real, not a hole.
        feeds.write_text(kept.replace("            VStack {", "            Menu {"))
        f5, c5 = audit(root)
        if any(p.name == "Feeds.swift" for p, _, _ in f5) or \
           not any(p.name == "Feeds.swift" for p, _, _, _ in c5):
            failures.append("a ShareLink moved into a menu was not carved out")
        feeds.write_text(kept)

        # MUTATION 6: raise that same View as ordinary content instead of as a
        # menu, and its unstyled link is a defect again — the carve-out tracks
        # the call site, so it cannot be a blanket pass for the type.
        room = root / "Casberi/Casberi/Screens/Room.swift"
        kept_r = room.read_text()
        room.write_text(kept_r.replace("row.contextMenu {", "row.overlay {"))
        if not flagged("Row.swift"):
            failures.append("a menu view raised as content was still carved out")
        room.write_text(kept_r)

        if failures:
            for f in failures:
                print(f"self-test FAILED: {f}", file=sys.stderr)
            return 1
        print("sharelink style audit self-test: ok (6 mutations)")
        return 0


def main() -> int:
    args = sys.argv[1:]
    if "--self-test" in args:
        return self_test()

    findings, census = audit(ROOT)
    if "--census" in args:
        for rel, lineno, word, why in census:
            print(f"{rel}:{lineno}: {word} — {why}")
    if not findings:
        print(f"sharelink style audit: ok ({len(census)} carved out, not failed on)")
        return 0
    print("A share control in content is left on the automatic button style:\n")
    for rel, lineno, word in findings:
        print(f"  {rel}:{lineno}: `{word}` has no .buttonStyle(.plain)")
    print("\nInside a List row that button becomes the ROW's action, so every tap")
    print("on the row raises the share sheet (prd §693). Add .buttonStyle(.plain).")
    return 1


if __name__ == "__main__":
    sys.exit(main())
