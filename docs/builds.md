# Builds

Which commit each shipped build was made from. `scripts/testflight.sh` and `scripts/testflight-mac.sh` add a row after every upload (`scripts/build-record.sh`).

- **Tree** is `clean` when every tracked file under `Casberi/` and `Vendor/` matched the commit in **From** when the build was archived, apart from the build number. The build's source is then the tag `build-<n>`, the commit that adds its row here: under `Casberi/` and `Vendor/` that commit is identical to what was archived.
- **Tree** is `dirty` when the build was shipped with uncommitted changes. It matches no commit and gets no tag.
- Builds before this ledger began (982 and earlier) were archived from the working tree with no record, so they cannot be tied to a commit. Each has a commit titled "Bump build number to N", which is close but not proof.

| Build | Version | Platform | From | Tree | Date |
| --- | --- | --- | --- | --- | --- |
| 983 | 3.0.28 | iOS | `b9128cbde` | clean | 2026-11-12 |
| 984 | 3.0.29 | iOS | `46aff3e5a` | clean | 2026-11-12 |
| 985 | 3.0.29 | iOS | `45ab32c2d` | clean | 2026-11-13 |
