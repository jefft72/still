# Working on Still

Still is a native macOS app built with SwiftUI and AppKit.
It requires macOS 14 or later and a Swift 6 toolchain, available with Xcode 16 or later.
It has no package dependencies, accounts, or network services.
CI uses Xcode 26.3, including its bundled formatter, to keep formatting checks consistent.
For matching local results, use that toolchain when running `make format` and `make lint`.

## Build and run

```sh
make check
make run
```

`make check` runs formatting checks, the core tests, and a debug build.
`make run` creates an app bundle at `dist/Still.app` and opens it.
Use `make format` to apply the project formatter before committing.

## Install

```sh
make install
```

This builds a release app and installs it in `~/Applications/Still.app` without administrator access.
Quit an installed copy before updating it.
The installer refuses to replace an unrelated app or a symlink.
It never changes a system Applications folder.
For another location, run `./scripts/install.sh --destination /path/to/folder` after building.
Run `make test-install` after `make app` to verify installation, updates, and refusal to replace unrelated files in a temporary directory.

Builds are ad hoc signed for local use, not notarized with an Apple Developer account.
A downloaded build may require approval in System Settings > Privacy & Security before macOS allows it to open.
Building from source avoids the downloaded-app quarantine step.

## Structure

`Sources/Still` contains the native interface, window behavior, and procedural audio.
`Sources/StillCore` contains the session state and local persistence.
`Tests/StillCoreTests` exercises countdown behavior, completion, history, and captured thoughts.
`scripts/GenerateIcon.swift` draws the app icon with AppKit during packaging.
Build outputs and generated icons stay in `dist` and are not committed.

## Release builds

```sh
make app
ditto -c -k --sequesterRsrc --keepParent dist/Still.app dist/Still-macOS.zip
```

The build targets the architecture of the machine running it.
GitHub Actions checks the source and uploads the packaged app as a workflow artifact.
The source remains the portable option for Macs with a different processor architecture.
