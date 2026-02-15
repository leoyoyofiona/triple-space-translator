#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "" ]]; then
  echo "Usage: $0 <app-version>"
  exit 1
fi

APP_VERSION="$1"
APP_NAME="TripleSpaceTranslator"
EXECUTABLE_NAME="TripleSpaceTranslatorApp"
BUNDLE_ID="com.leo.triplespacetranslator"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_DIR="$ROOT_DIR/.xcode-build"
DIST_DIR="$ROOT_DIR/macos-dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"

rm -rf "$DERIVED_DATA_DIR" "$DIST_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

echo "Building universal macOS binary..."
xcodebuild \
  -scheme "$EXECUTABLE_NAME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  build

BIN_PATH="$(find "$DERIVED_DATA_DIR/Build/Products/Release" -type f -name "$EXECUTABLE_NAME" | head -n 1)"
if [[ -z "$BIN_PATH" || ! -f "$BIN_PATH" ]]; then
  echo "Build output not found."
  exit 1
fi

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
  <key>NSAccessibilityUsageDescription</key>
  <string>This app needs Accessibility permission to read and replace text in focused input fields.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>This app uses automation to update text in the focused input field.</string>
</dict>
</plist>
EOF

# Ad-hoc sign to keep bundle metadata consistent for distribution.
codesign --force --deep --sign - "$APP_DIR"

ZIP_NAME="$DIST_DIR/TripleSpaceTranslator-macOS26-universal-$APP_VERSION.zip"
DMG_NAME="$DIST_DIR/TripleSpaceTranslator-macOS26-universal-$APP_VERSION.dmg"

echo "Packaging zip..."
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_NAME"

echo "Packaging dmg..."
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_DIR" -ov -format UDZO "$DMG_NAME"

echo "Generating checksums..."
(
  cd "$DIST_DIR"
  shasum -a 256 "$(basename "$ZIP_NAME")" "$(basename "$DMG_NAME")" > "SHA256-$APP_VERSION.txt"
)

echo "Done."
ls -lh "$DIST_DIR"
