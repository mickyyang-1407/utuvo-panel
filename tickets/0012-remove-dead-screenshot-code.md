# 0012 — 清掉 0007 只斷入口留下的死碼（截圖／對齊／位置／深色桌布）

- 票型：standard（行為保持的刪除重構，跨 7 檔）
- writer：agyw（Gemini，gemini-3.8-flash-high；ccm3 兩次失敗：ECONNRESET、MiniMax Token Plan 429 用量上限）｜reviewer：luna-review（OpenAI）｜UI 回歸：orchestrator
- 工作目錄：`/Users/mickyyang/Projects/utuvo-panel-0012`（git worktree，branch `0012-deadcode`，基底 `71f4b47`）

## 背景

1.0.1 用 WidgetKit SPI 做到真透明後，0007 拿掉了「截圖 → 對齊 → 選位置」的 UI 入口，但程式本體留著。
小工具背景現在只有兩種：`transparent`（系統透出桌布，不畫圖）與 `gradient`（畫內建深藍漸層，不畫圖）。
**所以任何「桌布圖／截圖／裁切／深色桌布／亮度量測」的路徑都已經走不到。**

## 要刪的東西（逐項確認沒有剩餘呼叫者再刪）

1. `ios/UTUVOPanel/UI/AlignView.swift` 整檔。
2. `ios/Shared/Intents.swift`：`PanelSlotChoice` enum 與上方註解（intent 早已沒有 slot 參數）。
3. `ios/Shared/Logic.swift`：`PanelSlotKind`、`PanelPlacement`（含 `estimated`、`defaultOffset`、`top(for:)`、`rect(top:)` 等）、`Shared.screenshotURL`、`Shared.screenshotDarkURL`、`Shared.backgroundURL`、`Shared.backgroundDarkURL`、`Shared.Key.screenPoints`，以及只為它們存在的 helper／config 欄位（例如 `backgroundOffset`）。
   - ⚠️ `PanelConfig` 是 Codable 存在 App Group 的：**刪欄位不可讓舊資料解碼失敗**。先看 `PanelConfig` 的 `init(from:)`（是否手寫、是否 decodeIfPresent）。若刪欄位會影響解碼就保留欄位、只加註解「legacy，未使用」。Check 裡要有一條「含舊欄位的 JSON 仍能解碼」的測試（沒有就加）。
4. `ios/PanelWidget/PanelWidget.swift`：`resolveBackground(...)`、`background`／`backgroundDark`／`luma`／`lumaDark` 的計算，改成直接傳 nil（或把 PanelData 的欄位一起拿掉，見 5）。
5. `ios/Shared/PanelView.swift`：`background`、`backgroundDark`、`backgroundLuma`、`backgroundLumaDark`、`backgroundPick`／`selectedBackground`／`selectedLuma`、以及畫桌布圖的分支。
   - ⚠️ **墨色（ink）判斷不能變**：現在 background 恆為 nil 時 `effectiveLuma` 的 base＝0.26（見 `selectedLuma ?? (selectedBackground == nil ? 0.26 : 0.45)`）。刪完後要保證透明／漸層兩種模式算出來的 lightScheme／墨色與刪前**完全相同**（把 0.26 那條路徑保留成常數即可）。
6. `ios/UTUVOPanel/App/PanelModel.swift`：`screenshot`、`screenshotDark`、`background`、`backgroundDark`、`backgroundLuma(Dark)`、`screenshotURL`、`migrateScreenshotIntoSharedContainer()`、`placement`、`screenSize`（若只剩這裡用）、設桌布／清桌布／`recrop` 等函式、`UIImage` 的 crop／`averageLuminance` extension（確認 widget 端也沒用後再刪）。`refreshSetup()` 呼叫 `SetupProgress.compute(... hasScreenshot:, offsetMoved:)` 的舊參數：若 `SetupProgress` 已不讀它們就一併把參數拿掉（Check 相應更新）。
7. `ios/UTUVOPanel/UI/SetupGuide.swift`、`RootView.swift`：跟著移除對上述符號的引用（應該只剩少數）。
8. `ios/Check/main.swift`：刪掉只測已刪符號的區塊；**不准為了讓 Check 通過而刪測試仍存在功能的斷言**。
9. 刪檔後跑 `cd ios && xcodegen generate`（AlignView.swift 從專案移除）。

## 不准做

- 你是唯一 writer：不得 orchestrate、派工、建立 child task、invoke_subagent，不得用 code-reviewer／security-auditor／test-engineer 等 agent，不得替自己的 diff 做 final review。
- 只准改 `/Users/mickyyang/Projects/utuvo-panel-0012` 裡的檔案，不碰其他目錄（尤其 `/Users/mickyyang/Projects/utuvo-panel-v101`）。
- git 只准唯讀（status／diff／log／show／grep），其餘全禁（add／commit／push／reset／checkout／switch／stash／clean／restore／rebase／merge／cherry-pick／tag／worktree）。
- 先落地再求好：前 10 次工具呼叫內要寫出第一個檔案。

- 不改任何還活著的行為與畫面：時間、天氣、行事曆、活動、計時器、launcher、系統列、邊框、下半部版面、真透明 SPI（`preferredBackgroundStyle`、`tools/make-widgetkit-spi.sh`）。
- 不改 0011 的 Deadline／WeatherService／timeline 並行結構。
- 不動 `project.yml` 版號、ExportOptions、entitlements、Localizable.xcstrings 以外的資源（xcstrings 若有字串只被已刪 UI 使用，可以留著不動）。
- 不新增依賴、不改 UITests（UI 回歸由 orchestrator 跑）。

## 驗收（writer 自己要跑到綠，回報附輸出）

```
cd /Users/mickyyang/Projects/utuvo-panel-0012/ios
xcodegen generate
swiftc -O Shared/Logic.swift Check/main.swift -o "$TMPDIR/panel-check-0012" && "$TMPDIR/panel-check-0012"      # 必須 OK — all checks green
xcodebuild -project UTUVOPanel.xcodeproj -scheme UTUVOPanel -configuration Release -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath /Users/mickyyang/Projects/utuvo-panel-0012/DerivedData build   # 必須 BUILD SUCCEEDED
git grep -n -E "AlignView|PanelPlacement|PanelSlotChoice|PanelSlotKind|screenshotURL|screenshotDarkURL|screenPoints|backgroundDarkURL|averageLuminance" -- ios   # 應為 0 行（legacy Codable 欄位若保留，列出並說明）
```

回報：刪了哪些符號（逐條）、保留了哪些與原因、`git diff --stat`、上面三段指令的輸出尾端。

## 狀態

CLOSED 2026-09-25

## Review（luna-review／gpt-6-luna 對 b5df388，唯讀；rebase 後 0d6ff43 產品碼相同）VERDICT: FAIL（1 minor）
- 原文要點：「The deleted image path remains reachable in the in-app preview for users with crops saved by an earlier version … Before, the preview rendered the saved crop and used its measured luminance; after, it always renders the built-in gradient and uses 0.26 * (1 - tint).」其餘（backgroundOffset 相容、panelSize fallback、setup 進度）確認無誤；小工具端的圖片路徑確認走不到。
- **裁決：接受為預期變更，不還原**。那張舊裁切圖小工具早已不用（transparent／gradient 兩種都回 nil，墨色基準 0.26），舊行為＝app 預覽與桌面小工具墨色可能不一致；刪後兩者一致。受影響者只有 1.0 時代存過桌布的使用者，且只影響 app 內預覽。
- 舊圖檔（panel-bg*.jpg、panel-screenshot*.jpg）留在使用者 App Group 不主動刪（非必要、避免擴大範圍）。

## UI 回歸（orchestrator，fresh sim 6E62282E，隔離單跑）
Check 綠；Release build 綠；test2／test3／test4／test10／test13／test5 全 passed；test13 三種版面＋app 預覽目視：真透明與墨色與刪前一致。
