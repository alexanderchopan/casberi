#!/usr/bin/env python3
"""A verb is a row, a choice is a pill, nothing else has a backing (prd §1324).

The slab buttons (`DSSlabButton`, the commit; `DSSlabDoor`, the door) draw one
form everywhere: the row §640 gave them on account pages. A filled block
coming back inside either struct is the backed button the user retired
("we don't do that anymore"), so this fails on any `.background(` or the
slab's own shape inside them. Pills stay `Chip` (§746), wells stay fields
(§1027); neither is read here.

    python3 scripts/verb-row-audit.py [--self-test]
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SLAB = ROOT / "Casberi/Casberi/Design/DSSlab.swift"
STRUCTS = ("DSSlabButton", "DSSlabDoor")
BANNED = (re.compile(r"\.background\("), re.compile(r"DSSlab\.shape"), re.compile(r"\bprivate var slab\b"))


def body(src: str, name: str) -> str:
    m = re.search(r"^struct " + name + r"\b[^{]*\{", src, re.M)
    if not m:
        return ""
    i, depth = m.end() - 1, 0
    for j in range(i, len(src)):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                return src[i:j + 1]
    return src[i:]


def findings(src: str) -> list[str]:
    out = []
    for name in STRUCTS:
        b = body(src, name)
        if not b:
            out.append(f"{name} is gone or renamed — the verb-row rule reads it (prd §1324)")
            continue
        code = "\n".join(l.split("//")[0] for l in b.splitlines())
        for pat in BANNED:
            if pat.search(code):
                out.append(f"{name} draws a backing again ({pat.pattern}) — a verb is a row (prd §1324)")
    return out


def self_test() -> int:
    good = "struct DSSlabButton: View {\n var body: some View { actRow }\n}\nstruct DSSlabDoor: View {\n var body: some View { actRow }\n}\n"
    cases = [
        ("clean", good, 0),
        ("a fill comes back", good.replace("{ actRow }\n}\nstruct DSSlabDoor", "{ actRow.background(DS.tint, in: DSSlab.shape) }\n}\nstruct DSSlabDoor"), 1),
        ("the slab form returns", good.replace("var body: some View { actRow }\n}\n", "var body: some View { actRow }\n private var slab: some View { EmptyView() }\n}\n", 1), 1),
        ("a struct renamed", good.replace("DSSlabDoor", "DSSlabGate"), 1),
        ("a comment naming it is fine", good.replace("{ actRow }", "{ actRow } // no .background( here", 1), 0),
    ]
    bad = 0
    for name, src, want in cases:
        got = 1 if findings(src) else 0
        ok = got == want
        bad += 0 if ok else 1
        print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    if bad:
        print("✗ verb-row audit self-test failed")
        return 1
    print("✓ verb-row audit self-test: 5 cases")
    return 0


def main() -> int:
    if "--self-test" in sys.argv:
        return self_test()
    f = findings(SLAB.read_text())
    if f:
        for line in f:
            print("✗ " + line)
        return 1
    print("✓ verb-row audit: the slab buttons are rows (prd §1324)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
