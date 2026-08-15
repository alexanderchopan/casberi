# Shipping a TestFlight build (handoff)

Point any session at this file to ship a Casberi build to TestFlight the same
way we always do. The process has TWO scripts, both run every ship, no
exceptions — this is not a step to wait to be asked for (user ruling
2026-07-21):

1. `scripts/testflight.sh` bumps the build number across all targets, archives
   Release **signed**, then re-signs + uploads for App Store distribution.
   (It archived UNSIGNED until 2026-08-01. That stripped every entitlement
   from every iOS build ever shipped — an unsigned `.app` carries no record of
   what `Casberi.entitlements` asked for, so export re-signed with only the
   four baseline keys: no app group, no keychain sharing, no iCloud, no
   HealthKit, no push. Do not "restore" the unsigned trick. Verify a doubtful
   build with `codesign -d --entitlements :- Payload/Casberi.app` on the
   exported IPA.)
2. `scripts/testflight-public-beta.sh` waits for that build to finish
   processing, writes tester-facing release notes, assigns it to the
   **Casberi Public Beta** external group, and submits it for Beta App Review.
   A ship that skips this step leaves the build sitting unassigned in App
   Store Connect — internal-only, not what "ship" means here.

## Credentials

The App Store Connect API access has three parts. Two are identifiers (safe to
keep here — useless on their own); the third is the private key (the only real
secret, never committed):

| Value | Store it here? | Value |
|---|---|---|
| `ASC_KEY_ID` | yes | `TR287WZD72` |
| `ASC_ISSUER_ID` | yes | `2152ec98-0a7c-477a-9c4a-e1c478a3a106` |
| `.p8` private key | **NO — never commit** | login Keychain, `dev-keys.sh` name `asc-p8` (see below) |
| `teamID` | already in `exportOptions.plist` | `35428TQK3S` |

Only the `.p8` grants upload access. It lives in the macOS **login Keychain**
under `casberi-dev.asc-p8`, managed by `scripts/dev-keys.sh` (2026-07-16 —
this replaced the paste-a-`cp`-line-per-ship ritual).

## Who does what (the whole ritual)

**The user's job is a ONE-TIME store, not a per-ship step.** If (and only if)
`scripts/dev-keys.sh list` doesn't show `asc-p8` yet, the user runs this once
in a terminal, then never again:

```sh
~/Developer/casberi/scripts/dev-keys.sh set-file asc-p8 ~/Downloads/AuthKey_TR287WZD72.p8
```

(Adjust the source path if the `.p8` lives elsewhere. Legacy fallback if the
Keychain copy is somehow gone AND the user can't re-store it:
`cp ~/Downloads/AuthKey_TR287WZD72.p8 /tmp/asc.p8` staged manually, as before.)

**Claude does everything, including staging the key** — a ship needs nothing
from the user once `asc-p8` is stored: commit the intended work, bump + commit
the build number, stage the key from the Keychain, and run the ship via the
Bash tool. Claude never reads or prints the key material — `get-file` writes
it straight to `/tmp/asc.p8` (mode 600) and the script reads it from there.
The commands Claude runs (from the canonical repo, or a clean isolated
worktree to exclude another session's WIP):

```sh
~/Developer/casberi/scripts/dev-keys.sh get-file asc-p8 /tmp/asc.p8

ASC_KEY_ID=TR287WZD72 \
ASC_ISSUER_ID=2152ec98-0a7c-477a-9c4a-e1c478a3a106 \
ASC_KEY_PATH=/tmp/asc.p8 \
SKIP_BUMP=1 \
~/Developer/casberi/scripts/testflight.sh
```

- `SKIP_BUMP=1` reuses the already-committed build number. Omit it to let the
  script bump the number itself (then commit the bump afterward — step 5).
- After `✓ Uploaded`, Claude wipes the staged copy: `rm -f /tmp/asc.p8` (the
  script also deletes it itself; belt and braces). The Keychain copy persists
  for the next ship — do NOT delete `asc-p8` from the Keychain.

## Steps (what Claude prepares before that command)

1. **Work only in `~/Developer/casberi`** — the canonical repo. Never the iCloud
   copy (its xattrs break codesign).

   **`git fetch` FIRST, and read the ahead/behind count** (2026-08-02). A bare
   `git status` prints a clean tree whether or not the branch is current, and
   `git log` shows only what this machine already has — so a repo six commits
   behind `origin/main` looks exactly like a repo with nothing new to ship. That
   is not hypothetical: this session was handed "we made more updates", found
   HEAD sitting on nothing but two build-number bumps, and was one command away
   from uploading 248/249 as byte-identical copies of 246/247. The auto-push
   hook means another session's work reaches `origin` the moment it commits, and
   never reaches this working copy until someone pulls. `git status -sb` after a
   fetch is the whole check — the `[behind N]` is the tell.

2. **Commit everything you want in the build** to `main`. The script archives
   from the working tree, so any uncommitted files go into the build — do NOT
   sweep in another session's WIP. Check `git status` and confirm the tree is
   what you intend. To exclude in-progress WIP from another session, build from a
   clean isolated worktree at the committed HEAD:
   `git worktree add /tmp/casberi-ship-N <commit>` and point the command's last
   line at `/tmp/casberi-ship-N/scripts/testflight.sh`.

3. **Run `scripts/verify.sh` — not just a build.** It must pass before shipping:
   ```sh
   cd ~/Developer/casberi && scripts/verify.sh
   ```

   A bare `xcodebuild … build` used to be step 3, and that is what let build 214
   ship with an **undisclosed network host** (2026-07-31). Compiling proves the
   code is valid, not that it's honest. `verify.sh` runs the static audits
   FIRST, before it builds anything, and four of them are ship gates in a way a
   compiler can never be:

   - **`network-reach-audit.sh`** — every host literal in the app must appear in
     the "What this app reaches" registry (`Model/NetworkReach.swift`, prd §205)
     or in the audit's explicit non-reach denylist. This is the privacy promise
     as a test: "no server, nothing routes through us" is only checkable because
     that registry is complete, and a bridge whose API host nobody disclosed
     makes the app's own privacy screen quietly wrong. **A missing entry ships
     as a broken promise and cannot be pulled back** — TestFlight builds are
     already on testers' devices by the time anyone notices.
   - **`catalog-sync.sh`** — the app catalog, the website shelf and the
     onboarding tiles are ONE set.
   - **`keychain-audit.py`** (prd §277) — every `SecItemAdd` must be
     `…ThisDeviceOnly` and non-synchronizable. Same shape of gate: a key
     stored with the wrong accessibility works perfectly and also rides an
     encrypted backup onto whatever device restores it, so no build, launch
     or screen sweep can ever see it.
   - **`secret-scan-selftest.py`** (prd §277) — the credential tripwire still
     hides a recovery phrase and still leaves an ordinary shopping list
     alone. Its thresholds were measured against real fixtures; a silent
     re-tune would either leak a phrase to Spotlight or quietly stop
     Spotlight finding people's notes.

   **Demo parity is a REQUIRED step of every ship (user ruling 2026-08-08) —
   never ship without checking it, and never wait to be asked**, the same
   standing the public-beta handoff itself carries. `verify.sh` runs THREE
   checks for this now (extended 2026-08-10 to "all parts of the app", user
   ruling — see CLAUDE.md's demo-mode entry; a fourth retired with the agent
   panel on 2026-08-15, see below), and they split into two kinds
   depending on whether the surface has runtime ranking to protect against,
   which is worth understanding rather than skimming past:

   - **`demo-selftest.py` checks D/E** (static, always hard-fails) — every
     name `DemoSeedAll.seatTable` claims as a connected demo seat resolves to
     a real `BridgeCatalog.offers` entry and has an actual seeded row. The
     CATALOG-NAME half: a bridge that gets renamed or retired, or a demo seat
     added with nothing behind it, fails the build outright.
   - **`demo-selftest.py` check F** (static, always hard-fails) — every
     `FeedScreen.Shape` case (the room-rendering taxonomy) has a seeded
     source that maps to it. Shape assignment is a pure function of a
     source's name with no ranking involved, so unlike the check below it
     can be proven from source text alone.
   - **~~The "Demo panel figure-kind coverage" step~~ — RETIRED 2026-08-15
     (prd §386p), and worth knowing it existed.** It ran the furnished demo
     through the real agent-panel composer and checked every
     `AgentPanel.Figure` case actually drew — the widest fan-in figure-kind
     check in the tree, and it found a real bug on its first real run
     (`runway` never drew because `CloudflareRunwaySource.compose` needed a
     `CloudflareEstateStore` snapshot nothing had ever seeded, 2026-08-08).
     It went with the agent panel: with no surface drawing many rooms'
     figures at once there is nothing left to run it over. The chip peek
     draws ONE room's figure on long-press, through the same
     `RoomFigure.roomFigure` chain, which `agent-panel-selftest.sh` compiles
     whole. **This is a real subtraction in ship coverage, not a cleanup** —
     if a many-figure surface is ever built again, rebuild this step with it.
     Its WARN-only design is the lesson to carry forward: the panel ranked
     and capped its cards, so a kind that genuinely composed could still
     lose one run's race (measured: PostHog's `curve` present in two runs,
     absent in a third, identical build), and a hard fail there would have
     been the cries-wolf class this repo's audits avoid on purpose.
   - **The "Demo room-head coverage" step**, in the simulator tail — runs
     `-roomInsightProbe <Source>` for each of the ten `FeedScreen.SourceHead`
     cases (Cloudflare's runway, Stripe, PostHog, Apple Wallet, Circle x402,
     App Store Connect, Cursor, Peer, Privacy Pools, Gnosis Pay) and checks
     each one's own head actually composes. **HARD FAIL, unlike the panel
     check above** — a room head has no ranking or cap to compete against
     (`sourceHead(_:)` gates one source at a time, so exactly one candidate
     is ever asked), so a demo corpus that can make a head compose makes it
     compose every single run; an absence is a real gap, not ranking noise.
     Found SIX real gaps on its first run (2026-08-10): Peer/Privacy Pools
     seeded rows carrying `"demo:"`-prefixed refs instead of the real
     bridges' own ref shapes; PostHog seeding readings but no watch row (and
     the readings never stamped `fetchedAt`); Apple Wallet's bespoke
     `connected` flag never being set; App Store Connect's head gating on a
     real Keychain credential a demo must never fake (fixed by widening the
     gate for `DemoMode.isActive` and seeding `ASCState` directly); and
     Cursor's seeded runs never stamping `authorHandle`, the field the head
     groups repos on. All six render as one silent "no card" from outside —
     exactly why this step exists rather than trusting a screenshot.

   None of the four checks require remembering to update the demo when
   something new ships elsewhere — see CLAUDE.md's demo-mode entry for what
   they do and don't cover (catalog/rendering consistency for the surfaces
   they name, not "every new feature must appear in the demo"; a bridge
   gaining a capability with no textual signature — a new figure kind, a new
   field a room head reads — still needs the human step, `-roomInsightProbe`/
   `-agentOpenProbe` against the demo corpus after a rendering change).

   Running these individually is not a substitute for `verify.sh`, and
   picking the audits you happen to remember is exactly the failure mode: the
   Stripe ship ran `catalog-sync.sh` and the liveness audit by hand, both
   passed, and the reach audit — the one that would have caught the real gap —
   was simply never invoked. **Run the whole script.**

   If `verify.sh` is too slow for the moment (it reinstalls and cold-launches
   ten times), the minimum acceptable gate is every static audit at its head,
   not a subset:
   ```sh
   LAUNCH_CYCLES=0 scripts/verify.sh
   ```

4. **Re-check `git status` IMMEDIATELY before each archive, not once at the
   start.** Both ship scripts `rsync` the WORKING TREE, so whatever is
   uncommitted at archive time goes into the build — and another Claude session
   editing this repo can dirty the tree in the minutes between your commit and
   your archive. That happened on 2026-07-31: the tree was clean when build 214
   was committed, and by the time build 215 rsynced it carried two files of
   another session's in-progress work that nobody reviewed.

   When any other session might be active, don't rely on timing — **archive from
   a clean worktree at the committed HEAD**, which makes the question
   unanswerable-by-construction rather than a race you have to win:
   ```sh
   git worktree add /tmp/casberi-ship-<n> <commit>
   # …then point the ship command's last line at /tmp/casberi-ship-<n>/scripts/testflight.sh
   git worktree remove /tmp/casberi-ship-<n>   # when the upload is done
   ```

5. **Bump the build number and commit it** so it sticks and never collides
   across sessions. Either let the script bump (omit `SKIP_BUMP`) then commit
   `Casberi/Casberi.xcodeproj/project.pbxproj`, or bump + commit first and pass
   `SKIP_BUMP=1`. Commit message: `Bump build number to N for TestFlight (internal)`.

6. **Run the one command above.** When it finishes you'll see `✓ Uploaded`.

7. **Don't re-check the App Store Connect API too soon.** Processing runs from
   ~5 min to over an hour. A build missing from the list right after upload is
   almost always still processing, not rejected.

## Notes

- Internal testers automatically see the latest processed build — no external
  Beta App Review is needed for the internal group.
- `-derivedDataPath` workarounds are only needed in the deprecated iCloud copy,
  not in `~/Developer/casberi`.
- The one-time setup for generating the API key (App Store Connect → Users and
  Access → Integrations → App Store Connect API, App Manager role) is documented
  in the header of `scripts/testflight.sh`.
