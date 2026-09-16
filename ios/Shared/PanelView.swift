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
            .modifier(BackgroundModifier(image: data.background, tint: data.config.tint, inWidget: inWidget, accented: accented))
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: rowSpacing) {
            HeaderRow(date: data.date, showSeconds: data.config.showSeconds).frame(height: 84)
            if data.config.showCalendar { CalendarRow(date: data.date, event: data.event).frame(height: 68) }
            if data.config.showWeather { WeatherRow(weather: data.weather, city: data.config.city).frame(height: 92) }
            if !data.compact {
                if data.config.showActivity { ActivityRow(activity: data.activity).frame(height: 68) }
                if data.config.showTimer { TimerRow(timer: data.timer, now: data.date, defaultMinutes: data.config.timerMinutes).frame(height: 58) }
            }
            if data.config.showLaunchers { LauncherRow(ids: data.config.launcherIDs).frame(height: 68) }
            if !data.compact, data.config.showNote { NoteRow(note: data.config.note).frame(height: 56) }
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

/// Small circular glass button (gear, play, stop).
private struct GlassCircle<Label: View>: View {
    @Environment(\.panelAccented) private var accented
    var size: CGFloat = 40
    var tint: Color = .clear
    @ViewBuilder var label: () -> Label
    var body: some View {
        label()
            .frame(width: size, height: size)
            .background {
                if accented {
                    Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.6)
                } else {
                    Circle().fill(Color.clear)
                        .glassEffect(.regular.tint(tint), in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.6))
                }
            }
    }
}

private func f(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
    .system(size: size, weight: weight)
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
                .font(.system(size: showSeconds ? 44 : 54, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .widgetAccentable()
                Text(date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(f(15, .medium))
                    .opacity(0.85)
            }
            Spacer()
            // Settings: opens the app (widgets can only open their own container).
            Link(destination: Launcher.settingsDeepLink) {
                GlassCircle(size: 48, tint: Color.white.opacity(0.08)) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
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
                            .font(f(15, .semibold))
                            .foregroundStyle(Color(hex: 0x9CCBFF))
                            .widgetAccentable()
                            .lineLimit(1)
                        if event.isAllDay {
                            Text("全天").font(f(16, .medium))
                        } else {
                            Text("\(event.start, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())–\(event.end, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())")
                                .font(f(17, .medium)).monospacedDigit()
                        }
                    } else {
                        Text("今天沒有行程").font(f(15, .semibold)).foregroundStyle(Color(hex: 0x9CCBFF)).widgetAccentable()
                        Text("休息一下").font(f(16, .medium)).opacity(0.8)
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
                .font(.system(size: 22, weight: .bold, design: .rounded))
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
                        Text(city ?? "定位中").font(f(14, .semibold))
                    }
                    Text(weather.map { "\(Int($0.temperature.rounded()))°" } ?? "--°")
                        .font(.system(size: 48, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .widgetAccentable()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    let d: (symbol: String, text: String) = weather?.description ?? (symbol: "cloud.fill", text: "—")
                    Image(systemName: d.symbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 24))
                    Text(d.text).font(f(15, .semibold))
                    if let w = weather {
                        HStack(spacing: 4) {
                            Text("\(Int(w.high.rounded()))°").font(f(14, .semibold))
                            Text("\(Int(w.low.rounded()))°").font(f(14, .semibold)).opacity(0.6)
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
            HStack(alignment: .center, spacing: 18) {
                stat("步數", Color(hex: 0xFF375F), activity.map { "\($0.steps)" } ?? "—", "")
                stat("運動", Color(hex: 0xA8FF3E), activity.map { "\($0.exerciseMinutes)" } ?? "—", "min")
                stat("站立", Color(hex: 0x28E5FF), activity.map { "\($0.standHours)" } ?? "—", "hr")
                Spacer(minLength: 0)
                Rings(activity: activity ?? ActivitySnapshot()).frame(width: 46, height: 46)
            }
        }
    }
    private func stat(_ label: String, _ color: Color, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(f(11, .semibold)).foregroundStyle(color).widgetAccentable()
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 18, weight: .bold, design: .rounded)).monospacedDigit()
                if !unit.isEmpty { Text(unit).font(f(12, .semibold)).opacity(0.8) }
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
                    GlassCircle(tint: orange.opacity(0.35)) {
                        Image(systemName: phase == .running ? "pause.fill" : "play.fill")
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(orange)
                    }
                }
                .buttonStyle(.plain)
                Button(intent: TimerStopIntent()) {
                    GlassCircle(tint: Color.white.opacity(0.1)) {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Text("計時器").font(f(15, .semibold)).foregroundStyle(orange).widgetAccentable()
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
                .font(.system(size: 30, weight: .medium, design: .rounded))
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
                    Link(destination: l.deepLink) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(accented ? Color.white.opacity(0.18) : Color(hex: l.colorHex))
                            .frame(width: 52, height: 52)
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.6)
                            }
                            .overlay {
                                Image(systemName: l.symbol)
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                    }
                    .frame(maxWidth: .infinity)
                }
                if launchers.isEmpty {
                    Text("在 app 裡挑五個 app").font(f(15, .medium)).opacity(0.7)
                }
            }
        }
    }
}

private struct NoteRow: View {
    @Environment(\.panelAccented) private var accented
    let note: String
    var body: some View {
        Card {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accented ? Color.white.opacity(0.18) : Color(hex: 0x2E7D32))
                    .frame(width: 40, height: 40)
                    .overlay { Image(systemName: "leaf.fill").foregroundStyle(accented ? .white : Color(hex: 0xC5FF7A)) }
                Text(note.isEmpty ? "在 app 裡寫一句今天的話" : note)
                    .font(f(15, .semibold))
                    .lineLimit(2)
                    .opacity(note.isEmpty ? 0.6 : 1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right.circle")
                    .font(.system(size: 22, weight: .regular))
                    .opacity(0.7)
            }
        }
    }
}
