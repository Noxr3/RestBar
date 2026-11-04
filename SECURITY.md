# Security

## Reporting a vulnerability

Please don't open a public issue. Use [GitHub's private vulnerability reporting](https://github.com/Noxr3/RestBar/security/advisories/new) and include the steps to reproduce it, your macOS version and what an attacker could do.

This is a small project maintained in spare time, so there's no guaranteed response time, but reports are taken seriously and credited if you'd like.

## What matters most here

RestBar makes no network requests and installs no background helper. The parts most worth scrutiny are:

- **Administrator commands.** Changing Low Power Mode or restoring system sleep runs `pmset` through the native macOS administrator prompt. These must stay fixed commands built only from internal values. Anything that lets outside input reach them is a vulnerability.
- **The lid-closed permission.** `/etc/sudoers.d/restbar` lets one account run exactly `pmset -a disablesleep 0` and `1` without a password. Anything that widens it, or lets outside input into it, is a vulnerability.
- **System sleep left off** after RestBar stops, crashes or restarts. The watcher process and the restore at launch exist to prevent this.
- **Agent detection** reads the process list. It must never store it, log it or send it anywhere.
- **Power assertions** that outlive the app or can't be released.
- **Builds.** Releases are signed with a Developer ID and notarized by Apple. `install.sh` checks the signing team, and the checksums are on each release.

## Supported versions

Only the latest release and the `main` branch receive fixes.
