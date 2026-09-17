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

## 21:30 第四輪：icon 不是 Liquid Glass

- 根因：App icon 給的是扁平 PNG appiconset；iOS 26 起要 **Icon Composer `.icon` 包**，系統才套 Liquid Glass（四變體）。
- 家族語彙（`~/Projects/utuvo/company/utuvo-brand/icons/*/*.icon`）：九個產品**共用同一個 mark SVG**（md5 相同）、
  同一個底 `srgb 0.051,0.067,0.086`、group shadow neutral 0.5＋translucency 0.5、scale 1.15，**只換一個產品色**。
  已用：珊瑚／琥珀／紫／靛／紅／粉／綠／青／藍。Panel 取 **冰白 `srgb 0.80,0.88,0.96`**（玻璃產品）。
- 接法：`UTUVOPanel/Resources/UTUVOPanel.icon` 放進 sources，`ASSETCATALOG_COMPILER_APPICON_NAME: UTUVOPanel`；
  xcodegen 2.45.4 認得 `wrapper.icon`，actool 自動產 fallback PNG。扁平 appiconset 已刪。
- 面板內五個 app 磚：`glassEffect(.tint)` 在 WidgetKit 內顏色會被洗白（證據 att17），改手繪：產品色 78%＋頂部鏡面漸層＋底部暗影＋髮絲邊。
- 證據：`09-app-icon-liquid-glass.png`、`10-glass-launcher-tiles.png`。已裝真機。

## 21:50 第五輪：「icon 要跟 iOS 一樣」

- 家族語彙（深底＋單色 mark）在 iOS 26 桌面上不像 Apple 自家 icon。Apple 語彙＝**`automatic-gradient` 單色底**（系統自動做上亮下暗）
  ＋**白色 `glass: true` 字形**（厚度、鏡面、陰影由系統算）＋ `lighting: individual`。
- 用 `ictool`（`Icon Composer.app/Contents/Executables/ictool`，`--design-generation 27`）離線渲染，不用進 SpringBoard 就能看：
  六候選在 `docs/evidence-2026-09-16/11-icon-candidates-ictool.png`，候選 `.icon` 包在 `docs/icon-candidates/`。
- 選了 **panel-blue**（面板字形＋iOS 藍）；Default／Dark／ClearLight／ClearDark 四渲染 `12-icon-renditions.png`；
  Tinted 渲染 ictool 要 `--tint-color`，兩次失敗未追。真機已裝（commit `b8bfb52`）。
- 這是品味決定，家族其他八顆仍是深底語彙——要不要全家族跟進是 Micky 的事。

## 22:25 第六輪：icon 定案 mark-blue；app 內 icon 全走 ictool 管線

- App icon＝**家族 mark＋iOS 藍 automatic-gradient＋白色 glass**（Micky 選）。候選包留在 `docs/icon-candidates/`。
- **app 內所有 icon 不再手畫**：`tools/make-tiles.py` 把每顆磚當成迷你 App icon（同一份 icon.json 語彙）交給 `ictool` 渲染，
  輸出 `ios/Shared/Tiles.xcassets`（27 顆 @3x，52 pt）。SF Symbol 圖層由 `tools/symbol2png.swift` 產（白色、49% 畫布）。
  改 Launcher 預設或列 icon → 重跑 `python3 tools/make-tiles.py`（會重建整個 catalog）。
- 用到的地方：面板五磚、一句話磚、設定頁所有列（`Row`／`SettingsIcon`）、常用 app 選單。Clear／tinted 模式回落白色符號在半透明板上。
- 證據：`14-glass-tiles.png`、`15-widget-with-glass-tiles.png`、`16-settings-rows.png`、`17-icon-mark-blue.png`。真機已裝（`a8dc29c`）。
- 「改到我覺得好為止」——下一輪等 Micky 指哪裡。

## 23:20 第七輪：圓鈕／天氣走管線、字型可選、icon 依 macosicons.com 重做

- **參考**（`23-macosicons-reference.png`，macosicons.com「macOS 27」搜尋前 16 顆）的共通點：字形粗、幾何、大（55–65%）、由厚玻璃筆畫構成，
  重疊處半透明見層次；底是飽和 automatic gradient 或深底＋發光玻璃字形。我原本的 mark 是細線插畫，套玻璃只是描線。
- 做法：家族 mark 用 SVG `stroke` 加粗（`mark-bold.svg`，stroke-width 120 路徑單位 ≈ +30 px）；再粗（220）內部細節糊掉，不用。
  兩輪 12 候選（`18`、`19`），定 **bold-big＋refractivity**：scale 1.35、`features:["refractivity","specular-location"]`、
  refractivity strength 1 depth 1、specular outside、translucency 0.45、藍 automatic gradient。四渲染 `20`。
  linear-gradient 底 ictool 27.0 拒收（格式錯），沒追。
- **圓鈕**（齒輪／播放／暫停／停止）用 `--platform watchOS`（circles）渲染；**天氣**每個 WMO 符號一顆磚（日藍／夜藍／灰）——
  `make-tiles.py` 的 `circles`／`weather` 清單；自檢加了「WMO 表每個符號都有磚」。
- **字型可選**：`PanelConfig.fontDesign` default／rounded／serif／mono，設定頁 Picker；面板所有文字走 `pf()`。
- 真機已裝。

## 23:45 第八輪：五顆 app 磚改分層手繪（Micky：icon 喜歡了，磚太醜）

- 醜的原因：SF Symbol 49% 細字形丟在漸層上。Apple 自家 icon 是大字形（60–65%）、粗、**多層物件**。
- 做法：`tools/tiles/*.svg` 手繪分層（Music 雙音符／Messages 大泡泡／Maps 摺頁＋紅針／Camera 機身＋鏡頭圈＋藍鏡片／Notes 黃帶＋白紙＋灰線），
  `make-tiles.py` 的 `CUSTOM` 表每層可設顏色、scale、glass、translucency。其餘 SF 磚改 bold、60%。
- 🔴 **Icon Composer 圖層順序＝第一個在最上面**（跟 Composer 面板一樣）。我先照底→頂寫，線條全被蓋掉；`render_custom` 現在 reverse。
- 證據 `24-launcher-tiles-layered.png`、`25-launcher-row-on-panel.png`。真機已裝。
- 下一步：Micky 要談 App icon 顏色；其餘 10 顆磚若也要分層手繪，照 CUSTOM 表加。

## 09-17 07:50 第九輪：磚改用 ChatGPT 圖（Micky 拿我的 prompt 去畫）

- 來源圖在 `docs/tile-sources-chatgpt/`（01 五顆／02 十顆／03 圓鈕／04 天氣 5×3）；prompt 在 `~/Desktop/UTUVO-Panel-icon-prompt/PROMPT-tiles.md`。
- `tools/slice-tiles.py <img> squircle|circle <pt> <ids>`：純黑底找亮區→列→欄切格、正方化、1024 重取樣、
  套 superellipse（k=5）或圓形遮罩（內縮 1.2% 去黑邊）、存 @3x。圓鈕 48 pt、app 磚 52 pt、天氣 44 pt。
- 這批磚**不再走 ictool**（ChatGPT 已烤好玻璃）；`make-tiles.py` 仍管 tile-note 與設定頁列 icon（重跑會覆蓋 catalog！——
  ⚠️ 要重跑 make-tiles 前先備份或改成只產缺的）。
- 證據 `26`、`27`、`28`。真機已裝。

## 09-17 08:20 第十輪：「一句話」列換成系統列

- Micky：沒人會寫一句話，改放 CPU／Storage／Wi-Fi／藍牙開關或監看。
- **開關做不到**（iOS 沒有第三方切 Wi-Fi／藍牙／飛航的 API，app 內都不行）。**監看**做：
  `Shared/SystemStats.swift`——CPU（host_processor_info 兩次取樣 0.25 s）、RAM（vm_statistics64 active+wired+compressed）、
  儲存（volumeAvailableCapacityForImportantUsage）、連線（NWPathMonitor 1 s 逾時）、電量（UIDevice，extension 讀不到就 nil）。
- 快照存 `panel.system`；timeline 改 15 分鐘一輪。sim 上讀到的是 Mac 的數字（512 GB／16 TB／wired），真機才是手機的。
- `showNote` 退役（key 留著給舊 config 解碼），新 `showSystem`。設定頁的一句話輸入框拿掉。
- `make-tiles.py` 改成**只產缺的或指定的 id**，不再整個 catalog 重建（ChatGPT 磚不會被蓋）。系統列六顆磚先用管線版，
  要高質感再請 ChatGPT 畫：cpu／memory／storage／wifi／cellular／offline。
- 證據 `29-system-row.png`。真機已裝。

## 09-17 08:45 第十一輪：系統列六磚＋綠葉換 ChatGPT 圖（05.png）

- 面板上**所有磚／鈕／天氣**現在都是 ChatGPT 渲染（來源 `docs/tile-sources-chatgpt/01–05`），管線只剩設定頁列 icon。
- 證據 `31-panel-final-tiles.png`。真機已裝（`da2d497`）。
- 剩下的：App icon 顏色（Micky 要談）、真機看透明對齊、要不要開 repo。

## 09-17 09:10 第十二輪：齒輪縮小、完成鈕、語言跟系統、icon 深底發光

- 齒輪 48→30 pt、85% 透明度。
- 「完成」：iOS 不允許 app 自己回桌面（只有私有 API），所以完成＝立刻 reload widget＋玻璃 toast「已套用到面板」。
- 本地化：`Shared/Localizable.xcstrings`（source zh-Hant，en 全翻），xcodegen `developmentLanguage: zh-Hant`；
  兩個 target 都含 catalog。Text 字面自動走 key；String 參數處改 `LocalizedStringKey`／`String(localized:)`。
  sim（英文）實拍 `32`、`33`；其他語言退回繁中。
- icon 改 **深底發光**（solid 0.08/0.09/0.12 底＋mark 0.45/0.68/1.0 玻璃、translucency 0.6、refractivity）——Micky 說照我建議；`34`。
- 真機已裝。

## 09-17 09:50 第十三輪：設定改 sheet、啟動列直轉、系統資訊可選、天氣橫排、活動數字放大

- App 結構：`RootView`＝面板預覽＋右上齒輪；`SettingsView` 是 sheet，「完成」＝reload widget＋dismiss（真的關掉）。
  齒輪 deep link `utuvopanel://settings` 直接開 sheet；launcher deep link 進來不顯示任何 UI 直接 `open(target)`（中轉那一下是 iOS 硬限制）。
- 系統資訊可選四格：`SystemMetric.all` 11 項（cpu／ram／memfree／storage／used／network／battery／lowpower／thermal／uptime／ip），
  `PanelConfig.systemMetrics`；新讀數在 `SystemStats`（ProcessInfo 低耗電／熱狀態／開機時間、getifaddrs IPv4）。
  新六顆磚先用管線版；ChatGPT prompt 在 PROMPT-tiles.md §6。
- 天氣列：磚 44 pt｜狀態｜H/L 橫排；活動數字 18→26。
- 測試 test1／test10 改走 sheet；test10 驗 Done 關閉。證據 `36`、`37`。真機已裝。
