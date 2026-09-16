// PanelView.swift — the panel itself. Rendered by the widget and, pixel-identical, by the app preview.

import SwiftUI
import WidgetKit

struct PanelData {
    var date: Date
    var config: PanelConfig
    var weather: WeatherSnapshot?
    var activity: ActivitySnapshot?
    var event: EventInfo?
    var timer: TimerState
    var background: UIImage?
    var avatar: UIImage?
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
            background: nil, avatar: nil)
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

    private let rowSpacing: CGFloat = 8
    private let pad: CGFloat = 12

    var body: some View {
        content
            .padding(pad)
            .modifier(BackgroundModifier(image: data.background, tint: data.config.tint, inWidget: inWidget))
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: rowSpacing) {
            HeaderRow(date: data.date, avatar: data.avatar).frame(height: 84)
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

private struct BackgroundModifier: ViewModifier {
    let image: UIImage?
    let tint: Double
    let inWidget: Bool

    @ViewBuilder private var fill: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(hex: 0x1E3A5F), Color(hex: 0x0B1B2B)],
                               startPoint: .top, endPoint: .bottom)
            }
            Color.black.opacity(tint)
        }
    }

    func body(content: Content) -> some View {
        if inWidget {
            content.containerBackground(for: .widget) { fill }
        } else {
            content
                .background { fill }
                .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        }
    }
}

// MARK: - Card

private struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
            }
    }
}

private func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
    .system(size: size, weight: weight, design: .rounded)
}

// MARK: - Rows

private struct HeaderRow: View {
    let date: Date
    let avatar: UIImage?
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text(date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                    .font(rounded(54, .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                Text(date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(rounded(15, .medium))
                    .opacity(0.85)
            }
            Spacer()
            ZStack {
                Circle().fill(Color(hex: 0x5AC8FA).opacity(0.9))
                if let avatar {
                    Image(uiImage: avatar).resizable().scaledToFill().clipShape(Circle())
                } else {
                    Image(systemName: "person.fill").font(.system(size: 30)).foregroundStyle(.white)
                }
            }
            .frame(width: 66, height: 66)
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
                            .font(rounded(15, .semibold))
                            .foregroundStyle(Color(hex: 0x9CCBFF))
                            .lineLimit(1)
                        if event.isAllDay {
                            Text("全天").font(rounded(16, .medium))
                        } else {
                            Text("\(event.start, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())–\(event.end, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())")
                                .font(rounded(17, .medium)).monospacedDigit()
                        }
                    } else {
                        Text("今天沒有行程").font(rounded(15, .semibold)).foregroundStyle(Color(hex: 0x9CCBFF))
                        Text("休息一下").font(rounded(16, .medium)).opacity(0.8)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct DateTile: View {
    let date: Date
    var body: some View {
        VStack(spacing: 0) {
            Text(date, format: .dateTime.month(.abbreviated))
                .font(.system(size: 10, weight: .bold))
                .textCase(.uppercase)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(Color(hex: 0xFF3B30))
            Text(date, format: .dateTime.day())
                .font(rounded(22, .bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
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
                        Text(city ?? "定位中").font(rounded(14, .semibold))
                    }
                    Text(weather.map { "\(Int($0.temperature.rounded()))°" } ?? "--°")
                        .font(rounded(48, .bold))
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    let d: (symbol: String, text: String) = weather?.description ?? (symbol: "cloud.fill", text: "—")
                    Image(systemName: d.symbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 24))
                    Text(d.text).font(rounded(15, .semibold))
                    if let w = weather {
                        HStack(spacing: 4) {
                            Text("\(Int(w.high.rounded()))°").font(rounded(14, .semibold))
                            Text("\(Int(w.low.rounded()))°").font(rounded(14, .semibold)).opacity(0.6)
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
            Text(label).font(rounded(11, .semibold)).foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(rounded(18, .bold)).monospacedDigit()
                if !unit.isEmpty { Text(unit).font(rounded(12, .semibold)).opacity(0.8) }
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
                circleButton(phase == .running ? "pause.fill" : "play.fill", orange.opacity(0.35), orange) {
                    TimerToggleIntent()
                }
                circleButton("xmark", Color.white.opacity(0.18), .white) {
                    TimerStopIntent()
                }
                Spacer()
                Text("計時器").font(rounded(15, .semibold)).foregroundStyle(orange)
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
                .font(rounded(30, .medium))
                .monospacedDigit()
                .foregroundStyle(orange)
                .frame(minWidth: 76, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
        }
    }
    private func circleButton<I: AppIntent>(_ symbol: String, _ fill: Color, _ fg: Color, _ intent: () -> I) -> some View {
        Button(intent: intent()) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(fg)
                .frame(width: 40, height: 40)
                .background(Circle().fill(fill))
        }
        .buttonStyle(.plain)
    }
}

private struct LauncherRow: View {
    let ids: [String]
    var body: some View {
        Card {
            HStack(spacing: 0) {
                let launchers = ids.prefix(5).compactMap(Launcher.byID)
                ForEach(launchers) { l in
                    Link(destination: l.deepLink) {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(Color(hex: l.colorHex))
                            .frame(width: 52, height: 52)
                            .overlay {
                                Image(systemName: l.symbol)
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                    }
                    .frame(maxWidth: .infinity)
                }
                if launchers.isEmpty {
                    Text("在 app 裡挑五個 app").font(rounded(15, .medium)).opacity(0.7)
                }
            }
        }
    }
}

private struct NoteRow: View {
    let note: String
    var body: some View {
        Card {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(hex: 0x2E7D32))
                    .frame(width: 40, height: 40)
                    .overlay { Image(systemName: "leaf.fill").foregroundStyle(Color(hex: 0xC5FF7A)) }
                Text(note.isEmpty ? "在 app 裡寫一句今天的話" : note)
                    .font(rounded(15, .semibold))
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

import AppIntents
