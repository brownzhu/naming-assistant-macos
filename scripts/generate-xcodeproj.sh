#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is not installed. Install with: brew install xcodegen" >&2
  exit 1
fi

xcodegen generate
echo "Generated QuickRename.xcodeproj. Open with: open QuickRename.xcodeproj"
