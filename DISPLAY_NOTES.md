# Display Engine Notes

## Why RedLight uses overlays

The current MacBook Pro uses a [Liquid Retina XDR](https://www.apple.com/macbook-pro/specs/) wide-gamut LCD with a mini-LED backlight. RedLight can control the digital RGB values that reach the compositor, but an app cannot directly control the panel’s spectral output. Unlike an OLED, setting a digital channel to zero does not physically switch off a self-emissive blue subpixel; panel filters, backlight spectrum, HDR processing, brightness, and viewing environment still affect measured light.

CoreGraphics exposes public display-transfer functions, but current macOS 26 releases have a confirmed failure on M5 Pro/Max hardware: gamma calls report success and read back the requested table while the visible display does not change. See [Apple Developer Forums thread 819331](https://developer.apple.com/forums/thread/819331).

Private Night Shift controls are not suitable for a Mac App Store product. A WindowServer-composited overlay is therefore the reliable, permission-free implementation for this hardware. RedLight also offers an opt-in High Clarity capture renderer for users who accept its permission, latency, energy, and protected-content tradeoffs.

## Digital suppression model

For a source-over tint:

`channelOut = ((1 - tintAlpha) × channelIn + tintAlpha × tintChannel) × (1 - dimAlpha)`

For the blue channel, RedLight reports:

`estimatedBlueTransmission = ((1 - intensity) + intensity × tintBlue) × (1 - dimming)`

The Red Room preset uses a dark zero-blue tint, 85% tint strength, and 20% dimming, leaving an estimated 12% of the original digital blue channel while retaining enough source contrast for text. Users can push the custom controls further, with a corresponding loss of legibility. This is a useful relative estimate, not a spectral or medical claim.

## High Clarity renderer

The optional High Clarity path avoids the overlay contrast floor by capturing each display and converting perceived luminance to a red-only output in Metal:

`Y = 0.2126R + 0.7152G + 0.0722B`

`output = (Y × gain, 0, 0)`

This retains black-to-white luminance differences while setting the digital green and blue output channels to zero. It requires Screen Recording permission, introduces capture latency and energy use, and cannot reproduce protected video content. Compatibility Overlay remains the permission-free fallback.

## Expected boundaries

- Covered: user desktop, standard apps, all configured displays, Spaces, and ordinary full-screen app windows.
- Not covered: login window, lock screen, early boot, some protected system/video surfaces, and content drawn above the selected public window level.
- Screen captures may include or omit the overlay depending on the capture API and selected source.
- HDR/EDR content can blend differently from SDR and requires device testing.
- Compatibility Overlay never reads screen pixels. High Clarity reads transient display frames only after explicit Screen Recording permission; neither mode needs Accessibility permission.

## Language for customers

Use “strongly suppresses the digital blue and green contribution” rather than “eliminates all blue light.” RedLight is a comfort utility, not a medical device.
