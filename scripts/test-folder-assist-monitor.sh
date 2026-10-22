#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd -P)"
build_dir="$repo_dir/work/folder-assist-monitor/build"
mkdir -p "$build_dir"

# A separate core module keeps the production monitor's normal import intact.
# These sources have no package dependencies, UI, network or account access.
xcrun swiftc -swift-version 6 -parse-as-library -emit-library -emit-module \
    -module-name MacRenameCore -emit-module-path "$build_dir/MacRenameCore.swiftmodule" \
    "$repo_dir"/Sources/MacRenameCore/Naming/*.swift \
    "$repo_dir"/Sources/MacRenameCore/Safety/*.swift \
    -Xlinker -install_name -Xlinker @rpath/libMacRenameCore.dylib \
    -o "$build_dir/libMacRenameCore.dylib"
xcrun swiftc -swift-version 6 -parse-as-library \
    -I "$build_dir" -L "$build_dir" -lMacRenameCore \
    -Xlinker -rpath -Xlinker @executable_path \
    "$repo_dir/Sources/NamingAssistantApp/FolderAssistMonitor.swift" \
    "$repo_dir/Tests/StandaloneFolderAssist/MonitorRegression.swift" \
    -o "$build_dir/folder-assist-monitor-regressions"
"$build_dir/folder-assist-monitor-regressions"
