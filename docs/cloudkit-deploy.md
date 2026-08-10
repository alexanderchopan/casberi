# CloudKit: the Production schema is a separate ship

SwiftData infers an additive `Thing` change and CloudKit's **Development**
environment auto-creates the matching field the first time a dev build syncs
it. **Neither of those touches Production.** A TestFlight or App Store build
mirrors to Production (`com.apple.developer.icloud-container-environment:
Production` in the signed IPA), and CloudKit never auto-creates schema there.

So a new `Thing` property is not shipped until its field exists in Production,
and nothing in the build, the audits, or `verify.sh` can tell you it doesn't.

## What that failure looks like

Not a crash, and not "sync is off" — **partial sync**, which is worse than
either because it looks like it's working. CoreData exports only the non-nil
attributes of a record, so a plain note (title, content, kind, source, dates)
syncs fine while anything carrying an undeployed field — a voice note's
`audio`, a social post's `socialContext`, a screenshot's `ocrTopics` — fails
its export and retries forever.

Measured 2026-08-01: Production was **25 fields behind** the model and
Development **20 behind** (they had drifted together since roughly the
wallet/social/detection work). The whole corpus of anything richer than a note
would have failed to sync.

**Resolved the same day.** Development was brought current via `cktool` and
promoted in the Console; both environments now carry all 57 stored properties
of `Thing` plus CoreData's `CD_entityName`, verified by re-export — no missing
fields, no type mismatches, the two environments level. That clears the last
server-side blocker; what remains unproven is a real device round-trip, which
needs build 231+ installed with sync switched on.

## Open: `CD_pinnedAt` is in Development, not yet in Production (2026-08-10)

The pin verb added `Thing.pinnedAt`. Development was imported and verified by
re-export the same session (59 → 60 `CD_*` fields); Production is **one field
behind and nothing else** (`--live production` reports `1 missing, 0
mismatched`), so the Console diff is a single added timestamp.

Until it is promoted, pins work locally and silently fail to mirror on any
build signed against Production — which is the partial-sync failure described
above, wearing the one field a person would most expect to follow them between
devices. Promote before the next TestFlight ship, then re-run
`scripts/cloudkit-schema-audit.py --live production` to confirm it landed.

## The drift is invisible — so it's checked, not remembered

`scripts/cloudkit-schema-audit.py` runs in `verify.sh`'s static head and fails
the build when a stored `Thing` property has no `CD_<name>` field — or has one
of the wrong type — in `docs/cloudkit-schema.ckdb`. Self-tested, no network,
no build. An EXTRA field in the schema is reported and never fails, because a
field deployed to Production cannot be removed (below).

Its ceiling, stated plainly: it proves the model matches the checked-in
snapshot, which makes the deploy impossible to **forget**. It cannot prove the
snapshot matches what is really deployed — someone can edit the file without
running the import or pressing Deploy. That is what `--live` is for, and why
it stays out of `verify.sh` (network + credentials, against `verify.sh`'s
all-local deterministic contract — the `live-integrations.sh` reasoning):

```sh
scripts/cloudkit-schema-audit.py --live production
```

Run that before a release, and after any promotion, to confirm the ship really
landed. The raw export it wraps:

```sh
xcrun cktool export-schema --team-id 35428TQK3S \
  --container-id iCloud.com.casberi.app --environment production
```

Diff the `CD_*` field names against `Thing`'s stored properties (the mapping is
just `CD_<propertyName>`; computed properties are NOT in the schema, and
`CD_entityName` is CoreData's own system field, not a model property).
`docs/cloudkit-schema.ckdb` is the checked-in snapshot of what Development
carried on 2026-08-01 — regenerate it whenever `Thing` changes.

Type mapping CoreData uses, confirmed against the live schema: `String`/`UUID`
→ `STRING`, `Date` → `TIMESTAMP`, `Int`/`Bool` → `INT64`, `Double` → `DOUBLE`,
and everything else — `Data` (including `.externalStorage`), `[String]`,
`Codable` structs, enums — → `BYTES`.

## Updating it

**Development** is scriptable. Export the current schema, add the missing field
lines to it (add to the export rather than regenerating, so the grants, the
`___` system fields and the `Users` record type survive untouched), then:

```sh
xcrun cktool validate-schema --team-id 35428TQK3S \
  --container-id iCloud.com.casberi.app --environment development --file schema.ckdb
xcrun cktool import-schema --team-id 35428TQK3S \
  --container-id iCloud.com.casberi.app --environment development --file schema.ckdb
```

**Production is not scriptable, by Apple's design.** `cktool` answers any
production write with `BadRequestException: endpoint not applicable in the
environment 'production'`. The promotion is a deliberate action in the CloudKit
Console — <https://icloud.developer.apple.com/dashboard/> → the
`iCloud.com.casberi.app` container → **Schema** → **Deploy Schema Changes** →
review the diff → Deploy.

It is one-way in the way that matters: `cktool reset-schema` resets
**Development** to match Production, and there is no inverse. A field deployed
to Production cannot be removed. That is survivable for a field that is merely
unused (Production still carries `CD_entityName` and other leftovers) but it is
why the diff gets read before the button gets pressed.

## When to do it

Every time `Thing` gains a property, in the same session — the same rule the
catalog and the network-reach registry already follow. The reason this drifted
20 fields deep is that no shipped iOS build had the iCloud entitlement at all
(see `scripts/testflight.sh` and the 2026-08-01 entitlements commit), so
Production sync had never once been exercised and nothing ever complained.
