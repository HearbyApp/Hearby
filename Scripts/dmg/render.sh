#!/bin/bash
# Renders background.html into the 1x and 2x PNGs that Scripts/release.sh
# combines into the DMG window background. Needs Google Chrome; run it after
# editing background.html and commit both PNGs.
set -euo pipefail
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for scale in 1 2; do
  out="background.png"
  [ "$scale" -eq 2 ] && out="background@2x.png"
  "$CHROME" --headless --disable-gpu --hide-scrollbars \
    --force-device-scale-factor="$scale" --window-size=660,400 \
    --screenshot="$PWD/$out" "file://$PWD/background.html" 2>/dev/null
  echo "wrote Scripts/dmg/$out"
done
