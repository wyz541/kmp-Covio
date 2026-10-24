# Covio 0.5.0 (internal test)

Covio 0.5.0 is an internal test build.
It is not a public release.

## Requirements

- macOS 26 or later.
- Apple Silicon Mac (arm64).

## What is new

- The macOS host is SwiftUI. Shared domain logic is Kotlin Multiplatform in `kmpDomain`.
- The Hub uses a Liquid Glass base plate and an adaptive glass navigation layer.
- Settings search opens the matching Settings row and highlights it.
- Clipboard history keeps recent text, images, and files.
- Files supports local offline auto naming for text, PDF, images, code, and mixed files.
  It includes preview, safe rename, and undo.
- Monitor shows CPU, GPU, memory, disk, network, battery, and power telemetry.
- The power card shows supply state, temperature, power draw, charging data, and energy users.
- The fan card shows control temperature and RPM trends.
  Its popover provides automatic curves, manual RPM, presets, sensor selection,
  and automatic return to system control.
- Sleep, lid, DarkWake, helper, screenshot toolbar, and LaunchAgent functions remain available.
- `config.json` remains compatible with 0.4.2.

## Privileged helper

The helper protocol is version `8`.
It handles sleep, lid leases, charge limits, active discharge, and fan control.
The app and helper must use the same app version.
An outdated helper shows an update-required state.

## Install

1. Open `Covio-0.5.0.dmg`.
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
844f2e88db4aee821532d47e3a99edc7375a59dd8bfb86e6e99914be5b1a7c61  Covio-0.5.0.dmg
```

## Internal test notes

- Use a test Mac.
- Fan control writes SMC values and requires the privileged helper.
- The battery lid-hold option increases battery drain.
- The exact 8 GB hardware path still needs separate validation.
- The update checker reads the GitHub Releases page and ignores pre-release tags.

## Not in this build

- No automatic update install.
- No Developer ID signature.
- No notarization.
- No Intel or Universal 2 build.
- No App Store build.
