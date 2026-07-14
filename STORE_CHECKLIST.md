# Mac App Store Checklist

## Product

- Price: USD $2.99, paid up front, no in-app purchases
- Category: Health & Fitness
- Minimum system: macOS 15
- Copyright and seller name updated
- Support URL, privacy-policy URL, and support email live

## Signing

- Replace `com.nick.RedLight` with the registered bundle identifier
- Select the App Store development team
- Confirm App Sandbox and Hardened Runtime
- Confirm the location entitlement and usage description
- Create Mac App Distribution and Mac Installer Distribution certificates if Xcode does not manage them

## Assets

- Import the generated 1024×1024 RedLight icon into an `AppIcon` asset set and set `ASSETCATALOG_COMPILER_APPICON_NAME`
- Capture menu-bar, Appearance, Schedule, and onboarding screenshots
- Verify every screenshot accurately represents overlay behavior

## Metadata

**Name:** RedLight  
**Subtitle:** A calmer screen after sunset  
**Promotional text:** Switch from gentle warmth to deep red instantly, or let local sunset and sunrise do it for you.

**Description:**

RedLight is a private, native screen-comfort tool for your Mac.

- Toggle a warm or deep-red filter from the menu bar
- Choose Warm, Twilight, Deep Red, Red Room, or a custom color
- Follow local sunset and sunrise automatically
- Use civil twilight or custom on/off times
- Pause or activate temporarily without changing the schedule
- Adjust filter strength, dimming, and transition speed
- Toggle from anywhere with a customizable global shortcut
- Cover every connected display and full-screen Space

Sun times are calculated entirely on your Mac. RedLight has no analytics, ads, account, network connection, or Accessibility permission. Optional High Clarity requests Screen Recording only when selected and processes transient frames entirely on-device.

RedLight strongly suppresses the blue and green contribution of displayed colors. Results vary by panel, brightness, HDR content, and ambient light; it is not a medical device.

**Keywords:** red light, blue light, screen filter, sunset, sunrise, sleep, night, warm display

## Review notes

- The app is a menu-bar utility (`LSUIElement`) and opens onboarding on first launch.
- Compatibility Overlay uses borderless, non-activating, click-through AppKit panels and never reads screen pixels. Optional High Clarity uses public ScreenCaptureKit and Metal after explicit permission; frames are never stored or transmitted.
- Location is requested only after enabling sunset/sunrise scheduling and remains on-device.
- Global shortcuts use public `RegisterEventHotKey`; no Accessibility or Input Monitoring permission is needed.
- Launch at login uses `SMAppService.mainApp`.
- No private Night Shift API or display gamma manipulation is used.

## Release validation

- Run all tests and Analyze with no project warnings
- Create and validate a Release archive
- Test a TestFlight build on M5 Max and at least one older Apple-silicon Mac
- Test internal and external displays, full-screen apps, Spaces, Stage Manager, HDR, sleep/wake, display hot-plug, clock and time-zone changes, DST, denied location, and shortcut conflicts
- Verify lock/login-screen limitation is documented
- Complete App Privacy as “Data Not Collected”
- Set the App Store price only after agreements, tax, and banking are active
