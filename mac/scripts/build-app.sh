#!/bin/bash
# Builds a release Sitch.app (with Info.plist and icon) at mac/.build/Sitch.app.
# Install with: cp -R .build/Sitch.app /Applications/
#
# Optional environment:
#   VERSION=1.2.3      version written to Info.plist (default: <Version> from the Windows csproj,
#                      so both platforms share one version line)
#   UNIVERSAL=1        build for both arm64 and x86_64
#   SIGN_IDENTITY=...  codesigning identity, e.g. "Developer ID Application: Name (TEAMID)" for
#                      distribution; the default "-" signs ad hoc. Ad-hoc rebuilds lose the Screen
#                      Recording grant, so sign dev builds with the Developer ID to keep it.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${VERSION:-$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' ../windows/Sitch/Sitch.csproj)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
BUNDLE_ID="io.github.phalladar.Sitch"

BUILD_ARGS=(-c release)
if [[ "${UNIVERSAL:-}" == 1 ]]; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

APP=".build/Sitch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/Sitch" "$APP/Contents/MacOS/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp ../LICENSE "$APP/Contents/Resources/LICENSE.txt"

# LSUIElement: menu-bar app; it switches to a regular (Dock) app only while an editor is open.
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Sitch</string>
    <key>CFBundleDisplayName</key>
    <string>Sitch</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>Sitch</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.graphics-design</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Image</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.png</string>
                <string>public.jpeg</string>
                <string>public.tiff</string>
                <string>public.heic</string>
                <string>org.webmproject.webp</string>
                <string>com.compuserve.gif</string>
                <string>com.microsoft.bmp</string>
            </array>
        </dict>
    </array>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 Josh Auriemma. MIT License.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    # Ad-hoc sign so the bundle's resources are sealed and the signature is valid.
    codesign --force --sign - "$APP"
else
    # Notarization requires the hardened runtime and a secure timestamp. No entitlements: screen
    # capture is gated by the Screen Recording privacy grant, not an entitlement.
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$APP"
fi

echo "Built $APP ($VERSION)"
