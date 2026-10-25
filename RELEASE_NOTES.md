# Covio 0.5.2 (internal test)

Covio 0.5.2 is an internal test build.
It is not a public release.

## Requirements

- macOS 26 or later.
- Apple Silicon Mac (arm64).

## Installers

| Installer | Size | Model |
| --- | --- | --- |
| `Covio-0.5.2.dmg` | `13,218,304` bytes | Not included |
| `Covio-Offline-0.5.2.dmg` | `1,540,934,144` bytes | Qwen3-VL 2B, revision `9c4f5209e57b31f4b9dfba735de3fb983739c9cc` |

Use the default DMG for online installation.
Use the offline DMG when the target Mac cannot download the model.

## What is new

- The default installer no longer carries model weights.
- The app shows model size, license, network need, progress, failures and removal controls.
- Agent and file naming use one model setup panel.
- The downloader pauses, survives app restart and resumes the same revision.
- A completed package is verified before registry activation.
- App replacement preserves the model registry and model files.
- The optional offline DMG includes the verified 2B model and attribution files.

## Verification

- Kotlin shared tests: `467` passed.
- macOS XCTest: `869` passed and `3` skipped.
- Default DMG: no `model.safetensors` file.
- Offline DMG: one `model.safetensors` file and `14` manifest files.
- Real download: paused at `1,284,301,146` registered bytes and resumed to `1,798,021,605` bytes.
- Corrupt model: rejected with `checksumMismatch`.
- Restricted 64 MiB volume: rejected with `insufficientDisk` and no registry entry.
- App replacement: registry SHA-256 stayed `b8d24a3151601131425effa98e6682fe6eda82a38b4e9f71e29e5333336c10ef`.
- Network-denied file naming: `7` files renamed and `7` undo operations restored.
- Network-denied Agent: `6` steps passed with zero non-loopback network rows.

The full result set is in `docs/research/installer-size-reduction/validation/`.

## Install

1. Open `Covio-0.5.2.dmg` for online installation.
2. Drag `Covio.app` to `Applications`.
3. Open `Covio.app`.
4. Open an AI feature and confirm the model download.

For offline installation, use `Covio-Offline-0.5.2.dmg` in step 1.

**Warning:** This build uses an ad-hoc signature.
macOS Gatekeeper rejects this build.
Allow the app in Privacy & Security, or clear the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/Covio.app
```

## Checksums

```text
5eced02d91ca0eb9585cd028afb6ed5c63d24e06bd55e40e2730b073997aee99  Covio-0.5.2.dmg
8bea35be7bd4c7dd7a439142153292f9672edaee63b3f1d2710eea92d6a754d7  Covio-Offline-0.5.2.dmg
```

## Internal test notes

- Use a test Mac.
- Fan control writes SMC values and requires the privileged helper.
- The battery lid-hold option increases battery drain.
- The update checker reads the GitHub Releases page and ignores pre-release tags.

## Not in this build

- Developer ID signature.
- Apple notarization.
- Public distribution.
- Automatic update install.
- Intel or Universal 2 build.
- App Store build.
