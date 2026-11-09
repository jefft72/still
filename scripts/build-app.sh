#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Still requires macOS 14 or later and the Swift 6 toolchain.' >&2
  exit 1
fi

swift build --configuration release
binary_dir="$(swift build --configuration release --show-bin-path)"
mkdir -p dist
staging_dir="$(mktemp -d "$PWD/dist/.still-build.XXXXXX")"
cleanup() {
  if [[ ! -e dist/Still.app && -d "$staging_dir/Previous.app" ]]; then
    mv "$staging_dir/Previous.app" dist/Still.app
  fi
  rm -rf "$staging_dir"
}
trap cleanup EXIT

app_path="$staging_dir/Still.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_dir/Still" "$app_path/Contents/MacOS/Still"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
cp LICENSE "$app_path/Contents/Resources/LICENSE"

swift scripts/GenerateIcon.swift "$staging_dir/Still.iconset"
iconutil --convert icns --output "$app_path/Contents/Resources/Still.icns" "$staging_dir/Still.iconset"
plutil -lint "$app_path/Contents/Info.plist"
codesign --force --sign - "$app_path"
codesign --verify --strict "$app_path"

# Replace only our generated output, after the new bundle has passed validation.
if [[ -e dist/Still.app || -L dist/Still.app ]]; then
  existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' dist/Still.app/Contents/Info.plist 2>/dev/null || true)"
  if [[ -L dist/Still.app || "$existing_id" != com.jefft72.still ]]; then
    echo 'Refusing to replace an unrecognized dist/Still.app.' >&2
    exit 1
  fi
  mv dist/Still.app "$staging_dir/Previous.app"
fi
mv "$app_path" dist/Still.app
echo "Built $PWD/dist/Still.app"
