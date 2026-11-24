#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

release="$PWD/build/release"
archive="$release/FTCTeamHub.xcarchive"
app="$archive/Products/Applications/FTCTeamHub.app"
mkdir -p "$release"

python3 scripts/configure-firebase.py
xcodegen generate
xcodebuild -version

xcodebuild -project FTCTeamHub.xcodeproj -scheme FTCTeamHub \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$archive" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  archive 2>&1 | tee "$release/xcodebuild.log"

test -f "$app/FTCTeamHub"
file "$app/FTCTeamHub" | tee "$release/executable.txt"
grep -q 'Mach-O' "$release/executable.txt"
if codesign -dv "$app" >/dev/null 2>&1; then
  echo "Expected an unsigned app bundle" >&2
  exit 1
fi

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
mkdir "$staging/Payload"
ditto "$app" "$staging/Payload/FTCTeamHub.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Info.plist")"
ipa="$release/FTCTeamHub-$version-$build-unsigned.ipa"
ditto -c -k --keepParent "$staging/Payload" "$ipa"
unzip -t "$ipa"
shasum -a 256 "$ipa" | tee "$release/sha256.txt"
git rev-parse HEAD > "$release/commit.txt"
