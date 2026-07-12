# Shipping a TestFlight build (handoff)

Point any session at this file to ship a Casberi build to TestFlight the same
way we always do. The whole process is encapsulated in `scripts/testflight.sh`
— it bumps the build number across all targets, archives Release **unsigned**,
then signs + uploads for App Store distribution.

## Credentials

The App Store Connect API access has three parts. Two are identifiers (safe to
keep here — useless on their own); the third is the private key (the only real
secret, never committed):

| Value | Store it here? | Value |
|---|---|---|
| `ASC_KEY_ID` | yes | `TR287WZD72` |
| `ASC_ISSUER_ID` | yes | `2152ec98-0a7c-477a-9c4a-e1c478a3a106` |
| `.p8` private key | **NO — never commit** | you stage it at `/tmp/asc.p8` each ship |
| `teamID` | already in `exportOptions.plist` | `35428TQK3S` |

Only the `.p8` grants upload access, and it's worthless to anyone without the
matching private key. So the one manual step per ship is putting your
`AuthKey_TR287WZD72.p8` at `/tmp/asc.p8`. The script deletes it after upload,
which is why it won't be there next time.

## Who does what (the whole ritual)

**The user's ONLY job is to stage the key.** Paste exactly this one line in a
terminal — nothing else is needed from the user:

```sh
cp "/Users/alexanderchopan/Downloads/AuthKey_TR287WZD72.p8" /tmp/asc.p8
```

(Your `.p8` lives in `~/Downloads`. If you keep it elsewhere, change the source
path — the destination is always `/tmp/asc.p8`.)

**Claude does everything else** once the user says the key is staged: commit the
intended work, bump + commit the build number, and run the ship via the Bash
tool. Claude never copies or reads the `.p8` — it only runs the script, which
reads the key from `/tmp/asc.p8`. The command Claude runs (from the canonical
repo, or a clean isolated worktree to exclude another session's WIP):

```sh
ASC_KEY_ID=TR287WZD72 \
ASC_ISSUER_ID=2152ec98-0a7c-477a-9c4a-e1c478a3a106 \
ASC_KEY_PATH=/tmp/asc.p8 \
SKIP_BUMP=1 \
~/Developer/casberi/scripts/testflight.sh
```

- `SKIP_BUMP=1` reuses the already-committed build number. Omit it to let the
  script bump the number itself (then commit the bump afterward — step 4).
- After `✓ Uploaded`, Claude wipes the key: `rm -f /tmp/asc.p8`.

## Steps (what Claude prepares before that command)

1. **Work only in `~/Developer/casberi`** — the canonical repo. Never the iCloud
   copy (its xattrs break codesign).

2. **Commit everything you want in the build** to `main`. The script archives
   from the working tree, so any uncommitted files go into the build — do NOT
   sweep in another session's WIP. Check `git status` and confirm the tree is
   what you intend. To exclude in-progress WIP from another session, build from a
   clean isolated worktree at the committed HEAD:
   `git worktree add /tmp/casberi-ship-N <commit>` and point the command's last
   line at `/tmp/casberi-ship-N/scripts/testflight.sh`.

3. **Build-clean check first** — must succeed before shipping:
   ```sh
   cd ~/Developer/casberi && xcodebuild -project Casberi/Casberi.xcodeproj -scheme Casberi \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
   ```

4. **Bump the build number and commit it** so it sticks and never collides
   across sessions. Either let the script bump (omit `SKIP_BUMP`) then commit
   `Casberi/Casberi.xcodeproj/project.pbxproj`, or bump + commit first and pass
   `SKIP_BUMP=1`. Commit message: `Bump build number to N for TestFlight (internal)`.

5. **Run the one command above.** When it finishes you'll see `✓ Uploaded`.

6. **Don't re-check the App Store Connect API too soon.** Processing runs from
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
