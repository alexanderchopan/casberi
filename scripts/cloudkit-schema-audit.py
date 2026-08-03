#!/usr/bin/env python3
"""Every stored `Thing` property has a CloudKit field — the drift that ships silently.

WHY THIS IS MECHANICAL
----------------------
SwiftData infers an additive `Thing` change and CloudKit's **Development**
environment auto-creates the matching field the first time a dev build syncs
it. Neither of those touches **Production**, and a TestFlight or App Store
build mirrors to Production. CloudKit never auto-creates schema there.

The failure is INVISIBLE — not a crash, not "sync is off", but PARTIAL sync,
which is worse than either because it looks like it is working. CoreData
exports only the non-nil attributes of a record, so a plain note (title,
content, kind, source, dates) syncs fine while every voice note's `audio`,
every social post's `socialContext` and every screenshot's `ocrTopics` fails
its export and retries forever. Nothing in the build, in `verify.sh`, or on
any screen can see it.

Measured 2026-08-01: Production was **25 fields behind** the model and
Development 20 behind. The whole corpus of anything richer than a note would
have failed to sync. It went undetected for months because no shipped iOS
build had the iCloud entitlement at all, so Production sync had never once
run and nothing ever complained. See docs/cloudkit-deploy.md.

This is the same shape as the network-reach audit (a bridge host nobody
disclosed) and the keychain audit (a key stored without a device-only
policy): a correctness rule that no runtime signal can report, recorded in
prose, re-broken anyway. So it stops being remembered and starts being
checked.

WHAT IT CHECKS (static, no network, no build)
---------------------------------------------
Every stored property of `Thing` has a `CD_<name>` field, of the right type,
in `docs/cloudkit-schema.ckdb` — the checked-in snapshot of the deployed
schema. Two findings, both fatal:

  MISSING       a stored property with no CloudKit field. This is the
                2026-08-01 failure exactly.
  TYPE MISMATCH a field whose CloudKit type doesn't match what CoreData
                mirrors the Swift type as. Silent corruption rather than
                silent absence, and a deployed field's type cannot be
                changed in Production any more than it can be removed.

An EXTRA `CD_*` field (in the schema, not on the model) is reported as INFO
and never fails: a field deployed to Production **cannot be removed** (see
the doc), so leftovers are permanent and survivable by design. `CD_entityName`
is CoreData's own system field, not a model property, and is excluded.

THE CEILING, STATED PLAINLY
---------------------------
This proves the snapshot matches the model. It does NOT prove the snapshot
matches what is actually deployed — someone can edit the file without running
the import or pressing Deploy. That gap is what `--live` is for:

    scripts/cloudkit-schema-audit.py --live production

which exports the real schema with `cktool` and diffs THAT. It needs network
and Apple credentials, so it is deliberately NOT in `verify.sh` (whose
contract is all-local and deterministic — the `live-integrations.sh`
reasoning). The static check makes the deploy impossible to FORGET; only the
live check proves it HAPPENED.

TYPE MAPPING
------------
Confirmed against the live schema on 2026-08-01 (docs/cloudkit-deploy.md):
`String`/`UUID` → STRING, `Date` → TIMESTAMP, `Int`/`Bool` → INT64,
`Double` → DOUBLE, and everything else — `Data` (including `.externalStorage`),
`[String]`, `Codable` structs, enums — → BYTES.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

MODEL = ROOT / "Casberi/Shared/Thing.swift"
SNAPSHOT = ROOT / "docs/cloudkit-schema.ckdb"

TEAM_ID = "35428TQK3S"
CONTAINER_ID = "iCloud.com.casberi.app"

# CoreData's own system field on every mirrored record — not a model property.
SYSTEM_FIELDS = {"CD_entityName"}

# Swift type → the CloudKit type CoreData mirrors it as. Anything not named
# here is a `Data`, a collection, a Codable struct or an enum, all of which
# CoreData archives to BYTES.
SCALAR_TYPES = {
    "String": "STRING",
    "UUID": "STRING",
    "Date": "TIMESTAMP",
    "Int": "INT64",
    "Bool": "INT64",
    "Double": "DOUBLE",
}

# Matches a STORED property: `var name: Type = default` or `var name: Type?`,
# with any number of leading attributes (`@Attribute(.externalStorage)`). A
# COMPUTED property (`var x: T { … }`) can't match — `[^{=]` stops at the
# brace and the trailing `(=|$)` then fails. Same shape as the liveness
# audit's parser, extended to capture the type.
STORED_PROPERTY = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*var\s+([A-Za-z_]\w*)\s*:\s*([^{=]+?)\s*(?:=|$)"
)

# `CD_foo   STRING QUERYABLE SORTABLE,` inside a RECORD TYPE block. The type
# must admit DIGITS (`INT64`) — an `[A-Z]+` here parses it as `INT` and then
# fails its own word boundary, which reads every Int and Bool property as
# MISSING against a perfectly correct schema. Caught by the self-test.
SCHEMA_FIELD = re.compile(r"^\s*(CD_[A-Za-z_]\w*)\s+([A-Z][A-Z0-9]*(?:<[A-Z0-9]+>)?)\b")


def cloudkit_type(swift_type: str) -> str:
    """The CloudKit type CoreData mirrors `swift_type` as."""
    bare = swift_type.strip().rstrip("?").strip()
    return SCALAR_TYPES.get(bare, "BYTES")


def thing_stored_properties(source: str) -> dict[str, str]:
    """Stored properties of `Thing` → their Swift type.

    Parsed out of Shared/Thing.swift rather than hardcoded, so a new field is
    covered the day it lands — the same reason the liveness audit parses it.
    Scoped to the class body so the helper structs declared above it
    (`Provenance`, `SocialCard`) can't leak in.
    """
    start = source.find("final class Thing")
    if start < 0:
        raise SystemExit(
            "cloudkit-schema-audit: can't find `final class Thing` — model moved?"
        )
    body = source[start:]

    # Stop at the end of the class body so extensions below it don't leak in.
    depth = 0
    seen_open = False
    end = len(body)
    for i, ch in enumerate(body):
        if ch == "{":
            depth += 1
            seen_open = True
        elif ch == "}":
            depth -= 1
            if seen_open and depth == 0:
                end = i
                break
    body = body[:end]

    props: dict[str, str] = {}
    for line in body.splitlines():
        m = STORED_PROPERTY.match(line)
        if m:
            props[m.group(1)] = m.group(2)
    return props


def schema_fields(source: str) -> dict[str, str]:
    """`CD_*` fields of the CD_Thing record type → their CloudKit type."""
    start = source.find("RECORD TYPE CD_Thing")
    if start < 0:
        raise SystemExit(
            "cloudkit-schema-audit: no `RECORD TYPE CD_Thing` in the schema — wrong file?"
        )
    end = source.find(");", start)
    block = source[start : end if end > 0 else len(source)]

    fields: dict[str, str] = {}
    for line in block.splitlines():
        m = SCHEMA_FIELD.match(line)
        if m:
            fields[m.group(1)] = m.group(2)
    return fields


def compare(props: dict[str, str], fields: dict[str, str]):
    """Returns (missing, mismatched, extra)."""
    missing: list[tuple[str, str]] = []
    mismatched: list[tuple[str, str, str]] = []

    for name, swift_type in sorted(props.items()):
        want = cloudkit_type(swift_type)
        field = f"CD_{name}"
        if field not in fields:
            missing.append((name, want))
        elif fields[field] != want:
            mismatched.append((name, want, fields[field]))

    expected = {f"CD_{n}" for n in props} | SYSTEM_FIELDS
    extra = sorted(f for f in fields if f not in expected)
    return missing, mismatched, extra


def report(props, fields, label: str) -> int:
    missing, mismatched, extra = compare(props, fields)

    for name, want in missing:
        print(f"  MISSING        {name} — no CD_{name} ({want}) in {label}")
    for name, want, got in mismatched:
        print(f"  TYPE MISMATCH  {name} — model says {want}, {label} says {got}")
    for field in extra:
        print(f"  info: {field} is in {label} with no matching property (deployed fields can't be removed)")

    if missing or mismatched:
        print()
        print(f"✗ CloudKit schema audit: {len(missing)} missing, {len(mismatched)} mismatched")
        print()
        print("  A TestFlight/App Store build mirrors to PRODUCTION, and CloudKit never")
        print("  auto-creates schema there. A property with no field doesn't fail loudly —")
        print("  every record carrying it fails its export forever while plain notes sync,")
        print("  so it reads as 'sync works'. See docs/cloudkit-deploy.md to update")
        print("  Development with cktool, then promote in the CloudKit Console.")
        return 1

    print(
        f"✓ CloudKit schema audit: {len(props)} stored properties, all present in {label}"
        + (f" ({len(extra)} leftover field{'s' if len(extra) != 1 else ''})" if extra else "")
    )
    return 0


def live_schema(environment: str) -> str:
    """Export the real schema with cktool. Network + credentials."""
    cmd = [
        "xcrun", "cktool", "export-schema",
        "--team-id", TEAM_ID,
        "--container-id", CONTAINER_ID,
        "--environment", environment,
    ]
    print(f"→ {' '.join(cmd)}")
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    except FileNotFoundError:
        raise SystemExit("cloudkit-schema-audit: xcrun not found — needs Xcode command line tools")
    except subprocess.TimeoutExpired:
        raise SystemExit("cloudkit-schema-audit: cktool timed out reaching CloudKit")
    if out.returncode != 0:
        raise SystemExit(
            "cloudkit-schema-audit: cktool failed — is a management token saved?\n"
            "  (xcrun cktool save-token --type management)\n"
            + (out.stderr or out.stdout).strip()
        )
    return out.stdout


# ── self-test ───────────────────────────────────────────────────────────
# A check that can't fail proves nothing, so it demonstrates it catches each
# shape — and passes the clean one — before it certifies the real tree.

CLEAN_MODEL = """
struct SocialCard: Codable {
    var handle: String
    var id: String { handle }
}

@Model
final class Thing {
    var id: UUID = UUID()
    var title: String = ""
    var kind: ThingKind = ThingKind.note
    var starCount: Int? = nil
    var transferUSD: Double? = nil
    var dueAt: Date? = nil
    var tags: [String] = []
    @Attribute(.externalStorage) var audio: Data? = nil
    var isFlagged: Bool { !title.isEmpty }
}

extension Thing {
    var typeTag: String { "thing" }
}
"""

CLEAN_SCHEMA = """
DEFINE SCHEMA
    RECORD TYPE CD_Thing (
        CD_id          STRING QUERYABLE SEARCHABLE SORTABLE,
        CD_title       STRING QUERYABLE SEARCHABLE SORTABLE,
        CD_kind        BYTES QUERYABLE SORTABLE,
        CD_starCount   INT64 QUERYABLE SORTABLE,
        CD_transferUSD DOUBLE QUERYABLE SORTABLE,
        CD_dueAt       TIMESTAMP QUERYABLE SORTABLE,
        CD_tags        BYTES QUERYABLE SORTABLE,
        CD_audio       BYTES QUERYABLE SORTABLE,
        CD_entityName  STRING QUERYABLE SEARCHABLE SORTABLE,
        "___recordID"  REFERENCE,
        GRANT READ TO "_world"
    );

    RECORD TYPE Users (
        "___recordID" REFERENCE,
        roles         LIST<INT64>
    );
"""


def self_test() -> int:
    failures = []

    def check(name: str, ok: bool, detail: str = ""):
        print(f"  {'✓' if ok else '✗'} {name}{'' if ok else f' — {detail}'}")
        if not ok:
            failures.append(name)

    props = thing_stored_properties(CLEAN_MODEL)
    fields = schema_fields(CLEAN_SCHEMA)

    # The parser itself: stored in, computed out, helper structs out.
    check("parses stored properties", props.keys() == {
        "id", "title", "kind", "starCount", "transferUSD", "dueAt", "tags", "audio",
    }, f"got {sorted(props)}")
    check("excludes computed properties", "isFlagged" not in props and "typeTag" not in props)
    check("excludes properties of other types", "handle" not in props)

    # The type mapping, each arm.
    for swift, want in [
        ("String", "STRING"), ("String?", "STRING"), ("UUID", "STRING"),
        ("Date?", "TIMESTAMP"), ("Int?", "INT64"), ("Bool", "INT64"),
        ("Double?", "DOUBLE"), ("Data?", "BYTES"), ("[String]", "BYTES"),
        ("ThingKind", "BYTES"), ("SocialCard?", "BYTES"),
    ]:
        check(f"maps {swift} → {want}", cloudkit_type(swift) == want, cloudkit_type(swift))

    # A clean tree passes.
    missing, mismatched, extra = compare(props, fields)
    check("clean model+schema is clean", not missing and not mismatched and not extra,
          f"missing={missing} mismatched={mismatched} extra={extra}")

    # Each failure shape is caught.
    dropped = {k: v for k, v in fields.items() if k != "CD_socialContext"}
    grown = dict(props, socialContext="String?")
    missing, _, _ = compare(grown, dropped)
    check("catches a MISSING field", missing == [("socialContext", "STRING")], str(missing))

    retyped = dict(fields, CD_starCount="STRING")
    _, mismatched, _ = compare(props, retyped)
    check("catches a TYPE MISMATCH", mismatched == [("starCount", "INT64", "STRING")], str(mismatched))

    shrunk = {k: v for k, v in props.items() if k != "audio"}
    m, mm, extra = compare(shrunk, fields)
    check("reports an EXTRA field without failing", extra == ["CD_audio"] and not m and not mm, str(extra))

    # The system field is never an extra, and never demanded of the model.
    check("CD_entityName is not an extra", "CD_entityName" not in extra)

    print()
    if failures:
        print(f"✗ self-test: {len(failures)} check(s) failed — the audit is broken, not the code")
        return 1
    print("✓ self-test passed")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--self-test", action="store_true",
                    help="prove the audit catches each failure shape")
    ap.add_argument("--live", choices=["development", "production"], metavar="ENV",
                    help="diff against the REAL schema via cktool (network; not run in verify.sh)")
    args = ap.parse_args()

    if args.self_test:
        return self_test()

    props = thing_stored_properties(MODEL.read_text(encoding="utf-8"))

    if args.live:
        return report(props, schema_fields(live_schema(args.live)), f"live {args.live}")

    if not SNAPSHOT.exists():
        print(f"✗ CloudKit schema audit: {SNAPSHOT.relative_to(ROOT)} is missing")
        print("  Regenerate it — see docs/cloudkit-deploy.md.")
        return 1
    return report(props, schema_fields(SNAPSHOT.read_text(encoding="utf-8")),
                  str(SNAPSHOT.relative_to(ROOT)))


if __name__ == "__main__":
    sys.exit(main())
