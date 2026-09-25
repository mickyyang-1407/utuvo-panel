// WeatherService.swift — open-meteo fetch + App Group cache. Compiled into BOTH targets:
// the widget reads it on every timeline, and the app calls it on launch / foreground so
// (a) the cache is warm before the widget's first timeline and (b) on China-model iPhones
// the per-app "Wireless Data" prompt is raised by the app — an extension can't show it,
// and until it's answered the extension's requests stall instead of failing (ticket 0011).

import Foundation

enum WeatherService {
    static func cached() -> WeatherSnapshot? {
        Shared.defaults.codable(WeatherSnapshot.self, forKey: Shared.Key.weather)
    }

    /// Short, non-waiting session: a widget timeline can't afford URLSession.shared's 60 s default.
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 5
        c.timeoutIntervalForResource = 8
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    /// Cached for 30 minutes; falls back to the cache on any failure or after `deadline` seconds.
    static func current(config: PanelConfig, deadline: Double = 6) async -> WeatherSnapshot? {
        guard config.showWeather else { return nil }
        // A cache from before ticket 0010 has no hourly data; treat it as stale so the hourly strip
        // shows up on the first timeline after the update instead of up to 30 min later.
        if let c = cached(), !c.hourly.isEmpty, Date().timeIntervalSince(c.fetched) < 30 * 60 { return c }
        // No location yet → Taipei, so the row never sits empty.
        let lat = config.latitude ?? 25.033, lon = config.longitude ?? 121.565
        let url = WeatherSnapshot.url(latitude: lat, longitude: lon)
        let fresh: WeatherSnapshot? = await Deadline.run(seconds: deadline, fallback: nil) {
            guard let (data, _) = try? await session.data(from: url),
                  let snap = WeatherSnapshot.parse(data) else { return nil }
            Shared.defaults.set(codable: snap, forKey: Shared.Key.weather)
            return snap
        }
        return fresh ?? cached()
    }
}
