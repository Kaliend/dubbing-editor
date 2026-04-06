#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="DubbingEditor"
BUILD_CONFIG="debug"
SHOULD_OPEN=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release)
            BUILD_CONFIG="release"
            shift
            ;;
        --no-open)
            SHOULD_OPEN=0
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Usage: $0 [--release] [--no-open]" >&2
            exit 2
            ;;
    esac
done

ICON_PATH="$ROOT_DIR/assets/AppIcon.icns"
if [[ ! -f "$ICON_PATH" ]]; then
    echo "App icon not found at $ICON_PATH. Building icon assets..."
    "$ROOT_DIR/scripts/build_app_icon.sh"
fi

echo "Building $APP_NAME ($BUILD_CONFIG)..."
swift build -c "$BUILD_CONFIG"

APP_BUNDLE="$ROOT_DIR/.build/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLIST_PATH="$CONTENTS_DIR/Info.plist"
BINARY_PATH="$ROOT_DIR/.build/$BUILD_CONFIG/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BINARY_PATH" "$MACOS_DIR/$APP_NAME"
cp "$ICON_PATH" "$RESOURCES_DIR/AppIcon.icns"

cat > "$PLIST_PATH" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>DubbingEditor</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>local.dubbingeditor.bundle</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>DubbingEditor</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>DubbingEditor needs microphone/speech access to generate Smart Auto-TC from audio.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>DubbingEditor uses on-device speech recognition to generate Smart Auto-TC locally.</string>
</dict>
</plist>
PLIST

# Ad-hoc signing keeps app launch behavior consistent for local bundle runs.
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true

echo "App bundle ready: $APP_BUNDLE"
if [[ $SHOULD_OPEN -eq 1 ]]; then
    open "$APP_BUNDLE"
fi
