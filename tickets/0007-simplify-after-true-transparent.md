# 0007 — 真透明之後把截圖／位置流程從介面拿掉

- 票型：standard ｜ writer：ccm3（MiniMax）｜ reviewer：agy（Gemini）
- 分支／worktree：`v1.0.1-transparent` ／ `~/Projects/utuvo-panel-v101`（在 0005、0006 之後）

## 為什麼

0005 之後「透明」是系統真透明（跟著桌布、輪播都對），截圖、對齊、選位置全部用不到了。Micky 之前說「我還是不會用耶」——留著這些步驟只會讓人以為還要做。Micky 已決定 1.0.1 帶真透明送審（09-21「送」）。

## 這張票只做一件事

把「截桌布／對齊／位置」從**介面**拿掉，設定引導縮成一步；暗度滑桿改成在透明模式下也有效。**底層的截圖／裁切程式碼不刪**（只斷掉入口），留待之後清。

## 具體步驟

1. **`ios/Shared/Intents.swift`**：`PanelWidgetIntent` 拿掉 `slot`（位置）這個 `@Parameter` 與 `slotDefault`／`slotValue`；`init` 同步。`PanelSlotChoice` enum 保留（`PanelSlotKind` 還有人用就留，沒人用就一起刪——編譯器說了算）。
   - `PanelBackgroundChoice` 的顯示文字：`.transparent: "透明"`、`.gradient: "漸層"`（原本「透明（用你的桌布）」會讓人以為要選桌布）。xcstrings 新 key 只准 append。
2. **provider（`PanelWidget.swift`）**：不再讀 `slotValue`。透明＝0005 的 trueTransparent 路徑；漸層照舊。`resolveBackground` 若因此沒人呼叫，保留並加一行註解「0007 起無入口，保留待清」。
3. **暗度在透明模式也有效**：`BackgroundModifier` 的 trueTransparent 分支改成 `containerBackground(for: .widget) { Color.black.opacity(tint) }`（tint 預設 0 → 仍是完全透明）。
4. **`SetupGuide.swift`**：縮成**一步**「把面板加到桌面」（標題、說明、示意圖、打勾條件都沿用舊的第 1 步），下面加一行小字：
   「想換漸層背景或加邊框：長按面板 › 編輯小工具」／"For a gradient background or a border: touch and hold the panel › Edit Widget"。
   做完（面板已放）就收起來，「重新看設定步驟」照舊。
5. **`Logic.swift` 的 `SetupProgress`／`setupProgress`**：`allDone` 只看 `widgetPlaced`。`wallpaperChosen`／`positioned` 欄位若沒人用就刪，Check 對應改寫（至少：沒面板＝未完成、有面板＝完成、全部漸層＝完成）。
6. **`RootView.swift` 的「透明背景」Section**：
   - 刪掉：兩個 `PhotosPicker`、「對齊背景」、「移除背景」「移除深色桌布」、`screenshotItem`／`screenshotDarkItem` 相關 `@State` 與 `.onChange`。
   - 保留：暗度滑桿（標題改「暗度（桌布太亮、字看不清時調高）」）、「重新看設定步驟」。
   - Section header 改「背景」；footer 改成：
     「面板直接透出你的桌布，換桌布、桌布輪播都會自動跟著變。長按面板 › 編輯小工具 可以改成漸層背景、加邊框。」
     英文：「The panel shows your wallpaper straight through — change it or use shuffle and it follows. Touch and hold the panel › Edit Widget for a gradient background or a border.」
   - `panelSizeIsMeasured` 那行提示刪掉（只跟裁切有關）。
7. **UI 測試 `UITests/WidgetFlowTests.swift`**：`test1_pickScreenshot`、`test7a_emptyPageScreenshot`、`test7b_pickNewest` 的功能已不存在 → 刪掉這三條。`test10_settingsScreens` 若斷言了被刪的文字，改成新文字。其他測試不要動。
8. **`Check/main.swift`**：照第 5 點改；不准刪與本票無關的 check。

## 不准做

- 不准刪截圖／裁切／`AlignView.swift`／`PanelPlacement` 等底層程式（只斷入口）。
- 不准改 0005 的 SPI 腳本與 `preferredBackgroundStyle`、0006 的邊框、版號、bundle id、entitlements、`tools/`、App Store。
- 模擬器只准用 `363878E7-E1F6-4F64-9D13-91F4C3E67BD2`；不准 erase。
- git 只准跑唯讀指令（status / diff / log / show）。其餘一律禁止——包含但不限於 add / commit / push / reset / checkout / switch / stash / clean / restore / rebase / merge / cherry-pick / tag / worktree。需要動 git 就停下來回報。

## 完成標準（全部要跑、貼輸出）

```bash
cd ~/Projects/utuvo-panel-v101/ios && xcodegen generate
swiftc -O Shared/Logic.swift Check/main.swift -o /tmp/c-v101 && /tmp/c-v101
xcodebuild -project UTUVOPanel.xcodeproj -scheme UTUVOPanel \
  -destination "platform=iOS Simulator,id=363878E7-E1F6-4F64-9D13-91F4C3E67BD2" \
  -derivedDataPath ../DerivedData build
python3 -c "import json;json.load(open('Shared/Localizable.xcstrings'))" && echo xcstrings-ok
grep -rn "PhotosPicker\|對齊背景\|移除背景" UTUVOPanel/UI/RootView.swift UTUVOPanel/UI/SetupGuide.swift || echo "no screenshot UI left"
```

回報：改了哪些檔、輸出最後幾行、沒照工單做的地方與理由。UI 測試與畫面實測由 orchestrator 做。

---

## 驗收紀錄（orchestrator，2026-09-21）

- **writer**：ccm3（MiniMax）。9 檔、+111／−400。偏離：`resolveBackground` 的位置裁切分支刪掉（slot 參數拿掉後無從讀起，合理）；`PanelSlotChoice`／`PanelSlotKind`／`AlignView`／`PanelPlacement` 保留（hash 驗過）。
- **orchestrator 抓到並修的**：writer 把英文寫成第二個 `Text`，**中英同時顯示**（設定頁 footer＋引導提示，目視抓到）。改成單一中文 key＋xcstrings 英文（+20 行；第一次用 json.dump 重排了整份 xcstrings 2000 行，已還原 HEAD 再以原格式 `": "` 只加條目）。
- **gate**：Check 全綠；`TEST BUILD SUCCEEDED`；UI test10／test5／test11 **passed**；grep 無 PhotosPicker／對齊背景／移除背景。
- **實測（sim，英文 UI）**：「背景」區塊只剩暗度＋重新看步驟、說明只顯示英文（`0007-settings-background-section.png`）；引導一步＋提示（`0007-setup-guide-one-step.png`）。
- **異家族 review**：AGY（Gemini）7 項 PASS；前後 checksum 一致（`c42d5f81…`）。
- **結論**：CLOSE。
