# UTUVO Panel — 接手點（2026-09-16 20:30 更新）

> 起因：Micky 丟一張小紅書截圖（Koco Widgets「iOS 27 特大尺寸組件」）說「我們也做一個吧」。
> 非 Pik／UTUVO 產品線；獨立小 app，放 `~/Projects/utuvo-panel`（本機 git，**未開 GitHub repo**，等 Micky 說）。
> 命名「透明面板／GlassPanel」是我代決，可改。

## 現況：iOS 27 模擬器上小工具已在桌面活著，六條 UI 測試全綠

| 項 | 狀態 | 證據 |
|---|---|---|
| 新 family `systemExtraLargePortrait`（`@available(iOS 27.0)`） | 用上了 | SDK swiftinterface 第 951 行；`docs/evidence-2026-09-16/02-gallery-xl-portrait.png` |
| 面板在桌面 | ✅ | `01-widget-on-home.png`（時鐘、Open-Meteo 真抓 25°／晴、五磚、計時器、透明背景） |
| 計時器 AppIntent 按鈕 | ✅ 5:00→4:54→× 回 Play | `03-timer-running.png`、test5 |
| 啟動列 deep link → app → 轉發目標 scheme | ✅ Maps 進前景 | `04-launcher-to-maps.png`（Maps 模擬器畫面黑，但狀態列「◀ 透明面板」＋XCTest `runningForeground` 斷言過） |
| 透明背景（截圖裁切） | ✅ 流程通 | test1 選相片→`panel-bg.jpg` 1 MB 落在 App Group |
| 純邏輯自檢 `Check/main.swift` | 40 條全綠 | `swiftc -O Shared/Logic.swift Check/main.swift -o /tmp/c && /tmp/c` |

**實測尺寸**（iPhone 17 Pro／iOS 27.0 24A434）：provider `displaySize` **349.67 × 565.67**（比 1.618，側邊 26 pt）。
估算公式已校成 `screen−52 × 1.618`；小工具加進桌面後 provider 會把真值寫進 `panel.displaySize.xlPortrait`，app 之後裁切用真值。

## 架構（xcodegen 正本 `ios/project.yml`；加檔必跑 `xcodegen generate`）

- `Shared/Logic.swift` — Foundation only：App Group 常數、`PanelConfig`（自訂 `init(from:)` 容忍缺 key）、`Launcher` 15 個預設（URL scheme）、
  `WeatherSnapshot`（Open-Meteo，免 key）、`ActivitySnapshot`、`TimerState` 狀態機、`PanelPlacement` 裁切幾何。
- `Shared/PanelView.swift` — 面板 UI，widget 與 app 預覽共用（`inWidget:` 切 `containerBackground` vs `.background`）。
- `Shared/Intents.swift` — `TimerToggleIntent`／`TimerStopIntent`（兩個 target 都編）。
- `PanelWidget/PanelWidget.swift` — provider：每分鐘一 entry ×30、天氣 30 分快取、EventKit 讀下一筆行程、寫 displaySize。
- `GlassPanel/App/PanelModel.swift` — 截圖裁切、頭像、EventKit／CoreLocation／HealthKit 授權與讀取（HealthKit 只能 app 讀，寫進 App Group 給 widget）。
- `UITests/WidgetFlowTests.swift` — 六條 XCUITest 直接驅動 SpringBoard（長按→Edit→Add Widget→搜尋→最後一頁→Add）。

跑法：
```
cd ~/Projects/utuvo-panel/ios && xcodegen generate
UDID=363878E7-E1F6-4F64-9D13-91F4C3E67BD2   # GlassPanel-iOS27-iPhone-17-Pro（sim 名未改）（iOS 27.0 runtime 已下載 8 GB）
xcodebuild -project UTUVOPanel.xcodeproj -scheme UTUVOPanel -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath ../DerivedData test
```

## 已知限制／下一步

1. **iOS 27 桌面是直向捲動的**（模擬器預設頁：News／Maps／Screen Time 疊著）。透明背景只在某個停留位置對得齊；
   靠 app 的「面板位置」滑桿手調。Koco 也是同一招。
2. 模擬器沒有真桌布可對——透明效果的**視覺**證明要在真機（截空桌面→選→加小工具→看邊緣）。
3. 天氣沒定位時預設台北座標並顯示「定位中」；授權定位後 reverse geocode 填城市。
4. HealthKit 在模擬器是 0；真機才有數字。行事曆需 app 內按「行事曆」授權（full access）。
5. 沒做：Podcast／Now Playing 磚（extension 拿不到）、多面板、iPad。
6. `UITests` 的 test3 走頁面用 `allElementsBoundByIndex`，已修掉 live query 索引崩。

## 卡 Micky（已寫 MICKY-TODO）

- 上真機（需簽章身分；DEVELOPMENT_TEAM 目前空）＋看透明對齊與 HealthKit 真數字
- 品味：配色／字級／模組順序；名字要不要留「透明面板」
- 要不要開 GitHub repo（private）

## 20:30 第二輪（Micky 五點回饋）

1. **免截圖透明＝iOS 26 系統「Clear」圖示樣式**：系統自動拿掉 widget 背景、換成玻璃、內容 accented 白化。
   iScreen／Koco 就是靠這個；截圖法只給「全彩」桌面用。實作：`@Environment(\.widgetRenderingMode)`，
   accented 時 `containerBackground` 不畫、卡片只留細框、彩色磚改半透明白；重點文字加 `.widgetAccentable()`。
2. **裁切對齊**：實測面板當某頁第一個項目時 **頂邊 y = 88 pt**（874 pt 螢幕，10.07%）；
   裁切範圍改成全螢幕 0…1，首次選截圖自動設到 88 pt，`AlignView` 用拖曳＋「往上／下 1 pt」微調。
3. 人頭 → **齒輪**（`utuvopanel://settings` 回 app）。
4. **時間走秒**開關：`Text(timerInterval: 當天 0:00…24:00, countsDown: false, showsHours: true)`，系統每秒推進，不吃 timeline。
   WidgetKit 做不到「冒號閃爍」（最小更新粒度不是秒），這是替代。
5. 質感：卡片 `glassEffect(.regular.tint(黑 18%))`＋漸層細框；圓鈕也玻璃；字體 SF Pro（數字 rounded）。

## 21:20 第三輪：「還是沒有透明」——實驗結論

- **WidgetKit 沒有真透明。** 同一台 sim 實測：`containerBackground` 給 `Color.clear` → 系統墊深藍底；給 `Color.white.opacity(0.01)` → 墊白底。
  證據 `docs/evidence-2026-09-16/07-clear-bg-is-opaque.png`、`08-alpha001-bg-is-opaque.png`。
- **iScreen 也是截圖法**：搜到的教學與 App Store 說明都寫「需要一張空白桌面截圖／上傳壁紙」；「免截圖」是印象錯誤，
  或是指 iOS 26「透明」圖示樣式（系統玻璃）。
- 因此產品做法定案：
  1. 全彩桌面 → 選**桌布原圖**（不必截圖）：app 把任何尺寸 aspect-fill 到螢幕尺寸（iOS 鋪桌布的方式），再裁面板那塊。
  2. 「透明」圖示樣式 → 系統玻璃，accented 模式已支援。
  3. 對齊：預設頂邊 88 pt（面板當該頁第一項），`AlignView` 拖曳＋±1 pt。桌布若開了「透視縮放」會有些微縮放差，目前只提供垂直微調。
- sim 拿不到未模糊的桌布原檔（只有 PaperBoardUI 的 blur 快取），所以對齊的視覺證據只能在真機。
