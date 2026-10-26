# Aperture

A small arcade game for iPhone that you steer with Camera Control. Swipe the control to move through the gaps in the walls. Touch works too.

## Highlights

- Steer with swipes on Camera Control
- Adjustable steering speed and haptics
- Pause with a swipe-to-continue slider
- Built with SwiftUI and Liquid Glass, in dark mode

## Privacy

The camera runs only so iOS delivers Camera Control events to the app. Aperture does not process, save or send camera frames. It stores only your best score and settings on the device.

## Platforms

| Platform | Status | Distribution |
| --- | --- | --- |
| iPhone with Camera Control | iOS 26 or later | Unsigned IPA for sideloading |

Builds are unsigned and meant for personal testing. Installing one needs a sideloading or local-signing setup of your own.

## Download

No public release yet. `Aperture.ipa` will be attached to a release once one is published.

## Build from source

Requires macOS, Xcode 26 or newer, and XcodeGen.

```bash
brew install xcodegen
xcodegen generate --spec project.yml
open CameraControlTest.xcodeproj
```

You can also fork the repository and run its **Build** workflow in GitHub Actions to get an unsigned IPA.
