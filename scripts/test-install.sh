#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -d dist/Still.app ]]; then
  echo 'Build the app with make app before running installer tests.' >&2
  exit 1
fi

test_root="$(mktemp -d "${TMPDIR:-/tmp}/still-installer-test.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
destination="$test_root/Applications"

./scripts/install.sh --destination "$destination"
codesign --verify --strict "$destination/Still.app"
./scripts/install.sh --destination "$destination"
codesign --verify --strict "$destination/Still.app"
echo 'PASS: fresh install and recognized app update'

rm -rf "$destination/Still.app"
mkdir -p "$destination/Still.app"
printf 'preserve this app\n' > "$destination/Still.app/sentinel"
if ./scripts/install.sh --destination "$destination"; then
  echo 'FAIL: installer replaced an unrelated app' >&2
  exit 1
fi
[[ "$(cat "$destination/Still.app/sentinel")" == 'preserve this app' ]]
echo 'PASS: unrelated app remains untouched'

rm -rf "$destination/Still.app"
ln -s "$PWD/dist/Still.app" "$destination/Still.app"
if ./scripts/install.sh --destination "$destination"; then
  echo 'FAIL: installer replaced a symlink' >&2
  exit 1
fi
[[ -L "$destination/Still.app" ]]
codesign --verify --strict dist/Still.app
echo 'PASS: symlink and its target remain untouched'

if ./scripts/install.sh --destination; then
  echo 'FAIL: installer accepted an invalid destination argument' >&2
  exit 1
fi
echo 'PASS: invalid arguments are rejected'
