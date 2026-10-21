#!/bin/bash
set -euo pipefail

# Builds into an explicit output folder. This script never installs an app,
# changes Services preferences, removes quarantine, or renames user documents.
project_root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 /absolute/output/directory" >&2
    exit 2
fi
output_directory="$1"
if [[ "$output_directory" != /* ]]; then
    echo "The output directory must be absolute." >&2
    exit 2
fi
application_path="$output_directory/Naming Assistant.app"
if [[ -e "$application_path" || -L "$application_path" ]]; then
    echo "Refusing to replace an existing application: $application_path" >&2
    exit 1
fi

cd "$project_root"
swift build --build-system native --configuration release --product NamingAssistant
binary_directory="$(swift build --build-system native --configuration release --show-bin-path)"
mkdir -p "$application_path/Contents/MacOS" "$application_path/Contents/Resources"
cp "$binary_directory/NamingAssistant" "$application_path/Contents/MacOS/NamingAssistant"
# Remove local source/object paths from Mach-O debug records before distribution.
/usr/bin/strip -S "$application_path/Contents/MacOS/NamingAssistant"
if LC_ALL=C /usr/bin/grep -aqF -- "$project_root/" "$application_path/Contents/MacOS/NamingAssistant" ||
   { [[ -n "${HOME:-}" && "$HOME" != / ]] && LC_ALL=C /usr/bin/grep -aqF -- "$HOME/" "$application_path/Contents/MacOS/NamingAssistant"; }; then
    echo "Refusing to package an executable containing local build/home paths." >&2
    exit 1
fi
cp packaging/NamingAssistant-Info.plist "$application_path/Contents/Info.plist"
cp LICENSE "$application_path/Contents/Resources/MacRename-LICENSE.txt"
mkdir -p "$application_path/Contents/Resources/zh_CN.lproj" "$application_path/Contents/Resources/zh-Hans.lproj"
cp packaging/zh_CN.lproj/ServicesMenu.strings "$application_path/Contents/Resources/zh_CN.lproj/ServicesMenu.strings"
cp packaging/zh_CN.lproj/ServicesMenu.strings "$application_path/Contents/Resources/zh-Hans.lproj/ServicesMenu.strings"
if [[ -f NAMING_ASSISTANT.md ]]; then
    cp NAMING_ASSISTANT.md "$application_path/Contents/Resources/Guide.md"
fi
plutil -lint "$application_path/Contents/Info.plist"
codesign --force --sign - --options runtime "$application_path"
codesign --verify --strict "$application_path"
echo "Local ad-hoc signed app: $application_path"
echo "This is not a notarized Developer ID release. No system settings were changed."
