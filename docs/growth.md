# Growth plan

Started 2026-09-27. How Casberi gets users past posting on X, and which part of it runs where.
The session that started it is summarized in `docs/growth-handoff.md`.

## Where it stands

- Live on the App Store, iOS and Mac (`id6788637831`). Betas ship through TestFlight's
  Casberi Public Beta group.
- The app has no telemetry, by rule. App Store Connect is the only place install, source and
  retention numbers come from.
- The live store description and promotional text sell the built-in ask, which §697b turned
  off. What the app offers now: bring your own agent (the keyed seats, §871) and the Apple
  Intelligence seat (§833, dark until Apple grants the managed entitlement). The replacement copy in
  `docs/store-copy.md` predates this framing and is not applied. The live subtitle is not
  recorded in the repo.
- MCP: the Mac listener is built, `MCPPairing.transportReady` is `false`, and it has never been
  run against a real client. The store page cannot claim it until it has.
- Drafted, not sent: `docs/hn-launch-post.md`, `docs/launch-thread.md` (lists 34 apps; the
  catalogue is 100+), `docs/paragraph-post.md`.

## What runs where

This cloud container cannot reach `api.appstoreconnect.apple.com` or `casberi.app` (the
environment's network policy returns 403), holds no App Store Connect key, and has no Xcode.

| Work | Cloud session | Mac session |
|---|---|---|
| Write scripts, copy, docs, website pages | yes | yes |
| Call the App Store Connect API | no (see "Moving ASC work to the cloud") | yes, key in Keychain |
| Build, simulator, `verify.sh`, screenshots | no | yes |
| Test the MCP listener with Claude Desktop / Claude Code | no | yes |
| Deploy the website (cPanel) | no | yes |
| Post, submit forms, send pitches | no, you do these | no, you do these |

Rule of thumb: the cloud writes, the Mac runs.

### Moving ASC work to the cloud (optional)

Two changes in the cloud environment's settings (environment menu in the session title bar →
Edit):

1. Network access: add `api.appstoreconnect.apple.com` to the allowed domains.
2. Environment variables: `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY_P8` (the `.p8`
   contents). The scripts below write `ASC_KEY_P8` to a temp file and pass it as
   `ASC_KEY_PATH`.

Use a second API key for this, not the upload key in the Keychain. Give it the narrowest role
that covers reports, reviews and metadata, so the cloud copy cannot ship a build. Revoke it in
App Store Connect → Users and Access → Integrations if it leaks.

## Workstreams

Each step is tagged with where it runs.

### 1. Measurement

- [mac, written 2026-09-27] `scripts/asc-report.py` — `status`; `request` (ONGOING, dry run
  until `--yes`, needs the Admin role); `funnel` prints impressions → page views → first-time
  downloads per week, by source, device and territory (`--detailed` adds campaign, referrer
  and custom product page); `links --pt` prints the campaign links. Reads DAILY instances
  (35 days) and takes each date from the newest instance only (Apple's overwrite rule).
  Sessions and installs/deletions are not read yet. `--self-test` runs offline.
- [mac, done 2026-09-27] ONGOING report request `4f45d303-e232-46eb-beb9-6f6b74091f92` made
  (none existed before). First instances land 1–2 days later: run `asc-report.py status`,
  then `funnel`. A request left unread for long enough stops (`stoppedDueToInactivity`), so
  the weekly run in workstream 1 also keeps it alive.
- [cloud] Campaign links: one App Store link per channel,
  `https://apps.apple.com/app/id6788637831?pt=<provider token>&ct=<channel>`. The provider
  token is under App Store Connect → Analytics. Keep the list in this file.
  Provider token `129130687` (read 2026-09-27; `asc-report.py links` prints these). A new
  channel is a row in `CHANNELS` in `scripts/asc-report.py`, a row here, AND a campaign
  SAVED in App Store Connect → Analytics → Campaigns under the same token: Apple counts only
  saved tokens (user, told by Apple, 2026-09-27). Generating a link does not save it. The campaign
  shows only in the DETAILED reports (`funnel --detailed`), which drop small rows.

  | Channel | Link | Saved in ASC |
  |---|---|---|
  | `x` | https://apps.apple.com/app/id6788637831?pt=129130687&ct=x&mt=8 | no |
  | `instagram` | https://apps.apple.com/app/id6788637831?pt=129130687&ct=instagram&mt=8 | 2026-09-27 |
  | `website` | https://apps.apple.com/app/id6788637831?pt=129130687&ct=website&mt=8 | no |
  | `farcaster` | https://apps.apple.com/app/id6788637831?pt=129130687&ct=farcaster&mt=8 | no |
  | `bluesky` | https://apps.apple.com/app/id6788637831?pt=129130687&ct=bluesky&mt=8 | no |
  | `hn` | https://apps.apple.com/app/id6788637831?pt=129130687&ct=hn&mt=8 | no |
  | `producthunt` | https://apps.apple.com/app/id6788637831?pt=129130687&ct=producthunt&mt=8 | no |
  | `reddit` | https://apps.apple.com/app/id6788637831?pt=129130687&ct=reddit&mt=8 | no |
  | `newsletter` | https://apps.apple.com/app/id6788637831?pt=129130687&ct=newsletter&mt=8 | no |
  | `github` | https://apps.apple.com/app/id6788637831?pt=129130687&ct=github&mt=8 | no |
  | `email` | https://apps.apple.com/app/id6788637831?pt=129130687&ct=email&mt=8 | no |
- [mac] Run `asc-report.py` weekly, or schedule it in the cloud after "Moving ASC work".

### 2. The store page

- [cloud, written 2026-09-27] `scripts/asc-copy.py` — `read` saves every live field (subtitle,
  description, keywords, promotional text, What's New, per locale) to `docs/store-live.json`;
  `diff` compares en-US with the drafts in `docs/store-copy.md`; `apply --platform --field`
  is a dry run until `--yes`, then writes and reads back. `--self-test` runs offline.
- [cloud, drafted 2026-09-27] Description and promotional text rewritten around the feed and bring your
  own agent (`docs/store-copy.md`). No MCP claim until workstream 5 passes.
- [mac, done 2026-09-27] `read` + `diff` run; live subtitle recorded (`One app for your
  things`). **Promotional text APPLIED** to iOS 1.0.39, iOS 1.0.40 (in review) and Mac 1.0.40,
  read back. The diff showed the iOS description DRAFT is behind the live text (live says
  "More than 100 apps" and already has an agents block; the draft says "Over 90") and the live
  iOS text has a typo ("Iry what is coming to Ethereum"): reconcile the draft against
  `docs/store-live.json` before 1.0.41. The iOS keywords draft is the live set reordered.
- [cloud] Keywords per locale the app already ships.
- [mac] Run it (key staged per `docs/testflight-handoff.md`):
  ```sh
  scripts/dev-keys.sh get-file asc-p8 /tmp/asc.p8
  scripts/asc-copy.py read          # record the live subtitle in store-copy.md
  scripts/asc-copy.py diff
  scripts/asc-copy.py apply --platform IOS --field promotionalText        # dry run
  scripts/asc-copy.py apply --platform IOS --field promotionalText --yes  # after approval
  scripts/asc-copy.py apply --platform MAC_OS --field promotionalText --yes
  rm -f /tmp/asc.p8
  ```
  Description and keywords need a version in an editable state; they go with the next
  submission.

### 3. Audience tests

- [cloud] Three Custom Product Pages, each with its own screenshots and link: all your apps
  in one feed; wallets and cards; social notifications (Farcaster, Bluesky, X). Download rate
  per page picks the audience.
- [mac] Capture the screenshots per page (`DEMO_SHOTS=1`, `-hideDemoBanner YES`).
- [mac] One Product Page Optimization test on the icon or first screenshot.
- [cloud] In-app events: one per shipped integration or feature, shown in App Store search.

### 4. Pages per integration

- [cloud] Generate one page per offer in `BridgeCatalog.offers` under `website/apps/`
  ("Gnosis Pay spending tracker", "Farcaster notifications on iPhone"), linked with that
  channel's campaign token. Extend `scripts/catalog-sync.sh` so a new offer without a page
  fails.
- [mac] Deploy through cPanel (`docs/website.md`).

### 5. MCP as a channel

- [mac] Connect Claude Desktop or Claude Code to the Mac listener (`-accountDetail mcp`).
  Measure the three tools, the pairing token, the loopback checks.
- [mac] If it holds: set `MCPPairing.transportReady = true`, add the pairing UI, ship.
- [cloud] Then: store copy line, a docs page, and listings in MCP registries.

### 6. Reviews and testers

- [cloud] `scripts/asc-reviews.py` — pull new reviews, draft replies into a file for approval,
  post approved ones with `--post`.
- [cloud] Read TestFlight tester feedback and crash submissions into a weekly list.
- [mac] Run both weekly.

### 7. Outside the App Store (drafts in the cloud, sending by you)

- Apple featuring nomination (App Store Connect → Nominations): Liquid Glass, Visual
  Intelligence, widgets, the Apple Intelligence seat once it is live.
- Ecosystem directories and grants: Farcaster, Base, Safe, World, Gnosis Pay, Obsidian,
  Ethereum Foundation. Claude compiles the list with links and drafts each submission.
- Instagram: run by the user through Meta's agent, outside this plan. Its links carry
  `ct=instagram` so its installs show in workstream 1's report.
- Communities: one post per integration for that integration's users, each with its campaign
  link.
- Launches: Show HN and Product Hunt, after workstream 2. Update the drafts to the current
  catalogue first.
- Long-form: measured findings from `docs/prd.md` as posts for developers.

## Order

1. Week 1 — workstreams 1 and 2.
2. Weeks 2–3 — workstreams 3 and 5.
3. Weeks 3–4 — workstream 4, then the launches in 7.
4. Ongoing — 6 weekly, the rest of 7 as drafts land.

## Starting the Mac session

Open Claude Code in `~/Developer/casberi` with Xcode running and the project open, then paste:

```
Read docs/growth.md. We run the Mac-tagged steps, starting with workstream 2:
stage the key per docs/testflight-handoff.md, run scripts/asc-copy.py read and diff,
record the live subtitle in docs/store-copy.md, show me the diff, and wait for my
approval before any apply --yes. Then workstream 1: write scripts/asc-report.py the
same way asc-copy.py is built (asc-jwt.py, stdlib, an offline --self-test).
```

If this file is on the `claude/growth-planning-strategy-0zpz7y` branch and not yet on
`main`, run `git fetch origin && git merge origin/claude/growth-planning-strategy-0zpz7y`
first.
