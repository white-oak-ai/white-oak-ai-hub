---
name: ios-asc-release
description: Set up, scaffold, and automate iOS app release pipelines using Apple's App Store Connect (asc) CLI and GitHub Actions. Covers internal TestFlight testing, external beta testing, and final App Store production releases with automated code signing, build promotion, and version management. Use when configuring iOS CI/CD, releasing iOS apps, setting up TestFlight groups, or automating App Store submissions.
---

# iOS App Store Connect Release Pipeline (`ios-asc-release`)

This skill guides you through setting up and operating a secure, automated iOS release pipeline using GitHub Actions and Apple's **App Store Connect (`asc`) CLI**. It implements a single-binary build-and-promote model across three release tiers:
1. **Internal Testers**: Instant distribution to team members without Apple review.
2. **External Testers**: Public/beta distribution with release notes and TestFlight Beta Review.
3. **App Store Production**: Production submission with optional 7-day phased rollouts.

---

## When to use

- User wants to set up a release pipeline for an iOS application.
- User wants to automate TestFlight internal or external distribution.
- User wants to submit iOS builds to the App Store using GitHub Actions and the `asc` CLI.
- User needs to configure headless code signing (certificates & provisioning profiles) in GitHub Actions.
- User asks how to structure branches, build numbers, and promotion workflows for iOS apps.

---

## Promotion Architecture

```
develop branch                  release/* branch / dispatch          main tag (v*.*.*)
      │                                     │                                │
      ▼                                     ▼                                ▼
[Build & Archive] ──► Upload ──► [External TestFlight] ──────► [App Store Review]
(Runs tests, signs,  (asc upload,  (Attaches test notes,      (Attaches build,
 exports IPA)        adds to       submits to Beta Review,    configures phased release,
                     Internal)     distributes to testers)    submits to App Store)
```

> [!IMPORTANT]
> **Single Binary Rule**: Never rebuild the `.ipa` when promoting between Internal Testers, External Testers, and the App Store. The identical binary tested by internal testers is assigned to external groups and eventually submitted to production review.

---

## Steps

### Step 0: Scaffold CI/CD Assets into the iOS Project

If setting up a new or existing iOS project, run the scaffolding script or copy the templates from this skill:

```bash
<skill-dir>/scripts/scaffold-ios-release.sh \
  --target "/path/to/ios/repo" \
  --app-id "<Apple-App-ID>" \
  --bundle-id "com.example.app" \
  --scheme "MyApp" \
  --profile "MyApp AppStore"
```

This installs:
- `.github/workflows/testflight-internal.yml`: Build, archive, sign, upload, and distribute to internal testers.
- `.github/workflows/testflight-external.yml`: Promote build to external testers and trigger TestFlight Beta Review.
- `.github/workflows/appstore-release.yml`: Attach build to an App Store version, configure phased rollout, and submit for review.
- `ci/ExportOptions.plist`: Non-interactive archive export configuration.
- `ci/setup-signing.sh`: Headless temporary keychain creation and profile installer for macOS runners.

---

### Step 1: Configure App Store Connect API Key & GitHub Secrets

1. **Create API Key**:
   - Go to **App Store Connect** > **Users and Access** > **Integrations** > **App Store Connect API**.
   - Create a key with role **App Manager** or **Admin**.
   - Note the **Key ID**, **Issuer ID**, and download `AuthKey_<KEY_ID>.p8`.

2. **Encode Secrets Locally on macOS**:
   ```bash
   # App Store Connect API Key
   base64 -i AuthKey_XXXXXXXXXX.p8 -o p8.txt

   # Distribution Certificate (.p12)
   base64 -i DistributionCert.p12 -o cert.txt

   # Provisioning Profile (.mobileprovision)
   base64 -i AppStoreProfile.mobileprovision -o profile.txt
   ```

3. **Add Secrets in GitHub** (`Settings` > `Secrets and variables` > `Actions`):
   - `ASC_KEY_ID`: 10-character Key ID
   - `ASC_ISSUER_ID`: Issuer UUID
   - `ASC_KEY_P8_BASE64`: Content of `p8.txt`
   - `APPLE_CERTIFICATE_P12_BASE64`: Content of `cert.txt`
   - `APPLE_CERTIFICATE_PASSWORD`: Password protecting the `.p12`
   - `PROVISIONING_PROFILE_BASE64`: Content of `profile.txt`

4. **Add Repository Variable**:
   - `ASC_APP_APPLE_ID`: Numeric Apple ID of the application (found in App Store Connect URL or App Information).

---

### Step 2: Configure App Code & Project Settings

1. **Bypass Export Compliance Stalling**:
   In your app's `Info.plist`, add:
   ```xml
   <key>ITSAppUsesNonExemptEncryption</key>
   <false/>
   ```
   *(If using non-exempt encryption, set to `<true/>` and supply compliance documentation in App Store Connect).*

2. **Automate Build Numbering**:
   Ensure `agvtool` is enabled in Xcode:
   - Target Build Settings > **Current Project Version** = `1`
   - Target Build Settings > **Versioning System** = `Apple Generic`

---

### Step 3: Triggering & Managing Releases

#### 1. Internal Testing (Automatic)
- **Trigger**: Merge or push to the `develop` branch.
- **What happens**:
  1. Temporary build keychain is created on macOS runner.
  2. `agvtool new-version -all "${{ github.run_number }}"` stamps the build number.
  3. `xcodebuild -archivePath ... archive` & `-exportArchive` creates `MyApp.ipa`.
  4. `asc builds upload` uploads the binary.
  5. `asc builds wait-for-processing` polls until Apple validates the build.
  6. `asc testflight groups add-build --group "App Store Connect Users"` assigns it.
- **Availability**: Available to team members in ~5–15 minutes without review.

#### 2. External Testing (Public Beta)
- **Trigger**: Run workflow `.github/workflows/testflight-external.yml` via GitHub Actions UI (`workflow_dispatch`).
- **Inputs**:
  - `build_number`: Build number already tested internally.
  - `whats_to_test`: Tester-facing release notes.
  - `group_name`: Name of the external group (e.g. `Public Beta`).
- **What happens**:
  1. `asc testflight builds set-test-info` updates "What to Test".
  2. `asc testflight groups add-build` adds the build to the external group.
  3. `asc testflight beta-reviews submit` submits the build to Apple TestFlight Beta Review.
- **Availability**: Once Apple approves the beta review (typically within 24 hours), testers receive notifications.

#### 3. App Store Production Release
- **Trigger**: Push a semantic git tag (e.g. `git tag v1.2.0 && git push origin v1.2.0`) or run via `workflow_dispatch`.
- **Inputs** (if manual dispatch):
  - `version`: Marketing version string (e.g., `1.2.0`).
  - `build_number`: Validated build number.
  - `release_notes`: What's New text for the App Store page.
- **What happens**:
  1. `asc versions create` creates the version container if needed.
  2. `asc versions set-release-notes` updates localized release notes.
  3. `asc versions attach-build` attaches the specified build.
  4. `asc versions set-phased-release --state ACTIVE` turns on 7-day phased rollout.
  5. `asc versions submit-for-review` submits the app to App Store Review.

---

## Troubleshooting Guide

| Issue | Cause | Fix |
|---|---|---|
| **User interaction is not allowed** during codesign | Default runner keychain is locked or missing partition access | Use `ci/setup-signing.sh` with `security set-key-partition-list -S apple-tool:,apple:,codesign:` |
| **Missing Compliance** in TestFlight | `ITSAppUsesNonExemptEncryption` is missing from `Info.plist` | Add `<key>ITSAppUsesNonExemptEncryption</key><false/>` to `Info.plist` |
| **No profile matching 'XYZ' found** | Provisioning profile UUID mismatch or bundle ID mismatch | Ensure `ci/ExportOptions.plist` specifies the exact App ID and profile name matching the `.mobileprovision` |
| **Build stuck in PROCESSING** | Apple symbol processing or asset compilation backlog | Normal processing takes 5-15 mins; `asc builds wait-for-processing` has an adjustable `--timeout` flag |
| **Beta Review Rejected** | Incomplete "What to Test" notes or missing demo credentials | Update beta review contact information and login instructions in App Store Connect > General Information |

---

## References & Assets

- [App Store Connect CLI Command Reference](file:///home/rickyjonesus/Development/white-oak-ai-hub/skills/ios-asc-release/references/asc-cli-reference.md)
- [Code Signing & Keychain Guide](file:///home/rickyjonesus/Development/white-oak-ai-hub/skills/ios-asc-release/references/signing-guide.md)
- [Scaffolding Script](file:///home/rickyjonesus/Development/white-oak-ai-hub/skills/ios-asc-release/scripts/scaffold-ios-release.sh)
- [ExportOptions.plist Template](file:///home/rickyjonesus/Development/white-oak-ai-hub/skills/ios-asc-release/assets/ExportOptions.plist)
- [Keychain Setup Script](file:///home/rickyjonesus/Development/white-oak-ai-hub/skills/ios-asc-release/assets/setup-signing.sh)
