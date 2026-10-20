# Covio

Covio is a macOS menu-bar app.
It controls sleep behavior and provides a screenshot toolbar at the top of the screen.

Covio is an independent implementation.
It does not use the Tendedero name, icon, or documentation images.

## Product design

- [Design contract](docs/covio-design-contract.json) is the machine-readable design authority.
- [Design contract schema](docs/covio-design-contract.schema.json) validates the contract structure.
- The Covio Figma file is the visual projection used for implementation verification.
- Static design status: 8 pages, 8 sections, 35 boards, 130 source component sets, 186 component nodes, and 42 prototype reactions. Static visual audit passed.

Each component carries a `composeMapping` and a `swiftMapping`.
The macOS host reads the Swift mapping. The Compose host reads the other one.

**Note:** The JSON schema cannot express "`swiftMapping` is required on macOS".
The check is in `scripts/validate-contract.py`.
The script also checks the rules that cross two sections of the contract.

## Research

- [Research archive](docs/research/README.md) defines the research archive rules and links each research topic.

## Workflow

Ideas turn into research reports, research reports into decisions, and decisions into issues.

- [Agent contract](AGENTS.md) is the rule set that Claude Code and Codex load each session.
- [Workflow](docs/process/workflow.md) is the seven-step process. The agent contract carries the per-session rules.
- [Architecture decisions](docs/adr/) hold the accepted decisions. The template is `docs/adr/adr-template.md`.

A big feature gets one parent issue and child issues, linked as GitHub sub-issues.
A small feature gets one issue.
Progress is read from GitHub. The repository does not hold issue definitions.

`main` is the trunk. Changes to `main` go through a pull request.

## Download (internal test)

This repository is under internal test.
The current build is not a public release.

0.4.2 is the last published build. It is the Compose version.
0.5.0 is the SwiftUI version. It is not published yet.
Build 0.5.0 locally with `bash scripts/package-macos-swift.sh`.

- [Covio-0.4.2.dmg](https://github.com/wises231/kmp-Covio/releases/download/v0.4.2/Covio-0.4.2.dmg)
- [Release page](https://github.com/wises231/kmp-Covio/releases/tag/v0.4.2)

Install steps:

1. Open `Covio-0.4.2.dmg`.
2. Drag `Covio.app` to `Applications`.
3. Open `Covio.app`.

Covio uses a clean install.
Covio does not copy settings from older internal-test builds.
The old apps, helpers, and settings remain unchanged.

**Warning:** This build uses an ad-hoc signature.
macOS Gatekeeper rejects this build.
If macOS blocks the app, allow the app in the "Privacy & Security" settings, or clear the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/Covio.app
```

The download has this SHA-256 checksum:

```text
1237b65bdb8c0c15f1300a0b6ca095f8280db3b1894f1018fb2803b386333344  Covio-0.4.2.dmg
```

## What is new in 0.5.0

- The macOS interface is SwiftUI. The shared logic is Kotlin Multiplatform, module `kmpDomain`.
- The app requires macOS 26 or later. Covio 0.4.x stays on macOS 12.
- The Hub has a new layout. A floating navigation rail is on the left. A floating capsule is at the top.
  - The rail holds the search box, the six tabs, and a bottom group.
  - The bottom group holds the run indicator, the settings button, the language menu, and quit.
  - The capsule holds the page title and the page actions.
  - On the Settings tab the capsule holds the six section switches.
  - The page title moved from the page body to the capsule.
- The search box searches settings. Selecting a result opens the Settings tab.
  The Hub scrolls to that row and highlights it for 1.2 seconds.
- Press Escape to clear the search. Press Escape again to collapse the Hub.
- The navigation rail and the capsule use Liquid Glass. In System Settings, turn on Reduce motion to switch without animation.
- The app adds the clipboard history. See the Clipboard history section.
- The screenshot toolbar behaves as in 0.4.2. The implementation is Swift.
- The app keeps the sleep, lid, DarkWake, helper, and LaunchAgent functions.
- The Settings tab keeps the same six sections.
- `config.json` is compatible with 0.4.2 in both directions.

## What is new in 0.4.2

- The project name is Covio.
- The Kotlin package is `com.wyz.covio`.
- The application identifier is `com.wyz.covio`.
- The app uses `Covio` for settings, logs, the helper, and the LaunchAgent.

## What is new in 0.4.1

- The app fixes a crash that happened when you opened Markup from a screenshot card.
- The app opens Markup on the main thread through a native helper.
- If Markup is unavailable, the app opens Preview.

## What is new in 0.4.0

- The app adds the screenshot toolbar.
- The app keeps the sleep, lid, DarkWake, helper, and LaunchAgent functions.
- The app adds a full-width screenshot toolbar at the top of the mouse screen.
- Screenshot takeover is on by default.
- New screenshots appear in the toolbar.
- A click copies the image and file URL.
- A double-click opens the preview.
- A long press opens macOS Markup. If Markup is unavailable, Preview opens.
- A right-click opens the screenshot menu.
- Dragging to an app copies the file and keeps the card.
- Dragging to a folder or the Desktop moves the file and removes the card.
- Dragging to the Trash deletes the file and removes the card.
- A canceled or failed drag returns the card.
- `Control+Option+T` shows or hides the toolbar.
- The Tray menu and the Top Shelf settings page control screenshot behavior.
- The settings and log use the `com.wyz.covio` application identifier.

## Screenshot toolbar

The toolbar width equals the full width of the screen under the mouse pointer.
The toolbar height is 210 points.
The toolbar shows 3 to 12 screenshot cards.
The mouse must stay on the menu bar for 0.25 seconds before the toolbar appears.
The toolbar hides 0.5 seconds after the mouse leaves it.
A new screenshot hides the toolbar after 2.5 seconds.
The toolbar does not appear in a full-screen Space.

Screenshot takeover writes these macOS settings:

- `location`
- `location-screenshot`
- `show-thumbnail`

Covio saves the old values before the first change.
Covio restores the old values when you disable takeover or quit the app normally.
If the app crashes, the next start reads the saved values and keeps them for the next restore.

The screenshot directory is:

```text
~/Library/Application Support/Covio/Screenshots
```

Screenshots stay on this Mac.
Covio does not send screenshot data to the network.

## Clipboard history

Covio keeps a clipboard history. Open the Hub and select the Clipboard tab.

- Copy text, links, colors, images, or files. Covio adds each one to the list.
- Select an item to copy it back to the clipboard.
- Select Paste to copy the item and press `Command+V` in the front app.
- Select Pin to keep an item. Clear All keeps pinned items.
- Select Pause to stop recording. Covio keeps the list.
- `Shift+Command+V` pastes the next item from the paste stack.
- `Shift+Command+C` copies the selection of the front app.

The Clipboard settings page shows the two shortcuts. Select a different combination when another app already uses one. Covio shows `Registration failed` in that case.

Paste needs the Accessibility permission. Without it, copying still works and you press `Command+V` yourself.

The retention policy keeps 100 items, 7 days, and 200 MB.
Pinned items are always kept.
Images are stored as files. Text recognition runs on each image, so you can find an image by the text inside it.

The clipboard directory is:

```text
~/Library/Application Support/Covio/Clipboard
```

Clipboard data stays on this Mac.
Covio does not send clipboard data to the network.

## Sleep and lid features

- Sleep at the low-battery capacity threshold.
- Sleep at the low-battery time threshold.
- Prevent idle sleep on AC power.
- Prevent lid sleep on AC power.
- Prevent lid sleep on battery power. This option drains the battery.
- Detect DarkWake and full wake events from the `pmset` wake log.
- Sleep immediately when the lid closes.
- Cancel a prevention rule after a selected delay.
- Run Sleep Now or Turn Display Off from the Tray menu.
- Set hibernation mode 0, 3, or 25.
- Detect lid changes with `IOServiceAddInterestNotification`.
- Start at login with a LaunchAgent.
- Restart after a crash with `KeepAlive.SuccessfulExit=false`.
- Clear the configuration from the Tray menu or the General settings page.
- Cache the system idle timeout for 60 seconds.
- Cache the wake log for 60 seconds.
- Show notifications and write a rotating log.
- Check the GitHub Releases page for a stable update.
- Show English and Simplified Chinese text.

## Requirements

- macOS 26 or later. Covio 0.4.x stays on macOS 12.
- An Apple Silicon Mac.
- Xcode 27 to build the SwiftUI host.
- JDK 25 for the shared layer.

## Build and test

Run every test:

```sh
bash scripts/test-all.sh
```

The script runs the Kotlin tests, checks the design-contract constants, checks the contract rules that the schema cannot express, checks with the helper cutover script, and runs the macOS XCTest suite.

Build one side only:

```sh
/bin/sh ./kotlin test          # the shared layer, on jvm and macosArm64
bash scripts/build-kmp-framework.sh   # write build/kmp-framework/kmpDomain.framework
bash scripts/build-macos-swift.sh     # build the SwiftUI host
bash scripts/test-macos-swift.sh      # run the SwiftUI host XCTest suite
```

After you change the design contract, run these two:

```sh
python3 scripts/validate-contract.py            # the cross-section rules
python3 scripts/generate-contract-constants.py  # rewrite the Swift constants
```

The SwiftUI host reads its text and its tokens from `ContractCopy.swift` and `ContractTokens.swift`.
Both files are generated. Do not edit them by hand.

The macOS host is SwiftUI. The shared layer is Kotlin Multiplatform, module `kmpDomain`.
The host links `kmpDomain.framework`. Open `macosApp/Covio.xcodeproj` to work on the host.

The project signs ad-hoc by default.
Ad-hoc signing has no Team ID, so macOS identifies the app by its cdhash.
Every build changes the cdhash, so macOS treats each build as a new app.
Then macOS asks for Accessibility again, and posts the "Device Control and Data Access" notice again.

To keep the grant across builds, pin a code-signing certificate:

1. Create a certificate. The steps are in `docs/adr/adr-0005-local-code-signing.md`.
2. Create `macosApp/Signing.local.xcconfig`:

   ```text
   CODE_SIGN_IDENTITY = Covio Dev
   CODE_SIGN_STYLE = Manual
   ```

3. Build the app, then grant Accessibility once. Later builds keep the grant.

`macosApp/Signing.local.xcconfig` is in `.gitignore`.
CI has no certificate, so CI uses the ad-hoc default.

The SwiftUI host is on macOS only.
It uses the same `config.json` as the Compose version.
The two versions use different lock files, so both can run at the same time.

## Package

```sh
bash scripts/package-macos-swift.sh
```

The script writes these files:

- `dist/Covio.app`
- `dist/Covio-0.5.0.dmg`

The script archives the Xcode project in the Release configuration.
The script reads the version from `APP_VERSION` and checks that the bundle carries it.
The script checks that the bundle carries `macosApp/src/Covio.icns` and applies an ad-hoc signature.
The script builds the DMG with `diskutil image create`.

The icon source is `assets/Covio.iconset`. Run `iconutil --convert icns --output macosApp/src/Covio.icns assets/Covio.iconset` after a change.
The Xcode target copies `macosApp/src/Covio.icns` into the bundle, so every build carries the icon.

The app is arm64 only. `kmpDomain.framework` has one slice, `macosArm64`.

## Real-Mac acceptance checklist

Run this checklist before a public release.
The current internal test does not complete this checklist.

1. Install the build under test.
2. Confirm the app version matches `APP_VERSION` in `kmpDomain/src/com/wyz/covio/core/Models.kt`.
3. Install the privileged helper.
4. Confirm the helper version matches the app version.
5. Confirm screenshot takeover changes the three `com.apple.screencapture` keys.
6. Take a screenshot. Confirm the system thumbnail is hidden.
7. Confirm the screenshot appears in the toolbar.
8. Click the screenshot. Confirm the image and file URL are on the clipboard.
9. Double-click the screenshot. Confirm Preview opens.
10. Long-press the screenshot. Confirm Markup opens.
11. Drag the screenshot to an app. Confirm the app receives a copy.
12. Drag the screenshot to a folder. Confirm the source moves.
13. Drag the screenshot to the Desktop. Confirm the source moves.
14. Drag the screenshot to the Trash. Confirm the source uses the Trash.
15. Cancel a drag. Confirm the card returns.
16. Close takeover. Confirm the three system keys return to the old values.
17. Quit Covio normally. Confirm the keys return to the old values.
18. Force-quit Covio. Start Covio. Confirm the saved snapshot is reused.
19. Test the toolbar on each display.
20. Enter a full-screen Space. Confirm the toolbar hides.
21. Press `Control+Option+T`. Confirm the toolbar toggles.
22. Delete a screenshot outside Covio. Confirm the card disappears.
23. Enable "Prevent lid sleep on AC power". Close the lid on AC power. Confirm SSH stays connected.
24. Enable "Prevent lid sleep on battery power". Close the lid on battery power. Confirm SSH stays connected.
25. Turn off the battery switch while the lid is closed. Confirm the Mac sleeps and SSH disconnects.
26. Reach the low battery threshold. Confirm the low battery rule wins.
27. Confirm the General page shows the DarkWake time, reason, and 24-hour count.
28. Fully wake the Mac. Confirm the timers restore or the policy recalculates.
29. Change the sleep mode between 0, 3, and 25.
30. Clear the configuration. Confirm the default values return.
31. Quit the app. Confirm the LaunchAgent does not restart it.
32. Force-quit the app. Confirm the LaunchAgent restarts it.
33. Remove the helper. Confirm `SleepDisabled` is `0`.
34. Open the Hub. Confirm the floating rail is on the left and the floating capsule is at the top.
35. Confirm the rail and the capsule look like glass. If they do not, set `GlassSurfaceMode.current` to `.material`.
36. Switch all six tabs. Confirm each page fits the card. Confirm no button row is cut.
37. Type `休眠` in the search box. Select the result. Confirm the Hub opens the Settings tab, the General section, and highlights the sleep mode row.
38. Press Escape. Confirm the search clears and the Hub stays open. Press Escape again. Confirm the Hub collapses.
39. Switch the language to English in the rail. Confirm all text changes.
40. Turn on Reduce motion in System Settings. Repeat step 36. Confirm the selection changes without animation.
41. Click quit at the bottom of the rail. Confirm the app exits and the sleep state returns to the value before start.

## Privileged helper

The app installs a LaunchDaemon only after you approve the installation dialog.
The helper accepts three commands:

- `version`
- `setDisableSleep`
- `setHibernateMode`

The helper checks the peer user ID before the helper runs a command.
The app and the helper must use the same version.
An old helper shows "Helper: Update Required" and disables the lid-hold switches.

## Paths

The configuration is:

```text
~/Library/Application Support/com.wyz.covio/config.json
```

`fileNaming` is optional. Old configuration files get the default naming policy.
The policy always preserves the original extension and requires a preview.

The log is:

```text
~/Library/Application Support/com.wyz.covio/logs/Covio.log
```

The LaunchAgent is:

```text
~/Library/LaunchAgents/com.wyz.covio.plist
```

The helper socket is:

```text
/Library/Application Support/Covio/helper.sock
```

The helper LaunchDaemon is:

```text
/Library/LaunchDaemons/com.wyz.covio.helper.plist
```

The screenshot shelf state and the screenshot files are:

```text
~/Library/Application Support/Covio/Screenshots
```

The clipboard state and the clipboard images are:

```text
~/Library/Application Support/Covio/Clipboard
```

## Publish an internal test release

1. Run `scripts/package-macos-swift.sh`.
2. Run `gh auth login`.
3. Run `bash scripts/create-release.sh`.

The release tag must be a full release.
The update checker ignores pre-release tags.

## License

MIT. See `LICENSE`.
Third-party notices are in `THIRD_PARTY_NOTICES.md`.
