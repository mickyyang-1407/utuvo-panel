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
    @Published private(set) var screenshot: UIImage?
    @Published private(set) var background: UIImage?
    /// Cached so the preview does not re-measure the crop on every redraw.
    private(set) var backgroundLuma: Double?
    @Published private(set) var activity: ActivitySnapshot?
    /// Settings sheet; the widget's gear deep link opens it directly.
    @Published var showSettings = false

    @Published private(set) var calendarStatus = "未詢問"
    @Published private(set) var locationStatus = "未詢問"
    @Published private(set) var healthStatus = "未詢問"

    private let location = CLLocationManager()
    private let health = HKHealthStore()
    private var screenshotURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("screenshot.jpg")
    }

    override init() {
        config = PanelConfig.load()
        super.init()
        screenshot = UIImage(contentsOfFile: screenshotURL.path)
        background = UIImage(contentsOfFile: Shared.backgroundURL.path)
        backgroundLuma = background?.averageLuminance
        activity = Shared.defaults.codable(ActivitySnapshot.self, forKey: Shared.Key.activity)
        location.delegate = self
        refreshStatuses()
    }

    // MARK: Widget

    func reloadWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: Shared.widgetKind)
    }

    var previewData: PanelData {
        var d = PanelData.sample
        d.config = config
        d.background = background
        d.activity = activity ?? d.activity
        d.timer = TimerState.load()
        d.system = Shared.defaults.codable(SystemSnapshot.self, forKey: Shared.Key.system) ?? d.system
        d.backgroundLuma = backgroundLuma
        if config.city == nil { d.config.city = "Taipei" }
        return d
    }

    // MARK: Geometry

    static var screenSize: CGSize {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.screen.bounds.size ?? CGSize(width: 402, height: 874)
    }

    /// Prefer the size the widget provider reported; estimate until it has run once.
    var placement: PanelPlacement {
        let s = Self.screenSize
        if let v = Shared.defaults.array(forKey: Shared.Key.displaySize + ".xlPortrait") as? [Double], v.count == 2, v[0] > 0, v[1] > 0 {
            return PanelPlacement(screen: (s.width, s.height), panel: (v[0], v[1]))
        }
        return PanelPlacement.estimated(screenWidth: s.width, screenHeight: s.height)
    }

    var panelSizeIsMeasured: Bool {
        (Shared.defaults.array(forKey: Shared.Key.displaySize + ".xlPortrait") as? [Double])?.count == 2
    }

    // MARK: Wallpaper

    func setScreenshot(_ data: Data) {
        guard let picked = UIImage(data: data)?.normalized() else { return }
        // A screenshot is already screen-shaped. A wallpaper *photo* is not: iOS shows it aspect-filled
        // and centred, so reproduce that here and the user never has to take a screenshot.
        let image = picked.aspectFilled(to: Self.screenSize, scale: 3)
        // First image: start from where the widget sits as the first item on a page (measured 88 pt down).
        if screenshot == nil { config.backgroundOffset = placement.defaultOffset }
        screenshot = image
        try? image.jpegData(compressionQuality: 0.95)?.write(to: screenshotURL, options: .atomic)
        recrop()
    }

    func clearScreenshot() {
        screenshot = nil
        background = nil
        backgroundLuma = nil
        try? FileManager.default.removeItem(at: screenshotURL)
        try? FileManager.default.removeItem(at: Shared.backgroundURL)
        reloadWidget()
    }

    /// Re-cut the panel-sized rectangle out of the screenshot. Called on every offset change.
    func recrop() {
        guard let shot = screenshot, let cg = shot.cgImage else { return }
        let p = placement
        let r = p.rect(offset: config.backgroundOffset)
        let scale = Double(cg.width) / p.screen.width   // screenshot pixels per point
        let crop = CGRect(x: r.x * scale, y: r.y * scale, width: r.width * scale, height: r.height * scale)
            .intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard let cut = cg.cropping(to: crop) else { return }
        let image = UIImage(cgImage: cut)
        background = image
        backgroundLuma = image.averageLuminance
        try? image.jpegData(compressionQuality: 0.9)?.write(to: Shared.backgroundURL, options: .atomic)
        reloadWidget()
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
        let read: Set<HKObjectType> = [
            HKQuantityType(.stepCount),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.appleExerciseTime),
            HKQuantityType(.appleStandTime),
            HKObjectType.activitySummaryType(),
        ]
        health.requestAuthorization(toShare: [], read: read) { [weak self] _, _ in
            Task { @MainActor in await self?.refreshHealth() }
        }
    }

    func refreshHealth() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        var snap = activity ?? ActivitySnapshot()
        snap.day = Date()
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())

        // Steps: cumulative sum for today.
        let steps: Double? = await withCheckedContinuation { cont in
            let pred = HKQuery.predicateForSamples(withStart: start, end: Date())
            let q = HKStatisticsQuery(quantityType: HKQuantityType(.stepCount), quantitySamplePredicate: pred, options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: .count()))
            }
            health.execute(q)
        }
        if let steps { snap.steps = Int(steps) }

        // Distance walked/run today — the ribbon shows it next to the step count.
        let distance: Double? = await withCheckedContinuation { cont in
            let pred = HKQuery.predicateForSamples(withStart: start, end: Date())
            let q = HKStatisticsQuery(quantityType: HKQuantityType(.distanceWalkingRunning), quantitySamplePredicate: pred, options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: .meter()))
            }
            health.execute(q)
        }
        if let distance { snap.distanceMeters = distance }

        // Rings: today's activity summary carries both totals and goals.
        let summary: HKActivitySummary? = await withCheckedContinuation { cont in
            var comps = cal.dateComponents([.year, .month, .day], from: Date())
            comps.calendar = cal
            let pred = HKQuery.predicateForActivitySummary(with: comps)
            let q = HKActivitySummaryQuery(predicate: pred) { _, summaries, _ in
                cont.resume(returning: summaries?.first)
            }
            health.execute(q)
        }
        if let s = summary {
            snap.moveKcal = s.activeEnergyBurned.doubleValue(for: .kilocalorie())
            snap.moveGoal = max(s.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()), 1)
            snap.exerciseMinutes = Int(s.appleExerciseTime.doubleValue(for: .minute()))
            snap.exerciseGoal = max(s.appleExerciseTimeGoal.doubleValue(for: .minute()), 1)
            snap.standHours = Int(s.appleStandHours.doubleValue(for: .count()))
            snap.standGoal = max(s.appleStandHoursGoal.doubleValue(for: .count()), 1)
        }
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
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in locationStatus = String(localized: "定位失敗：\(error.localizedDescription)") }
    }
}

// MARK: - UIImage

extension UIImage {
    /// Scale-to-fill `size` (in points, at `scale`) and centre-crop — the same fit iOS uses for wallpapers.
    /// Returns self when the aspect already matches within 1%.
    func aspectFilled(to size: CGSize, scale: CGFloat) -> UIImage {
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let ratio = self.size.width / self.size.height, want = target.width / target.height
        if abs(ratio - want) / want < 0.01 { return self }
        let s = max(target.width / self.size.width, target.height / self.size.height)
        let w = self.size.width * s, h = self.size.height * s
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(x: (target.width - w) / 2, y: (target.height - h) / 2, width: w, height: h))
        }
    }

    /// Bake EXIF orientation into the pixels so CGImage cropping works in display space.
    func normalized() -> UIImage {
        if imageOrientation == .up, scale == 1 { return self }
        let renderer = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}
