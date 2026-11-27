#!/usr/bin/env bash
# ci/setup-signing.sh
# Sets up a temporary keychain and installs the provisioning profile in GitHub Actions runners.
set -euo pipefail

KEYCHAIN_PATH="${RUNNER_TEMP:-/tmp}/build.keychain"
KEYCHAIN_PASSWORD="${KEYCHAIN_PASSWORD:-temporary_runner_password}"

echo "==> Creating temporary keychain..."
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security default-keychain -s "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"

echo "==> Importing Apple Distribution Certificate..."
CERT_PATH="${RUNNER_TEMP:-/tmp}/cert.p12"
echo "$APPLE_CERTIFICATE_P12_BASE64" | base64 --decode > "$CERT_PATH"
security import "$CERT_PATH" -k "$KEYCHAIN_PATH" -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" > /dev/null 2>&1 || true

echo "==> Installing Provisioning Profile..."
PROFILES_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PROFILES_DIR"

PROFILE_PATH="${RUNNER_TEMP:-/tmp}/profile.mobileprovision"
echo "$PROVISIONING_PROFILE_BASE64" | base64 --decode > "$PROFILE_PATH"

# Extract UUID from provisioning profile
PROFILE_UUID=$(strings "$PROFILE_PATH" | grep -A1 UUID | grep string | sed -e 's/<string>//' -e 's/<\/string>//' | tr -d '\t ')
cp "$PROFILE_PATH" "$PROFILES_DIR/${PROFILE_UUID}.mobileprovision"

echo "==> Successfully installed provisioning profile ($PROFILE_UUID) into $PROFILES_DIR"
