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
    @Published private(set) var screenshotDark: UIImage?
    @Published private(set) var background: UIImage?
    @Published private(set) var backgroundDark: UIImage?
    /// Cached so the preview does not re-measure the crop on every redraw.
    private(set) var backgroundLuma: Double?
    private(set) var backgroundLumaDark: Double?
    @Published private(set) var activity: ActivitySnapshot?
    /// One-step onboarding banner state (above the preview). Refreshed via `refreshSetup()` —
    /// on `.task`, every `scenePhase` change back to `.active`, and after screenshot changes.
    @Published private(set) var setup: SetupProgress = SetupProgress(widgetPlaced: false)
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
        screenshotDark = UIImage(contentsOfFile: Shared.screenshotDarkURL.path)
        backgroundDark = UIImage(contentsOfFile: Shared.backgroundDarkURL.path)
        backgroundLumaDark = backgroundDark?.averageLuminance
        activity = Shared.defaults.codable(ActivitySnapshot.self, forKey: Shared.Key.activity)
        location.delegate = self
        refreshStatuses()
        migrateScreenshotIntoSharedContainer()
    }

    /// One-time: any device that already has Documents/screenshot.jpg but no shared
    /// panel-screenshot.jpg gets the JPEG and the matching screenPoints written to the
    /// app group so the widget's transparent/top/row1/row2 choices have something to crop.
    private func migrateScreenshotIntoSharedContainer() {
        guard FileManager.default.fileExists(atPath: screenshotURL.path),
              !FileManager.default.fileExists(atPath: Shared.screenshotURL.path)
        else { return }
        let s = Self.screenSize
        try? FileManager.default.copyItem(at: screenshotURL, to: Shared.screenshotURL)
        Shared.defaults.set([Double(s.width), Double(s.height)], forKey: Shared.Key.screenPoints)
        reloadWidget()
    }

    // MARK: Widget

    func reloadWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: Shared.widgetKind)
    }

    /// Reads every configured Panel widget from WidgetCenter and recomputes the one-step banner.
    /// Caller-driven (`.task`, scenePhase → .active, screenshot change).
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
                // widgetSlots / hasScreenshot / offsetMoved are ignored by SetupProgress now;
                // pass empty / false to keep the call shape stable.
                self.setup = SetupProgress.compute(
                    widgetBackgrounds: backgrounds,
                    widgetSlots: [],
                    hasScreenshot: self.screenshot != nil,
                    offsetMoved: false
                )
            }
        }
    }

    var previewData: PanelData {
        var d = PanelData.sample
        d.config = config
        d.background = background
        d.backgroundDark = backgroundDark
        d.activity = activity ?? d.activity
        // Real weather (with hourly) once the widget has fetched it; the sample otherwise.
        if let w = Shared.defaults.codable(WeatherSnapshot.self, forKey: Shared.Key.weather), !w.hourly.isEmpty { d.weather = w }
        d.timer = TimerState.load()
        d.system = Shared.defaults.codable(SystemSnapshot.self, forKey: Shared.Key.system) ?? d.system
        d.backgroundLuma = backgroundLuma
        d.backgroundLumaDark = backgroundLumaDark
        d.borderStyle = config.borderStyle
        d.borderColor = config.borderColor
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

    func setScreenshot(_ data: Data, dark: Bool = false) {
        guard let picked = UIImage(data: data)?.normalized() else { return }
        // A screenshot is already screen-shaped. A wallpaper *photo* is not: iOS shows it aspect-filled
        // and centred, so reproduce that here and the user never has to take a screenshot.
        let image = picked.aspectFilled(to: Self.screenSize, scale: 3)
        // First image: start from where the widget sits as the first item on a page (measured 88 pt down).
        if !dark, screenshot == nil { config.backgroundOffset = placement.defaultOffset }
        if dark {
            screenshotDark = image
            // Dark variant lives only in the shared container — the app preview reads it via `backgroundDark`.
            try? image.jpegData(compressionQuality: 0.95)?.write(to: Shared.screenshotDarkURL, options: .atomic)
            let s = Self.screenSize
            Shared.defaults.set([Double(s.width), Double(s.height)], forKey: Shared.Key.screenPoints)
        } else {
            screenshot = image
            try? image.jpegData(compressionQuality: 0.95)?.write(to: screenshotURL, options: .atomic)
            // Same JPEG goes to the shared app-group container so the widget can crop a region out
            // when the user picks "Top of the page" / "One row down" / "Two rows down" in the Edit Widget sheet.
            try? image.jpegData(compressionQuality: 0.95)?.write(to: Shared.screenshotURL, options: .atomic)
            let s = Self.screenSize
            Shared.defaults.set([Double(s.width), Double(s.height)], forKey: Shared.Key.screenPoints)
        }
        recrop()
        refreshSetup()
    }

    func clearScreenshot() {
        screenshot = nil
        screenshotDark = nil
        background = nil
        backgroundDark = nil
        backgroundLuma = nil
        backgroundLumaDark = nil
        try? FileManager.default.removeItem(at: screenshotURL)
        try? FileManager.default.removeItem(at: Shared.backgroundURL)
        try? FileManager.default.removeItem(at: Shared.screenshotURL)
        try? FileManager.default.removeItem(at: Shared.backgroundDarkURL)
        try? FileManager.default.removeItem(at: Shared.screenshotDarkURL)
        reloadWidget()
        refreshSetup()
    }

    /// Remove only the dark variant — leave the light crop untouched.
    func clearDarkScreenshot() {
        screenshotDark = nil
        backgroundDark = nil
        backgroundLumaDark = nil
        try? FileManager.default.removeItem(at: Shared.backgroundDarkURL)
        try? FileManager.default.removeItem(at: Shared.screenshotDarkURL)
        reloadWidget()
    }

    /// Re-cut the panel-sized rectangle out of the screenshot. Called on every offset change.
    func recrop() {
        if let shot = screenshot, let cg = shot.cgImage {
            let p = placement
            let r = p.rect(offset: config.backgroundOffset)
            let scale = Double(cg.width) / p.screen.width   // screenshot pixels per point
            let crop = CGRect(x: r.x * scale, y: r.y * scale, width: r.width * scale, height: r.height * scale)
                .intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            if let cut = cg.cropping(to: crop) {
                background = UIImage(cgImage: cut)
                backgroundLuma = background?.averageLuminance
                try? background?.jpegData(compressionQuality: 0.9)?.write(to: Shared.backgroundURL, options: .atomic)
            }
        }
        if let shot = screenshotDark, let cg = shot.cgImage {
            let p = placement
            let r = p.rect(offset: config.backgroundOffset)
            let scale = Double(cg.width) / p.screen.width   // screenshot pixels per point
            let crop = CGRect(x: r.x * scale, y: r.y * scale, width: r.width * scale, height: r.height * scale)
                .intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            if let cut = cg.cropping(to: crop) {
                backgroundDark = UIImage(cgImage: cut)
                backgroundLumaDark = backgroundDark?.averageLuminance
                try? backgroundDark?.jpegData(compressionQuality: 0.9)?.write(to: Shared.backgroundDarkURL, options: .atomic)
            }
        }
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
