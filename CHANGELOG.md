# Changelog

## Unreleased

### Fixed

- Low Power Mode could not be used on Macs that report `powermode` instead of `lowpowermode`, such as those with High Power Mode. The switch stayed disabled with "not available".

### Changed

- New look: black and white on a dot grid, replacing the green theme and coffee cup. The moon is a crescent with a red dot at rest, and a full red disc while keeping the Mac awake. The keep-awake switch turns red with it; nothing else does.
- A much simpler panel that fits without scrolling: no cards, repeated icons or subtitles, and the timer moved to the header.
- The battery percentage in the menu bar is now off by default.
- The bundle identifier is now `io.github.noxr3.restbar`. Settings and menu bar position from earlier builds aren't carried over.

### Added

- MIT license, contribution and security guides, and a brand guide.
- A release workflow that creates a draft release from a version tag.

## 1.0

- First version.
