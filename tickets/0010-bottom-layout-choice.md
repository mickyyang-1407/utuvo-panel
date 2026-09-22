# 0010 — 面板下半部三種版面，設定頁可選（逐時天氣／行程清單／平均分配）

- 票型：standard ｜ writer：ccm3（MiniMax）｜ reviewer：agy（Gemini）
- 分支／worktree：`v1.0.1-transparent` ／ `~/Projects/utuvo-panel-v101`（在 0009 `4ec4521` 之後）

## 為什麼

Micky（09-22）看 XL 面板「下面有點空」，看完 A／B／C 三張示意圖後：「ABC 都要，在設定裡面讓使用者選擇」。
XL 目前各排高度加總後底部留 ~65 pt 空白（`Metrics.xl`，最後是 `Spacer`）。

## 這張票只做一件事

`PanelConfig.bottomLayout`（`"hourly"`／`"agenda"`／`"spread"`，預設 `"hourly"`）決定 **systemExtraLargePortrait** 下半部怎麼用掉那塊空白。systemLarge（`compact == true`）完全不受影響。

## 三種版面

- **hourly（逐時天氣）**：在 `SystemBar` 之後加一排 `HourlyStrip`，高 `m.hourly = 62`，用 `GlassCard`。內容：接下來 6 個整點（從下一個整點起），每格三行置中：時間（`HH`，`.caps(8.5)`、`ink.tertiary`）、天氣圖示（`WeatherSnapshot.description.symbol` 同一套對照，SF Symbol `.symbolRenderingMode(.multicolor)`，高 16）、溫度（`"24°"`，`.pf(13, .regular)`、`ink.primary`、`monospacedDigit`）。沒有逐時資料（舊快取／天氣關）→ 這排不畫（等同 spread）。點整排開天氣（`open("weather")`）。
- **agenda（行程清單）**：`WeekCard` 變高（`m.week + 62`），底部的單行事件改成**最多 3 行**：接下來 48 小時內的行程（沒行程時維持原本「今天沒有行程」一行）。每行格式同現有 `WeekCard.line`（今天／明天／星期、時間、標題）。
- **spread（平均分配）**：不加內容；把 VStack 的 `Spacer` 拿掉，改成各排之間平均分配剩餘空間（例：各排之間放 `Spacer(minLength: m.gap)`），讓空白平均散開。

## 具體步驟

1. **`Shared/Logic.swift`**
   - `PanelConfig` 加 `var bottomLayout = "hourly"`；`init(from:)` 用 `decodeIfPresent ?? d.bottomLayout`（跟既有欄位同寫法）。
   - `WeatherSnapshot` 加 `var hourly: [HourlyPoint] = []`，`struct HourlyPoint: Codable, Equatable { var time: Date; var temperature: Double; var code: Int; var isDay: Bool }`。**手寫 `init(from:)` 讓舊快取（沒有 hourly）照樣解得開**（記憶：新欄位要手寫 init(from:)）；既有 memberwise 呼叫點（PanelView sample、Check 三處）不能壞——`hourly` 放最後、有預設值。
   - `url(...)` 加 `hourly=temperature_2m,weather_code,is_day`、`forecast_days` 改 `2`（跨午夜時 6 小時才夠）。
   - `parse(...)`：讀 `hourly.time`（Open-Meteo 在 `timezone=auto` 時是當地時間 `"yyyy-MM-dd'T'HH:mm"`，**要用回應裡的 `utc_offset_seconds` 轉成 Date**）＋三個陣列，長度不一致就 `hourly = []`（不要整個回 nil）。
   - 純函式 `static func nextHours(_ points: [HourlyPoint], after now: Date, count: Int = 6) -> [HourlyPoint]`：回傳 `time > now` 的前 `count` 筆（依時間排序）。
   - `CalendarService` 在 widget target；在 Logic 加純函式 `enum AgendaPick { static func pick(_ events: [EventInfo], now: Date, limit: Int) -> [EventInfo] }`：進行中或 48 h 內開始、依開始時間排序、同時段有時間的排在全天之前、取前 `limit` 筆。
2. **`PanelWidget/PanelWidget.swift`**
   - `CalendarService` 加 `static func upcoming(from now: Date, limit: Int) -> [EventInfo]`（48 h 查詢＋`AgendaPick.pick`）；`nextEvent` 維持不動（hourly／spread 用）。
   - provider：`PanelData` 新欄位 `events: [EventInfo] = []`，只在 `config.bottomLayout == "agenda"` 且顯示行事曆時填 `upcoming(limit: 3)`。
3. **`Shared/PanelView.swift`**
   - `Metrics` 加 `hourly: CGFloat`（xl 62、large 0）。
   - `content` 依 `resolved.config.bottomLayout`（且 `!resolved.compact`）切換，如上三種。
   - `WeekCard` 接 `events: [EventInfo]`；非空且 agenda 時畫多行，否則照舊單行。
   - 新 `private struct HourlyStrip`。
   - **不准動**：Header／時鐘（0009）、邊框（0006/0008）、透明（0005）、其他列的內部樣式與字級。
4. **`UTUVOPanel/UI/RootView.swift`**：「內容」Section 加 `Picker(selection: $model.config.bottomLayout)`：逐時天氣（`hourly`）／行程清單（`agenda`）／平均分配（`spread`），label `Row("layout", "下半部")`。footer 不用改。
5. **圖示**：`tools/make-tiles.py` `TILES` 加 `"tile-layout": tile("teal", sf("rectangle.split.1x2.fill", 0.62)),`，跑 `python3 tools/make-tiles.py tile-layout`。不准手畫／AI 生圖。
6. **`Shared/Localizable.xcstrings`**：新 key＋英文（下半部 / Bottom section；逐時天氣 / Hourly weather；行程清單 / Agenda；平均分配 / Even spacing），**單一 Text＋xcstrings、只 append、保留原格式**。
7. **`Check/main.swift`**：
   - `parse`：帶 hourly 的合成 JSON（含 `utc_offset_seconds: 28800`）→ 第一筆時間正確（例 `"2026-09-22T08:00"` ＋0800 → UTC 00:00）；hourly 陣列長度不一致 → `hourly.isEmpty` 但整體非 nil；舊 JSON（無 hourly）→ 非 nil、`hourly.isEmpty`。
   - 舊快取解碼：沒有 `hourly` 的 WeatherSnapshot JSON 能 decode。
   - `nextHours`：跨午夜、`now` 剛好在整點（不含等於）、不足 6 筆。
   - `AgendaPick`：排序、48 h 外排除、進行中納入、limit。
   - `PanelConfig` 舊 JSON → `bottomLayout == "hourly"`。

## 不准做

- 不准改 systemLarge 版面、版號、bundle id、entitlements、SPI 腳本、App Store。
- 不准加新權限（行事曆沿用既有 fullAccess 判斷）。
- 模擬器只准用 `363878E7-E1F6-4F64-9D13-91F4C3E67BD2`；不准 erase。
- git 只准跑唯讀指令（status / diff / log / show）。其餘一律禁止——包含但不限於 add / commit / push / reset / checkout / switch / stash / clean / restore / rebase / merge / cherry-pick / tag / worktree。需要動 git 就停下來回報。

## 完成標準（全部要跑、貼輸出）

```bash
cd ~/Projects/utuvo-panel-v101 && python3 tools/make-tiles.py tile-layout && ls ios/Shared/Tiles.xcassets | grep tile-layout
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

- **writer**：ccm3（MiniMax）。7 檔＋tile-layout 圖示；受保護檔 hash 未變。writer 自改一條 AgendaPick 測試的命名／預期（實作符合工單「同開始時間 timed 在 all-day 前」），查證合理。
- **orchestrator 抓到並修的（實拍才看得到）**：
  1. **逐時天氣條超出面板底部**：工單的 62 pt 是照 Pro Max 目測估的；XL 面板高度因機型不同（17 Pro 幾乎零空間、17 Pro Max ≈ 53 pt）。改成 `GeometryReader` 算剩餘空間：逐時條高 = min(62, 剩餘 − gap)，< 40 不畫、< 54 用兩行格；agenda 加高 = min(62, 剩餘)、行數依空間。
  2. **預覽在 hourly 模式也出現 3 行行程**：WeekCard 只要 events 非空就多行 → 只在 agenda 傳 events。
  3. **預覽看不到逐時／多行程**：`PanelData.sample` 補逐時與 3 筆範例行程；預覽優先用已抓到的真實天氣。
  4. **舊天氣快取沒有逐時資料要等 30 分鐘**：沒有 hourly 的快取視為過期。
- **gate**：Check 全綠；UI test13（設定頁逐一選三種→預覽＋桌面截圖）**passed**（17 Pro 與 17 Pro Max 各一次）；回歸 test5／6／10／11／12 **passed**。
- **實測（17 Pro Max sim）**：`docs/evidence-1.0.1/0010-17pm-{widget,preview}-{hourly,agenda,spread}.png`——逐時條兩行格、行程清單加高、平均分配三種都對；預覽 agenda 顯示 3 行。
- **異家族 review**：AGY（Gemini）7 PASS／1 FAIL。FAIL 三點：①`if compact {…} else { icon; temp }` 歧義——**駁回**（ViewBuilder 合法，Pro Max 預覽三行格實拍正確）；②EventKit 查不到進行中事件——**駁回**（predicateForEvents 是區間重疊，reviewer 自己也寫了）；③`ForEach(id: \.start)` 同開始時間重複 id——**成立，已修**（改 index id）。前後 checksum 一致（`3f8a9189…`）。
- **結論**：CLOSE。

## 追加（09-22 10:50）：逐時天氣條移到天氣卡正下方

Micky：「hourly weather 放在最下面好怪」→ 看三個位置示意圖選 1（天氣卡正下方）。orchestrator 親修（搬移一個區塊，+4／−4）；Pro Max sim test13 passed，截圖 `docs/evidence-1.0.1/0010b-17pm-{widget,preview}-hourly.png`。
