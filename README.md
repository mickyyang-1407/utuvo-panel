# UTUVO Panel

An iOS 27 Home Screen widget in the new extra-large portrait size (`systemExtraLargePortrait`):
clock, next event, weather, activity rings, a timer with real buttons, five app shortcuts that
open their apps directly, and a system row you can compose from eleven readings.

- **Transparent** on a full-colour Home Screen by cropping your own wallpaper to the panel
  (iOS gives widgets no true transparency), or automatically glass in the Clear icon style.
- **Direct launch**: tiles use `OpenURLIntent` (iOS 18+), so the container app never appears.
- **Liquid Glass**: the app icon is an Icon Composer `.icon`; every tile is pre-rendered artwork.
- **Localised**: Traditional Chinese and English, following the system language.

## Build

```
brew install xcodegen
cd ios && xcodegen generate
open UTUVOPanel.xcodeproj      # or: xcodebuild -scheme UTUVOPanel -destination 'generic/platform=iOS Simulator'
```

Requires Xcode 27 and an iOS 27 simulator or device.

## Layout

| Path | What |
|---|---|
| `ios/Shared/` | Model, panel UI, intents, tiles, strings — compiled into both the app and the widget |
| `ios/PanelWidget/` | WidgetKit timeline provider |
| `ios/UTUVOPanel/` | The app (settings, wallpaper crop, permissions) |
| `ios/UITests/` | XCUITests that drive SpringBoard: add the widget, tap tiles, run the timer |
| `ios/Check/` | Pure-logic self-check: `swiftc -O Shared/Logic.swift Check/main.swift -o /tmp/c && /tmp/c` |
| `tools/` | `make-tiles.py` (ictool pipeline), `slice-tiles.py` (cut rendered rows into the asset catalog) |
| `docs/` | Handoff log with evidence screenshots |

## Licence

Code: MIT (`LICENSE`). Brand mark and tile artwork: all rights reserved — see `ASSETS-LICENSE.md`.
