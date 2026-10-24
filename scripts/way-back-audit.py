#!/usr/bin/env python3
"""Way-back audit: every screen has a way back to the one before it.

On the phone nothing pushes (prd §1132): every screen rises as a sheet, and a
sheet goes back with a swipe down. So a screen can only trap you by switching
the usual way back OFF, and those are the four shapes this audit checks:

  A. `.fullScreenCover` cannot be swiped away, so the view it shows must carry
     its own way out (`dismiss()`, `.dsSheetDismiss`, or an `onCancel` the
     cover passes), and must ALWAYS show it: an `if` with no `else` around the
     cover's content leaves an empty full-screen cover with no control. That
     shipped: the thing sheet's photo zoom drew nothing once its row was
     deleted under it.
  B. `.interactiveDismissDisabled()` turns a sheet's swipe off; a file that
     uses it is listed in ALLOWED with the control that gets you out instead.
  C. `.navigationBarBackButtonHidden(true)` (the Mac's pushes) is paid for by
     the dock's leading seat (prd §767) and `DSSwipeBack()`, which turns the
     edge swipe back on; the swipe must sit right beside the hide.
  D. UIKit's `isModalInPresentation = true` is B under another spelling.
  E. Every push names its way back (prd §1304): a `.navigationDestination`
     closure wears `.dsSheetStep()` (in a sheet, the seat's back door at the
     foot, never the system's Back under the sheet's corner) or hides the
     back itself, as the shell's own stack does where the dock's seat is
     the way back (C then holds it to its swipe).

What it does NOT check: that the dock's seat actually draws on a pushed screen,
or that a close control is reachable on screen. Those are runtime facts, for
the screen sweep (`screen-audit`).

Usage:  scripts/way-back-audit.py [--self-test]
Exit 0 = clean.
"""

import re
import sys
import pathlib
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = [ROOT / "Casberi/Casberi", ROOT / "Casberi/Shared",
           ROOT / "Casberi/ShareExtension"]

# File name → the control that replaces the swipe.
ALLOWED = {
    # The exported private key exists nowhere else while it is shown (prd
    # §1493): "I saved it" and "Remove the key" are the way out.
    "MoveExportKey.swift": "I saved it · Remove the key",
}

COVER = re.compile(r"\.fullScreenCover\s*\(")
DISMISS_OFF = re.compile(r"\.interactiveDismissDisabled\s*\(\s*(?:true\s*)?\)")
BACK_HIDDEN = re.compile(r"\.navigationBarBackButtonHidden\s*\(\s*true\s*\)")
MODAL = re.compile(r"isModalInPresentation\s*=\s*true")
ESCAPE = re.compile(r"\bdismiss\s*\(\s*\)|\.dsSheetDismiss\b|\bonCancel\b")
SWIPE_BACK = re.compile(r"\bDSSwipeBack\s*\(")
DESTINATION = re.compile(r"\.navigationDestination\s*\(")
SHEET_STEP = re.compile(r"\.dsSheetStep\s*\(\s*\)")
# How many lines after a hidden back button its swipe may sit.
SWIPE_WINDOW = 3


def strip(src):
    """Blank comments and string literals, keeping offsets, so braces and
    words inside them are not read as code."""
    out = list(src)
    i, n = 0, len(src)
    while i < n:
        if src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            for k in range(i, j):
                out[k] = " "
            i = j
        elif src.startswith("/*", i):
            j = src.find("*/", i + 2)
            j = n if j < 0 else j + 2
            for k in range(i, j):
                if out[k] != "\n":
                    out[k] = " "
            i = j
        elif src[i] == '"':
            j = i + 1
            while j < n and src[j] not in '"\n':
                j += 2 if src[j] == "\\" else 1
            for k in range(i + 1, min(j, n)):
                out[k] = " "
            i = j + 1
        else:
            i += 1
    return "".join(out)


def block(code, open_at):
    """The text inside the braces opening at `open_at`."""
    depth = 0
    for i in range(open_at, len(code)):
        if code[i] == "{":
            depth += 1
        elif code[i] == "}":
            depth -= 1
            if depth == 0:
                return code[open_at + 1:i]
    return code[open_at + 1:]


def cover_content(code, at):
    """The content closure of the cover call starting at `at`: the first `{`
    after the call's arguments close."""
    i = code.index("(", at)
    depth = 0
    for j in range(i, len(code)):
        if code[j] == "(":
            depth += 1
        elif code[j] == ")":
            depth -= 1
            if depth == 0:
                k = code.find("{", j)
                return block(code, k) if k >= 0 else ""
    return ""


def view_bodies(files):
    """Type name → its declaration's body, across the tree."""
    bodies = {}
    for code in files.values():
        for m in re.finditer(r"\bstruct\s+(\w+)[^{]*\{", code):
            bodies.setdefault(m.group(1), block(code, m.end() - 1))
    return bodies


def top_level_ifs_without_else(content):
    """`if` statements at the closure's own depth with no `else` after them."""
    flagged = []
    depth = 0
    i = 0
    while i < len(content):
        c = content[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        elif depth == 0 and re.match(r"\bif\b", content[i:]) and \
                (i == 0 or not (content[i - 1].isalnum() or content[i - 1] == "_")):
            k = content.find("{", i)
            if k < 0:
                break
            inner = block(content, k)
            end = k + len(inner) + 2
            if not re.match(r"\s*else\b", content[end:]):
                flagged.append(content[i:k].strip())
            i = end
            continue
        i += 1
    return flagged


def audit(paths):
    files = {}
    for root in paths:
        if root.exists():
            for path in sorted(root.rglob("*.swift")):
                files[path] = strip(path.read_text(errors="ignore"))
    bodies = view_bodies(files)
    findings = []

    def rel(path):
        try:
            return path.relative_to(ROOT)
        except ValueError:
            return path

    for path, code in files.items():
        line_of = lambda at: code.count("\n", 0, at) + 1

        # A. Full-screen covers.
        for m in COVER.finditer(code):
            where = f"{rel(path)}:{line_of(m.start())}"
            content = cover_content(code, m.start())
            for cond in top_level_ifs_without_else(content):
                findings.append(
                    f"{where}: the cover's content is `{cond} {{ … }}` with no "
                    f"else — when it is false the cover is empty and nothing "
                    f"closes it")
            if ESCAPE.search(content):
                continue
            names = re.findall(r"\b([A-Z]\w*)\s*\(", content)
            if not any(ESCAPE.search(bodies.get(n, "")) for n in names):
                findings.append(
                    f"{where}: a full-screen cover whose view has no way out "
                    f"(no dismiss(), .dsSheetDismiss or onCancel) — it cannot "
                    f"be swiped away")

        # B. A sheet with its swipe switched off.
        if path.name not in ALLOWED:
            for m in DISMISS_OFF.finditer(code):
                findings.append(
                    f"{rel(path)}:{line_of(m.start())}: interactiveDismissDisabled "
                    f"switches the swipe back off — list the file in ALLOWED "
                    f"with the control that replaces it")

        # C. A hidden back button with no swipe beside it.
        lines = code.splitlines()
        for m in BACK_HIDDEN.finditer(code):
            ln = line_of(m.start())
            window = "\n".join(lines[ln - 1:ln + SWIPE_WINDOW])
            if not SWIPE_BACK.search(window):
                findings.append(
                    f"{rel(path)}:{ln}: navigationBarBackButtonHidden(true) with "
                    f"no DSSwipeBack() beside it — the edge swipe goes with the "
                    f"button (prd §767)")

        # E. A push with no way back of its own.
        for m in DESTINATION.finditer(code):
            content = cover_content(code, m.start())
            if not (SHEET_STEP.search(content) or BACK_HIDDEN.search(content)):
                findings.append(
                    f"{rel(path)}:{line_of(m.start())}: a navigationDestination "
                    f"whose step wears neither .dsSheetStep() nor its own "
                    f"hidden back — in a sheet it draws the system's Back "
                    f"under the sheet's corner (prd §1304)")

        # D. UIKit's spelling of B.
        if path.name not in ALLOWED:
            for m in MODAL.finditer(code):
                findings.append(
                    f"{rel(path)}:{line_of(m.start())}: isModalInPresentation = "
                    f"true switches the swipe back off — list the file in ALLOWED")
    return findings


def self_test():
    viewer = ("struct Viewer: View {\n"
              "    @Environment(\\.dismiss) private var dismiss\n"
              "    var body: some View { Button(\"Close\") { dismiss() } }\n}\n")
    trap = "struct Trap: View {\n    var body: some View { Text(\"no way out\") }\n}\n"
    cases = {
        "a cover over a view with a close control":
            (viewer + "x.fullScreenCover(isPresented: $a) { Viewer() }\n", False),
        "a cover over a view with no way out":
            (trap + "x.fullScreenCover(isPresented: $a) { Trap() }\n", True),
        "a cover that passes its own onCancel":
            (trap + "x.fullScreenCover(isPresented: $a) { Trap(onCancel: { a = false }) }\n", False),
        "a cover whose content is an if with no else (the photo zoom)":
            (viewer + "x.fullScreenCover(isPresented: $a) {\n"
                      "    if thing.isLive { Viewer() }\n}\n", True),
        "a cover whose if has an else":
            (viewer + "x.fullScreenCover(isPresented: $a) {\n"
                      "    if ok { Viewer() } else { Viewer() }\n}\n", False),
        "a cover with arguments before its content":
            (viewer + "x.fullScreenCover(isPresented: $a,\n"
                      "    onDismiss: { if b { c() } }) { Viewer() }\n", False),
        "a close word inside a comment is not a close control":
            (trap + "x.fullScreenCover(isPresented: $a) {\n"
                    "    Trap() // dismiss() later\n}\n", True),
        "a sheet with its swipe switched off":
            ("x.sheet(isPresented: $a) { V().interactiveDismissDisabled() }\n", True),
        "a sheet with its swipe explicitly on":
            ("x.sheet(isPresented: $a) { V().interactiveDismissDisabled(false) }\n", False),
        "a hidden back button with its swipe beside it":
            ("v.navigationBarBackButtonHidden(true)\n    .background(DSSwipeBack())\n", False),
        "a hidden back button with no swipe":
            ("v.navigationBarBackButtonHidden(true)\n", True),
        "UIKit's modal lock":
            ("vc.isModalInPresentation = true\n", True),
        "a push that wears the seat's back door":
            ("x.navigationDestination(for: N.self) { Room($0).dsSheetStep() }\n", False),
        "a push left on the system's Back":
            ("x.navigationDestination(for: N.self) { Room($0) }\n", True),
        "a push whose binding has closures, and no step":
            ("x.navigationDestination(isPresented: Binding(get: { a }, set: { a = $0 })) {\n"
             "    Room()\n}\n", True),
        "a push that hides its back and keeps the swipe (the shell's stack)":
            ("x.navigationDestination(for: N.self) { n in\n"
             "    Room(n).navigationBarBackButtonHidden(true)\n"
             "        .background(DSSwipeBack())\n}\n", False),
        "the step named only in a comment is not the step":
            ("x.navigationDestination(for: N.self) {\n"
             "    Room($0) // .dsSheetStep()\n}\n", True),
    }
    ok = True
    with tempfile.TemporaryDirectory() as tmp:
        for i, (why, (body, should_flag)) in enumerate(cases.items()):
            d = pathlib.Path(tmp) / f"c{i}"
            d.mkdir()
            (d / "Case.swift").write_text(body)
            flagged = bool(audit([d]))
            if flagged != should_flag:
                ok = False
            print(f"  {'ok  ' if flagged == should_flag else 'FAIL'} "
                  f"{'flags' if should_flag else 'passes'} {why}")
    return ok


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        print("way-back self-test")
        sys.exit(0 if self_test() else 1)

    problems = audit(SOURCES)
    if problems:
        print("✗ screens with no way back:")
        for p in problems:
            print(f"  {p}")
        sys.exit(1)
    print("✓ way back: every cover closes, every sheet swipes, every hidden "
          "back button keeps its swipe, every push names its way back")
