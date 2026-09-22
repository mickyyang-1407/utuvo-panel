# 0002 — 淺色／深色模式各一張桌布＋對不齊提示（iScreen parity 第二、三段）

- 票型：standard ｜ writer：ccm3（同 0001，延續 context）｜ reviewer：agy（Gemini）
- 分支／worktree：`v1.0.1-transparent` ／ `~/Projects/utuvo-panel-v101`
- 前置：0001 已落地（`526e737`：`Shared.screenshotURL`、`PanelWidgetIntent`、provider 的 `resolveBackground(intent:panel:)`）。

## 為什麼

iOS 在深色模式下會把桌布調暗（設定 › 桌布 › 「深色外觀調暗桌布」），iScreen 因此要使用者**淺色／深色各上傳一張**空白桌面截圖。
我們只有一張 → 深色模式下面板背景比真的桌布亮，一眼就看得出「透明」是假的。

## 這張票只做一件事

讓「淺色桌布」與「深色桌布（選填）」各存一份；小工具依**系統當下的外觀**選用；沒設深色那張就用淺色那張。

## 具體步驟

1. **`Logic.swift`**：`Shared` 加 `screenshotDarkURL`（`panel-screenshot-dark.jpg`）、`backgroundDarkURL`（`panel-bg-dark.jpg`）。

2. **`PanelModel.swift`**：
   - 新增 `@Published private(set) var screenshotDark: UIImage?`、`backgroundDark: UIImage?`、`backgroundLumaDark: Double?`。
   - `setScreenshot(_:dark:)`：`dark == false` 行為與現在相同；`dark == true` 寫深色那兩個 URL（Documents 那份不需要）。
   - `recrop()` 同一個 offset 兩張都裁（深色那張存在才裁）。
   - `clearScreenshot()` 兩組都刪；另加 `clearDarkScreenshot()` 只刪深色那組。
   - `previewData` 帶上 dark 那組。

3. **`PanelWidget.swift` provider**：用 0001 的同一套 slot 邏輯，對淺、深各算一次背景（深色缺→`nil`）與各自的 luma，都放進 `PanelData`。

4. **`PanelView.swift`**（只准動資料選擇，**不准改任何視覺常數**）：
   - `PanelData` 加 `backgroundDark: UIImage?`、`backgroundLumaDark: Double?`。
   - `PanelView` 在**最外層**讀 `@Environment(\.colorScheme)`（**注意**：body 裡已經有 `.environment(\.colorScheme, ink.light ? .light : .dark)` 覆寫玻璃用的外觀，系統外觀一定要在這個覆寫之前讀）。
     系統是深色且 `backgroundDark != nil` → 用深色那張與它的 luma；否則用淺色那張。
   - `lightScheme`／`effectiveLuma` 改成吃「實際選中那張」的 luma。

5. **`RootView.swift`** 透明背景區（L30 起的 `Section`，footer 在 L46–53）：
   - 現有「選你的桌布」＝淺色，行為不變。下面加一個 `PhotosPicker`（另一個 `@State` item，比照 L18／L145 的 `screenshotItem` 寫法）
     「深色模式的桌布（選填）」/"Dark Mode wallpaper (optional)"；已設時顯示「換深色桌布」/"Change Dark Mode wallpaper" ＋
     「移除深色桌布」/"Remove Dark Mode wallpaper"（destructive）。
   - **footer 換成新的一段**（新 key＋英文；舊 key 留在 xcstrings 不刪）。內容照下面四點，中文逐字：
     ```
     iOS 不讓小工具真的透明，iScreen 也是用一張桌布截圖。選你設成桌布的那張原圖，或滑到空白桌面截圖再選，會自動裁成面板那一塊。
     位置可以在這裡「對齊背景」拖，或長按小工具 › 編輯小工具 › 位置 直接選。
     深色模式下 iOS 會把桌布調暗：想完全對上，切到深色模式再截一次空白頁，放進「深色模式的桌布」。
     對不齊？到 設定 › 桌布 › 主畫面預覽 關掉「透視縮放」，設定 › 螢幕顯示與亮度 › 顯示縮放 選「預設」，再重新截圖。
     ```
     英文：
     ```
     iOS doesn't let widgets be truly transparent — iScreen uses a wallpaper screenshot too. Pick the photo you use as wallpaper, or a screenshot of an empty Home Screen page, and it's cropped to the panel automatically.
     Set the position here with Align Background, or long-press the widget › Edit Widget › Position.
     In Dark Mode iOS dims the wallpaper: for an exact match, switch to Dark Mode, screenshot an empty page again and add it under Dark Mode wallpaper.
     Not lining up? In Settings › Wallpaper › Home Screen preview turn off Perspective Zoom, set Settings › Display & Brightness › Display Zoom to Default, then take the screenshot again.
     ```
   - L50–52 那個 `panelSizeIsMeasured` 提示保留原樣。

6. **xcstrings**：新增 key＋英文，只准 append。

7. **Check**：`PanelData` 的選擇邏輯若抽成純函式（建議：`static func pick(light:dark:systemDark:) -> Int` 之類放 Logic.swift）就補測試：系統深色＋有深色→深色；系統深色＋沒深色→淺色；系統淺色→淺色。

## 不准做
同 0001（視覺、kind、版本號、tools/docs/App Store、其他模擬器、git 白名單）。

## 完成標準
同 0001 三段指令全綠。

---

## 驗收紀錄（orchestrator，2026-09-21）

- **writer**：ccm3（MiniMax），一次到 candidate；自報「沒有偏離工單」，兩次編譯錯都是自己的命名／參數順序問題。
- **範圍**：7 個檔；`project.yml` hash 未變；reflog 只有 0001 的 commit。PanelView 被刪的行全是 `data.X → resolved.X`，版面／顏色／字級常數一個沒動。
- **關鍵正確性**：系統外觀在 `PanelView` 自己的 `@Environment(\.colorScheme)` 讀（父層傳入＝系統外觀），玻璃用的 `.environment(\.colorScheme, …)` 只作用於子視圖，不會污染判斷。
- **deterministic gate（orchestrator 親跑）**：Check 全綠、`BUILD SUCCEEDED`。
- **真小工具實測**（先 uninstall 才會載到新 binary）：面板區平均亮度 淺色 38.6 → 深色＋有深色桌布 **27.7** → 深色但沒設 **38.6**（＝正確退回淺色那張）。
  **產品入口端到端**：從設定頁「深色模式的桌布（選填）」實際挑照片 → app group 出現 `panel-screenshot-dark.jpg`（1206×2622）與 `panel-bg-dark.jpg`（1049×1697）→ 系統切深色，小工具換成那張。證據 `docs/evidence-1.0.1/0002-*.png`。
- **異家族 review**：AGY（Gemini）8 項全 PASS，`VERDICT: PASS`；review 前後 diff checksum 一致（`83e48249…`）。
- **orchestrator 補的兩件（mechanical，deterministic gate＋目視）**：
  1. 設定頁「深色模式的桌布」那列**沒有圖示**：writer 寫了 `Row("moon", …)` 但素材庫沒有 `tile-moon`。依專案規矩用 `tools/make-tiles.py`＋ictool 產（`tile("indigo", sf("moon.fill", 0.62))`，跟 tile-grid 同色同字形），不用 AI 生圖。
  2. **「對齊背景」頁的預覽一直對不上黃框（09-16 起的舊 bug，審核中的 build 5 也有）**：外層 `.frame(width: r.width * s, …)` 沒寫 alignment，
     SwiftUI 把比它大的原尺寸面板置中塞進去，縮放後整塊往左上偏。加 `alignment: .topLeading` 後預覽精確落在黃框內、框內外畫面連續。
     實際裁切一直是對的（直接用 `rect(offset:)`），壞的只是給人看的預覽——但這頁的用途就是看著預覽拖。
- **UI 測試**：10/12，紅的是已知環境問題（`test3` 沒有斷言、`test7a` 桌面沒有空白頁）；所有產品斷言綠。
- **結論**：CLOSE。
