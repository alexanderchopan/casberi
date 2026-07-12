# Shipping a TestFlight build (handoff)

Point any session at this file to ship a Casberi build to TestFlight the same
way we always do. The whole process is encapsulated in `scripts/testflight.sh`
— it bumps the build number across all targets, archives Release **unsigned**,
then signs + uploads for App Store distribution.

## Secrets — read this first

- **The `.p8` API key is the only secret.** It grants upload access. It is
  **never** committed, never copied or read by Claude. You (the user) stage it
  yourself and give the session only its file path.
- **Key ID and Issuer ID are identifiers, not standalone secrets** — but they
  identify your App Store Connect API access, so they stay out of committed
  files too. Pass all three at run time as env vars (below).
- The only distribution value baked into the repo is `teamID 35428TQK3S` in
  `scripts/exportOptions.plist` — that's a public identifier and has to be there.

## Steps

1. **Work only in `~/Developer/casberi`** — the canonical repo. Never the iCloud
   copy (its xattrs break codesign).

2. **Commit everything you want in the build** to `main`. The script archives
   from the working tree, so any uncommitted files go into the build — do NOT
   sweep in another session's WIP. Check `git status` and confirm the tree is
   what you intend. The build-number bump especially must be committed so
   numbers never collide across sessions.

3. **Build-clean check first** — must succeed before shipping:
   ```sh
   cd ~/Developer/casberi && xcodebuild -project Casberi/Casberi.xcodeproj -scheme Casberi \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
   ```

4. **Ask the user to stage the App Store Connect API key.** The user copies the
   `.p8` to a path themselves. The session receives only three values:
   `ASC_KEY_ID`, `ASC_ISSUER_ID`, and the key file path — never the key contents.

5. **Run the ship script:**
   ```sh
   cd ~/Developer/casberi && \
   ASC_KEY_ID=<key id> \
   ASC_ISSUER_ID=<issuer id> \
   ASC_KEY_PATH="<path to AuthKey_XXXX.p8>" \
   scripts/testflight.sh
   ```
   (Set `SKIP_BUMP=1` in front to re-upload without bumping the build number —
   e.g. a failed upload retry.)

6. **Commit the build-number bump** (`Casberi/Casberi.xcodeproj/project.pbxproj`)
   so the number sticks:
   `Bump build number to N for TestFlight (internal)`.

7. **Delete the key** afterward if it was placed anywhere temporary.

8. **Don't re-check the App Store Connect API too soon.** Processing runs from
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
