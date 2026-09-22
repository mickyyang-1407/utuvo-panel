# 0001 — 小工具在系統「編輯小工具」裡選背景與位置（iScreen parity 第一段）

- 票型：standard ｜ writer：ccm3（MiniMax；pool-pace 建議第一棒，ark 76% 已停一般 writer）｜ reviewer：agy（Gemini，異家族）
- 分支／worktree：`v1.0.1-transparent` ／ `~/Projects/utuvo-panel-v101`（**只在這個資料夾裡工作**）
- 下一版 1.0.1 的第一張票。版本號、App Store、docs 都不歸這張票。

## 為什麼

使用者覺得 iScreen「有透明選項」、我們沒有。查證結果：iScreen 跟我們一樣是「使用者的桌布截圖 → 裁出小工具那一塊當背景」。
差別在 UX：它在**系統的「編輯小工具」**（長按小工具 → 編輯小工具）裡讓使用者選「透明」和「位置」。
我們現在是進 app 用「對齊背景」頁拖。這張票把「背景」與「位置」兩個選項搬進系統的編輯小工具。

## 這張票只做一件事

把小工具從 `StaticConfiguration` 改成 `AppIntentConfiguration`，加一個 `WidgetConfigurationIntent`，兩個參數：

| 參數 | 選項（中文為 source key，英文放 xcstrings） | 預設 |
|---|---|---|
| 背景 `background` | `transparent`＝「透明（用你的桌布）」/"Transparent (your wallpaper)"；`gradient`＝「漸層」/"Gradient" | `transparent` |
| 位置 `slot` | `custom`＝「在 app 裡對齊的位置」/"Where you aligned it in the app"；`top`＝「頁面頂端」/"Top of the page"；`row1`＝「往下一列」/"One row down"；`row2`＝「往下兩列」/"Two rows down" | `custom` |

**預設值必須讓現有使用者的畫面完全不變**：`transparent`＋`custom` ＝ 今天的行為（用 app 已裁好的 `panel-bg.jpg`）。

## 具體步驟（行號為 1ab4c26 的錨點）

1. **`ios/Shared/Logic.swift`（純 Foundation，Check 也會編它，不准 import UIKit/SwiftUI/WidgetKit/AppIntents）**
   - `enum Shared` 加 `static var screenshotURL: URL { container.appendingPathComponent("panel-screenshot.jpg") }`（跟 L18 `backgroundURL` 並列）。
   - `enum Shared.Key` 加 `static let screenPoints = "panel.screenPoints"`（app 寫入 `[寬, 高]`，單位 pt）。
   - 加一個純資料 enum（給 Check 測、給 intent 用）：
     ```swift
     enum PanelSlotKind: String, CaseIterable { case custom, top, row1, row2
         /// How many icon rows below the top of the page; nil = use the app's aligned crop.
         var rowsDown: Int? { switch self { case .custom: nil; case .top: 0; case .row1: 1; case .row2: 2 } }
     }
     ```
   - `struct PanelPlacement`（L357 起）加：
     - `var rowPitch: Double { (screen.height * 0.1144).rounded() }` —— 註解寫「iPhone 17 Pro / iOS 27.0 實測：桌面圖示列距 100 pt（874 pt 螢幕）」。
     - `func top(for slot: PanelSlotKind) -> Double?`：`slot.rowsDown.map { defaultTop + Double($0) * rowPitch }`。
     - `func rect(top: Double) -> (x: Double, y: Double, width: Double, height: Double)`：水平置中（同 L386），`y` clamp 到 `0...max(screen.height - panel.height, 0)`，四捨五入。**不要改現有的 `rect(offset:)`**。

2. **`ios/Shared/Intents.swift`**：加
   - `enum PanelBackgroundChoice: String, AppEnum`（transparent／gradient），`enum PanelSlotChoice: String, AppEnum`（custom／top／row1／row2，`kind: PanelSlotKind { PanelSlotKind(rawValue: rawValue)! }`）。`typeDisplayRepresentation` 與 `caseDisplayRepresentations` 用上表的中文 key（`LocalizedStringResource`）。
   - `struct PanelWidgetIntent: WidgetConfigurationIntent`：`title`＝「面板設定」/"Panel settings"，`description`＝「選背景與位置」/"Choose the background and position"；兩個 `@Parameter`（`title` 用「背景」/"Background"、「位置」/"Position"），預設如上表。

3. **`ios/PanelWidget/PanelWidget.swift`**
   - `PanelProvider`（L12）改成 `AppIntentTimelineProvider`：`placeholder(in:)`、`snapshot(for:in:) async`、`timeline(for:in:) async`。`build(...)`（L36）多收一個 `PanelWidgetIntent`。
   - 背景決定（取代 L52–54 那兩行）：
     - `gradient` → `background = nil`、`luma = nil`（面板會走既有的深藍漸層 fallback）。
     - `transparent`＋`custom` → 照舊讀 `Shared.backgroundURL`（**行為與今天逐位元相同**）。
     - `transparent`＋`top/row1/row2` → 讀 `Shared.screenshotURL` 的全螢幕截圖，用 `PanelPlacement(screen: 讀 Shared.Key.screenPoints, panel: context.displaySize).rect(top: top(for:)!)` 算 pt 座標，乘上 `截圖像素寬 ÷ screen 寬(pt)` 換成像素，`cgImage.cropping(to:)`。任何一步拿不到（沒有截圖、沒有 screenPoints、crop 失敗）→ 退回 `panel-bg.jpg`，再拿不到就 nil。
     - `luma` 一律用最後拿到的那張算（`averageLuminance`）。
   - L127 `StaticConfiguration(...)` 改 `AppIntentConfiguration(kind: Shared.widgetKind, intent: PanelWidgetIntent.self, provider: PanelProvider())`。**kind 字串不准改**（改了使用者桌面上已放好的小工具會消失）。其餘 modifier（`.configurationDisplayName`、`.description`、`.supportedFamilies`、`.contentMarginsDisabled()`、`.containerBackgroundRemovable(false)`）原樣保留。

4. **`ios/UTUVOPanel/App/PanelModel.swift`**
   - `setScreenshot`（L85）存完 Documents 那份之後，**再**把同一張 JPEG 寫到 `Shared.screenshotURL`，並 `Shared.defaults.set([Double(Self.screenSize.width), Double(Self.screenSize.height)], forKey: Shared.Key.screenPoints)`。
   - `clearScreenshot`（L96 附近）也要刪 `Shared.screenshotURL`。
   - `init()`（L34 附近）加一次性遷移：Documents 有 `screenshot.jpg`、group 沒有 `panel-screenshot.jpg` → 複製過去並寫 `screenPoints`。
   - 以上三處改完都 `reloadWidget()`（現有函式）。

5. **`ios/Shared/Localizable.xcstrings`**：上表所有中文 key ＋英文翻譯。**只准新增 key，不准重排或重寫既有條目**（用 JSON 讀進來、把新 key append 到 `strings` 尾端、`indent=2` 寫回）。

6. **`ios/Check/main.swift`**：新增測試（沿用檔內的 `check(_:_:)`）：
   - `PanelSlotKind.custom.rowsDown == nil`；`top/row1/row2` 依序 0/1/2。
   - 874 pt 螢幕：`rowPitch == 100`、`top(for: .top) == defaultTop`、`top(for: .row1) == defaultTop + 100`。
   - `rect(top:)` 超出底部時 clamp（例：`top: 10_000` → `y == screen.height - panel.height`）；負值 clamp 到 0；`x` 置中。

## 不准做

- **不准改 `PanelView.swift` 的任何視覺**，也不准改 `rect(offset:)`、`backgroundOffset`、AlignView。
- 不准改 kind 字串、bundle id、entitlements、版本號（`project.yml` 的 `MARKETING_VERSION`／`CURRENT_PROJECT_VERSION`）。
- 不准碰 `tools/`、`docs/`、App Store 相關任何東西。
- 模擬器**只准用** `363878E7-E1F6-4F64-9D13-91F4C3E67BD2`（GlassPanel-iOS27-iPhone-17-Pro）。不准碰其他模擬器、不准 erase。
- git 只准跑唯讀指令（status / diff / log / show）。其餘一律禁止——包含但不限於 add / commit / push / reset / checkout / switch / stash / clean / restore / rebase / merge / cherry-pick / tag / worktree。需要動 git 就停下來回報，由 orchestrator 執行。

## 完成標準（全部要跑、貼輸出）

```bash
cd ~/Projects/utuvo-panel-v101/ios && xcodegen generate
swiftc -O Shared/Logic.swift Check/main.swift -o /tmp/c-v101 && /tmp/c-v101        # 全綠，含新測試
xcodebuild -project UTUVOPanel.xcodeproj -scheme UTUVOPanel \
  -destination "platform=iOS Simulator,id=363878E7-E1F6-4F64-9D13-91F4C3E67BD2" \
  -derivedDataPath ../DerivedData build                                              # ** BUILD SUCCEEDED **
```

回報：改了哪些檔（`git diff --stat`）、上面兩段的最後幾行輸出、有沒有任何沒照工單做的地方與理由。
視覺與 SpringBoard 驗收由 orchestrator 做，你不用跑 UI 測試。

---

## 驗收紀錄（orchestrator，2026-09-21）

- **writer**：ccm3（MiniMax）。第一次派工沒起跑：`--allowedTools` 是可變長度參數，把後面的 prompt 吃掉當工具名；改成 prompt 放前面、工具清單逗號串成單一參數後正常。
- **範圍**：6 個檔；`PanelView.swift`／`project.yml` hash 未變；reflog 只有建 worktree 那一筆。
- **deterministic gate（orchestrator 親跑）**：Check 全綠、`BUILD SUCCEEDED`。
- **writer 的錯誤宣稱（已由 orchestrator 短修）**：writer 說「WidgetConfigurationIntent 要求參數必須 optional」，因此兩個參數都改成 optional、沒有預設值。
  實測**非 optional＋`default:` 可以編過**。差別是使用者看得到的：沒預設值時系統「編輯小工具」那兩格是空白。已改成 `@Parameter(title:, default:)` 非 optional（6 行，orchestrator 親改，納入 review）。
- **真小工具實測（模擬器操控 SpringBoard）**：長按 → 出現「Edit Widget」（StaticConfiguration 時沒有）→ 兩個參數顯示預設值
  「Transparent (your wallpaper)」「Where you aligned it in the app」→ 改「Two rows down」背景裁切框確實下移 → 改「Gradient」變深藍漸層。
  證據 `docs/evidence-1.0.1/0001-*.png`。
- **異家族 review**：AGY（Gemini）7 項全 PASS，`VERDICT: PASS`；review 前後 diff checksum 一致（`061bfee5…`）。
- **UI 測試**：9/12。`test3`（沒有斷言、翻頁動畫中查詢丟錯）、`test7a`（桌面沒有空白頁）是已知環境問題；
  `test11` 紅是**早上左右對調造成的測試座標過時**（點到天氣卡），不是這張票——已在 main（`ad5b470`）與本分支修正，重跑 passed。
- **結論**：CLOSE。
