# 0003 — 設定頁最上面的「三步驟」引導（每步會自動打勾）

- 票型：standard ｜ writer：ccm3（MiniMax）｜ reviewer：agy（Gemini）
- 分支／worktree：`v1.0.1-transparent` ／ `~/Projects/utuvo-panel-v101`（HEAD `91dfab2`）

## 為什麼

Micky 拿到 1.0.1 之後說「我還是不會用耶」。現在的說明是設定頁中間一大段字，使用者不知道順序、也不知道自己做到哪一步。
要讓人**不看說明也會用**：打開 app 最上面就是三個步驟，做完的自動打勾，全部做完就收起來。

## 這張票只做一件事

在設定頁加一個「三步驟」引導區塊，取代頁尾那個舊的「加到桌面」區塊。

## 版面與行為

- **位置**：`SettingsView` 的 `Form` 裡**第一個** `Section`（在面板預覽 `PreviewCard` 之上）。
- **三個步驟都完成**就不顯示這個區塊；改在「透明背景」區塊最後加一列「重新看設定步驟」/"Show setup steps again"，點了再展開（`@State` 即可，不用存）。
- 每一步是一列：左邊一張小示意圖（見下）＋中間標題與一行說明＋右邊狀態（完成＝綠色 `checkmark.circle.fill`；未完成＝步驟編號圈）。
- **狀態刷新**：`.task` 一次，另外 `@Environment(\.scenePhase)` 變回 `.active` 時再刷一次（使用者會跑去桌面操作再回來）。

### 三個步驟（中文是 source key，英文放 xcstrings，**逐字照抄**）

| # | 標題 | 說明 | 動作 | 何時打勾 |
|---|---|---|---|---|
| 1 | 把面板加到桌面 / Add the panel to your Home Screen | 長按桌面空白處 › 左上「編輯」› 加入小工具 › 搜尋 UTUVO Panel › 選最高的尺寸 / Touch and hold an empty spot › Edit › Add Widget › search UTUVO Panel › pick the tallest size | 無 | 桌面上有任何一個 kind＝`Shared.widgetKind` 的小工具 |
| 2 | 截一張空白桌面，交給 app / Screenshot an empty Home Screen page | 長按桌面讓圖示抖動 › 往左滑到最後的空白頁 › 側邊按鈕＋音量上截圖。桌布是自己的照片就直接選那張 / Touch and hold until the icons jiggle › swipe to the empty page at the end › press the side button and volume up. If your wallpaper is your own photo, just pick that photo. | `PhotosPicker` 按鈕「選你的桌布（截圖或照片）」/"Choose your wallpaper (screenshot or photo)"，**綁同一個 `screenshotItem`**（沿用既有 `.onChange` 流程） | `model.screenshot != nil` |
| 3 | 告訴面板它在哪裡 / Tell the panel where it sits | 長按面板 › 編輯小工具 › 背景選「透明」；面板在最上面就選「頁面頂端」，上面有一排 app 就選「往下一列」 / Touch and hold the panel › Edit Widget › Background: Transparent. Position: Top of the page if nothing is above it, One row down if a row of apps is above it. | 次要連結「或在 app 裡拖著對齊」/"Or drag it into place in the app" → `AlignView()`（同既有 NavigationLink） | 見下 |

**步驟 3 何時打勾**（寫成純函式，見「步驟」第 1 點）：桌面上任一面板的 intent 符合下列任一條——
- `slotValue != .custom`（使用者在編輯小工具選了位置）；或
- `slotValue == .custom` 且 `config.backgroundOffset` 跟 `placement.defaultOffset` 差超過 0.001（使用者在 app 裡拖過）。

**特例**：若所有面板的背景都選了「漸層」，步驟 2、3 不需要桌布——兩步都算完成，步驟 2 的說明改成「你選了漸層背景，不需要桌布」/"You chose the gradient background — no wallpaper needed."。

### 示意圖（SwiftUI 畫，**不准用圖片素材、不准 AI 生圖**）

每步左邊一支 44×76 pt 的小手機：圓角 10 的外框（`.secondary` 1pt 描邊）＋內部內容：
1. 內部一塊佔 80% 的圓角矩形（面板）＋左上角小圓「＋」（`plus.circle.fill`，accent 色）。
2. 內部淡淡的漸層（桌布），正中央 `camera.viewfinder`。
3. 內部面板＋右下角 `hand.tap.fill`＋底部一條小橫條（代表編輯小工具那張卡）。

顏色用系統語意色（`.secondary`、`.tint`、`Color(.secondarySystemFill)`），深色模式自動正確。

## 具體步驟

1. **`Shared/Logic.swift`**：加純函式（Check 要測）
   ```swift
   struct SetupProgress: Equatable {
       var widgetPlaced: Bool; var wallpaperChosen: Bool; var positioned: Bool
       var allDone: Bool { widgetPlaced && wallpaperChosen && positioned }
   }
   /// slots/backgrounds: one entry per Panel widget on the Home Screen (rawValue strings, so Logic stays AppIntents-free).
   func setupProgress(widgetBackgrounds: [String], widgetSlots: [String], hasScreenshot: Bool, offsetMoved: Bool) -> SetupProgress
   ```
   規則照上表（沒有任何面板時 `widgetPlaced == false`、`positioned == false`；全部是 `"gradient"` → `wallpaperChosen == true && positioned == true`）。
2. **`UTUVOPanel/App/PanelModel.swift`**：加 `@Published private(set) var setup = SetupProgress(...)` 與 `func refreshSetup() async`：
   `WidgetCenter.shared.currentConfigurations()` → 過濾 `kind == Shared.widgetKind` → 每個 `info.widgetConfigurationIntent(of: PanelWidgetIntent.self)` 取 `backgroundValue.rawValue`／`slotValue.rawValue`（拿不到 intent 就當預設值）→ 呼叫 `setupProgress`。`offsetMoved` 用 `abs(config.backgroundOffset - placement.defaultOffset) > 0.001`。`setScreenshot`／`clearScreenshot` 之後也要刷新。
3. **`UTUVOPanel/UI/RootView.swift`**：新增 `SetupGuide` 子 View（可放新檔 `UTUVOPanel/UI/SetupGuide.swift`，**加檔記得 `xcodegen generate`**）；`SettingsView` 依上面的版面插入；**刪掉**頁尾舊的「加到桌面」`Section`（L120–126 附近，字串 key 留在 xcstrings 不用刪）。
4. **`Shared/Localizable.xcstrings`**：新 key＋英文，只准 append。
5. **`Check/main.swift`**：`setupProgress` 至少 6 條：沒面板／有面板沒截圖／有截圖位置 custom 沒拖／有截圖選了 row1／custom 但拖過／全部漸層。
6. **UI 測試**：`test1_pickScreenshot`／`test7b_pickNewest` 用 `label BEGINSWITH '選你的桌布'` 找按鈕，引導的按鈕刻意也用這個開頭，所以會先點到引導那顆（開同一個選取器）——**確認兩條仍然通過**；它們斷言「移除背景」前只 `swipeUp()` 一次，引導把內容往下推之後可能不夠，改成最多捲 3 次直到找到。其他測試不要動。

## 不准做

- 不准改 `PanelView.swift`、`PanelWidget.swift`、`Intents.swift`、小工具任何行為。
- 不准改版號、kind、bundle id、entitlements、`tools/`、`docs/`、App Store。
- 模擬器只准用 `363878E7-E1F6-4F64-9D13-91F4C3E67BD2`；不准 erase。
- git 只准跑唯讀指令（status / diff / log / show）。其餘一律禁止——包含但不限於 add / commit / push / reset / checkout / switch / stash / clean / restore / rebase / merge / cherry-pick / tag / worktree。需要動 git 就停下來回報。

## 完成標準（全部要跑、貼輸出）

```bash
cd ~/Projects/utuvo-panel-v101/ios && xcodegen generate
swiftc -O Shared/Logic.swift Check/main.swift -o /tmp/c-v101 && /tmp/c-v101
xcodebuild -project UTUVOPanel.xcodeproj -scheme UTUVOPanel \
  -destination "platform=iOS Simulator,id=363878E7-E1F6-4F64-9D13-91F4C3E67BD2" \
  -derivedDataPath ../DerivedData build
xcodebuild -project UTUVOPanel.xcodeproj -scheme UTUVOPanel \
  -destination "platform=iOS Simulator,id=363878E7-E1F6-4F64-9D13-91F4C3E67BD2" \
  -derivedDataPath ../DerivedData \
  -only-testing:UTUVOPanelUITests/WidgetFlowTests/test1_pickScreenshot \
  -only-testing:UTUVOPanelUITests/WidgetFlowTests/test7b_pickNewest \
  -only-testing:UTUVOPanelUITests/WidgetFlowTests/test10_settingsScreens test
```

回報：改了哪些檔、四段輸出的最後幾行、沒照工單做的地方與理由（說 API 限制要附編譯錯誤原文）。畫面目視由 orchestrator 做。

---

## 驗收紀錄（orchestrator，2026-09-21）

- **writer**：ccm3（MiniMax）。自報 test7b 失敗是「少了 runner 植入的截圖」——**錯**。實際原因見下。
- **範圍**：8 個檔（含新檔 `SetupGuide.swift`、xcodegen 重產的 pbxproj）；受保護的 PanelView／PanelWidget／Intents／project.yml hash 未變。
- **orchestrator 抓到並修的（短修，已含在 review 範圍）**：
  1. **示意圖把版面撐爆**：`StepPhone` 只把 44×76 套在外框線上，內容（`.infinity` frame、漸層、Spacer）沒被限制，示意圖佔掉半個畫面、文字被擠成一條、第 3 步手勢圖示不見。改成尺寸與裁切套在整個示意圖。
  2. **示意圖對 VoiceOver 會念雜訊**，而且害 UI 測試失敗：`camera.viewfinder` 的系統自動無障礙標籤叫「Screenshot」，
     測試用「標籤含 Screenshot」找照片→把被選取器蓋住的它也算進去→「第 7 格」點不到。用 `app.debugDescription` 印出畫面樹才找到。
     示意圖改成 `.accessibilityElement(children: .ignore)`＋`.accessibilityHidden(true)`（單獨 `accessibilityHidden` 沒生效，樹裡還看得到）。
  3. **test1／test7b 的照片選取條件收緊**成「標籤以 Photo, / Screenshot, / 照片 / 截圖 開頭」。test1 以前一直是碰巧點到被蓋住位置下面的照片才過。
- **deterministic gate**：Check 全綠（含 7 條 setupProgress）、`BUILD SUCCEEDED`；test1／test7b／test10 **passed**（test7b 數到正確的 6 格）。
- **實機流程（模擬器操控）**：引導淺色／深色都正常；面板已放、桌布已選 → 1、2 打勾；到桌面長按面板 › 編輯小工具 › 位置選「頁面頂端」→ 回 app，**三步驟自動收起**；「重新看設定步驟」在透明背景區塊最後一列。證據 `docs/evidence-1.0.1/0003-*.png`。
- **環境**：這台模擬器今天跑 xcodebuild test 會在測試結束後卡 ~10 分鐘收尾（app／runner 都已結束、沒有 crash）。改用 build-for-testing＋test-without-building，從 stdout 讀結果。
- **異家族 review**：AGY（Gemini）9 項全 PASS，`VERDICT: PASS`；前後 checksum 一致（`84ff3df8…`）。
- **結論**：CLOSE。
