# Changelog

## 1.1.0

### Fixed

- The diagnostics tab said the system sleep policy was unconfirmed whenever sleep was allowed, because macOS leaves that line out.
- Low Power Mode could not be used on Macs that report `powermode` instead of `lowpowermode`, such as those with High Power Mode. The switch stayed disabled with "not available".

### Changed

- New look: black and white on a dot grid, replacing the green theme and coffee cup. The moon is a crescent with a red dot at rest, and a full red disc while keeping the Mac awake. The keep-awake switch turns red with it; nothing else does.
- A much simpler panel that fits without scrolling: no cards, repeated icons or subtitles, and the timer moved to the header.
- Low Power Mode moved from the panel to the gear menu.
- The keep-awake switch is redrawn so on and off are obvious, and the action buttons no longer look disabled.
- Keep-awake now runs until you turn it off by default.
- RestBar starts at login by default. It sets this up once, from an Applications folder, and never overrides your choice.
- The battery percentage in the menu bar is now off by default.
- The bundle identifier is now `io.github.noxr3.restbar`. Settings and menu bar position from earlier builds aren't carried over.

### Added

- RestBar now keeps your Mac awake automatically while a coding agent is working, and lets it sleep when the agent is done.
- It can keep running with the lid closed, if you turn that on. Sleep comes back when it stops, quits or crashes, and it stops by itself at 20% battery or if the Mac runs hot.
- Signed, notarized, universal releases, with a Homebrew cask, a one-line installer and a DMG.
- English, Simplified Chinese and Traditional Chinese, following the system language.
- MIT license, contribution and security guides, and a brand guide.

## 1.0

- First version.
