#!/usr/bin/env bash
# scaffold-ios-release.sh
# Scaffolds iOS App Store Connect release workflows, signing scripts, and export configurations into a target repo.
set -euo pipefail

usage() {
  local exit_code="${1:-1}"
  cat <<EOF
Usage: $0 --target <path-to-ios-repo> [options]

Options:
  --target <path>           Path to the root of the iOS git repository (required)
  --app-id <apple-id>       Numeric Apple App ID from App Store Connect (optional)
  --bundle-id <bundle-id>   iOS App Bundle Identifier (e.g., com.company.app) (optional)
  --scheme <scheme-name>    Xcode Scheme name to build (e.g., MyApp) (optional)
  --profile <profile-name>  App Store Provisioning Profile Name (optional)
  -h, --help                Show this help message

Example:
  $0 --target ~/Development/MyCoolApp \\
     --app-id 6478901234 \\
     --bundle-id com.company.mycoolapp \\
     --scheme MyCoolApp \\
     --profile "MyCoolApp AppStore"
EOF
  exit "$exit_code"
}

TARGET_DIR=""
APP_ID=""
BUNDLE_ID=""
SCHEME=""
PROFILE_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET_DIR="$2"; shift 2 ;;
    --app-id) APP_ID="$2"; shift 2 ;;
    --bundle-id) BUNDLE_ID="$2"; shift 2 ;;
    --scheme) SCHEME="$2"; shift 2 ;;
    --profile) PROFILE_NAME="$2"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

if [[ -z "$TARGET_DIR" ]]; then
  echo "Error: --target is required." >&2
  usage
fi

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "Error: Target directory $TARGET_DIR does not exist." >&2
  exit 1
fi

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS_DIR="$SKILL_DIR/assets"

echo "==> Scaffolding iOS ASC Release configuration into $TARGET_DIR..."

mkdir -p "$TARGET_DIR/.github/workflows"
mkdir -p "$TARGET_DIR/ci"

# 1. Copy ci/setup-signing.sh
cp "$ASSETS_DIR/setup-signing.sh" "$TARGET_DIR/ci/setup-signing.sh"
chmod +x "$TARGET_DIR/ci/setup-signing.sh"

# 2. Copy and customize ci/ExportOptions.plist
BUNDLE_ID_VAL="${BUNDLE_ID:-com.yourcompany.myapp}"
PROFILE_VAL="${PROFILE_NAME:-MyApp AppStore Profile}"

sed -e "s/BUNDLE_IDENTIFIER_PLACEHOLDER/$BUNDLE_ID_VAL/g" \
    -e "s/PROVISIONING_PROFILE_NAME_PLACEHOLDER/$PROFILE_VAL/g" \
    "$ASSETS_DIR/ExportOptions.plist" > "$TARGET_DIR/ci/ExportOptions.plist"

# 3. Copy workflows
cp "$ASSETS_DIR/workflows/testflight-internal.yml" "$TARGET_DIR/.github/workflows/testflight-internal.yml"
cp "$ASSETS_DIR/workflows/testflight-external.yml" "$TARGET_DIR/.github/workflows/testflight-external.yml"
cp "$ASSETS_DIR/workflows/appstore-release.yml" "$TARGET_DIR/.github/workflows/appstore-release.yml"

# Replace scheme if provided
if [[ -n "$SCHEME" ]]; then
  sed -e "s/SCHEME: \"MyApp\"/SCHEME: \"$SCHEME\"/g" \
      -e "s/MyApp.xcworkspace/$SCHEME.xcworkspace/g" \
      -e "s/MyApp.xcarchive/$SCHEME.xcarchive/g" \
      "$TARGET_DIR/.github/workflows/testflight-internal.yml" > "$TARGET_DIR/.github/workflows/testflight-internal.yml.tmp"
  mv "$TARGET_DIR/.github/workflows/testflight-internal.yml.tmp" "$TARGET_DIR/.github/workflows/testflight-internal.yml"
fi

if [[ -n "$BUNDLE_ID" ]]; then
  sed -e "s/BUNDLE_ID: \"com.yourcompany.myapp\"/BUNDLE_ID: \"$BUNDLE_ID\"/g" \
      "$TARGET_DIR/.github/workflows/testflight-internal.yml" > "$TARGET_DIR/.github/workflows/testflight-internal.yml.tmp"
  mv "$TARGET_DIR/.github/workflows/testflight-internal.yml.tmp" "$TARGET_DIR/.github/workflows/testflight-internal.yml"
fi

cat <<EOF

==============================================================
SUCCESS! iOS Release Automation scaffolded successfully.
==============================================================

Next Steps:
1. Ensure your iOS project's Info.plist contains:
   <key>ITSAppUsesNonExemptEncryption</key>
   <false/>

2. Configure these GitHub Repository Secrets:
   - ASC_KEY_ID: App Store Connect API Key ID (10 chars)
   - ASC_ISSUER_ID: App Store Connect Issuer UUID
   - ASC_KEY_P8_BASE64: base64-encoded AuthKey_XXXXXX.p8
   - APPLE_CERTIFICATE_P12_BASE64: base64-encoded Distribution .p12
   - APPLE_CERTIFICATE_PASSWORD: password for the .p12 certificate
   - PROVISIONING_PROFILE_BASE64: base64-encoded .mobileprovision

3. Configure this GitHub Repository Variable (optional if hardcoded):
   - ASC_APP_APPLE_ID: ${APP_ID:-"<Your numeric Apple App ID>"}

4. Commit and push the created files:
   git add .github/workflows/ ci/
   git commit -m "ci: add iOS release automation with asc cli"
   git push origin <branch>
EOF
