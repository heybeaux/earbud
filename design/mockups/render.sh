#!/bin/zsh
# Render mockup HTML files to 2x PNGs with headless Chrome.
# Usage: ./render.sh NAME[:WIDTHxHEIGHT] ...   (default 1440x900)
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for spec in "$@"; do
  name="${spec%%:*}"
  size="1440,900"
  if [[ "$spec" == *:* ]]; then size="${${spec#*:}/x/,}"; fi
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
    --window-size="$size" --virtual-time-budget=1500 \
    --screenshot="$PWD/$name.png" "file://$PWD/src/$name.html" >/dev/null 2>&1
  echo "rendered $name.png ($size)"
done
