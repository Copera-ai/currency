# Copera Currency

A native macOS menu-bar app showing live currency & crypto pair rates (iStat-Menus style — one menu-bar item per tracked pair) with a converter popover and a Settings window.

## Prerequisites

- macOS 14.0+ (Apple Silicon, arm64 only)
- Xcode 26+ (full Xcode, not just Command Line Tools)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build & run

The Xcode project is generated from `project.yml` and is **not** committed. Generate it first:

```sh
xcodegen generate
```

Then either open it in Xcode:

```sh
open CoperaCurrency.xcodeproj
# In Xcode: select the "CoperaCurrency" scheme and press ⌘R
```

…or build from the command line:

```sh
xcodebuild \
  -project CoperaCurrency.xcodeproj \
  -scheme CoperaCurrency \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build
```

Re-run `xcodegen generate` after any structural change (new folders, target settings, Info.plist/entitlements changes). New `.swift` files added under `CoperaCurrency/` are picked up automatically via source globbing on regenerate.

## Project layout

```
CoperaCurrency/
  App/         App entry point + AppDelegate
  MenuBar/     NSStatusItem controllers (later phases)
  Models/      Currency / pair / rate models
  Networking/  Rate providers (Fawaz fiat, Coinbase crypto)
  Store/       RatesStore, persistence, load state
  Theme/       Theme tokens + manager
  UI/          Popover + Settings views
  Components/   Reusable SwiftUI components
  Updater/     Sparkle auto-update (later)
  Login/       Launch-at-login (SMAppService)
  Resources/   Info.plist, entitlements, Assets.xcassets (app icon)
```

> The app icon is a generated placeholder ("$" on terracotta); the real Copera icon ships before public release.
