// Check/main.swift — compiled with Shared/Logic.swift only (no UIKit), run on the Mac:
//   swiftc -O Shared/Logic.swift Check/main.swift -o /tmp/glasspanel-check && /tmp/glasspanel-check
// Every assertion has a known-bad input somewhere below; a check that can never go red is not a check.

import Foundation

var failures = 0
func check(_ cond: Bool, _ msg: String, file: String = #file, line: Int = #line) {
    if !cond { failures += 1; print("FAIL \(line): \(msg)") }
}

// MARK: Deep links
do {
    let m = Launcher.byID("music")!
    check(m.deepLink.absoluteString == "utuvopanel://launch/music", "deep link shape")
    check(Launcher.fromDeepLink(m.deepLink)?.id == "music", "round-trip")
    check(Launcher.fromDeepLink(URL(string: "utuvopanel://launch/nope")!) == nil, "unknown id → nil")
    check(Launcher.fromDeepLink(URL(string: "https://launch/music")!) == nil, "wrong scheme → nil")
    check(Launcher.fromDeepLink(URL(string: "utuvopanel://open/music")!) == nil, "wrong host → nil")
    check(Set(Launcher.presets.map(\.id)).count == Launcher.presets.count, "preset ids unique")
    check(Launcher.presets.allSatisfy { URL(string: $0.url) != nil }, "every preset url parses")
    check(Launcher.byID("messages")?.url == "ichat://", "messages opens the conversation list (iOS 26: sms:/messages:// compose)")
    check(["calendar","weather","fitness"].allSatisfy { Launcher.byID($0) != nil }, "rows that open apps have presets")
    check(Launcher.settingsDeepLink.absoluteString == "utuvopanel://settings", "settings link")
    check(Launcher.fromDeepLink(Launcher.settingsDeepLink) == nil, "settings link is not a launcher")
}

// MARK: Weather parse + WMO table
do {
    let good = """
    {"current":{"temperature_2m":33.4,"weather_code":0,"is_day":1},
     "daily":{"temperature_2m_max":[35.1],"temperature_2m_min":[26.0]}}
    """.data(using: .utf8)!
    let w = WeatherSnapshot.parse(good)
    check(w?.temperature == 33.4 && w?.high == 35.1 && w?.low == 26.0 && w?.isDay == true, "parse fields")
    check(w?.description.text == "晴" && w?.description.symbol == "sun.max.fill", "code 0 day")
    var night = w!; night.isDay = false
    check(night.description.symbol == "moon.stars.fill", "code 0 night")
    check(WeatherSnapshot(temperature: 0, high: 0, low: 0, code: 95, isDay: true, fetched: .init()).description.text == "雷雨", "code 95")
    check(WeatherSnapshot(temperature: 0, high: 0, low: 0, code: 123, isDay: true, fetched: .init()).description.text == "—", "unknown code")
    let missingDaily = #"{"current":{"temperature_2m":1,"weather_code":0}}"#.data(using: .utf8)!
    check(WeatherSnapshot.parse(missingDaily) == nil, "missing daily → nil")
    check(WeatherSnapshot.parse(Data("garbage".utf8)) == nil, "garbage → nil")
    // every symbol the WMO table can emit has a rendered tile; unknown symbols fall back
    let symbols = Set([0,1,2,3,45,51,56,61,66,71,80,85,95,96].flatMap { c in [true,false].map { WeatherSnapshot(temperature: 0, high: 0, low: 0, code: c, isDay: $0, fetched: .init()).description.symbol } })
    check(symbols.allSatisfy { WeatherSnapshot.tileName(for: $0) != "wx-unknown" }, "all WMO symbols map to a tile: \(symbols.filter { WeatherSnapshot.tileName(for: $0) == "wx-unknown" })")
    check(WeatherSnapshot.tileName(for: "nope") == "wx-unknown", "unknown symbol → wx-unknown")
    let u = WeatherSnapshot.url(latitude: 25.033, longitude: 121.565).absoluteString
    check(u.contains("latitude=25.03&") && u.contains("longitude=121.5") && !u.contains("25.033") && u.contains("timezone=auto"), "url query is coarse (2 dp ≈ 1 km)")
    check(Launcher.byID("settings") == nil, "no App-prefs launcher (App Review)")
    check(SystemMetric.byID("uptime") == nil, "no uptime metric (boot-time API has no display reason)")
}

// MARK: Timer state machine
do {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    let idle = TimerState()
    check(idle.phase(at: t0) == .idle, "fresh is idle")
    let running = idle.toggled(at: t0, defaultMinutes: 5)
    check(running.phase(at: t0) == .running, "idle→running")
    check(running.endDate == t0.addingTimeInterval(300), "5 min end")
    check(running.phase(at: t0.addingTimeInterval(301)) == .idle, "expired counts as idle")
    let paused = running.toggled(at: t0.addingTimeInterval(120), defaultMinutes: 5)
    check(paused.phase(at: t0) == .paused, "running→paused")
    check(paused.pausedRemaining == 180, "remaining after 2 min = 180")
    let resumed = paused.toggled(at: t0.addingTimeInterval(500), defaultMinutes: 5)
    check(resumed.endDate == t0.addingTimeInterval(680), "resume keeps 180 s")
    check(TimerState().toggled(at: t0, defaultMinutes: 0).endDate == t0.addingTimeInterval(60), "0 min clamps to 1")
    check(TimerState.format(312) == "5:12" && TimerState.format(5) == "0:05" && TimerState.format(-3) == "0:00", "m:ss")
    check(TimerState.stopped.phase(at: t0) == .idle, "stopped is idle")
}

// MARK: Activity fractions
do {
    var a = ActivitySnapshot(); a.moveKcal = 250; a.moveGoal = 500; a.exerciseMinutes = 45; a.exerciseGoal = 30; a.standGoal = 0
    check(a.moveFraction == 0.5, "half move")
    check(a.exerciseFraction == 1, "over goal clamps to 1")
    check(a.standFraction == 0, "zero goal → 0, not NaN")
}

// MARK: Crop geometry (iPhone 17 Pro, 402×874 pt)
do {
    let p = PanelPlacement.estimated(screenWidth: 402, screenHeight: 874)
    check(p.panel.width == 350, "estimated width = screen − 52 (measured 349.67)")
    check(p.panel.height == 566, "estimated height 350×1.618 (measured 565.67)")
    let top = p.rect(offset: 0), bottom = p.rect(offset: 1), mid = p.rect(offset: 0.5)
    check(top.x == 26 && bottom.x == 26, "centred")
    check(top.y == 0, "offset 0 is the top edge")
    check(bottom.y + bottom.height == 874, "offset 1 is the bottom edge")
    check(p.rect(offset: p.defaultOffset).y == 88, "default offset lands on the icon grid top (88 pt)")
    check(mid.y > top.y && mid.y < bottom.y, "mid between")
    check(p.rect(offset: 7).y == bottom.y && p.rect(offset: -2).y == top.y, "offset clamps")
    // Reported size taller than the usable band: must still be inside the screen.
    let tall = PanelPlacement(screen: (402, 874), panel: (364, 900))
    let r = tall.rect(offset: 0.5)
    check(r.y == 0 && r.height == 874, "oversize panel clamps to screen")
    // Different phone, same math.
    let se = PanelPlacement.estimated(screenWidth: 375, screenHeight: 667)
    check(se.panel.width == 323 && se.rect(offset: 0).x == 26, "other screen width")
}

// MARK: Config round-trip
do {
    var c = PanelConfig(); c.note = "hi"; c.launcherIDs = ["maps"]; c.tint = 0.4
    let data = try! JSONEncoder().encode(c)
    check(try! JSONDecoder().decode(PanelConfig.self, from: data) == c, "config codable")
    // Older config missing new keys must still decode (defaults fill in).
    let old = #"{"note":"x"}"#.data(using: .utf8)!
    let decodedOld = try? JSONDecoder().decode(PanelConfig.self, from: old)
    check(decodedOld?.tint == 0.0 && decodedOld?.note == "x" && decodedOld?.timerMinutes == 5 && decodedOld?.launcherIDs.count == 5 && decodedOld?.showSeconds == false && decodedOld?.fontDesign == "default", "old config with missing keys keeps defaults")
    // A config written before the v2 redesign carries designVersion 0, which is what triggers the one-time
    // re-seat of the typeface in PanelConfig.load().
    check(decodedOld?.designVersion == 0 && decodedOld?.panelScheme == "auto", "pre-v2 config decodes as designVersion 0 / auto scheme")
}

// MARK: Activity snapshot decodes across versions
do {
    // A snapshot stored before `distanceMeters` existed must still decode (the widget would otherwise
    // show "—" for everyone who upgrades).
    let old = #"{"steps":812,"exerciseMinutes":12,"standHours":3,"moveKcal":140,"moveGoal":500,"exerciseGoal":30,"standGoal":12,"day":760000000}"#.data(using: .utf8)!
    let a = try? JSONDecoder().decode(ActivitySnapshot.self, from: old)
    check(a?.steps == 812 && a?.distanceMeters == 0, "pre-distance activity snapshot still decodes")
    var b = ActivitySnapshot(); b.distanceMeters = 3860
    let round = try? JSONDecoder().decode(ActivitySnapshot.self, from: JSONEncoder().encode(b))
    check(round == b, "activity snapshot round-trips with distance")
}

// MARK: Dark-mode wallpaper pick (panel renders the dark variant only when the system is dark AND a dark crop exists)
do {
    check(PanelBackgroundPick.pick(light: true,  dark: true,  systemDark: true)  == PanelBackgroundPick.dark, "system dark + dark crop → dark")
    check(PanelBackgroundPick.pick(light: true,  dark: false, systemDark: true)  == PanelBackgroundPick.light, "system dark + no dark crop → fall back to light")
    check(PanelBackgroundPick.pick(light: true,  dark: true,  systemDark: false) == PanelBackgroundPick.light, "system light → light even with a dark crop")
    check(PanelBackgroundPick.pick(light: false, dark: true,  systemDark: true)  == PanelBackgroundPick.dark, "no light crop + dark crop available + system dark → dark")
    check(PanelBackgroundPick.pick(light: false, dark: false, systemDark: true)  == PanelBackgroundPick.light, "neither crop → light (no-op)")
    check(PanelBackgroundPick.light == 0 && PanelBackgroundPick.dark == 1, "indices stay 0/1")
    // The new dark URLs live next to the light ones in the shared container — sharing the
    // container means a permission bug would break both at once.
    check(Shared.backgroundDarkURL.lastPathComponent == "panel-bg-dark.jpg", "dark bg URL filename")
    check(Shared.screenshotDarkURL.lastPathComponent == "panel-screenshot-dark.jpg", "dark screenshot URL filename")
}

// MARK: Home Screen grid geometry matches the two measured phones
do {
    let pro = PanelPlacement(screen: (402, 874), panel: (349.67, 565.67))
    check(pro.defaultTop == 88 && pro.rowPitch == 100, "17 Pro grid: top 88, pitch 100")
    let max = PanelPlacement(screen: (440, 956), panel: (388, 628))
    check(max.defaultTop == 94, "17 Pro Max grid top ≈ 93.7 → 94")
    check(max.top(for: .row2) == 311, "17 Pro Max two rows down lands on the measured 311 pt")
    check(abs(max.rowPitch - 108.6) < 0.001, "17 Pro Max pitch 108.6")
}

// MARK: ActivitySnapshot.resolve — fresh wins, today's cache wins, yesterday never does
do {
    // Pin the calendar to UTC so the "23 hours ago" probes don't shift across day boundaries
    // on machines in other timezones. now = 2023-11-14 23:00 UTC → 23 h ago is still the
    // same calendar day, 24 h ago is the previous day, 25 h ago is also the previous day.
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let now = cal.date(from: DateComponents(year: 2023, month: 11, day: 14, hour: 23, minute: 0))!

    // 1. Fresh wins regardless of cached.
    let fresh = ActivitySnapshot(steps: 8000, day: now)
    let old = ActivitySnapshot(steps: 999, day: now.addingTimeInterval(-86400))
    let r1 = ActivitySnapshot.resolve(fresh: fresh, cached: old, now: now, calendar: cal)
    check(r1.steps == 8000, "fresh wins over stale cached")

    // 2. No fresh, cached is from today → use cached.
    let today = ActivitySnapshot(steps: 1234, day: now.addingTimeInterval(-3600))
    let r2 = ActivitySnapshot.resolve(fresh: nil, cached: today, now: now, calendar: cal)
    check(r2.steps == 1234, "today's cache survives when fresh fails")
    check(r2.day == today.day, "cached snapshot keeps its original day timestamp")

    // 3. No fresh, cached is from yesterday → return an empty snapshot dated today.
    let yesterday = ActivitySnapshot(steps: 4321, day: now.addingTimeInterval(-86400))
    let r3 = ActivitySnapshot.resolve(fresh: nil, cached: yesterday, now: now, calendar: cal)
    check(r3.steps == 0 && r3.exerciseMinutes == 0 && r3.distanceMeters == 0, "yesterday's cache becomes zero, not yesterday's number")
    check(cal.isDate(r3.day, inSameDayAs: now), "the empty fallback is dated today")

    // 4. No fresh, no cached → return zero snapshot dated today.
    let r4 = ActivitySnapshot.resolve(fresh: nil, cached: nil, now: now, calendar: cal)
    check(r4.steps == 0, "no fresh, no cached → 0 steps")
    check(cal.isDate(r4.day, inSameDayAs: now), "no fresh, no cached → day is today")
    check(r4.moveGoal == 500 && r4.exerciseGoal == 30 && r4.standGoal == 12, "defaults survive")

    // 5. A snapshot from 23 hours ago is still "today" → still acceptable.
    let earlier = ActivitySnapshot(steps: 77, day: now.addingTimeInterval(-23 * 3600))
    let r5 = ActivitySnapshot.resolve(fresh: nil, cached: earlier, now: now, calendar: cal)
    check(r5.steps == 77, "23-hour-old cache still counts as today")

    // 6. A snapshot from 25 hours ago is yesterday → must NOT be recycled.
    let justYesterday = ActivitySnapshot(steps: 88, day: now.addingTimeInterval(-25 * 3600))
    let r6 = ActivitySnapshot.resolve(fresh: nil, cached: justYesterday, now: now, calendar: cal)
    check(r6.steps == 0, "25-hour-old cache is yesterday → zeroed, not shown as today")

    // 7. The whole reason this function exists: the old PanelModel code stamped `day = Date()`
    //    on the existing snapshot, so a failed query would save yesterday's steps labelled
    //    today. Probe: fresh came back nil AND cached is from yesterday — steps must be 0,
    //    not whatever the cache had. Flip `r3.steps == 0` above and this probe turns red.
    check(ActivitySnapshot.resolve(fresh: nil, cached: yesterday, now: now, calendar: cal).steps == 0,
          "probe: yesterday's cache can never surface as today's steps")
}

// MARK: Mutation probes — flip one thing, expect red
do {
    // 1. Off-by-scheme: a deep link with the scheme upper-cased is a different URL and must not match.
    check(Launcher.fromDeepLink(URL(string: "UTUVOPANEL://launch/music")!) == nil, "probe: scheme is case-sensitive here")
    // 2. Timer: toggling twice at the same instant returns to paused with full remaining.
    let t0 = Date()
    let twice = TimerState().toggled(at: t0, defaultMinutes: 3).toggled(at: t0, defaultMinutes: 3)
    check(twice.pausedRemaining == 180, "probe: pause immediately keeps full 180")
}

// MARK: Setup progress (one-step banner state — driven by WidgetCenter only)
do {
    // Ticket 0007: the wallpaper / position steps were killed by true-transparent. `allDone`
    // now reduces to one question: has the user placed at least one Panel widget on the Home
    // Screen? The extra flags on `compute` are kept for call-site compatibility but ignored.

    // No widget on Home Screen yet → not done.
    var p = SetupProgress.compute(widgetBackgrounds: [], widgetSlots: [], hasScreenshot: false, offsetMoved: false)
    check(p == SetupProgress(widgetPlaced: false), "no widget → not done")
    check(p.allDone == false, "no widget → allDone is false")

    // Any widget on the Home Screen — transparent, gradient, with or without a screenshot — counts as done.
    p = SetupProgress.compute(widgetBackgrounds: ["transparent"], widgetSlots: ["custom"], hasScreenshot: false, offsetMoved: false)
    check(p == SetupProgress(widgetPlaced: true), "widget placed (transparent, no screenshot) → done")
    check(p.allDone, "widget placed → allDone")

    // All widgets on gradient → done (the old code also short-circuited here).
    p = SetupProgress.compute(widgetBackgrounds: ["gradient", "gradient"], widgetSlots: ["custom", "custom"], hasScreenshot: false, offsetMoved: false)
    check(p == SetupProgress(widgetPlaced: true), "all gradient → done")
    check(p.allDone, "all gradient → allDone")

    // Multiple widgets, mixed backgrounds → still done as long as one is on the Home Screen.
    p = SetupProgress.compute(widgetBackgrounds: ["transparent", "gradient"], widgetSlots: ["custom", "row1"], hasScreenshot: true, offsetMoved: true)
    check(p == SetupProgress(widgetPlaced: true), "mixed backgrounds → done")
    check(p.allDone, "mixed backgrounds → allDone")

    // Probe: the old `positioned` / `wallpaperChosen` fields are gone — accessing them must not compile.
    // Pin it via `Mirror` to make sure no leftover SetupProgress carries the dead fields.
    let fields = Mirror(reflecting: SetupProgress(widgetPlaced: true)).children.compactMap { $0.label }
    check(Set(fields) == ["widgetPlaced"], "SetupProgress has only widgetPlaced; got \(Set(fields))")
}

// MARK: Widget configuration slot geometry (iPhone 17 Pro, 402×874 pt)
do {
    // Slot kind maps to the right row offset (custom = no fixed row).
    check(PanelSlotKind.custom.rowsDown == nil, "custom has no rowsDown")
    check(PanelSlotKind.top.rowsDown == 0, "top = 0 rows down")
    check(PanelSlotKind.row1.rowsDown == 1, "row1 = 1 row down")
    check(PanelSlotKind.row2.rowsDown == 2, "row2 = 2 rows down")

    // 874 pt screen: measured row pitch is 100 pt (= 0.1144 × 874, rounded).
    let p = PanelPlacement.estimated(screenWidth: 402, screenHeight: 874)
    check(p.rowPitch == 100, "row pitch on 874-pt screen = 100 pt")
    check(p.top(for: .top) == p.defaultTop, "top slot lands on defaultTop")
    check(p.top(for: .row1) == p.defaultTop + 100, "row1 = defaultTop + one pitch")
    check(p.top(for: .row2) == p.defaultTop + 200, "row2 = defaultTop + two pitches")
    check(p.top(for: .custom) == nil, "custom slot has no top")

    // rect(top:) clamps so the panel is always inside the screen.
    let huge = p.rect(top: 10_000)
    check(huge.y == 874 - 566, "rect clamps y to bottom edge")
    let neg = p.rect(top: -50)
    check(neg.y == 0, "rect clamps y to 0")
    let ok = p.rect(top: 200)
    check(ok.x == 26, "rect keeps horizontal centre")
    check(ok.y == 200, "rect passes valid top through unchanged")

    // Oversize panel: even with a wild top, the rect stays inside the screen.
    let tall = PanelPlacement(screen: (402, 874), panel: (364, 900))
    let r = tall.rect(top: -10_000)
    check(r.y == 0 && r.height == 874, "oversize rect clamps to screen")
}

// MARK: Panel border — every Edit Widget choice pins a known stroke; "none" / unknown → nil
do {
    // none and unknown → nil (renderer draws nothing)
    check(PanelBorderSpec.from(style: "none") == nil, "none → no spec")
    check(PanelBorderSpec.from(style: "fancy") == nil, "unknown string → no spec")
    check(PanelBorderSpec.from(style: "") == nil, "empty string → no spec")

    // Ticket 0008: resolve bridges the Edit Widget intent and the app's default.
    check(PanelBorderPick.resolve(intentValue: "app", appValue: "bold") == "bold",
          "intent says 'app' → use the app setting (bold)")
    check(PanelBorderPick.resolve(intentValue: "double", appValue: "hairline") == "double",
          "intent gives an explicit value → use the intent, app setting ignored")
    check(PanelBorderPick.resolve(intentValue: "app", appValue: "none") == "none",
          "intent says 'app' and app setting is none → none (no border at all)")
    check(PanelBorderPick.resolve(intentValue: "glow", appValue: "none") == "glow",
          "explicit intent beats an app setting of none")
    // Unknown intent values pass through verbatim; the renderer's own nil-fallback then
    // turns them into no border, so a stale widget config can't sneak in a surprise style.
    check(PanelBorderPick.resolve(intentValue: "fancy", appValue: "hairline") == "fancy",
          "unknown intent value passes through (renderer collapses it)")

    // PanelConfig written before ticket 0008 must still decode — borderStyle/borderColor
    // did not exist in the JSON, so the field-by-field decodeIfPresent keeps the defaults.
    let oldBorderConfig = #"{"note":"hi","tint":0.3}"#.data(using: .utf8)!
    let decodedOld = try? JSONDecoder().decode(PanelConfig.self, from: oldBorderConfig)
    check(decodedOld?.borderStyle == "none", "pre-0008 config decodes with borderStyle default 'none'")
    check(decodedOld?.borderColor == "white", "pre-0008 config decodes with borderColor default 'white'")

    // Hairline: 1 pt solid, no inner ring, no glow.
    let hair = PanelBorderSpec.from(style: "hairline")
    check(hair == PanelBorderSpec(width: 1, dash: [], innerWidth: nil, innerInset: 0, glowRadii: []),
          "hairline = 1 pt solid")

    // Bold: 3.5 pt solid (heavier but still no extra geometry).
    let bold = PanelBorderSpec.from(style: "bold")
    check(bold == PanelBorderSpec(width: 3.5, dash: [], innerWidth: nil, innerInset: 0, glowRadii: []),
          "bold = 3.5 pt solid")

    // Double: outer 2 pt + inner 1 pt ring inset 5 pt.
    let dbl = PanelBorderSpec.from(style: "double")
    check(dbl == PanelBorderSpec(width: 2, dash: [], innerWidth: 1, innerInset: 5, glowRadii: []),
          "double = outer 2 pt + inner 1 pt inset 5")

    // Dashed: 2 pt with [8, 6] dash pattern.
    let dash = PanelBorderSpec.from(style: "dashed")
    check(dash == PanelBorderSpec(width: 2, dash: [8, 6], innerWidth: nil, innerInset: 0, glowRadii: []),
          "dashed = 2 pt dash [8, 6]")

    // Glow: 2 pt solid + two shadow layers (radii 6 and 12).
    let glow = PanelBorderSpec.from(style: "glow")
    check(glow == PanelBorderSpec(width: 2, dash: [], innerWidth: nil, innerInset: 0, glowRadii: [6, 12]),
          "glow = 2 pt + shadow radii 6 and 12")

    // Probe: an extra case landing in `default` (e.g. a stale rawValue) still maps to nil,
    // not a partial spec — so old configs never silently start drawing a border.
    check(PanelBorderSpec.from(style: "HAIRLINE") == nil, "probe: unknown variant → nil")
}

// MARK: True-transparent ink pick (wallpaper unknown → pick collapses to white unless user pinned light)
do {
    // Ticket 0005 minimum: auto + transparent → white ink (the safe guess when the wallpaper
    // brightness is unknown). explicit light + transparent → dark ink.
    check(PanelInkPick.lightScheme(trueTransparent: true, panelScheme: "auto", effectiveLuma: 0.9) == false,
          "transparent + auto → white ink (false), regardless of measured luma")
    check(PanelInkPick.lightScheme(trueTransparent: true, panelScheme: "auto", effectiveLuma: 0.1) == false,
          "transparent + auto → white ink even on a dark crop (luma is ignored)")
    check(PanelInkPick.lightScheme(trueTransparent: true, panelScheme: "light", effectiveLuma: 0.1) == true,
          "transparent + pin light → dark ink (true), luma ignored")
    check(PanelInkPick.lightScheme(trueTransparent: true, panelScheme: "dark", effectiveLuma: 0.9) == false,
          "transparent + pin dark → white ink (false), luma ignored")

    // Non-transparent keeps the old behaviour.
    check(PanelInkPick.lightScheme(trueTransparent: false, panelScheme: "auto", effectiveLuma: 0.9) == true,
          "normal + auto + bright wallpaper → dark ink")
    check(PanelInkPick.lightScheme(trueTransparent: false, panelScheme: "auto", effectiveLuma: 0.1) == false,
          "normal + auto + dark wallpaper → white ink")
    check(PanelInkPick.lightScheme(trueTransparent: false, panelScheme: "auto", effectiveLuma: 0.46) == false,
          "normal + auto at the 0.46 threshold → false (strict >)")
    check(PanelInkPick.lightScheme(trueTransparent: false, panelScheme: "auto", effectiveLuma: 0.4601) == true,
          "normal + auto just above the 0.46 threshold → true")

    // Probes: flip one knob, expect red. These are the bug-traps.
    check(PanelInkPick.lightScheme(trueTransparent: true, panelScheme: "light", effectiveLuma: 0.0) == true,
          "probe: transparent + 'light' must stay true even with the luma probe cranked to 0")
    check(PanelInkPick.lightScheme(trueTransparent: false, panelScheme: "dark", effectiveLuma: 0.0) == false,
          "probe: pin 'dark' beats a dark wallpaper — false wins, not the luma test")
}

// MARK: Seconds clock prefix (00:35:17 used to render "35:17")
do {
    // What the day-long timer renders, per the system format: ≥1 h "H:MM:SS", 10–59 min "MM:SS", <10 min "M:SS".
    func timerText(_ h: Int, _ m: Int, _ s: Int) -> String {
        if h >= 1 { return String(format: "%d:%02d:%02d", h, m, s) }
        if m >= 10 { return String(format: "%02d:%02d", m, s) }
        return String(format: "%d:%02d", m, s)
    }
    for (h, m, s) in [(0, 35, 17), (0, 5, 3), (0, 0, 0), (0, 59, 59), (1, 5, 3), (9, 59, 59), (10, 0, 0), (23, 59, 59)] {
        let shown = ClockPrefix.forTime(hour: h, minute: m) + timerText(h, m, s)
        check(shown == String(format: "%02d:%02d:%02d", h, m, s), "clock at \(h):\(m):\(s) reads \(shown)")
    }
}

// MARK: Weather hourly parse — utc_offset + length mismatch + old JSON
do {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!

    // 1. Hourly payload with utc_offset_seconds = 28800 (TWN, +08:00). The 08:00 local
    //    wall-clock string should decode to UTC 00:00 — that's how nextHours produces
    //    sortable Date values across midnight.
    let withHourly = """
    {"current":{"temperature_2m":33.4,"weather_code":0,"is_day":1},
     "daily":{"temperature_2m_max":[35.1],"temperature_2m_min":[26.0]},
     "utc_offset_seconds":28800,
     "hourly":{"time":["2026-09-22T08:00","2026-09-22T09:00","2026-09-22T10:00"],
               "temperature_2m":[25.0,26.0,27.0],
               "weather_code":[0,1,2],
               "is_day":[1,1,1]}}
    """.data(using: .utf8)!
    let w = WeatherSnapshot.parse(withHourly)
    check(w != nil, "hourly JSON parses")
    check(w?.hourly.count == 3, "hourly has 3 points")
    let expectedFirst = utc.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 0, minute: 0))!
    check(w?.hourly.first?.time == expectedFirst,
          "first hourly time = 2026-09-22 UTC 00:00 (local 08:00 + offset 28800)")

    // 2. Length mismatch between any of the four arrays → hourly empty, parse still non-nil.
    let mismatch = """
    {"current":{"temperature_2m":33.4,"weather_code":0,"is_day":1},
     "daily":{"temperature_2m_max":[35.1],"temperature_2m_min":[26.0]},
     "hourly":{"time":["2026-09-22T08:00","2026-09-22T09:00"],
               "temperature_2m":[25.0],
               "weather_code":[0,1],
               "is_day":[1,1]}}
    """.data(using: .utf8)!
    let wmm = WeatherSnapshot.parse(mismatch)
    check(wmm != nil, "length mismatch: parse still non-nil")
    check(wmm?.hourly.isEmpty == true, "length mismatch: hourly empty")
    check(wmm?.temperature == 33.4, "length mismatch: current/daily still intact")

    // 3. Old payload (no hourly key at all) → parse non-nil, hourly empty.
    let oldShape = """
    {"current":{"temperature_2m":33.4,"weather_code":0,"is_day":1},
     "daily":{"temperature_2m_max":[35.1],"temperature_2m_min":[26.0]}}
    """.data(using: .utf8)!
    let wo = WeatherSnapshot.parse(oldShape)
    check(wo != nil && wo?.hourly.isEmpty == true, "no-hourly payload: parse non-nil, hourly empty")

    // 4. Old cache on disk: a snapshot JSON written before ticket 0010 (no `hourly` key)
    //    still decodes — otherwise the widget would crash for everyone who upgrades.
    let oldCache = """
    {"temperature":30.5,"high":35.0,"low":26.0,"code":0,"isDay":true,"fetched":760000000}
    """.data(using: .utf8)!
    let decodedOld = try? JSONDecoder().decode(WeatherSnapshot.self, from: oldCache)
    check(decodedOld != nil, "old cache decodes")
    check(decodedOld?.temperature == 30.5 && decodedOld?.code == 0 && decodedOld?.hourly.isEmpty == true,
          "old cache: data intact, hourly empty")

    // 5. UTC offset of 0 (server returned local time in UTC) — sanity check the math.
    let utcPayload = """
    {"current":{"temperature_2m":1,"weather_code":0,"is_day":1},
     "daily":{"temperature_2m_max":[2],"temperature_2m_min":[0]},
     "utc_offset_seconds":0,
     "hourly":{"time":["2026-09-22T08:00"],
               "temperature_2m":[10.0],
               "weather_code":[0],
               "is_day":[1]}}
    """.data(using: .utf8)!
    let wu = WeatherSnapshot.parse(utcPayload)
    let expectedUtc = utc.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 8, minute: 0))!
    check(wu?.hourly.first?.time == expectedUtc,
          "utc_offset 0: 2026-09-22T08:00 → UTC 08:00 (raw, no shift)")
    check(wu?.hourly.first?.time != expectedFirst,
          "utc_offset 0: NOT shifted to UTC 00:00")

    // 6. URL gains `hourly=...` and `forecast_days=2` (without these the widget would
    //    just render an empty HourlyStrip because the payload has no hourly arrays).
    let u = WeatherSnapshot.url(latitude: 25.033, longitude: 121.565).absoluteString
    check(u.contains("hourly=temperature_2m"), "url includes hourly query")
    check(u.contains("forecast_days=2"), "url: forecast_days = 2 (cover midnight)")
    check(u.contains("forecast_days=1") == false, "url: no longer forecast_days=1")
}

// MARK: nextHours — cross-midnight, exact-hour-edge, short list
do {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let today2300 = utc.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 23, minute: 0))!
    let tomorrow0100 = utc.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 1, minute: 0))!
    let tomorrow0300 = utc.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 3, minute: 0))!
    let pts = [
        WeatherSnapshot.HourlyPoint(time: today2300,    temperature: 18, code: 0, isDay: false),
        WeatherSnapshot.HourlyPoint(time: tomorrow0100, temperature: 22, code: 1, isDay: true),
        WeatherSnapshot.HourlyPoint(time: tomorrow0300, temperature: 24, code: 2, isDay: true),
    ]

    // Cross-midnight: now at 22:30 today pulls both 23:00 (today) and 01:00 / 03:00 (tomorrow),
    // up to count. Time must be ascending regardless of input order.
    let cross = WeatherSnapshot.nextHours(pts, after: today2300.addingTimeInterval(-1800), count: 6)
    check(cross.count == 3, "cross-midnight: all three points retained (count 6)")
    check(cross.map(\.time) == [today2300, tomorrow0100, tomorrow0300],
          "cross-midnight: time-ascending regardless of source order")

    // now lands exactly on a point's time → the point is excluded (strict >).
    let edge = WeatherSnapshot.nextHours(pts, after: today2300, count: 6)
    check(edge.allSatisfy { $0.time > today2300 }, "now == point.time → excluded (strict >)")
    check(edge.count == 2, "now on the hour: only the two tomorrow points remain")

    // Empty input, empty after-pick, and short input (less than count) all behave gracefully.
    check(WeatherSnapshot.nextHours([], after: today2300, count: 6).isEmpty, "empty input → empty output")
    check(WeatherSnapshot.nextHours(pts, after: tomorrow0300.addingTimeInterval(3600), count: 6).isEmpty,
          "now after every point → empty output")

    let oneP = [WeatherSnapshot.HourlyPoint(time: tomorrow0100, temperature: 22, code: 1, isDay: true)]
    let short = WeatherSnapshot.nextHours(oneP, after: today2300, count: 6)
    check(short.count == 1, "fewer than `count` points available → return what's there")
}

// MARK: AgendaPick — 48 h gate, ongoing inclusion, sort, timed-before-allday, limit
do {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let now = utc.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 10, minute: 0))!

    let e1 = EventInfo(title: "1",
                       start: utc.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 11, minute: 0))!,
                       end: utc.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 12, minute: 0))!,
                       isAllDay: false)
    // Started 1 h before now, ends in 30 min — must be included as "ongoing".
    let ongoing = EventInfo(title: "ongoing",
                            start: now.addingTimeInterval(-3600),
                            end: now.addingTimeInterval(1800),
                            isAllDay: false)
    // Tomorrow afternoon: inside the 48 h gate.
    let e2 = EventInfo(title: "2",
                       start: utc.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 13, minute: 0))!,
                       end: utc.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 14, minute: 0))!,
                       isAllDay: false)
    // 50 h from now → outside the 48 h gate, must be excluded.
    let far = EventInfo(title: "far",
                        start: now.addingTimeInterval(50 * 3600),
                        end: now.addingTimeInterval(50 * 3600 + 3600),
                        isAllDay: false)
    // Same start as e1 but all-day → ordered AFTER the timed one.
    let allday = EventInfo(title: "allday",
                           start: e1.start,
                           end: e1.start.addingTimeInterval(24 * 3600),
                           isAllDay: true)

    // Order in the input is deliberately jumbled to prove the sort doesn't trust the caller.
    let pick = AgendaPick.pick([e2, e1, allday, far, ongoing], now: now, limit: 3)
    check(pick.count == 3, "agenda: limit=3 → 3 results")
    check(pick.first?.title == "ongoing", "agenda: ongoing wins the leading slot")
    check(pick.allSatisfy { $0.title != "far" }, "agenda: >48 h excluded by gate")

    // Limit test: with four candidates (ongoing, e1, allday, e2), limit=3 drops one.
    // Sort is ongoing, e1, allday, e2 — so limit=3 keeps ongoing, e1, allday; e2 falls off.
    check(pick.last?.title == "allday",
          "agenda: limit=3 keeps ongoing + e1 + allday; e2 dropped")
    check(!pick.contains(where: { $0.title == "2" }),
          "agenda: e2 (next-day, same time as allday would be if limit were wide) pushed out by allday at +1h")

    // With limit high enough to admit everything, the full sort is visible: ongoing, then
    // by start, with the timed event at +1h sitting above the all-day at +1h.
    let pickAll = AgendaPick.pick([allday, e1, e2, ongoing], now: now, limit: 5)
    check(pickAll.map(\.title) == ["ongoing", "1", "allday", "2"],
          "agenda: ongoing first, then by start; timed beats all-day at same start")

    // No events at all → empty result.
    check(AgendaPick.pick([], now: now, limit: 3).isEmpty, "agenda: empty input → empty output")

    // Events ending exactly at now are still "ongoing" (closed interval).
    let endingNow = EventInfo(title: "ending-now",
                              start: now.addingTimeInterval(-3600),
                              end: now,
                              isAllDay: false)
    check(AgendaPick.pick([endingNow], now: now, limit: 3).count == 1,
          "agenda: end == now is still ongoing (inclusive)")
}

// MARK: PanelConfig — pre-0010 JSON decodes with bottomLayout == "hourly"
do {
    // The ticket's "Micky installs the upgrade" scenario: any saved config without the new
    // key has to keep working. The default ("hourly") is what we want — that's what the
    // user was effectively seeing before this ticket (the bottom was empty hourly space).
    let pre = #"{"note":"x","tint":0.3}"#.data(using: .utf8)!
    let decoded = try? JSONDecoder().decode(PanelConfig.self, from: pre)
    check(decoded?.bottomLayout == "hourly",
          "pre-0010 config decodes with bottomLayout default 'hourly'")

    // A config that explicitly opted into agenda still survives a round-trip.
    var c = PanelConfig(); c.bottomLayout = "agenda"
    let enc = try! JSONEncoder().encode(c)
    let dec = try? JSONDecoder().decode(PanelConfig.self, from: enc)
    check(dec?.bottomLayout == "agenda", "bottomLayout round-trips")
}

print(failures == 0 ? "OK — all checks green" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
