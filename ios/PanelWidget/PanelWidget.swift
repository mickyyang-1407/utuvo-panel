// PanelWidget.swift — the WidgetKit extension: timeline provider + configuration.

import WidgetKit
import SwiftUI
import EventKit

struct PanelEntry: TimelineEntry {
    let date: Date
    let data: PanelData
}

struct PanelProvider: TimelineProvider {
    func placeholder(in context: Context) -> PanelEntry {
        var d = PanelData.sample
        d.compact = context.family != .systemExtraLargePortrait
        return PanelEntry(date: d.date, data: d)
    }

    func getSnapshot(in context: Context, completion: @escaping (PanelEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task { completion(await build(context: context, fetchWeather: false).first!) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PanelEntry>) -> Void) {
        Task {
            let entries = await build(context: context, fetchWeather: true)
            let refresh = Date().addingTimeInterval(15 * 60)
            completion(Timeline(entries: entries, policy: .after(refresh)))
        }
    }

    /// One entry per minute for the next 30 minutes so the clock ticks without a reload.
    private func build(context: Context, fetchWeather: Bool) async -> [PanelEntry] {
        // The app cannot ask WidgetKit for the family size; the provider knows it. Leave it where the app can read it.
        Shared.defaults.set([Double(context.displaySize.width), Double(context.displaySize.height)],
                            forKey: Shared.Key.displaySize + "." + familyKey(context.family))

        let config = PanelConfig.load()
        let compact = context.family != .systemExtraLargePortrait
        let now = Date()
        let minute = Calendar.current.dateInterval(of: .minute, for: now)?.start ?? now

        let weather = fetchWeather ? await WeatherService.current(config: config) : WeatherService.cached()
        let activity = Shared.defaults.codable(ActivitySnapshot.self, forKey: Shared.Key.activity)
        let event = config.showCalendar ? CalendarService.nextEvent(from: now) : nil
        let timer = TimerState.load()
        let system = config.showSystem ? await SystemStats.sample() : nil
        if let system { Shared.defaults.set(codable: system, forKey: Shared.Key.system) }
        let background = UIImage(contentsOfFile: Shared.backgroundURL.path)
        // Measured once per timeline: decides light-glass-on-dark-ink vs the reverse.
        let luma = background?.averageLuminance

        var entries: [PanelEntry] = []
        for i in 0..<30 {
            let date = minute.addingTimeInterval(TimeInterval(i * 60))
            let data = PanelData(date: date, config: config, weather: weather, activity: activity,
                                 event: event, timer: timer, system: system, background: background,
                                 compact: compact, backgroundLuma: luma)
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

// MARK: - Weather

enum WeatherService {
    static func cached() -> WeatherSnapshot? {
        Shared.defaults.codable(WeatherSnapshot.self, forKey: Shared.Key.weather)
    }

    /// Cached for 30 minutes; falls back to the cache on any failure.
    static func current(config: PanelConfig) async -> WeatherSnapshot? {
        guard config.showWeather else { return nil }
        if let c = cached(), Date().timeIntervalSince(c.fetched) < 30 * 60 { return c }
        // No location yet → Taipei, so the row never sits empty.
        let lat = config.latitude ?? 25.033, lon = config.longitude ?? 121.565
        do {
            let (data, _) = try await URLSession.shared.data(from: WeatherSnapshot.url(latitude: lat, longitude: lon))
            if let snap = WeatherSnapshot.parse(data) {
                Shared.defaults.set(codable: snap, forKey: Shared.Key.weather)
                return snap
            }
        } catch {}
        return cached()
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
}

// MARK: - Widget

struct PanelWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Shared.widgetKind, provider: PanelProvider()) { entry in
            PanelView(data: entry.data, inWidget: true)
        }
        .configurationDisplayName("UTUVO Panel")
        .description("時間、行程、天氣、活動、計時器、常用 app，一塊透明的面板。")
        .supportedFamilies([.systemExtraLargePortrait, .systemLarge])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}

@main
struct PanelWidgetBundle: WidgetBundle {
    var body: some Widget {
        PanelWidget()
    }
}
