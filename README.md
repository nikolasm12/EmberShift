# EmberShift

EmberShift is a native macOS menu-bar app, currently built as **RedLight**, that adds a warm-to-deep-red, click-through filter to every connected display. It can run manually, on custom times, or from locally calculated sunset and sunrise.

The menu bar also provides temporary 15-minute, one-hour, and two-hour overrides without changing the underlying schedule.

RedLight has two rendering paths:

- **Compatibility Overlay** is the default, requires no screen access, and uses almost no idle CPU.
- **High Clarity** is opt-in and experimental. It uses ScreenCaptureKit and Metal entirely on-device to convert screen luminance into a red-only image with stronger text contrast. Frames are never stored or transmitted, and the app automatically falls back to the overlay if capture is unavailable.

## Requirements

- macOS 15 or later
- Xcode 26 or later
- A Mac App Store signing team for distribution

## Run

1. Open `RedLight.xcodeproj`.
2. Select the RedLight target and choose your development team.
3. Replace the placeholder bundle identifier `com.nick.RedLight` with your registered identifier.
4. Build and run.

For local testing without a paid developer account or distribution certificate:

```sh
zsh run-local.sh
```

This creates an optimized, ad-hoc signed sandboxed build at `~/Applications/RedLight.app` and launches it normally. The installed copy can register itself to launch at login.

No third-party dependencies, network service, Accessibility access, or privileged helper is used. Screen Recording is requested only when the user explicitly selects High Clarity.

## Architecture

- `ScreenOverlayController` owns one non-activating, click-through `NSPanel` per `NSScreen`.
- `FilterRendererCoordinator` switches safely between the compatibility overlay and High Clarity, keeping the overlay visible until captured frames are ready.
- `HighClarityRenderer` owns per-display ScreenCaptureKit streams and Metal-backed click-through panels.
- `ScheduleController` combines manual/sun scheduling with temporary user overrides.
- `SolarCalculator` calculates official sunrise/sunset and civil twilight offline.
- `LocationManager` requests coarse location only when solar scheduling is enabled.
- `GlobalHotKey` uses the public Carbon hotkey registration API.
- SwiftUI provides onboarding, menu-bar controls, and settings.

## Display limitations

RedLight uses a composited overlay because CoreGraphics display-transfer APIs are visually ineffective on M5 Pro/Max Macs running current macOS 26 releases. An overlay strongly suppresses RGB blue/green contribution, but cannot guarantee spectral elimination of all emitted blue light. It cannot affect the login window, lock screen, or protected system surfaces.

## Verify

```sh
xcodebuild -project RedLight.xcodeproj -scheme RedLight -destination 'platform=macOS' test
xcodebuild -project RedLight.xcodeproj -scheme RedLight -configuration Release archive
```

See `STORE_CHECKLIST.md` before distribution.
