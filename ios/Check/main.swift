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
    check(u.contains("latitude=25.0330") && u.contains("longitude=121.5650") && u.contains("timezone=auto"), "url query")
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
    check(decodedOld?.tint == 0.0 && decodedOld?.note == "x" && decodedOld?.timerMinutes == 5 && decodedOld?.launcherIDs.count == 5 && decodedOld?.showSeconds == false && decodedOld?.fontDesign == "rounded", "old config with missing keys keeps defaults")
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

print(failures == 0 ? "OK — all checks green" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
