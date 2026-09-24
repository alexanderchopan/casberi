#!/usr/bin/env python3
"""A row that names a thing on the web carries its door (prd §909, §912).

`Thing.content` is the page the row's disc opens. Four bridges built rows with
none at all — the Safe signature that asks you to go and sign, a Splits
transfer, a Wise transfer, a Privy app wallet's activity — while the payload in
hand carried the transaction hash, the chain and the id that name that page.
The row read as a fact with nowhere to go, which is §83's dead control one
layer down: the disc draws, the tap does nothing.

WHY A MECHANICAL CHECK. `Thing.init` defaults `content` to `""`, so a doorless
row is the path of least resistance and compiles, builds and screenshots
perfectly. The GitHub events pass (§909) found the same shape as a door to the
repository ROOT; this audit catches the harder case, no door, which no screen
sweep can see because the row looks like every other row.

THE ONE CHECK. Every `Thing(kind: …)` constructed under `Casberi/Casberi/Model`
either passes a non-empty `content:` or is counted against its file's
allowance below. An allowance is a RULING with a reason (the object has no web
page: a HealthKit workout, a FinanceKit charge, a photo), never a snooze. A
file drawing FEWER doorless rows than it is allowed fails too, so the table
comes down as doors are added.

WHAT THIS DOES NOT CHECK. Rows built through a bridge's own helper (`thing(…)`,
`Shaped`, `land(…)`) whose door is a ROOT page rather than the object's — that
is a judgement per bridge (§912 lists them), not a grep. Nor the demo seeds
(`Demo*.swift`, a mode, not landed rows), DEBUG probes, the share extension or
the import receipts, which are outside `Model/` or are not landed rows.

Usage:  scripts/empty-door-audit.py [--self-test]
Exit 0 = clean.
"""
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TREE = "Casberi/Casberi/Model"

# file name → (doorless rows it may build, why). Counted; a stale row fails.
ALLOWED = {
    "AppleWalletBridge.swift": (4, "FinanceKit is on the phone: an account, a charge, a "
                                   "balance and a card have no web page"),
    "HealthIngest.swift": (1, "a HealthKit workout has no page; the rider seats add none"),
    "ScreenshotIngest.swift": (1, "a photo — the disc opens Photos by asset id, not a URL"),
    "GeminiImport.swift": (1, "an import: the door is the export's own file, stated in the "
                              "file's comment"),
    "AcornsLive.swift": (1, "an unmeasured seat behind a sign-in (§780b): no per-record page is "
                            "known, and a guessed one is a wrong door"),
    "RocketMoneyLive.swift": (1, "the same seat shape as Acorns (§780b)"),
    "SafeSigner.swift": (1, "a signature made on this phone; the transaction's own row "
                            "carries the Safe page"),
    "CardPointersBridge.swift": (1, "the MCP offer payload names no URL (measured in its "
                                    "decoder); the merchant is in the title"),
}

CALL = re.compile(r"\bThing\(\s*kind\s*:")


def blank_comments(src: str) -> str:
    """Comments emptied, LINES KEPT, so a finding's line number is the file's."""
    src = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), src, flags=re.S)
    out = []
    for line in src.splitlines():
        if line.strip().startswith("//"):
            out.append("")
        else:
            out.append(re.sub(r"(?<!:)//.*$", "", line))
    return "\n".join(out)


def calls(code: str):
    """Each `Thing(kind:` construction as (line, argument text)."""
    for m in CALL.finditer(code):
        i, depth = m.end(), 1
        while i < len(code) and depth:
            depth += {"(": 1, ")": -1}.get(code[i], 0)
            i += 1
        yield code.count("\n", 0, m.start()) + 1, code[m.end():i - 1]


def doorless(args: str) -> str | None:
    if not re.search(r"\bcontent\s*:", args):
        return "no content:"
    if re.search(r'\bcontent\s*:\s*""', args):
        return 'content: ""'
    return None


def scan(root: Path, tree: str = TREE) -> list[tuple[str, int, str]]:
    findings: list[tuple[str, int, str]] = []
    for path in sorted((root / tree).rglob("*.swift")):
        # The furnished demo's seeds are a MODE (§217), not rows a bridge lands,
        # and its notes deliberately point nowhere.
        if path.name.startswith("Demo"):
            continue
        rel = path.relative_to(root).as_posix()
        code = blank_comments(path.read_text())
        hits = [(line, why) for line, args in calls(code) if (why := doorless(args))]
        cap = ALLOWED.get(path.name, (0, ""))[0]
        if len(hits) > cap:
            for line, why in hits:
                findings.append((rel, line, f"a row with no door ({why}; {len(hits)} built, "
                                            f"{cap} allowed, §912)"))
        elif path.name in ALLOWED and len(hits) < cap:
            findings.append((rel, 0, f"builds {len(hits)} doorless rows of its {cap} — the "
                                     f"allowance is stale, bring it down"))
    return findings


def report(findings) -> int:
    if not findings:
        print(f"empty-door audit: clean — every landed row under {TREE} carries its door, "
              f"{len(ALLOWED)} reasoned allowances")
        return 0
    print("empty-door audit: FAILED")
    for rel, line, msg in findings:
        print(f"  {rel}:{line}: {msg}" if line else f"  {rel}: {msg}")
    print()
    print("  A row's `content` is the page its disc opens (prd §909, §912). If the")
    print("  payload names the object — a hash, an id, a handle — build that page.")
    print("  If the object has NO page, that is a ruling in docs/prd.md and a row")
    print("  in this audit's ALLOWED table with the reason, never an empty string.")
    return 1


def self_test() -> int:
    ok = True
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        model = root / TREE
        model.mkdir(parents=True)

        def plant(name: str, body: str) -> None:
            (model / name).write_text(body)

        plant("Doored.swift", 'let t = Thing(kind: .link, title: "a",\n'
                              '              content: "https://x.example/1", source: "S")\n')
        plant("Doorless.swift", 'let t = Thing(kind: .transaction, title: "a", source: "S")\n')
        plant("EmptyDoor.swift", 'let t = Thing(kind: .note, title: "a", content: "", source: "S")\n')
        plant("TalksAboutIt.swift", '// It used to build Thing(kind: .note, title: "a") with no door.\n'
                                    '/* and Thing(kind: .link, content: "") in a block */\n'
                                    'let t = Thing(kind: .link, title: "a", content: url, source: "S")\n')
        plant("HealthIngest.swift", 'let t = Thing(kind: .event, title: "", source: "H")\n')
        plant("AppleWalletBridge.swift", 'let t = Thing(kind: .note, title: "", content: "", source: "W")\n')
        plant("Nested.swift", 'let t = Thing(kind: .link, title: f(a, g(b)),\n'
                              '              content: url(for: item), source: "S")\n')

        findings = scan(root)
        flagged = {rel for rel, _, _ in findings}

        def said(name: str, fragment: str) -> bool:
            return any(r.endswith(name) and fragment in m for r, _, m in findings)

        cases = [
            ("a row with a door passes", f"{TREE}/Doored.swift" not in flagged),
            ("a row with no content: is caught", said("Doorless.swift", "no content:")),
            ("a row with an empty door is caught", said("EmptyDoor.swift", 'content: ""')),
            ("the finding names the file's own line",
             any(r.endswith("Doorless.swift") and line == 1 for r, line, _ in findings)),
            ("a file that only TALKS about a doorless row passes",
             f"{TREE}/TalksAboutIt.swift" not in flagged),
            ("an allowed file at its count passes", f"{TREE}/HealthIngest.swift" not in flagged),
            ("a stale allowance is reported", said("AppleWalletBridge.swift", "allowance is stale")),
            ("nested parentheses inside the call are walked", f"{TREE}/Nested.swift" not in flagged),
        ]
        for what, passed in cases:
            print(f"  {'ok  ' if passed else '✗   '} {what}")
            ok &= passed
    print("empty-door audit self-test:", "ok" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(self_test())
    sys.exit(report(scan(ROOT)))
