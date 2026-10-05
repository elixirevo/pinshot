#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ARCH:?Release architecture is required}"
: "${APP_VERSION:?Release version is required}"
: "${APP_BUILD:?Release build number is required}"
: "${DIST_DIR:?Release output directory is required}"
: "${APP_PATH:?Release app path is required}"
make sparkle
make all ARCH="$ARCH" VERSION="$APP_VERSION" BUILD="$APP_BUILD" OUT_DIR="$DIST_DIR"
test -x "$APP_PATH/Contents/MacOS/PinShot"
if [[ -n "${DSYM_PATH:-}" ]]; then
  ditto "$DIST_DIR/PinShot.app.dSYM" "$DSYM_PATH"
fi
