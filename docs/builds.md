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
| 1002 | 3.0.30 | iOS | `ea3c582d7` | clean | 2026-11-14 |
| 1003 | 3.0.30 | iOS | `5e3473d9b` | clean | 2026-11-15 |
| 1004 | 3.0.30 | iOS | `c6fcb2d5e` | clean | 2026-11-15 |
| 1004 | 3.0.30 | Mac | `40abd7a63` | clean | 2026-11-15 |
| 1005 | 3.0.30 | iOS | `09b4c767b` | clean | 2026-11-15 |
| 1006 | 3.0.30 | iOS | `d94561e12` | clean | 2026-11-15 |
| 1007 | 3.0.30 | iOS | `1376ca967` | clean | 2026-11-15 |
| 1008 | 3.0.30 | iOS | `0c42da2eb` | clean | 2026-11-15 |
| 1009 | 3.0.30 | iOS | `07dfb1bdb` | clean | 2026-11-15 |
| 1010 | 3.0.30 | iOS | `4585be2ed` | clean | 2026-11-15 |
| 1011 | 3.0.31 | iOS | `d1d47bac9` | clean | 2026-11-16 |
| 1012 | 3.0.31 | iOS | `0f9fbcc78` | clean | 2026-11-16 |
| 1013 | 3.0.31 | iOS | `8a93cf906` | clean | 2026-11-16 |
| 1014 | 3.0.31 | iOS | `f04dd69f3` | clean | 2026-11-16 |
| 1015 | 3.0.31 | iOS | `f638f4d82` | clean | 2026-11-16 |
| 1016 | 3.0.31 | iOS | `561a08667` | clean | 2026-11-16 |
| 1017 | 3.0.32 | iOS | `8a2c80b9f` | clean | 2026-11-16 |
| 1019 | 3.0.32 | iOS | `aed97b1b3` | clean | 2026-11-17 |
| 1020 | 3.0.32 | iOS | `09c121fef` | clean | 2026-11-17 |
| 1021 | 3.0.32 | iOS | `6c6e07647` | clean | 2026-11-17 |
| 1022 | 3.0.32 | iOS | `54487b94c` | clean | 2026-11-17 |
| 1023 | 3.0.32 | iOS | `572337493` | clean | 2026-11-17 |
