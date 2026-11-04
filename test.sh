#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/module-cache
/usr/bin/xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" \
  Sources/PowerCore.swift Sources/Brand.swift Tests/main.swift -framework IOKit -framework AppKit -framework SwiftUI -o build/RestBarTests
build/RestBarTests "$@"
