#!/usr/bin/env python3
"""Sheet-sweep audit (prd §1308).

The sheet sweep (`journeys.sh sheets`, `CasberiUITests/SheetSweepTests.swift`)
opens every sheet, tray and cover in the app on the simulator and closes it
the ways a person would: a pull down, and its own control. This audit is the
half that needs no simulator. It lists every presentation in the code and
holds the sweep's manifest (`scripts/sheet-sweep.json`) to it, so a sheet
added tomorrow cannot go unswept without someone saying why.

What it inventories, from `Casberi/Casberi/**/*.swift`:

  * every `.sheet(`, `.fullScreenCover(`, `.dsOneSheet(` and
    `DSOneSheet(route:` site, keyed
    `<file>:<binding>` (`Screens/AccountScreen.swift:languageOpen`); a binding
    a file presents twice is `<binding>@2`.
  * a site whose item is a ROUTE ENUM is one key per case
    (`Screens/FeedScreen.swift:feedSheet#walletTokens`), so a case added to a
    router is a new sheet the manifest must name. Two routes nest a second
    enum (`SheetRoot.node`, `SettingsSheet.home`) and expand one more level.

What it requires of the manifest:

  1. every inventory key is covered by exactly one entry or one `exempt` row;
  2. every key the manifest names still exists (a stale entry is a sheet that
     moved, and its walk now proves nothing);
  3. every entry has an id (unique), a launch, steps, an anchor, and checks at
     least one way to close; every exempt row says why.

Usage:  scripts/sheet-sweep-audit.py [--list] [--self-test]
Exit 0 = clean.
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = "Casberi/Casberi"
MANIFEST = "scripts/sheet-sweep.json"
# The wrapper itself: its `.sheet(` lines are every `.dsOneSheet(` site's.
SKIP_FILES = {"Design/DSOneSheet.swift"}
SITE = re.compile(r"\.(sheet|fullScreenCover|dsOneSheet)\(|\bDSOneSheet\(")
# Called on `self` inside a `View` extension (the note page's cover): counted
# only when it reads a binding, so a function that merely shares the name is not.
BARE = re.compile(r"(?<![\w.$])(sheet|fullScreenCover)\(")
# A binding reached through another object: its type is declared elsewhere.
CROSS_FILE = {"route.sheet": "SheetRoot", "chrome.pivot": "PivotQuery",
              "chrome.appSheet": "AppSheet"}
# A route case whose payload is itself a route: expanded one more level.
NESTED = {("SheetRoot", "node"): "Node@Shell/HomeRoute.swift", ("SettingsSheet", "home"): "ListHome"}


def swift_files(root, overrides=None):
    """Every source file's text; `overrides` (rel path → text) stands in for
    a file, so the self-test can break one without copying the tree."""
    if root not in _READ:
        base = root / SRC
        _READ[root] = [(str(p.relative_to(base)), p.read_text()) for p in sorted(base.rglob("*.swift"))
                       if str(p.relative_to(base)) not in SKIP_FILES]
    for rel, text in _READ[root]:
        yield rel, (overrides or {}).get(rel) or text


_READ = {}


def binding_of(text, start):
    """The state a presentation reads, from the text after its `(`."""
    window = text[start:start + 240]
    for pat in (r"isPresented:\s*\$([\w.]+)", r"item:\s*\$([\w.]+)", r"route:\s*\$([\w.]+)"):
        m = re.match(r"\s*" + pat, window)
        if m:
            return m.group(1)
    # A computed binding: the state its getter reads, `a&&b` when it reads two.
    m = re.match(r"\s*(?:isPresented|item):\s*Binding\(get:\s*\{\s*([^}]*?)\s*(?:==|!=|\}|,\s*set)", window)
    if m:
        names = re.findall(r"[A-Za-z_][\w.]*", m.group(1))
        names = [n for n in names if n not in ("nil", "true", "false")]
        return "&&".join(names) if names else None
    return None


ENUM_DECL = re.compile(r"\benum\s+(\w+)\b[^{\n]*\{")
VAR_DECL = re.compile(r"\bvar\s+(\w+)\s*:\s*([\w.]+)\?")


class Index:
    """Where an enum is declared and what types a `var` name is declared
    with, looked up on demand behind a substring test (the regex over every
    file was the audit's whole cost)."""
    def __init__(self, sources):
        self.sources = sources
        self.memo = {}

    def __contains__(self, name):
        return self.enum(name) is not None

    def __getitem__(self, name):
        return self.enum(name)

    def enum(self, name):
        # "Node@Shell/HomeRoute.swift" names the file: a second `enum Node`
        # elsewhere (Yjs.swift's, prd §1355) took the route's cases otherwise.
        name, _, home = name.partition("@")
        key = ("enum", name, home)
        if key not in self.memo:
            self.memo[key] = None
            needle = "enum " + name
            for path, text in self.sources:
                if needle not in text or (home and not str(path).endswith(home)):
                    continue
                for m in ENUM_DECL.finditer(text):
                    if m.group(1) == name:
                        self.memo[key] = (text, m)
                        break
                if self.memo[key]:
                    break
        return self.memo[key]

    def get(self, var, default=None):
        key = ("var", var)
        if key not in self.memo:
            found = set()
            needle = "var " + var
            for _, text in self.sources:
                if needle in text:
                    found |= {m.group(2) for m in VAR_DECL.finditer(text) if m.group(1) == var}
            self.memo[key] = found
        return self.memo[key] or default


def index(sources):
    idx = Index(sources)
    return idx, idx


def enum_cases(enums, name):
    """Top-level case names of `enum <name>` anywhere in the tree, else None."""
    base, at, home = name.partition("@")
    short = base.split(".")[-1] + at + home
    for text, m in ([enums[short]] if short in enums else []):
        if not m:
            continue
        depth, i, body = 1, m.end(), []
        while i < len(text) and depth > 0:
            c = text[i]
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
            elif depth == 1:
                body.append(c)
            i += 1
        cases = []
        for line in "".join(body).splitlines():
            line = line.strip()
            if not line.startswith("case "):
                continue
            for part in re.split(r",(?![^(]*\))", line[5:]):
                cm = re.match(r"\s*([a-z]\w*)", part)
                if cm:
                    cases.append(cm.group(1))
        return cases or None
    return None


def declared_type(text, binding):
    last = binding.split(".")[-1]
    m = re.search(r"\bvar\s+" + re.escape(last) + r"\s*:\s*([\w.]+)\?", text)
    return m.group(1) if m else None


def inventory(root, overrides=None):
    sources = list(swift_files(root, overrides))
    enums, varTypes = index(sources)
    keys = []
    for rel, text in sources:
        seen = {}
        if "heet(" not in text and "Cover(" not in text:
            continue
        hits = list(SITE.finditer(text))
        for m in BARE.finditer(text):
            lead = text[text.rfind("\n", 0, m.start()) + 1:m.start()]
            if "func " not in lead and binding_of(text, m.end()):
                hits.append(m)
        for m in sorted(hits, key=lambda m: m.start()):
            line_start = text.rfind("\n", 0, m.start()) + 1
            lead = text[line_start:m.start()]
            # A comment, or a pattern match on a case named `sheet`.
            if lead.lstrip().startswith("//") or lead.rstrip().endswith("case"):
                continue
            binding = binding_of(text, m.end())
            if binding is None:
                keys.append(f"{rel}:?line{text.count(chr(10), 0, m.start()) + 1}")
                continue
            seen[binding] = seen.get(binding, 0) + 1
            key = f"{rel}:{binding}" + (f"@{seen[binding]}" if seen[binding] > 1 else "")
            # A computed binding (`a&&b`) is a flag, never a route.
            kind = None if "&&" in binding else (CROSS_FILE.get(binding) or declared_type(text, binding))
            if kind is None and "&&" not in binding:
                # Declared in another file of the same type (an extension's
                # file): taken when the tree agrees on one type for the name.
                found = varTypes.get(binding.split(".")[-1], set())
                kind = next(iter(found)) if len(found) == 1 else None
            cases = enum_cases(enums, kind) if kind else None
            if not cases:
                keys.append(key)
                continue
            for case in cases:
                inner = NESTED.get((kind.split(".")[-1], case))
                sub = enum_cases(enums, inner) if inner else None
                if sub:
                    keys.extend(f"{key}#{case}.{s}" for s in sub)
                else:
                    keys.append(f"{key}#{case}")
    return keys


def audit(root, overrides=None, manifest=None):
    keys = inventory(root, overrides)
    out = [f"{k}: a presentation the audit cannot read (no `isPresented: $x` or `item: $x`)"
           for k in keys if ":?line" in k]
    if manifest is None:
        try:
            manifest = json.loads((root / MANIFEST).read_text())
        except (OSError, ValueError) as e:
            return out + [f"{MANIFEST}: unreadable ({e})"]
    covered = {}
    ids = set()
    for e in manifest.get("entries", []):
        eid = e.get("id")
        if not eid:
            out.append(f"{MANIFEST}: an entry has no id")
            continue
        if eid in ids:
            out.append(f"{MANIFEST}: id {eid} twice")
        ids.add(eid)
        for field in ("launch", "steps", "anchor"):
            if not e.get(field) and not (field == "steps" and e.get("opensAtLaunch")):
                out.append(f"{MANIFEST}: {eid} has no {field}")
        if not e.get("swipe", True) and not e.get("control"):
            out.append(f"{MANIFEST}: {eid} checks no way to close (no swipe, no control)")
        for k in e.get("covers", []):
            covered.setdefault(k, []).append(eid)
    for x in manifest.get("exempt", []):
        if not (x.get("why") or "").strip():
            out.append(f"{MANIFEST}: an exempt row ({', '.join(x.get('covers', []))}) says no why")
        for k in x.get("covers", []):
            covered.setdefault(k, []).append("exempt")
    known = set(keys)
    for k in keys:
        if ":?line" in k:
            continue
        who = covered.get(k, [])
        if not who:
            out.append(f"{k}: a sheet the sweep never opens — add an entry to {MANIFEST}, or an exempt row saying why")
        elif len(who) > 1:
            out.append(f"{k}: covered {len(who)} times ({', '.join(who)})")
    for k in covered:
        if k not in known:
            out.append(f"{MANIFEST}: {k} names no sheet in the code (moved or renamed?)")
    return out


def self_test():
    clean = audit(ROOT)
    if clean:
        print("self-test: the tree itself is not clean:\n  " + "\n  ".join(clean[:10]), file=sys.stderr)
        return 1
    manifest = json.loads((ROOT / MANIFEST).read_text())
    a_key = manifest["entries"][0]["covers"][0]
    cases = [
        # A new sheet in the code with no entry.
        ("code", "Screens/AccountScreen.swift", ".sheet(isPresented: $languageOpen)",
         ".sheet(isPresented: $sweepProbe) { EmptyView() }\n        .sheet(isPresented: $languageOpen)",
         "AccountScreen.swift:sweepProbe: a sheet the sweep never opens"),
        # A new case on a router.
        ("code", "Screens/ContactsPage.swift", "case newContact\n",
         "case newContact\n    case sweepProbe\n", "ContactsPage.swift:sheet#sweepProbe"),
        # An entry that lost its cover.
        ("manifest", "drop", a_key, None, f"{a_key}: a sheet the sweep never opens"),
        # A stale cover.
        ("manifest", "add", "Screens/Nowhere.swift:gone", None, "names no sheet in the code"),
        # An exempt row with no reason.
        ("manifest", "why", None, None, "says no why"),
        # An entry that closes nothing.
        ("manifest", "noclose", None, None, "checks no way to close"),
    ]
    failed = 0
    for kind, a, b, c, expect in cases:
        m = json.loads(json.dumps(manifest))
        overrides = None
        if kind == "code":
            text = (ROOT / SRC / a).read_text()
            if b not in text:
                print(f"self-test FAILED: mutation anchor moved in {a}: {b[:50]!r}", file=sys.stderr)
                failed += 1
                continue
            overrides = {a: text.replace(b, c, 1)}
        elif a == "drop":
            m["entries"][0]["covers"].remove(b)
        elif a == "add":
            m["entries"][0]["covers"].append(b)
        elif a == "why":
            m.setdefault("exempt", []).append({"covers": [], "why": " "})
        elif a == "noclose":
            m["entries"][0]["swipe"] = False
            m["entries"][0].pop("control", None)
        found = audit(ROOT, overrides, m)
        if not any(expect.lower() in f.lower() for f in found):
            print(f"self-test FAILED: '{expect}' went unnoticed; found {found[:3]}", file=sys.stderr)
            failed += 1
    if failed:
        return 1
    print(f"sheet-sweep audit self-test: ok ({len(cases)} mutations)")
    return 0


def main():
    if "--self-test" in sys.argv[1:]:
        return self_test()
    if "--list" in sys.argv[1:]:
        print("\n".join(inventory(ROOT)))
        return 0
    findings = audit(ROOT)
    for f in findings:
        print(f"  {f}")
    if findings:
        print(f"✗ sheet-sweep audit: {len(findings)} finding(s) (prd §1308)")
        return 1
    n = len(inventory(ROOT))
    print(f"✓ sheet-sweep audit: all {n} sheets, trays and covers are in the sweep or say why not")
    return 0


if __name__ == "__main__":
    sys.exit(main())
