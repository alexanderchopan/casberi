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

Eight checks, static, on a COMMENT-STRIPPED copy — this file and all three
sources document the rule by naming the very symbols that enforce it, so a guard
reading raw source is satisfied by the prose explaining it (the Obsidian/Cursor
lesson, and the one `privacy-cover-audit.py` earned first).

  A. The app delegate does NOT stamp the fact. Build 537 did, from
     `applicationState` inside `didFinishLaunchingWithOptions`, on the premise
     that the value separates a background launch from a foreground one. It does
     not: `applicationState` is derived from the app's SCENES, none of which has
     connected at that callback, so it reads `.background` for EVERY launch —
     measured on every simulator launch and every line of build 537's Mac logs.
     The gate then never opened on Mac, where neither of the two mount doors of
     the day posts for a launch, and the app shipped a blank window.
  B. The fact is asked of the SCENE and MEMOISED. `connectedScenes` +
     `activationState` is the per-scene truth (`.background` for a refresh
     launch, `.foregroundInactive` for a watched one); memoising is what the
     stored flag used to buy — re-derived later it would say "not background"
     the instant the app wakes, which is exactly when the shell must still be
     withheld.
  C. `RootShell`'s mount flag starts from that fact, negated.
  D. `shellBase` is the gate: the shell's content is behind `if shellMounted`.
  E. Nothing ever sets it back to false. Unmounting on background is §614's root
     invalidation wearing a different name — the whole-tree update inside the
     snapshot transaction that made the privacy cover a `UIWindow`.
  F. ALL FOUR mount doors survive: the scene-phase observer,
     `willEnterForegroundNotification`, `didBecomeActiveNotification` (the only
     activation signal a Catalyst LAUNCH posts) and the direct read in `.task`
     (which waits on no signal at all, so it cannot miss one). Two doors were
     one bug away from an app that opens to a blank page, and build 537 is that
     bug: on Mac neither of them fired.
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
# MEMOISED: a backing `Bool?` that the accessor writes exactly once. This is
# what the stored flag used to buy — one answer for the life of the process —
# now that the answer cannot be known until a scene exists.
MEMO_STORE = r"static\s+var\s+stamped\s*:\s*Bool\?"
MEMO_WRITE = r"\bstamped\s*=\s*answer\b"
# The per-scene truth, and the two halves must BOTH be named: `connectedScenes`
# alone could be counted, `activationState` alone could be read off something
# else.
READS_SCENE = (r"connectedScenes", r"activationState")
# The false premise itself. The fact file may not derive the answer from the
# APPLICATION's state at all — that is the whole of build 537's defect, and a
# regression would otherwise look exactly like the code that shipped it.
APP_STATE_SOURCE = r"applicationState"
FLAG_INIT = r"@State\s+.*\bshellMounted\s*=\s*!\s*BackgroundLaunch\.isBackgroundLaunch"
GATE = r"if\s+shellMounted\b"
UNMOUNT = r"\bshellMounted\s*=\s*false\b"
MOUNT = r"\bshellMounted\s*=\s*true\b"
PHASE_DOOR = r"phase\s*!=\s*\.background"
FOREGROUND_DOOR = r"willEnterForegroundNotification"
# Door three is the Mac's, and the pattern demands the MOUNT be above the
# platform guard — `shellMounted = true` on the notification's own line block
# before `isMacCatalystApp` appears. Checked as an ordering, because a mount
# below that guard is a mount iOS never takes and Mac takes only by luck.
# A TEMPERED match: the run between the notification and the mount may not
# contain `isMacCatalystApp`. Spelling it as "…{0,400}?…isMacCatalystApp"
# instead passed the very fixture it was written for — the guard moved above
# the mount, and the trailing `isMacCatalystApp` was found in the NEXT door.
MAC_DOOR = (r"didBecomeActiveNotification"
            r"(?:(?!isMacCatalystApp)[\s\S]){0,400}?\bshellMounted\s*=\s*true\b")
# Door four waits on nothing: it reads the live application state once the view
# is attached. This is the only door whose correctness does not depend on a
# notification being posted, which is why every platform takes it.
DIRECT_DOOR = (r"applicationState\s*!=\s*\.background\s*\{\s*"
               r"shellMounted\s*=\s*true")
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

    # --- A. the app delegate does NOT stamp the fact -------------------------
    if re.search(STAMP, app_s):
        findings.append(
            "the app delegate stamps `BackgroundLaunch.record(...)` again — "
            "that is build 537's defect exactly: no scene has connected at "
            "`didFinishLaunchingWithOptions`, so `applicationState` reads "
            "`.background` for EVERY launch there and the gate closes on a "
            "launch someone is watching"
        )
    launch_body, err = body_of(app_s.split("\n"), DID_FINISH)
    if err:
        findings.append(err)
    elif launch_body is not None and re.search(APP_STATE_SOURCE, launch_body):
        findings.append(
            "`didFinishLaunchingWithOptions` reads `applicationState` — it "
            "cannot answer about the launch there, and reading it is how the "
            "Mac shipped a blank window"
        )

    # --- B. the fact is asked of the SCENE, and memoised ---------------------
    if re.search(APP_STATE_SOURCE, fact_s):
        findings.append(
            "`BackgroundLaunch` reads `applicationState` — the answer must "
            "come from the SCENE (`connectedScenes` / `activationState`); the "
            "application's own state is derived from those scenes and reads "
            "`.background` before any of them connects"
        )
    for pattern in READS_SCENE:
        if not re.search(pattern, fact_s):
            findings.append(
                f"`BackgroundLaunch` never names `{pattern}` — it cannot know "
                "what it claims to know about the scene it gates"
            )
    if not re.search(MEMO_STORE, fact_s) or not re.search(MEMO_WRITE, fact_s):
        findings.append(
            "`BackgroundLaunch` does not memoise its answer into a `Bool?` — "
            "re-derived on a later read it reports 'not background' the "
            "instant the app wakes, which is precisely when the shell must "
            "still be withheld"
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
        if not re.search(MAC_DOOR, window):
            findings.append(
                "the `didBecomeActiveNotification` mount door is gone, or its "
                "mount sits below the `isMacCatalystApp` guard — it is the "
                "ONLY activation signal a Catalyst launch posts, and without "
                "it the Mac opens to a blank window (build 537)"
            )
        if not re.search(DIRECT_DOOR, window):
            findings.append(
                "the direct-read mount door in `.task` is gone — it is the one "
                "door that waits on no notification, so it is the only one "
                "that cannot be lost by a platform that does not post the "
                "signal the other three listen for"
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
        application.shortcutItems = []
        return true
    }
}
"""

# BUILD 537 ITSELF. The stamp is back in `didFinishLaunchingWithOptions`, where
# it reads `.background` for every launch there is — the shape that shipped, and
# the shape a future pass is most likely to re-propose, because it reads like
# the earliest and therefore the most careful place to ask.
APP_537_STAMP = """
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundLaunch.record(application)
        application.shortcutItems = []
        return true
    }
}
"""

# The stamp gone but the false premise left behind: the delegate still decides
# the launch from the APPLICATION's state, under some other name.
APP_READS_APP_STATE = """
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        LaunchFacts.wasBackground = application.applicationState == .background
        application.shortcutItems = []
        return true
    }
}
"""

FACT_CLEAN = """
enum BackgroundLaunch {
    nonisolated(unsafe) private static var stamped: Bool?

    static var isBackgroundLaunch: Bool {
        if let stamped { return stamped }
        let answer = resolve()
        stamped = answer
        return answer
    }

    private static func resolve() -> Bool {
        let scenes = UIApplication.shared.connectedScenes
        guard !scenes.isEmpty else { return false }
        return !scenes.contains { scene in
            scene.activationState == .foregroundActive
                || scene.activationState == .foregroundInactive
        }
    }
}
"""

# BUILD 537's fact: the application's state, stored once, in the app delegate.
# `applicationState` is derived FROM the scenes, so before one connects it is
# `.background` on every launch — this fixture is the defect verbatim.
FACT_537 = """
enum BackgroundLaunch {
    nonisolated(unsafe) private(set) static var isBackgroundLaunch = false
    static func record(_ application: UIApplication) {
        isBackgroundLaunch = application.applicationState == .background
    }
}
"""

# The scene asked, but the answer re-derived on every read — so it reports
# "not background" the instant the app wakes, which is when the shell must
# still be withheld.
FACT_NOT_MEMOISED = """
enum BackgroundLaunch {
    static var isBackgroundLaunch: Bool {
        let scenes = UIApplication.shared.connectedScenes
        return !scenes.contains { $0.activationState == .foregroundActive }
    }
}
"""

# Memoised, but the question asked of nothing in particular — a flag somebody
# else sets. It names neither `connectedScenes` nor `activationState`, so it
# cannot know what it claims to know.
FACT_NO_SCENE = """
enum BackgroundLaunch {
    nonisolated(unsafe) private static var stamped: Bool?
    static var isBackgroundLaunch: Bool {
        if let stamped { return stamped }
        let answer = ProcessInfo.processInfo.environment["BG"] != nil
        stamped = answer
        return answer
    }
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
            for: UIApplication.didBecomeActiveNotification)) { _ in
            shellMounted = true
            guard ProcessInfo.processInfo.isMacCatalystApp else { return }
            handleActivation()
        }
        .task {
            if UIApplication.shared.applicationState != .background { shellMounted = true }
            guard ProcessInfo.processInfo.isMacCatalystApp,
                  UIApplication.shared.applicationState == .active else { return }
            handleActivation()
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

# BUILD 537's SHELL: the two notification doors only. On Mac neither posts for
# a launch, so this is the blank window verbatim.
SHELL_537_DOORS = SHELL_CLEAN.replace(
    """            shellMounted = true
            guard ProcessInfo.processInfo.isMacCatalystApp else { return }
""",
    "            guard ProcessInfo.processInfo.isMacCatalystApp else { return }\n",
).replace(
    "            if UIApplication.shared.applicationState != .background { shellMounted = true }\n",
    "",
)

# The Mac door's mount pushed BELOW the platform guard — present, greppable,
# and reached on exactly the platform that already had another door.
SHELL_MAC_MOUNT_BELOW_GUARD = SHELL_CLEAN.replace(
    """            shellMounted = true
            guard ProcessInfo.processInfo.isMacCatalystApp else { return }
            handleActivation()
""",
    """            guard ProcessInfo.processInfo.isMacCatalystApp else { return }
            shellMounted = true
            handleActivation()
""",
)

SHELL_NO_DIRECT_DOOR = SHELL_CLEAN.replace(
    "            if UIApplication.shared.applicationState != .background { shellMounted = true }\n",
    "",
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
        ("build 537: the app delegate stamps the launch again",
         APP_537_STAMP, FACT_CLEAN, SHELL_CLEAN, True),
        ("build 537: the fact read from applicationState",
         APP_CLEAN, FACT_537, SHELL_CLEAN, True),
        ("build 537: only the two notification doors",
         APP_CLEAN, FACT_CLEAN, SHELL_537_DOORS, True),
        ("the delegate reads applicationState under another name",
         APP_READS_APP_STATE, FACT_CLEAN, SHELL_CLEAN, True),
        ("the fact re-derived on every read", APP_CLEAN, FACT_NOT_MEMOISED, SHELL_CLEAN, True),
        ("the fact never asks the scene", APP_CLEAN, FACT_NO_SCENE, SHELL_CLEAN, True),
        ("the Mac door mounts below its platform guard",
         APP_CLEAN, FACT_CLEAN, SHELL_MAC_MOUNT_BELOW_GUARD, True),
        ("the direct-read door deleted", APP_CLEAN, FACT_CLEAN, SHELL_NO_DIRECT_DOOR, True),
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
