#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version="${1:-1.2.12}"
derived="$root/dist/DerivedData"
app="$derived/Build/Products/Release/MacPower.app"
stage="$root/dist/dmg-root"
dmg="$root/dist/MacPower-${version}.dmg"

cd "$root"
mkdir -p "$root/dist"

xcodebuild \
  -project MacPower.xcodeproj \
  -scheme MacPower \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived" \
  build

# Apple Development signatures are not trusted on other Macs and often surface
# as “app is damaged” after download. Re-sign ad-hoc for the public DMG.
codesign --force --deep --sign - \
  --options runtime \
  --entitlements "$root/MacPower/MacPower.entitlements" \
  --timestamp=none \
  "$app"

rm -rf "$stage"
mkdir -p "$stage"
ditto "$app" "$stage/MacPower.app"
ln -s /Applications "$stage/Applications"

rm -f "$dmg"
hdiutil create \
  -volname "MacPower" \
  -srcfolder "$stage" \
  -ov \
  -format UDZO \
  "$dmg"

echo "Created $dmg"
codesign -dv --verbose=2 "$stage/MacPower.app" 2>&1 | head -20
