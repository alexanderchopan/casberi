# Docs

Start with `law.md`. It is the current ruling for every area of the app, each line citing the entry in `prd.md` that made it.

## At this level: what is in force

| File | What it is |
| --- | --- |
| `law.md` | Current rulings by area. Generated from `prd.md` by `scripts/law-digest.py`. |
| `prd.md` | The ruling ledger, append-only, cited everywhere as `§N`. The record, not the summary. |
| `build-brief.md` | The design system (§8 is law for all UI work). |
| `brand.md` | The mark, the name and the directions that were rejected. |
| `verify.md` | Every check `scripts/verify.sh` runs: what it catches and why it exists. |
| `gotchas.md` | SwiftUI and UIKit traps already paid for. |
| `liveness.md` | The SwiftData crash class and the rule that prevents it. |
| `cloudkit-deploy.md`, `cloudkit-schema.ckdb` | Shipping a schema change to CloudKit Production. |
| `testflight-handoff.md` | The release runbook. |
| `website.md` | Rules for casberi.app (`website/`). |
| `workers.md` | Rules for unattended agent sessions and the gate that enforces them. |

## Folders

| Folder | What it holds |
| --- | --- |
| `hooks/` | Per-area build records: wallet, bridges, design, system, agent, social, rooms, imports, devnets. Each DEBUG launch hook and what it measures. |
| `specs/` | Feature specs. The security-relevant ones: `signing-safety-spec.md`, `safe-wallet-spec.md`, `signer-spec.md`, `aztec-security-model.md`. |
| `store/` | The App Store page's text, read and applied by `scripts/asc-copy.py` and checked by `scripts/catalog-sync.sh`. |
| `archive/` | Superseded specs and session handoffs, kept because code comments and the ledger cite them. Not current. |
