# Maintaining RestBar

## Going public

Do these in order. Changing visibility is the point of no return, because forks and caches keep whatever was public.

1. Remove the personal e-mail address from history. The first commit carries one, and a public repository publishes it forever. While the repository has few commits and no forks, rewrite the author to the GitHub no-reply address and force-push `main`.
2. Run the manual checks below on at least the current macOS version.
3. Change the repository to public.
4. Under Settings: upload the social card, turn on private vulnerability reporting (`SECURITY.md` depends on it), turn on Discussions if you want them, and protect `main` so the macOS CI job must pass.
5. Add the description and topics: `macos`, `menu-bar`, `swift`, `keep-awake`, `battery`, `low-power-mode`.

The copyright is held by Brad personally, as `LICENSE` and `NSHumanReadableCopyright` in `Info.plist` say.

## Manual checks before a release

CI cannot do these: they need real hardware or a password.

- [ ] Low Power Mode turns on and off for battery and for external power, and the panel reads the new value back.
- [ ] On a Mac that reports `powermode` (those with High Power Mode) and on one that reports `lowpowermode`.
- [ ] Restoring a system-wide sleep disable works, and cancelling the password prompt changes nothing.
- [ ] Turn off display, and immediate sleep after its confirmation.
- [ ] Start at login turns on and off, including the approval step in System Settings.
- [ ] Keep-awake stops on unplug and at 20% when those options are on.
- [ ] The moon fills in the menu bar while awake, and the red dot appears beside the timer. Nothing else in the real panel is red, checked switches included.
- [ ] `bash test.sh --integration` passes.

## Releasing

1. Update `CHANGELOG.md`, and set `CFBundleShortVersionString` in `Info.plist` to the new version.
2. Tag it: `git tag v1.2.3 && git push origin v1.2.3`.
3. The Release workflow checks that the tag matches `Info.plist`, runs the tests, builds, and creates a **draft** release with the zip and its SHA-256.
4. Read the draft, then publish it yourself.

Until builds are Developer ID signed and notarized, say so in the release notes: macOS will refuse to open a downloaded copy normally.

## Triage

- Label reports `bug`, `enhancement` or `question`, and ask for the macOS version and Mac model when they are missing. Power behaviour varies by model.
- Keep the scope narrow. Charge limits, fan control and anything that needs a background helper, a network connection or a third-party dependency are out of scope.
- Anything touching a command run with administrator rights gets a second careful read. Those commands stay fixed strings built only from internal values.

## Bundle identifier

It is `io.github.noxr3.restbar`. Changing it resets every user's settings and their menu bar position, so don't, unless the project moves.
