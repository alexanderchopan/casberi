#!/usr/bin/env python3
"""Casberi defaults-under-lock audit (prd §720, 2026-09-14).

A `UserDefaults` WRITE WHILE A LOCK IS HELD IS A DEADLOCK, and it killed build
570 on a real phone. The crash report is a `0x8BADF00D` scene-update watchdog
reading "is stuck (deadlock)", and the line that separates it from every other
watchdog in this project's history is the CPU accounting:

    Elapsed application CPU time (seconds): 0.017, 0% CPU

§614, §642, §646 and §657 are all the app doing too much work to answer in
time. This one did nothing at all. The cycle, both halves of it in the report:

  1. a background cooperative thread takes a store's NSLock and, holding it,
     calls `UserDefaults.standard.set`;
  2. `UserDefaults` posts its change notification SYNCHRONOUSLY on that thread;
  3. SwiftUI's `UserDefaultObserver.userDefaultsDidChange` — how `@AppStorage`
     invalidates — runs there and calls `Update.begin()`, taking SwiftUI's
     global update lock;
  4. the MAIN thread is inside `ViewBodyAccessor.updateBody`, already holding
     SwiftUI's update lock, and the body it is evaluating asks the same store
     for a reading.

Background holds ours and wants SwiftUI's. Main holds SwiftUI's and wants ours.

THE RULE: persistence from a locked store goes through `DefaultsWrite`, which
hands the bytes to one serial queue — preserving the order the lock
establishes — and touches `UserDefaults` on a thread holding nothing.

WHY A STATIC CHECK. Nothing that runs here can see this. The build is happy
either way; the simulator never reproduced it; it needs a bridge sweep and a
view body to collide inside the same millisecond on a real device under real
load. And the shape is not exotic — it is the obvious way to write a
thread-safe cache, it was written that way five times independently in this
codebase, and two of those carried a comment explaining that the write stays
inside the lock ON PURPOSE.

**THE WRITE IS USUALLY A FRAME DEEPER.** Four of the five shipped cases hold
the lock across a CALL — `record()` takes the lock and calls `save()`,
`note()` takes it and calls `write()` — so a scan that looks only between a
`lock()` and its `unlock()` sees nothing. This resolves, per type, which of its
own functions reach a `UserDefaults` write transitively, and then treats a call
to one of those as a write.

That precision is the point and it was earned twice. The first cut of this
script scanned function-locally, passed twelve hand-written fixtures, and found
ONE of the five real defects. The second cut flagged any locked type touching
`UserDefaults` anywhere, caught all five, and falsely accused two more
(`AgentAnswer`, `EmbeddingIndex`) whose writes no lock can reach. So
`--self-test` runs BOTH ways against the real pre-fix files: all five must be
caught, and those two must come back clean. Fixtures prove a check does what
you meant; only the tree proves you meant the right thing.

Exit non-zero on a finding.
"""

import re
import subprocess
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = [ROOT / "Casberi" / "Casberi", ROOT / "Casberi" / "Shared"]

# `DefaultsWrite` is the door itself; its queue body writes `UserDefaults`
# deliberately, on a thread holding nothing.
EXEMPT = {"DefaultsWrite.swift"}

LOCK = re.compile(r"\b\w*[Ll]ock\.lock\(\)")
UNLOCK = re.compile(r"\b\w*[Ll]ock\.unlock\(\)")
WRITE = re.compile(
    r"(UserDefaults\s*\(\s*suiteName[^)]*\)\s*\??|UserDefaults\.\w+|"
    r"\bgroupDefaults\s*\??|\bdefaults\s*\??|\bd)\s*\??\.\s*"
    r"(set|setValue|removeObject|removePersistentDomain|synchronize)\s*\("
)
STRING = re.compile(r'"(?:[^"\\]|\\.)*"')
TYPE_HEAD = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"
    r"(?:public\s+|internal\s+|private\s+|fileprivate\s+|final\s+|indirect\s+)*"
    r"(?:enum|class|struct|actor|extension)\s+[\w.]+")
# Deliberately loose: attributes and modifiers vary, and a declaration this
# misses is a function whose writes go unattributed, i.e. a false NEGATIVE.
FUNC_HEAD = re.compile(r"\bfunc\s+(\w+)")


def strip(line):
    """Comments and string bodies out, so braces and calls inside them neither
    move the depth nor read as code."""
    line = STRING.sub('""', line)
    cut = line.find("//")
    return line if cut < 0 else line[:cut]


def blocks(lines, head, base_depth=0):
    """(header index, [lines]) for every `head`-matching declaration whose body
    opens at `base_depth`. Names are returned by the caller's own regex."""
    out = []
    depth = base_depth
    start = None
    opened = None
    for n, raw in enumerate(lines):
        line = strip(raw)
        if start is None and depth == base_depth and head.search(line) and "{" in line:
            start = n
            opened = depth
        depth += line.count("{") - line.count("}")
        if start is not None and depth <= opened:
            out.append((start, lines[start:n + 1]))
            start = None
    return out


def reaching_writers(functions):
    """Which of a type's own functions reach a `UserDefaults` write — directly,
    or through another of its functions. Fixpoint over a one-type call graph."""
    bodies = {name: "\n".join(strip(l) for l in body) for name, body in functions}
    writers = {n for n, b in bodies.items() if WRITE.search(b)}
    changed = True
    while changed:
        changed = False
        for name, body in bodies.items():
            if name in writers:
                continue
            for target in writers:
                if target == name:
                    continue
                if re.search(r"\b" + re.escape(target) + r"\s*\(", body):
                    writers.add(name)
                    changed = True
                    break
    return writers


def held_scan(lines, offset, writers):
    """Line numbers (1-based, `offset`-relative) where — with a lock held — a
    `UserDefaults` write happens, or a function that reaches one is called.

    Run over a WHOLE TYPE BODY rather than per function, on purpose: brace
    depth releases a hold at a function's closing brace anyway, and a
    declaration whose header this file's regexes did not recognise still gets
    scanned."""
    findings = []
    depth = 0
    held = None          # (kind, depth): "explicit" until .unlock(), "defer" to scope end
    reaches = re.compile(r"\b(" + "|".join(re.escape(w) for w in sorted(writers)) +
                         r")\s*\(") if writers else None
    for n, raw in enumerate(lines):
        line = strip(raw)
        opens, closes = line.count("{"), line.count("}")

        if held is not None and (WRITE.search(line) or (reaches and reaches.search(line))):
            findings.append(offset + n + 1)

        if held is not None and UNLOCK.search(line):
            # `defer { lock.unlock() }` on its own line is not a release — it is
            # what makes the hold last to the end of the scope. Reading it as a
            # release is why an earlier cut called `NetworkLedger` and
            # `AppMetrics` clean; both write those two lines separately.
            if "defer" in line:
                held = ("defer", held[1])
            elif held[0] == "explicit":
                held = None
        elif LOCK.search(line):
            held = ("defer" if ("defer" in line and UNLOCK.search(line)) else "explicit",
                    depth)

        depth += opens - closes
        # A defer's hold ends when the scope that TOOK the lock closes, i.e.
        # when the depth drops BELOW the depth that line sat at — not when it
        # returns to it, which is where it already is.
        if held is not None and held[0] == "defer" and depth < held[1]:
            held = None
    return findings


def scan(text):
    """Every line where a `UserDefaults` write is reachable under a held lock."""
    lines = text.splitlines()
    findings = []
    for type_start, type_lines in blocks(lines, TYPE_HEAD):
        inner = type_lines[1:]
        functions = []
        for idx, body in blocks(inner, FUNC_HEAD, base_depth=0):
            match = FUNC_HEAD.search(strip(body[0]))
            if match:
                functions.append((match.group(1), body))
        writers = reaching_writers(functions)
        if not writers:
            continue
        findings += held_scan(type_lines, type_start, writers)
    return sorted(set(findings))


def audit():
    findings = []
    for root in SOURCES:
        for path in sorted(root.rglob("*.swift")):
            if path.name in EXEMPT:
                continue
            rel = path.relative_to(ROOT)
            for line in scan(path.read_text()):
                findings.append(f"{rel}:{line}: a `UserDefaults` write is reached "
                                f"with a lock held — route it through "
                                f"`DefaultsWrite` (prd §720)")
    return findings


FIXTURES = [
    ("write inside an explicit lock/unlock pair", """
enum S {
    private static let lock = NSLock()
    static func flush() {
        lock.lock()
        UserDefaults.standard.set(data, forKey: storeKey)
        lock.unlock()
    }
}
""", True),
    ("lock.lock() and defer on SEPARATE lines, write later", """
final class S {
    private let lock = NSLock()
    private func flush() {
        lock.lock()
        defer { lock.unlock() }
        UserDefaults.standard.set(data, forKey: key)
    }
}
""", True),
    ("lock.lock(); defer on ONE line, write later", """
enum S {
    static func flush() {
        lock.lock(); defer { lock.unlock() }
        UserDefaults.standard.set(data, forKey: key)
    }
}
""", True),
    ("the write is a frame deeper, in a private helper", """
enum S {
    private static let lock = NSLock()
    static func record() {
        lock.lock(); defer { lock.unlock() }
        save(book)
    }
    private static func save(_ book: Book) {
        cache = book
        UserDefaults.standard.set(data, forKey: key)
    }
}
""", True),
    ("two frames deeper", """
enum S {
    private static let lock = NSLock()
    static func note() {
        lock.lock(); defer { lock.unlock() }
        write(records)
    }
    private static func write(_ r: R) { persist(r) }
    private static func persist(_ r: R) {
        UserDefaults.standard.set(data, forKey: key)
    }
}
""", True),
    ("removeObject under the lock", """
final class S {
    private let lock = NSLock()
    func wipe() {
        lock.lock()
        entries = [:]
        UserDefaults.standard.removeObject(forKey: storeKey)
        lock.unlock()
    }
}
""", True),
    ("an app-group suite write under the lock", """
enum S {
    static func flush() {
        lock.lock()
        groupDefaults?.set(stamp, forKey: "widget.lastSeen")
        lock.unlock()
    }
}
""", True),
    # --- must NOT flag -----------------------------------------------------
    ("the write AFTER the unlock", """
final class S {
    private let lock = NSLock()
    func flush() {
        lock.lock()
        let snapshot = entries
        lock.unlock()
        UserDefaults.standard.set(encode(snapshot), forKey: storeKey)
    }
}
""", False),
    ("a helper that writes, never called under the lock", """
enum S {
    private static let lock = NSLock()
    static func configured() -> [P] {
        lock.lock(); defer { lock.unlock() }
        return memo
    }
    static func activate(_ p: P) {
        UserDefaults.standard.set(p.rawValue, forKey: activeKey)
    }
}
""", False),
    ("a READ under the lock — reads post no notification", """
enum S {
    private static let lock = NSLock()
    static func loaded() -> Data? {
        lock.lock(); defer { lock.unlock() }
        return UserDefaults.standard.data(forKey: key)
    }
    static func save() { UserDefaults.standard.set(d, forKey: key) }
}
""", False),
    ("the DefaultsWrite hand-off under the lock, which is the fix", """
enum S {
    private static let lock = NSLock()
    static func flush() {
        lock.lock(); defer { lock.unlock() }
        DefaultsWrite.set(data, forKey: storeKey)
    }
}
""", False),
    ("a lock+defer scope that closed before the write", """
enum S {
    private static let lock = NSLock()
    static func outer() {
        run {
            lock.lock(); defer { lock.unlock() }
            cache = book
        }
        UserDefaults.standard.set(data, forKey: key)
    }
}
""", False),
    ("the write named only inside a comment", """
enum S {
    private static let lock = NSLock()
    static func flush() {
        lock.lock()
        // NOT UserDefaults.standard.set(data, forKey: key) — see DefaultsWrite
        DefaultsWrite.set(data, forKey: key)
        lock.unlock()
    }
}
""", False),
    ("a brace inside a string literal does not move the depth", """
enum S {
    private static let lock = NSLock()
    static func flush() {
        lock.lock(); defer { lock.unlock() }
        log("closing } brace")
        DefaultsWrite.set(data, forKey: key)
    }
}
""", False),
]

# The pass's own evidence: the files as they shipped in build 570, and what
# this check must say about each. Run from git, so it keeps testing the real
# thing long after the working tree is fixed.
SHIPPED = "9f398d6"
MUST_CATCH = [
    "Casberi/Casberi/Model/BridgeHealth.swift",     # the one in the crash report
    "Casberi/Casberi/Model/FeedFreshness.swift",
    "Casberi/Casberi/Model/NetworkLedger.swift",
    "Casberi/Casberi/Model/AgentSpend.swift",
    "Casberi/Casberi/Model/AppMetrics.swift",
]
MUST_PASS = [
    # Both keep an NSLock and both write `UserDefaults` — and no lock-holding
    # path of either reaches those writes. A coarser rule accused them.
    "Casberi/Casberi/Model/AgentAnswer.swift",
    "Casberi/Casberi/Model/EmbeddingIndex.swift",
]


def shipped(path):
    out = subprocess.run(["git", "-C", str(ROOT), "show", f"{SHIPPED}:{path}"],
                         capture_output=True, text=True)
    return out.stdout if out.returncode == 0 else None


def self_test():
    failures = 0
    for name, source, should_flag in FIXTURES:
        if bool(scan(source)) != should_flag:
            print(f"✗ fixture '{name}' should {'flag' if should_flag else 'pass'} and did not")
            failures += 1

    missing = False
    for path in MUST_CATCH:
        text = shipped(path)
        if text is None:
            missing = True
            continue
        if not scan(text):
            print(f"✗ build 570's {path} is NOT caught — it shipped the deadlock shape")
            failures += 1
    for path in MUST_PASS:
        text = shipped(path)
        if text is None:
            missing = True
            continue
        hits = scan(text)
        if hits:
            print(f"✗ build 570's {path} is falsely accused at {hits} — "
                  f"no lock-holding path reaches those writes")
            failures += 1
    if missing:
        print(f"  (skipped the build-570 checks: commit {SHIPPED} not in this clone)")

    live = audit()
    if live:
        print("✗ self-test cannot run: the tree already has findings")
        for f in live:
            print("   " + f)
        failures += 1
    if failures:
        return 1
    print(f"✓ defaults-lock audit self-test: {len(FIXTURES)} fixtures, "
          f"{len(MUST_CATCH)} shipped defects caught, {len(MUST_PASS)} lookalikes cleared")
    return 0


def main():
    if "--self-test" in sys.argv:
        return self_test()
    findings = audit()
    if findings:
        print("defaults-lock audit: FINDINGS")
        for f in findings:
            print("  ✗ " + f)
        print("\nA `UserDefaults` write posts its change notification synchronously on "
              "the writing thread; SwiftUI's @AppStorage observer takes SwiftUI's global "
              "update lock there; and the main thread holds that lock whenever it is "
              "inside a view body. Build 570 died this way. Hand the bytes to "
              "`DefaultsWrite` instead — it keeps your ordering and writes on a thread "
              "holding nothing.")
        return 1
    print("defaults-lock audit: ok — no UserDefaults write is reachable under a lock")
    return 0


if __name__ == "__main__":
    sys.exit(main())
