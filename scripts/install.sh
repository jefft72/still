#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

source_app="$PWD/dist/Still.app"
destination_dir="$HOME/Applications"

if [[ $# -gt 0 ]]; then
  if [[ $# -ne 2 || "$1" != --destination || -z "$2" ]]; then
    echo 'Usage: ./scripts/install.sh [--destination <directory>]' >&2
    exit 1
  fi
  destination_dir="$2"
fi

destination_app="$destination_dir/Still.app"

if [[ ! -d "$source_app" ]]; then
  echo 'Build Still first with make app.' >&2
  exit 1
fi

codesign --verify --strict "$source_app"
source_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_app/Contents/Info.plist" 2>/dev/null || true)"
if [[ -L "$source_app" || "$source_id" != com.jefft72.still ]]; then
  echo 'The source bundle is not a recognized Still app. Nothing was changed.' >&2
  exit 1
fi

if [[ -e "$destination_app" || -L "$destination_app" ]]; then
  existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination_app/Contents/Info.plist" 2>/dev/null || true)"
  if [[ -L "$destination_app" || "$existing_id" != com.jefft72.still ]]; then
    echo "An unrelated app already exists at $destination_app. Nothing was changed." >&2
    exit 1
  fi
fi

if pgrep -f "$destination_app/Contents/MacOS/Still" >/dev/null; then
  echo 'Quit the installed copy of Still before updating it.' >&2
  exit 1
fi

mkdir -p "$destination_dir"
staging_dir="$(mktemp -d "$destination_dir/.still-install.XXXXXX")"
cleanup() {
  if [[ ! -e "$destination_app" && -d "$staging_dir/Previous.app" ]]; then
    mv "$staging_dir/Previous.app" "$destination_app"
  fi
  rm -rf "$staging_dir"
}
trap cleanup EXIT
ditto "$source_app" "$staging_dir/Still.app"
codesign --verify --strict "$staging_dir/Still.app"
if [[ -e "$destination_app" ]]; then
  mv "$destination_app" "$staging_dir/Previous.app"
fi
mv "$staging_dir/Still.app" "$destination_app"
echo "Installed $destination_app"
echo 'Open Still from its installation folder or Spotlight.'
