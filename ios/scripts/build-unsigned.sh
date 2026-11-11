#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild \
  -project LifeTracker.xcodeproj \
  -scheme LifeTracker \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
mkdir -p build/package/Payload
# Remove only this script's previous app output, never user data.
if [ -d build/package/Payload/LifeTracker.app ]; then
  rm -rf build/package/Payload/LifeTracker.app
fi
ditto build/DerivedData/Build/Products/Release-iphoneos/LifeTracker.app build/package/Payload/LifeTracker.app
(
  cd build/package
  ditto -c -k --keepParent Payload ../LifeTracker-unsigned.ipa
)
echo 'Unsigned IPA: ios/build/LifeTracker-unsigned.ipa (must be signed before installation)'
