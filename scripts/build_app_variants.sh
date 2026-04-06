#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="DubbingEditor"
BUILD_CONFIG="release"
OUTPUT_DIR="$ROOT_DIR/dist"
ICON_PATH="$ROOT_DIR/assets/AppIcon.icns"
ARM64_SCRATCH="$ROOT_DIR/.build-arm64"
X86_64_SCRATCH="$ROOT_DIR/.build-x86_64"
ARM64_TRIPLE="arm64-apple-macosx13.0"
X86_64_TRIPLE="x86_64-apple-macosx13.0"
MINIMUM_SYSTEM_VERSION="13.0"
SKIP_BUILD=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)
            BUILD_CONFIG="debug"
            shift
            ;;
        --release)
            BUILD_CONFIG="release"
            shift
            ;;
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Usage: $0 [--debug|--release] [--skip-build]" >&2
            exit 2
            ;;
    esac
done

if [[ ! -f "$ICON_PATH" ]]; then
    echo "App icon not found at $ICON_PATH. Building icon assets..."
    "$ROOT_DIR/scripts/build_app_icon.sh"
fi

ARM64_BINARY="$ARM64_SCRATCH/arm64-apple-macosx/$BUILD_CONFIG/$APP_NAME"
X86_64_BINARY="$X86_64_SCRATCH/x86_64-apple-macosx/$BUILD_CONFIG/$APP_NAME"

if [[ $SKIP_BUILD -eq 0 ]]; then
    echo "Building arm64 variant..."
    swift build -c "$BUILD_CONFIG" --triple "$ARM64_TRIPLE" --scratch-path "$ARM64_SCRATCH"

    echo "Building x86_64 variant..."
    swift build -c "$BUILD_CONFIG" --triple "$X86_64_TRIPLE" --scratch-path "$X86_64_SCRATCH"
fi

if [[ ! -f "$ARM64_BINARY" ]]; then
    echo "Missing arm64 binary at $ARM64_BINARY" >&2
    exit 1
fi
if [[ ! -f "$X86_64_BINARY" ]]; then
    echo "Missing x86_64 binary at $X86_64_BINARY" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

create_bundle() {
    local binary_path="$1"
    local bundle_path="$2"

    local contents_dir="$bundle_path/Contents"
    local macos_dir="$contents_dir/MacOS"
    local resources_dir="$contents_dir/Resources"
    local plist_path="$contents_dir/Info.plist"

    rm -rf "$bundle_path"
    mkdir -p "$macos_dir" "$resources_dir"

    cp "$binary_path" "$macos_dir/$APP_NAME"
    cp "$ICON_PATH" "$resources_dir/AppIcon.icns"

    cat > "$plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>local.dubbingeditor.bundle</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MINIMUM_SYSTEM_VERSION}</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>DubbingEditor needs microphone/speech access to generate Smart Auto-TC from audio.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>DubbingEditor uses on-device speech recognition to generate Smart Auto-TC locally.</string>
</dict>
</plist>
PLIST

    codesign --force --deep --sign - "$bundle_path" >/dev/null 2>&1 || true
}

INTEL_BUNDLE="$OUTPUT_DIR/${APP_NAME}-intel.app"
UNIVERSAL_BUNDLE="$OUTPUT_DIR/${APP_NAME}-universal.app"
UNIVERSAL_BINARY="$OUTPUT_DIR/${APP_NAME}-universal"

echo "Creating Intel app bundle..."
create_bundle "$X86_64_BINARY" "$INTEL_BUNDLE"

echo "Creating universal binary..."
rm -f "$UNIVERSAL_BINARY"
lipo -create "$ARM64_BINARY" "$X86_64_BINARY" -output "$UNIVERSAL_BINARY"

echo "Creating universal app bundle..."
create_bundle "$UNIVERSAL_BINARY" "$UNIVERSAL_BUNDLE"
rm -f "$UNIVERSAL_BINARY"

echo "Built app variants:"
echo "  Intel:     $INTEL_BUNDLE"
echo "  Universal: $UNIVERSAL_BUNDLE"
