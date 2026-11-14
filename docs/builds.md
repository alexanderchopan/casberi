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
| 986 | 3.0.29 | Mac | `88140c160` | clean | 2026-11-13 |
| 987 | 3.0.29 | iOS | `75ace61e2` | clean | 2026-11-13 |
| 988 | 3.0.29 | iOS | `d3c6a3065` | clean | 2026-11-13 |
| 989 | 3.0.29 | iOS | `623e5b2c3` | clean | 2026-11-13 |
| 990 | 3.0.29 | iOS | `305571956` | clean | 2026-11-13 |
| 991 | 3.0.29 | iOS | `f04ea6d63` | clean | 2026-11-13 |
| 992 | 3.0.30 | iOS | `f7ec2b5f7` | clean | 2026-11-13 |
| 993 | 3.0.30 | iOS | `fff104ee4` | clean | 2026-11-14 |
| 994 | 3.0.30 | iOS | `0af3ea76e` | clean | 2026-11-14 |
| 995 | 3.0.30 | iOS | `88407b8a0` | clean | 2026-11-14 |
| 996 | 3.0.30 | iOS | `85cba80c2` | clean | 2026-11-14 |
| 996 | 3.0.30 | iOS | `85cba80c2` | clean | 2026-11-14 |
| 997 | 3.0.30 | iOS | `8e79f7ec0` | clean | 2026-11-14 |
| 997 | 3.0.30 | iOS | `8e79f7ec0` | clean | 2026-11-14 |
| 998 | 3.0.30 | iOS | `52c981a1a` | clean | 2026-11-14 |
| 999 | 3.0.30 | iOS | `686f9f1e4` | clean | 2026-11-14 |
| 1000 | 3.0.30 | iOS | `4de592cc7` | clean | 2026-11-14 |
| 1001 | 3.0.30 | iOS | `9c5946090` | clean | 2026-11-14 |
| 1001 | 3.0.30 | Mac | `9c5946090` | clean | 2026-11-14 |
