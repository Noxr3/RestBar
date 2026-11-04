#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/module-cache dist/RestBar.app/Contents/MacOS dist/RestBar.app/Contents/Resources
/usr/bin/xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx13.0 \
  -module-cache-path "$PWD/build/module-cache" \
  Sources/*.swift -o dist/RestBar.app/Contents/MacOS/RestBar \
  -framework AppKit -framework SwiftUI -framework IOKit -framework ServiceManagement
cp Info.plist dist/RestBar.app/Contents/Info.plist
if [ -f AppIcon.icns ]; then cp AppIcon.icns dist/RestBar.app/Contents/Resources/; fi
/usr/bin/codesign --force --sign - --identifier io.github.noxr3.restbar dist/RestBar.app
/usr/bin/codesign --verify --strict dist/RestBar.app
echo "Built: $PWD/dist/RestBar.app"
