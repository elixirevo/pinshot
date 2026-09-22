#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
output_dir="${1:-build/icons}"

# Command Line Tools does not include actool or Icon Composer. Use the
# installed Xcode without changing the user's global xcode-select setting.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    export DEVELOPER_DIR="$(xcode-select -p)"
    if [[ "$DEVELOPER_DIR" == /Library/Developer/CommandLineTools ]]; then
        export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    fi
fi
ictool="$DEVELOPER_DIR/../Applications/Icon Composer.app/Contents/Executables/ictool"
if [[ ! -x "$DEVELOPER_DIR/usr/bin/actool" || ! -x "$ictool" ]]; then
    echo "Icon compilation requires Xcode 26 or later with Icon Composer. Set DEVELOPER_DIR to its Contents/Developer directory." >&2
    exit 1
fi

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

xcrun actool pinshot.icon \
    --compile "$temp_dir" \
    --output-format human-readable-text --notices --warnings --errors \
    --output-partial-info-plist "$temp_dir/Info.plist" \
    --app-icon pinshot --include-all-app-icons \
    --enable-on-demand-resources NO --development-region en \
    --target-device mac --minimum-deployment-target 12.0 --platform macosx

"$ictool" pinshot.icon --export-image \
    --output-file "$temp_dir/icon.png" \
    --platform macOS --rendition Default --width 1024 --height 1024 --scale 1

mkdir -p "$output_dir"
cp "$temp_dir/Assets.car" "$temp_dir/pinshot.icns" "$output_dir/"
cp "$temp_dir/icon.png" icon.png
