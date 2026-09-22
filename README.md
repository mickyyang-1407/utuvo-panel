# UTUVO Panel

An iOS 27 Home Screen widget in the new extra-large portrait size (`systemExtraLargePortrait`):
clock, next event, weather, activity rings, a timer with real buttons, five app shortcuts that
open their apps directly, and a system row you can compose from eleven readings.

- **Truly transparent** on the default (full-colour) Home Screen: the wallpaper shows straight
  through, follows wallpaper shuffle, no screenshot or cropping. See *Transparency* below.
- **Borders**: six styles × six colours, set once in the app or per panel in Edit Widget.
- **Bottom section** (extra-large portrait): hourly weather under today's forecast, a three-event
  agenda, or even spacing — sized from the space actually left on each iPhone model.
- **Live activity data**: the widget reads HealthKit itself, so steps update without opening the app.
- **Direct launch**: tiles use `OpenURLIntent` (iOS 18+), so the container app never appears.
- **Liquid Glass**: the app icon is an Icon Composer `.icon`; every tile is pre-rendered artwork.
- **Localised**: Traditional Chinese and English, following the system language.

## Transparency

WidgetKit's public API has no transparent background on the default Home Screen — a clear
`containerBackground` is composited onto a solid fill (white in Light, RGB 17,17,17 in Dark;
tested on device, see `docs/evidence-1.0.1/`). WidgetKit does export an undocumented
`WidgetConfiguration.preferredBackgroundStyle(_:)`; with `.transparent` the system composites the
widget straight onto the wallpaper, with no dim. `isTransparent(true)`, also exported, is
transparent but adds a scheme-coloured veil.

Neither is declared in the SDK's `.swiftinterface`. `tools/make-widgetkit-spi.sh` runs as a
pre-build phase of the widget target: it copies the active SDK's `WidgetKit.framework` into the
build directory and appends the declarations, and `FRAMEWORK_SEARCH_PATHS` points the compiler at
that copy. Linking still resolves against the system WidgetKit (the symbols are in its `.tbd`).
No SDK files are committed.

Caveats: it is undocumented, so App Review may object and a future iOS may remove it — the
widget would then fail to load rather than fall back.

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
