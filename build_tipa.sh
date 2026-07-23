#!/bin/bash
# Build and package UVCDisplay for installation with TrollStore.
#
# Usage: ./build_tipa.sh [Debug|Release]
# Output: build/UVCDisplay.tipa

set -euo pipefail
cd "$(dirname "$0")"

CONFIGURATION="${1:-Release}"
SCHEME="UVCDisplay"
ENTITLEMENTS="UVCDisplay.entitlements"
DERIVED_DATA="build/DerivedData"
PRODUCTS="$DERIVED_DATA/Build/Products"
APP="$PRODUCTS/$CONFIGURATION-iphoneos/$SCHEME.app"
STAGING="build/tipa-staging"
OUTPUT="build/$SCHEME.tipa"

case "$CONFIGURATION" in
  Debug|Release) ;;
  *)
    echo "ERROR: configuration must be Debug or Release" >&2
    exit 2
    ;;
esac

for command in xcodebuild codesign ditto plutil; do
  command -v "$command" >/dev/null || {
    echo "ERROR: required tool '$command' was not found" >&2
    exit 1
  }
done

[[ -f "$ENTITLEMENTS" ]] || {
  echo "ERROR: $ENTITLEMENTS was not found" >&2
  exit 1
}

if [[ ! -f Vendor/lib/libusb-1.0.a || ! -f Vendor/lib/libuvc.a ]]; then
  echo ">> Native dependencies are missing; building them first..."
  ./build_deps.sh
fi

echo ">> Building $CONFIGURATION for iphoneos (unsigned)..."
xcodebuild \
  -project UVCDisplay.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

[[ -d "$APP" ]] || {
  echo "ERROR: expected app was not produced at $APP" >&2
  exit 1
}

echo ">> Applying TrollStore entitlements with an ad-hoc signature..."
codesign --force --sign - \
  --entitlements "$ENTITLEMENTS" \
  --generate-entitlement-der \
  --timestamp=none \
  "$APP"

codesign --verify --deep --strict "$APP"

echo ">> Packaging ${OUTPUT}..."
rm -rf "$STAGING"
mkdir -p "$STAGING/Payload"
ditto "$APP" "$STAGING/Payload/$SCHEME.app"
rm -f "$OUTPUT"
(cd "$STAGING" && ditto -c -k --sequesterRsrc --keepParent Payload "../$SCHEME.tipa")
rm -rf "$STAGING"

[[ -s "$OUTPUT" ]] || {
  echo "ERROR: package was not created" >&2
  exit 1
}

echo ">> Embedded entitlements:"
codesign -d --entitlements - "$APP"
echo
echo "Done: $(pwd)/$OUTPUT"
echo "Install this .tipa with TrollStore."
