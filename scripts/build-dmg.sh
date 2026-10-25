#!/usr/bin/env bash
#
# Builds Lime in Release and packages it as build/Lime.dmg.
#
#   scripts/build-dmg.sh [version]
#
# With a "Developer ID Application" certificate in the keychain the app and DMG are signed,
# and with notary credentials the DMG is also notarized and stapled. Without them you get an
# unsigned (ad-hoc) DMG that works after "Open Anyway". See docs/RELEASING.md.
#
# Optional environment:
#   LIME_SIGNING_IDENTITY   certificate name; defaults to the first Developer ID Application one found
#   LIME_NOTARY_PROFILE     keychain profile from `xcrun notarytool store-credentials`
#   NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER_ID
#                           App Store Connect API key, used instead of a profile (CI)
#   BUILD_NUMBER            defaults to the number of commits

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' Lime.xcodeproj/project.pbxproj | head -1)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"
OUT=build
ARCHIVE="$OUT/Lime.xcarchive"
STAGE="$OUT/dmg"
DMG="$OUT/Lime.dmg"

IDENTITY="${LIME_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)}"

rm -rf "$OUT"
mkdir -p "$STAGE"

if [[ -n "$IDENTITY" ]]; then
    TEAM_ID="$(sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p' <<<"$IDENTITY")"
    echo "==> Signing with: $IDENTITY"
    SIGNING=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM_ID"
             OTHER_CODE_SIGN_FLAGS="--timestamp")
else
    echo "==> No Developer ID certificate found; building an unsigned (ad-hoc) DMG"
    SIGNING=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM="")
fi

echo "==> Archiving Lime $VERSION ($BUILD_NUMBER)"
xcodebuild archive -quiet \
    -project Lime.xcodeproj -scheme Lime -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" "${SIGNING[@]}"

APP="$ARCHIVE/Products/Applications/Lime.app"
codesign --verify --deep --strict "$APP"

echo "==> Making the disk image"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Lime $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
rm -rf "$STAGE"

NOTARIZED=false
if [[ -n "$IDENTITY" ]]; then
    codesign --sign "$IDENTITY" --timestamp "$DMG"

    NOTARY=()
    if [[ -n "${LIME_NOTARY_PROFILE:-}" ]]; then
        NOTARY=(--keychain-profile "$LIME_NOTARY_PROFILE")
    elif [[ -n "${NOTARY_KEY_PATH:-}" ]]; then
        NOTARY=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
    fi

    if (( ${#NOTARY[@]} )); then
        echo "==> Notarizing (this usually takes a few minutes)"
        RESULT="$(xcrun notarytool submit "$DMG" "${NOTARY[@]}" --wait --output-format json)"
        if ! grep -q '"status" *: *"Accepted"' <<<"$RESULT"; then
            echo "$RESULT"
            ID="$(sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p' <<<"$RESULT" | head -1)"
            [[ -n "$ID" ]] && xcrun notarytool log "$ID" "${NOTARY[@]}" || true
            echo "Notarization failed." >&2
            exit 1
        fi
        xcrun stapler staple -q "$DMG"
        spctl --assess --type open --context context:primary-signature "$DMG"
        NOTARIZED=true
    else
        echo "==> Signed but not notarized (set LIME_NOTARY_PROFILE to notarize)"
    fi
fi

[[ -n "${GITHUB_OUTPUT:-}" ]] && echo "notarized=$NOTARIZED" >>"$GITHUB_OUTPUT"
echo "==> Done: $DMG"
echo "    version $VERSION ($BUILD_NUMBER), notarized: $NOTARIZED"
echo "    sha256 $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
