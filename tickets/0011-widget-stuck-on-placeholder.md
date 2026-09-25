# 0011 — 首次安裝後小工具停在骨架（redacted placeholder）

- 票型：standard（改 widget timeline 行為；客訴、線上 1.0.1 (6)）
- 來源：Micky 09-25 11:4x 轉朋友截圖：「朋友安裝以後，小工具沒東西，但設定裡面有」
- 證據：截圖＝我們 `placeholder(in:)` 版面＋系統 redacted 骨架、底是不透明深藍（sample data 非透明）→ timeline 從沒交出來

## 根因（推定＋佐證）

1. **app 本身從不連網**：天氣只由 widget `WeatherService.current` 抓（`URLSession.shared`、無 timeout＝預設 60 s）。
   app 預覽用 sample／快取，所以「設定裡面有」。
2. 朋友手機有支付寶／微信＝很可能中國大陸機型或網路。大陸機型 app 的「無線資料」權限要由 **app 本身第一次連網** 才跳窗；
   app 沒連過網 → extension 的請求不會失敗而是卡住 → timeline 等到被系統砍 → 永遠 placeholder。
   即使不是大陸機型，慢網路下 60 s 等待本來就超過 widget 預算。
3. 附帶真缺陷：`SystemStats.networkKind()` 的 `done` 旗標跨兩條 queue 無鎖 → 可能 double resume（CheckedContinuation 崩潰）。
4. HealthKit continuation 沒上限：不可取消，理論上也可能拖住 timeline。

sim 全新安裝（Release、新 sim `UTUVO-Panel-FreshInstall-17PM` 6E62282E…）網路正常時**不重現**（`DerivedData-fresh/fresh-home.png`），符合「差在真機網路環境」。

## 修法

- `Shared/Logic.swift` 新增 `Deadline.run(seconds:fallback:_:)`：**非結構化**競賽（TaskGroup 會等不可取消的 child，見 memory `taskgroup-awaits-children-defeats-timeout`）＋`OnceResume` 鎖保護只 resume 一次。
- `WeatherService` 搬到 `Shared/WeatherService.swift`（app 也要用）：專用 ephemeral session，request 5 s／resource 8 s，`waitsForConnectivity=false`，外層 Deadline 6 s，失敗回快取。
- `build()`：天氣 7 s、HealthKit 4 s、SystemStats 2.5 s 各上 Deadline，逾時用快取。
- `networkKind()` 改用 `OnceResume`。
- app 啟動（RootView `.task`）與回前景時抓一次天氣＝①觸發大陸機型的網路權限窗 ②預熱快取給 widget ③完成後 reload widget。

## 驗收

- Check：`Deadline` 三條（快 op 回值、慢 op 回 fallback 且在時限內返回、不可取消的 continuation op 也準時返回）＋已知紅輸入。
- sim 模擬「網路卡死」：把天氣 URL 指到不回應的 host（只在 Check／探針，不進產品）→ timeline 仍在 ≤8 s 內交出。
- Release 全新 sim 安裝＋test2 加小工具 → 有內容。
- UI 回歸 test2/test4。
- 異血統 review（writer＝Claude orchestrator 親寫，理由：客訴急件、<150 行；reviewer＝luna-review 或 ccm3）。

## 狀態

CLOSED 2026-09-25（1acadb1＋71f4b47＋test3 修正）

## Review 1（luna-review／gpt-6-luna，唯讀，index checksum 前後相同 d40603de…）VERDICT: FAIL
原文摘要（逐條）：
1. major `RootView.swift:9-12` launch task 先 await refreshHealth() 才 refreshWeather()；HealthKit 不回呼就永遠到不了天氣 → **修**：天氣改獨立 Task 先起。
2. major `PanelWidget.swift` 三來源串行，最壞 6+4+2.5≈12.5 s → **修**：async let 並行（含行事曆），最壞≈最長時限 6 s。
3. minor EventKit `events(matching:)` 同步、沒上限 → **修**：兩個行事曆讀取也包 Deadline（2 s）。
4. minor 逾時後被放棄的 HealthKit worker／query 會懸著 → **不修（理由）**：extension process 短命，每次 timeline 至多留一個懸掛 task；HKHealthStore.stop 需要把 query 物件拉出 continuation，改動面大於收益。記錄於此。

## 同票附帶
- 版號 1.0.2 (7)。
- UITest：test2 冪等（已有面板就跳過並斷言恰好一個；新裝先開一次 app 讓 gallery 登記）、test3 補斷言、拿掉會 flake 的逐元素列印迴圈（handoff §4 第 4 項）。

## Review 2（luna-review delta on 71f4b47，index checksum 前後相同 c06831b2…）VERDICT: FAIL（僅測試 low）
- 原文結論：「The three prior findings appear fixed … the combination does not appear to block timeline construction past roughly 6–7 seconds or deadlock.」
- Finding 1（Low）：test3 只比水平邊界，垂直在畫面外也會算 on-screen。**不採納**：test3 回答「在哪一頁」（頁面是水平軸）；垂直可見由 test4／scrollToWidget（minY/maxY）負責。
- 回歸：test2 首跑 101 s 綠、再跑 8 s 走 already-added；test3（改成在找到的那頁計數——SpringBoard 不曝露畫面外頁面的 widget，實測計數 0）綠；test4 綠。
