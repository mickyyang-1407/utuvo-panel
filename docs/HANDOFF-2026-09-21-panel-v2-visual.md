# UTUVO Panel — 面板視覺 v2（editorial glass）

> 版本：v1 ｜ 建立：2026-09-21 ｜ 上一棒：Claude Code（Opus 5）｜ 下一棒：任何 AI 或 Micky
> 這是**現行接手點**。產品／上架／環境／禁區看 `HANDOFF-2026-09-20-utuvo-panel.md`（仍然有效，只有「面板長相」那部分被本檔取代）。
> 狀態：程式面已完成並自驗；**卡 Micky 兩件**：真機目視、以及要不要為了這版改動重送審。

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
時鐘 thin 64 ＋ 齒輪                     header 90
SUNDAY, SEP 20（micro-caps）
┌ 天氣卡 ────────┐ ┌ 日期卡 ───────┐     cards  140
│ TAIPEI         │ │ SEPTEMBER     │
│  ☀（單色）      │ │      20       │ ← 珊瑚紅 thin
│  33°（藍 thin） │ │   Sunday      │ ← bold
│  Clear         │ └───────────────┘
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
| SpringBoard UI 測試 **12 條** | 全綠（含真小工具在桌面、計時器 intent、直開 Maps） | `xcodebuild … test` |
| 真小工具（不是 app 預覽） | 實拍：證據 09（桌面）、10（計時中 4:58 珊瑚紅） | test4／test5 的 attachment |

**順手修好的兩條測試**（跟原任務分開標）：`test1_pickScreenshot`／`test7b_pickNewest` 在這台（英文）sim 上本來就紅——
①Form 是 lazy 的，「移除背景」那列在面板預覽下方、沒捲到就不在 accessibility tree 裡 → 斷言前加 `swipeUp()`；
②`test7b` 把 `移除背景` 寫死成中文，英文 sim 必紅 → 改成跟 `test1` 一樣吃兩種語言。
修之前那一輪的 attachment 證明產品本身沒壞（背景有存進去、按鈕已變「Change wallpaper」）。

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
