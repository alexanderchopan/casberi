#!/usr/bin/env python3
"""Setup-screen anatomy audit (prd §608, 2026-09-04).

`setup-copy-audit.py` (§315) governs what a connect screen SAYS. Nothing
governed what it was SHAPED like, and the shape is where the drift went.

Measured across the sixty-two screens carrying `BridgeSetupHeader`, on the
tree as it stood the morning this was written:

  * the same six shared blocks appeared in **forty-eight distinct orders**,
    and twelve screens put the room door or the connected state ABOVE the
    identity block while the other fifty put them below;
  * every one of them ended its `List` with the same seven chassis modifiers,
    which is one screen copy-pasted sixty-two times — and two of the copies
    had already lost a modifier each, silently;
  * fifteen wordings existed for four outcomes, and the failure tone was a
    separate `Bool` that §252 had already caught five screens getting wrong;
  * eight screens carried a hand-rolled Disconnect, and not one of them
    offered the purge that the shared row has offered since 2026-07-13.

Every one of those is invisible from a build, from a screenshot, and from the
copy audit. So they are checks.

CHECKS
  A. Chassis — an account page draws none of the old chassis's vocabulary
     (`BridgeSetupPage`, `BridgeSetupHeader`, `BridgeConnectedState`,
     `RoomDoor`, `RecentThingsSection`) and keeps no chassis modifier of its
     own (`.bridgeSetupWash` / `.listStyle(.insetGrouped)`).
  B. DELETED with the slots (prd §639, 2026-09-06). The order is the chassis's
     now — an adopter fills two closures and hands over data for the rest — so
     it cannot be got wrong by a screen at all, which is strictly better than a
     text check that could. §608 made it an audit rather than a type because
     `setup-copy-audit.py` discovered a screen by its header; that reason went
     with the header.
  C. `BridgeFieldRow` stays deleted (§190's "two controls for one act").
  D. The proof row takes `proof:` — never `result:` + `resultIsError:`.
  E. Disconnect is `BridgeDisconnectSection`, never a hand-rolled destructive
     button, so the keep-or-purge choice cannot go missing again.
  F. `BridgeProof.says` never carries a line a case already covers.
  G. `flipTrigger` stays gone — the coin flip is derived from `connected`.

DELIBERATELY NOT CHECKED, so this cannot become the lint nobody runs:
  * whether a screen SHOULD have a connected state. That is a judgement about
    whether its form is set-once configuration or a list you come back to
    (§186 vs §465), and no grep can make it.
  * the ORDER of a screen's own sections (see B).
  * copy. That is `setup-copy-audit.py`'s job and it is better at it.
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCREENS = os.path.join(ROOT, "Casberi", "Casberi", "Screens")

# Files that name `BridgeSetupHeader` without being a setup screen: the
# component that declares it, the chassis that documents it, and the audit
# fixtures. Each is a conscious "this is not a screen", not a snooze.
NOT_A_SCREEN = {"BridgeSetupComponents.swift", "AccountPage.swift"}

# The old chassis's own vocabulary, kept as a DENYLIST rather than as an order
# (see check A). Nothing may draw these again: they are the slab-and-section
# anatomy §639 replaced, and a screen that brings one back brings the whole
# shape with it.

# A destructive button whose words are a CONNECTION verb. An item-level delete
# ("Remove" on one feed, "Unwatch") is a different act and is not matched.
HAND_DISCONNECT = re.compile(
    r'Button\(\s*"(Disconnect[^"]*|Remove (?:key|token|vault|folder|account)[^"]*)"'
    r'\s*,\s*role:\s*\.destructive')

# A `says` that a real case already covers.
SAYS_CANONICAL = re.compile(
    r'\.says\(\s*(?:String\(localized:\s*)?"'
    r'(?:Up to date|Connected\.?|\\\([\w.]+\) new)"')


def strip_comments(src: str) -> str:
    """Blank out comments and string bodies, character by character.

    Both matter here. A comment is prose that names the very things this
    audit forbids — this file's own docstring would fail check C — and a
    STRING can hold a screen's copy about its own Disconnect. The scanner is
    a character walk rather than a pair of regexes because a `//` inside a
    string literal and a `"` inside a comment each break the naive version,
    and a stripper that silently blanks the rest of a file reports that file
    as clean (the 2026-09-02 hero-tint defect, same shape)."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == '"':
            # a string: keep the quotes, blank the body
            out.append('"')
            i += 1
            while i < n and src[i] != '"':
                if src[i] == '\\':
                    out.append(' ')
                    i += 1
                    if i < n:
                        out.append(' ')
                        i += 1
                    continue
                out.append('\n' if src[i] == '\n' else ' ')
                i += 1
            if i < n:
                out.append('"')
                i += 1
            continue
        if src.startswith('//', i):
            while i < n and src[i] != '\n':
                out.append(' ')
                i += 1
            continue
        if src.startswith('/*', i):
            depth = 1
            out.append('  ')
            i += 2
            while i < n and depth:
                if src.startswith('/*', i):
                    depth += 1
                    out.append('  ')
                    i += 2
                elif src.startswith('*/', i):
                    depth -= 1
                    out.append('  ')
                    i += 2
                else:
                    out.append('\n' if src[i] == '\n' else ' ')
                    i += 1
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def strip_comments_only(src: str) -> str:
    """Comments blanked, strings KEPT — for the checks whose subject is a
    string literal (a hand-rolled Disconnect's label, a canonical `says`)."""
    out = []
    i, n = 0, len(src)
    while i < n:
        if src[i] == '"':
            out.append('"')
            i += 1
            while i < n and src[i] != '"':
                if src[i] == '\\':
                    out.append(src[i:i + 2])
                    i += 2
                    continue
                out.append(src[i])
                i += 1
            if i < n:
                out.append('"')
                i += 1
            continue
        if src.startswith('//', i):
            while i < n and src[i] != '\n':
                out.append(' ')
                i += 1
            continue
        if src.startswith('/*', i):
            depth = 1
            out.append('  ')
            i += 2
            while i < n and depth:
                if src.startswith('/*', i):
                    depth += 1; out.append('  '); i += 2
                elif src.startswith('*/', i):
                    depth -= 1; out.append('  '); i += 2
                else:
                    out.append('\n' if src[i] == '\n' else ' ')
                    i += 1
            continue
        out.append(src[i])
        i += 1
    return ''.join(out)


def line_of(src: str, pos: int) -> int:
    return src.count('\n', 0, pos) + 1


def page_blocks(code: str):
    """Every `BridgeSetupPage( … ) { … }` body in the file, brace-matched."""
    for m in re.finditer(r'BridgeSetupPage\(', code):
        i = code.index('{', m.end() - 1)
        depth, j = 0, i
        while j < len(code):
            if code[j] == '{':
                depth += 1
            elif code[j] == '}':
                depth -= 1
                if depth == 0:
                    break
            j += 1
        yield m.start(), code[i:j]


def audit(files):
    findings = []
    for path in files:
        name = os.path.basename(path)
        raw = open(path, encoding='utf-8').read()
        if 'AccountPage(' not in raw or name in NOT_A_SCREEN:
            continue
        code = strip_comments(raw)          # comments AND string bodies gone
        text = strip_comments_only(raw)     # comments gone, strings kept

        # --- A. chassis -------------------------------------------------
        #
        # THE OLD CHASSIS IS GONE (prd §639, 2026-09-06). Every connect screen
        # is an `AccountPage`, so what A can still catch is a screen that keeps
        # a chassis modifier of its own — the copy-pasted `List` this check was
        # written for, which is how two of the sixty-two silently lost one.
        for old_chassis in ('BridgeSetupPage(', 'BridgeSetupHeader(',
                            'BridgeConnectedState(', 'RoomDoor(',
                            'RecentThingsSection('):
            for m in re.finditer(r'\b' + re.escape(old_chassis), code):
                findings.append((name, line_of(code, m.start()), 'A',
                                 'draws ' + old_chassis + ' — the slab-and-section '
                                 'anatomy §639 replaced'))
        for pat in (r'\.bridgeSetupWash\(', r'\.listStyle\(\.insetGrouped\)'):
            for m in re.finditer(pat, code):
                findings.append((name, line_of(code, m.start()), 'A',
                                 'chassis modifier on an account page: '
                                 + pat.replace('\\', '')))

        # --- B. slot order ----------------------------------------------
        #
        # DELETED WITH THE SLOTS (prd §639). The order is the chassis's now —
        # an adopter fills two closures and hands over data for the rest — so
        # it cannot be got wrong by a screen at all, which is strictly better
        # than a text check that could. §608's own doc said the order was an
        # AUDIT rather than a type because `setup-copy-audit.py` discovered a
        # screen by its header; that reason went with the header.

        # --- C. BridgeFieldRow --------------------------------------------
        for m in re.finditer(r'\bBridgeFieldRow\b', code):
            findings.append((name, line_of(code, m.start()), 'C',
                             'BridgeFieldRow is deleted — use DSSlabField'))

        # --- D. proof row --------------------------------------------------
        for m in re.finditer(r'\bresultIsError\s*:', code):
            findings.append((name, line_of(code, m.start()), 'D',
                             'proof row takes proof: BridgeProof?, not result:/resultIsError:'))

        # --- E. hand-rolled disconnect -------------------------------------
        for m in HAND_DISCONNECT.finditer(text):
            findings.append((name, line_of(text, m.start()), 'E',
                             'hand-rolled disconnect — use BridgeDisconnectSection'))

        # --- F. says() saying what a case says -----------------------------
        for m in SAYS_CANONICAL.finditer(text):
            findings.append((name, line_of(text, m.start()), 'F',
                             '.says() carries a line BridgeProof already has a case for'))

        # --- G. flipTrigger ------------------------------------------------
        for m in re.finditer(r'\bflipTrigger\b', code):
            findings.append((name, line_of(code, m.start()), 'G',
                             'flipTrigger is deleted — the flip derives from connected:'))
    return findings


# ---------------------------------------------------------------- self-test
CLEAN = '''
struct FooScreen: View {
    var body: some View {
        AccountPage(name: "Foo", seatID: "foo", source: "Foo", state: st,
                    mode: .pasteKey, intro: "x", teardown: { }, sheet: $sheet,
                    act: { keyBlock }, more: { EmptyView() },
                    keySheet: { keyBlock })
    }
    private var keyBlock: some View {
        BridgeSyncStatusRows(syncing: s, syncingLine: "Reading Foo…", proof: proof)
    }
}
'''

DIRTY = {
 'A': ('''
struct FooScreen: View {
    var body: some View {
        AccountPage(name: "Foo", seatID: "foo", source: "Foo", state: st,
                    teardown: { }, sheet: $sheet, act: { EmptyView() },
                    more: { RoomDoor(name: "Foo", source: "Foo") },
                    keySheet: { EmptyView() })
        .listStyle(.insetGrouped)
        .bridgeSetupWash(name: "Foo")
    }
}
''', 'A'),
 'C': ('''
struct FooScreen: View {
    var body: some View {
        AccountPage(name: "Foo", seatID: "foo", source: "Foo", state: st) {
            BridgeFieldRow(placeholder: "Key", text: $k, buttonLabel: "Connect") { }
        }
    }
}
''', 'C'),
 'D': ('''
struct FooScreen: View {
    var body: some View {
        AccountPage(name: "Foo", seatID: "foo", source: "Foo", state: st) {
            BridgeSyncStatusRows(result: r, resultIsError: e)
        }
    }
}
''', 'D'),
 'E': ('''
struct FooScreen: View {
    var body: some View {
        AccountPage(name: "Foo", seatID: "foo", source: "Foo", state: st) {
            Button("Disconnect", role: .destructive) { Foo.disconnect() }
        }
    }
}
''', 'E'),
 'F': ('''
struct FooScreen: View {
    var body: some View {
        AccountPage(name: "Foo", seatID: "foo", source: "Foo", state: st) { }
    }
    private func go() { proof = .says(String(localized: "Up to date")) }
}
''', 'F'),
 'G': ('''
struct FooScreen: View {
    var body: some View {
        AccountPage(name: "Foo", seatID: "foo", source: "Foo", state: st,
                    flipTrigger: t) { }
    }
}
''', 'G'),
}

# The two that a naive stripper gets wrong, and the reason each is here.
TRICKY = {
 # A comment quoting the rule must not fail the rule. Every one of these
 # rules is documented in the source by naming the thing it forbids — the
 # Obsidian/Cursor lesson, and it has now cost this repo nine findings.
 'comment_quotes_rule': '''
struct FooScreen: View {
    // `BridgeFieldRow` was deleted; resultIsError went with it, and
    // flipTrigger too. Do not bring any of them back.
    var body: some View {
        AccountPage(name: "Foo", seatID: "foo", source: "Foo", state: st) { }
    }
}
''',
 # A string holding "//" must not open a comment and blank the rest of the
 # file — which would make every later violation invisible and report the
 # file clean, the worst way for a check to fail.
 'string_holds_slashes': '''
struct FooScreen: View {
    var body: some View {
        AccountPage(name: "Foo", seatID: "foo", source: "Foo", state: st,
                    intro: "https://x.example") { }
    }
}
''',
 # An ITEM-level Remove is not a connection verb. Nineteen screens have one.
 'item_level_remove': '''
struct FooScreen: View {
    var body: some View {
        AccountPage(name: "Foo", seatID: "foo", source: "Foo", state: st) {
            ForEach(feeds) { f in
                Button("Remove", role: .destructive) { drop(f) }
            }
        }
    }
}
''',
}


def self_test() -> int:
    import tempfile
    bad = 0

    def run(src, fname="FooScreen.swift"):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, fname)
            open(p, 'w', encoding='utf-8').write(src)
            return audit([p])

    got = run(CLEAN)
    if got:
        print("SELF-TEST FAIL: clean fixture flagged:", got); bad += 1

    for label, (src, want) in DIRTY.items():
        got = {f[2] for f in run(src)}
        if want not in got:
            print(f"SELF-TEST FAIL: {label} not caught (got {sorted(got) or 'nothing'})")
            bad += 1

    for label, src in TRICKY.items():
        got = run(src)
        if got:
            print(f"SELF-TEST FAIL: {label} should be clean, flagged: {got}")
            bad += 1

    if bad == 0:
        print(f"setup-anatomy-audit self-test ✓  "
              f"({1 + len(DIRTY) + len(TRICKY)} fixtures)")
    return bad


def main() -> int:
    if "--self-test" in sys.argv:
        return 1 if self_test() else 0
    if self_test():
        return 1
    files = [os.path.join(SCREENS, f) for f in sorted(os.listdir(SCREENS))
             if f.endswith('.swift')]
    findings = audit(files)
    if not findings:
        n = sum(1 for f in files
                if 'AccountPage(' in open(f, encoding='utf-8').read()
                and os.path.basename(f) not in NOT_A_SCREEN)
        print(f"setup anatomy ✓  ({n} setup screens, 7 checks)")
        return 0
    print(f"setup anatomy ✗  ({len(findings)} finding(s))")
    for name, line, check, why in findings:
        print(f"  {name}:{line}  [{check}]  {why}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
