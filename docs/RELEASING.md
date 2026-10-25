# Releasing Lime

Releases are DMGs attached to [GitHub Releases](https://github.com/jdank417/Lime/releases).
The README's download link always points at the newest one:
`https://github.com/jdank417/Lime/releases/latest/download/Lime.dmg`.

## Publish a release

1. Make sure `main` has everything and the tests pass.
2. Tag the version and push the tag:

   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

The **Release** workflow then runs the tests, builds `Lime.dmg` (version taken from the tag) and creates the GitHub Release with it.
You can also build a DMG on your own Mac:

```bash
scripts/build-dmg.sh 1.0.0
```

It lands in `build/Lime.dmg`.

## Signing and notarizing

Without signing, people have to click **Open Anyway** in System Settings the first time they open Lime.
Signing with a Developer ID and notarizing with Apple removes that warning. Both need a paid
[Apple Developer Program](https://developer.apple.com/programs/) membership.

### One-time setup

1. **Create a Developer ID Application certificate.** In Xcode, open **Settings → Accounts**, pick your team,
   click **Manage Certificates…**, then **+** → **Developer ID Application**.
2. **For notarizing from your Mac**, create an app-specific password at [account.apple.com](https://account.apple.com)
   (Sign-In and Security → App-Specific Passwords), then save it for `notarytool`:

   ```bash
   xcrun notarytool store-credentials lime-notary --apple-id "you@example.com" --team-id YOURTEAMID
   ```

   Now `LIME_NOTARY_PROFILE=lime-notary scripts/build-dmg.sh 1.0.0` signs, notarizes and staples the DMG.

### Signing in GitHub Actions

Add these repository secrets (**Settings → Secrets and variables → Actions**). When they're present the
Release workflow signs and notarizes automatically; when they're missing it publishes an unsigned DMG.

| Secret | What to put in it |
| --- | --- |
| `DEVELOPER_ID_P12` | Your Developer ID Application certificate and private key, exported from Keychain Access as a `.p12`, then base64-encoded: `base64 -i DeveloperID.p12 \| pbcopy` |
| `DEVELOPER_ID_P12_PASSWORD` | The password you chose when exporting the `.p12` |
| `NOTARY_KEY` | The contents of an App Store Connect API key (`AuthKey_XXXX.p8`). Create one at App Store Connect → Users and Access → Integrations → Team Keys, with the Developer role |
| `NOTARY_KEY_ID` | That key's ID |
| `NOTARY_ISSUER_ID` | The Issuer ID shown above the keys list |

## Checking a DMG

```bash
spctl --assess --type open --context context:primary-signature -v build/Lime.dmg   # "accepted" when notarized
codesign -dv --verbose=2 "/Volumes/Lime 1.0.0/Lime.app"                            # who signed the app
```
