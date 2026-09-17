// PanelView.swift — the panel itself. Rendered by the widget and, pixel-identical, by the app preview.
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

    static var sample: PanelData {
        var c = PanelConfig()
        c.city = "Taipei"
        c.note = "An A.I. Pin Drops · Hard Fork"
        let now = Date()
        return PanelData(
            date: now, config: c,
            weather: WeatherSnapshot(temperature: 33, high: 35, low: 26, code: 0, isDay: true, fetched: now),
            activity: ActivitySnapshot(steps: 3264, exerciseMinutes: 45, standHours: 6, moveKcal: 320),
            event: EventInfo(title: "Morning Meeting", start: now.addingTimeInterval(3600), end: now.addingTimeInterval(3600 * 3.5), isAllDay: false),
            timer: TimerState(endDate: now.addingTimeInterval(312), pausedRemaining: nil),
            system: SystemSnapshot(cpuPercent: 12, memoryUsedBytes: 3_100_000_000, memoryTotalBytes: 8_000_000_000,
                                   diskFreeBytes: 118_000_000_000, diskTotalBytes: 256_000_000_000, network: "wifi", batteryLevel: 0.81, sampled: now),
            background: nil)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Panel

struct PanelView: View {
    let data: PanelData
    /// true inside WidgetKit (uses containerBackground + real intents); false in the app preview.
    var inWidget: Bool = true
    @Environment(\.widgetRenderingMode) private var renderingMode

    private let rowSpacing: CGFloat = 8
    private let pad: CGFloat = 12
    private var accented: Bool { inWidget && renderingMode != .fullColor }

    var body: some View {
        content
            .padding(pad)
            .environment(\.panelAccented, accented)
            .environment(\.panelFont, data.config.design)
            // Anything without its own button (header, system row, gaps) opens the app's settings sheet.
            .widgetURL(Launcher.settingsDeepLink)
            .modifier(BackgroundModifier(image: data.background, tint: data.config.tint, inWidget: inWidget, accented: accented))
    }

    /// Wrap a row in a button that opens the launcher's app directly (OpenAppIntent → OpenURLIntent).
    @ViewBuilder private func open<V: View>(_ id: String, @ViewBuilder _ row: () -> V) -> some View {
        Button(intent: OpenAppIntent(id: id)) { row() }.buttonStyle(.plain)
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: rowSpacing) {
            HeaderRow(date: data.date, showSeconds: data.config.showSeconds).frame(height: 84)
            // Rows that stand for an app open that app (via the container-app hand-off, like the launcher tiles).
            if data.config.showCalendar { open("calendar") { CalendarRow(date: data.date, event: data.event) }.frame(height: 68) }
            if data.config.showWeather { open("weather") { WeatherRow(weather: data.weather, city: data.config.city) }.frame(height: 92) }
            if !data.compact {
                if data.config.showActivity { open("fitness") { ActivityRow(activity: data.activity) }.frame(height: 68) }
                if data.config.showTimer { TimerRow(timer: data.timer, now: data.date, defaultMinutes: data.config.timerMinutes).frame(height: 58) }
            }
            if data.config.showLaunchers { LauncherRow(ids: data.config.launcherIDs).frame(height: 68) }
            if !data.compact, data.config.showSystem { SystemRow(system: data.system, metrics: data.config.systemMetrics).frame(height: 62) }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }
}

private struct PanelAccentedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var panelAccented: Bool {
        get { self[PanelAccentedKey.self] }
        set { self[PanelAccentedKey.self] = newValue }
    }
}

private struct BackgroundModifier: ViewModifier {
    let image: UIImage?
    let tint: Double
    let inWidget: Bool
    let accented: Bool

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

// MARK: - Glass card

private struct Card<Content: View>: View {
    @Environment(\.panelAccented) private var accented
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        content()
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if accented {
                    // System glass already behind us; just a faint rim so rows read as rows.
                    shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                } else {
                    shape.fill(Color.clear)
                        .glassEffect(.regular.tint(Color.black.opacity(0.18)), in: shape)
                        .overlay {
                            // Liquid-glass rim: brighter top-left, fading to nothing.
                            shape.strokeBorder(
                                LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.08), Color.white.opacity(0.25)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 0.8)
                        }
                }
            }
    }
}

/// Round glass button rendered by ictool on the circles platform (tools/make-tiles.py → btn-*).
private struct GlassButton: View {
    @Environment(\.panelAccented) private var accented
    let name: String      // btn-gear / btn-play / btn-pause / btn-stop
    let symbol: String    // fallback for Clear/tinted mode
    var size: CGFloat = 40
    var body: some View {
        if accented {
            Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.6)
                .overlay { Image(systemName: symbol).font(.system(size: size * 0.38, weight: .bold)).foregroundStyle(.white) }
                .frame(width: size, height: size)
        } else {
            Image(name).resizable().interpolation(.high).widgetAccentedRenderingMode(.fullColor)
                .frame(width: size, height: size)
        }
    }
}

private struct PanelFontKey: EnvironmentKey { static let defaultValue: Font.Design = .rounded }
extension EnvironmentValues {
    var panelFont: Font.Design {
        get { self[PanelFontKey.self] }
        set { self[PanelFontKey.self] = newValue }
    }
}
extension PanelConfig {
    var design: Font.Design {
        switch fontDesign { case "default": return .default; case "serif": return .serif; case "mono": return .monospaced; default: return .rounded }
    }
}
/// Text font in the panel's chosen design. Digits always get the same design so clocks and temps match the labels.
private struct PanelText: ViewModifier {
    @Environment(\.panelFont) private var design
    let size: CGFloat; let weight: Font.Weight
    func body(content: Content) -> some View { content.font(.system(size: size, weight: weight, design: design)) }
}
private extension View {
    func pf(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> some View { modifier(PanelText(size: size, weight: weight)) }
}

// MARK: - Rows

private struct HeaderRow: View {
    let date: Date
    let showSeconds: Bool
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if showSeconds, let day = Calendar.current.dateInterval(of: .day, for: date) {
                        // Live, ticking every second, driven by the system — no timeline entries needed.
                        Text(timerInterval: day.start...day.end, pauseTime: nil, countsDown: false, showsHours: true)
                    } else {
                        Text(date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                    }
                }
                .pf(showSeconds ? 44 : 54, .medium)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .widgetAccentable()
                Text(date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .pf(15, .medium)
                    .opacity(0.85)
            }
            Spacer()
            // Settings: opens the app (widgets can only open their own container).
            Link(destination: Launcher.settingsDeepLink) {
                GlassButton(name: "btn-gear", symbol: "gearshape.fill", size: 30)
                    .opacity(0.85)
                    .padding(.top, 4)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 6)
    }
}

private struct CalendarRow: View {
    let date: Date
    let event: EventInfo?
    var body: some View {
        Card {
            HStack(spacing: 12) {
                DateTile(date: date)
                Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    if let event {
                        Text(event.title)
                            .pf(15, .semibold)
                            .foregroundStyle(Color(hex: 0x9CCBFF))
                            .widgetAccentable()
                            .lineLimit(1)
                        if event.isAllDay {
                            Text("全天").pf(16, .medium)
                        } else {
                            Text("\(event.start, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())–\(event.end, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())")
                                .pf(17, .medium).monospacedDigit()
                        }
                    } else {
                        Text("今天沒有行程").pf(15, .semibold).foregroundStyle(Color(hex: 0x9CCBFF)).widgetAccentable()
                        Text("休息一下").pf(16, .medium).opacity(0.8)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct DateTile: View {
    @Environment(\.panelAccented) private var accented
    let date: Date
    var body: some View {
        VStack(spacing: 0) {
            Text(date, format: .dateTime.month(.abbreviated))
                .font(.system(size: 10, weight: .bold))
                .textCase(.uppercase)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(accented ? Color.white.opacity(0.35) : Color(hex: 0xFF3B30))
            Text(date, format: .dateTime.day())
                .pf(22, .bold)
                .foregroundStyle(accented ? .white : .black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(accented ? Color.white.opacity(0.15) : Color.white)
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct WeatherRow: View {
    let weather: WeatherSnapshot?
    let city: String?
    var body: some View {
        Card {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill").font(.system(size: 11))
                        if let city { Text(city).pf(14, .semibold) } else { Text("定位中").pf(14, .semibold) }
                    }
                    Text(weather.map { "\(Int($0.temperature.rounded()))°" } ?? "--°")
                        .pf(48, .medium)
                        .monospacedDigit()
                        .widgetAccentable()
                }
                Spacer(minLength: 8)
                let d: (symbol: String, text: String) = weather?.description ?? (symbol: "cloud.fill", text: "—")
                HStack(spacing: 10) {
                    Tile(name: WeatherSnapshot.tileName(for: d.symbol), symbol: d.symbol, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey(d.text)).pf(17, .semibold).lineLimit(1).minimumScaleFactor(0.7)
                        if let w = weather {
                            HStack(spacing: 6) {
                                Text("H \(Int(w.high.rounded()))°").pf(14, .semibold)
                                Text("L \(Int(w.low.rounded()))°").pf(14, .semibold).opacity(0.6)
                            }
                            .monospacedDigit()
                        }
                    }
                }
            }
        }
    }
}

private struct ActivityRow: View {
    let activity: ActivitySnapshot?
    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 22) {
                stat("步數", Color(hex: 0xFF375F), activity.map { "\($0.steps)" } ?? "—", "")
                stat("運動", Color(hex: 0xA8FF3E), activity.map { "\($0.exerciseMinutes)" } ?? "—", "min")
                stat("站立", Color(hex: 0x28E5FF), activity.map { "\($0.standHours)" } ?? "—", "hr")
                Spacer(minLength: 0)
                Rings(activity: activity ?? ActivitySnapshot()).frame(width: 46, height: 46)
            }
        }
    }
    private func stat(_ label: LocalizedStringKey, _ color: Color, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).pf(12, .semibold).foregroundStyle(color).widgetAccentable()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).pf(26, .bold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                if !unit.isEmpty { Text(unit).pf(13, .semibold).opacity(0.8) }
            }
        }
    }
}

private struct Rings: View {
    let activity: ActivitySnapshot
    var body: some View {
        ZStack {
            ring(activity.moveFraction, Color(hex: 0xFF375F), inset: 0)
            ring(activity.exerciseFraction, Color(hex: 0xA8FF3E), inset: 7)
            ring(activity.standFraction, Color(hex: 0x28E5FF), inset: 14)
        }
        .widgetAccentable()
    }
    private func ring(_ fraction: Double, _ color: Color, inset: CGFloat) -> some View {
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: 5)
            Circle().trim(from: 0, to: max(fraction, 0.02))
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(inset)
    }
}

private struct TimerRow: View {
    let timer: TimerState
    let now: Date
    let defaultMinutes: Int
    var body: some View {
        Card {
            HStack(spacing: 10) {
                let phase = timer.phase(at: now)
                let orange = Color(hex: 0xFF9F0A)
                Button(intent: TimerToggleIntent()) {
                    GlassButton(name: phase == .running ? "btn-pause" : "btn-play", symbol: phase == .running ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(phase == .running ? "Pause" : "Play")
                Button(intent: TimerStopIntent()) {
                    GlassButton(name: "btn-stop", symbol: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                Spacer()
                Text("計時器").pf(15, .semibold).foregroundStyle(orange).widgetAccentable()
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
                .pf(30, .medium)
                .monospacedDigit()
                .foregroundStyle(orange)
                .widgetAccentable()
                .frame(minWidth: 76, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
        }
    }
}

private struct LauncherRow: View {
    @Environment(\.panelAccented) private var accented
    let ids: [String]
    var body: some View {
        Card {
            HStack(spacing: 0) {
                let launchers = ids.prefix(5).compactMap(Launcher.byID)
                ForEach(launchers) { l in
                    Button(intent: OpenAppIntent(id: l.id)) {
                        Tile(name: "tile-\(l.id)", symbol: l.symbol, size: 52)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(LocalizedStringKey(l.name))
                    .frame(maxWidth: .infinity)
                }
                if launchers.isEmpty {
                    Text("在 app 裡挑五個 app").pf(15, .medium).opacity(0.7)
                }
            }
        }
    }
}

/// A launcher tile: pre-rendered by Apple's own icon renderer (tools/make-tiles.py → Tiles.xcassets),
/// so it carries the same Liquid Glass as a real Home Screen icon. In Clear/tinted mode the system
/// wants flat white content, so fall back to the symbol on a translucent slab.
private struct Tile: View {
    @Environment(\.panelAccented) private var accented
    let name: String
    let symbol: String
    let size: CGFloat
    var body: some View {
        if accented {
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

private struct SystemRow: View {
    let system: SystemSnapshot?
    let metrics: [String]
    var body: some View {
        Card {
            HStack(spacing: 0) {
                ForEach(metrics.prefix(4).map { $0 }, id: \.self) { id in
                    metricCell(id)
                }
            }
        }
    }
    private func metricCell(_ id: String) -> some View {
        let m: SystemMetric = SystemMetric.byID(id) ?? SystemMetric.all[0]
        let c: (value: String, label: String, tile: String, symbol: String) = system?.cell(for: id) ?? (value: "—", label: m.name, tile: m.tile, symbol: m.symbol)
        return cell(c.tile, c.symbol, c.value, LocalizedStringKey(c.label))
    }
    private func cell(_ tile: String, _ symbol: String, _ value: String, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Tile(name: tile, symbol: symbol, size: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).pf(14, .bold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(label).pf(10, .semibold).opacity(0.7).lineLimit(1).minimumScaleFactor(0.7)
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}
