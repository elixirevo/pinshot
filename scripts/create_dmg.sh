#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <app_bundle_path> <output_dmg_path> <volume_name> <app_name>"
  exit 1
fi

APP_BUNDLE_PATH="$1"
OUTPUT_DMG_PATH="$2"
VOLUME_NAME="$3"
APP_NAME="$4"

if [[ ! -d "$APP_BUNDLE_PATH" ]]; then
  echo "App bundle not found: $APP_BUNDLE_PATH"
  exit 1
fi

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "Installing create-dmg..."
  brew install create-dmg
fi

WORK_DIR="$(mktemp -d /tmp/pinshot-dmg.XXXXXX)"
STAGE_DIR="$WORK_DIR/stage"
BG_PATH="$WORK_DIR/background.png"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$STAGE_DIR"
cp -R "$APP_BUNDLE_PATH" "$STAGE_DIR/"

swift - "$BG_PATH" <<'SWIFT'
import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 670, height: 380)
let image = NSImage(size: size)
image.lockFocus()

let top = NSColor(calibratedRed: 0.99, green: 0.97, blue: 0.93, alpha: 1.0)
let bottom = NSColor(calibratedRed: 0.95, green: 0.92, blue: 0.86, alpha: 1.0)
NSGradient(starting: top, ending: bottom)?.draw(in: NSRect(origin: .zero, size: size), angle: 90)

NSColor(calibratedRed: 0.90, green: 0.84, blue: 0.73, alpha: 0.55).setFill()
NSBezierPath(roundedRect: NSRect(x: 22, y: 20, width: 626, height: 338), xRadius: 16, yRadius: 16).fill()

let titleStyle = NSMutableParagraphStyle()
titleStyle.alignment = .center
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 23, weight: .bold),
    .foregroundColor: NSColor(calibratedRed: 0.23, green: 0.20, blue: 0.16, alpha: 1.0),
    .paragraphStyle: titleStyle
]
"Drag PinShot.app to Applications".draw(
    in: NSRect(x: 0, y: 248, width: size.width, height: 36),
    withAttributes: titleAttrs
)

let arrowColor = NSColor(calibratedRed: 0.48, green: 0.34, blue: 0.18, alpha: 1.0)
arrowColor.setStroke()
let shaft = NSBezierPath()
shaft.lineWidth = 14
shaft.lineCapStyle = .round
shaft.move(to: NSPoint(x: 238, y: 174))
shaft.line(to: NSPoint(x: 414, y: 174))
shaft.stroke()

let head = NSBezierPath()
head.lineWidth = 14
head.lineCapStyle = .round
head.move(to: NSPoint(x: 384, y: 141))
head.line(to: NSPoint(x: 427, y: 174))
head.line(to: NSPoint(x: 384, y: 207))
head.stroke()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff) else { fatalError("Failed to render background") }
rep.size = NSSize(width: 670, height: 380) // force 72 DPI
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("Failed to encode PNG background") }
try png.write(to: output)
SWIFT

mkdir -p "$(dirname "$OUTPUT_DMG_PATH")"
rm -f "$OUTPUT_DMG_PATH"

if [[ -d "/Volumes/$VOLUME_NAME" ]]; then
  hdiutil detach "/Volumes/$VOLUME_NAME" -force >/dev/null 2>&1 || true
fi

create-dmg \
  --volname "$VOLUME_NAME" \
  --background "$BG_PATH" \
  --window-pos 120 120 \
  --window-size 670 380 \
  --icon-size 128 \
  --text-size 13 \
  --icon "$APP_NAME.app" 130 170 \
  --app-drop-link 540 170 \
  --no-internet-enable \
  "$OUTPUT_DMG_PATH" \
  "$STAGE_DIR"

echo "Created DMG: $OUTPUT_DMG_PATH"
