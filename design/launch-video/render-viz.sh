#!/usr/bin/env bash
# Build + render the visualizations reel end-to-end (Linux sandbox friendly:
# pre-installed Chromium via CHROME_BIN, PyAV for the mp4 — no Xcode, no
# system ffmpeg needed).
#
#   design/launch-video/render-viz.sh            # full render -> out-viz/
#   design/launch-video/render-viz.sh --preview  # 10 spot-check frames only
set -euo pipefail
cd "$(dirname "$0")"

export NODE_PATH="${NODE_PATH:-/opt/node22/lib/node_modules}"
export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}"
if [ -z "${CHROME_BIN:-}" ] && [ -x /opt/pw-browsers/chromium-1194/chrome-linux/chrome ]; then
  export CHROME_BIN=/opt/pw-browsers/chromium-1194/chrome-linux/chrome
fi

node build-viz-reel.js

if [ "${1:-}" = "--preview" ]; then
  node render-frames.js clip-viz-reel.html --size=1920x1080 --preview
  echo "preview frames -> frames-viz/"
  exit 0
fi

node render-frames.js clip-viz-reel.html --size=1920x1080 --fps=30 --poster=3.7
mkdir -p out-viz
python3 frames-to-mp4.py frames-viz out-viz/casberi-viz-reel.mp4 30
cp frames-viz/poster.jpg out-viz/casberi-viz-reel-poster.jpg
echo "done -> out-viz/"
ls -la out-viz/
