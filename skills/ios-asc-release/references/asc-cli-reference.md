# App Store Connect (asc) CLI Command Reference

This reference documents the subcommands and usage patterns for Apple's App Store Connect CLI (`asc`) across the complete iOS release lifecycle.

---

## 1. Authentication & Configuration

The `asc` CLI authenticates using App Store Connect API Keys (`.p8`).

### Environment Variables
Set these variables in CI (or your local environment) to authenticate without passing flags to every command:

```bash
export ASC_KEY_ID="XXXXXXXXXX"
export ASC_ISSUER_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export ASC_PRIVATE_KEY_PATH="~/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
```

Alternatively, `asc` supports standard flag options:
```bash
asc --key-id "$ASC_KEY_ID" --issuer-id "$ASC_ISSUER_ID" --private-key-path "$ASC_PRIVATE_KEY_PATH" <subcommand>
```

---

## 2. Managing Builds

### Upload an IPA
Upload a signed `.ipa` archive to App Store Connect:
```bash
asc builds upload \
  --app "<APP_APPLE_ID>" \
  --file "path/to/MyApp.ipa"
```

### Check Build Status
Query the status of uploaded builds (e.g., `PROCESSING`, `VALID`, `FAILED`):
```bash
asc builds list \
  --app "<APP_APPLE_ID>" \
  --limit 5
```

### Wait for Processing
Apple processes uploaded builds (symbol extraction, bitcode/asset validation, encryption checks) before they can be assigned to TestFlight:
```bash
asc builds wait-for-processing \
  --app "<APP_APPLE_ID>" \
  --build-number "<BUILD_NUMBER>" \
  --timeout 1800 # 30 minute timeout
```

---

## 3. TestFlight Internal Testers

Internal groups consist of App Store Connect team members. Builds assigned to internal groups do **not** require Apple Beta Review and become available immediately after processing completes.

### List TestFlight Groups
```bash
asc testflight groups list --app "<APP_APPLE_ID>"
```

### Add Build to Internal Group
```bash
asc testflight groups add-build \
  --group "App Store Connect Users" \
  --app "<APP_APPLE_ID>" \
  --build-number "<BUILD_NUMBER>"
```

---

## 4. TestFlight External Testers & Beta Review

External groups allow public beta testing (up to 10,000 testers via public link or email invitation). The first build for each marketing version (`CFBundleShortVersionString`) submitted to an external group requires **TestFlight Beta Review**.

### Set "What to Test" Notes
Before submitting for beta review or assigning to external groups, release notes must be provided:
```bash
asc testflight builds set-test-info \
  --app "<APP_APPLE_ID>" \
  --build-number "<BUILD_NUMBER>" \
  --locale "en-US" \
  --whats-new "Resolved login crash and improved performance on iPad."
```

### Add Build to External Group
```bash
asc testflight groups add-build \
  --group "Public Beta" \
  --app "<APP_APPLE_ID>" \
  --build-number "<BUILD_NUMBER>"
```

### Submit for TestFlight Beta Review
```bash
asc testflight beta-reviews submit \
  --app "<APP_APPLE_ID>" \
  --build-number "<BUILD_NUMBER>"
```

### Monitor Beta Review Status
```bash
asc testflight beta-reviews status \
  --app "<APP_APPLE_ID>" \
  --build-number "<BUILD_NUMBER>"
```

---

## 5. Production App Store Release

### Create App Store Version
Create a new version container if it does not already exist:
```bash
asc versions create \
  --app "<APP_APPLE_ID>" \
  --version "1.2.0" \
  --platform IOS
```

### Set Release Notes ("What's New in This Version")
```bash
asc versions set-release-notes \
  --app "<APP_APPLE_ID>" \
  --version "1.2.0" \
  --locale "en-US" \
  --text "Exciting new features and stability enhancements."
```

### Attach Processed Build to Version
```bash
asc versions attach-build \
  --app "<APP_APPLE_ID>" \
  --version "1.2.0" \
  --build-number "<BUILD_NUMBER>"
```

### Enable Phased Release (7-Day Rollout)
Recommended for production to mitigate undetected regressions:
```bash
asc versions set-phased-release \
  --app "<APP_APPLE_ID>" \
  --version "1.2.0" \
  --state ACTIVE
```

### Submit for App Store Review
```bash
asc versions submit-for-review \
  --app "<APP_APPLE_ID>" \
  --version "1.2.0"
```
