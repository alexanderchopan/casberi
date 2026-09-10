#!/usr/bin/env python3
"""Dead-closure audit (prd §669, 2026-09-10).

WHY THIS EXISTS. A SwiftUI view that hands its verbs out as closure properties
can declare one with a NO-OP DEFAULT:

    var onRename: (String) -> Void = { _ in }

and then call it from a control. The compiler is content, every audit here is
content, the control renders perfectly, and it does nothing — for every call
site, forever, because nothing ever passed it. That is §83's dead control with
a type signature in front of it, and the app has now shipped it three times in
ONE file: `onWatched: {}` (a discovery list that could not add), `onScope` (a
prop the call site passed and nothing called, the mirror image), and
`onRename`, reported by the user on 2026-09-10 — *"long press on accounts in
wallet and devnet silhouette rails offer to name this address but when i click
it nothing happens"*. The second of those was fixed by wiring one property and
LEAVING THE ONE BESIDE IT INERT, with a comment saying nobody had reported that
one. A comment is not a check, which is the whole argument for this file.

ONE CHECK, static, no build:

    A view property whose default is a no-op closure, and which the declaring
    file CALLS, must be supplied by some call site.

Both halves of that sentence are load-bearing:

  · **CALLS.** A no-op default nothing invokes is unused weight, not a dead
    control — there is no button promising anything. Reported by `--census`,
    never failed on, because deleting it is a judgement call and this check
    does not make judgement calls.
  · **SUPPLIED.** `onRename: onRename` does NOT count. Forwarding a property
    into a child view moves the same nothing one level down, and that exact
    line is in the tree today: `VibenetDetailContextMenu(onRename: onRename)`
    is what made this bug look wired to a grep. A supply is an argument whose
    VALUE is not the parameter's own name.

WHAT THIS DELIBERATELY DOES NOT CHECK, so it stays honest about its reach:

  · An OPTIONAL closure (`var onX: ((String) -> Void)? = nil`). Those are the
    honest form — the call site's `nil` is readable at the declaration, and
    every caller in this tree already gates its control on the optional being
    non-nil, which is §83 satisfied rather than dodged. A control drawn
    unconditionally over a nil optional is a real defect this cannot see.
  · Whether a supplied closure does the RIGHT thing. A call site passing
    `onRename: { _ in }` explicitly passes this check and is the same bug
    written out loud; no text check can tell an intended no-op from a
    forgotten one, and spelling it at the call site is at least a decision
    somebody made where the reader can see it.
  · Anything about `GenUI/` — model-authored documents, carved out here for
    the reason `primary-verb-audit.py` and the ramp audit both carve it out.
"""

import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIRS = ["Casberi/Casberi", "Casberi/Shared", "Casberi/CasberiWidgets"]
SKIP_PARTS = {"GenUI"}

TYPE_DECL = re.compile(
    r"^\s*(?:public\s+|internal\s+|private\s+|fileprivate\s+|final\s+)*"
    r"(?:struct|class|enum|extension)\s+(\w+)"
)
VAR_DECL = re.compile(
    r"^\s*(?:@\w+(?:\([^()]*\))?\s+)*"
    r"(?:public\s+|internal\s+|private\s+|fileprivate\s+)*"
    r"var\s+(?P<name>\w+)\s*:\s*(?P<type>.+?)\s*=\s*(?P<default>.+?)\s*$"
)
NOOP = re.compile(r"^\{\s*(?:_(?:\s*,\s*_)*\s+in\s*)?\}$")


def strip_comments(text: str) -> str:
    """Comments out, string literals kept.

    This repo documents its rules by NAMING the very symbols they govern, so a
    check reading raw source fires on the prose explaining it — the lesson
    `ondevice-selftest.sh` and `category-fold-selftest.sh` each record paying
    for. A `//` inside a string (every `https://` host literal) is not a
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


class Prop:
    __slots__ = ("file", "line", "owner", "name", "is_closure", "noop")

    def __init__(self, file, line, owner, name, is_closure, noop):
        self.file, self.line, self.owner = file, line, owner
        self.name, self.is_closure, self.noop = name, is_closure, noop


def properties(path: Path, text: str):
    """Every stored `var` declared directly in a type body, in order."""
    found = []
    depth = 0
    stack = []          # (type name, body depth)
    for lineno, line in enumerate(text.splitlines(), 1):
        m = TYPE_DECL.match(line)
        opens = line.count("{")
        closes = line.count("}")
        if m and opens:
            stack.append((m.group(1), depth + 1))
        v = VAR_DECL.match(line)
        if v and stack and depth == stack[-1][1]:
            typ, dflt = v.group("type"), v.group("default")
            found.append(Prop(path, lineno, stack[-1][0], v.group("name"),
                              "->" in typ, bool(NOOP.match(dflt))))
        depth += opens - closes
        while stack and depth < stack[-1][1]:
            stack.pop()
    return found


def constructed_with_trailing_closure(name: str, texts) -> bool:
    """`T(…) { … }` or `T { … }` anywhere — Swift's trailing closure fills the
    LAST function-typed parameter with no label to grep for, which is how
    `AgentKeyPicker(selection: $p) { … }` supplies `onSelect` invisibly. Missed
    on this check's first run against the real tree; it reported that call site
    as a dead control, which would have been a false alarm shipped into the
    pass."""
    head = re.compile(r"(?<![\w.])%s\s*(\(|\{)" % re.escape(name))
    for text in texts.values():
        for m in head.finditer(text):
            i = m.end() - 1
            if text[i] == "{":
                return True
            depth, j = 0, i
            while j < len(text):
                if text[j] == "(":
                    depth += 1
                elif text[j] == ")":
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            k = j + 1
            while k < len(text) and text[k] in " \t\n":
                k += 1
            if k < len(text) and text[k] == "{":
                return True
    return False


def swift_files(root: Path):
    out = []
    for rel in SOURCE_DIRS:
        base = root / rel
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*.swift")):
            if SKIP_PARTS & set(path.parts):
                continue
            out.append(path)
    return out


def audit(root: Path):
    """Returns (findings, census) — findings are dead controls, census is the
    no-op defaults nothing in the declaring file even mentions."""
    files = swift_files(root)
    texts = {p: strip_comments(p.read_text(encoding="utf-8", errors="replace")) for p in files}
    props = {p: properties(p, t) for p, t in texts.items()}

    findings, census = [], []
    for path, text in texts.items():
        lines = text.splitlines()
        for prop in props[path]:
            if not (prop.is_closure and prop.noop):
                continue
            name = prop.name
            ref = re.compile(r"(?<![\w.])%s(?![\w])" % re.escape(name))
            used = any(ref.search(l) for i, l in enumerate(lines, 1)
                       if i != prop.line)
            if not used:
                census.append((path.relative_to(root), prop.line, name))
                continue
            # A supply is an argument whose VALUE is not the parameter's own
            # name: `onRename: onRename` moves the same nothing one level down.
            supply = re.compile(r"(?<![\w.])%s\s*:(?!\s*%s\b)" % (re.escape(name), re.escape(name)))
            decl = re.compile(r"\b(?:var|let)\s+%s\s*:" % re.escape(name))
            supplied = any(
                supply.search(l) and not decl.search(l)
                for t in texts.values() for l in t.splitlines()
            )
            if not supplied:
                siblings = [p for p in props[path] if p.owner == prop.owner and p.is_closure]
                last_closure = bool(siblings) and siblings[-1].name == name
                if last_closure and constructed_with_trailing_closure(prop.owner, texts):
                    supplied = True
            if not supplied:
                findings.append((path.relative_to(root), prop.line, name))
    return findings, census


SELF_TEST_FILES = {
    # The bug, verbatim in shape: a no-op default, called by a control, never
    # supplied — and forwarded to a child under its own name, which is what
    # made it look wired.
    "Casberi/Casberi/Screens/Dead.swift": """
struct DeadCard: View {
    var onRename: (String) -> Void = { _ in }
    var body: some View {
        Button { onRename(address) } label: { Text("Name this…") }
            .modifier(Child(onRename: onRename))
    }
}
struct Child: ViewModifier {
    let onRename: (String) -> Void
}
""",
    # Supplied by a real call site — passes.
    "Casberi/Casberi/Screens/Live.swift": """
struct LiveCard: View {
    var onPick: (String) -> Void = { _ in }
    var body: some View { Button { onPick(id) } label: { Text("Pick") } }
}
struct Host: View {
    var body: some View { LiveCard(onPick: rename) }
}
""",
    # A no-op default nothing calls — census, never a failure.
    "Casberi/Casberi/Screens/Unused.swift": """
struct QuietCard: View {
    var onDone: () -> Void = {}
    var body: some View { Text("nothing") }
}
""",
    # An OPTIONAL closure nothing supplies — deliberately out of reach.
    "Casberi/Casberi/Screens/Optional.swift": """
struct OptionalCard: View {
    var onOpen: ((String) -> Void)? = nil
    var body: some View {
        if let onOpen { Button { onOpen(id) } label: { Text("Open") } }
    }
}
""",
    # Carved out: model-authored documents.
    "Casberi/Casberi/GenUI/Doc.swift": """
struct GenDoc: View {
    var onAct: (String) -> Void = { _ in }
    var body: some View { Button { onAct(id) } label: { Text("Act") } }
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

        findings, census = audit(root)
        names = sorted(n for _, _, n in findings)
        census_names = sorted(n for _, _, n in census)

        failures = []
        if names != ["onRename"]:
            failures.append(f"expected exactly ['onRename'] flagged, got {names}")
        if census_names != ["onDone"]:
            failures.append(f"expected exactly ['onDone'] in the census, got {census_names}")

        # MUTATION 1: supply it, and the finding must go.
        live = root / "Casberi/Casberi/Screens/Host.swift"
        live.write_text("struct H: View { var body: some View { DeadCard(onRename: rename) } }\n")
        if any(n == "onRename" for _, _, n in audit(root)[0]):
            failures.append("a supplied closure was still reported — the check does not clear")
        live.unlink()

        # MUTATION 2: supplying it under its OWN name must NOT clear it.
        fwd = root / "Casberi/Casberi/Screens/Fwd.swift"
        fwd.write_text("struct F: View { var body: some View { DeadCard(onRename: onRename) } }\n")
        if not any(n == "onRename" for _, _, n in audit(root)[0]):
            failures.append("forwarding a property under its own name cleared the finding")
        fwd.unlink()

        # MUTATION 3: stop MENTIONING it at all, and it drops to the census —
        # a default nothing reads promises nobody anything.
        dead = root / "Casberi/Casberi/Screens/Dead.swift"
        kept = dead.read_text()
        dead.write_text(
            "struct DeadCard: View {\n"
            "    var onRename: (String) -> Void = { _ in }\n"
            "    var body: some View { Text(\"nothing\") }\n"
            "}\n"
        )
        f3, c3 = audit(root)
        if any(n == "onRename" for _, _, n in f3) or not any(n == "onRename" for _, _, n in c3):
            failures.append("an unmentioned no-op default was not moved to the census")
        dead.write_text(kept)

        # MUTATION 4: a TRAILING CLOSURE supplies the last closure property,
        # with no label anywhere to grep — the false alarm this check produced
        # on its own first run against the real tree.
        trail = root / "Casberi/Casberi/Screens/Trailing.swift"
        trail.write_text(
            "struct PickerCard: View {\n"
            "    @Binding var selection: Int\n"
            "    var onSelect: () -> Void = {}\n"
            "    var body: some View { Button { onSelect() } label: { Text(\"Pick\") } }\n"
            "}\n"
            "struct PickerHost: View {\n"
            "    var body: some View { PickerCard(selection: $n) { clear() } }\n"
            "}\n"
        )
        if any(n == "onSelect" for _, _, n in audit(root)[0]):
            failures.append("a trailing closure did not count as supplying the last closure property")
        trail.unlink()

        if failures:
            for f in failures:
                print(f"self-test FAILED: {f}", file=sys.stderr)
            return 1
        print("dead-closure audit self-test: ok (4 mutations)")
        return 0


def main() -> int:
    args = sys.argv[1:]
    if "--self-test" in args:
        return self_test()

    findings, census = audit(ROOT)
    if "--census" in args:
        for rel, lineno, name in census:
            print(f"{rel}:{lineno}: {name} — a no-op default nothing calls")
    if not findings:
        print(f"dead-closure audit: ok ({len(census)} uncalled no-op defaults, not failed on)")
        return 0
    print("A control calls a closure property no call site ever supplies:\n")
    for rel, lineno, name in findings:
        print(f"  {rel}:{lineno}: `{name}` defaults to a no-op and nothing passes it")
    print("\nPass it from every call site, or delete the control that calls it (§83).")
    return 1


if __name__ == "__main__":
    sys.exit(main())
