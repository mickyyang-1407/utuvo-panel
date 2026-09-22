# 0005 — 一般外觀下真透明（WidgetKit SPI `preferredBackgroundStyle(.transparent)`）

- 票型：standard ｜ writer：ccm3（MiniMax）｜ reviewer：agy（Gemini）
- 分支／worktree：`v1.0.1-transparent` ／ `~/Projects/utuvo-panel-v101`

## 為什麼

Micky：iScreen 在一般（彩色圖示）外觀＋桌布輪播下是真透明，不用截圖。orchestrator 09-21 真機實證：
- WidgetKit 有匯出但不在公開 swiftinterface 的 `WidgetConfiguration.preferredBackgroundStyle(_ style: WidgetBackgroundStyle) -> some WidgetConfiguration`；
  套 `.preferredBackgroundStyle(.transparent)`＋`containerBackground(for: .widget) { Color.clear }` → **真透明、無暗紗**（證據 `docs/evidence-1.0.1/device-probe4-P4P5-preferred-transparent-no-dim.jpg`，大面板也驗過）。
- 單用 `isTransparent(true)` 會被系統蓋暗紗 → **不要用 isTransparent**。
- 要呼叫它：從「使用中的 SDK」複製一份 `WidgetKit.framework`，在它的 `.swiftinterface` 尾端補宣告，build 時 `FRAMEWORK_SEARCH_PATHS` 指到那份。連結仍接系統的 WidgetKit（tbd 有匯出這些符號）。

## 這張票只做一件事

背景選「透明」時，小工具畫 `Color.clear`，由系統透出真桌布；不再畫桌布裁切圖。其他（漸層、app 內預覽、截圖流程、設定頁）一律不動。

## 具體步驟

1. **新檔 `tools/make-widgetkit-spi.sh`**（bash，`set -euo pipefail`）：參數 `<SDKROOT> <OUT_DIR>`。
   - `rm -rf "$OUT_DIR/WidgetKit.framework"`，`cp -R "$SDKROOT/System/Library/Frameworks/WidgetKit.framework" "$OUT_DIR/"`，`chmod -R u+w`。
   - 對 `$OUT_DIR/WidgetKit.framework/Modules/WidgetKit.swiftmodule/*.swiftinterface` 每個檔 **append** 下面這段（逐字）：
     ```
     @available(iOS 26.0, macOS 26.0, *)
     @available(tvOS, unavailable)
     @available(watchOS, unavailable)
     @available(visionOS, unavailable)
     public enum WidgetBackgroundStyle : Swift::Int {
       case transparent
       case blur
       case opaque
       public init?(rawValue: Swift::Int)
       public typealias RawValue = Swift::Int
       public var rawValue: Swift::Int {
         get
       }
     }
     @available(iOS 26.0, macOS 26.0, *)
     @available(tvOS, unavailable)
     @available(watchOS, unavailable)
     @available(visionOS, unavailable)
     extension SwiftUI::WidgetConfiguration {
       @_Concurrency::MainActor @preconcurrency public func preferredBackgroundStyle(_ style: WidgetKit::WidgetBackgroundStyle) -> some SwiftUI::WidgetConfiguration

     }
     ```
   - 已經 append 過（grep 到 `func preferredBackgroundStyle`）就不要重複 append（冪等）。
   - **不准把 Apple SDK 的檔案 commit 進 repo**（repo 是 public）；只 commit 這支腳本。
2. **`ios/project.yml`** 的 `PanelWidget` target：
   - `preBuildScripts`：`"$SRCROOT/../tools/make-widgetkit-spi.sh" "$SDKROOT" "$PROJECT_TEMP_DIR/WidgetKitSPI/$PLATFORM_NAME"`，`name: WidgetKit SPI interface`，`basedOnDependencyAnalysis: false`。
   - `settings.base.FRAMEWORK_SEARCH_PATHS: ["$(inherited)", "$(PROJECT_TEMP_DIR)/WidgetKitSPI/$(PLATFORM_NAME)"]`。
   - 若 `ENABLE_USER_SCRIPT_SANDBOXING` 擋住腳本寫檔，對這個 target 設 `NO`（回報時寫明）。
   - 改完 `xcodegen generate`。
3. **`ios/PanelWidget/PanelWidget.swift`** 的 `PanelWidget.body`：在 `.contentMarginsDisabled()` 後加 `.preferredBackgroundStyle(.transparent)`，並把舊註解換成一行說明（為什麼、用的是 SPI、證據檔名）。
4. **透明時畫 clear**：
   - `PanelData` 加 `var trueTransparent: Bool = false`。
   - provider（`build`）：`intent.backgroundValue == .transparent` 時 `trueTransparent = true`，且**不載入桌布裁切**（`background`／`backgroundDark` 給 nil，luma 給 nil）。漸層照舊。
   - `PanelView` 的 `BackgroundModifier` 在 `inWidget && trueTransparent` 時：`content.containerBackground(for: .widget) { Color.clear }`；其餘分支原樣。app 內預覽（`inWidget == false`）不受影響。
   - 墨色：`trueTransparent` 時 `lightScheme` 走 `config.panelScheme`，auto 時用 `false`（白字；桌布未知）。寫在 `PanelData.lightScheme` 裡，Logic 可測的部分放 Logic.swift。
5. **`ios/Check/main.swift`**：至少 2 條——透明時 auto 墨色＝白字、pin light 時＝黑字。

## 不准做

- 不准用 `isTransparent`（真機實證會蓋暗紗）。
- 不准改 `Intents.swift` 的選項、`SetupGuide.swift`、`RootView.swift`、`AlignView`、截圖／裁切程式、版號、bundle id、entitlements、App Store。
- 不准 commit 任何 Apple SDK 檔案。
- 模擬器只准用 `363878E7-E1F6-4F64-9D13-91F4C3E67BD2`；不准 erase。
- git 只准跑唯讀指令（status / diff / log / show）。其餘一律禁止——包含但不限於 add / commit / push / reset / checkout / switch / stash / clean / restore / rebase / merge / cherry-pick / tag / worktree。需要動 git 就停下來回報。

## 完成標準（全部要跑、貼輸出）

```bash
cd ~/Projects/utuvo-panel-v101/ios && xcodegen generate
swiftc -O Shared/Logic.swift Check/main.swift -o /tmp/c-v101 && /tmp/c-v101
xcodebuild -project UTUVOPanel.xcodeproj -scheme UTUVOPanel \
  -destination "platform=iOS Simulator,id=363878E7-E1F6-4F64-9D13-91F4C3E67BD2" \
  -derivedDataPath ../DerivedData build
nm -u ../DerivedData/Build/Products/Debug-iphonesimulator/UTUVOPanel.app/PlugIns/PanelWidget.appex/PanelWidget.debug.dylib | grep -c preferredBackgroundStyle
git -C .. status --short
```

回報：改了哪些檔、輸出最後幾行、沒照工單做的地方與理由（說 API 限制要附編譯錯誤原文）。畫面實測由 orchestrator 做。

---

## 驗收紀錄（orchestrator，2026-09-21）

- **writer**：ccm3（MiniMax）。範圍：新腳本 `tools/make-widgetkit-spi.sh`、project.yml、PanelWidget.swift、PanelView.swift、Logic.swift（`PanelInkPick`）、Check；受保護檔 hash 未變。orchestrator 只改一處腳本註解（誤寫「只限模擬器 SDK」→ device 也會跑）。
- **gate**：Check 全綠（含 10 條 PanelInkPick）；sim 與 device（generic iOS、ASC key 自動簽章）`BUILD SUCCEEDED`；兩邊 `nm -u` 都連到 `preferredBackgroundStyle`；build log 有 `staged WidgetKit SPI at …/Intermediates.noindex/…`（SDK 檔不進 repo）。
- **實測**：sim 深色一般外觀，面板透出真桌布、無暗紗（`docs/evidence-1.0.1/0005-sim-dark-true-transparent.png`）；真機探針同一 API 驗過（`device-probe4-…`）。22:45 已裝 Micky 17PMX。
- **已知限制（寫給 Micky 決策）**：硬連結 SPI——未來 iOS 若拿掉符號，extension 載入失敗、小工具空白（WidgetBundleBuilder 只有版本分支，無法執行期退回）；送審有 2.5.1 風險。
- **異家族 review**：AGY（Gemini）7 項 PASS，`VERDICT: PASS`；前後 checksum 一致（`58db0524…`）。
- **結論**：CLOSE。
