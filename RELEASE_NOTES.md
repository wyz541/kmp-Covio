# Covio 0.5.1 (internal test)

Covio 0.5.1 is an internal test build.
It is not a public release.

## Requirements

- macOS 26 or later.
- Apple Silicon Mac (arm64).

## What is new

- The workbench ignores navigation hover for 0.5 seconds after it opens.
  Clicking a navigation item still works during the protection period.
- The power and fan card popovers keep the workbench open while the user operates them.
  Closing the last popover restores the normal pointer-exit collapse behavior.
- Workbench navigation buttons use Liquid Glass.
- The Files area indexes native macOS screenshots without taking over screenshot capture.
- All 0.5.0 features remain available.
- `config.json` remains compatible with 0.4.2.

## Privileged helper

The helper protocol is version `8`.
It handles sleep, lid leases, charge limits, active discharge, and fan control.
The app and helper must use the same app version.
An outdated helper shows an update-required state.

## Install

1. Open `Covio-0.5.1.dmg`.
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
d3202027f9a39ae3591a5607015922bd6a5fa9d30c45da6ae1a98e3eebdb4bc7  Covio-0.5.1.dmg
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
