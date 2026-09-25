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
    /// Upcoming events for the "agenda" bottom layout (3 rows). Empty for hourly / spread;
    /// populated by the widget provider only when `bottomLayout == "agenda"`. Renderer
    /// also uses it for `WeekCard`'s multi-line mode — see `WeekCard.init`.
    var events: [EventInfo] = []
    var timer: TimerState
    var system: SystemSnapshot?
    /// systemLarge gets the short version; systemExtraLargePortrait gets everything.
    var compact: Bool = false
    /// True when the user picked "transparent" in Edit Widget AND `.preferredBackgroundStyle(.transparent)`
    /// is in effect. In this mode the system composites the widget straight onto the wallpaper (no dim),
    /// and the view paints `Color.clear` as the container background.
    var trueTransparent: Bool = false
    /// Border style rawValue (`PanelBorderChoice`). "none" or unknown → PanelView draws nothing.
    var borderStyle: String = "none"
    /// Border colour rawValue (`PanelBorderColorChoice`). "ink" → follows the current ink; others → hex.
    var borderColor: String = "white"

    /// Wallpaper brightness after the user's dimming slider.
    /// Base luminance is constant 0.26 (matching when background was nil), keeping ink identical.
    var effectiveLuma: Double {
        0.26 * (1 - config.tint)
    }
    /// true = light glass + dark ink (the reference look); false = dark glass + white ink.
    var lightScheme: Bool {
        PanelInkPick.lightScheme(trueTransparent: trueTransparent,
                                  panelScheme: config.panelScheme,
                                  effectiveLuma: effectiveLuma)
    }

    static var sample: PanelData {
        var c = PanelConfig()
        c.city = "Taipei"
        c.note = "An A.I. Pin Drops · Hard Fork"
        let now = Date()
        return PanelData(
            date: now, config: c,
            weather: WeatherSnapshot(temperature: 33, high: 35, low: 26, code: 0, isDay: true, fetched: now,
                                     hourly: (1...8).map { i in
                                         let t = Calendar.current.dateInterval(of: .hour, for: now)!.start.addingTimeInterval(Double(i) * 3600)
                                         return .init(time: t, temperature: 33 - Double(i) * 0.6, code: [0, 1, 2, 2, 3, 61, 3, 2][i - 1], isDay: true)
                                     }),
            activity: ActivitySnapshot(steps: 3264, exerciseMinutes: 45, standHours: 6, moveKcal: 320, distanceMeters: 3860),
            event: EventInfo(title: "Morning Meeting", start: now.addingTimeInterval(3600), end: now.addingTimeInterval(3600 * 3.5), isAllDay: false),
            events: [EventInfo(title: "Morning Meeting", start: now.addingTimeInterval(3600), end: now.addingTimeInterval(3600 * 3.5), isAllDay: false),
                     EventInfo(title: "Mix review", start: now.addingTimeInterval(3600 * 26), end: now.addingTimeInterval(3600 * 27), isAllDay: false),
                     EventInfo(title: "Studio day", start: Calendar.current.startOfDay(for: now).addingTimeInterval(3600 * 48), end: Calendar.current.startOfDay(for: now).addingTimeInterval(3600 * 72), isAllDay: true)],
            timer: TimerState(endDate: now.addingTimeInterval(312), pausedRemaining: nil),
            system: SystemSnapshot(cpuPercent: 12, memoryUsedBytes: 3_100_000_000, memoryTotalBytes: 8_000_000_000,
                                   diskFreeBytes: 118_000_000_000, diskTotalBytes: 256_000_000_000, network: "wifi", batteryLevel: 0.81, sampled: now))
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
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
    /// Height of the "Hourly" bottom strip (the 6-up next-hours row). 0 on `large`
    /// because the bottom-layout pickers don't apply to systemLarge.
    var hourly: CGFloat
    static let xl = Metrics(header: 76, cards: 150, ribbon: 38, week: 88, timer: 40, launch: 62, system: 36,
                            gap: 7, clock: 64, hero: 54, tile: 50, hourly: 62)
    // systemLarge is only 329×345 pt on the smallest phone iOS 27 still runs on, so this set has to
    // fit 345 − 24 (padding) = 321: 52+112+70+52 + 3×6 = 304.
    static let large = Metrics(header: 52, cards: 112, ribbon: 0, week: 70, timer: 0, launch: 52, system: 0,
                               gap: 6, clock: 44, hero: 40, tile: 44, hourly: 0)
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
    private var resolved: PanelData { data }
    private var ink: PanelInk { PanelInk(light: resolved.lightScheme, accented: accented) }
    private var metrics: Metrics { resolved.compact ? .large : .xl }

    var body: some View {
        content
            .padding(pad)
            .environment(\.panelInk, ink)
            // `.regular` glass follows the colour scheme, not our ink — pin it so a dark wallpaper
            // gets dark glass instead of a grey slab.
            .environment(\.colorScheme, ink.light ? .light : .dark)
            .environment(\.panelMetrics, metrics)
            .environment(\.panelFont, resolved.config.design)
            // Anything without its own button (header, system row, gaps) opens the app's settings sheet.
            .widgetURL(Launcher.settingsDeepLink)
            .modifier(BackgroundModifier(tint: resolved.config.tint,
                                         inWidget: inWidget, accented: accented, ink: ink,
                                         trueTransparent: resolved.trueTransparent))
            .modifier(BorderModifier(style: resolved.borderStyle, colorID: resolved.borderColor,
                                     ink: ink, accented: accented, inWidget: inWidget))
    }

    /// Wrap a block in a button that opens the launcher's app directly (OpenAppIntent → OpenURLIntent).
    @ViewBuilder private func open<V: View>(_ id: String, @ViewBuilder _ row: () -> V) -> some View {
        Button(intent: OpenAppIntent(id: id)) { row() }.buttonStyle(.plain)
    }

    /// Rows have fixed heights; what's left over depends on the device (the XL portrait panel is
    /// ~592 pt on a 17 Pro, ~609 pt on a 17 Pro Max). The bottom layouts only get that slack.
    private var content: some View {
        GeometryReader { geo in
            rows(slack: max(0, geo.size.height - fixedRowsHeight))
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }

    /// Sum of the fixed-height rows that are on, plus the gaps between them.
    private var fixedRowsHeight: CGFloat {
        let m = metrics, c = resolved.config, compact = resolved.compact
        var h: [CGFloat] = [m.header]
        if c.showWeather || c.showCalendar { h.append(m.cards) }
        if !compact, c.showActivity { h.append(m.ribbon) }
        if c.showCalendar { h.append(m.week) }
        if !compact, c.showTimer { h.append(m.timer) }
        if c.showLaunchers { h.append(m.launch) }
        if !compact, c.showSystem { h.append(m.system) }
        return h.reduce(0, +) + m.gap * CGFloat(h.count - 1)
    }

    @ViewBuilder private func rows(slack: CGFloat) -> some View {
        let m = metrics
        // The three "bottom" layouts only apply to extra-large portrait (systemLarge stays unchanged).
        let bottomLayout = resolved.config.bottomLayout
        let applyBottom = !resolved.compact
        let isSpread = applyBottom && bottomLayout == "spread"
        let isAgenda = applyBottom && bottomLayout == "agenda"
        // Hourly strip only paints when there's data (no hourly payload = fall back to a plain
        // bottom edge, same visual as spread). nextHours returns [] when payload is missing or empty.
        let hourlyPoints: [WeatherSnapshot.HourlyPoint] = applyBottom && bottomLayout == "hourly"
            ? WeatherSnapshot.nextHours(resolved.weather?.hourly ?? [], after: resolved.date)
            : []
        // Agenda grows the week card into the slack (≤ 62 pt); each extra event line needs ~14 pt.
        let weeklyExtra: CGFloat = isAgenda ? min(62, slack) : 0
        let agendaEvents = isAgenda ? Array(resolved.events.prefix(1 + Int(weeklyExtra / 14))) : []
        // Hourly strip gets the slack minus one gap, capped at m.hourly; too little room → no strip.
        let hourlyHeight = min(m.hourly, slack - m.gap)
        let showHourly = !hourlyPoints.isEmpty && hourlyHeight >= 40
        // Spread mode manages its own spacing (flexible Spacers between rows); the other modes
        // rely on VStack(spacing:) and only need the single bottom Spacer to nudge contents up.
        VStack(spacing: isSpread ? 0 : m.gap) {
            HeaderRow(date: resolved.date, showSeconds: resolved.config.showSeconds).frame(height: m.header)
            if isSpread { Spacer(minLength: m.gap) }

            if resolved.config.showWeather || resolved.config.showCalendar {
                HStack(spacing: 8) {
                    if resolved.config.showCalendar {
                        open("calendar") { DateCard(date: resolved.date) }
                    }
                    if resolved.config.showWeather {
                        open("weather") { WeatherCard(weather: resolved.weather, city: resolved.config.city) }
                    }
                }
                .frame(height: m.cards)
                if isSpread { Spacer(minLength: m.gap) }
            }
            // Hourly sits right under today's weather card (Micky 09-22 picked this over the bottom).
            if showHourly {
                open("weather") { HourlyStrip(points: hourlyPoints, compact: hourlyHeight < 54) }.frame(height: hourlyHeight)
            }

            if !resolved.compact, resolved.config.showActivity {
                open("fitness") { ActivityRibbon(activity: resolved.activity) }.frame(height: m.ribbon)
                if isSpread { Spacer(minLength: m.gap) }
            }
            if resolved.config.showCalendar {
                open("calendar") {
                    WeekCard(date: resolved.date,
                             // single-line goes away when the agenda list takes over the bottom
                             event: isAgenda ? nil : resolved.event,
                             events: agendaEvents)
                }
                .frame(height: m.week + weeklyExtra)
                if isSpread { Spacer(minLength: m.gap) }
            }
            if !resolved.compact, resolved.config.showTimer {
                TimerBar(timer: resolved.timer, now: resolved.date, defaultMinutes: resolved.config.timerMinutes).frame(height: m.timer)
                if isSpread { Spacer(minLength: m.gap) }
            }
            if resolved.config.showLaunchers {
                LauncherStrip(ids: resolved.config.launcherIDs).frame(height: m.launch)
                if isSpread { Spacer(minLength: m.gap) }
            }
            if !resolved.compact, resolved.config.showSystem {
                SystemBar(system: resolved.system, metrics: resolved.config.systemMetrics).frame(height: m.system)
                if isSpread { Spacer(minLength: m.gap) }
            }
            if isSpread {
                // Final spacer mirrors the inter-row ones; the whole chain distributes slack
                // evenly because they're all flex Spacers with the same minLength.
                Spacer(minLength: m.gap)
            } else {
                Spacer(minLength: 0)
            }
        }
    }
}

private struct BackgroundModifier: ViewModifier {
    let tint: Double
    let inWidget: Bool
    let accented: Bool
    let ink: PanelInk
    /// True when the user picked "transparent" + `.preferredBackgroundStyle(.transparent)` is in
    /// effect. The system transparent container lets the real wallpaper show through with no dim.
    let trueTransparent: Bool

    @ViewBuilder private var fill: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x1E3A5F), Color(hex: 0x0B1B2B)],
                           startPoint: .top, endPoint: .bottom)
            Color.black.opacity(tint)
            // One faint sheet over the whole panel: it ties the bare rows to the cards without
            // hiding the wallpaper underneath.
            ink.sheetFill
        }
    }

    func body(content: Content) -> some View {
        if inWidget {
            if trueTransparent {
                // 0007: the dim slider now affects true-transparent too — tint=0 keeps the wallpaper
                // straight through, tint>0 paints a translucent black veil so light wallpapers don't
                // bleach the ink. Handed to the system via containerBackground so the wallpaper
                // composites through wherever alpha < 1.
                content.containerBackground(for: .widget) { Color.black.opacity(tint) }
            } else if accented {
                // In accented/Clear mode the system supplies the glass; anything we draw would be tinted white.
                content.containerBackground(for: .widget) { Color.clear }
            } else {
                content.containerBackground(for: .widget) { fill }
            }
        } else {
            content
                .background { fill }
                .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        }
    }
}

// MARK: - Border (overlay drawn last so it sits on the panel's outermost edge)

private struct BorderModifier: ViewModifier {
    let style: String
    let colorID: String
    let ink: PanelInk
    let accented: Bool
    let inWidget: Bool

    private var spec: PanelBorderSpec? { PanelBorderSpec.from(style: style) }

    private var resolvedColor: Color {
        // Accented (Clear / tinted Home Screen): the system paints everything white, so the border
        // becomes a soft white halo on top of the system glass — `.widgetAccentable()` so it picks
        // up the user's tint.
        if accented { return Color.white.opacity(0.6) }
        switch colorID {
        case "white": return Color(hex: 0xFFFFFF)
        case "black": return Color(hex: 0x000000)
        case "ink":   return ink.primary
        case "coral": return Color(hex: 0xFF453A)
        case "gold":  return Color(hex: 0xE3C58A)
        case "sky":   return Color(hex: 0x64D2FF)
        default:      return Color.white
        }
    }

    /// Same shape as the BackgroundModifier's container: ContainerRelativeShape so the widget
    /// matches whatever corner radius the system gives it; the app preview uses 36 pt continuous.
    @ViewBuilder
    private func ring(color: Color, style: StrokeStyle) -> some View {
        if inWidget {
            ContainerRelativeShape().strokeBorder(color, style: style)
        } else {
            RoundedRectangle(cornerRadius: 36, style: .continuous).strokeBorder(color, style: style)
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if let spec {
            let color = resolvedColor
            let dash = spec.dash.map { CGFloat($0) }
            ring(color: color,
                 style: StrokeStyle(lineWidth: CGFloat(spec.width),
                                    lineCap: style == "dashed" ? .round : .butt,
                                    dash: dash))
                .overlay {
                    if let iw = spec.innerWidth {
                        // The outer shape is type-erased by `ring`, so we inset the inner one
                        // visually with `padding(innerInset)` — the stroke lands `innerInset`
                        // pt inside the outer ring instead of using `Shape.inset(by:)`.
                        ring(color: color, style: StrokeStyle(lineWidth: CGFloat(iw)))
                            .padding(CGFloat(spec.innerInset))
                    }
                }
                // Two-layer glow: shadow radii come from `spec.glowRadii`. Anything missing = no shadow.
                .shadow(color: spec.glowRadii.count >= 1 ? color : .clear,
                        radius: spec.glowRadii.first ?? 0)
                .shadow(color: spec.glowRadii.count >= 2 ? color.opacity(0.5) : .clear,
                        radius: spec.glowRadii.dropFirst().first ?? 0)
                .applyAccentable(accented)
                .allowsHitTesting(false)
        }
    }

    func body(content: Content) -> some View {
        content.overlay { overlay }
    }
}

private extension View {
    /// Conditionally wrap with `widgetAccentable()`. `.widgetAccentable` is the public API that
    /// hands the view back to the system in Clear / tinted mode so it picks up the user's tint.
    @ViewBuilder func applyAccentable(_ on: Bool) -> some View {
        if on { self.widgetAccentable() } else { self }
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
            Group {
                if showSeconds, let day = Calendar.current.dateInterval(of: .day, for: date) {
                    // Live, ticking every second, driven by the system — no timeline entries needed.
                    // The timer drops/unpads the hour ("35:17" at 00:35:17, "1:05:03"); ClockPrefix puts
                    // the missing "0"/"00:" in front. It only changes on minute boundaries, and there is
                    // one timeline entry per minute. (A masked per-minute timer froze after entry swaps.)
                    let hm = Calendar.current.dateComponents([.hour, .minute], from: date)
                    HStack(spacing: 0) {
                        Text(verbatim: ClockPrefix.forTime(hour: hm.hour ?? 0, minute: hm.minute ?? 0))
                        Text(timerInterval: day.start...day.end, pauseTime: nil, countsDown: false, showsHours: true)
                    }
                } else {
                    Text(date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                }
            }
            .hero(showSeconds ? m.clock * 0.78 : m.clock)
            .foregroundStyle(ink.primary)
            .widgetAccentable()
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
    /// Single "next up" event — used by every layout except the agenda bottom, which feeds
    /// `events` instead so the line can grow into a 3-row list.
    let event: EventInfo?
    /// Upcoming events for the "agenda" bottom layout. Non-empty enables the multi-line mode
    /// below; otherwise the card falls through to its single-line + `event` rendering.
    var events: [EventInfo] = []

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
                if events.isEmpty {
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
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        // Index ids: two events can share a start (all-day ones all start at 00:00).
                        ForEach(Array(events.enumerated()), id: \.offset) { _, e in
                            HStack(spacing: 6) {
                                Circle().fill(ink.coral).frame(width: 4, height: 4)
                                Text(Self.line(e, now: date))
                                    .caps(9.5, .medium)
                                    .foregroundStyle(ink.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.bottom, 11)
                }
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

// MARK: - Hourly (the "hourly" bottom layout)

/// Up to 6 upcoming hours as a glass strip — one column per hour: HH caps, monochrome weather
/// glyph, integer temperature. Empty `points` is filtered before this view is constructed, so
/// we don't paint an empty card. Tapping the whole strip opens Weather (matches the existing
/// `WeatherCard` link in the row above it).
private struct HourlyStrip: View {
    @Environment(\.panelInk) private var ink
    let points: [WeatherSnapshot.HourlyPoint]
    /// < 54 pt of room: two-line cells instead of three.
    var compact = false

    var body: some View {
        GlassCard {
            HStack(spacing: 0) {
                ForEach(points, id: \.time) { p in
                    cell(p).frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    /// Symbol is computed through `WeatherSnapshot.description` so it tracks the same WMO table
    /// the WeatherCard uses; we construct a throwaway snapshot rather than duplicate the switch.
    private func cell(_ p: WeatherSnapshot.HourlyPoint) -> some View {
        let snap = WeatherSnapshot(temperature: 0, high: 0, low: 0, code: p.code,
                                   isDay: p.isDay, fetched: .init())
        let icon = Image(systemName: snap.description.symbol)
            .symbolRenderingMode(.multicolor)
            .font(.system(size: compact ? 12 : 16, weight: .regular))
            .foregroundStyle(ink.primary)
        let temp = Text("\(Int(p.temperature.rounded()))°")
            .pf(compact ? 12 : 13, .regular)
            .monospacedDigit()
            .foregroundStyle(ink.primary)
        return VStack(spacing: compact ? 3 : 2) {
            Text(Self.hour(p.time))
                .caps(8.5)
                .foregroundStyle(ink.tertiary)
            // Short strip (little slack on smaller phones): icon and temperature share one line.
            if compact { HStack(spacing: 3) { icon; temp } } else { icon; temp }
        }
    }

    private static func hour(_ d: Date) -> String {
        String(format: "%02d", Calendar.current.component(.hour, from: d))
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
        // Same image in every mode: on the Clear / Tinted Home Screen `.fullColor` keeps the tile's own
        // colours on top of the system glass (that is how photo widgets stay colourful there).
        Image(name)
            .resizable()
            .interpolation(.high)
            .widgetAccentedRenderingMode(.fullColor)
            .frame(width: size, height: size)
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
