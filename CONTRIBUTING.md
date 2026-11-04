# Contributing to RestBar

Thanks for helping. Bug reports are especially useful, because power behaviour varies between Mac models and macOS versions in ways no test here can see.

## Reporting a bug

Open an issue using the bug template and include your Mac model and macOS version. For anything about sleep or Low Power Mode, the output of `pmset -g custom` and `pmset -g assertions` usually settles it. Look through it first and remove anything you'd rather not share.

For a security problem, follow [SECURITY.md](SECURITY.md) instead.

## Making a change

You need an Apple Silicon Mac on macOS 13 or later, with Xcode or the Command Line Tools.

```sh
bash test.sh                 # Deterministic checks, on every change
bash test.sh --integration   # Real power APIs, if you touched power code
bash build.sh && open dist/RestBar.app
```

Before opening a pull request:

- Keep it to one change, and open an issue first if it's a large one.
- Add a check in `Tests/main.swift` for any new parsing or policy logic.
- Try the change in the real app, and say in the pull request what you tried and on which Mac. If you changed how the app looks, include a screenshot.
- Regenerate the README screenshots with `scripts/PanelShot.swift` if the panel changed visibly.

## What fits

RestBar stays small on purpose. It has no third-party dependencies, makes no network requests, collects no data and has no background helper. Proposals that would change any of those will almost certainly be declined, however good they are. Charge limits and fan control are out of scope too.

Commands that run with administrator rights must stay fixed strings built only from internal values, never from user input or anything read from the system.

For how RestBar should look and sound, see [docs/BRAND.md](docs/BRAND.md). In short: monochrome, red only for the moon and for keeping your Mac awake, and nothing said twice.

## Conduct

This project follows the [Code of Conduct](CODE_OF_CONDUCT.md). By contributing, you agree your work is released under the [MIT License](LICENSE).
