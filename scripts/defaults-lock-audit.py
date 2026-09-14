#!/usr/bin/env python3
"""Defaults-under-a-lock audit (prd §721, 2026-09-14).

WHY THIS EXISTS. Build 570 died on the user's phone with `0x8BADF00D` — a
scene-update watchdog, faulting thread `com.apple.main-thread`, four minutes
after launch, reported as *"touching the app catalog icon in top is inactive
and leads to crashing on multiple pages"*. Every page was inactive: the main
thread was not slow, it was DEADLOCKED, and the crash report names both halves.

  · MAIN: `ViewBodyAccessor.updateBody` → Casberi → `__psynch_mutexwait`.
    A view body, which by construction holds SwiftUI's update lock (every body
    runs under `Update.ensure`), waiting on `BridgeHealth.lock`. All 55 account
    pages ask `AccountPageState.of` from their body.
  · A SWEEP, on `com.apple.root.user-initiated-qos.cooperative`: Casberi →
    `-[NSNotificationCenter postNotificationName:…]` →
    `UserDefaultObserver.userDefaultsDidChange` → `Update.enqueueAction` →
    `Update.begin` → `_MovableLockLock` → `__psynch_mutexwait`.
    It HOLDS `BridgeHealth.lock` (load-modify-save is one critical section,
    prd §710) and inside it called `UserDefaults.standard.set` — which posts
    `didChangeNotification` SYNCHRONOUSLY, on the calling thread. Any app with
    an `@AppStorage` anywhere has SwiftUI's own observer on that notification,
    and the observer takes the update lock main is holding.

Two locks, two orders, no way out. Three more threads in the same report were
queued behind the same `BridgeHealth.lock`.

THE RULE THIS ENFORCES, which is broader than the one crash: code holding a
lock must not write `UserDefaults`. The write reads as a pure store touch and
is a synchronous call-out to every observer in the process, SwiftUI's included.
`Model/DefaultsWrite.swift` is the door — it moves the store write to one
serial queue, keeping same-key ordering (the reason those writes were put
inside the lock) without the call-out.

Five stores shipped this shape and are all fixed: `BridgeHealth` (the one that
crashed), `FeedFreshness`, `NetworkLedger`, `AgentSpend` and `AppMetrics`.

WHAT IT CHECKS, static, no build:

  1. No `UserDefaults` write — `set`, `setValue`, `removeObject`, `register`,
     `synchronize` — inside a critical section, whether written inline, in a
     `defer`-unlocked function, or in a `withLock { }` block.
  2. …including one level of indirection: a helper in the same file that
     writes defaults, called from inside a critical section. That is exactly
     how the crash was written (`record` held the lock and called `save`),
     so a check that reads only the locked lines would have passed it.
  3. No `NotificationCenter.post` inside a critical section either. Same
     hazard by the same mechanism — a synchronous call-out to observers that
     may take the main actor's or SwiftUI's own locks — and it is the general
     form of what `UserDefaults.set` does behind your back.

WHAT IT DELIBERATELY DOES NOT CHECK, so it stays honest about its reach:

  · An actor, a `DispatchQueue.sync`, or `MainActor.assumeIsolated` holding
    the same call-out. The crash was an `NSLock`, the fix is an `NSLock`
    rule, and a scan for every serialization primitive in the tree would be
    mostly false alarms this file cannot judge. `EmbeddingIndex.serialized`
    is the one queue with the same shape and it writes no defaults.
  · Whether a view body reads a lock-guarded store at all. It should not
    (prd §628), and hundreds do through `AccountPageState.of`; making that
    read cheap is what the memoised caches are for. This closes the deadlock,
    which is the half that kills the app.
  · A write reached two levels down (a helper calling a helper). No such call
    exists today; the census names every helper resolved.
"""

import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIRS = ["Casberi/Casberi", "Casberi/Shared", "Casberi/CasberiWidgets",
               "Casberi/ShareExtension"]

# A defaults WRITE. Reads (`data(forKey:)`, `bool(forKey:)`) are fine under a
# lock — they post nothing.
WRITE_VERBS = "set|setValue|removeObject|removePersistentDomain|register|synchronize"
DEFAULTS_WRITE = re.compile(
    r"\bUserDefaults\s*(?:\.\w+|\([^)]*\))?\s*(?:\?|!)?\s*\.\s*(?:" + WRITE_VERBS + r")\s*\(")
# …and through a NAMED receiver. The name is not guessed: `defaults_receivers`
# below reads the file for bindings and parameters that ARE a `UserDefaults`
# (`let d = UserDefaults.standard`, `group: UserDefaults`), because a bare
# `.set(` on any receiver would fire on every dictionary and Set in the tree.
BINDING = re.compile(r"\b(?:let|var)\s+(\w+)\s*(?::\s*UserDefaults[?!]?\s*)?=\s*[^\n]*\bUserDefaults\b")
TYPED = re.compile(r"\b(\w+)\s*:\s*UserDefaults[?!]?\b")

NOTIFY_POST = re.compile(r"NotificationCenter[^\n]*\.\s*post\s*\(|\.\s*post\s*\(\s*name\s*:")

LOCK_CALL = re.compile(r"\b(\w+(?:\.\w+)*)\.lock\(\)")
UNLOCK_CALL = re.compile(r"\b(\w+(?:\.\w+)*)\.unlock\(\)")
WITH_LOCK = re.compile(r"\b(\w+(?:\.\w+)*)\.withLock\s*\{")
FUNC_DECL = re.compile(r"^\s*(?:@\w+\s+)*(?:public |private |fileprivate |internal |static |class |final |nonisolated |@MainActor )*func\s+(\w+)")


def strip_comments(text: str) -> str:
    """Comments out, string literals kept, line numbers preserved.

    This repo documents its rules by NAMING the symbols they govern — the
    fixed files above each carry a comment saying "not
    `UserDefaults.standard.set`" — so a check reading raw source fires on the
    prose explaining it. `sharelink-style-audit.py`'s own note, paid again
    here on the first run.
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


def depths(lines):
    """Brace depth BEFORE each line, and after it."""
    before, depth = [], 0
    for line in lines:
        before.append(depth)
        depth += line.count("{") - line.count("}")
    return before


def critical_regions(lines):
    """Every (start, end, lock name) span where a lock is held.

    A span opened by `x.lock()` runs to its matching `x.unlock()` at the same
    brace depth, or — the `defer { unlock }` spelling, which is the majority
    here — to the end of the enclosing scope. An unlock inside a `defer` does
    NOT close the span: that is precisely the form that keeps the lock held to
    the end of the function, and reading it as the end would clear every
    finding in this repo's own stores. A `withLock { }` span is the closure's
    own braces.
    """
    before = depths(lines)
    after = [before[i] + lines[i].count("{") - lines[i].count("}") for i in range(len(lines))]
    spans = []
    for i, line in enumerate(lines):
        for match in WITH_LOCK.finditer(line):
            depth = before[i]
            end = len(lines) - 1
            for j in range(i + 1, len(lines)):
                if after[j] <= depth:
                    end = j
                    break
            spans.append((i, end, match.group(1)))
        for match in LOCK_CALL.finditer(line):
            name = match.group(1)
            depth = before[i]
            end = len(lines) - 1
            for j in range(i + 1, len(lines)):
                if after[j] < depth:
                    end = j - 1
                    break
                if "defer" in lines[j]:
                    continue
                unlocked = [m.group(1) for m in UNLOCK_CALL.finditer(lines[j])]
                if name in unlocked and before[j] == depth:
                    end = j
                    break
            spans.append((i, end, name))
    return spans


def calling_out_functions(lines, receivers=frozenset()):
    """Functions in THIS file whose own body makes the call-out, by name.

    Check 2's whole point: `BridgeHealth.record` held the lock and called
    `save`, so the offending write was never on a locked line.
    """
    before = depths(lines)
    after = [before[i] + lines[i].count("{") - lines[i].count("}") for i in range(len(lines))]
    names = {}
    for i, line in enumerate(lines):
        match = FUNC_DECL.match(line)
        if not match:
            continue
        depth = before[i]
        end = len(lines) - 1
        for j in range(i + 1, len(lines)):
            if after[j] <= depth:
                end = j
                break
        body = lines[i + 1 : end + 1]
        for row in body:
            if writes_defaults(row, receivers):
                names[match.group(1)] = (i + 1, "writes UserDefaults")
                break
            if NOTIFY_POST.search(row):
                names[match.group(1)] = (i + 1, "posts a notification")
                break
    return names


def defaults_receivers(lines):
    """Every name in this file that holds a `UserDefaults`.

    A binding (`let d = UserDefaults.standard`, `let group =
    UserDefaults(suiteName:)`) or a declared type (a parameter or property
    `defaults: UserDefaults`). Derived rather than listed, so a store spelling
    it `prefs` is covered without this file having heard of `prefs`.
    """
    names = set()
    for line in lines:
        for match in BINDING.finditer(line):
            names.add(match.group(1))
        for match in TYPED.finditer(line):
            names.add(match.group(1))
    return names


def writes_defaults(line: str, receivers=frozenset()) -> bool:
    if DEFAULTS_WRITE.search(line):
        return True
    for name in receivers:
        if re.search(r"(?<![\w.])" + re.escape(name) + r"\s*(?:\?|!)?\s*\.\s*(?:"
                     + WRITE_VERBS + r")\s*\(", line):
            return True
    return False


def audit(root: Path):
    findings, census, resolved = [], [], []
    for directory in SOURCE_DIRS:
        base = root / directory
        if not base.exists():
            continue
        for path in sorted(base.rglob("*.swift")):
            rel = path.relative_to(root)
            lines = strip_comments(path.read_text()).splitlines()
            spans = critical_regions(lines)
            if not spans:
                continue
            receivers = defaults_receivers(lines)
            helpers = calling_out_functions(lines, receivers)
            for helper, (decl, what) in helpers.items():
                resolved.append((rel, decl, helper, what))
            for start, end, name in spans:
                for i in range(start, min(end + 1, len(lines))):
                    line = lines[i]
                    if writes_defaults(line, receivers):
                        findings.append((rel, i + 1, f"a UserDefaults write under `{name}`"))
                    elif NOTIFY_POST.search(line):
                        findings.append((rel, i + 1, f"a NotificationCenter post under `{name}`"))
                    else:
                        for helper, (decl, what) in helpers.items():
                            if re.search(r"(?<![\w.])" + re.escape(helper) + r"\s*\(", line) \
                               and not FUNC_DECL.match(line):
                                findings.append(
                                    (rel, i + 1,
                                     f"`{helper}()` {what} (line {decl}) and is "
                                     f"called under `{name}`"))
                                break
                census.append((rel, start + 1, end + 1, name))
    # One finding per line, whichever span reported it first.
    seen, unique = set(), []
    for rel, lineno, why in findings:
        if (rel, lineno) in seen:
            continue
        seen.add((rel, lineno))
        unique.append((rel, lineno, why))
    return unique, census, resolved


FIXTURE = '''import Foundation

enum Store {
    private static let key = "store.v1"
    private static let lock = NSLock()
    private static var cache: [String: Int]?

    static func record(_ name: String) {
        lock.lock(); defer { lock.unlock() }
        var book = loaded()
        book[name, default: 0] += 1
        save(book)
    }

    private static func loaded() -> [String: Int] {
        if let cache { return cache }
        let decoded = (UserDefaults.standard.dictionary(forKey: key) as? [String: Int]) ?? [:]
        cache = decoded
        return decoded
    }

    private static func save(_ book: [String: Int]) {
        cache = book
        DefaultsWrite.set(book, forKey: key)
    }

    static func count(_ name: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return loaded()[name] ?? 0
    }
}

final class Ledger {
    private let lock = NSLock()
    private var entries: [String: Int] = [:]

    func note(_ host: String) {
        lock.lock()
        entries[host, default: 0] += 1
        lock.unlock()
        flush()
    }

    private func flush() {
        lock.lock()
        defer { lock.unlock() }
        DefaultsWrite.set(Data(), forKey: "ledger.v1")
    }
}
'''


def self_test() -> int:
    failures = []
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        src = root / "Casberi/Casberi/Model"
        src.mkdir(parents=True)
        store = src / "Store.swift"
        store.write_text(FIXTURE)
        kept = FIXTURE

        def flagged(needle: str) -> bool:
            found, _, _ = audit(root)
            return any(needle in why for _, _, why in found)

        # CLEAN: the fixture is the shipped shape — a memoised, lock-guarded
        # store whose persistence goes through `DefaultsWrite`.
        found, census, _ = audit(root)
        if found:
            failures.append(f"the clean fixture was flagged: {found}")
        if len(census) != 4:
            failures.append(f"expected 4 critical sections, saw {len(census)}")

        # MUTATION 1: the write moved back inline, under the lock. This is
        # `AppMetrics`' pre-fix shape.
        store.write_text(kept.replace(
            '        DefaultsWrite.set(Data(), forKey: "ledger.v1")',
            '        UserDefaults.standard.set(Data(), forKey: "ledger.v1")'))
        if not flagged("UserDefaults write"):
            failures.append("an inline defaults write under a lock was not caught")
        store.write_text(kept)

        # MUTATION 2: the write moved into the helper the locked function
        # calls — build 570's actual shape, and the one a line-local check
        # cannot see.
        store.write_text(kept.replace(
            "        DefaultsWrite.set(book, forKey: key)",
            "        UserDefaults.standard.set(book, forKey: key)"))
        if not flagged("`save()` writes UserDefaults"):
            failures.append("a defaults write one call deep was not caught")
        store.write_text(kept)

        # MUTATION 3: a `withLock` span counts too.
        store.write_text(kept.replace(
            """        lock.lock()
        entries[host, default: 0] += 1
        lock.unlock()""",
            """        lock.withLock {
            entries[host, default: 0] += 1
            UserDefaults.standard.set(1, forKey: "n")
        }"""))
        if not flagged("UserDefaults write"):
            failures.append("a defaults write inside withLock was not caught")
        store.write_text(kept)

        # MUTATION 4: a notification post under a lock — the general form of
        # what a defaults write does behind your back.
        store.write_text(kept.replace(
            "        book[name, default: 0] += 1",
            "        book[name, default: 0] += 1\n"
            "        NotificationCenter.default.post(name: .init(\"x\"), object: nil)"))
        if not flagged("NotificationCenter post"):
            failures.append("a notification post under a lock was not caught")
        store.write_text(kept)

        # MUTATION 4b: …and one call deep, the same way a write is.
        store.write_text(kept.replace(
            "        DefaultsWrite.set(book, forKey: key)",
            "        NotificationCenter.default.post(name: .init(\"x\"), object: nil)"))
        if not flagged("`save()` posts a notification"):
            failures.append("a notification post one call deep was not caught")
        store.write_text(kept)

        # MUTATION 4c: a NAMED receiver — `let d = UserDefaults.standard`,
        # which `AgentSpend` really spells that way. The receiver is derived
        # from the file, never guessed, so a bare `.set(` on a dictionary is
        # still not a finding (mutation 7).
        store.write_text(kept.replace(
            "        DefaultsWrite.set(book, forKey: key)",
            "        let prefs = UserDefaults.standard\n"
            "        prefs.set(book, forKey: key)"))
        if not flagged("`save()` writes UserDefaults"):
            failures.append("a write through a named UserDefaults receiver was not caught")
        store.write_text(kept)

        # MUTATION 7: `.set(` on something that is NOT a UserDefaults stays
        # clean — the check reads receivers, not verbs.
        store.write_text(kept.replace(
            "        book[name, default: 0] += 1",
            "        book[name, default: 0] += 1\n        seen.set(name)"))
        found7, _, _ = audit(root)
        if found7:
            failures.append(f"a `.set(` on a non-defaults receiver was flagged: {found7}")
        store.write_text(kept)

        # MUTATION 5: the same write OUTSIDE any lock is not a finding — the
        # rule is about the lock, and a check that failed on every defaults
        # write in the tree would be turned off inside a week.
        store.write_text(kept.replace(
            """    static func count(_ name: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return loaded()[name] ?? 0
    }""",
            """    static func count(_ name: String) -> Int {
        return 0
    }

    static func forget() {
        UserDefaults.standard.removeObject(forKey: key)
    }"""))
        found5, _, _ = audit(root)
        if found5:
            failures.append(f"a write outside every lock was flagged: {found5}")
        store.write_text(kept)

        # MUTATION 6: a defaults READ under the lock stays clean — `loaded()`
        # is called under the lock on purpose and posts nothing.
        store.write_text(kept.replace(
            "        var book = loaded()",
            "        var book = loaded()\n        _ = UserDefaults.standard.bool(forKey: \"flag\")"))
        found6, _, _ = audit(root)
        if found6:
            failures.append(f"a defaults READ under a lock was flagged: {found6}")
        store.write_text(kept)

        if failures:
            for failure in failures:
                print(f"self-test FAILED: {failure}", file=sys.stderr)
            return 1
        print("defaults-lock audit self-test: ok (9 mutations)")
        return 0


def main() -> int:
    args = sys.argv[1:]
    if "--self-test" in args:
        return self_test()

    findings, census, resolved = audit(ROOT)
    if "--census" in args:
        for rel, start, end, name in census:
            print(f"{rel}:{start}-{end}: held by `{name}`")
        print()
        for rel, decl, helper, what in resolved:
            print(f"{rel}:{decl}: `{helper}()` {what} — resolved through call sites")
    if not findings:
        print(f"defaults-lock audit: ok ({len(census)} critical sections read)")
        return 0
    print("A lock is held across a synchronous call-out to observers:\n")
    for rel, lineno, why in findings:
        print(f"  {rel}:{lineno}: {why}")
    print("\nA `UserDefaults` write posts its change notification synchronously, and")
    print("SwiftUI's observer takes the update lock a view body already holds while")
    print("waiting for this one — the deadlock that killed build 570 (prd §721).")
    print("Persist through `DefaultsWrite` instead.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
