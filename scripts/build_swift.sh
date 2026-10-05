#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
product="${1:-PinShot}"
architecture="${ARCH:-$(uname -m)}"
configuration="${CONFIGURATION:-release}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
arguments=(--scratch-path ".build/spm-$architecture" --arch "$architecture" -c "$configuration"
  --sdk "$sdk_path" -Xswiftc -enable-testing
  -Xlinker -platform_version -Xlinker macos -Xlinker 13.0 -Xlinker "$sdk_version"
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks)
xcrun swift build --product "$product" "${arguments[@]}"
binary_dir="$(xcrun swift build --show-bin-path "${arguments[@]}")"
if [[ "$product" == ScreenshotTests ]]; then
  "$binary_dir/ScreenshotTests" "${@:2}"
  exit
fi
app_bundle="${OUT_DIR:-build}/PinShot.app"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources" "$app_bundle/Contents/Frameworks"
cp "$binary_dir/PinShot" "$app_bundle/Contents/MacOS/PinShot"
for module in MacAppSettings MacAppOnboarding MacAppMenuBar MacAppMainMenu; do
  bundle="MacAppEssentials_${module}.bundle"
  test -d "$binary_dir/$bundle"
  ditto "$binary_dir/$bundle" "$app_bundle/Contents/Resources/$bundle"
done
ditto "$binary_dir/PinShot_PinShotApp.bundle" "$app_bundle/Contents/Resources/PinShot_PinShotApp.bundle"
ditto "$binary_dir/Sparkle.framework" "$app_bundle/Contents/Frameworks/Sparkle.framework"
# Sentry is statically linked; its privacy manifest must still ship in our app.
cp "$binary_dir/Sentry.framework/Resources/PrivacyInfo.xcprivacy" "$app_bundle/Contents/Resources/PrivacyInfo.xcprivacy"
cp ".build/spm-$architecture/checkouts/sentry-cocoa/LICENSE.md" "$app_bundle/Contents/Resources/Sentry-LICENSE.md"
test -f "$app_bundle/Contents/Resources/PinShot_PinShotApp.bundle/Contents/Resources/SentryConfiguration.json"
if [[ "$configuration" == release ]]; then
  ditto "$binary_dir/PinShot.dSYM" "${OUT_DIR:-build}/PinShot.app.dSYM"
fi
build_info="$(xcrun vtool -show-build "$app_bundle/Contents/MacOS/PinShot")"
actual_min="$(awk '$1 == "minos" {print $2; exit}' <<< "$build_info")"
actual_sdk="$(awk '$1 == "sdk" {print $2; exit}' <<< "$build_info")"
[[ "$actual_min" == 13.0 && "$actual_sdk" == "$sdk_version" ]]
printf 'Verified minimum macOS %s / SDK %s\n' "$actual_min" "$actual_sdk"
