#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/module-cache
/usr/bin/xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" \
  Sources/PowerCore.swift Tests/main.swift -framework IOKit -o build/RestBarTests
build/RestBarTests "$@"
