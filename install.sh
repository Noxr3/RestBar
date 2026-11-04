#!/bin/bash
# Installs the latest RestBar release:
#   curl -fsSL https://raw.githubusercontent.com/Noxr3/RestBar/main/install.sh | bash
#
# It checks the download's checksum, who signed it, and that Apple notarized it. It asks
# for no password and changes nothing outside the Applications folder it installs to.
set -euo pipefail

team="4SGLPC8L36"
base="${RESTBAR_RELEASE_URL:-https://github.com/Noxr3/RestBar/releases/latest/download}"

fail() { echo "RestBar: $1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "this app is for macOS."
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 13 ] || fail "macOS 13 or later is required."

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "Downloading RestBar..."
curl -fsSL "$base/RestBar.zip" -o "$work/RestBar.zip" || fail "the download failed."
curl -fsSL "$base/RestBar.zip.sha256" -o "$work/RestBar.zip.sha256" || fail "the checksum download failed."
(cd "$work" && shasum -a 256 -c RestBar.zip.sha256 >/dev/null) || fail "the checksum doesn't match, so nothing was installed."

ditto -x -k "$work/RestBar.zip" "$work/unpacked"
app="$work/unpacked/RestBar.app"
[ -d "$app" ] || fail "the download doesn't contain RestBar.app."

codesign --verify --strict "$app" || fail "the app's signature is invalid, so nothing was installed."
# Into a variable first: grep -q exits at its first match, and under pipefail the pipe
# that breaks would read as a failure.
signature="$(codesign -dv "$app" 2>&1)"
case "$signature" in
  *"TeamIdentifier=$team"*) ;;
  *) fail "the app isn't signed by RestBar's developer, so nothing was installed." ;;
esac
if [ "${RESTBAR_SKIP_NOTARY_CHECK:-0}" != 1 ]; then
  spctl --assess --type execute "$app" 2>/dev/null || fail "Apple hasn't notarized this app, so nothing was installed."
fi

if [ -n "${RESTBAR_INSTALL_DIR:-}" ]; then
  target="$RESTBAR_INSTALL_DIR"
elif [ -w /Applications ]; then
  target="/Applications"
else
  target="$HOME/Applications"
fi
mkdir -p "$target"

if [ "${RESTBAR_NO_LAUNCH:-0}" != 1 ]; then
  osascript -e 'tell application id "io.github.noxr3.restbar" to quit' >/dev/null 2>&1 || true
  sleep 1
fi
rm -rf "$target/RestBar.app"
ditto "$app" "$target/RestBar.app"
echo "Installed to $target/RestBar.app"

if [ "${RESTBAR_NO_LAUNCH:-0}" != 1 ]; then
  open "$target/RestBar.app"
  echo "RestBar is running. Look for the moon in your menu bar."
  echo "On a full menu bar macOS may hide it behind the notch: hold Command and drag other icons to make room."
fi
