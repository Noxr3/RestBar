#!/bin/bash
# Builds, signs and notarizes a release on this Mac, then creates a DRAFT GitHub release
# for a person to read and publish. Runs locally on purpose: it keeps the Developer ID
# key out of the CI of a public repository.
#
# First-time setup, once per Mac:
#   xcrun notarytool store-credentials restbar-notary --key <AuthKey.p8> --key-id <id> --issuer <id>
#
#   bash scripts/release.sh           the real thing, from a clean, pushed main
#   bash scripts/release.sh --dry-run signs and packages, skips notarizing and GitHub
set -euo pipefail
cd "$(dirname "$0")/.."

identity="${RESTBAR_SIGN_IDENTITY:-Developer ID Application: YIJUN BAO (4SGLPC8L36)}"
profile="${RESTBAR_NOTARY_PROFILE:-restbar-notary}"
dry_run=0
[ "${1:-}" = "--dry-run" ] && dry_run=1

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
tag="v$version"

notarize() {
  [ "$dry_run" = 1 ] && return 0
  /usr/bin/xcrun notarytool submit "$1" --keychain-profile "$profile" --wait
}

if [ "$dry_run" = 0 ]; then
  if [ -n "$(git status --porcelain)" ]; then echo "Commit your changes first."; exit 1; fi
  git fetch -q origin main
  if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then echo "Release from the pushed main."; exit 1; fi
  if git ls-remote --exit-code --tags origin "$tag" >/dev/null; then echo "$tag already exists. Raise the version in Info.plist."; exit 1; fi
  /usr/bin/xcrun notarytool history --keychain-profile "$profile" >/dev/null
fi

bash test.sh
rm -rf dist
SIGN_IDENTITY="$identity" bash build.sh

out=dist/release
mkdir -p "$out"

# The app has to be notarized and stapled before it goes into either package, so it
# also opens on a Mac with no network.
/usr/bin/ditto -c -k --sequesterRsrc --keepParent dist/RestBar.app "$out/submit.zip"
notarize "$out/submit.zip"
rm "$out/submit.zip"
[ "$dry_run" = 1 ] || /usr/bin/xcrun stapler staple dist/RestBar.app
/usr/bin/ditto -c -k --sequesterRsrc --keepParent dist/RestBar.app "$out/RestBar.zip"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
/usr/bin/ditto dist/RestBar.app "$stage/RestBar.app"
ln -s /Applications "$stage/Applications"
/usr/bin/hdiutil create -quiet -volname RestBar -srcfolder "$stage" -ov -format UDZO "$out/RestBar.dmg"
/usr/bin/codesign --force --timestamp --sign "$identity" "$out/RestBar.dmg"
notarize "$out/RestBar.dmg"
[ "$dry_run" = 1 ] || /usr/bin/xcrun stapler staple "$out/RestBar.dmg"

(cd "$out" && /usr/bin/shasum -a 256 RestBar.zip > RestBar.zip.sha256 && /usr/bin/shasum -a 256 RestBar.dmg > RestBar.dmg.sha256)

sed -e "s/@VERSION@/$version/" -e "s/@SHA256@/$(cut -d' ' -f1 "$out/RestBar.zip.sha256")/" \
  packaging/homebrew/restbar.rb > "$out/restbar.rb"

if [ "$dry_run" = 1 ]; then
  echo "Dry run finished. Not notarized, nothing uploaded: $out"
  exit 0
fi

/usr/sbin/spctl --assess --type execute dist/RestBar.app
/usr/sbin/spctl --assess --type open --context context:primary-signature "$out/RestBar.dmg"

notes="$(awk -v heading="## $version" '$0 == heading { found = 1; next } /^## / { found = 0 } found' CHANGELOG.md)"
if [ -z "$notes" ]; then echo "CHANGELOG.md has no section called ## $version."; exit 1; fi

gh release create "$tag" "$out/RestBar.dmg" "$out/RestBar.zip" "$out/RestBar.dmg.sha256" "$out/RestBar.zip.sha256" \
  --draft --target "$(git rev-parse HEAD)" --title "RestBar $version" --notes "$notes"

echo "Draft release created. After publishing it, copy $out/restbar.rb to Casks/ in Noxr3/homebrew-tap."
