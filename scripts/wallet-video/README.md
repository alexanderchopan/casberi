# Wallet features — walkthrough video

A self-contained animated walkthrough of Casberi's **Wallet** feature, rendered
to a shareable video (Instagram/X story aspect, 1080×1920). Useful for the
launch thread, the website, or App Store previews.

It is **not** a simulator screen recording — those need Xcode/`simctl` on a Mac.
This renders a faithful HTML mock of `WalletScreen` (real design tokens, copy,
and flow) in headless Chromium and captures it as it auto-plays, so it works
anywhere Node + Chromium run (including Linux CI / this cloud session).

## What it shows

Watch vitalik.eth in one tap → live holdings treemap → value line → NFT shelf →
onchain activity → pin to Home → a second wallet and the combined "Across your
wallets" view. Closes on *Watch-only. On-device.*

## Run

```sh
scripts/wallet-video/render.sh
```

Outputs:
- `out/casberi-wallet.webm` — Playwright's native (ffmpeg-backed) recording.
- `out/casberi-wallet.mp4` — H.264, QuickTime-ready (needs `ffmpeg` on PATH, or
  `pip install av`).

## Files

- `wallet-demo.html` — the animated app + director timeline (edit this to change
  scenes, copy, or pacing). Design tokens are ported from
  `Casberi/Casberi/Design/DesignTokens.swift`; keep them in sync if the app's
  palette changes.
- `render.mjs` — headless-Chromium recorder (`window.__done` gates the capture).
- `transcode.py` — webm → H.264 mp4 via PyAV, used when no system `ffmpeg`.
- `render.sh` — installs deps, records, transcodes.

## Sandbox notes (this cloud environment)

- No Xcode/simulator — hence the HTML approach.
- Chromium is pre-installed under `/opt/pw-browsers`; `render.sh` pins
  `CHROME_BIN` to the `chromium-1194` build (Playwright's own revision differs).
- The bundled ffmpeg is VP8-only, so the mp4 is produced with PyAV instead.
