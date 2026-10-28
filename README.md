# RestBar

A lightweight macOS menu bar app for keeping your Mac awake, checking battery status, and managing Low Power Mode. Built with Swift, AppKit, SwiftUI, and IOKit. The current interface is in Simplified Chinese.

[中文说明](README.zh-CN.md)

## Features

- Keep the system awake while allowing the display to sleep, or keep both awake.
- Stop automatically after 15 or 30 minutes, 1, 2, or 4 hours; alternatively, stop manually.
- Optionally stop when external power is disconnected, or when the battery reaches 20% and is not charging.
- Read battery percentage, power source, charging state, and available macOS time estimates.
- Manage Low Power Mode separately for battery and external power.
- Inspect applications preventing automatic sleep and the system's sleep policy.
- Turn off the display or request immediate sleep with confirmation.
- Optionally launch at login and show the battery percentage in the menu bar.

No account, network service, telemetry, or third-party package dependencies are required.

## Requirements

- Apple Silicon Mac, macOS 13 or later.
- Xcode or the Command Line Tools with a Swift compiler supporting Swift 5 language mode and macOS 13 APIs.
- This build script targets `arm64`. Intel builds and cross-device distribution have not been validated.

## Build and install

```sh
git clone https://github.com/Noxr3/RestBar.git
cd RestBar
bash build.sh
open dist/RestBar.app
```

The output is `dist/RestBar.app`. Drag it into your personal `~/Applications` folder or `/Applications` to install it. Quit any running copy before launching the installed copy. Click the moon or coffee cup icon in the menu bar to open the panel; right-click for quick actions.

The build is locally ad-hoc signed. It is not Developer ID signed or notarized. A build copied to another Mac may require additional distribution work before it can be opened normally.

## How power controls behave

RestBar starts without enabling keep-awake or changing system power settings. Keep-awake uses a temporary IOKit assertion. The OS releases it when its timeout expires or the process exits; the app also releases it explicitly when stopped. Closing the panel leaves a session running. Changing duration restarts the countdown, while changing display mode preserves its deadline.

Lid closure and explicit system sleep still follow macOS rules. Turning RestBar off releases only its own assertion; other applications may continue to prevent automatic sleep. Selecting “turn off display” during a display-awake session switches that session to system-only wakefulness.

Low Power Mode and restoring a globally disabled sleep policy are persistent system settings. Changes require the native macOS administrator prompt, and successful commands are followed by a settings readback. The app does not read or store administrator passwords. These settings remain after RestBar exits. Login at startup is opt-in and uses `SMAppService`.

RestBar does not set charge limits, control fans, or estimate whole-machine wattage. The Activity Monitor shortcut opens the app; select its Energy tab to inspect consumption.

## Tests

```sh
bash test.sh                 # 26 deterministic parsing and policy checks
bash test.sh --integration   # Also run 8 local IOKit integration checks
```

The integration checks briefly create native keep-awake assertions and verify explicit release, timeout, mode changes, and process-exit cleanup. Run them on a local Mac, one invocation at a time. They do not request sleep or alter Low Power Mode. The CI workflow runs the deterministic checks, builds and validates the app, and uploads a zipped build artifact. It does not run hardware or interactive authorization tests.

Administrator setting changes, immediate sleep, display sleep, and login-item registration still need manual acceptance on each supported macOS version. A passing build does not validate those flows.

## Project layout

| Path | Purpose |
| --- | --- |
| `Sources/PowerCore.swift` | Battery APIs, settings parsers, policies, native assertions |
| `Sources/PowerController.swift` | Session lifecycle, system settings, authorization, login item |
| `Sources/Panel.swift` | Menu bar popover UI |
| `Sources/AppDelegate.swift` | Status item and application lifecycle |
| `Tests/main.swift` | Deterministic and local integration checks |
| `scripts/Icon.swift` | Original AppKit icon generator |

The checked-in icon can be regenerated on macOS:

```sh
mkdir -p build/module-cache
xcrun swift -module-cache-path "$PWD/build/module-cache" scripts/Icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o AppIcon.icns
```

## Release status

This repository is private preparation for a future open-source release. An open-source license has not been selected yet. Before public distribution, choose a license, validate the administrator and login-item flows, and decide how to sign and notarize releases. English localization and additional hardware coverage are also planned work, not current features.

## Platform references

- [IOKit idle sleep assertions](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridlesystemsleep)
- [Assertion timeouts](https://developer.apple.com/documentation/iokit/1557078-iopmassertioncreatewithdescripti)
- [Power source descriptions](https://developer.apple.com/documentation/iokit/1523867-iopsgetpowersourcedescription)
- [Login item registration](https://developer.apple.com/documentation/servicemanagement/smappservice/register())
