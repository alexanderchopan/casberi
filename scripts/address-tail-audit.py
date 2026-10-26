#!/usr/bin/env python3
"""A SHORTENED ADDRESS IS ITS TAIL: `...e07a` (prd §1551, user 2026-10-26).

Three ASCII dots and the last four characters, spelled in ONE place,
`Casberi/Shared/AddressTail.swift`. Never cut at both ends (`0x4b19…e07a`),
never the `…` character. The rule had been ruled three times before (§483,
§495, the 2026-10-19 "never front and end truncation") and each time a file
somewhere still spelled its own: `YourAccountPreview.short` drew
`0x1a2B…cD09` into Move's sentence, `AztecSignRequest.short` drew ten and
eight, the demo carried `0x9f…21`, and nine files each kept a private
`"…" + suffix(4)`. Every one of them renders as an ordinary row, so nothing
but a check sees the drift.

Three checks, over every Swift file in the app, the extensions and Shared
(comments ignored):

  (1) HEAD AND TAIL. A `prefix(…)` and a `suffix(…)` joined by an ellipsis
      (`…`, `...` or `\\u{2026}`) on one line is a both-ends shortener.
  (2) A TAIL SPELLED BY HAND. An ellipsis glued to a `suffix(…)` —
      `"…" + x.suffix(4)`, `"...\\(x.suffix(4))"` — outside `AddressTail`. Call
      `AddressTail.short(_:wholeUpTo:)`; it is the one spelling.
  (3) A SHORT ID WRITTEN AS DATA. A string literal holding a hex id cut at
      both ends (`0x9f…21`) or a `…` tail (`from …Kf2W`) — the demo's rows
      and fixtures draw on screen like anything else.

The allowance below is per file, with its reason, and is a CEILING and a
FLOOR: more is a new shortener, fewer is a stale allowance to lower.

**STATED CEILINGS.** It reads one line at a time and string literals only:
a shortener built across statements (`let head = a.prefix(6)` … `head + "…"
+ tail`) passes, as does SwiftUI's own `.truncationMode(.middle)` on a whole
value that does not fit (generic rows; a whole address is shown whole or
wrapped, `AddressBookViews`). `address-tail-selftest.sh` holds the helper's
shape and pins the forwarders to it.
"""

import re
import sys
from pathlib import Path

ROOTS = ("Casberi/Casberi", "Casberi/Shared", "Casberi/CasberiWidgets",
         "Casberi/ShareExtension", "Casberi/NotificationContent")
HELPER = "AddressTail.swift"

# file name → {check: (allowed count, reason)}
ALLOWED = {
    "WalletStore.swift": {
        "head-and-tail": (1, "isAutoName RECOGNISES the pre-2026-08-12 placeholder books on disk still hold; it draws nothing"),
        "hand-tail": (1, "isAutoName RECOGNISES the …-four placeholder (to 2026-10-26) books on disk still hold; it draws nothing"),
    },
    "AgentAnswer.swift": {
        "hand-tail": (1, "a stored API key's hint (…3kQA) — a secret's tail, not an address or an id"),
    },
    "L2beatDirectory.swift": {
        "id-literal": (1, "L2BEAT's own prose, quoted as published (`0x00…0074`), not an id the app shortened"),
    },
}

ELLIPSIS = r'(?:…|\.\.\.|\\u\{2026\})'
HEAD_AND_TAIL = re.compile(r'prefix\([^)\n]*\)[^\n]*?' + ELLIPSIS + r'[^\n]*?suffix\(')
HAND_TAIL = re.compile(
    r'"' + ELLIPSIS + r'"\s*\+[^\n]*?suffix\('          # "…" + x.suffix(4)
    r'|"' + ELLIPSIS + r'\\\([^\n]*?suffix\(')           # "…\(x.suffix(4))"
STRING = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
ID_LITERAL = re.compile(
    r'\b0x[0-9a-fA-F]{1,12}' + ELLIPSIS + r'[0-9a-fA-F]{1,12}\b'   # 0x9f…21
    r'|(?:^|[\s(])…[0-9A-Za-z]{4}(?![0-9A-Za-z])')                 # from …Kf2W


def strip_comments(src: str) -> list[str]:
    out = []
    for line in src.splitlines():
        if line.lstrip().startswith("//"):
            out.append("")
            continue
        # A trailing `// …` comment, outside a string literal.
        quoted, cut = False, None
        i = 0
        while i < len(line):
            c = line[i]
            if c == "\\" and quoted:
                i += 2
                continue
            if c == '"':
                quoted = not quoted
            elif not quoted and line.startswith("//", i):
                cut = i
                break
            i += 1
        out.append(line if cut is None else line[:cut])
    return out


def scan(src: str) -> dict[str, list[str]]:
    hits = {"head-and-tail": [], "hand-tail": [], "id-literal": []}
    for line in strip_comments(src):
        if HEAD_AND_TAIL.search(line):
            hits["head-and-tail"].append(line.strip())
        elif HAND_TAIL.search(line):
            hits["hand-tail"].append(line.strip())
        for lit in STRING.findall(line):
            if ID_LITERAL.search(lit):
                hits["id-literal"].append(f'"{lit}"')
    return hits


WHY = {
    "head-and-tail": "a shortener cut at BOTH ends — an address is its tail, `AddressTail.short`",
    "hand-tail": "a tail spelled by hand — call `AddressTail.short(_:wholeUpTo:)`",
    "id-literal": "a short id written as data in the old spelling — write `...xxxx`",
}


def audit(files: dict[str, str]) -> list[str]:
    findings = []
    seen = set()
    for path, src in files.items():
        name = Path(path).name
        if name == HELPER:
            continue
        hits = scan(src)
        allowed = ALLOWED.get(name, {})
        if allowed:
            seen.add(name)
        for check, found in hits.items():
            limit, reason = allowed.get(check, (0, ""))
            if len(found) > limit:
                shown = "; ".join(found[:3])
                findings.append(f"{path}: {len(found)} × {WHY[check]} (allowed {limit}"
                                f"{' — ' + reason if reason else ''}): {shown}")
            elif len(found) < limit:
                findings.append(f"{path}: {len(found)} {check} line(s), allowance says {limit} —"
                                f" lower the allowance in address-tail-audit.py")
    for name in ALLOWED:
        if name not in seen:
            findings.append(f"{name}: on the allowance list but not in the tree — remove the row")
    return findings


def self_test() -> bool:
    ok = True

    def expect(label, cond):
        nonlocal ok
        print(f"  {'✓' if cond else '✗'} {label}")
        ok = ok and cond

    base = {
        "Casberi/Shared/AddressTail.swift":
            'static let dots = "..."\nreturn dots + String(id.suffix(shown))\nlet x = "…" + id.suffix(4)\n',
        "Casberi/Casberi/Model/WalletStore.swift":
            'AddressTail.short(address)\nif name == "…\\(address.suffix(4))" { return true }\n'
            'return name == "\\(address.prefix(6))…\\(address.suffix(4))"\n',
        "Casberi/Casberi/Model/AgentAnswer.swift": 'return "…" + key.suffix(4)\n',
        "Casberi/Casberi/Model/L2beatDirectory.swift": '"a precompile (0x00…0074), after which"\n',
        "Casberi/Casberi/Model/Good.swift":
            'let s = AddressTail.short(a)\nlet t = String(text.prefix(80)) + "…"\n'
            'Text("Fetching \\(bridge.noun)…")\nlet c = "\\(card) ••\\(last4)"\n',
    }
    expect("a clean tree has no findings", audit(base) == [])

    def one(code: str, check: str) -> bool:
        tree = dict(base)
        tree["Casberi/Casberi/Screens/New.swift"] = code
        f = audit(tree)
        return len(f) == 1 and "New.swift" in f[0] and WHY[check].split(" — ")[0] in f[0]

    expect("prefix…suffix concatenated is head-and-tail",
           one('return String(a.prefix(6)) + "…" + String(a.suffix(4))\n', "head-and-tail"))
    expect("prefix…suffix interpolated is head-and-tail",
           one('return "\\(h.prefix(10))…\\(h.suffix(8))"\n', "head-and-tail"))
    expect("three dots between them too",
           one('return "\\(a.prefix(6))...\\(a.suffix(4))"\n', "head-and-tail"))
    expect("a hand tail with + is caught", one('return "…" + body.suffix(4)\n', "hand-tail"))
    expect("a hand tail interpolated is caught", one('"…\\(address.suffix(4))"\n', "hand-tail"))
    expect("a hand tail with three dots is caught too", one('"...\\(a.suffix(4))"\n', "hand-tail"))
    expect("a hex id cut at both ends in data is caught",
           one('content: "Base · from 0x9f…21"\n', "id-literal"))
    expect("a … tail in data is caught", one('("Sent 40 — to …hE51", ["Sent"], 2)\n', "id-literal"))
    expect("the new spelling in data is fine", audit({**base, "Casberi/Casberi/Model/D.swift":
                                                      '("Sent 40 — to ...hE51", ["Sent"], 2)\n'}) == [])
    expect("a comment is not code",
           audit({**base, "Casberi/Casberi/Model/C.swift": '// was "0x1a2B…cD09": String(a.prefix(6)) + "…" + a.suffix(4)\n'
                                                           'let y = 1 // "…" + a.suffix(4)\n'}) == [])

    grown = dict(base)
    grown["Casberi/Casberi/Model/AgentAnswer.swift"] += 'return "…" + other.suffix(4)\n'
    expect("an allowance that grew is a finding", any("AgentAnswer" in x for x in audit(grown)))
    stale = dict(base)
    stale["Casberi/Casberi/Model/AgentAnswer.swift"] = "return AddressTail.short(key)\n"
    expect("a stale allowance is a finding", any("lower the allowance" in x for x in audit(stale)))
    gone = dict(base)
    del gone["Casberi/Casberi/Model/L2beatDirectory.swift"]
    expect("an allowance for a missing file is a finding", any("not in the tree" in x for x in audit(gone)))
    return ok


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    print("address-tail-audit self-test")
    if not self_test():
        print("SELF-TEST FAILED")
        return 1
    if "--self-test" in sys.argv:
        print("  self-test passed")
        return 0
    files = {}
    for r in ROOTS:
        for p in sorted((root / r).rglob("*.swift")):
            files[str(p.relative_to(root))] = p.read_text(encoding="utf-8", errors="replace")
    findings = audit(files)
    if findings:
        print(f"address-tail-audit: {len(findings)} finding(s)")
        for f in findings:
            print(f"  ✗ {f}")
        return 1
    print(f"address-tail-audit: clean — {len(files)} files, every short id is AddressTail's `...xxxx`")
    return 0


if __name__ == "__main__":
    sys.exit(main())
