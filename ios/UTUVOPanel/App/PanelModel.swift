// PanelModel.swift — app-side state: config, wallpaper crop, and the three data sources
// (calendar, location, health) the widget cannot request for itself.

import SwiftUI
import WidgetKit
import EventKit
import CoreLocation
import HealthKit
import UIKit

@MainActor
final class PanelModel: NSObject, ObservableObject {
    @Published var config: PanelConfig {
        didSet { if config != oldValue { config.save(); reloadWidget() } }
    }
    @Published private(set) var activity: ActivitySnapshot?
    /// One-step onboarding banner state (above the preview). Refreshed via `refreshSetup()` —
    /// on `.task`, every `scenePhase` change back to `.active`, and after setup changes.
    @Published private(set) var setup: SetupProgress = SetupProgress(widgetPlaced: false)
    /// Settings sheet; the widget's gear deep link opens it directly.
    @Published var showSettings = false

    @Published private(set) var calendarStatus = "未詢問"
    @Published private(set) var locationStatus = "未詢問"
    @Published private(set) var healthStatus = "未詢問"

    private let location = CLLocationManager()
    private let health = HKHealthStore()

    override init() {
        config = PanelConfig.load()
        super.init()
        activity = Shared.defaults.codable(ActivitySnapshot.self, forKey: Shared.Key.activity)
        location.delegate = self
        refreshStatuses()
    }

    // MARK: Widget

    func reloadWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: Shared.widgetKind)
    }

    /// The app fetches weather itself (ticket 0011): on China-model iPhones only the app can raise
    /// the "Wireless Data" prompt, and a warm cache means the widget's first timeline has data.
    func refreshWeather() async {
        let before = WeatherService.cached()?.fetched
        _ = await WeatherService.current(config: config, deadline: 10)
        if WeatherService.cached()?.fetched != before {
            objectWillChange.send()
            reloadWidget()
        }
    }

    /// Reads every configured Panel widget from WidgetCenter and recomputes the one-step banner.
    /// Caller-driven (`.task`, scenePhase → .active).
    func refreshSetup() {
        Task { [weak self] in
            let info = (try? await WidgetCenter.shared.currentConfigurations()) ?? []
            var backgrounds: [String] = []
            for i in info where i.kind == Shared.widgetKind {
                let intent = i.widgetConfigurationIntent(of: PanelWidgetIntent.self)
                let bg = intent?.backgroundValue ?? PanelWidgetIntent.backgroundDefault
                backgrounds.append(bg.rawValue)
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.setup = SetupProgress.compute(widgetBackgrounds: backgrounds)
            }
        }
    }

    var previewData: PanelData {
        var d = PanelData.sample
        d.config = config
        d.activity = activity ?? d.activity
        // Real weather (with hourly) once the widget has fetched it; the sample otherwise.
        if let w = Shared.defaults.codable(WeatherSnapshot.self, forKey: Shared.Key.weather), !w.hourly.isEmpty { d.weather = w }
        d.timer = TimerState.load()
        d.system = Shared.defaults.codable(SystemSnapshot.self, forKey: Shared.Key.system) ?? d.system
        d.borderStyle = config.borderStyle
        d.borderColor = config.borderColor
        if config.city == nil { d.config.city = "Taipei" }
        return d
    }

    // MARK: Geometry

    var panelSize: CGSize {
        if let v = Shared.defaults.array(forKey: Shared.Key.displaySize + ".xlPortrait") as? [Double], v.count == 2, v[0] > 0, v[1] > 0 {
            return CGSize(width: v[0], height: v[1])
        }
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let s = scene?.screen.bounds.size ?? CGSize(width: 402, height: 874)
        let w = s.width - 52
        return CGSize(width: w, height: (w * 1.618).rounded())
    }

    // MARK: Permissions

    func refreshStatuses() {
        calendarStatus = Self.describe(EKEventStore.authorizationStatus(for: .event))
        locationStatus = Self.describe(location.authorizationStatus) + (config.city.map { " · \($0)" } ?? "")
        healthStatus = HKHealthStore.isHealthDataAvailable()
            ? (activity == nil ? String(localized: "未讀取") : String(localized: "已讀取 \(activity!.steps) 步"))
            : String(localized: "此裝置沒有健康資料")
    }

    private static func describe(_ s: EKAuthorizationStatus) -> String {
        switch s {
        case .fullAccess: return String(localized: "已授權")
        case .writeOnly: return String(localized: "只能寫入（不夠）")
        case .denied, .restricted: return String(localized: "已拒絕，去設定打開")
        default: return String(localized: "未詢問")
        }
    }
    private static func describe(_ s: CLAuthorizationStatus) -> String {
        switch s {
        case .authorizedWhenInUse, .authorizedAlways: return String(localized: "已授權")
        case .denied, .restricted: return String(localized: "已拒絕，去設定打開")
        default: return String(localized: "未詢問")
        }
    }

    func requestCalendar() {
        Task {
            _ = try? await EKEventStore().requestFullAccessToEvents()
            refreshStatuses()
            reloadWidget()
        }
    }

    func requestLocation() {
        switch location.authorizationStatus {
        case .notDetermined: location.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: location.requestLocation()
        default: refreshStatuses()
        }
    }

    // MARK: Health

    func requestHealth() {
        guard HKHealthStore.isHealthDataAvailable() else { refreshStatuses(); return }
        health.requestAuthorization(toShare: [], read: HealthReader.readTypes) { [weak self] _, _ in
            Task { @MainActor in await self?.refreshHealth() }
        }
    }

    func refreshHealth() async {
        let now = Date()
        let fresh = await HealthReader.today(store: health, now: now)
        // Same `resolve` the widget uses — yesterday's cache never masquerades as today.
        let snap = ActivitySnapshot.resolve(fresh: fresh, cached: activity, now: now)
        activity = snap
        Shared.defaults.set(codable: snap, forKey: Shared.Key.activity)
        refreshStatuses()
        reloadWidget()
    }
}

// MARK: - CLLocationManagerDelegate

extension PanelModel: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            refreshStatuses()
            if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            config.latitude = loc.coordinate.latitude
            config.longitude = loc.coordinate.longitude
            // Force a fresh fetch for the new coordinates.
            Shared.defaults.removeObject(forKey: Shared.Key.weather)
            let placemarks = try? await CLGeocoder().reverseGeocodeLocation(loc)
            if let city = placemarks?.first?.locality ?? placemarks?.first?.administrativeArea {
                config.city = city
            }
            refreshStatuses()
            await refreshWeather()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in locationStatus = String(localized: "定位失敗：\(error.localizedDescription)") }
    }
}
