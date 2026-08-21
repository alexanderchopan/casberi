#!/usr/bin/env python3
"""Every sheet in this app must have decided how big it is on a REGULAR idiom.

**Why this is mechanical rather than remembered (2026-08-20).** Catalyst
honours NONE of iOS's sheet sizing: `presentationDetents`, the drag indicator
and `presentationBackgroundInteraction` are all inert there. A modal with no
explicit sizing presents as a FORM SHEET — a fixed ~540x620 card centred in the
window, the same size in a 2000pt window as in a 980pt one, and reporting a
COMPACT horizontal size class so `dsAdaptiveContentWidth()` is a no-op inside
it. That is the whole of the user's report ("some of the mac design looks like
it was made for mobile, like when you go to connect an app a small modal pops
up"): ~14 trays and every reading sheet in the app were rendering at one
borrowed size computed for a phone.

The failure is INVISIBLE to everything else here. It compiles, every static
audit passes, the iOS build is unaffected by construction, and a Catalyst
COMPILE proves only that it builds. Even `verify-mac.sh` — the one pass that
runs the app for real — screenshots five screens and opens none of these
sheets. So a new `.sheet` ships phone-sized and nothing says a word.

Two checks:

  1. A view declaring `presentationDetents` must ALSO declare a Mac sizing
     (`dsSizedSheet`, `dsPageSheet`, or `presentationSizing`) in the same
     struct. Detents are the caller SAYING what size it wants; on Mac that
     sentence is dropped on the floor, so the two belong together and drift
     apart silently.

  2. The content views presented as sheets that carry NO detents at all are
     named here with the decision each one made. A hand list, deliberately —
     the reason each is sized the way it is cannot be derived from the text,
     and this repo's own rule is that a curated set with recorded reasons beats
     a glob that runs the same checks and throws every reason away
     (`catalog-sync.sh`'s shape).

**Comments are stripped before either check**, and that is not fussiness: five
files in this tree DOCUMENT this rule by naming the very API it governs
(`ThingSheetView` explains why `presentationBackground` and
`presentationDetents` behave differently under a NavigationStack;
`WalletFeedTiles` explains that detents are a preference DSTray declares).
Grepping raw source scores those prose paragraphs as compliance. Earned the
hard way five times in this codebase already — the Obsidian/Cursor lesson.

What this deliberately does NOT check, so it cannot become a lint that cries
wolf: whether the size CHOSEN is the right one (a judgement no text check can
make), `fullScreenCover` (already the whole window on every platform, which is
what those three call sites want), and any sheet whose content is a `DSTray`
(the scaffold declares the sizing for all ~14 of them in one place, which is
the point of having a scaffold).

Usage: mac-sheet-audit.py [--self-test]
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = [ROOT / "Casberi" / "Casberi", ROOT / "Casberi" / "Shared"]

MAC_SIZING = re.compile(r"\.(dsSizedSheet|dsPageSheet|presentationSizing)\s*\(")
DETENTS = re.compile(r"\.presentationDetents\s*\(")
STRUCT = re.compile(r"^\s*(?:public\s+|private\s+|fileprivate\s+|internal\s+)?struct\s+(\w+)")

# Content views presented as a sheet that declare no detents of their own.
# Each must carry a Mac sizing decision. The reason is the entry's whole value.
NO_DETENT_SHEETS = {
    "AddressBookViews.swift": "AddressCard — presented from the thing sheet's face tap AND the wallet book, both inside a switch, so the size is declared in the view rather than twice at two call sites.",
    "WalletbeatCardScreen.swift": "WalletbeatCardScreen — presented from the Walletbeat room and from its directory; a report you read, so it takes the page size.",
    "AccountScreen.swift": "Diagnostics and How-it-works, both plain sheets with no sizing of their own; sized at the call site because neither view is presented anywhere else.",
    "BridgeRouting.swift": "ConnectFormSheet — the sheet that got REPORTED (2026-08-20, \"way too small, user has to scroll to read them in a tiny box\"). It had no detents and no sizing at all, so on iPad it was the default ~540x620 box holding a whole setup screen. The first cut of this audit missed it precisely because Mac pushes it rather than raising it, so it is not a sheet there — which is the reason this file checks the IDIOM-gated helpers rather than anything Mac-specific.",
    "BridgeConnectedState.swift": "BridgeConnectionSheet — the credentials door raised from inside a setup screen, i.e. the second modal in a connect flow.",
}

# Full-window by nature on every platform — nothing to decide.
KNOWN_EXEMPT = {
    "fullScreenCover": "already the whole window everywhere; the three call sites (onboarding, photo zoom, the barcode scanner) all want exactly that.",
}


def strip_comments(text: str) -> str:
    """Blank out // line comments and /* */ blocks, preserving line count."""
    out, i, n = [], 0, len(text)
    in_block = in_line = in_str = False
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if in_line:
            if c == "\n":
                in_line = False
                out.append(c)
            else:
                out.append(" ")
        elif in_block:
            if c == "*" and nxt == "/":
                in_block = False
                out.append("  ")
                i += 2
                continue
            out.append("\n" if c == "\n" else " ")
        elif in_str:
            out.append(c)
            if c == "\\":
                out.append(nxt)
                i += 2
                continue
            if c == '"':
                in_str = False
        else:
            if c == "/" and nxt == "/":
                in_line = True
                out.append("  ")
                i += 2
                continue
            if c == "/" and nxt == "*":
                in_block = True
                out.append("  ")
                i += 2
                continue
            if c == '"':
                in_str = True
            out.append(c)
        i += 1
    return "".join(out)


def struct_spans(lines):
    """[(name, start, end)] by brace depth — good enough for this tree's style."""
    spans, stack, depth = [], [], 0
    for idx, line in enumerate(lines):
        m = STRUCT.match(line)
        if m and "{" in line:
            stack.append((m.group(1), idx, depth))
        depth += line.count("{") - line.count("}")
        while stack and depth <= stack[-1][2]:
            name, start, _ = stack.pop()
            spans.append((name, start, idx))
    for name, start, _ in stack:
        spans.append((name, start, len(lines) - 1))
    return spans


def rel(path: Path) -> str:
    """Repo-relative where possible; the self-test's fixtures live in /tmp."""
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return path.name


def swift_files():
    for root in SOURCES:
        if root.exists():
            yield from sorted(root.rglob("*.swift"))


def check_detents(files):
    """Every struct declaring detents must declare a Mac sizing too."""
    findings = []
    for path in files:
        raw = path.read_text(encoding="utf-8", errors="replace")
        if ".presentationDetents" not in raw:
            continue
        lines = strip_comments(raw).splitlines()
        spans = struct_spans(lines)
        for idx, line in enumerate(lines):
            if not DETENTS.search(line):
                continue
            owner = None
            for name, start, end in spans:
                if start <= idx <= end and (owner is None or start > owner[1]):
                    owner = (name, start, end)
            if owner is None:
                findings.append(f"{rel(path)}:{idx+1} detents outside any struct")
                continue
            body = "\n".join(lines[owner[1]:owner[2] + 1])
            if not MAC_SIZING.search(body):
                findings.append(
                    f"{rel(path)}:{idx+1} `{owner[0]}` declares presentationDetents "
                    f"with no Mac sizing — it renders as a fixed ~540x620 form sheet on Catalyst. "
                    f"Add .dsSizedSheet(h) for a tray or .dsPageSheet() for a reading sheet."
                )
    return findings


def check_registry(files):
    """The named no-detent sheet views must keep their decision."""
    findings = []
    by_name = {p.name: p for p in files}
    for fname, reason in sorted(NO_DETENT_SHEETS.items()):
        path = by_name.get(fname)
        if path is None:
            findings.append(f"{fname} is registered here but no longer exists — remove the entry or fix the name.")
            continue
        body = strip_comments(path.read_text(encoding="utf-8", errors="replace"))
        if not MAC_SIZING.search(body):
            findings.append(f"{fname} lost its Mac sizing. It is registered because: {reason}")
    return findings


def run_audit():
    files = list(swift_files())
    if not files:
        print("✗ no Swift sources found", file=sys.stderr)
        return 1
    findings = check_detents(files) + check_registry(files)
    if findings:
        print("✗ mac sheet audit")
        for f in findings:
            print(f"    {f}")
        return 1
    detent_sites = sum(
        1 for p in files for l in strip_comments(p.read_text(encoding="utf-8", errors="replace")).splitlines()
        if DETENTS.search(l)
    )
    print(f"✓ mac sheet audit: {detent_sites} detent site(s) paired with a Mac size, "
          f"{len(NO_DETENT_SHEETS)} no-detent sheet view(s) decided")
    return 0


# ── self-test ──────────────────────────────────────────────────────────────
CLEAN = """
struct Good: View {
    var body: some View {
        Text("x")
        .presentationDetents([.medium, .large])
        .dsPageSheet()
    }
}
"""
DIRTY = """
struct Bad: View {
    var body: some View {
        Text("x")
        .presentationDetents([.medium, .large])
    }
}
"""
COMMENT_ONLY = """
struct Sneaky: View {
    var body: some View {
        // We call .dsPageSheet() elsewhere, honest.
        Text("x")
        .presentationDetents([.medium])
    }
}
"""
TRAY_OK = """
struct Tray: View {
    var body: some View {
        Text("x")
        .presentationDetents([.height(400)])
        .dsSizedSheet(400)
    }
}
"""
SIZING_OK = """
struct Page: View {
    var body: some View {
        Text("x")
        .presentationDetents([.large])
        .presentationSizing(.page)
    }
}
"""
TWO_STRUCTS = """
struct First: View {
    var body: some View {
        Text("a")
        .presentationDetents([.large])
        .dsPageSheet()
    }
}
struct Second: View {
    var body: some View {
        Text("b")
        .presentationDetents([.large])
    }
}
"""


def self_test():
    import tempfile
    cases = [
        ("clean view passes", CLEAN, 0),
        ("missing Mac sizing is caught", DIRTY, 1),
        ("a COMMENT naming the modifier is not compliance", COMMENT_ONLY, 1),
        ("a tray's stated height counts", TRAY_OK, 0),
        ("raw presentationSizing counts", SIZING_OK, 0),
        ("sizing in a SIBLING struct does not cover this one", TWO_STRUCTS, 1),
    ]
    ok = True
    for label, src, want in cases:
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "Case.swift"
            p.write_text(src)
            got = len(check_detents([p]))
            good = (got > 0) == (want > 0)
            ok &= good
            print(f"  {'✓' if good else '✗'} {label}")
    # The registry half must notice a lost decision.
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "AccountScreen.swift"
        p.write_text("struct AccountScreen: View { var body: some View { Text(\"x\") } }")
        got = len(check_registry([p]))
        good = got > 0
        ok &= good
        print(f"  {'✓' if good else '✗'} a registered view losing its sizing is caught")
    # Comment stripping must preserve line numbers, or every finding points at
    # the wrong line — which is how a real lint gets distrusted and turned off.
    stripped = strip_comments("a\n// b\n/* c\nd */\ne\n")
    good = len(stripped.splitlines()) == 5
    ok &= good
    print(f"  {'✓' if good else '✗'} comment stripping preserves line numbers")
    print("✓ self-test passed" if ok else "✗ self-test FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(self_test() if "--self-test" in sys.argv else run_audit())
