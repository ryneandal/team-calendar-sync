#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

configuration="${1:-release}"
if [[ "$configuration" != "release" && "$configuration" != "debug" ]]; then
    echo "Usage: bash scripts/build-app.sh [release|debug]" >&2
    exit 1
fi

swift build -c "$configuration"
binary_directory="$(swift build -c "$configuration" --show-bin-path)"
app_directory="$PWD/build/Team Calendar.app"
rm -rf "$app_directory"
mkdir -p "$app_directory/Contents/MacOS" "$app_directory/Contents/Resources"
cp "$binary_directory/TeamCalendar" "$app_directory/Contents/MacOS/TeamCalendar"
cp App/Info.plist "$app_directory/Contents/Info.plist"
# SwiftPM locates embedded resource bundles in Bundle.main.resourceURL.
for resource in "$binary_directory"/*.bundle; do
    [[ -d "$resource" ]] || continue
    cp -R "$resource" "$app_directory/Contents/Resources/"
done
swift scripts/make-icon.swift "$PWD/build/AppIcon.iconset"
iconutil -c icns "$PWD/build/AppIcon.iconset" -o "$app_directory/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$app_directory"
echo "Built: $app_directory"
