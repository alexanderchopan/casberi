#!/usr/bin/env python3
"""Casberi background-launch audit (prd §642, 2026-09-07) — the shell is not
BUILT for a scene connected in the background, and every door that could hide
that fact is checked.

    Casberi/Casberi/CasberiApp.swift
    Casberi/Casberi/Shell/BackgroundLaunch.swift
    Casberi/Casberi/Shell/RootShell.swift

**What this exists for.** Build 534 was killed by the scene-update watchdog —
`0x8BADF00D`, "exhausted real (wall clock) time allowance of 10.00 seconds",
`ProcessVisibility: Background`, `procRole: Background`, parent `launchd` — with
the main thread inside ONE SwiftUI graph update: `GraphHost.flushTransactions`
→ `DynamicBody.updateValue` → `EnvironmentBox.update` →
`_swift_getGenericMetadata`. Not a Casberi frame on the stack. iOS had launched
the app in the background for its `BGAppRefreshTask`, connected the window scene
anyway (a scene-based app always gets one), and SwiftUI set about building the
whole shell where no frame would ever be shown.

**The arithmetic, from the app's own numbers.** prd §628 measured first paint at
**1.3s** on a phone. The report's own line reads `Elapsed application CPU time
(seconds): 9.976, 16% CPU`: a backgrounded app is throttled, so that build is
about **eight seconds of wall clock** before the store, the first query or one
row is counted. Building this shell for a background-connected scene was never a
race the app could win — it was a coin flip against a ten-second wall, taken on
every background refresh iOS granted.

**Why mechanical.** This is the THIRD watchdog of this family (§614's builds 511
and 521 were the first two) and every one of them is invisible to everything
else in this repo: the build is clean, every static audit passed on the crashing
binary, the screen sweep photographs a perfectly healthy app, and **no machine
here can background-launch anything** — the simulator will not do it, so the
only door is `-forceBackgroundLaunch YES`, which proves the branch renders and
proves nothing about the watchdog. A rule nothing can exercise has to be held
statically or not at all.

Seven checks, static, on a COMMENT-STRIPPED copy — this file and all three
sources document the rule by naming the very symbols that enforce it, so a guard
reading raw source is satisfied by the prose explaining it (the Obsidian/Cursor
lesson, and the one `privacy-cover-audit.py` earned first).

  A. The launch is STAMPED, in `didFinishLaunchingWithOptions`. That callback is
     the only place `applicationState` answers about the LAUNCH rather than
     about the moment it was asked. No stamp ⇒ the flag is false forever ⇒ the
     gate is open forever, silently.
  B. `BackgroundLaunch` STORES the answer. A computed property re-reading
     `applicationState` would say "not background" the instant the app wakes,
     which is exactly when the shell must still be withheld.
  C. `RootShell`'s mount flag starts from that fact, negated.
  D. `shellBase` is the gate: the shell's content is behind `if shellMounted`.
  E. Nothing ever sets it back to false. Unmounting on background is §614's root
     invalidation wearing a different name — the whole-tree update inside the
     snapshot transaction that made the privacy cover a `UIWindow`.
  F. BOTH mount doors survive: the scene-phase observer and
     `willEnterForegroundNotification`. One door is one bug away from a shell
     that never builds — an app that opens to a blank page.
  G. `onOpenURL` and the Spotlight continuation stay OUTSIDE the gated body. A
     deep link arriving at a background-launched process that is being opened
     would be dropped by a handler that is not in the tree, and the loss is
     silent: the app opens, on the wrong screen, exactly as if the link were
     mistyped.

Deliberately NOT checked: whether the closed branch draws the right thing (it
paints `DSPageBackground`, which is a look, not a rule), whether the background
task should do less (it should, and that is its own entry), and whether the
mount is fast enough once it happens (it is an ordinary cold-launch build, which
`LAUNCH_CYCLES` already gates).

Pure, local, deterministic. `--self-test` first, then the tree. Exit non-zero on
failure.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

APP = Path("Casberi/Casberi/CasberiApp.swift")
FACT = Path("Casberi/Casberi/Shell/BackgroundLaunch.swift")
SHELL = Path("Casberi/Casberi/Shell/RootShell.swift")

STAMP = r"BackgroundLaunch\.record\s*\("
DID_FINISH = r"didFinishLaunchingWithOptions"
# STORED, and the `=` is the whole point: a computed `static var … : Bool {`
# matches any looser spelling of this and is exactly what check B rejects.
STORED = r"static\s+var\s+isBackgroundLaunch\s*(?::[^={]*)?=\s*\S"
READS_STATE = r"applicationState\s*==\s*\.background"
FLAG_INIT = r"@State\s+.*\bshellMounted\s*=\s*!\s*BackgroundLaunch\.isBackgroundLaunch"
GATE = r"if\s+shellMounted\b"
UNMOUNT = r"\bshellMounted\s*=\s*false\b"
MOUNT = r"\bshellMounted\s*=\s*true\b"
PHASE_DOOR = r"phase\s*!=\s*\.background"
FOREGROUND_DOOR = r"willEnterForegroundNotification"
GATED_BODY = r"private\s+var\s+shellContent\s*:"
# `\b`, not `\(`: both are written with a TRAILING CLOSURE in this app, so a
# pattern demanding a parenthesis matches neither and check G would pass over
# a link door sitting inside the gate — a guard that certifies nothing.
ALWAYS_LIVE = (r"\.onOpenURL\b", r"\.onContinueUserActivity\b")


def strip_comments(text: str) -> str:
    """Blank `//` comments and `/* */` blocks, preserving line numbering.

    Lifted whole from `privacy-cover-audit.py`, including the rule that cost
    that file a false accusation: WHICHEVER DELIMITER OPENS FIRST WINS. Testing
    `/*` first blanks the rest of the file on a line comment that merely
    mentions a glob; testing `//` first breaks on a `//` inside a one-line
    `/* … */`. Scanning left to right is the only rule needing no exception.
    """
    out = []
    in_block = False
    for line in text.split("\n"):
        if in_block:
            end = line.find("*/")
            if end == -1:
                out.append("")
                continue
            line = " " * (end + 2) + line[end + 2:]
            in_block = False
        pos = 0
        while True:
            b = line.find("/*", pos)
            s = line.find("//", pos)
            if s != -1 and (b == -1 or s < b):
                line = line[:s]
                break
            if b == -1:
                break
            end = line.find("*/", b + 2)
            if end == -1:
                line = line[:b]
                in_block = True
                break
            line = line[:b] + " " * (end + 2 - b) + line[end + 2:]
            pos = end + 2
        out.append(line)
    return "\n".join(out)


def body_of(lines: list[str], declaration: str) -> tuple[str | None, str | None]:
    """The braced body that follows the first line matching `declaration`.

    Returns `(body, error)`. Brace-counted from the declaration's own opening
    brace over comment-stripped source. An unbalanced count returns an ERROR
    rather than a guess — a check that silently narrows its window is a check
    that passes for the wrong reason, which is the failure this whole file is
    about.
    """
    rx = re.compile(declaration)
    start = next((i for i, line in enumerate(lines) if rx.search(line)), None)
    if start is None:
        return None, None
    depth = 0
    seen = False
    body: list[str] = []
    for line in lines[start:]:
        body.append(line)
        for ch in line:
            if ch == "{":
                depth += 1
                seen = True
            elif ch == "}":
                depth -= 1
        if seen and depth <= 0:
            return "\n".join(body), None
    return None, f"could not delimit the body of `{declaration}` — braces never balance"


def audit(app: str, fact: str, shell: str) -> list[str]:
    """Return a list of findings; empty means clean."""
    app_s = strip_comments(app)
    fact_s = strip_comments(fact)
    shell_s = strip_comments(shell)
    shell_lines = shell_s.split("\n")
    findings: list[str] = []

    # --- A. the launch is stamped, in the one callback that can answer -------
    stamped = re.search(STAMP, app_s)
    if not stamped:
        findings.append(
            "nothing calls `BackgroundLaunch.record(…)` — the flag stays false "
            "for every launch, so the gate is open on a background launch and "
            "the shell builds under the watchdog again, silently"
        )
    else:
        launch_body, err = body_of(app_s.split("\n"), DID_FINISH)
        if err:
            findings.append(err)
        elif launch_body is None or not re.search(STAMP, launch_body):
            findings.append(
                "`BackgroundLaunch.record(…)` is not inside "
                "`didFinishLaunchingWithOptions` — `applicationState` answers "
                "about the LAUNCH only there; anywhere later it answers about "
                "the moment it was asked"
            )

    # --- B. the answer is STORED, not recomputed -----------------------------
    if not re.search(STORED, fact_s):
        findings.append(
            "`BackgroundLaunch.isBackgroundLaunch` is not a stored `static var` "
            "— a computed one re-reads `applicationState` and reports 'not "
            "background' the instant the app wakes, which is precisely when the "
            "shell must still be withheld"
        )
    if not re.search(READS_STATE, fact_s):
        findings.append(
            "`BackgroundLaunch` never compares `applicationState` to "
            "`.background` — it cannot know what it claims to know"
        )

    # --- C. the mount flag starts from that fact -----------------------------
    if not re.search(FLAG_INIT, shell_s):
        findings.append(
            "`shellMounted` is not initialised from "
            "`!BackgroundLaunch.isBackgroundLaunch` — a flag that starts true "
            "gates nothing, and one that starts false blanks every ordinary "
            "launch"
        )

    # --- D. shellBase is the gate -------------------------------------------
    gate_body, err = body_of(shell_lines, r"private\s+var\s+shellBase\s*:")
    if err:
        findings.append(err)
    elif gate_body is None:
        findings.append("`shellBase` not found — there is nothing to gate")
    elif not re.search(GATE, gate_body):
        findings.append(
            "`shellBase` does not branch on `shellMounted` — the shell builds "
            "for a scene connected in the background, which is build 534's "
            "scene-update watchdog"
        )

    # --- E. nothing unmounts -------------------------------------------------
    unmount = [i for i, line in enumerate(shell_lines) if re.search(UNMOUNT, line)]
    if unmount:
        findings.append(
            f"`shellMounted = false` at line {unmount[0] + 1} — tearing the "
            "shell down on background is §614's root invalidation under a new "
            "name: a whole-tree update inside the snapshot transaction, which "
            "is what made the privacy cover a `UIWindow`"
        )

    # --- F. both mount doors -------------------------------------------------
    mounts = [i for i, line in enumerate(shell_lines) if re.search(MOUNT, line)]
    if not mounts:
        findings.append(
            "nothing sets `shellMounted = true` — the shell would never build "
            "after a background launch, so opening the app shows a blank page"
        )
    else:
        window = "\n".join(shell_lines)
        if not re.search(PHASE_DOOR, window):
            findings.append(
                "the scene-phase mount door is gone (no `phase != .background`) "
                "— one door is one bug away from an app that opens to nothing"
            )
        if not re.search(FOREGROUND_DOOR, window):
            findings.append(
                "the `willEnterForegroundNotification` mount door is gone — it "
                "is the one that fires BEFORE the phase moves, i.e. the earliest "
                "signal on the only path that matters"
            )

    # --- G. the always-live doors stay outside the gate ----------------------
    gated, err = body_of(shell_lines, GATED_BODY)
    if err:
        findings.append(err)
    elif gated is None:
        findings.append(
            "`shellContent` not found — the gated body has been renamed or "
            "folded away, and check G can no longer tell what is behind the gate"
        )
    else:
        for pattern in ALWAYS_LIVE:
            if re.search(pattern, gated):
                findings.append(
                    f"`{pattern}` sits INSIDE the gated body — a link or a "
                    "Spotlight hand-off arriving at a background-launched "
                    "process is dropped by a handler that is not in the tree, "
                    "and the app simply opens on the wrong screen"
                )

    return findings


# --- fixtures ----------------------------------------------------------------

APP_CLEAN = """
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundLaunch.record(application)
        application.shortcutItems = []
        return true
    }
}
"""

# The stamp moved to a callback that runs later. `applicationState` there
# answers about the moment it was asked, not about the launch.
APP_LATE_STAMP = """
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.shortcutItems = []
        return true
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        BackgroundLaunch.record(UIApplication.shared)
    }
}
"""

APP_NO_STAMP = APP_CLEAN.replace("        BackgroundLaunch.record(application)\n", "")

FACT_CLEAN = """
enum BackgroundLaunch {
    nonisolated(unsafe) private(set) static var isBackgroundLaunch = false
    static func record(_ application: UIApplication) {
        isBackgroundLaunch = application.applicationState == .background
    }
}
"""

FACT_COMPUTED = """
enum BackgroundLaunch {
    static var isBackgroundLaunch: Bool {
        UIApplication.shared.applicationState == .background
    }
    static func record(_ application: UIApplication) {}
}
"""

SHELL_CLEAN = """
struct RootShell: View {
    @Environment(\\.scenePhase) private var scenePhase
    @State private var shellMounted = !BackgroundLaunch.isBackgroundLaunch

    private var shell: some View {
        shellPhaseAware
        .onOpenURL { route($0) }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in }
    }

    private var shellPhaseAware: some View {
        shellBase
        .onChange(of: scenePhase) { _, phase in
            if phase != .background { shellMounted = true }
            if phase == .active { handleActivation() } else { handleDeactivation(phase: phase) }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification)) { _ in
            shellMounted = true
        }
    }

    @ViewBuilder
    private var shellBase: some View {
        if shellMounted {
            shellContent
        } else {
            DSPageBackground()
        }
    }

    private var shellContent: some View {
        ZStack(alignment: .bottom) {
            MainSurface()
        }
    }
}
"""

SHELL_NO_GATE = SHELL_CLEAN.replace(
    """        if shellMounted {
            shellContent
        } else {
            DSPageBackground()
        }
""",
    "        shellContent\n",
)

SHELL_FLAG_ALWAYS_TRUE = SHELL_CLEAN.replace(
    "@State private var shellMounted = !BackgroundLaunch.isBackgroundLaunch",
    "@State private var shellMounted = true",
)

SHELL_UNMOUNTS = SHELL_CLEAN.replace(
    "            if phase == .active { handleActivation() }",
    "            if phase == .background { shellMounted = false }\n"
    "            if phase == .active { handleActivation() }",
)

SHELL_ONE_DOOR = SHELL_CLEAN.replace(
    """        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification)) { _ in
            shellMounted = true
        }
""",
    "",
)

SHELL_NO_PHASE_DOOR = SHELL_CLEAN.replace(
    "            if phase != .background { shellMounted = true }\n", ""
)

# The link door dragged inside the gate — the silent one. The app still opens;
# it just opens on the wrong screen, indistinguishable from a mistyped link.
SHELL_LINK_INSIDE = SHELL_CLEAN.replace(
    "        .onOpenURL { route($0) }\n", ""
).replace(
    """        ZStack(alignment: .bottom) {
            MainSurface()
        }
""",
    """        ZStack(alignment: .bottom) {
            MainSurface()
        }
        .onOpenURL { route($0) }
""",
)

# The gate present only as PROSE — the exact shape a raw-source grep scores as
# compliant, and the reason every read here is comment-stripped.
SHELL_COMMENT_ONLY = SHELL_CLEAN.replace(
    """        if shellMounted {
            shellContent
        } else {
            DSPageBackground()
        }
""",
    "        // the shell renders only if shellMounted, per prd §642\n"
    "        shellContent\n",
)

# A `//` comment mentioning a glob, above everything. Regression fixture for
# the comment stripper's own bug (2026-09-01), carried across with the code.
SHELL_GLOB_COMMENT = (
    "// see scripts/output/*/perf.txt for the launch numbers\n" + SHELL_CLEAN
)


def self_test() -> tuple[int, int]:
    cases = [
        ("clean tree", APP_CLEAN, FACT_CLEAN, SHELL_CLEAN, False),
        ("no stamp at all", APP_NO_STAMP, FACT_CLEAN, SHELL_CLEAN, True),
        ("stamp moved out of didFinishLaunching",
         APP_LATE_STAMP, FACT_CLEAN, SHELL_CLEAN, True),
        ("the fact recomputed instead of stored",
         APP_CLEAN, FACT_COMPUTED, SHELL_CLEAN, True),
        ("the gate removed", APP_CLEAN, FACT_CLEAN, SHELL_NO_GATE, True),
        ("the gate present only in a comment",
         APP_CLEAN, FACT_CLEAN, SHELL_COMMENT_ONLY, True),
        ("the flag hard-wired true", APP_CLEAN, FACT_CLEAN, SHELL_FLAG_ALWAYS_TRUE, True),
        ("the shell unmounts on background", APP_CLEAN, FACT_CLEAN, SHELL_UNMOUNTS, True),
        ("the foreground door deleted", APP_CLEAN, FACT_CLEAN, SHELL_ONE_DOOR, True),
        ("the scene-phase door deleted", APP_CLEAN, FACT_CLEAN, SHELL_NO_PHASE_DOOR, True),
        ("onOpenURL dragged inside the gate", APP_CLEAN, FACT_CLEAN, SHELL_LINK_INSIDE, True),
        ("a glob in a line comment does not blank the file",
         APP_CLEAN, FACT_CLEAN, SHELL_GLOB_COMMENT, False),
    ]
    bad = 0
    for name, app, fact, shell, should_fail in cases:
        findings = audit(app, fact, shell)
        got = bool(findings)
        if got != should_fail:
            want = "a finding" if should_fail else "no findings"
            print(f"  ✗ self-test: {name} — expected {want}, got {findings or 'none'}")
            bad += 1
        else:
            print(f"  ✓ self-test: {name}")
    return bad, len(cases)


def main() -> int:
    if "--self-test" in sys.argv:
        bad, total = self_test()
        if bad:
            print(f"✗ background-launch audit self-test: {bad} case(s) wrong")
            return 1
        print(f"✓ background-launch audit self-test: {total}/{total}")
        return 0

    for path in (APP, FACT, SHELL):
        if not path.is_file():
            print(f"✗ {path} not found (run from the repo root)")
            return 1

    findings = audit(APP.read_text(encoding="utf-8"),
                     FACT.read_text(encoding="utf-8"),
                     SHELL.read_text(encoding="utf-8"))
    if findings:
        print("✗ background-launch audit")
        for f in findings:
            print(f"  • {f}")
        return 1
    print("✓ background-launch audit: the shell is not built for a background scene")
    return 0


if __name__ == "__main__":
    sys.exit(main())
