# Covio 0.5.2 (internal test)

Covio 0.5.2 is an internal test build.
It is not a public release.

## Requirements

- macOS 26 or later.
- Apple Silicon Mac (arm64).

## What is new

- Charge-limit target repair continues while the battery is charging.
- Target repair retries are rate-limited and no longer remain blocked in `applying`.
- The current-target field reports the target that macOS actually registered.
- Active discharge keeps the configured limit instead of falling back to the old target.
- A developer-only fan capability preview uses Swift Charts.
  Production fan control is unchanged.
- All 0.5.1 features remain available.
- `config.json` remains compatible with 0.4.2.

## Privileged helper

The helper protocol is version `8`.
It handles sleep, lid leases, charge limits, active discharge, and fan control.
The app and helper must use the same app version.
An outdated helper shows an update-required state.

## Verification

- The Kotlin shared tests passed.
- The macOS SwiftUI suite passed with 798 tests and 2 skipped tests.
- The offline file-naming bundle verification passed with no non-loopback network rows.
- The release app is arm64, requires macOS 26, and has a valid ad-hoc signature.

## Install

1. Open `Covio-0.5.2.dmg`.
2. Drag `Covio.app` to `Applications`.
3. Open `Covio.app`.

**Warning:** This build uses an ad-hoc signature.
macOS Gatekeeper rejects this build.
Allow the app in Privacy & Security, or clear the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/Covio.app
```

## Checksum

```text
8fba01f6eacba17921fbd1bd337bac68bcc59f6aae9571faeeab3dc11da2d6d4  Covio-0.5.2.dmg
```

## Internal test notes

- Use a test Mac.
- Fan control writes SMC values and requires the privileged helper.
- The battery lid-hold option increases battery drain.
- The battery target-repair path still needs real-Mac acceptance with the 0.5.2 helper.
- The exact 8 GB hardware path still needs separate validation.
- The update checker reads the GitHub Releases page and ignores pre-release tags.

## Not in this build

- No automatic update install.
- No Developer ID signature.
- No notarization.
- No Intel or Universal 2 build.
- No App Store build.
