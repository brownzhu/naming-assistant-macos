#!/usr/bin/env bash
# Capture the front QuickRename window to Resources/screenshots/<name>.png
# at an App Store-accepted size.
#
# Usage:   ./scripts/screenshots/capture.sh hero               # 1440x900 points
#          ./scripts/screenshots/capture.sh exif 1280x800      # 1280x800 points
#
# All four App Store macOS screenshot slots (1280x800, 1440x900, 2560x1600,
# 2880x1800) are 16:10 — same aspect at different densities. On a Retina
# display, capturing a 1440x900 point window produces a 2880x1800 PNG, the
# highest-quality slot. On non-Retina, the same window produces a 1440x900
# PNG. Either way Apple accepts it.

set -euo pipefail

cd "$(dirname "$0")/../.."

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: capture.sh <screenshot-name> [WIDTHxHEIGHT]" >&2
  echo "       size defaults to 1440x900 (becomes 2880x1800 PNG on Retina)" >&2
  exit 2
fi

NAME="$1"
SIZE="${2:-1440x900}"

if [[ ! "$SIZE" =~ ^([0-9]+)x([0-9]+)$ ]]; then
  echo "size must be WIDTHxHEIGHT, e.g. 1440x900" >&2
  exit 2
fi
WIDTH="${BASH_REMATCH[1]}"
HEIGHT="${BASH_REMATCH[2]}"

OUT="Resources/screenshots/${NAME}.png"
mkdir -p "$(dirname "$OUT")"

# Bring QuickRename to the front
osascript -e 'tell application "QuickRename" to activate' >/dev/null
sleep 0.8

# Resize the front window to the target size in points. AppKit will clamp
# to MainView's minWidth/minHeight if asked smaller — that's surfaced below.
osascript <<AS >/dev/null
tell application "System Events"
    tell process "QuickRename"
        if (count of windows) > 0 then
            set size of window 1 to {$WIDTH, $HEIGHT}
        end if
    end tell
end tell
AS
sleep 0.4

# Read back the actual window bounds in screen points. Returns "x,y,w,h".
BOUNDS="$(osascript <<'AS' 2>/dev/null
tell application "System Events"
    tell process "QuickRename"
        if (count of windows) is 0 then return ""
        set p to position of window 1
        set s to size of window 1
        return ((item 1 of p) as text) & "," & ((item 2 of p) as text) ¬
            & "," & ((item 1 of s) as text) & "," & ((item 2 of s) as text)
    end tell
end tell
AS
)"

if [[ -z "$BOUNDS" ]]; then
  echo "Could not find a QuickRename window. Is the app running and visible?" >&2
  echo "(If you've never granted Accessibility permission, System Settings →" >&2
  echo " Privacy & Security → Accessibility → enable Terminal/iTerm.)" >&2
  exit 1
fi

IFS=, read -r _ _ ACTUAL_W ACTUAL_H <<< "$BOUNDS"
if [[ "$ACTUAL_W" != "$WIDTH" || "$ACTUAL_H" != "$HEIGHT" ]]; then
  echo "  ⚠️  Window settled at ${ACTUAL_W}x${ACTUAL_H} (asked for ${WIDTH}x${HEIGHT})." >&2
  echo "      Likely clamped by minWidth/minHeight in MainView, or by the" >&2
  echo "      screen. Capture proceeds at the actual size." >&2
fi

# -o = no shadow (cleaner App Store shot), -x = silent, -R = region
screencapture -o -x -R "$BOUNDS" "$OUT"

# Report actual pixel dimensions so you know which App Store slot it fits.
PIXELS="$(sips -g pixelWidth -g pixelHeight "$OUT" 2>/dev/null \
  | awk '/pixelWidth/ {w=$2} /pixelHeight/ {h=$2} END {print w "x" h}')"
echo "Wrote $OUT  pixels=$PIXELS  region=$BOUNDS"
