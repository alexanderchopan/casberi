#!/usr/bin/env bash
# Render the wallet-features walkthrough to a video.
#
#   scripts/wallet-video/render.sh
#
# Produces out/casberi-wallet.webm (Playwright's native recorder) and, when a
# usable ffmpeg/PyAV is present, out/casberi-wallet.mp4 (H.264, QuickTime-ready).
# No Xcode or simulator needed — it runs the HTML walkthrough in headless
# Chromium and captures it as it auto-plays.
set -euo pipefail
cd "$(dirname "$0")"

# 1. Playwright (browser automation + recorder). Uses the sandbox's bundled
#    Chromium when CHROME_BIN points at it; otherwise `npx playwright install`.
if [ ! -d node_modules/playwright ]; then
  npm install playwright@latest --no-audit --no-fund
fi

# Sandbox note: PLAYWRIGHT_BROWSERS_PATH + CHROME_BIN pin the pre-installed
# Chromium so no browser download is needed. On a normal machine, drop these
# and run `npx playwright install chromium` once.
export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}"
if [ -z "${CHROME_BIN:-}" ] && [ -x /opt/pw-browsers/chromium-1194/chrome-linux/chrome ]; then
  export CHROME_BIN=/opt/pw-browsers/chromium-1194/chrome-linux/chrome
fi

# 2. Record the walkthrough -> out/casberi-wallet.webm
node render.mjs

# 3. Transcode to H.264 mp4 for players that don't take webm (QuickTime, etc.).
#    Prefers a full `ffmpeg` if on PATH; falls back to PyAV (pip install av).
if command -v ffmpeg >/dev/null 2>&1; then
  ffmpeg -y -i out/casberi-wallet.webm -c:v libx264 -crf 20 -preset slow \
    -pix_fmt yuv420p -movflags +faststart out/casberi-wallet.mp4
elif python3 -c "import av" >/dev/null 2>&1; then
  python3 transcode.py out/casberi-wallet.webm out/casberi-wallet.mp4
else
  echo "note: no ffmpeg and no PyAV — leaving webm only (pip install av for mp4)"
fi

echo "done -> out/"
ls -la out/
