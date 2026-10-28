<p align="center"><img src="Sources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="160" alt="Aperture icon"></p>

# Aperture

A small arcade game for iPhone that you steer with Camera Control. Swipe the control to move through the gaps in the walls. Touch works too.

## Highlights

- Steer with swipes on Camera Control, click to dash
- Power-ups: shield, magnet and slow-mo
- Combo multiplier for clean passes, swinging walls later in a round
- Three difficulties (Calm, Normal, Fast) and a daily challenge with the same course for everyone
- Shop with ball skins, trail colors and themes, paid with lightning from your rounds
- Stats and achievements with lightning rewards
- Sounds and haptics with adjustable strength
- Everything works from Camera Control: the menu, shop items, every setting, and pause/continue and retry with a click
- Built with SwiftUI and Liquid Glass, in dark mode

## Controls

| Screen | Swipe | Click |
| --- | --- | --- |
| Menu | Play, Daily, Shop, Stats, Settings | Open the selection |
| Playing | Steer | Dash |
| Shop | Item (tabs by touch) | Equip, or hold to buy |
| Settings | Value of the active control (switch controls natively with Camera Control) | - |
| Stats, Paused, Crashed | - | Back, continue, retry |

## Privacy

The camera runs only so iOS delivers Camera Control events to the app. Aperture does not process, save or send camera frames. It stores only your best score, settings and shop progress on the device.

## Platforms

| Platform | Status | Distribution |
| --- | --- | --- |
| iPhone with Camera Control | iOS 26 or later | Unsigned IPA for sideloading |

Builds are unsigned and meant for personal testing. Installing one needs a sideloading or local-signing setup of your own.

## Download

Get `Aperture.ipa` from the [latest release](https://github.com/Malti2/Aperture/releases/latest).

## AltStore source

1. Open AltStore and go to **Sources**.
2. Tap **+** and enter `https://malti2.github.io/Aperture/source.json`.
3. Open the Aperture listing and install it.

You can also use the [Add to AltStore](https://altdirect.app/?url=https%3A%2F%2Fmalti2.github.io%2FAperture%2Fsource.json) link. The source is generated from published GitHub releases. It lists each release's `Aperture.ipa`, version, date, file size and release notes.

## Build from source

Requires macOS, Xcode 26 or newer, and XcodeGen.

```bash
brew install xcodegen
xcodegen generate --spec project.yml
open Aperture.xcodeproj
```

You can also fork the repository and run its **Build** workflow in GitHub Actions to get an unsigned IPA.
