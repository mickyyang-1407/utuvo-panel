# UTUVO Panel — Handoff 2026-09-25（1.0.1 已上架）

> 上一棒：Claude Code（Opus 5.5）｜下一棒：新 Claude Code session
> 先讀：本檔 → project memory `utuvo-panel-ios27-xl-portrait-widget-line.md`（最上面「現況」段）→ 需要時再看 `tickets/0001–0010`

## 1. 現況（一句話）

**1.0 (5) 與 1.0.1 (6) 都在 App Store 上架（READY_FOR_SALE）**，程式碼已開源。卡 Micky 的只剩「發文」（他親手，素材在桌面）。

| 項目 | 值 |
|---|---|
| App Store | https://apps.apple.com/app/utuvo-panel/id6812964840（ASC app id `6812964840`） |
| 1.0.1 送審 | submission `e8aafbf0-7514-41aa-bf4f-c1c889e2936e`、Delivery `c817d944`、09-24 過審、Micky 親手發布 |
| IPA | `~/Desktop/utuvo builds/UTUVO-Panel-1.0.1-6/export/UTUVOPanel.ipa`（SHA `8442d04c…`，已入 SHA256SUMS） |
| public repo | `github.com/mickyyang-1407/utuvo-panel` main `faf73f4` |
| 開發正本 | 本機 `~/Projects/utuvo-panel-v101`，branch `v1.0.1-transparent`（逐票歷史，**沒推**），HEAD `ac7428e` |
| 主工作樹 | `~/Projects/utuvo-panel`（= public main，晨報腳本讀這裡的 `tools/review-status.py`） |
| 發文素材 | `~/Desktop/UTUVO Panel 1.0.1 發文素材/`（7 圖＋`文案.md`，已改成「已上架」） |

## 2. 1.0.1 做了什麼（工單都 CLOSE）

| 票 | 內容 | commit（v101） |
|---|---|---|
| 0001–0003 | 編輯小工具選背景／位置、淺深兩張桌布、三步驟引導（後被 0007 精簡） | `526e737` `11e1645` `f674aed` |
| 0004 | 小工具自己讀 HealthKit，不開 app 步數也更新；昨天數字不當今天 | `6a00c6b` |
| **0005** | **一般桌面真透明**：WidgetKit SPI `preferredBackgroundStyle(.transparent)` | `9fca10b` |
| 0006／0008 | 邊框 6 樣式×6 色；app 設定頁＋編輯小工具「跟 app 設定一樣」 | `a3a78d3` `e136953` |
| 0007 | 拿掉截圖／對齊／位置 UI，引導縮一步，暗度在透明下生效 | `c141118` |
| 0009 | 走秒時鐘 00 點吃掉小時（`ClockPrefix`） | `4ec4521` |
| 0010 | 下半部三種版面（逐時天氣〔天氣卡下方〕／行程清單／平均分配），GeometryReader 依機型剩餘空間 | `262d19b` `d9284bc` |

## 3. 關鍵技術事實（別重新發明）

- **真透明**：公開 API 在一般桌面做不到（`Color.clear`＝淺色白底／深色 RGB 17,17,17，sim＋真機證據在 `docs/evidence-1.0.1/`）。`isTransparent(true)` 透明但系統疊暗紗；**`preferredBackgroundStyle(.transparent)` 無暗紗**＝iScreen 同法。已過 App Review。
  - 呼叫方式：`tools/make-widgetkit-spi.sh` 是 widget target 的 preBuildScript，複製 SDK 的 WidgetKit.framework 到 `$PROJECT_TEMP_DIR/WidgetKitSPI/$PLATFORM_NAME` 並補宣告，`FRAMEWORK_SEARCH_PATHS` 指過去。SDK 檔不進 repo。
  - 驗證要用 `dyld_info -imports`；**Release 版 `nm -u` 查不到＝假陰性**。
  - 風險：未來 iOS 拿掉符號＝extension 載入失敗（無執行期退路）。每次新 iOS beta 先查 WidgetKit.tbd 是否仍匯出 `…preferredBackgroundStyle…`。
- **簽章／上傳**：發行憑證是 Apple **雲端代管**（本機鑰匙圈沒有）→ **Xcode 必須登入 Micky 帳號**才 export 得了（09-23 已登入）。流程：archive → `env PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -exportArchive`（原 `ExportOptions-AppStore.plist`、不帶 -authenticationKey）→ `xcrun altool --upload-app --apiKey --apiIssuer`。
- **ASC 全走 API**（`tools/asc.py`，key 在 `~/.config/asc/utuvo-panel.env`）：建版本、PATCH description／whatsNew、審核備註、attach build、`reviewSubmissions` 送審。**發布永遠 Micky 親手**（releaseType MANUAL）；in-app browser 的 ASC 登入會過期，要他重登。
- **晨報**：`~/Scripts/panel-review-status.sh` → `tools/review-status.py`（跟最新版本走；已上架／未送出 exit 2 靜音）。下個版本建好會自動回報。
- **開源推送**：v101 與 public main 歷史不同（public 是 squash）。hook 禁改寫歷史 → 用 `git commit-tree HEAD^{tree} -p origin/main -m …` 疊一個 commit 到 `release/1.0.1-oss` 再 push `:main`。推前：`credscan.py --range origin/main..NEW`＋**真機截圖一律人工看**（09-22 抓到週曆有家人行程）。
- **模擬器**：驗證用 `UTUVO-Panel-Screenshots-17-Pro-Max`（`6E56E659-…`，XL 面板剩餘空間才夠）與 `GlassPanel-iOS27-iPhone-17-Pro`（`363878E7-…`）。xcodebuild test 用 `build-for-testing`＋`test-without-building`；**測試依名稱排序執行**（test13 先於 test2）；sim 桌面閒置會暫停小工具即時文字（不是 bug）；sim HealthKit 授權 sheet 被測試關掉後不會再跳。
- 真機 17PMX `00008150-000C71143E30401C`，`devicectl device install app`；**不准自動截真機畫面**（會拍到私人畫面）。

## 4. 未完成／建議下一步（按價值排序）

1. **Micky 親手**：發文（FB／IG／Threads／英文），素材與文案已備好。
2. **App Store 截圖還是 1.0 的 4 張**（沒有真透明／邊框）。下次送版時換成 1.0.1 畫面（6.9" 1320×2868，Pro Max sim；zh-Hant 要中文介面另拍）。
3. **死碼清理**（0007 只斷入口）：`AlignView.swift`、`PanelPlacement`、`PanelSlotChoice/Kind`、截圖／裁切／深色桌布相關程式與 `Shared.screenshotURL` 等。清完要跑 Check＋UI 回歸。
4. `test2_addWidget` 不冪等（每跑一次多一個面板）、`test3` 沒斷言——修測試。
5. 中國大陸無 ICP 備案（175 區清單含中國大陸）——是否從供應地區移除是 Micky 決定。
6. `~/Desktop/utuvo builds/UTUVO-Panel-1.0-4/` 舊版可清（build-folder 規則：只留最新）。
7. v101 的 `docs/AppStore/1.0.1-metadata.md` 只在本機；要同步到 public 用第 3 節的 commit-tree 流程。

## 5. 禁區

- 不准 erase 模擬器；不准 AI 生圖做 icon（用 `tools/make-tiles.py`＋ictool）；憑證不進 repo；App Store 發布／花錢／對外發文＝Micky 親手。
- writer 派工 git 白名單（只准唯讀）；reviewer 前後 checksum。

## 6. 信心最低的地方

- SPI 在 iOS 27.x 小版本更新後是否仍有效——沒有自動監測，只能每次新 iOS 手動查。
- 真機上三種下半部版面只有 Micky 目視過 hourly；agenda（多筆行程）在真機未驗。

## 7. 09-25 午後更新（1.0.2）

- **1.0.2 (7) 已送審**（submission `26e67ee2`，MANUAL）：修「首次安裝小工具停在骨架」（ticket 0011）。送審稿 `docs/AppStore/1.0.2-metadata.md`。17PMX 已裝同版。
- §4 第 3 項死碼清理＝ticket 0012 CLOSED；第 4 項測試＝test2 冪等、test3 斷言、中英 predicate；第 6 項 builds 夾＝1.0-4／1.0-5 移垃圾桶（1.0.1-6 等 1.0.2 上架後清）；第 2 項截圖＝`docs/AppStore/screenshots-1.0.2/{en-US,zh-Hant}/`（未上傳）；第 7 項 metadata 已隨 public 同步。
- public main `44c642b`＝本分支 tree。
- 仍卡 Micky：1.0.2 過審後發布；截圖品味（系統列 Mac 數字、繁中截圖英文城市名）；中國大陸 ICP。
