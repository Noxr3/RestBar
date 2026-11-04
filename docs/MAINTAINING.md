# Maintaining RestBar

## Going public

Do these in order. Changing visibility is the point of no return, because forks and caches keep whatever was public.

1. Remove the personal e-mail address from history. The first commit carries one, and a public repository publishes it forever. While the repository has few commits and no forks, rewrite the author to the GitHub no-reply address and force-push `main`.
2. Run the manual checks below on at least the current macOS version.
3. Change the repository to public, create the public `Noxr3/homebrew-tap` repository with the cask from `scripts/release.sh`, and publish the first release. Homebrew, `install.sh` and the download links only work from this point.
4. Under Settings: upload the social card, turn on private vulnerability reporting (`SECURITY.md` depends on it), turn on Discussions if you want them, and protect `main` so the macOS CI job must pass.
5. Add the description and topics: `macos`, `menu-bar`, `swift`, `keep-awake`, `battery`, `low-power-mode`.

The copyright is held by Brad personally, as `LICENSE` and `NSHumanReadableCopyright` in `Info.plist` say.

## Manual checks before a release

CI cannot do these: they need real hardware or a password.

- [ ] Low Power Mode turns on and off for battery and for external power from the gear menu, and the menu shows the new value afterwards.
- [ ] On a Mac that reports `powermode` (those with High Power Mode) and on one that reports `lowpowermode`.
- [ ] Restoring a system-wide sleep disable works, and cancelling the password prompt changes nothing.
- [ ] Turn off display, and immediate sleep after its confirmation.
- [ ] A first launch from Applications adds the login item once. Turning it off under the gear menu survives a relaunch and a reinstall. The approval step in System Settings works.
- [ ] With the lid-closed option on and an agent working, close the lid for ten minutes: `pmset -g log | grep -E ' Sleep | Wake '` shows no sleep, and the agent kept going.
- [ ] When that agent finishes, or at 20% battery, `pmset -g` no longer lists `SleepDisabled`. Force quit RestBar during a session and check the same.
- [ ] An idle agent session doesn't start keep-awake, and a busy one does within about ten seconds.
- [ ] Keep-awake stops on unplug and at 20% when those options are on.
- [ ] While awake, the moon is a red disc in the menu bar and the panel, and the keep-awake switch is red. No other control in the real panel is red.
- [ ] The panel appears in each language: change the system language, or run `open RestBar.app --args -AppleLanguages '(zh-Hant)'`.
- [ ] `bash test.sh --integration` passes.

## Releasing

Releases are signed and notarized on a maintainer's Mac, not in CI, so the Developer ID key stays out of a public repository's workflows.

1. Update `CHANGELOG.md`, and raise `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`. Merge to `main`.
2. Once per Mac, store the notarization key: `xcrun notarytool store-credentials restbar-notary --key <AuthKey.p8> --key-id <id> --issuer <id>`.
3. Run `bash scripts/release.sh`. It runs the tests, builds a universal app, notarizes and staples the app and the DMG, and creates a **draft** release. `--dry-run` does everything except notarizing and uploading.
4. Read the draft, then publish it yourself.
5. Copy `dist/release/restbar.rb` to `Casks/restbar.rb` in `Noxr3/homebrew-tap`.

## Triage

- Label reports `bug`, `enhancement` or `question`, and ask for the macOS version and Mac model when they are missing. Power behaviour varies by model.
- Keep the scope narrow. Charge limits, fan control and anything that needs a background helper, a network connection or a third-party dependency are out of scope.
- Anything touching a command run with administrator rights gets a second careful read. Those commands stay fixed strings built only from internal values.

## Bundle identifier

It is `io.github.noxr3.restbar`. Changing it resets every user's settings and their menu bar position, so don't, unless the project moves.
