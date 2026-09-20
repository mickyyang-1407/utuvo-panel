# Micky Handoff Document — UTUVO Panel

> 版本：v1 ｜ 更新時間：2026-09-20 ｜ 上一棒：Claude Code（Fable 5.1 → Opus 5）｜ 下一棒：任何 AI 或 Micky
> 狀態：**1.0 (build 4) 送審中（WAITING_FOR_REVIEW，已排隊 2 天）。程式面沒有未完成的工作，卡的是 Apple 與 Micky 的目視。**
> 前段逐輪流水帳在 `docs/HANDOFF-2026-09-16-utuvo-panel.md`（24 輪，含所有踩坑）。本檔是接手點，只寫現況與怎麼繼續。

---

## 1. 我是誰（固定，不要改這區）

- **姓名：** Micky Yang（楊敏奇），52 歲
- **職業：** Tonmeister、錄音製作人、Dolby Atmos 混音工程師
- **職位：** DAMI music 音樂總監、德國 msm-production 製作人、台藝大／北藝大教授

### 本地環境
| 服務 | 網址 | 用途 |
|---|---|---|
| n8n | localhost:5678 | Workflow 自動化 |
| Open WebUI | localhost:8081 | Chat UI / RAG |
| Ollama | localhost:11434 | 本地 LLM 推論 |
| ComfyUI | localhost:8188 | 圖像生成 |
| 主機 | Mac Studio M3 Ultra | 512 GB RAM / 16 TB SSD |

### AI 回答規則
- 繁體中文、條列式；程式碼直接給、不解釋基礎；音訊術語保留英文
- 不重複解釋已完成的部分；「記錄進度」＝立刻寫 project memory ＋ STATUS.md
- 自驗優先：能自己測的自己測完，只有品味／聽感／實機／帳號才叫 Micky

---

## 2. 這個任務是什麼

**UTUVO Panel** — iOS 27 桌面小工具，用 iOS 27 新增的特大直式尺寸（`systemExtraLargePortrait`，實測 349.67 × 565.67 pt）。
起點是 Micky 丟一張小紅書的 Koco Widgets 截圖說「我們也做一個吧」（09-16），做成獨立產品並上架。

面板內容：時鐘（可走秒）／下一筆行事曆／天氣（Open-Meteo）／活動三環（HealthKit）／計時器（AppIntent 真按鈕）／
五個 app 捷徑／系統資訊四格（11 項可選）。點磚與點列都**直接開目標 app**。

**完成定義**：App Store 上架、公開 repo、視覺達到 Apple 自家 icon 的水準。前兩項已做到送審與已開源，第三項 Micky 09-18 已認可。

---

## 3. 目前進度

| 項目 | 狀態 | 證據 |
|---|---|---|
| App Store 1.0 (build 4) | **WAITING_FOR_REVIEW**（09-18 03:29 UTC 送出，submission `21f29296`） | ASC API |
| ASC 後台欄位 | 全填完（兩語文案／截圖／類別／年齡／免費／175 地區／審核備註） | 第十八輪 |
| App Privacy 問卷 | Micky 網頁已 Publish（Coarse Location／App Functionality／不連結／不追蹤） | 第二十一輪 |
| 公開 repo | https://github.com/mickyyang-1407/utuvo-panel （MIT，credscan 全史乾淨） | 第二十二輪 |
| 真機 | iPhone 17 Pro Max（iOS 27.0）已裝與送審同版 | devicectl |
| 邏輯自檢 | `Check/main.swift` 46 條全綠 | `swiftc -O ios/Shared/Logic.swift ios/Check/main.swift -o /tmp/c && /tmp/c` |
| sim UI 測試 | 6 條全綠（面板／計時器／直開 Maps 且本 app 不進前景／日曆列開行事曆／設定頁 Done／桌面 icon） | `ios/UITests/WidgetFlowTests.swift` |
| 家族 icon | **另一條 session 已用本專案工具換完 14 顆**（09-18，備份 `utuvo-brand/icons/_backup-2026-09-18`） | 非本線產出 |

**卡住的三件**（只有 Micky 能做）：
1. Apple 審核結果（信箱 mickymaster@me.com）
2. 真機上目視透明背景對齊（模擬器拿不到未模糊的桌布原檔，只有真機能看）
3. App icon 顏色最終拍板（現在是 Mail 藍；白／深藍／靛三個候選仍在 scratchpad）

---

## 4. 重要決定與結論（防止下一棒推翻）

- **WidgetKit 沒有真透明**：`containerBackground` 給 `.clear` 或 1% alpha，系統都墊不透明底（實測兩張證據）。
  iScreen 也是截圖法。全彩桌面的「透明」＝使用者選桌布原圖，app 依螢幕尺寸 aspect-fill 後裁面板那塊。
- **面板頂邊 y = 88 pt**（面板當某頁第一個項目時），首次選圖自動對到這裡，再用 `AlignView` 拖曳微調。
- **磚與列直接開別的 app**：iOS 18+ `Button(intent:)` 的 `perform()` 回傳 `.result(opensIntent: OpenURLIntent(url))`。
  「小工具只能開自己的 app」是 iOS 17 以前的舊知識，**不要再改回中轉**。test6 有「本 app 不進前景」的斷言。
- **Messages 只能用 `ichat://`**：iOS 26 起 `sms:`／`messages://`／`imessage://` 全部開「新訊息」（sim 四 scheme 實測）。
- **app 沒有首頁**：開 app 就是設定頁，Done＝套用＋toast。iOS 不允許 app 自己退回桌面，別再嘗試。
- **所有 icon 由 Apple 的 `ictool` 渲染**，參數對 Apple macOS 27 自家 icon 校準（見 §5 工具）。
  **不要用 AI 生圖補 icon**——Micky 09-18 明確否決那批「廉價的發光」磚。
- 家族 mark 在 icon 裡一律 **scale 1.15**（跟所有 UTUVO .icon 同高）；磚內字形另用 1.152 補畫布內縮。
- 版號 1.0；iPhone-only；`ITSAppUsesNonExemptEncryption=false`；隱私清單在 `ios/Shared/PrivacyInfo.xcprivacy`。

---

## 5. 目前產出

```
~/Projects/utuvo-panel            ← public repo，main 與 origin 同步
  ios/Shared/                     Logic.swift（純 Foundation，Check 也編它）、PanelView、Intents、SystemStats、
                                  Localizable.xcstrings（zh-Hant 正、en 全翻）、Tiles.xcassets（54 顆 icon）
  ios/PanelWidget/                WidgetKit provider（每分鐘一 entry ×30、天氣 30 分快取、15 分一輪）
  ios/UTUVOPanel/                 app＝設定頁；Resources/UTUVOPanel.icon（Icon Composer 包）
  ios/UITests/WidgetFlowTests.swift  驅動 SpringBoard：加小工具、點磚、計時器、Done
  ios/Check/main.swift            46 條純邏輯自檢
  tools/make-tiles.py             ← 54 顆 icon 的正本產生器（改磚只動這裡，再跑一次）
  tools/symbol2png.swift          SF Symbol →（可指定 palette 層）白色 1024 圖層
  tools/liquid-icon.py            家族 icon 產生器：mark ＋ 產品色 → .icon
  tools/slice-tiles.py            切 AI 生圖用（目前沒用到，留著）
  tools/asc.py / resubmit.py      App Store Connect API（ES256 JWT，key 走環境變數）
  docs/HANDOFF-2026-09-16-…md     24 輪流水帳＋所有踩坑
  docs/AppStore/1.0-metadata.md   上架文案正本
  docs/evidence-2026-09-16/       43 張證據截圖
~/Desktop/utuvo builds/UTUVO-Panel-1.0-4/   送審用 IPA（SHA 在 SHA256SUMS）
```

**環境／識別**
- ASC app：UTUVO Panel，Apple ID `6812964840`，version `cf1e60dc-8f70-4775-9f80-ddbf01ba5966`
- ASC API：`export ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_<id>.p8`
  （值在 `~/Projects/pik-player-mobile/HANDOFF-2026-08-22-GO-SUBMISSION-READY.md` §48；**不准寫進 repo**）
- 簽章 team `RPNT54P79S`；真機 `00008150-000C71143E30401C`
- 模擬器：`GlassPanel-iOS27-iPhone-17-Pro`（`363878E7-…`）、`UTUVO-Panel-Screenshots-17-Pro-Max`（`6E56E659-…`，6.9" 截圖用）

**常用指令**
```bash
cd ~/Projects/utuvo-panel/ios && xcodegen generate            # 加檔必跑
swiftc -O Shared/Logic.swift Check/main.swift -o /tmp/c && /tmp/c
xcodebuild -project UTUVOPanel.xcodeproj -scheme UTUVOPanel \
  -destination "platform=iOS Simulator,id=363878E7-E1F6-4F64-9D13-91F4C3E67BD2" \
  -derivedDataPath ../DerivedData test
python3 ../tools/make-tiles.py [asset…]                        # 重出 icon
env PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -exportArchive …   # 🔴 不清 PATH 會吃到 Homebrew rsync 而失敗
python3 ../tools/resubmit.py <build> <截圖資料夾> widget-in-place timer-running settings-top settings-mid
```

---

## 6. 下一棒請做

1. **每天看一次審核狀態**（或等 Apple 信）：
   `python3 tools/asc.py GET /v1/appStoreVersions/cf1e60dc-8f70-4775-9f80-ddbf01ba5966`
2. **通過**：Micky 決定發布時間（目前 releaseType＝MANUAL，要手動按發布）；發布後更新官網與 MICKY-TODO。
3. **退件**：先看退件理由再動手。最可能是 **5.2.5**（五顆磚像 Apple 自家 icon）。
   備案已想好：把 music／messages／maps／camera／notes 換成抽象符號版（只改 `tools/make-tiles.py` 的 TILES 表再跑），
   bump build、`resubmit.py` 重送。**不要為了猜測先改**。
4. **Micky 真機目視透明對齊**後如果說不準，調的是 `PanelPlacement.defaultTop`（現 0.1007 × 螢幕高）或請他用 AlignView 拖。
5. icon 顏色若要換：改 `ios/UTUVOPanel/Resources/UTUVOPanel.icon/icon.json` 的兩個色值（或用 `tools/liquid-icon.py` 重產），
   bump build 重送。

---

## 7. 禁止事項

- 不准用 AI 生圖做 icon／磚；一律 `tools/make-tiles.py`＋ictool。
- 不准把 ASC key id／issuer／.p8、Apple 官方 icon 圖檔 commit 進這個 public repo。推之前一定跑
  `python3 ~/Projects/micky-avatar/tools/credscan.py --range origin/main..HEAD`，綠了才推。
- 不准 `git add -A` 之後不看 status（09-18 差點把 `DerivedData-max/` 3300 個檔掃進 commit，被 credscan 擋下）。
- 不准在沒有 Micky 同意下發布（release）已核准的版本，或改 App Store 價格／地區。
- 不准把「小工具只能開自己的 app」「透明可以靠 .clear」這兩個已被實測推翻的說法寫回程式或文件。

---

## 8. 錯誤紀錄（這一輪踩過、已修）

| 坑 | 症狀 | 結論 |
|---|---|---|
| Icon Composer 畫布內縮 | 字形永遠比 Apple 小 15% | 圖層 scale **1.152**（磚）／1.15（家族 mark） |
| ictool 輸出 Display P3 | 顏色怎麼調都對不上 Apple | 量測前用 ICC 轉 sRGB |
| xcodegen target 設定 | IPA `UIDeviceFamily` 變 1,2 → 被要求 iPad 截圖 | `TARGETED_DEVICE_FAMILY` 要寫在**每個 target** |
| xcodegen `info:` | `CFBundleVersion` 寫死 "1"，上傳被判重複 | 明寫 `$(CURRENT_PROJECT_VERSION)` |
| exportArchive | "Copy failed" | 吃到 Homebrew rsync 3.5；清 PATH |
| ASC builds 端點 | 新 build 查不到 | 用 `/v1/builds?filter[app]=…` 不要用 `apps/{id}/builds` |
| 送審中鎖定 | 換 build／截圖回 409 | 只能撤回送審再換（`resubmit.py`） |
| SF 多層符號 | 翻譯的字、碼錶指針不見 | palette 層分開上色（`symbol2png` 的 layer 參數） |

---

## 9. 信心最低清單（誠實條款）

- **透明背景在真機的對齊**：信心低。模擬器拿不到未模糊的桌布原檔，整條路只在 sim 上驗過流程、沒驗過**視覺結果**。
  下一棒請 Micky 在真機做一次：選桌布原圖 → 加小工具 → 看邊緣，不齊就用 AlignView 拖。
- **5.2.5 審核風險**：信心中低。五顆磚刻意做成 Apple 語彙（那是 Micky 要的質感），有被判「與 Apple 產品混淆」的可能。
  沒有任何方式能預先確認，只能等退件理由。
- **HealthKit 活動數字**：信心中。模擬器恆為 0，只在真機安裝過、沒有逐項核對過步數／運動／站立與健康 app 是否一致。
- **天氣列真機點擊**：信心中。`weather://` 只在真機能驗（模擬器沒有天氣 app），日曆列已用 test11 驗過同一條路徑。
- **系統列讀數**：信心中。CPU／RAM 演算法有對照活動監視器口徑寫，但沒有跟真機的實際數字逐項比對過。
- **本地化覆蓋**：信心中高。78 條字串有英文，sim 切英文實拍過面板與設定頁；其他語言會退回繁中，沒有測過。
