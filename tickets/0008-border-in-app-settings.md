# 0008 — 邊框也放進 app 設定（學 iScreen），編輯小工具多「跟 app 設定一樣」

- 票型：standard ｜ writer：ccm3（MiniMax）｜ reviewer：agy（Gemini）
- 分支／worktree：`v1.0.1-transparent` ／ `~/Projects/utuvo-panel-v101`（在 0007 之後）

## 為什麼

Micky（09-21）：「框框也要學 iscreen 放進去設定」。iScreen 的邊框在 app 裡選，編輯小工具有「Follow App Settings」。現在（0006）只有編輯小工具能選。

## 這張票只做一件事

app 設定頁新增「邊框」區塊（樣式＋顏色，預覽即時反映）；編輯小工具的兩個邊框選項多一個「跟 app 設定一樣」並設為預設。

## 具體步驟

1. **`Shared/Logic.swift` 的 `PanelConfig`**：加 `var borderStyle = "none"`、`var borderColor = "white"`；`init(from:)` 用 `decodeIfPresent ?? d.x`（同既有寫法），`CodingKeys`（若有明列）同步。
2. **`Shared/Logic.swift`**：純函式（Check 要測）
   ```swift
   enum PanelBorderPick {
       /// intent 值為 "app" → 用 app 設定；否則用 intent 值。
       static func resolve(intentValue: String, appValue: String) -> String
   }
   ```
3. **`Shared/Intents.swift`**：`PanelBorderChoice` 與 `PanelBorderColorChoice` 各加 `case app`，顯示「跟 app 設定一樣」／"Same as app settings"，**放在選單第一個**；兩個 `@Parameter` 的 `default` 改 `.app`，`borderDefault`／`borderColorDefault` 同步。
4. **provider（`PanelWidget.swift`）**：`borderStyle: PanelBorderPick.resolve(intentValue: intent.borderValue.rawValue, appValue: config.borderStyle)`，顏色同理。
5. **app 預覽**：`PanelModel.previewData` 帶 `borderStyle: config.borderStyle, borderColor: config.borderColor`（預覽要看得到邊框）。
6. **`UTUVOPanel/UI/RootView.swift`**：在「內容」Section 之後新增 `Section("邊框")`：
   - `Picker` 樣式：無／細線／粗線／雙線／虛線／光暈（tag = `none/hairline/bold/double/dashed/glow`），label `Row("border", "樣式")`。
   - `Picker` 顏色：白／黑／跟文字一樣／珊瑚紅／香檳金／天藍（tag = `white/black/ink/coral/gold/sky`），label `Row("palette", "顏色")`；樣式為「無」時 `.disabled(true)`。
   - footer：「桌面上每個面板都會用這裡的邊框；想讓某一個不一樣，長按它 › 編輯小工具 單獨改。」
   - 改動要觸發既有的存檔＋`reloadWidget()`（跟其他 config 欄位同一條路；確認 `config` 的 didSet／apply 流程會帶到）。
7. **圖示**：`tools/make-tiles.py` 的 `TILES` 加
   `"tile-border": tile("pink", sf("square.dashed", 0.66)),`
   `"tile-palette": tile("purple", sf("paintpalette.fill", 0.64)),`
   跑 `python3 tools/make-tiles.py tile-border tile-palette` 產出到 `ios/Shared/Tiles.xcassets`。**不准手畫、不准 AI 生圖**。`Row` 取圖的命名規則照既有（`Row("border", …)` 對 `tile-border`，先確認）。
8. **`Shared/Localizable.xcstrings`**：新 key＋英文，**單一 Text＋xcstrings**（不准在畫面上並列中英）；只准 append 條目、保留原格式（2 格縮排、`": "`）。
9. **`Check/main.swift`**：`PanelBorderPick.resolve` 至少 3 條（app→用 app 值、明確值→用明確值、app 設定為 none→none）；`PanelConfig` 舊資料（沒有 borderStyle 欄位的 JSON）解碼後為 none/white。

## 不准做

- 不准改 0005 SPI、0006 邊框畫法（`BorderModifier`／`PanelBorderSpec`）、版號、bundle id、entitlements、App Store。
- 不准刪任何現有 Section 或設定。
- 模擬器只准用 `363878E7-E1F6-4F64-9D13-91F4C3E67BD2`；不准 erase。
- git 只准跑唯讀指令（status / diff / log / show）。其餘一律禁止——包含但不限於 add / commit / push / reset / checkout / switch / stash / clean / restore / rebase / merge / cherry-pick / tag / worktree。需要動 git 就停下來回報。

## 完成標準（全部要跑、貼輸出）

```bash
cd ~/Projects/utuvo-panel-v101 && python3 tools/make-tiles.py tile-border tile-palette && ls ios/Shared/Tiles.xcassets | grep -E "tile-(border|palette)"
cd ios && xcodegen generate
swiftc -O Shared/Logic.swift Check/main.swift -o /tmp/c-v101 && /tmp/c-v101
xcodebuild -project UTUVOPanel.xcodeproj -scheme UTUVOPanel \
  -destination "platform=iOS Simulator,id=363878E7-E1F6-4F64-9D13-91F4C3E67BD2" \
  -derivedDataPath ../DerivedData build
python3 -c "import json;json.load(open('Shared/Localizable.xcstrings'))" && echo xcstrings-ok
git -C .. diff --stat
```

回報：改了哪些檔、輸出最後幾行、沒照工單做的地方與理由。畫面實測由 orchestrator 做。

---

## 驗收紀錄（orchestrator，2026-09-22）

- **writer**：ccm3（MiniMax）。8 檔＋兩顆 make-tiles 產出的圖示（tile-border／tile-palette）；受保護檔 hash 未變。多 append 3 條 xcstrings（畫面實際用到的字，合理）。
- **gate**：Check 全綠（PanelBorderPick 5 條＋舊 JSON 解碼 2 條）、`BUILD SUCCEEDED`、xcstrings ok。
- **實測（sim）**：設定頁「Border」區塊兩列＋新圖示；選 Dashed＋Champagne → app 預覽即時出現金色虛線（`0008-app-preview-dashed-gold.png`）；桌面上從沒單獨設過的面板跟著變金色虛線（`0008-home-widget-follows-app-dashed-gold.png`）；單獨設過珊瑚紅光暈的那個仍保留（`0008-pages-explicit-override-kept.png` 第一格）。
- **異家族 review**：AGY（Gemini）7 項 PASS；前後 checksum 一致（`152b2b9e…`）。
- **結論**：CLOSE。
