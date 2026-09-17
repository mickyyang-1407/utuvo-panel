// Logic.swift — Foundation only. Everything here is also compiled by Check/main.swift,
// so keep UIKit / SwiftUI / WidgetKit out of this file.

import Foundation

enum Shared {
    static let appGroup = "group.com.utuvo.panel"
    static let widgetKind = "UTUVOPanel.Panel"
    static let urlScheme = "utuvopanel"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }
    static var container: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.temporaryDirectory
    }
    static var backgroundURL: URL { container.appendingPathComponent("panel-bg.jpg") }
    static var avatarURL: URL { container.appendingPathComponent("avatar.jpg") }

    enum Key {
        static let config = "panel.config"
        static let weather = "panel.weather"
        static let activity = "panel.activity"
        static let timer = "panel.timer"
        static let displaySize = "panel.displaySize"   // written by the widget provider
        static let system = "panel.system"
    }
}

// MARK: - Codable store helpers

extension UserDefaults {
    func codable<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func set<T: Encodable>(codable value: T?, forKey key: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            set(data, forKey: key)
        } else {
            removeObject(forKey: key)
        }
    }
}

// MARK: - Config

struct PanelConfig: Codable, Equatable {
    var showCalendar = true
    var showWeather = true
    var showActivity = true
    var showTimer = true
    var showLaunchers = true
    var showNote = false      // retired row, kept so old configs decode
    var showSystem = true
    /// Up to four ids from SystemMetric.all, in display order.
    var systemMetrics: [String] = ["cpu", "ram", "storage", "network"]

    var note = ""
    /// Clock shows a live seconds counter instead of hh:mm.
    var showSeconds = false
    /// Panel typeface: "default" (SF Pro), "rounded" (SF Rounded), "serif" (New York), "mono" (SF Mono).
    var fontDesign = "rounded"
    var timerMinutes = 5
    var launcherIDs: [String] = ["music", "messages", "maps", "camera", "notes"]
    /// 0 = fully transparent wallpaper, 1 = opaque black.
    var tint: Double = 0.0
    /// Vertical placement of the panel inside the screenshot, 0 (top) … 1 (bottom).
    var backgroundOffset: Double = 0.286  // = PanelPlacement.defaultOffset on a 17 Pro (88 pt / (874−566)); app resets it on first pick

    var latitude: Double?
    var longitude: Double?
    var city: String?

    init() {}

    /// Synthesized Decodable would reject a stored config missing a key added later,
    /// and `load()` would then silently reset the user's setup. Decode field by field instead.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PanelConfig()
        showCalendar = try c.decodeIfPresent(Bool.self, forKey: .showCalendar) ?? d.showCalendar
        showWeather = try c.decodeIfPresent(Bool.self, forKey: .showWeather) ?? d.showWeather
        showActivity = try c.decodeIfPresent(Bool.self, forKey: .showActivity) ?? d.showActivity
        showTimer = try c.decodeIfPresent(Bool.self, forKey: .showTimer) ?? d.showTimer
        showLaunchers = try c.decodeIfPresent(Bool.self, forKey: .showLaunchers) ?? d.showLaunchers
        showNote = try c.decodeIfPresent(Bool.self, forKey: .showNote) ?? d.showNote
        showSystem = try c.decodeIfPresent(Bool.self, forKey: .showSystem) ?? d.showSystem
        systemMetrics = try c.decodeIfPresent([String].self, forKey: .systemMetrics) ?? d.systemMetrics
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? d.note
        showSeconds = try c.decodeIfPresent(Bool.self, forKey: .showSeconds) ?? d.showSeconds
        fontDesign = try c.decodeIfPresent(String.self, forKey: .fontDesign) ?? d.fontDesign
        timerMinutes = try c.decodeIfPresent(Int.self, forKey: .timerMinutes) ?? d.timerMinutes
        launcherIDs = try c.decodeIfPresent([String].self, forKey: .launcherIDs) ?? d.launcherIDs
        tint = try c.decodeIfPresent(Double.self, forKey: .tint) ?? d.tint
        backgroundOffset = try c.decodeIfPresent(Double.self, forKey: .backgroundOffset) ?? d.backgroundOffset
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        city = try c.decodeIfPresent(String.self, forKey: .city)
    }

    static func load() -> PanelConfig {
        Shared.defaults.codable(PanelConfig.self, forKey: Shared.Key.config) ?? PanelConfig()
    }
    func save() {
        Shared.defaults.set(codable: self, forKey: Shared.Key.config)
    }
}

// MARK: - System metrics (what the system row can show)

struct SystemMetric: Identifiable, Equatable {
    let id: String
    let name: String      // localization key
    let tile: String
    let symbol: String
    static let all: [SystemMetric] = [
        SystemMetric(id: "cpu",      name: "CPU",       tile: "tile-cpu",      symbol: "cpu"),
        SystemMetric(id: "ram",      name: "RAM",       tile: "tile-memory",   symbol: "memorychip"),
        SystemMetric(id: "memfree",  name: "可用記憶體", tile: "tile-memfree",  symbol: "memorychip"),
        SystemMetric(id: "storage",  name: "可用空間",   tile: "tile-storage",  symbol: "internaldrive"),
        SystemMetric(id: "used",     name: "已用空間",   tile: "tile-storage",  symbol: "internaldrive"),
        SystemMetric(id: "network",  name: "連線",      tile: "tile-wifi",     symbol: "wifi"),
        SystemMetric(id: "battery",  name: "電量",      tile: "tile-battery",  symbol: "battery.75percent"),
        SystemMetric(id: "lowpower", name: "低耗電",    tile: "tile-lowpower", symbol: "bolt.fill"),
        SystemMetric(id: "thermal",  name: "溫度",      tile: "tile-thermal",  symbol: "thermometer.medium"),
        SystemMetric(id: "uptime",   name: "開機時間",   tile: "tile-uptime",   symbol: "hourglass"),
        SystemMetric(id: "ip",       name: "IP",        tile: "tile-ip",       symbol: "globe"),
    ]
    static func byID(_ id: String) -> SystemMetric? { all.first { $0.id == id } }
}

// MARK: - Launchers

struct Launcher: Identifiable, Equatable {
    let id: String
    let name: String
    let symbol: String
    let colorHex: UInt32
    let url: String

    static let presets: [Launcher] = [
        Launcher(id: "music",     name: "音樂",     symbol: "music.note",          colorHex: 0xFC3C44, url: "music://"),
        Launcher(id: "messages",  name: "訊息",     symbol: "message.fill",        colorHex: 0x34C759, url: "messages://"),
        Launcher(id: "maps",      name: "地圖",     symbol: "map.fill",            colorHex: 0x30B0C7, url: "maps://"),
        Launcher(id: "camera",    name: "相機",     symbol: "camera.fill",         colorHex: 0x8E8E93, url: "camera://"),
        Launcher(id: "notes",     name: "備忘錄",   symbol: "note.text",           colorHex: 0xFFCC00, url: "mobilenotes://"),
        Launcher(id: "books",     name: "書籍",     symbol: "book.fill",           colorHex: 0xFF9500, url: "ibooks://"),
        Launcher(id: "photos",    name: "照片",     symbol: "photo.on.rectangle",  colorHex: 0xFF2D55, url: "photos-redirect://"),
        Launcher(id: "calendar",  name: "行事曆",   symbol: "calendar",            colorHex: 0xFF3B30, url: "calshow://"),
        Launcher(id: "mail",      name: "郵件",     symbol: "envelope.fill",       colorHex: 0x007AFF, url: "message://"),
        Launcher(id: "shortcuts", name: "捷徑",     symbol: "square.stack.3d.up",  colorHex: 0x5856D6, url: "shortcuts://"),
        Launcher(id: "phone",     name: "電話",     symbol: "phone.fill",          colorHex: 0x34C759, url: "tel:"),
        Launcher(id: "weather",   name: "天氣",     symbol: "cloud.sun.fill",      colorHex: 0x5AC8FA, url: "weather://"),
        Launcher(id: "clock",     name: "時鐘",     symbol: "clock.fill",          colorHex: 0x1C1C1E, url: "clock-alarm://"),
        Launcher(id: "translate", name: "翻譯",     symbol: "character.bubble",    colorHex: 0x32ADE6, url: "translate://"),
        Launcher(id: "settings",  name: "設定",     symbol: "gearshape.fill",      colorHex: 0x8E8E93, url: "App-prefs://"),
        Launcher(id: "fitness",   name: "健身",     symbol: "figure.run",          colorHex: 0xFF375F, url: "fitnessapp://"),
    ]

    static func byID(_ id: String) -> Launcher? { presets.first { $0.id == id } }

    /// The widget can only open its own container app. Each launcher tile links here;
    /// the app receives it and forwards to the real scheme.
    var deepLink: URL { URL(string: "\(Shared.urlScheme)://launch/\(id)")! }

    /// The gear on the panel: opens the app's settings.
    static var settingsDeepLink: URL { URL(string: "\(Shared.urlScheme)://settings")! }

    /// Parse `utuvopanel://launch/<id>` back to a launcher. Anything else → nil.
    static func fromDeepLink(_ url: URL) -> Launcher? {
        guard url.scheme == Shared.urlScheme, url.host == "launch" else { return nil }
        let id = url.pathComponents.dropFirst().first ?? ""
        return byID(id)
    }
}

// MARK: - Weather

struct WeatherSnapshot: Codable, Equatable {
    var temperature: Double
    var high: Double
    var low: Double
    var code: Int          // WMO weather interpretation code
    var isDay: Bool
    var fetched: Date

    /// Open-Meteo, no key required.
    static func url(latitude: Double, longitude: Double) -> URL {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(format: "%.4f", latitude)),
            .init(name: "longitude", value: String(format: "%.4f", longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "forecast_days", value: "1"),
            .init(name: "timezone", value: "auto"),
        ]
        return c.url!
    }

    static func parse(_ data: Data, now: Date = Date()) -> WeatherSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = root["current"] as? [String: Any],
              let daily = root["daily"] as? [String: Any],
              let temp = current["temperature_2m"] as? Double,
              let code = current["weather_code"] as? Int,
              let hi = (daily["temperature_2m_max"] as? [Double])?.first,
              let lo = (daily["temperature_2m_min"] as? [Double])?.first
        else { return nil }
        let isDay = ((current["is_day"] as? Int) ?? 1) == 1
        return WeatherSnapshot(temperature: temp, high: hi, low: lo, code: code, isDay: isDay, fetched: now)
    }

    /// SF Symbol → pre-rendered glass tile asset (tools/make-tiles.py `weather` list).
    static func tileName(for symbol: String) -> String {
        let map: [String: String] = [
            "sun.max.fill": "wx-sun", "moon.stars.fill": "wx-moon-stars", "moon.fill": "wx-moon",
            "cloud.sun.fill": "wx-cloud-sun", "cloud.moon.fill": "wx-cloud-moon", "cloud.fill": "wx-cloud",
            "cloud.fog.fill": "wx-fog", "cloud.drizzle.fill": "wx-drizzle", "cloud.sleet.fill": "wx-sleet",
            "cloud.rain.fill": "wx-rain", "cloud.snow.fill": "wx-snow", "cloud.heavyrain.fill": "wx-heavyrain",
            "cloud.bolt.fill": "wx-bolt", "cloud.bolt.rain.fill": "wx-bolt-rain"]
        return map[symbol] ?? "wx-unknown"
    }

    /// WMO code → (SF Symbol, 中文). Table from the Open-Meteo docs.
    var description: (symbol: String, text: String) {
        switch code {
        case 0:            return (isDay ? "sun.max.fill" : "moon.stars.fill", "晴")
        case 1:            return (isDay ? "sun.max.fill" : "moon.fill", "大致晴朗")
        case 2:            return (isDay ? "cloud.sun.fill" : "cloud.moon.fill", "多雲")
        case 3:            return ("cloud.fill", "陰")
        case 45, 48:       return ("cloud.fog.fill", "霧")
        case 51, 53, 55:   return ("cloud.drizzle.fill", "毛毛雨")
        case 56, 57:       return ("cloud.sleet.fill", "凍雨")
        case 61, 63, 65:   return ("cloud.rain.fill", "雨")
        case 66, 67:       return ("cloud.sleet.fill", "凍雨")
        case 71, 73, 75, 77: return ("cloud.snow.fill", "雪")
        case 80, 81, 82:   return ("cloud.heavyrain.fill", "陣雨")
        case 85, 86:       return ("cloud.snow.fill", "陣雪")
        case 95:           return ("cloud.bolt.fill", "雷雨")
        case 96, 99:       return ("cloud.bolt.rain.fill", "雷雨冰雹")
        default:           return ("questionmark.circle", "—")
        }
    }
}

// MARK: - Activity (written by the app from HealthKit, read by the widget)

struct ActivitySnapshot: Codable, Equatable {
    var steps: Int = 0
    var exerciseMinutes: Int = 0
    var standHours: Int = 0
    var moveKcal: Double = 0
    var moveGoal: Double = 500
    var exerciseGoal: Double = 30
    var standGoal: Double = 12
    var day: Date = Date()

    var moveFraction: Double { moveGoal > 0 ? min(moveKcal / moveGoal, 1) : 0 }
    var exerciseFraction: Double { exerciseGoal > 0 ? min(Double(exerciseMinutes) / exerciseGoal, 1) : 0 }
    var standFraction: Double { standGoal > 0 ? min(Double(standHours) / standGoal, 1) : 0 }
}

// MARK: - Timer

/// idle: both nil · running: endDate set · paused: remaining set.
struct TimerState: Codable, Equatable {
    var endDate: Date?
    var pausedRemaining: TimeInterval?

    enum Phase { case idle, running, paused }
    func phase(at now: Date) -> Phase {
        if let end = endDate { return end > now ? .running : .idle }
        if pausedRemaining != nil { return .paused }
        return .idle
    }

    static func load() -> TimerState {
        Shared.defaults.codable(TimerState.self, forKey: Shared.Key.timer) ?? TimerState()
    }
    func save() { Shared.defaults.set(codable: self, forKey: Shared.Key.timer) }

    /// Start (idle) / pause (running) / resume (paused). One button, three meanings.
    func toggled(at now: Date, defaultMinutes: Int) -> TimerState {
        switch phase(at: now) {
        case .idle:
            return TimerState(endDate: now.addingTimeInterval(TimeInterval(max(defaultMinutes, 1)) * 60), pausedRemaining: nil)
        case .running:
            return TimerState(endDate: nil, pausedRemaining: max(endDate!.timeIntervalSince(now), 0))
        case .paused:
            return TimerState(endDate: now.addingTimeInterval(pausedRemaining!), pausedRemaining: nil)
        }
    }
    static let stopped = TimerState()

    /// Fixed remaining shown while paused, formatted m:ss.
    static func format(_ seconds: TimeInterval) -> String {
        let s = max(Int(seconds.rounded()), 0)
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}

// MARK: - Calendar event (widget reads EventKit itself; this is the render model)

struct EventInfo: Equatable {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
}

// MARK: - Background crop geometry

/// Where the extra-large-portrait panel sits on a full-screen screenshot.
/// Everything in points; caller multiplies by the screenshot's pixel scale.
struct PanelPlacement: Equatable {
    var screen: (width: Double, height: Double)
    var panel: (width: Double, height: Double)

    static func == (a: PanelPlacement, b: PanelPlacement) -> Bool {
        a.screen == b.screen && a.panel == b.panel
    }

    /// Fallback when the widget has not yet reported its display size.
    /// Measured on iPhone 17 Pro / iOS 27.0 (24A434): displaySize 349.67 × 565.67 on a 402-pt screen,
    /// i.e. 26 pt side margins and a 1.618 aspect. The provider's real value replaces this after first render.
    static func estimated(screenWidth: Double, screenHeight: Double) -> PanelPlacement {
        let w = screenWidth - 52
        return PanelPlacement(screen: (screenWidth, screenHeight), panel: (w, (w * 1.618).rounded()))
    }

    /// Where the panel lands when it is the first item on a page scrolled to the top
    /// (measured: icon grid starts 88 pt down on an 874-pt screen). Used as the default offset.
    var defaultTop: Double { (screen.height * 0.1007).rounded() }
    var defaultOffset: Double {
        let range = max(screen.height - panel.height, 1)
        return min(max(defaultTop / range, 0), 1)
    }

    /// Crop rect for `offset` in 0…1 over the whole screen (0 = top edge, 1 = bottom edge).
    /// iOS 27 home pages scroll vertically, so no band is off-limits; the user drags it into place.
    /// Horizontally centred. Clamped so the rect is always inside the screen.
    func rect(offset: Double) -> (x: Double, y: Double, width: Double, height: Double) {
        let o = min(max(offset, 0), 1)
        let x = ((screen.width - panel.width) / 2).rounded()
        let maxY = max(screen.height - panel.height, 0)
        let y = (maxY * o).rounded()
        return (x, y, panel.width, min(panel.height, screen.height))
    }
}
