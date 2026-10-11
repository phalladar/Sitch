#!/bin/bash
# Notarizes and staples .build/Sitch.app, then zips it for distribution.
# Build first with a Developer ID SIGN_IDENTITY (see build-app.sh).
#
# Requires an App Store Connect API key in the environment:
#   NOTARY_KEY_PATH   path to the AuthKey_XXXXXXXXXX.p8 file
#   NOTARY_KEY_ID     the key's ID
#   NOTARY_ISSUER_ID  the issuer ID shown above the keys list in App Store Connect
#
# Usage: scripts/notarize.sh OUTPUT.zip
set -euo pipefail

OUT="${1:?usage: $0 OUTPUT.zip}"
APP="$(cd "$(dirname "$0")/.." && pwd)/.build/Sitch.app"
AUTH=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")

SUBMISSION="$(mktemp -d)/Sitch.zip"
ditto -c -k --keepParent "$APP" "$SUBMISSION"

RESULT="$(xcrun notarytool submit "$SUBMISSION" "${AUTH[@]}" --wait --output-format json)"
STATUS="$(plutil -extract status raw -o - - <<< "$RESULT")"
if [[ "$STATUS" != "Accepted" ]]; then
    echo "Notarization failed with status: $STATUS" >&2
    xcrun notarytool log "$(plutil -extract id raw -o - - <<< "$RESULT")" "${AUTH[@]}" >&2
    exit 1
fi

xcrun stapler staple "$APP"
ditto -c -k --keepParent "$APP" "$OUT"
echo "Notarized $APP and wrote $OUT"
