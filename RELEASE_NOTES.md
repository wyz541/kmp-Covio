# Covio 0.4.2 (internal test)

> **Warning:** This file still describes 0.4.2.
> The app version is `0.5.0` in `kmpDomain/src/com/wyz/covio/core/Models.kt`.
> `scripts/create-release.sh` reads that version.
> Rewrite this file before the next release.
> Run the real-Mac acceptance checklist first, then rewrite this file from the results.
>
> The next release is 0.5.0. It requires macOS 26 or later.
> The SwiftUI host uses Liquid Glass, and the Hub has a new layout.
> macOS 14 and macOS 15 are no longer supported. The 0.4.2 text below still says macOS 12.
>
> Release notes must say the build passed real-Mac acceptance.
> That checklist has not run yet, so this text is not rewritten.
> The pending items are in `docs/adr/adr-0001-macos-ui-swiftui.md`, section 未决事项.

## What 0.5.0 will change

- The macOS interface is SwiftUI. The shared logic is Kotlin Multiplatform, module `kmpDomain`.
- The Hub has a floating navigation rail on the left and a floating capsule at the top.
  The rail holds the search box, the six tabs, and a bottom group with the run indicator,
  settings, language, and quit.
- The capsule holds the page title and the page actions. On the Settings tab it holds the
  six section switches.
- The search box searches settings. Selecting a result jumps to that row and highlights it.
- The app requires macOS 26 or later.
- The app adds the clipboard history.
- The Files tab adds local offline auto naming with preview, safe rename, and undo.
- The Monitor tab shows a Stats-style dashboard for CPU, GPU, memory, disk, network, and battery.
- The Monitor power card shows the supply state, battery level, temperature, power draw,
  and recent trends. Its expandable detail panel shows estimated time, charging data,
  power events, and the top three energy users from the last hour.
- `config.json` is compatible with 0.4.2 in both directions.

The details are in `README.md`, section "What is new in 0.5.0".

## Covio 0.4.2 (the text below describes this build)

This is an internal test build.
It is not a public release.

This build renames the project to Covio.
The Kotlin package is `com.wyz.covio`.
The application identifier is `com.wyz.covio`.

## Requirements

- macOS 12 or later.
- An Apple Silicon Mac (arm64).
- JDK 25 is not required to run the app.

## What is in this build

- The Covio project name.
- The `com.wyz.covio` Kotlin package and application identifier.
- Covio paths for settings, logs, screenshots, the helper, and the LaunchAgent.
- A menu-bar app with no Dock icon.
- A full-width screenshot toolbar at the top of the screen.
- Screenshot takeover with the system thumbnail hidden.
- Screenshot copy, preview, Markup, context menu, and drag behavior.
- A `Control+Option+T` toolbar shortcut.
- Screenshot takeover restore on disable or normal exit.
- Sleep modes 0, 3, and 25 through `hibernatemode`.
- Event-driven lid detection with `IOServiceAddInterestNotification`.
- Battery sleep rules for capacity and time remaining.
- AC idle-sleep and lid-sleep prevention.
- Battery lid-sleep prevention. This option drains the battery.
- DarkWake awareness from the `pmset` wake log.
- A full wake restores the sleep timers or recalculates the power policy.
- A unified lid-hold policy for manual, timed, and power rules.
- Timed cancel for prevention rules.
- Sleep Now and Turn Display Off.
- LaunchAgent start at login.
- LaunchAgent restart after a crash.
- Configuration reset from the Tray menu and the General settings page.
- A 60-second cache for the system idle timeout.
- A 60-second cache for the wake log.
- Notifications and a rotating log.
- Stable update checks from the GitHub Releases page.
- English and Simplified Chinese text.
- A single-instance lock.

## Clean install

Covio uses the `com.wyz.covio` identifier.
Covio does not migrate older internal-test settings.
Covio does not modify older apps, helpers, or configurations.
Uninstall the older internal-test app before you use this build.

## Privileged helper

The helper accepts only these commands:

- `version`
- `setDisableSleep`
- `setHibernateMode`

The app and the helper must use version `0.4.2`.
An old helper shows "Helper: Update Required".

## Install

1. Open `Covio-0.4.2.dmg`.
2. Drag `Covio.app` to `Applications`.
3. Open `Covio.app`.

**Warning:** This build uses an ad-hoc signature.
macOS Gatekeeper rejects this build.
If macOS blocks the app, open the app from the `Privacy & Security` settings, or clear the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/Covio.app
```

## Checksum

```text
SHA-256: 1237b65bdb8c0c15f1300a0b6ca095f8280db3b1894f1018fb2803b386333344
Covio-0.4.2.dmg
```

## Internal test notes

- Use a test Mac.
- The battery lid-hold option drains the battery.
- Complete the real-Mac checklist in `README.md`.
- Remove the helper from the Tray menu after the test.
- Export the log when you report a problem.
- The update checker reads the Releases page. The update checker does not use the GitHub REST API.
- The update checker ignores pre-release tags.
- This build does not download or install updates.

## Not in this build

- No automatic update install.
- No Developer ID signature.
- No notarization.
- No Intel or Universal 2 build.
- No App Store build.
