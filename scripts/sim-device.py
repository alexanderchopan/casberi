#!/usr/bin/env python3
"""ONE SIMULATOR, BY UDID — the destination this repo's passes build against.

**It cost a ship 30 seconds in on 2026-09-21.** `verify.sh` built with
`-destination "platform=iOS Simulator,name=iPhone 17 Pro"` and no OS, so
xcodebuild resolved against the LATEST runtime, matched by DEVICE TYPE, found
two — `Casberi Shots 27` and `Casberi AI Seat`, both iPhone 17 Pro device types
on iOS 27.0, neither NAMED that — and refused:

    The requested device could not be found because multiple devices matched
    the request. ( SimDevice: Casberi Shots 27 ... SimDevice: Casberi AI Seat )

The plainly-named `iPhone 17 Pro` existed only on iOS 26.5, which xcodebuild
never looked at. The workaround that unblocked the ship was to CREATE a
`iPhone 17 Pro` on 27.0 — additive, and it leaves the pass depending on which
simulators happen to exist on the machine. That is the recorded
`booted`-is-ambiguous-with-two-simulators class (CLAUDE.md: "Pin the udid on
every call"), one layer up: the same lesson, unlearned at the build step.

**So the passes resolve a UDID first and pass `id=<udid>`.** An id is exact:
no device type matching, no runtime guessing, and a sibling simulator someone
else created on any runtime cannot touch it. It also fixes the half nobody had
noticed — `xcrun simctl boot "iPhone 17 Pro"` was itself ambiguous, because two
devices carry that exact name (26.5 and 27.0), and which one simctl picks is
not a promise anywhere.

**THE RUNTIME FOLLOWS LATEST, and that is a choice with a lever.** Pinning to
iOS 26.5 — what CLAUDE.md's "Test device: iOS 26 runtime" line would suggest —
buys determinism the wrong way round: the pass would stop seeing the newest OS
the app actually ships onto, and would hard-fail the day Xcode drops that
runtime, which is a doc edit standing between a machine and a green pass. So
this picks the NEWEST runtime carrying a device of the exact name, prints which
one it chose on every run, and takes `VERIFY_SIM_OS=26.5` when a ship wants the
older one nailed down. Determinism comes from the udid and from saying out loud
which runtime it is, not from freezing the number.

**MATCHING IS BY EXACT NAME, never by device type.** That is the whole fix:
`Casberi Shots 27` is an iPhone 17 Pro and is none of this pass's business.

**THE GUARD.** Two devices with the same exact name on the SAME runtime is a
genuine ambiguity no rule here can break, so it is reported as one — every
candidate, with its udid and runtime, in three lines — rather than as a
40-line xcodebuild destination dump. The same-name-DIFFERENT-runtime case is
not an error (the newest wins) but it is PRINTED, because a stale 26.5 twin is
exactly the thing that makes a later "but it worked yesterday" unreadable.

**IT CREATES THE DEVICE IF IT IS ABSENT**, so a fresh machine and a machine
whose runtime just moved both work with no hand step — the same `simctl create`
that unblocked the ship, run by the pass instead of by a person, on the newest
runtime that offers the device type.

**IT NEVER DELETES ANYTHING.** Concurrent sessions own simulators here.

**NEVER ON CI.** It shells out to `simctl` and will try to CREATE a device, so
it must stay out of the workflows' discovery globs — which are
`scripts/*-audit.{py,sh}` and `scripts/*-selftest.*`, and this file matches
neither. Do not rename it into one. The cost of that is that CI never proves
the chooser: `verify.sh` is the only gate that runs the self-test below, which
is the right trade while CI has no simulators at all.

STATED CEILINGS. It proves the destination is unambiguous, never that the
device BOOTS or that the runtime is installed correctly. It knows nothing about
which device is `booted` — that is the caller's, and every caller now passes a
udid, so `booted` is out of the picture. It reads iOS runtimes only.

`--self-test` runs the chooser over fixtures — including the 2026-09-21 census
verbatim — and is required, per this repo's rule that a check which cannot
demonstrate it catches anything certifies nothing.
"""
import json
import os
import re
import subprocess
import sys

DEFAULT_NAME = "iPhone 17 Pro"
DEFAULT_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
RUNTIME_PREFIX = "com.apple.CoreSimulator.SimRuntime."


class Ambiguous(Exception):
    """Two devices share the exact name on one runtime. Nothing can break it."""


class NotFound(Exception):
    """No device of that exact name on any iOS runtime."""


def runtime_version(identifier):
    """`...SimRuntime.iOS-27-0` → (27, 0). None for anything not iOS."""
    tail = identifier.rsplit(".", 1)[-1]
    m = re.fullmatch(r"iOS-(\d+)(?:-(\d+))?(?:-(\d+))?", tail)
    if not m:
        return None
    return tuple(int(g) for g in m.groups() if g is not None)


def version_text(identifier):
    v = runtime_version(identifier)
    return "iOS " + ".".join(str(n) for n in v) if v else identifier


def normalize_pin(pin):
    """`26.5`, `iOS 26.5`, `iOS-26-5` all mean the same runtime."""
    if pin is None:
        return None
    digits = re.findall(r"\d+", pin)
    return tuple(int(d) for d in digits) if digits else None


def choose(devices, name, pin=None):
    """(udid, runtime identifier) for the one device to build against.

    `devices` is simctl's own `devices` map: runtime identifier → device list.
    """
    candidates = []
    for identifier, entries in devices.items():
        version = runtime_version(identifier)
        if version is None:
            continue
        if pin is not None and version != pin:
            continue
        for entry in entries:
            if entry.get("name") != name:
                continue
            # A device whose runtime is not installed is not a destination.
            if entry.get("isAvailable") is False:
                continue
            candidates.append((version, identifier, entry))

    if not candidates:
        raise NotFound(name)

    newest = max(version for version, _, _ in candidates)
    on_newest = [(i, e) for v, i, e in candidates if v == newest]
    if len(on_newest) > 1:
        raise Ambiguous(
            "\n".join(
                "  %s  %s  (%s)" % (e["udid"], e["name"], version_text(i))
                for i, e in sorted(on_newest, key=lambda p: p[1]["udid"])
            )
        )

    identifier, entry = on_newest[0]
    others = [
        (i, e) for v, i, e in candidates if v != newest
    ]
    return entry["udid"], identifier, others


# ── Live resolution ────────────────────────────────────────────────
def census():
    out = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "-j"],
        capture_output=True, text=True, check=True,
    ).stdout
    return json.loads(out)["devices"]


def newest_runtime_offering(device_type):
    """The newest installed iOS runtime that can host this device type."""
    out = subprocess.run(
        ["xcrun", "simctl", "list", "-j"],
        capture_output=True, text=True, check=True,
    ).stdout
    blob = json.loads(out)
    best = None
    for pair in blob.get("devicetypes", []):
        if pair.get("identifier") != device_type:
            continue
        break
    else:
        return None
    for runtime in blob.get("runtimes", []):
        if not runtime.get("isAvailable"):
            continue
        identifier = runtime.get("identifier", "")
        version = runtime_version(identifier)
        if version is None:
            continue
        supported = runtime.get("supportedDeviceTypes")
        if supported is not None and not any(
            d.get("identifier") == device_type for d in supported
        ):
            continue
        if best is None or version > best[0]:
            best = (version, identifier)
    return best[1] if best else None


def create(name, device_type):
    identifier = newest_runtime_offering(device_type)
    if identifier is None:
        sys.exit(
            "✗ no installed iOS runtime offers %s — install one in Xcode > "
            "Settings > Components" % device_type.rsplit(".", 1)[-1]
        )
    print(
        "  creating %r on %s (no simulator of that name existed)"
        % (name, version_text(identifier)),
        file=sys.stderr,
    )
    subprocess.run(
        ["xcrun", "simctl", "create", name, device_type, identifier],
        capture_output=True, text=True, check=True,
    )
    return identifier


def resolve(name, device_type, pin):
    """Print the udid on stdout; everything human goes to stderr."""
    forced = os.environ.get("VERIFY_SIM_UDID", "").strip()
    if forced:
        devices = census()
        for identifier, entries in devices.items():
            for entry in entries:
                if entry.get("udid", "").lower() == forced.lower():
                    print(
                        "  VERIFY_SIM_UDID → %s on %s"
                        % (entry.get("name"), version_text(identifier)),
                        file=sys.stderr,
                    )
                    return entry["udid"]
        sys.exit("✗ VERIFY_SIM_UDID=%s names no simulator on this machine" % forced)

    for attempt in (1, 2):
        try:
            udid, identifier, others = choose(census(), name, normalize_pin(pin))
        except Ambiguous as exc:
            sys.exit(
                "✗ two simulators match the destination — the pass cannot pick "
                "one for you.\n"
                "  %r exists more than once on the same runtime:\n%s\n"
                "  Rename or delete one (it may be another session's), or pin "
                "this run with VERIFY_SIM_UDID=<udid>." % (name, exc)
            )
        except NotFound:
            if attempt == 2 or pin is not None:
                sys.exit(
                    "✗ no simulator named %r%s. Create one:\n"
                    "  xcrun simctl create %r %s <runtime>"
                    % (name, " on iOS %s" % pin if pin else "", name, device_type)
                )
            create(name, device_type)
            continue

        note = ""
        if others:
            note = " (ignoring the same name on %s)" % ", ".join(
                sorted({version_text(i) for i, _ in others})
            )
        print(
            "  destination: %s on %s%s — id=%s"
            % (name, version_text(identifier), note, udid),
            file=sys.stderr,
        )
        return udid


# ── Self-test ──────────────────────────────────────────────────────
def _dev(name, udid, available=True):
    return {"name": name, "udid": udid, "isAvailable": available}


RT26 = RUNTIME_PREFIX + "iOS-26-5"
RT27 = RUNTIME_PREFIX + "iOS-27-0"
RT_WATCH = RUNTIME_PREFIX + "watchOS-12-0"

# The machine as it stood when the ship broke, names verbatim.
CENSUS_20260921 = {
    RT26: [
        _dev("Casberi Splits", "E9B28403"),
        _dev("Casberi Web Shots", "41415625"),
        _dev("Casberi-perf", "E3B001E2"),
        _dev("deck-iphone", "9471878A"),
        _dev("iPhone 17 Pro", "6129481A"),
        _dev("shot-iphone", "D6A05B15"),
    ],
    RT27: [
        _dev("Casberi AI Seat", "45C96B5C"),
        _dev("Casberi Shots 27", "99C42121"),
        _dev("iPhone 17 Pro", "D4023139"),
    ],
}


def self_test():
    failures = []

    def ok(label, condition):
        if not condition:
            failures.append(label)

    def raises(label, exc_type, fn):
        try:
            fn()
        except exc_type:
            return
        except Exception as e:  # noqa: BLE001
            failures.append("%s (raised %s instead)" % (label, type(e).__name__))
            return
        failures.append("%s (raised nothing)" % label)

    # 1. The newest runtime's exact-name device wins, and the custom-named
    #    iPhone 17 Pro device types on that runtime are invisible. This is the
    #    2026-09-21 failure, resolved.
    udid, identifier, others = choose(CENSUS_20260921, "iPhone 17 Pro")
    ok("1 picks the 27.0 device", udid == "D4023139")
    ok("1 names the runtime", identifier == RT27)
    ok("1 reports the 26.5 twin", [i for i, _ in others] == [RT26])

    # 2. Before the workaround device existed — 26.5 only — the answer is the
    #    26.5 device, NOT a failure. xcodebuild's "latest" is what broke; the
    #    newest runtime CARRYING THE NAME is what works.
    pre = {RT26: CENSUS_20260921[RT26], RT27: [
        _dev("Casberi AI Seat", "45C96B5C"),
        _dev("Casberi Shots 27", "99C42121"),
    ]}
    udid, identifier, others = choose(pre, "iPhone 17 Pro")
    ok("2 falls back to 26.5", (udid, identifier, others) == ("6129481A", RT26, []))

    # 3. Same exact name TWICE on one runtime is the ambiguity nothing can
    #    break — it must raise, not pick.
    twins = {RT27: [_dev("iPhone 17 Pro", "AAA"), _dev("iPhone 17 Pro", "BBB")]}
    raises("3 same name, same runtime", Ambiguous,
           lambda: choose(twins, "iPhone 17 Pro"))

    # 4. The pin overrides latest, and a pin with no device is NotFound rather
    #    than a silent fall back to a runtime the caller ruled out.
    udid, identifier, _ = choose(CENSUS_20260921, "iPhone 17 Pro", (26, 5))
    ok("4 pin picks 26.5", (udid, identifier) == ("6129481A", RT26))
    raises("4 pin with no device", NotFound,
           lambda: choose(CENSUS_20260921, "iPhone 17 Pro", (25, 0)))

    # 5. A name nobody carries is NotFound (the caller creates it).
    raises("5 unknown name", NotFound,
           lambda: choose(CENSUS_20260921, "iPhone 42 Pro"))

    # 6. An unavailable device is not a destination — a runtime that is not
    #    installed still lists its devices.
    gone = {RT27: [_dev("iPhone 17 Pro", "DEAD", available=False)],
            RT26: [_dev("iPhone 17 Pro", "LIVE")]}
    udid, identifier, _ = choose(gone, "iPhone 17 Pro")
    ok("6 skips unavailable", (udid, identifier) == ("LIVE", RT26))

    # 7. Non-iOS runtimes are ignored, including one whose name collides.
    watch = {RT_WATCH: [_dev("iPhone 17 Pro", "WATCH")],
             RT26: [_dev("iPhone 17 Pro", "IOS")]}
    udid, _, _ = choose(watch, "iPhone 17 Pro")
    ok("7 ignores watchOS", udid == "IOS")
    raises("7 watchOS alone is NotFound", NotFound,
           lambda: choose({RT_WATCH: [_dev("iPhone 17 Pro", "WATCH")]},
                          "iPhone 17 Pro"))

    # 8. Version ordering is numeric, not lexical: 27.0 > 26.10 > 26.5, and
    #    "iOS-27" with no minor sorts below "iOS-27-1".
    ok("8 26.10 beats 26.5", runtime_version(RUNTIME_PREFIX + "iOS-26-10")
       > runtime_version(RT26))
    ok("8 27.0 beats 26.10", runtime_version(RT27)
       > runtime_version(RUNTIME_PREFIX + "iOS-26-10"))
    ok("8 27 below 27.1", runtime_version(RUNTIME_PREFIX + "iOS-27")
       < runtime_version(RUNTIME_PREFIX + "iOS-27-1"))
    ok("8 non-iOS has no version", runtime_version(RT_WATCH) is None)

    # 9. Every spelling of the pin means one runtime.
    ok("9 pin spellings", normalize_pin("26.5") == normalize_pin("iOS 26.5")
       == normalize_pin("iOS-26-5") == (26, 5))
    # A second version, because one asserted value is satisfied by a constant:
    # a `normalize_pin` returning (26, 5) for everything survived check 9 alone.
    ok("9 pin reads the number", normalize_pin("iOS-27-0") == (27, 0))
    ok("9 pin single component", normalize_pin("27") == (27,))
    ok("9 empty pin", normalize_pin(None) is None)

    # 10. An exact name is exact: a prefix or a suffix is a different device.
    near = {RT27: [_dev("iPhone 17 Pro Max", "MAX"), _dev("iPhone 17", "BASE")]}
    raises("10 no prefix matching", NotFound,
           lambda: choose(near, "iPhone 17 Pro"))

    if failures:
        for f in failures:
            print("✗ %s" % f)
        print("✗ sim-device self-test: %d of its checks did not hold" % len(failures))
        return 1
    print("✓ sim-device self-test (10 checks)")
    return 0


def main(argv):
    if "--self-test" in argv:
        return self_test()
    name = os.environ.get("VERIFY_SIM_NAME") or (
        argv[1] if len(argv) > 1 and not argv[1].startswith("-") else DEFAULT_NAME
    )
    device_type = os.environ.get("VERIFY_SIM_TYPE", DEFAULT_TYPE)
    pin = os.environ.get("VERIFY_SIM_OS") or None
    print(resolve(name, device_type, pin))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
