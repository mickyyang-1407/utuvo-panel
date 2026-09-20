# UTUVO Panel — 面板視覺 v2（editorial glass）

> 版本：v1 ｜ 建立：2026-09-21 ｜ 上一棒：Claude Code（Opus 5）｜ 下一棒：任何 AI 或 Micky
> 這是**現行接手點**。產品／上架／環境／禁區看 `HANDOFF-2026-09-20-utuvo-panel.md`（仍然有效，只有「面板長相」那部分被本檔取代）。
> 狀態：程式面已完成並自驗（commit `6907848`＋`a60686a`，**未 push**）；**卡 Micky 三件**：要不要 push、要不要為了這版重送審、真機目視。

---

## 1. 為什麼改

Micky 2026-09-21 丟了三張 iPhone 桌面照（Widgy 面板：淺玻璃卡、極細大字、micro-caps 小標、虛線連接線、整週日曆）
說「這才是我要的質感，不是現在這樣，字型也是，我們差太多了，對齊！！！然後超越」。

舊面板（v1）的問題，逐條對照參考圖：

| 參考圖 | v1 | v2 |
|---|---|---|
| SF Pro，英雄數字 thin | SF **Rounded**，幾乎全 semibold／bold | SF Pro；`.thin` ＋負字距的英雄數字，標籤一律 micro-caps ＋ tracking |
| 黑墨壓在淺玻璃上 | 白字直接壓照片 | **墨色隨桌布亮度自動翻**（見 §3） |
| 兩張卡＋虛線 ribbon＋週曆 | 六條一模一樣的圓角橫列 | 雙卡（天氣／日期）＋ribbon＋週曆卡＋裸列 |
| 單色象形圖，顏色只有 2 個 | 每列一顆彩色方磚（天氣／CPU／RAM／網路／計時器按鈕） | 單色 SF Symbol；顏色只剩溫度藍與今日／計時中珊瑚紅 |
| 一行 micro-caps 事件 | 「SEP 20」小磚 ＋ 事件標題 | 整週日曆＋今日紅圈＋`明天, 16:00 · 標題` |

## 2. 現在的面板長什麼樣（XL 直式 349.67 × 565.67 pt）

```
時鐘 thin 64 ＋ 齒輪                     header 76
┌ 日期卡 ───────┐ ┌ 天氣卡 ────────┐     cards  150
│ SEPTEMBER     │ │ TAIPEI         │
│      21       │ │  ☀（單色）      │ ← 日期珊瑚紅 thin
│   Monday      │ │  33°（藍 thin） │
└───────────────┘ │  Clear         │
                  │  H 35° L 26°   │
                  └────────────────┘
🚶 3264 步數 ········ 3.9 km 距離  ◎三環      ribbon 38
┌ 週曆卡 ──────────────────────────┐        week  88
│ 週日 週一 週二 週三 週四 週五 週六 │
│ ⑳  21  22  23  24  25  26        │ ← 今日珊瑚紅圓
│ • 明天, 00:58 · MORNING MEETING   │
└──────────────────────────────────┘
▶ ✕                計時器  5:00          timer 40
[音樂][訊息][地圖][相機][備忘錄]          launch 62（磚沿用 ictool，未改）
CPU 16% │ RAM 128G │ 10.3T 可用 │ 有線     system 36
```

（09-21 Micky 微調：標頭那行日期拿掉——週曆卡本來就帶日期；日期卡與天氣卡左右對調。）

所有列高／字級集中在 `Metrics`（`.xl` 與 `.large` 兩組），compact（systemLarge）自動縮一號並隱藏 ribbon／計時器／系統列。

## 3. 墨色自動適配（這是「超越」的那一塊）

參考圖的黑墨淺玻璃只在**亮桌布**成立。所以 v2 量桌布裁切圖的平均亮度：

- `UIImage.averageLuminance`（畫進 1×1 bitmap，Rec.709）→ provider 每次 timeline 量一次，app 在 `recrop()` 量一次並快取
- `PanelData.effectiveLuma = luma × (1 − tint)`，`> 0.46` → 淺玻璃黑墨，否則深玻璃白墨
- `config.panelScheme`：`auto`／`light`／`dark`，設定頁「面板色調」可鎖
- 🔴 `.regular` 玻璃是跟 **colorScheme** 走的，不是跟我們的墨色走——所以 `PanelView` 會 `.environment(\.colorScheme, ink.light ? .light : .dark)`。
  少了這行，暗桌布上的卡片會變成灰色塑膠板（實拍證據：`after3-dark` vs `after4-dark`）。

整個設計系統集中在 `struct PanelInk`（primary／secondary／tertiary／hairline／dots／blue／coral／sheetFill／cardTint／cardStroke／halo），
改風格只動這一個 struct。

## 4. 一併做掉的兩件小事（跟原任務分開標）

1. **距離**：`ActivitySnapshot.distanceMeters` ＋ HealthKit `distanceWalkingRunning` 查詢，ribbon 上照語系出 `3.9 km`／`2.4 mi`
   （參考圖上那個 `2.4 mi`）。`ActivitySnapshot` 因此補了手寫 `init(from:)`——不補的話舊的 snapshot JSON 會整包解不開，
   使用者升級後 ribbon 會變「—」。Check 補了兩條守這個。
2. **字型遷移**：`designVersion` ＝ 2；舊 config 若還停在 `rounded`，`PanelConfig.load()` 一次性改成 `default` 並存回。
   使用者仍可在設定頁改回去。

## 5. 自驗到什麼程度

| 項目 | 結果 | 怎麼跑 |
|---|---|---|
| build（app＋widget extension） | 綠 | `xcodebuild -scheme UTUVOPanel -destination "…id=363878E7-…" build` |
| 邏輯自檢 48 條 | 全綠 | `swiftc -O Shared/Logic.swift Check/main.swift -o /tmp/c && /tmp/c` |
| 淺桌布（luma 0.541） | 黑墨淺玻璃，實拍 | 證據 `docs/evidence-2026-09-21/` |
| 深桌布 | 白墨深玻璃，實拍 | 同上 |
| 明暗混合桌布 | 自動判深玻璃，底部系統列仍可讀 | 同上 |
| 繁中 ＋ 英文 | 都實拍過 | `simctl launch … -AppleLanguages '(zh-Hant)'` |
| accented（Clear 圖示樣式） | 實拍過，元素齊、全白墨 | 暫時把 preview 改 `inWidget: true` ＋ `.environment(\.widgetRenderingMode, .accented)`，拍完還原 |
| systemLarge（compact） | 實拍過，329×345 pt 無裁切 | 同上手法，`d.compact = true` ＋ `.frame(329×345)`（iOS 27 最小機型的 systemLarge） |
| SpringBoard UI 測試 **12 條** | 每一條產品斷言都實測綠；會紅的兩條是環境（見下） | `xcodebuild … test` |
| 真小工具（不是 app 預覽） | 實拍：證據 09（桌面）、10（計時中 4:58 珊瑚紅） | test4／test5 的 attachment |

**這套 UI 測試不是冪等的，也不是自給自足的**（09-21 五次實測，同一份程式碼）。`test2_addWidget` **每跑一次就多放一個小工具**，
而 XCTest 照字母序跑，`test11` 排在 `test2` 前面：

| 模擬器狀態 | 通過 | 紅的是誰 · 為什麼 |
|---|---|---|
| 英文、桌面上剛好一個小工具且還有空白頁 | **12/12** | — |
| 英文、我又多加了兩個小工具 | 10/12 | `test3`（見下）、`test7a` 找不到空白頁 |
| `simctl erase` 後（**語言變成繁中**） | 6/12 | `test2` 找 `buttons["Edit"]`，SpringBoard 在繁中叫「編輯」→ 小工具加不上去，後面全倒 |
| erase 後改回英文、第一輪 | 10/12 | `test11` 此時桌面還沒有小工具（字母序在 test2 之前）、`test3` |
| 同上、第二輪 | 10/12 | `test3`、`test7a`（第二輪又多一個小工具，沒有空白頁了） |

**所以「一輪全綠」需要桌面剛好是：一個 UTUVO Panel 小工具 ＋ 還有一頁空白。**
跨這五輪，**每一條產品斷言都至少綠過一次，而且沒有任何一條是因為產品理由紅的**：
真小工具畫面（test4）、計時器 intent（test5）、直開 Maps 且本 app 不進前景（test6）、日曆列開行事曆（test11）、
設定頁 Done（test10）、桌面 icon（test8）、選桌布（test1／test7b）全部實測綠。

兩條會紅的是環境，不是產品：
- `test3_locateWidget` **完全沒有斷言**（只翻四頁、印出找到的元素、拍照）。它紅的時候是 XCUITest 在翻頁動畫中查詢丟錯。
- `test7a_emptyPageScreenshot` 需要一頁空白，桌面被小工具塞滿就紅。

**這不是「erase 之後長按壞掉」**（我一開始誤判成這樣），語言那條是**測試把 SpringBoard 的英文標籤寫死**，
已把 `Edit`／`Add Widget`／`Edit Home Screen` 三個查詢改成中英通吃（同一台繁中 sim 上 test2 就過了）。裝置語言在
`~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Library/Preferences/.GlobalPreferences.plist`
（`plutil -replace AppleLanguages -json '["en-US"]'` 再重開機）。

看逐條結果用 `xcrun xcresulttool get test-results tests --path <xcresult> --format json`
（⚠️ `Executed 12 tests, with N failures` 那行的 N 是**斷言數**不是失敗條數：6 條失敗會印成 10 failures）。

**順手修好的兩條測試**（跟原任務分開標）：`test1_pickScreenshot`／`test7b_pickNewest` 在這台（英文）sim 上本來就紅——
①Form 是 lazy 的，「移除背景」那列在面板預覽下方、沒捲到就不在 accessibility tree 裡 → 斷言前加 `swipeUp()`；
②`test7b` 把 `移除背景` 寫死成中文，英文 sim 必紅 → 改成跟 `test1` 一樣吃兩種語言。
修之前那一輪的 attachment 證明產品本身沒壞（背景有存進去、按鈕已變「Change wallpaper」）。

**🔴🔴 卡片不能靠 `glassEffect` 上色**（量出來的）：在**真小工具**裡 `glassEffect` 會用它自己那層近乎全透明的材質蓋過底下的填色，
所以 tint 跟 fill 都不見。量測（同一張淺桌布、同一個位置取樣）：
| 畫法 | 卡片內 vs 面板底 的亮度差 |
|---|---|
| 只有 `glassEffect(.regular.tint(...))`（原本） | **2.6** ← 等於沒有卡片 |
| 自己畫（fill ＋ 左上高光 ＋ 髮絲邊） | **37.9** ← 參考圖的卡中卡層級 |
app 預覽看起來一直是對的（那邊 glassEffect 有作用），**只有真小工具是錯的**——這就是「驗的是自己布置好的世界」。
證據 12（上下對照）、13（現行真小工具）。這條跟家族 icon 那條「`glassEffect(.tint)` 在 WidgetKit 內被洗白」是同一個底。

**🔴🔴 驗證陷阱（這一輪踩到）**：桌面上**已放好的小工具不會載入新的 extension binary**。改完 `PanelView` 只跑
`-only-testing:…test4_showWidget`（會重裝 app）拍到的還是舊 binary 畫的畫面——時鐘與桌布裁切會更新，所以很像「有在換」。
抓法：把 `cardFill` 改成紅色 0.85 當 mutation probe，卡片沒變紅就是沒換。正解：`simctl uninstall` → 重跑
`test2_addWidget` 重新放一次小工具，才算驗到新程式碼。

**繁中抓到的真 bug（已修）**：`Text(date, format: .dateTime.day())` 在 zh_TW 會輸出「20日」——日期卡的「日」變得跟數字一樣大，
週曆七格全被擠成 `2…`。改成 `String(Calendar.current.component(.day, from:))`。

**順手記一筆**：`Tiles.xcassets` 的 `btn-play/pause/stop/gear` 四顆圓形玻璃鈕 v2 沒有再用（改成 hairline 圓環鈕），
資產留著沒刪——要換回玻璃鈕只要把 `RingButton` 換回 `Image(name)` 就好。

## 6. 卡 Micky（只有他能做）

1. **真機目視**：模擬器拿不到未模糊的桌布原檔，透明對齊與玻璃質感最後還是要在 17 Pro Max 上看。
2. **要不要重送審**：build 4 還在 WAITING_FOR_REVIEW。三條路——
   (a) 等審完再出 1.0.1；(b) 撤回送審、bump build 重送（會重新排隊）；(c) 先不動，等他真機看過再決定。
   **沒有他點頭不准動 ASC。**
3. icon 顏色（沿用 09-20 handoff 的未決事項）。

## 7. 信心最低清單（誠實條款）

- **Clear／tinted 桌面（accented 模式）**：結構跟 v1 相同（白墨、只留 rim、磚退回 symbol slab），但**沒有在 sim 上目視過**。
- **真機 HealthKit 距離**：sim 恆為 0，距離的格式化只在程式碼層驗過，沒跟健康 app 對過數字。
- **極端桌布**：只測了三張合成漸層與一張深色。使用者拿高飽和照片當桌布時，`0.46` 這個門檻是估的，沒有大樣本。
- **CJK micro-caps**：8.5 pt 的「可用空間」「連線」在 sim 上可讀，但沒在真機上看過。
