#!/bin/bash
# Wrap a REAL screen recording in the editorial App Store frame.
#
#   ./frame-preview.sh <recording.mp4> <out.mp4> "<Headline>" "<sub>"
#
# Apple-safe by construction: the genuine device capture is the substance and
# fills ~80% of the canvas; the frame only adds a background + caption, which
# app preview guidelines allow. Output is 886x1920 (the 6.5" preview size).
set -e
REC="$1"; OUT="$2"; HEAD="$3"; SUB="$4"
DIR="$(cd "$(dirname "$0")" && pwd)"
W=886; H=1920

# Geometry — mirrors build-appstore-shot.js exactly (S = W/1320) so the
# previews and the screenshots share one layout.
S=$(python3 -c "print($W/1320)")
SHOTW=$(python3 -c "print(round(1080*$S))")
SHOTTOP=$(python3 -c "print(round(560*$S))")
RADIUS=$(python3 -c "print(round(56*$S))")
X=$(python3 -c "print(round(($W-$SHOTW)/2))")

# Source aspect -> overlay height
SRCW=$(ffprobe -v error -select_streams v -show_entries stream=width  -of default=nw=1:nk=1 "$REC")
SRCH=$(ffprobe -v error -select_streams v -show_entries stream=height -of default=nw=1:nk=1 "$REC")
SHOTH=$(python3 -c "print(round($SHOTW*$SRCH/$SRCW))")
DUR=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$REC")

# 1. Background: the editorial frame, with a dark plate standing in for the
#    screen so the composer draws its radius + offset shadow in the right place.
python3 - "$SRCW" "$SRCH" <<'PY'
import sys
from PIL import Image
w,h=int(sys.argv[1]),int(sys.argv[2])
Image.new("RGB",(w,h),(11,13,18)).save("/tmp/_plate.png")
PY
node "$DIR/build-appstore-shot.js" /tmp/_plate.png "$HEAD" "$SUB" $W $H "#2E63FF" blue >/dev/null
node "$DIR/render.js" clip-appstore-shot.html --size=${W}x${H} --preview --spots=0 >/dev/null 2>&1
cp "$(ls "$DIR"/frames/*.png | head -1)" /tmp/_bg.png

# 2. Rounded-corner alpha mask for the recording
python3 - "$SHOTW" "$SHOTH" "$RADIUS" <<'PY'
import sys
from PIL import Image, ImageDraw
w,h,r=int(sys.argv[1]),int(sys.argv[2]),int(sys.argv[3])
m=Image.new("L",(w,h),0)
ImageDraw.Draw(m).rounded_rectangle([0,0,w-1,h-1],radius=r,fill=255)
m.save("/tmp/_mask.png")
PY

# 3. Composite: real capture over the frame, rounded, clipped by the canvas
ffmpeg -y -v error -loop 1 -i /tmp/_bg.png -i "$REC" -loop 1 -i /tmp/_mask.png \
  -filter_complex "[1:v]scale=${SHOTW}:${SHOTH},setsar=1[v];[v][2:v]alphamerge[va];[0:v][va]overlay=${X}:${SHOTTOP}:shortest=1,format=yuv420p[o]" \
  -map "[o]" -t "$DUR" -c:v libx264 -profile:v high -crf 20 -preset veryfast -r 30 -movflags +faststart "$OUT"

echo "  $(basename "$OUT")  $(ffprobe -v error -select_streams v -show_entries stream=width,height -of csv=p=0:s=x "$OUT")  $(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT" | cut -d. -f1)s"
