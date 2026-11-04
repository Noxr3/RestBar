# Security

## Reporting a vulnerability

Please don't open a public issue. Use [GitHub's private vulnerability reporting](https://github.com/Noxr3/RestBar/security/advisories/new) and include the steps to reproduce it, your macOS version and what an attacker could do.

This is a small project maintained in spare time, so there's no guaranteed response time, but reports are taken seriously and credited if you'd like.

## What matters most here

RestBar makes no network requests and has no background helper. The parts most worth scrutiny are:

- **Administrator commands.** Changing Low Power Mode or restoring system sleep runs `pmset` through the native macOS administrator prompt. These must stay fixed commands built only from internal values. Anything that lets outside input reach them is a vulnerability.
- **Power assertions** that outlive the app or can't be released.
- **Builds.** Releases aren't yet Developer ID signed or notarized, so building from source is the way to be sure what you're running.

## Supported versions

Only the latest release and the `main` branch receive fixes.
