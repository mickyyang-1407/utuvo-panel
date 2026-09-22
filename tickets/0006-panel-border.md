# 0006 — 面板邊框（樣式＋顏色，在「編輯小工具」選）

- 票型：standard ｜ writer：ccm3（MiniMax）｜ reviewer：agy（Gemini）
- 分支／worktree：`v1.0.1-transparent` ／ `~/Projects/utuvo-panel-v101`（在 0005 之後施工）

## 為什麼

Micky（09-21，看完真透明面板）：「我們可以學 iscreen，讓我選擇可不可以做框框嗎就是描邊，然後邊框可以選擇，樣式或是顏色？」
iScreen 的透明小工具有一圈可選的白色描邊，透明面板少了邊界時特別需要。

## 這張票只做一件事

長按面板 › 編輯小工具 多兩個選項：「邊框」與「邊框顏色」，面板外緣畫出對應的描邊。預設「無」＝現在的樣子不變。

## 選項（中文是 source key，英文放 xcstrings，逐字照抄）

`PanelBorderChoice`（`@Parameter(title: "邊框", default: .none)`）：
| case | 中文 | English | 畫法 |
|---|---|---|---|
| none | 無 | None | 不畫 |
| hairline | 細線 | Hairline | 1 pt 實線 |
| bold | 粗線 | Bold | 3.5 pt 實線 |
| double | 雙線 | Double | 外 2 pt＋往內 5 pt 再一圈 1 pt |
| dashed | 虛線 | Dashed | 2 pt，dash [8, 6]，round cap |
| glow | 光暈 | Glow | 2 pt 實線＋同色 shadow radius 6（兩層，第二層 radius 12、opacity 0.5） |

`PanelBorderColorChoice`（`@Parameter(title: "邊框顏色", default: .white)`）：
| case | 中文 | English | 色值 |
|---|---|---|---|
| white | 白 | White | #FFFFFF |
| black | 黑 | Black | #000000 |
| ink | 跟文字一樣 | Match text | 面板目前墨色（`PanelInk.primary`） |
| coral | 珊瑚紅 | Coral | #FF453A（家族 accent） |
| gold | 香檳金 | Champagne | #E3C58A |
| sky | 天藍 | Sky | #64D2FF |

## 具體步驟

1. **`ios/Shared/Logic.swift`**：純資料（Check 要測，只用 Foundation）
   ```swift
   struct PanelBorderSpec: Equatable {
       var width: Double; var dash: [Double]; var innerWidth: Double?; var innerInset: Double; var glowRadii: [Double]
       static func from(style: String) -> PanelBorderSpec?   // "none" 或未知 → nil
   }
   ```
   數值照上表。
2. **`ios/Shared/Intents.swift`**：加兩個 AppEnum 與兩個 `@Parameter`（非 optional＋`default:`，跟既有「背景」「位置」同寫法），`PanelWidgetIntent` 的 `parameterSummary`（若有）一併補上。
3. **`PanelConfig` 不動**；把選擇帶進 `PanelData`：加 `var borderStyle: String = "none"`、`var borderColor: String = "white"`；provider 從 intent 讀 rawValue 填入。
4. **`ios/Shared/PanelView.swift`**：在最外層（`BackgroundModifier` 之後、同一個形狀）加 overlay：
   - 在小工具裡用 `ContainerRelativeShape()`（自動貼合系統圓角）；app 內預覽用與預覽裁切相同的 `RoundedRectangle(cornerRadius: 36, style: .continuous)`。
   - 用 `strokeBorder`（畫在內側，不會被裁掉）。雙線的內圈用 `.inset(by: innerInset)`。
   - 顏色 `ink` 取 `PanelInk.primary`；其餘照色值。
   - `accented`（清透／染色桌面）時邊框用 `Color.white.opacity(0.6)` 且 `.widgetAccentable()`。
   - `allowsHitTesting(false)`，不能擋到按鈕。
5. **`ios/Shared/Localizable.xcstrings`**：新 key＋英文，只准 append。
6. **`ios/Check/main.swift`**：`PanelBorderSpec.from` 至少 7 條（6 樣式＋未知字串回 nil）。

## 不准做

- 不准改背景／位置選項、透明邏輯（0005）、截圖裁切、`SetupGuide.swift`、`RootView.swift`、版號、bundle id、entitlements、`tools/`、App Store。
- 不准用圖片素材或 AI 生圖做邊框（全部 SwiftUI 畫）。
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
```

回報：改了哪些檔、輸出最後幾行、沒照工單做的地方與理由。畫面實測由 orchestrator 做。

---

## 驗收紀錄（orchestrator，2026-09-21）

- **writer**：ccm3（MiniMax）。範圍 6 檔；受保護檔（SetupGuide／RootView／兩份 entitlements／SPI 腳本）hash 未變。偏離兩處皆合理：無既有 `parameterSummary` 故不加；雙線內圈用 `padding` 代 `inset(by:)`（型別擦除後無 inset）——目視確認 ContainerRelativeShape 內圈同心。
- **gate**：Check 全綠（9 條 PanelBorderSpec）、xcstrings JSON ok、`BUILD SUCCEEDED`。
- **實測（sim，真的在「編輯小工具」點選）**：選項表出現「邊框／邊框顏色」各 6 項（英文 UI 顯示 Border／Border colour）；雙線白（`0006-sim-border-double-white.png`，放大轉角同心）、光暈珊瑚紅（`0006-sim-border-glow-coral.png`）。
- **異家族 review**：AGY（Gemini）7 項 PASS；前後 checksum 一致（`547b2b4c…`）。
- **結論**：CLOSE。
