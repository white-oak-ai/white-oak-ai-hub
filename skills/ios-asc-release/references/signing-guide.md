# iOS Code Signing & Keychain Guide for GitHub Actions

This guide details how to securely configure iOS code signing for non-interactive headless macOS CI runners (such as GitHub-hosted `macos-14` / Apple Silicon runners).

---

## 1. Required Credentials Overview

| Secret Name | Content | How to Obtain |
|---|---|---|
| `APPLE_CERTIFICATE_P12_BASE64` | Distribution Certificate + Private Key | Export from macOS Keychain Access as `.p12`, then encode: `base64 -w 0 Cert.p12` |
| `APPLE_CERTIFICATE_PASSWORD` | Password protecting the `.p12` | Chosen when exporting from Keychain |
| `PROVISIONING_PROFILE_BASE64` | App Store Provisioning Profile | Download `.mobileprovision` from developer.apple.com, then encode: `base64 -w 0 profile.mobileprovision` |
| `ASC_KEY_ID` | 10-character API Key ID | App Store Connect > Users and Access > Integrations > API |
| `ASC_ISSUER_ID` | UUID string | App Store Connect > Users and Access > Integrations > API |
| `ASC_KEY_P8_BASE64` | Private key (`AuthKey_XXXXXX.p8`) | Download once from App Store Connect, then encode: `base64 -w 0 AuthKey_XXXXXX.p8` |

---

## 2. Generating the Base64 Secrets

Run these commands locally on your Mac:

```bash
# 1. Base64 encode your distribution certificate
base64 -i DistributionCert.p12 -o cert_base64.txt

# 2. Base64 encode your provisioning profile
base64 -i AppStore_Profile.mobileprovision -o profile_base64.txt

# 3. Base64 encode your App Store Connect API Key
base64 -i AuthKey_XXXXXXXXXX.p8 -o p8_base64.txt
```

Copy the contents of each `.txt` file into your GitHub Repository Secrets.

---

## 3. Temporary CI Keychain Lifecycle

In CI environments, macOS default keychains are often locked or trigger interactive UI prompts. To prevent `User interaction is not allowed` errors:

1. **Create an isolated temporary keychain** (`$RUNNER_TEMP/build.keychain`).
2. **Unlock the keychain** with an ephemeral password.
3. **Set key partition list** (`security set-key-partition-list -S apple-tool:,apple:,codesign:`) so `codesign` can access the private key non-interactively.
4. **Delete the keychain** in a cleanup step when the job finishes.

---

## 4. Bypassing Encryption Prompts

To prevent builds from stalling with "Missing Compliance" in App Store Connect, configure your `Info.plist`:

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

If your app utilizes proprietary or non-exempt encryption algorithms, provide the App Store Connect encryption document reference in App Store Connect instead of setting this to false.
