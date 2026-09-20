// PanelView.swift — the panel itself. Rendered by the widget and, pixel-identical, by the app preview.
//
// Design (v2, 2026-09-21): editorial glass.
//  • Ink scheme adapts to the wallpaper crop: light wallpaper → dark ink on light glass;
//    dark wallpaper → white ink on dark glass. `config.panelScheme` can pin either.
//  • Type: one thin hero numeral per block, everything else micro-caps with tracking. SF Pro by default.
//  • Colour is rationed: blue (temperature) and coral (today / running timer). Everything else is ink.
//
// Two ways to be "transparent":
//  • Full-colour home screen: we draw the user's wallpaper crop as the container background (screenshot method).
//  • iOS 26+ "Clear"/tinted home screen: the system strips our container background and renders us in
//    accented mode on its own glass. We detect `widgetRenderingMode` and draw nothing behind the cards.

import SwiftUI
import WidgetKit
import AppIntents

struct PanelData {
    var date: Date
    var config: PanelConfig
    var weather: WeatherSnapshot?
    var activity: ActivitySnapshot?
    var event: EventInfo?
    var timer: TimerState
    var system: SystemSnapshot?
    var background: UIImage?
    /// systemLarge gets the short version; systemExtraLargePortrait gets everything.
    var compact: Bool = false
    /// Average luminance (0…1) of `background`, measured once where the image is loaded.
    var backgroundLuma: Double? = nil

    /// Wallpaper brightness after the user's dimming slider.
    var effectiveLuma: Double {
        let base = backgroundLuma ?? (background == nil ? 0.26 : 0.45)
        return base * (1 - config.tint)
    }
    /// true = light glass + dark ink (the reference look); false = dark glass + white ink.
    var lightScheme: Bool {
        switch config.panelScheme {
        case "light": return true
        case "dark": return false
        default: return effectiveLuma > 0.46
        }
    }

    static var sample: PanelData {
        var c = PanelConfig()
        c.city = "Taipei"
        c.note = "An A.I. Pin Drops · Hard Fork"
        let now = Date()
        return PanelData(
            date: now, config: c,
            weather: WeatherSnapshot(temperature: 33, high: 35, low: 26, code: 0, isDay: true, fetched: now),
            activity: ActivitySnapshot(steps: 3264, exerciseMinutes: 45, standHours: 6, moveKcal: 320, distanceMeters: 3860),
            event: EventInfo(title: "Morning Meeting", start: now.addingTimeInterval(3600), end: now.addingTimeInterval(3600 * 3.5), isAllDay: false),
            timer: TimerState(endDate: now.addingTimeInterval(312), pausedRemaining: nil),
            system: SystemSnapshot(cpuPercent: 12, memoryUsedBytes: 3_100_000_000, memoryTotalBytes: 8_000_000_000,
                                   diskFreeBytes: 118_000_000_000, diskTotalBytes: 256_000_000_000, network: "wifi", batteryLevel: 0.81, sampled: now),
            background: nil, backgroundLuma: nil)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension UIImage {
    /// Average luminance (Rec. 709) of the whole image, by downsampling to a single pixel.
    var averageLuminance: Double {
        guard let cg = cgImage else { return 0.5 }
        var px: [UInt8] = [0, 0, 0, 0]
        guard let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0.5 }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (0.2126 * Double(px[0]) + 0.7152 * Double(px[1]) + 0.0722 * Double(px[2])) / 255
    }
}

// MARK: - Ink (the whole design system lives here)

struct PanelInk {
    /// Dark ink on light glass.
    var light: Bool
    /// Clear/tinted Home Screen: the system paints everything white on its own glass.
    var accented: Bool

    var primary: Color { accented ? .white : (light ? Color(hex: 0x0B0F14).opacity(0.94) : .white) }
    var secondary: Color { accented ? Color.white.opacity(0.75) : (light ? Color.black.opacity(0.56) : Color.white.opacity(0.74)) }
    var tertiary: Color { accented ? Color.white.opacity(0.5) : (light ? Color.black.opacity(0.34) : Color.white.opacity(0.48)) }
    var hairline: Color { accented ? Color.white.opacity(0.22) : (light ? Color.black.opacity(0.14) : Color.white.opacity(0.22)) }
    var dots: Color { accented ? Color.white.opacity(0.35) : (light ? Color.black.opacity(0.26) : Color.white.opacity(0.35)) }

    var blue: Color { accented ? .white : (light ? Color(hex: 0x2E8FD4) : Color(hex: 0x7FCBFF)) }
    var coral: Color { accented ? .white : (light ? Color(hex: 0xFF4A3D) : Color(hex: 0xFF6A5E)) }

    var sheetFill: Color { light ? Color.white.opacity(0.14) : Color.black.opacity(0.12) }
    var cardFill: Color { light ? Color.white.opacity(0.42) : Color.black.opacity(0.26) }
    var cardStroke: Color { light ? Color.white.opacity(0.62) : Color.white.opacity(0.30) }
    /// Soft halo so bare rows (header, launcher, system) stay legible straight on the wallpaper.
    var halo: Color { light ? Color.white.opacity(0.35) : Color.black.opacity(0.28) }
}

private struct PanelInkKey: EnvironmentKey { static let defaultValue = PanelInk(light: false, accented: false) }
extension EnvironmentValues {
    var panelInk: PanelInk {
        get { self[PanelInkKey.self] }
        set { self[PanelInkKey.self] = newValue }
    }
}

/// Row heights and hero type sizes, per family.
private struct Metrics {
    var header: CGFloat, cards: CGFloat, ribbon: CGFloat, week: CGFloat, timer: CGFloat, launch: CGFloat, system: CGFloat
    var gap: CGFloat, clock: CGFloat, hero: CGFloat, tile: CGFloat
    static let xl = Metrics(header: 90, cards: 140, ribbon: 38, week: 88, timer: 40, launch: 62, system: 36,
                            gap: 7, clock: 64, hero: 54, tile: 50)
    // systemLarge is only 329×345 pt on the smallest phone iOS 27 still runs on, so this set has to
    // fit 345 − 24 (padding) = 321: 64+104+70+52 + 3×6 = 308.
    static let large = Metrics(header: 64, cards: 104, ribbon: 0, week: 70, timer: 0, launch: 52, system: 0,
                               gap: 6, clock: 44, hero: 40, tile: 44)
}
private struct MetricsKey: EnvironmentKey { static let defaultValue = Metrics.xl }
private extension EnvironmentValues {
    var panelMetrics: Metrics {
        get { self[MetricsKey.self] }
        set { self[MetricsKey.self] = newValue }
    }
}

// MARK: - Panel

struct PanelView: View {
    let data: PanelData
    /// true inside WidgetKit (uses containerBackground + real intents); false in the app preview.
    var inWidget: Bool = true
    @Environment(\.widgetRenderingMode) private var renderingMode

    private let pad: CGFloat = 12
    private var accented: Bool { inWidget && renderingMode != .fullColor }
    private var ink: PanelInk { PanelInk(light: data.lightScheme, accented: accented) }
    private var metrics: Metrics { data.compact ? .large : .xl }

    var body: some View {
        content
            .padding(pad)
            .environment(\.panelInk, ink)
            // `.regular` glass follows the colour scheme, not our ink — pin it so a dark wallpaper
            // gets dark glass instead of a grey slab.
            .environment(\.colorScheme, ink.light ? .light : .dark)
            .environment(\.panelMetrics, metrics)
            .environment(\.panelFont, data.config.design)
            // Anything without its own button (header, system row, gaps) opens the app's settings sheet.
            .widgetURL(Launcher.settingsDeepLink)
            .modifier(BackgroundModifier(image: data.background, tint: data.config.tint,
                                         inWidget: inWidget, accented: accented, ink: ink))
    }

    /// Wrap a block in a button that opens the launcher's app directly (OpenAppIntent → OpenURLIntent).
    @ViewBuilder private func open<V: View>(_ id: String, @ViewBuilder _ row: () -> V) -> some View {
        Button(intent: OpenAppIntent(id: id)) { row() }.buttonStyle(.plain)
    }

    @ViewBuilder private var content: some View {
        let m = metrics
        VStack(spacing: m.gap) {
            HeaderRow(date: data.date, showSeconds: data.config.showSeconds).frame(height: m.header)

            if data.config.showWeather || data.config.showCalendar {
                HStack(spacing: 8) {
                    if data.config.showWeather {
                        open("weather") { WeatherCard(weather: data.weather, city: data.config.city) }
                    }
                    if data.config.showCalendar {
                        open("calendar") { DateCard(date: data.date) }
                    }
                }
                .frame(height: m.cards)
            }

            if !data.compact, data.config.showActivity {
                open("fitness") { ActivityRibbon(activity: data.activity) }.frame(height: m.ribbon)
            }
            if data.config.showCalendar {
                open("calendar") { WeekCard(date: data.date, event: data.event) }.frame(height: m.week)
            }
            if !data.compact, data.config.showTimer {
                TimerBar(timer: data.timer, now: data.date, defaultMinutes: data.config.timerMinutes).frame(height: m.timer)
            }
            if data.config.showLaunchers {
                LauncherStrip(ids: data.config.launcherIDs).frame(height: m.launch)
            }
            if !data.compact, data.config.showSystem {
                SystemBar(system: data.system, metrics: data.config.systemMetrics).frame(height: m.system)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct BackgroundModifier: ViewModifier {
    let image: UIImage?
    let tint: Double
    let inWidget: Bool
    let accented: Bool
    let ink: PanelInk

    @ViewBuilder private var fill: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                // No wallpaper yet. WidgetKit always composites the widget onto an opaque backing
                // (verified 2026-09-16: .clear and 1%-alpha both come out solid), so "transparent" on a
                // full-colour Home Screen is only possible by drawing the wallpaper crop ourselves.
                LinearGradient(colors: [Color(hex: 0x1E3A5F), Color(hex: 0x0B1B2B)],
                               startPoint: .top, endPoint: .bottom)
            }
            Color.black.opacity(tint)
            // One faint sheet over the whole panel: it ties the bare rows to the cards without
            // hiding the wallpaper underneath.
            ink.sheetFill
        }
    }

    func body(content: Content) -> some View {
        if inWidget {
            // In accented/Clear mode the system supplies the glass; anything we draw would be tinted white.
            content.containerBackground(for: .widget) { if !accented { fill } }
        } else {
            content
                .background { fill }
                .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        }
    }
}

// MARK: - Type

private struct PanelFontKey: EnvironmentKey { static let defaultValue: Font.Design = .default }
extension EnvironmentValues {
    var panelFont: Font.Design {
        get { self[PanelFontKey.self] }
        set { self[PanelFontKey.self] = newValue }
    }
}
extension PanelConfig {
    var design: Font.Design {
        switch fontDesign { case "rounded": return .rounded; case "serif": return .serif; case "mono": return .monospaced; default: return .default }
    }
}

private struct PanelText: ViewModifier {
    @Environment(\.panelFont) private var design
    let size: CGFloat; let weight: Font.Weight; let tracking: CGFloat
    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design)).tracking(tracking)
    }
}
private extension View {
    /// Body / value type.
    func pf(_ size: CGFloat, _ weight: Font.Weight = .regular, tracking: CGFloat = 0) -> some View {
        modifier(PanelText(size: size, weight: weight, tracking: tracking))
    }
    /// One hero numeral per block: thin, tight, big.
    func hero(_ size: CGFloat) -> some View {
        modifier(PanelText(size: size, weight: .thin, tracking: -size * 0.03))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
    /// The quiet label voice: small, letterspaced, uppercased by the caller.
    func caps(_ size: CGFloat = 9.5, _ weight: Font.Weight = .semibold) -> some View {
        modifier(PanelText(size: size, weight: weight, tracking: size * 0.13))
            .lineLimit(1)
    }
}
private func up(_ s: String) -> String { s.uppercased(with: .current) }
/// A localized label in the micro-caps voice: resolved, then uppercased for the current locale.
private func upKey(_ key: String.LocalizationValue) -> String { up(String(localized: key)) }

/// Dotted rule, the connective tissue of the ribbon and the week strip.
private struct DottedRule: View {
    let color: Color
    var body: some View {
        GeometryReader { g in
            Path { p in
                p.move(to: CGPoint(x: 0, y: g.size.height / 2))
                p.addLine(to: CGPoint(x: g.size.width, y: g.size.height / 2))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.01, 4.5]))
        }
        .frame(height: 2)
    }
}

// MARK: - Glass card

private struct GlassCard<Content: View>: View {
    @Environment(\.panelInk) private var ink
    var radius: CGFloat = 22
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if ink.accented {
                    // System glass already behind us; just a faint rim so blocks read as blocks.
                    shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                } else {
                    // 🔴 Inside WidgetKit `glassEffect` renders its own near-transparent material over
                    // whatever is behind it, so neither its tint nor a fill under it survives (measured
                    // 2026-09-21: white 0.34 vs 0.52 under the glass came out identical on the real widget).
                    // The card therefore paints its own glass: fill + top-left specular + hairline rim.
                    shape.fill(ink.cardFill)
                        .overlay {
                            shape.fill(LinearGradient(colors: [Color.white.opacity(ink.light ? 0.30 : 0.12), .clear],
                                                      startPoint: .topLeading, endPoint: .center))
                        }
                        .overlay { shape.strokeBorder(ink.cardStroke, lineWidth: 0.8) }
                }
            }
    }
}

/// Hairline circular button — the timer transport and the settings gear.
private struct RingButton: View {
    @Environment(\.panelInk) private var ink
    let symbol: String
    var size: CGFloat = 34
    var body: some View {
        Circle()
            .fill(ink.light ? Color.white.opacity(0.30) : Color.white.opacity(0.10))
            .overlay { Circle().strokeBorder(ink.light ? Color.white.opacity(0.7) : Color.white.opacity(0.3), lineWidth: 0.8) }
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.36, weight: .medium))
                    .foregroundStyle(ink.primary)
            }
            .frame(width: size, height: size)
            .widgetAccentable()
    }
}

// MARK: - Header

private struct HeaderRow: View {
    @Environment(\.panelInk) private var ink
    @Environment(\.panelMetrics) private var m
    let date: Date
    let showSeconds: Bool

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if showSeconds, let day = Calendar.current.dateInterval(of: .day, for: date) {
                        // Live, ticking every second, driven by the system — no timeline entries needed.
                        Text(timerInterval: day.start...day.end, pauseTime: nil, countsDown: false, showsHours: true)
                    } else {
                        Text(date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                    }
                }
                .hero(showSeconds ? m.clock * 0.78 : m.clock)
                .foregroundStyle(ink.primary)
                .widgetAccentable()
                Text(up(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())))
                    .caps(10)
                    .foregroundStyle(ink.secondary)
            }
            Spacer(minLength: 8)
            // Settings: opens the app (widgets can only open their own container).
            Link(destination: Launcher.settingsDeepLink) {
                RingButton(symbol: "gearshape", size: 30)
            }
            .accessibilityLabel("Settings")
            .padding(.top, 6)
        }
        .padding(.horizontal, 4)
        .shadow(color: ink.halo, radius: 10, x: 0, y: 0)
    }
}

// MARK: - Weather / date cards

private struct WeatherCard: View {
    @Environment(\.panelInk) private var ink
    @Environment(\.panelMetrics) private var m
    let weather: WeatherSnapshot?
    let city: String?

    var body: some View {
        GlassCard {
            let d: (symbol: String, text: String) = weather?.description ?? (symbol: "cloud.fill", text: "—")
            VStack(spacing: 0) {
                Text(city.map(up) ?? upKey("定位中"))
                    .caps(9)
                    .foregroundStyle(ink.tertiary)
                    .padding(.top, 12)
                Spacer(minLength: 0)
                Image(systemName: d.symbol)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 27, weight: .regular))
                    .foregroundStyle(ink.primary)
                    .widgetAccentable()
                Text(weather.map { "\(Int($0.temperature.rounded()))°" } ?? "--°")
                    .hero(m.hero)
                    .foregroundStyle(ink.blue)
                    .widgetAccentable()
                    .padding(.top, 2)
                Text(LocalizedStringKey(d.text))
                    .pf(15, .regular)
                    .foregroundStyle(ink.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if let w = weather {
                    Text("H \(Int(w.high.rounded()))°   L \(Int(w.low.rounded()))°")
                        .caps(9)
                        .monospacedDigit()
                        .foregroundStyle(ink.tertiary)
                        .padding(.bottom, 12)
                }
            }
            .padding(.horizontal, 10)
        }
    }
}

private struct DateCard: View {
    @Environment(\.panelInk) private var ink
    @Environment(\.panelMetrics) private var m
    let date: Date

    var body: some View {
        GlassCard {
            VStack(spacing: 0) {
                Text(up(date.formatted(.dateTime.month(.wide))))
                    .caps(10)
                    .foregroundStyle(ink.secondary)
                    .padding(.top, 12)
                Spacer(minLength: 0)
                Text(String(Calendar.current.component(.day, from: date)))
                    .hero(m.hero * 1.16)
                    .foregroundStyle(ink.coral)
                    .widgetAccentable()
                Spacer(minLength: 0)
                Text(date.formatted(.dateTime.weekday(.wide)))
                    .pf(17, .bold)
                    .foregroundStyle(ink.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 8)
        }
    }
}

// MARK: - Activity ribbon

private struct ActivityRibbon: View {
    @Environment(\.panelInk) private var ink
    let activity: ActivitySnapshot?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.walk")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ink.primary)
                .widgetAccentable()
            value(activity.map { "\($0.steps)" } ?? "—", upKey("步數"))
            DottedRule(color: ink.dots).frame(minWidth: 24)
            value(activity.map { Self.distance($0.distanceMeters) } ?? "—", upKey("距離"))
            Rings(activity: activity ?? ActivitySnapshot()).frame(width: 28, height: 28)
        }
        .padding(.horizontal, 6)
        .shadow(color: ink.halo, radius: 8)
    }

    /// Localised road distance: 3.9 km in metric, 2.4 mi where miles are used.
    static func distance(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road).locale(.current))
    }

    private func value(_ v: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(v).pf(16, .medium).monospacedDigit().foregroundStyle(ink.primary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).caps(8.5).foregroundStyle(ink.tertiary)
        }
        .fixedSize()
    }
}

private struct Rings: View {
    let activity: ActivitySnapshot
    var body: some View {
        ZStack {
            ring(activity.moveFraction, Color(hex: 0xFF375F), inset: 0)
            ring(activity.exerciseFraction, Color(hex: 0xA8FF3E), inset: 5)
            ring(activity.standFraction, Color(hex: 0x28E5FF), inset: 10)
        }
        .widgetAccentable()
    }
    private func ring(_ fraction: Double, _ color: Color, inset: CGFloat) -> some View {
        ZStack {
            Circle().stroke(color.opacity(0.22), lineWidth: 2.6)
            Circle().trim(from: 0, to: max(fraction, 0.02))
                .stroke(color, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(inset)
    }
}

// MARK: - Week + next event

private struct WeekCard: View {
    @Environment(\.panelInk) private var ink
    let date: Date
    let event: EventInfo?

    var body: some View {
        GlassCard {
            let cal = Calendar.current
            let days = Self.week(of: date, cal: cal)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(days, id: \.self) { d in
                        Text(up(cal.shortWeekdaySymbols[cal.component(.weekday, from: d) - 1]))
                            .caps(8.5)
                            .foregroundStyle(ink.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 11)
                Rectangle().fill(ink.hairline).frame(height: 0.7).padding(.top, 7)
                HStack(spacing: 0) {
                    ForEach(days, id: \.self) { d in
                        let today = cal.isDate(d, inSameDayAs: date)
                        Text(String(cal.component(.day, from: d)))
                            .pf(14, today ? .semibold : .regular)
                            .monospacedDigit()
                            .foregroundStyle(today ? (ink.accented ? ink.primary : .white) : ink.primary)
                            .frame(width: 24, height: 24)
                            .background { if today { Circle().fill(ink.accented ? Color.white.opacity(0.35) : ink.coral) } }
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 8)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Circle().fill(event == nil ? ink.tertiary : ink.coral).frame(width: 4, height: 4)
                    Text(Self.line(event, now: date))
                        .caps(9.5, .medium)
                        .foregroundStyle(ink.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 11)
            }
            .padding(.horizontal, 10)
        }
    }

    private static func week(of date: Date, cal: Calendar) -> [Date] {
        guard let start = cal.dateInterval(of: .weekOfYear, for: date)?.start else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    /// "TOMORROW, 16:00 · Bournemouth – Liverpool"
    private static func line(_ event: EventInfo?, now: Date) -> String {
        guard let e = event else { return upKey("今天沒有行程") }
        let cal = Calendar.current
        let day: String
        if cal.isDateInToday(e.start) { day = String(localized: "今天") }
        else if cal.isDateInTomorrow(e.start) { day = String(localized: "明天") }
        else { day = e.start.formatted(.dateTime.weekday(.abbreviated)) }
        let when = e.isAllDay ? String(localized: "全天")
                              : e.start.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute())
        return up("\(day), \(when) · \(e.title)")
    }
}

// MARK: - Timer

private struct TimerBar: View {
    @Environment(\.panelInk) private var ink
    let timer: TimerState
    let now: Date
    let defaultMinutes: Int

    var body: some View {
        let phase = timer.phase(at: now)
        HStack(spacing: 8) {
            Button(intent: TimerToggleIntent()) {
                RingButton(symbol: phase == .running ? "pause.fill" : "play.fill", size: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(phase == .running ? "Pause" : "Play")
            Button(intent: TimerStopIntent()) {
                RingButton(symbol: "xmark", size: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            Spacer(minLength: 6)
            Text(upKey("計時器"))
                .caps(9.5)
                .foregroundStyle(ink.tertiary)
            Group {
                switch phase {
                case .running:
                    Text(timerInterval: now...timer.endDate!, countsDown: true)
                case .paused:
                    Text(TimerState.format(timer.pausedRemaining!))
                case .idle:
                    Text("\(defaultMinutes):00")
                }
            }
            .hero(30)
            .foregroundStyle(phase == .running ? ink.coral : ink.primary)
            .widgetAccentable()
            .frame(minWidth: 74, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .shadow(color: ink.halo, radius: 8)
    }
}

// MARK: - Launchers

private struct LauncherStrip: View {
    @Environment(\.panelInk) private var ink
    @Environment(\.panelMetrics) private var m
    let ids: [String]

    var body: some View {
        HStack(spacing: 0) {
            let launchers = ids.prefix(5).compactMap(Launcher.byID)
            ForEach(launchers) { l in
                Button(intent: OpenAppIntent(id: l.id)) {
                    Tile(name: "tile-\(l.id)", symbol: l.symbol, size: m.tile)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LocalizedStringKey(l.name))
                .frame(maxWidth: .infinity)
            }
            if launchers.isEmpty {
                Text("在 app 裡挑五個 app").pf(14).foregroundStyle(ink.secondary)
            }
        }
        .padding(.horizontal, 2)
        .shadow(color: ink.halo, radius: 10, y: 2)
    }
}

/// A launcher tile: pre-rendered by Apple's own icon renderer (tools/make-tiles.py → Tiles.xcassets),
/// so it carries the same Liquid Glass as a real Home Screen icon. In Clear/tinted mode the system
/// wants flat white content, so fall back to the symbol on a translucent slab.
private struct Tile: View {
    @Environment(\.panelInk) private var ink
    let name: String
    let symbol: String
    let size: CGFloat
    var body: some View {
        if ink.accented {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(Color.white.opacity(0.18))
                .overlay { Image(systemName: symbol).font(.system(size: size * 0.46, weight: .medium)).foregroundStyle(.white) }
                .frame(width: size, height: size)
        } else {
            Image(name)
                .resizable()
                .interpolation(.high)
                .widgetAccentedRenderingMode(.fullColor)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - System

private struct SystemBar: View {
    @Environment(\.panelInk) private var ink
    let system: SystemSnapshot?
    let metrics: [String]

    var body: some View {
        HStack(spacing: 0) {
            let ids = Array(metrics.prefix(4))
            ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                if index > 0 {
                    Rectangle().fill(ink.hairline).frame(width: 0.7, height: 16)
                }
                cell(id).frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
        .shadow(color: ink.halo, radius: 8)
    }

    private func cell(_ id: String) -> some View {
        let m: SystemMetric = SystemMetric.byID(id) ?? SystemMetric.all[0]
        let c: (value: String, label: String, tile: String, symbol: String) =
            system?.cell(for: id) ?? (value: "—", label: m.name, tile: m.tile, symbol: m.symbol)
        return VStack(spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: c.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ink.secondary)
                Text(c.value)
                    .pf(14, .medium).monospacedDigit()
                    .foregroundStyle(ink.primary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Text(upKey(String.LocalizationValue(c.label)))
                .caps(8.5)
                .foregroundStyle(ink.tertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .widgetAccentable()
    }
}
