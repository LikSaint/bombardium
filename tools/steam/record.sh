#!/bin/zsh
# Records one Capture plan to <outdir>/<plan>.avi (+ PNG screenshots in <outdir>/shots).
#   tools/steam/record.sh <plan> <outdir> [lang]
# The movie size comes from the project's viewport settings (960x720 in the real game), so
# the recording runs from a scratch copy whose override.cfg makes it 1920x1080 with the
# same on-screen scale. The Godot window must stay in front while it records (macOS stops
# drawing a covered window), so this keeps pulling it to the front.
set -e
PLAN=$1; OUT=$2; LANG_CODE=${3:-en}
SRC=${0:A:h:h:h}
COPY=$OUT/project
mkdir -p $OUT/shots
rsync -a --delete --exclude .git --exclude build --exclude .claude $SRC/ $COPY/
cat > $COPY/override.cfg <<CFG
[display]
window/size/viewport_width=1920
window/size/viewport_height=1080
window/size/mode=0
window/stretch/scale=1.5
CFG
/Applications/Godot.app/Contents/MacOS/Godot --path $COPY res://tools/steam/Capture.tscn \
  --windowed --resolution 1920x1080 --write-movie $OUT/$PLAN.avi --fixed-fps 30 \
  -- plan=$PLAN shots=$OUT/shots lang=$LANG_CODE > $OUT/$PLAN.log 2>&1 &
PID=$!
while kill -0 $PID 2>/dev/null; do
  osascript -e "tell application \"System Events\" to set frontmost of first process whose unix id is $PID to true" 2>/dev/null || true
  sleep 3
done
tail -4 $OUT/$PLAN.log
