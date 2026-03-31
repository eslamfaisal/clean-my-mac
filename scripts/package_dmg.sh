#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="CleanMyMac"
BUNDLE_ID="com.eslam.cleanmymac"
VERSION="0.0.3"
MIN_MACOS="14.0"
BUILD_DIR="$ROOT_DIR/.build"
RELEASE_DIR="$BUILD_DIR/arm64-apple-macosx/release"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$DIST_DIR/dmg-staging"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
EXECUTABLE="$RELEASE_DIR/$APP_NAME"

mkdir -p "$DIST_DIR"

mkdir -p "$ROOT_DIR/Resources"

CLANG_MODULE_CACHE_PATH="$BUILD_DIR/ModuleCache" SWIFTPM_ENABLE_PLUGINS=0 swift "$ROOT_DIR/scripts/generate_brand_assets.swift"
CLANG_MODULE_CACHE_PATH="$BUILD_DIR/ModuleCache" SWIFTPM_ENABLE_PLUGINS=0 swift build -c release --scratch-path "$BUILD_DIR"

rm -rf "$APP_BUNDLE" "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$STAGING_DIR"

cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/Resources/BrandPreview.png" "$APP_BUNDLE/Contents/Resources/BrandPreview.png"

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

cp -R "$APP_BUNDLE" "$STAGING_DIR/"

create_applications_alias() {
  rm -f "$STAGING_DIR/Applications"

  if osascript <<EOF >/dev/null 2>&1
tell application "Finder"
  set stagingFolder to POSIX file "$STAGING_DIR" as alias
  set appsAlias to make new alias file to POSIX file "/Applications" at stagingFolder
  set name of appsAlias to "Applications"
end tell
EOF
  then
    return 0
  fi

  ln -s /Applications "$STAGING_DIR/Applications"
}

create_applications_alias

cat > "$STAGING_DIR/Install CleanMyMac.txt" <<EOF
$APP_NAME

1. Drag $APP_NAME.app into Applications.
2. Launch the app from Applications.
3. If macOS blocks the app, right-click it once and choose Open.
4. For deep scanning, grant Full Disk Access in System Settings > Privacy & Security.

This DMG is locally packaged and ad-hoc signed for personal installation.
EOF

cp "$ROOT_DIR/Resources/AppIcon.icns" "$STAGING_DIR/.VolumeIcon.icns"
SetFile -a C "$STAGING_DIR" || true

codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

hdiutil create \
  -volname "$APP_NAME Installer" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Created:"
echo "  $APP_BUNDLE"
echo "  $DMG_PATH"
