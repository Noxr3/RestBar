#!/bin/bash
# Builds a universal dist/RestBar.app. Ad-hoc signed unless SIGN_IDENTITY names a
# certificate, which also turns on the hardened runtime that notarization requires.
set -euo pipefail
cd "$(dirname "$0")"
app=dist/RestBar.app
mkdir -p build/module-cache "$app/Contents/MacOS" "$app/Contents/Resources"
for arch in arm64 x86_64; do
  /usr/bin/xcrun swiftc -swift-version 5 -O -target "$arch-apple-macosx13.0" \
    -module-cache-path "$PWD/build/module-cache" \
    Sources/*.swift -o "build/RestBar-$arch" \
    -framework AppKit -framework SwiftUI -framework IOKit -framework ServiceManagement
done
/usr/bin/lipo -create build/RestBar-arm64 build/RestBar-x86_64 -output "$app/Contents/MacOS/RestBar"
cp Info.plist "$app/Contents/Info.plist"
if [ -f AppIcon.icns ]; then cp AppIcon.icns "$app/Contents/Resources/"; fi
rm -rf "$app"/Contents/Resources/*.lproj
cp -R Resources/*.lproj "$app/Contents/Resources/"
if [ "${SIGN_IDENTITY:--}" = "-" ]; then
  /usr/bin/codesign --force --sign - --identifier io.github.noxr3.restbar "$app"
else
  /usr/bin/codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" --identifier io.github.noxr3.restbar "$app"
fi
/usr/bin/codesign --verify --strict "$app"
echo "Built: $PWD/$app"
