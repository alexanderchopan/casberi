# Builds

Which commit each shipped build was made from. `scripts/testflight.sh` and `scripts/testflight-mac.sh` add a row after every upload (`scripts/build-record.sh`).

- **Tree** is `clean` when every tracked file under `Casberi/` and `Vendor/` matched the commit in **From** when the build was archived, apart from the build number. The build's source is then the tag `build-<n>`: the commit that carries the build-number bump.
- **Tree** is `dirty` when the build was shipped with uncommitted changes. It matches no commit and gets no tag.
- Builds before this ledger began (982 and earlier) were archived from the working tree with no record, so they cannot be tied to a commit. Each has a commit titled "Bump build number to N", which is close but not proof.

| Build | Version | Platform | From | Tree | Date |
| --- | --- | --- | --- | --- | --- |
