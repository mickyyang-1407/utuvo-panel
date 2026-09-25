// PanelWidget.swift — the WidgetKit extension: timeline provider + configuration.

import WidgetKit
import SwiftUI
import EventKit
import HealthKit

struct PanelEntry: TimelineEntry {
    let date: Date
    let data: PanelData
}

struct PanelProvider: AppIntentTimelineProvider {
    typealias Intent = PanelWidgetIntent
    typealias Entry = PanelEntry

    func placeholder(in context: Context) -> PanelEntry {
        var d = PanelData.sample
        d.compact = context.family != .systemExtraLargePortrait
        return PanelEntry(date: d.date, data: d)
    }

    func snapshot(for configuration: PanelWidgetIntent, in context: Context) async -> PanelEntry {
        if context.isPreview { return placeholder(in: context) }
        return await build(context: context, intent: configuration, fetchWeather: false).first!
    }

    func timeline(for configuration: PanelWidgetIntent, in context: Context) async -> Timeline<PanelEntry> {
        let entries = await build(context: context, intent: configuration, fetchWeather: true)
        let refresh = Date().addingTimeInterval(15 * 60)
        return Timeline(entries: entries, policy: .after(refresh))
    }

    /// One entry per minute for the next 30 minutes so the clock ticks without a reload.
    private func build(context: Context, intent: PanelWidgetIntent, fetchWeather: Bool) async -> [PanelEntry] {
        // The app cannot ask WidgetKit for the family size; the provider knows it. Leave it where the app can read it.
        Shared.defaults.set([Double(context.displaySize.width), Double(context.displaySize.height)],
                            forKey: Shared.Key.displaySize + "." + familyKey(context.family))

        let config = PanelConfig.load()
        let compact = context.family != .systemExtraLargePortrait
        let now = Date()
        let minute = Calendar.current.dateInterval(of: .minute, for: now)?.start ?? now

        // Every async source below is capped (ticket 0011): a timeline that never returns leaves
        // the widget on its redacted placeholder, so a stalled source falls back to its cache.
        // All slow sources run concurrently, so the worst case is the longest deadline (~6 s),
        // not their sum.
        async let weatherRead: WeatherSnapshot? = fetchWeather
            ? WeatherService.current(config: config) : WeatherService.cached()
        async let activityRead: ActivitySnapshot? = config.showActivity
            ? Deadline.run(seconds: 4, fallback: nil) { await HealthReader.today(now: now) }
            : nil
        async let systemRead: SystemSnapshot? = config.showSystem
            ? Deadline.run(seconds: 2.5, fallback: nil) { await SystemStats.sample() }
            : nil
        // EventKit's events(matching:) is synchronous; capped the same way.
        async let eventRead: EventInfo? = config.showCalendar
            ? Deadline.run(seconds: 2, fallback: nil) { CalendarService.nextEvent(from: now) }
            : nil
        // Agenda layout only: the bottom strip paints up to 3 events; hourly / spread don't read
        // this field, so we skip the EK query in those modes to keep the widget snappy.
        async let eventsRead: [EventInfo] = (config.bottomLayout == "agenda" && config.showCalendar)
            ? Deadline.run(seconds: 2, fallback: []) { CalendarService.upcoming(from: now, limit: 3) }
            : []
        let weather = await weatherRead
        // Read fresh on every timeline so the widget reflects today's numbers even when the
        // app hasn't been opened. If HealthKit is unavailable / locked we keep the cached
        // snapshot (only when it's still from today — `resolve` refuses yesterday's data).
        let cachedActivity = Shared.defaults.codable(ActivitySnapshot.self, forKey: Shared.Key.activity)
        let freshActivity = await activityRead
        if let freshActivity {
            Shared.defaults.set(codable: freshActivity, forKey: Shared.Key.activity)
        }
        let activity = ActivitySnapshot.resolve(fresh: freshActivity, cached: cachedActivity, now: now)
        let event = await eventRead
        let events = await eventsRead
        let timer = TimerState.load()
        let cachedSystem = Shared.defaults.codable(SystemSnapshot.self, forKey: Shared.Key.system)
        let freshSystem = await systemRead
        if let freshSystem { Shared.defaults.set(codable: freshSystem, forKey: Shared.Key.system) }
        let system = config.showSystem ? (freshSystem ?? cachedSystem) : nil
        // True-transparent mode: the widget composites straight onto the live wallpaper (no dim,
        // no crop of our own). Skip the wallpaper load entirely — PanelView hands the system
        // Color.clear as the container background. Gradient still draws its own fallback.
        let trueTransparent = intent.backgroundValue == .transparent

        var entries: [PanelEntry] = []
        for i in 0..<30 {
            let date = minute.addingTimeInterval(TimeInterval(i * 60))
            let data = PanelData(date: date, config: config, weather: weather, activity: activity,
                                 event: event, events: events, timer: timer, system: system,
                                 compact: compact,
                                 trueTransparent: trueTransparent,
                                 borderStyle: PanelBorderPick.resolve(intentValue: intent.borderValue.rawValue,
                                                                       appValue: config.borderStyle),
                                 borderColor: PanelBorderPick.resolve(intentValue: intent.borderColorValue.rawValue,
                                                                       appValue: config.borderColor))
            entries.append(PanelEntry(date: date, data: data))
        }
        // If a timer ends inside this window, add an entry right at that moment so the row flips to idle.
        if let end = timer.endDate, end > now, end < minute.addingTimeInterval(30 * 60) {
            var data = entries[0].data
            data.date = end
            entries.append(PanelEntry(date: end, data: data))
            entries.sort { $0.date < $1.date }
        }
        return entries
    }


    private func familyKey(_ f: WidgetFamily) -> String {
        switch f {
        case .systemExtraLargePortrait: return "xlPortrait"
        case .systemLarge: return "large"
        default: return "other"
        }
    }
}

// MARK: - Calendar

enum CalendarService {
    /// First event that is ongoing or starts within 24 h. Timed events win over all-day ones.
    static func nextEvent(from now: Date) -> EventInfo? {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return nil }
        let store = EKEventStore()
        let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(24 * 3600), calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
        let pick = events.first { !$0.isAllDay } ?? events.first
        return pick.map { EventInfo(title: $0.title ?? "（無標題）", start: $0.startDate, end: $0.endDate, isAllDay: $0.isAllDay) }
    }

    /// Up to `limit` events for the "agenda" bottom layout — ongoing, or starting within 48 h.
    /// The 48 h window is wider than `nextEvent`'s 24 h so the strip still has something to show
    /// mid-afternoon (the next day's events are usually the only thing on the screen).
    static func upcoming(from now: Date, limit: Int) -> [EventInfo] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let store = EKEventStore()
        let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(48 * 3600), calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .map { EventInfo(title: $0.title ?? "（無標題）", start: $0.startDate, end: $0.endDate, isAllDay: $0.isAllDay) }
        return AgendaPick.pick(events, now: now, limit: limit)
    }
}

// MARK: - Widget

struct PanelWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Shared.widgetKind, intent: PanelWidgetIntent.self, provider: PanelProvider()) { entry in
            PanelView(data: entry.data, inWidget: true)
        }
        .configurationDisplayName("UTUVO Panel")
        .description("時間、行程、天氣、活動、計時器、常用 app，一塊透明的面板。")
        .supportedFamilies([.systemExtraLargePortrait, .systemLarge])
        .contentMarginsDisabled()
        // `.preferredBackgroundStyle(.transparent)` is a SPI on WidgetConfiguration — the
        // symbols don't ship in the public .swiftinterface. We stage a copy of WidgetKit.framework
        // with the declarations appended (tools/make-widgetkit-spi.sh) and put it on
        // FRAMEWORK_SEARCH_PATHS. On the default Home Screen this is what lets the wallpaper
        // (incl. shuffle) show through with no dim. Evidence: device-probe4-P4P5-preferred-transparent-no-dim.jpg.
        .preferredBackgroundStyle(.transparent)
    }
}

@main
struct PanelWidgetBundle: WidgetBundle {
    var body: some Widget {
        PanelWidget()
    }
}
