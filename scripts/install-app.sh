#!/usr/bin/env bash
# Install QuickRename.app into /Applications (or ~/Applications) so Launch
# Services keeps a stable path for the embedded Finder Sync extension.
# Usage:
#   ./scripts/install-app.sh                # Debug, ~/Applications
#   ./scripts/install-app.sh release        # Release, ~/Applications
#   ./scripts/install-app.sh release system # Release, /Applications (sudo)
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
LOCATION="${2:-user}"

case "$CONFIG" in
  debug|Debug)     CONFIG=Debug   ;;
  release|Release) CONFIG=Release ;;
  *) echo "Unknown config: $CONFIG (expected debug|release)" >&2; exit 2 ;;
esac

case "$LOCATION" in
  user)   DEST="$HOME/Applications" ;;
  system) DEST="/Applications"      ;;
  *) echo "Unknown location: $LOCATION (expected user|system)" >&2; exit 2 ;;
esac

mkdir -p "$DEST"

echo "Building Quick Rename ($CONFIG)..."
xcodebuild \
  -project QuickRename.xcodeproj \
  -scheme QuickRename \
  -configuration "$CONFIG" \
  -destination 'platform=macOS' \
  build >/dev/null

BUILT="$(ls -dt ~/Library/Developer/Xcode/DerivedData/QuickRename-*/Build/Products/"$CONFIG"/QuickRename.app 2>/dev/null | head -1)"

if [[ -z "$BUILT" || ! -d "$BUILT" ]]; then
  echo "Could not locate built QuickRename.app in DerivedData." >&2
  exit 1
fi

TARGET="$DEST/QuickRename.app"

# Check whether the embedded extension is signed with a real identity.
# Ad-hoc signatures (authority "-") won't register with Finder.
if codesign -dvv "$BUILT/Contents/PlugIns/FinderExtension.appex" 2>&1 \
   | grep -q 'Authority=-'; then
  echo
  echo "  ⚠️  The Finder extension is signed ad-hoc."
  echo "      Finder will ignore it. Open QuickRename.xcodeproj, select the"
  echo "      QuickRename and FinderExtension targets, and set Signing & Capabilities"
  echo "      → Team to your Apple ID / Personal Team. Rerun this script after."
  echo
fi

echo "Installing to $TARGET ..."
if [[ "$LOCATION" == "system" ]]; then
  sudo rm -rf "$TARGET"
  sudo cp -R "$BUILT" "$TARGET"
else
  rm -rf "$TARGET"
  cp -R "$BUILT" "$TARGET"
fi

# Re-register with Launch Services and restart Finder so the extension shows up.
LSREG=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
"$LSREG" -f "$TARGET" >/dev/null 2>&1 || true
"$LSREG" -f "$TARGET/Contents/PlugIns/FinderExtension.appex" >/dev/null 2>&1 || true
killall Finder 2>/dev/null || true

cat <<EOF

  ✓ Installed QuickRename.app to $TARGET

  Next steps to light up the Finder right-click menu:
    1. System Settings → Privacy & Security → Extensions → Added Extensions
       (older macOS: General → Login Items & Extensions → Finder)
       Toggle "Quick Rename Finder Extension" on.
    2. Right-click any file in Finder — "Rename with Quick Rename" should appear
       near the bottom of the context menu.

  Open Extensions settings now?  (Ctrl-C to skip)
EOF
read -r
open "x-apple.systempreferences:com.apple.ExtensionsPreferences" 2>/dev/null \
  || open "/System/Library/PreferencePanes/Extensions.prefPane" 2>/dev/null \
  || true
