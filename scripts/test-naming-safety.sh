#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd -P)"
build_dir="$repo_dir/work/security-review/build"
mkdir -p "$build_dir"
xcrun swiftc -swift-version 6 "$repo_dir"/Sources/MacRenameCore/Naming/*.swift "$repo_dir"/Sources/MacRenameCore/Safety/*.swift "$repo_dir"/Tests/StandaloneSecurity/*.swift -o "$build_dir/security-regressions"
"$build_dir/security-regressions"
