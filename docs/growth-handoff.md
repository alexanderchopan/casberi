# Growth — session handoff (2026-09-27)

What the cloud session that started `docs/growth.md` decided and left open, for the Mac
session that picks it up. Read `docs/growth.md` first; this file is the conversation around it.

## Decisions the user made

- **Growth beyond X is planned in seven workstreams** (`docs/growth.md`). Each step is tagged
  cloud or Mac, because the cloud container cannot reach `api.appstoreconnect.apple.com` or
  `casberi.app`, holds no ASC key, and has no Xcode.
- **Instagram is run by the user through Meta's agent**, outside the plan. Its links carry
  `ct=instagram` so its installs appear in the weekly report.
- **The ask is not gone.** §697b turned off the built-in ask, but the keyed agents answer in
  their own screens with All and Chat (§839, §840): Claude, ChatGPT, Gemini, Grok, Venice,
  OpenRouter, NEAR AI, Muse, Bankr. The store page sells that as "bring your own agent".
- **MCP is not claimed anywhere yet.** The Mac listener exists; `MCPPairing.transportReady`
  is `false` and it has never met a real client. Workstream 5 tests it first.
- **Apple Intelligence is not named** on the store page: its seat is dark until Apple grants
  the managed entitlement (§833).
- **No "room" on the store page.** Someone told the user it reads as AI. The store drafts
  use "Open an agent", "YOUR OWN AGENT", "opens shaped like", "Every view answers".
- **The app's own text keeps "room" for now** (19 strings). The user chose not to ship a
  build for wording. The website's 19 uses are also left as they are; they can change any
  time without a build.

## What exists

| Item | State |
|---|---|
| `docs/growth.md` | The plan, with the Mac commands and a start prompt |
| `docs/store-copy.md` | iOS and Mac descriptions and promotional text rewritten (agent block, no "room"). **Awaiting the user's approval. Not applied.** Keywords still pending on iOS |
| `scripts/asc-copy.py` | `read` / `diff` / `apply --yes`, lint, offline `--self-test` (passes). **Never run against the real API** |
| `CLAUDE.md` | Status line: live on the App Store, iOS and Mac |
| PR #199 | Branch `claude/growth-planning-strategy-0zpz7y`, draft. The repo's rule is straight to `main`; merge it or fetch the branch |

## Next, on the Mac

1. `git fetch origin && git merge origin/claude/growth-planning-strategy-0zpz7y`
2. Stage the key per `docs/testflight-handoff.md`, then `scripts/asc-copy.py read` and `diff`.
3. Record the live subtitle in `docs/store-copy.md` (it was changed 2026-09-08 and never
   written down).
4. Show the user the diff. On approval: `apply --field promotionalText --yes` for `IOS` and
   `MAC_OS` — promotional text needs no review, so it can go out before the Instagram posts.
   Description and keywords go with the next submission.
5. Workstream 1: write `scripts/asc-report.py` the way `asc-copy.py` is built (asc-jwt.py,
   stdlib, offline `--self-test`), then campaign links per channel.

## Open questions for the user

- Approve or edit the store copy in `docs/store-copy.md`.
- Take "room" off the website now, or later.
- Put a second, narrower ASC key in the cloud environment (optional) so reports can run on a
  schedule there.
