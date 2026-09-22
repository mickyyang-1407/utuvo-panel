# 0004 — 小工具自己讀健康資料（不用打開 app 步數也會更新）

- 票型：standard ｜ writer：ccm3（MiniMax）｜ reviewer：agy（Gemini）
- 分支／worktree：`v1.0.1-transparent` ／ `~/Projects/utuvo-panel-v101`

## 為什麼

Micky：「那個健康要如何可以即時同步？目前好像都不能同步」。查證：
- 只有 app 的 `PanelModel.refreshHealth()` 讀 HealthKit（`UTUVOPanel/App/PanelModel.swift` L278 起），只在打開 app 時跑。
- 小工具只讀 app 存下的快取 `Shared.Key.activity`（`PanelWidget/PanelWidget.swift` L45），而且小工具 extension **沒有 HealthKit entitlement**。
- 另一個 bug：`refreshHealth()` 以 `activity ?? ActivitySnapshot()` 為底、先蓋上 `snap.day = Date()`，某項查詢失敗時就把**昨天的數字存成今天的**。
- SDK 已查：HealthKit 查詢在 app extension 可用（只有 `handleAuthorizationForExtension` 標 extension unavailable）。授權由 app 請求，extension 共用。

## 這張票只做一件事

讓小工具每次建 timeline 時自己讀今天的健康資料；讀不到（手機鎖著、沒授權）就用今天的快取，快取不是今天的就顯示 0，**永遠不把昨天的數字當今天**。app 與小工具共用同一份讀取程式。

## 具體步驟

1. **`ios/project.yml`**：`PanelWidget` target 的 `entitlements.properties` 加 `com.apple.developer.healthkit: true`（跟 app target L27 一樣）。跑 `xcodegen generate` 會重寫 `PanelWidget/PanelWidget.entitlements`。
2. **新檔 `ios/Shared/HealthReader.swift`**（Shared 資料夾兩個 target 都會編；**不要放進 Logic.swift**，Logic 必須維持純 Foundation）：
   ```swift
   import HealthKit
   enum HealthReader {
       static let readTypes: Set<HKObjectType>   // 現在 PanelModel.requestHealth() 那六個
       /// Today's activity, read fresh. nil = could not read (HealthKit unavailable, or the store is
       /// inaccessible because the device is locked) — callers keep what they had.
       static func today(store: HKHealthStore = HKHealthStore(), now: Date = Date()) async -> ActivitySnapshot?
   }
   ```
   - 從**全新的** `ActivitySnapshot()` 開始、`day = now`，不繼承任何舊值。
   - 步數、距離：`HKStatisticsQuery` cumulativeSum（同現有寫法）。錯誤碼是 `HKError.Code.errorNoData` → 當 0；**其他任何錯誤 → 整個函式回 nil**。
   - 圓環：`HKActivitySummaryQuery`（同現有寫法）。沒有 summary → 值 0、目標用預設；錯誤（非 noData）→ 回 nil。
   - `HKHealthStore.isHealthDataAvailable() == false` → 回 nil。
3. **`ios/Shared/Logic.swift`**：加純函式（Check 要測）
   ```swift
   extension ActivitySnapshot {
       /// What the panel shows: a fresh read wins; otherwise today's cache; otherwise an empty snapshot for today.
       static func resolve(fresh: ActivitySnapshot?, cached: ActivitySnapshot?, now: Date, calendar: Calendar = .current) -> ActivitySnapshot
   }
   ```
   「今天」用 `calendar.isDate(cached.day, inSameDayAs: now)`。空的那份 `day = now`。
4. **`ios/PanelWidget/PanelWidget.swift`** `build(...)`：取代 L45 那行——
   `let cached = Shared.defaults.codable(ActivitySnapshot.self, forKey: Shared.Key.activity)`；
   `let fresh = config.showActivity ? await HealthReader.today(now: now) : nil`；
   `fresh` 非 nil → `Shared.defaults.set(codable: fresh, forKey: Shared.Key.activity)`；
   `let activity = ActivitySnapshot.resolve(fresh: fresh, cached: cached, now: now)`。其餘不動（timeline 策略維持 15 分鐘）。
5. **`ios/UTUVOPanel/App/PanelModel.swift`**：`requestHealth()` 改用 `HealthReader.readTypes`；`refreshHealth()` 整個改成呼叫 `HealthReader.today()` ＋ 上面同一套存檔／`resolve` 邏輯，最後 `refreshStatuses()`、`reloadWidget()`。刪掉三段重複的 query 程式（**單一正本**）。
6. **`ios/Check/main.swift`**：`resolve` 至少 4 條——有 fresh 用 fresh／沒 fresh＋今天快取用快取／沒 fresh＋昨天快取回 0 且 day 是今天／兩個都沒有回 0。

## 不准做

- 不准改 `PanelView.swift`、`Intents.swift`、`SetupGuide.swift`、`RootView.swift` 的畫面。
- 不准改版號、kind、bundle id、app target 的 entitlements、`tools/`、`docs/`、App Store。
- 不准加寫入健康資料的權限（`toShare` 維持空集合）。
- 模擬器只准用 `363878E7-E1F6-4F64-9D13-91F4C3E67BD2`；不准 erase。
- git 只准跑唯讀指令（status / diff / log / show）。其餘一律禁止——包含但不限於 add / commit / push / reset / checkout / switch / stash / clean / restore / rebase / merge / cherry-pick / tag / worktree。需要動 git 就停下來回報。

## 完成標準（全部要跑、貼輸出）

```bash
cd ~/Projects/utuvo-panel-v101/ios && xcodegen generate
swiftc -O Shared/Logic.swift Check/main.swift -o /tmp/c-v101 && /tmp/c-v101
xcodebuild -project UTUVOPanel.xcodeproj -scheme UTUVOPanel \
  -destination "platform=iOS Simulator,id=363878E7-E1F6-4F64-9D13-91F4C3E67BD2" \
  -derivedDataPath ../DerivedData build
plutil -p PanelWidget/PanelWidget.entitlements
```

回報：改了哪些檔、輸出最後幾行、沒照工單做的地方與理由（說 API 限制要附編譯錯誤原文）。**不用跑 UI 測試**，實測由 orchestrator 做。

---

## 驗收紀錄（orchestrator，2026-09-21）

- **writer**：ccm3（MiniMax）。範圍 7 檔＋新檔 `Shared/HealthReader.swift`；受保護的 PanelView／Intents／SetupGuide／RootView／app entitlements hash 未變。
- **deterministic gate**：Check 全綠（resolve 7 條）、`BUILD SUCCEEDED`、widget entitlements 含 `com.apple.developer.healthkit`。
- **突變**：把 resolve 改成「有快取就用」→ Check 4 條 FAIL、exit 1；原版 exit 0。
- **模擬器實測（真實入口）**：健康 app 加 4,321 步 → app 讀到 4,321 → 關掉 app → 健康 app 再加 1,000（共 5,321）→ **不開 app**，按小工具 ▶（TimerToggleIntent reload）→ 小工具從 4,321 變 5,321。證據 `docs/evidence-1.0.1/0004-health-*.png`。
- **異家族 review**：AGY（Gemini）9 項全 PASS，`VERDICT: PASS`；前後 checksum 一致（`abeacf2a…`）。
- **已知限制（非缺陷）**：iOS 決定小工具多久重建一次 timeline（約 15 分鐘預算制），所以不是「秒級」即時；手機鎖著時健康資料庫加密讀不到 → 沿用今天的快取。
- **結論**：CLOSE。
