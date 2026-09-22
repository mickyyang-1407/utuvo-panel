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
    static var backgroundDarkURL: URL { container.appendingPathComponent("panel-bg-dark.jpg") }
    static var screenshotURL: URL { container.appendingPathComponent("panel-screenshot.jpg") }
    static var screenshotDarkURL: URL { container.appendingPathComponent("panel-screenshot-dark.jpg") }
    static var avatarURL: URL { container.appendingPathComponent("avatar.jpg") }

    enum Key {
        static let config = "panel.config"
        static let weather = "panel.weather"
        static let activity = "panel.activity"
        static let timer = "panel.timer"
        static let displaySize = "panel.displaySize"   // written by the widget provider
        static let system = "panel.system"
        static let screenPoints = "panel.screenPoints"   // app writes [width, height] in pt
    }
}

/// User's selection in the widget's "Edit Widget" sheet. Pure data: both the intent
/// (PanelSlotChoice) and the geometry (PanelPlacement.top(for:)) read from this.
enum PanelSlotKind: String, CaseIterable {
    case custom, top, row1, row2

    /// How many icon rows below the top of the page; nil = use the app's aligned crop.
    var rowsDown: Int? {
        switch self {
        case .custom: return nil
        case .top:    return 0
        case .row1:   return 1
        case .row2:   return 2
        }
    }
}

// MARK: - Background selection (system appearance aware)

/// Which wallpaper crop to draw: 0 = light, 1 = dark. Pure function so Check can exercise every branch.
enum PanelBackgroundPick {
    static let light = 0
    static let dark = 1
    static func pick(light: Bool, dark: Bool, systemDark: Bool) -> Int {
        if systemDark, dark { return PanelBackgroundPick.dark }
        return PanelBackgroundPick.light
    }
}

// MARK: - Ink scheme (light glass + dark ink vs dark glass + white ink)

/// Pure decision over the inputs that drive the panel's ink scheme, kept here so Check can pin
/// every branch. `PanelData.lightScheme` is the only caller.
enum PanelInkPick {
    /// True = light glass + dark ink (the reference look); false = dark glass + white ink.
    /// - `trueTransparent`: wallpaper shows straight through; we don't know its brightness, so
    ///   the user's explicit pick wins and `auto` collapses to white ink (false).
    /// - Otherwise: explicit pick wins, `auto` falls back to the measured luminance.
    static func lightScheme(trueTransparent: Bool, panelScheme: String, effectiveLuma: Double) -> Bool {
        if trueTransparent {
            return panelScheme == "light"
        }
        switch panelScheme {
        case "light": return true
        case "dark": return false
        default: return effectiveLuma > 0.46
        }
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
    var fontDesign = "default"
    /// Ink scheme: "auto" (from the wallpaper), "light" (dark ink on light glass), "dark" (white ink).
    var panelScheme = "auto"
    /// Bumped when the panel design changes in a way that has to re-seat old settings. 2 = editorial glass (2026-09-21).
    var designVersion = 0
    var timerMinutes = 5
    var launcherIDs: [String] = ["music", "messages", "maps", "camera", "notes"]
    /// 0 = fully transparent wallpaper, 1 = opaque black.
    var tint: Double = 0.0
    /// Vertical placement of the panel inside the screenshot, 0 (top) … 1 (bottom).
    var backgroundOffset: Double = 0.286  // = PanelPlacement.defaultOffset on a 17 Pro (88 pt / (874−566)); app resets it on first pick
    /// Default border style for every Panel widget on the Home Screen. Edit Widget can still
    /// override this per-instance via `PanelWidgetIntent.border` (case `.app` = follow this).
    /// Ticket 0008 — same ids as `PanelBorderChoice.rawValue` so the renderer reuses one switch.
    var borderStyle: String = "none"
    /// Default border colour; `.ink` follows the current ink, others are hexes. Same id space as `PanelBorderColorChoice`.
    var borderColor: String = "white"
    /// How the bottom of an extra-large portrait panel fills its leftover space —
    /// "hourly" (next 6 hours weather), "agenda" (next 3 events), or "spread" (even gaps).
    /// The user picks this in the app's settings; systemLarge (`compact == true`) is unaffected.
    var bottomLayout: String = "hourly"

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
        panelScheme = try c.decodeIfPresent(String.self, forKey: .panelScheme) ?? d.panelScheme
        designVersion = try c.decodeIfPresent(Int.self, forKey: .designVersion) ?? d.designVersion
        timerMinutes = try c.decodeIfPresent(Int.self, forKey: .timerMinutes) ?? d.timerMinutes
        launcherIDs = try c.decodeIfPresent([String].self, forKey: .launcherIDs) ?? d.launcherIDs
        tint = try c.decodeIfPresent(Double.self, forKey: .tint) ?? d.tint
        backgroundOffset = try c.decodeIfPresent(Double.self, forKey: .backgroundOffset) ?? d.backgroundOffset
        borderStyle = try c.decodeIfPresent(String.self, forKey: .borderStyle) ?? d.borderStyle
        borderColor = try c.decodeIfPresent(String.self, forKey: .borderColor) ?? d.borderColor
        bottomLayout = try c.decodeIfPresent(String.self, forKey: .bottomLayout) ?? d.bottomLayout
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        city = try c.decodeIfPresent(String.self, forKey: .city)
    }

    static let currentDesignVersion = 2

    static func load() -> PanelConfig {
        guard var c = Shared.defaults.codable(PanelConfig.self, forKey: Shared.Key.config) else { return PanelConfig() }
        // v2 is drawn for SF Pro; a config saved under v1 still carries the old rounded default.
        if c.designVersion < currentDesignVersion {
            if c.fontDesign == "rounded" { c.fontDesign = "default" }
            c.designVersion = currentDesignVersion
            c.save()
        }
        return c
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
        Launcher(id: "messages",  name: "訊息",     symbol: "message.fill",        colorHex: 0x34C759, url: "ichat://"),   // iOS 26: sms:/messages:// open compose; ichat:// opens the conversation list
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
    /// Next ~48 h of hourly data, parsed only when the response had matching-length arrays.
    /// `HourlyPoint` is a `Date` so the renderer can sort/filter without re-parsing strings.
    /// Defaults to `[]`; the `init(from:)` below swallows the case where this key was saved
    /// before ticket 0010, so old caches still decode.
    var hourly: [HourlyPoint] = []

    /// One hour's weather. Auto-synth works (Codable + Equatable on Date/Double/Int/Bool).
    struct HourlyPoint: Codable, Equatable {
        var time: Date
        var temperature: Double
        var code: Int
        var isDay: Bool
    }

    /// `init(from:)` is written by hand (not synthesized) so a snapshot written before `hourly`
    /// existed still decodes — synthesized Decodable rejects missing non-optional keys.
    init(temperature: Double, high: Double, low: Double, code: Int, isDay: Bool,
         fetched: Date, hourly: [HourlyPoint] = []) {
        self.temperature = temperature; self.high = high; self.low = low
        self.code = code; self.isDay = isDay; self.fetched = fetched; self.hourly = hourly
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WeatherSnapshot(temperature: 0, high: 0, low: 0, code: 0, isDay: true, fetched: Date())
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? d.temperature
        high        = try c.decodeIfPresent(Double.self, forKey: .high)        ?? d.high
        low         = try c.decodeIfPresent(Double.self, forKey: .low)         ?? d.low
        code        = try c.decodeIfPresent(Int.self,    forKey: .code)        ?? d.code
        isDay       = try c.decodeIfPresent(Bool.self,   forKey: .isDay)       ?? d.isDay
        fetched     = try c.decodeIfPresent(Date.self,   forKey: .fetched)     ?? d.fetched
        hourly      = try c.decodeIfPresent([HourlyPoint].self, forKey: .hourly) ?? d.hourly
    }

    /// Open-Meteo, no key required.
    static func url(latitude: Double, longitude: Double) -> URL {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(format: "%.2f", latitude)),
            .init(name: "longitude", value: String(format: "%.2f", longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            // 2 days of hourly covers "next 6 whole hours even across midnight".
            .init(name: "forecast_days", value: "2"),
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
        // Hourly is best-effort: present and aligned → use it; missing or misaligned → []
        // (we deliberately do NOT return nil here — the current/daily snapshot is still valuable).
        let hourly: [HourlyPoint] = Self.parseHourly(root: root)
        return WeatherSnapshot(temperature: temp, high: hi, low: lo, code: code, isDay: isDay,
                               fetched: now, hourly: hourly)
    }

    /// Read `hourly.{time,temperature_2m,weather_code,is_day}` from an Open-Meteo response.
    /// Returns `[]` if any of the arrays is missing or the four aren't the same length
    /// (the ticket's length-mismatch branch — `nextHours` then falls back to the spread layout).
    /// Local-time strings `"yyyy-MM-dd'T'HH:mm"` carry no timezone designator; the response's
    /// `utc_offset_seconds` is what turns them into real `Date` values.
    private static func parseHourly(root: [String: Any]) -> [HourlyPoint] {
        guard let h = root["hourly"] as? [String: Any],
              let times = h["time"] as? [String],
              let temps = h["temperature_2m"] as? [Double],
              let codes = h["weather_code"] as? [Int],
              let days = h["is_day"] as? [Int]
        else { return [] }
        guard times.count == temps.count, temps.count == codes.count, codes.count == days.count
        else { return [] }
        let offset = (root["utc_offset_seconds"] as? Int) ?? 0
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm"
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.locale = Locale(identifier: "en_US_POSIX")
        var out: [HourlyPoint] = []
        out.reserveCapacity(times.count)
        for i in 0..<times.count {
            // Parse the local-time string as if it were UTC, then subtract the offset
            // — what remains is the real UTC instant for that "wall-clock hour".
            guard let naive = fmt.date(from: times[i]) else { continue }
            let utc = naive.addingTimeInterval(-Double(offset))
            out.append(HourlyPoint(time: utc, temperature: temps[i],
                                   code: codes[i], isDay: days[i] == 1))
        }
        return out
    }

    /// Pure: the first `count` hourly points strictly later than `now`, time-ascending.
    /// Used by the bottom-of-panel hourly strip; lives in Logic so Check can pin the
    /// cross-midnight / exact-hour-edge / short-list cases.
    static func nextHours(_ points: [HourlyPoint], after now: Date, count: Int = 6) -> [HourlyPoint] {
        return points
            .filter { $0.time > now }
            .sorted { $0.time < $1.time }
            .prefix(count)
            .map { $0 }
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
    /// Walking + running distance today, in metres. Shown on the ribbon next to the step count.
    var distanceMeters: Double = 0

    init() {}
    init(steps: Int = 0, exerciseMinutes: Int = 0, standHours: Int = 0, moveKcal: Double = 0,
         moveGoal: Double = 500, exerciseGoal: Double = 30, standGoal: Double = 12,
         day: Date = Date(), distanceMeters: Double = 0) {
        self.steps = steps; self.exerciseMinutes = exerciseMinutes; self.standHours = standHours
        self.moveKcal = moveKcal; self.moveGoal = moveGoal; self.exerciseGoal = exerciseGoal
        self.standGoal = standGoal; self.day = day; self.distanceMeters = distanceMeters
    }

    /// Same reason as PanelConfig: a snapshot written before a field existed must still decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ActivitySnapshot()
        steps = try c.decodeIfPresent(Int.self, forKey: .steps) ?? d.steps
        exerciseMinutes = try c.decodeIfPresent(Int.self, forKey: .exerciseMinutes) ?? d.exerciseMinutes
        standHours = try c.decodeIfPresent(Int.self, forKey: .standHours) ?? d.standHours
        moveKcal = try c.decodeIfPresent(Double.self, forKey: .moveKcal) ?? d.moveKcal
        moveGoal = try c.decodeIfPresent(Double.self, forKey: .moveGoal) ?? d.moveGoal
        exerciseGoal = try c.decodeIfPresent(Double.self, forKey: .exerciseGoal) ?? d.exerciseGoal
        standGoal = try c.decodeIfPresent(Double.self, forKey: .standGoal) ?? d.standGoal
        day = try c.decodeIfPresent(Date.self, forKey: .day) ?? d.day
        distanceMeters = try c.decodeIfPresent(Double.self, forKey: .distanceMeters) ?? d.distanceMeters
    }

    var moveFraction: Double { moveGoal > 0 ? min(moveKcal / moveGoal, 1) : 0 }
    var exerciseFraction: Double { exerciseGoal > 0 ? min(Double(exerciseMinutes) / exerciseGoal, 1) : 0 }
    var standFraction: Double { standGoal > 0 ? min(Double(standHours) / standGoal, 1) : 0 }

    /// What the panel shows:
    /// - a fresh HealthKit read wins (it came from today);
    /// - otherwise today's cached snapshot (it was written earlier today);
    /// - otherwise an empty snapshot dated today.
    ///
    /// Yesterday's cache is NEVER shown as today's numbers. The whole reason this function
    /// exists: `PanelModel.refreshHealth()` used to seed `snap` from `activity ?? .init()`
    /// and stamp `snap.day = Date()`, so a single failed query would save yesterday's steps
    /// labelled as today. This `resolve` is the only place the snapshot the user sees is
    /// chosen, and it refuses to recycle stale data.
    static func resolve(fresh: ActivitySnapshot?, cached: ActivitySnapshot?, now: Date, calendar: Calendar = .current) -> ActivitySnapshot {
        if let fresh { return fresh }
        if let cached, calendar.isDate(cached.day, inSameDayAs: now) { return cached }
        return ActivitySnapshot(day: now)
    }
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

// MARK: - Panel border (drawn in PanelView, fed by the intent)

/// Bridges `PanelWidgetIntent` (per-instance override) and `PanelConfig` (the app's default).
/// `intentValue == "app"` → fall through to `appValue`; anything else is treated as an explicit
/// choice and passed through verbatim (so an unknown string still flows to the renderer, which
/// already collapses unknown styles to "no border"). Pure function so Check can pin every branch.
/// The "show seconds" clock is a live day-long system timer (`Text(timerInterval:showsHours:)`), which
/// renders elapsed time as "H:MM:SS" for ≥ 1 h (hour not padded), "MM:SS" for 10–59 min and "M:SS"
/// under 10 min — so 00:35:17 used to show "35:17". This is the static text to put in front of it so the
/// whole reads HH:MM:SS. It only changes at minute boundaries, and the widget has one entry per minute.
enum ClockPrefix {
    static func forTime(hour: Int, minute: Int) -> String {
        if hour >= 10 { return "" }
        if hour >= 1 { return "0" }
        return minute >= 10 ? "00:" : "00:0"
    }
}

enum PanelBorderPick {
    static let followsApp = "app"
    static func resolve(intentValue: String, appValue: String) -> String {
        intentValue == Self.followsApp ? appValue : intentValue
    }
}

/// Geometry for the panel's outer stroke. One shape + one or two `strokeBorder`s; the renderer
/// (PanelView) reads this struct, not the intent's raw string, so Check can pin every case.
/// `none` is **not** a spec — the renderer's first check is `from(style:) == nil` and it draws
/// nothing. Unknown strings also → nil so a config written before this ticket still draws no border.
struct PanelBorderSpec: Equatable {
    /// Outer stroke width, in points.
    var width: Double
    /// Dash pattern, e.g. [8, 6]. Empty = solid.
    var dash: [Double]
    /// `double` only: width of the inner ring. nil = no inner ring.
    var innerWidth: Double?
    /// `double` only: inset of the inner ring from the outer one (5 pt in the spec).
    var innerInset: Double
    /// `glow` only: radii of the two shadow layers, [r1, r2]. Empty = no glow.
    var glowRadii: [Double]

    /// Style id (rawValue of `PanelBorderChoice`) → spec. `"none"` or unknown → nil (= no border).
    static func from(style: String) -> PanelBorderSpec? {
        switch style {
        case "hairline": return PanelBorderSpec(width: 1,   dash: [],     innerWidth: nil, innerInset: 0, glowRadii: [])
        case "bold":     return PanelBorderSpec(width: 3.5, dash: [],     innerWidth: nil, innerInset: 0, glowRadii: [])
        case "double":   return PanelBorderSpec(width: 2,   dash: [],     innerWidth: 1,   innerInset: 5, glowRadii: [])
        case "dashed":   return PanelBorderSpec(width: 2,   dash: [8, 6], innerWidth: nil, innerInset: 0, glowRadii: [])
        case "glow":     return PanelBorderSpec(width: 2,   dash: [],     innerWidth: nil, innerInset: 0, glowRadii: [6, 12])
        case "none":     return nil
        default:         return nil
        }
    }
}

// MARK: - Setup progress (SettingsView's one-step banner)

/// Per-panel state as observed from `WidgetCenter.currentConfigurations()`.
/// Strings only — Logic stays AppIntents-free so Check can exercise every branch.
///
/// Ticket 0007: the wallpaper / position steps were killed when true-transparent made them
/// unnecessary. `allDone` now reduces to one question: has the user placed at least one Panel
/// widget on the Home Screen? `compute` keeps the same call shape (panel list + flags) so
/// PanelModel doesn't have to change shape, but only `widgetPlaced` is meaningful.
struct SetupProgress: Equatable {
    var widgetPlaced: Bool      // at least one Panel widget on the Home Screen

    var allDone: Bool { widgetPlaced }

    /// widgetBackgrounds: one entry per Panel widget on the Home Screen, rawValue strings
    /// ("transparent" / "gradient"). The other flags are kept for the same call shape but ignored.
    static func compute(widgetBackgrounds: [String], widgetSlots: [String], hasScreenshot: Bool, offsetMoved: Bool) -> SetupProgress {
        return SetupProgress(widgetPlaced: !widgetBackgrounds.isEmpty)
    }
}

// MARK: - Calendar event (widget reads EventKit itself; this is the render model)

struct EventInfo: Equatable {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
}

/// Pure filter/sort used by `CalendarService.upcoming` and exercised end-to-end by Check.
/// Lives in Logic so the widget target can call it without importing AppIntents / EventKit —
/// the rule shape (48-hour window, timed-before-allday at the same start) is a data decision,
/// not an EventKit decision.
enum AgendaPick {
    /// "Upcoming" = ongoing now OR starting within 48 h of `now`. Sorted by start
    /// (timed beats all-day when they share a start, so a meeting at 09:00 sits above
    /// an all-day block on the same day), then capped at `limit`.
    static func pick(_ events: [EventInfo], now: Date, limit: Int) -> [EventInfo] {
        let cutoff = now.addingTimeInterval(48 * 3600)
        let kept = events.filter { e in
            if e.start <= now, now <= e.end { return true }            // ongoing
            return e.start > now && e.start <= cutoff                  // within 48 h
        }
        let sorted = kept.sorted { a, b in
            if a.start != b.start { return a.start < b.start }
            if a.isAllDay != b.isAllDay { return !a.isAllDay }
            return false
        }
        return Array(sorted.prefix(limit))
    }
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
    var defaultTop: Double { Self.measured(screen.height, pro: 88, proMax: 93.7).rounded() }
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

    /// Distance between icon rows on the Home Screen.
    var rowPitch: Double { Self.measured(screen.height, pro: 100, proMax: 108.6) }

    /// Home Screen grid geometry measured on iOS 27.0 (24A434), icon top edges from real screenshots:
    ///   iPhone 17 Pro      402 × 874 pt → first row top 88 pt,   row pitch 100 pt
    ///   iPhone 17 Pro Max  440 × 956 pt → first row top 93.7 pt, row pitch 108.6 pt (both gaps)
    /// A single height ratio was 2.3 pt off on the Pro Max, so other heights are interpolated linearly
    /// through these two points instead.
    static func measured(_ height: Double, pro: Double, proMax: Double) -> Double {
        pro + (height - 874) * (proMax - pro) / (956 - 874)
    }

    /// Top edge (in screen points) for a fixed slot, or nil for `custom` (= use the app's aligned crop).
    func top(for slot: PanelSlotKind) -> Double? {
        slot.rowsDown.map { (defaultTop + Double($0) * rowPitch).rounded() }
    }

    /// Crop rect anchored to an explicit top (in screen points). Horizontally centred;
    /// y clamped so the rect is always inside the screen.
    func rect(top: Double) -> (x: Double, y: Double, width: Double, height: Double) {
        let x = ((screen.width - panel.width) / 2).rounded()
        let maxY = max(screen.height - panel.height, 0)
        let y = min(max(top.rounded(), 0), maxY)
        return (x, y, panel.width, min(panel.height, screen.height))
    }
}
