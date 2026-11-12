# Scripts

One flat folder, sorted by name. The suffix says what a file is. Paths are stable on purpose: `verify.sh` discovers checks by pattern, and the nightly jobs, CI and docs name these files directly.

## By suffix

| Pattern | Count | What it is |
| --- | --- | --- |
| `*-audit.py`, `*-audit.sh` | 76 | Static checks over the source tree. No build needed. Discovered and run by `verify.sh`. |
| `*-selftest.sh`, `*-selftest.py` | 212 | Pure-logic harnesses. Each compiles the app's own Foundation-only files against stubs and runs test vectors and mutations. |

Every check has a `--self-test` proving it can fail. What each one catches is in `docs/verify.md`.

## Entry points

| Script | Use |
| --- | --- |
| `verify.sh` | The whole pass: build, Mac Catalyst compile, every audit and self-test, simulator sweep. |
| `verify-mac.sh` | The Mac leg. `verify.sh` runs it in parallel and gates on it. |
| `xcb.sh` | `xcodebuild` behind a machine-wide lock. Always build through this. |
| `sim-device.py` | Prints the test simulator's UDID. |
| `dev-keys.sh` | Test keys in the login Keychain. Nothing secret lives in the tree. |
| `install-hooks.sh` | Installs the git hooks in `hooks/`. |

## Everything else

| Group | Scripts |
| --- | --- |
| Release | `testflight.sh`, `testflight-mac.sh`, `testflight-public-beta*.sh`, `testflight-expire-*`, `testflight-retry-review.sh`, `appstore-release.sh`, `appstore-swap-build.sh`, `exportOptions.plist` |
| App Store Connect | `asc-copy.py`, `asc-jwt.py`, `asc-report.py`, `asc-screenshots.py`, `mac-appstore-capture.sh` |
| Nightly | `nightly-live.sh`, `nightly-mac.sh`, `live-integrations.sh`, `journeys.sh`, `journeys-report.py`, `journeys-targets.json`, `sheet-sweep*`, `app-pages-sweep.sh`, `com.casberi.*.plist` (launchd) |
| Engines and vendored builds | `aztec-engine.sh`, `tdlib.sh`, `tor-repackage.sh`, `ppv2-upstream.py` |
| Generated data | `clearsign-registry.py`, `clearsign-casberi.py`, `uniswap-v4-pools.py`, `l2beat-snapshot.py`, `walletbeat-snapshot.py`, `law-digest.py`, `build-blocks.py`, `coin-symbol.swift` |
| Website | `catalog-sync.sh`, `site-integrity.py` |
| Demo art | `demo-art/`, `make-demo-art.swift`, `make-demo-avatars.swift`, `wallet-video/` |
| Performance | `perf.sh`, `main-thread-profile.sh` |
| Repo upkeep | `repo-sync.sh`, `branch-prune.sh`, `disk-sweep.sh`, `worker-gate.py`, `file-findings.py` |
| Probes | `wc-handshake.sh`, `wc-wallet/`, `fileverse-probe/`, `direct-swap-record.py` |

## Folders

| Folder | What it holds |
| --- | --- |
| `fixtures/` | Recorded responses and test vectors the self-tests read. |
| `support/` | Shared helpers and vector generators for the harnesses. |
| `hooks/` | The git hooks (`commit-msg`, `post-commit`). |
| `output/` | Verify output. Ignored by git. |
