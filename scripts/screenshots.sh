#!/bin/bash
# Renders the README screenshots from the real panel, one set per README language.
# To show the awake state it starts a real keep-awake session for a few seconds and
# releases it. It changes no system setting.
set -euo pipefail
cd "$(dirname "$0")/.."
app=build/PanelShot.app
rm -rf "$app"
mkdir -p build/module-cache "$app/Contents/MacOS" "$app/Contents/Resources"
# Inside a bundle, because that is the only place macOS looks for translations.
cp Info.plist "$app/Contents/Info.plist"
cp -R Resources/*.lproj "$app/Contents/Resources/"
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$PWD/build/module-cache" \
  Sources/PowerCore.swift Sources/Brand.swift Sources/PowerController.swift Sources/Panel.swift scripts/PanelShot.swift \
  -framework AppKit -framework SwiftUI -framework IOKit -framework ServiceManagement -o "$app/Contents/MacOS/PanelShot"
for language in en zh-Hans; do
  "$app/Contents/MacOS/PanelShot" "assets/screenshots/$language" -AppleLanguages "($language)"
done
