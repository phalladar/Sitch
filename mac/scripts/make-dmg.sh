#!/bin/bash
# Packages .build/Sitch.app as a drag-to-Applications disk image, then signs, notarizes and
# staples the image. Run after build-app.sh — and after notarize.sh, so the app inside carries
# its own stapled ticket and still opens offline once it has been copied out of the image.
#
# Optional environment (same as build-app.sh / notarize.sh):
#   SIGN_IDENTITY     Developer ID Application identity; without it the image is left unsigned
#   NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER_ID
#                     App Store Connect API key; without it notarization is skipped
#
# Usage: scripts/make-dmg.sh [OUTPUT.dmg]   (default Sitch.dmg)
set -euo pipefail

OUT="${1:-Sitch.dmg}"
cd "$(dirname "$0")/.."
[[ "$OUT" = /* ]] || OUT="$PWD/$OUT"
APP=".build/Sitch.app"
VOLNAME="Sitch"
[[ -d "$APP" ]] || { echo "Build $APP first (scripts/build-app.sh)" >&2; exit 1; }

WORK="$(mktemp -d)"
STAGE="$WORK/stage"
MOUNT="$WORK/mount"
trap 'hdiutil detach "$MOUNT" -quiet -force 2>/dev/null || true; rm -rf "$WORK"' EXIT
mkdir -p "$STAGE" "$MOUNT"

ditto "$APP" "$STAGE/Sitch.app"
ln -s /Applications "$STAGE/Applications"
[[ -f "$STAGE/Sitch.app/Contents/Resources/DMGBackground.tiff" ]] \
    || { echo "$APP has no DMGBackground.tiff; rebuild it with build-app.sh" >&2; exit 1; }

hdiutil create -quiet -volname "$VOLNAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$WORK/rw.dmg"
hdiutil attach -quiet -readwrite -noverify -noautoopen -mountpoint "$MOUNT" "$WORK/rw.dmg"

# Window layout is stored in the volume's .DS_Store, which only Finder writes. CI runners can
# refuse Apple Events; the image still works without it, just unstyled — so warn, don't fail.
if ! osascript <<EOF
tell application "Finder"
    set dmg to disk (POSIX file "$MOUNT" as alias)
    tell dmg
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 800, 548}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 128
        set text size of opts to 13
        -- Art from inside the bundle (see build-app.sh): no visible .background folder.
        set background picture of opts to file "Sitch.app:Contents:Resources:DMGBackground.tiff"
        -- Icon centers; make-dmg-background.swift draws the arrow between them at y = 190.
        set position of item "Sitch.app" of container window to {150, 190}
        set position of item "Applications" of container window to {450, 190}
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF
then
    echo "warning: Finder layout step failed; the disk image will open unstyled" >&2
fi

# Don't ship the mount's FSEvents log or trash.
rm -rf "$MOUNT/.fseventsd" "$MOUNT/.Trashes"
chmod -Rf go-w "$MOUNT" 2>/dev/null || true
sync
hdiutil detach -quiet "$MOUNT"
rm -f "$OUT"
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT"

if [[ -n "${SIGN_IDENTITY:-}" && "$SIGN_IDENTITY" != "-" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$OUT"
else
    echo "warning: SIGN_IDENTITY not set; disk image left unsigned" >&2
fi

if [[ -n "${NOTARY_KEY_PATH:-}" ]]; then
    AUTH=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
    RESULT="$(xcrun notarytool submit "$OUT" "${AUTH[@]}" --wait --output-format json)"
    STATUS="$(plutil -extract status raw -o - - <<< "$RESULT")"
    if [[ "$STATUS" != "Accepted" ]]; then
        echo "Notarization failed with status: $STATUS" >&2
        xcrun notarytool log "$(plutil -extract id raw -o - - <<< "$RESULT")" "${AUTH[@]}" >&2
        exit 1
    fi
    xcrun stapler staple "$OUT"
else
    echo "warning: NOTARY_KEY_PATH not set; disk image not notarized" >&2
fi

echo "Wrote $OUT"
