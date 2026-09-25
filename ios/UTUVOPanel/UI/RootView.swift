import SwiftUI

/// The app is the settings screen; there is no separate home page (iOS never lets an app send itself to the Home Screen).
struct RootView: View {
    @EnvironmentObject private var model: PanelModel
    var body: some View {
        SettingsView()
            .task {
                // Weather first and independent of HealthKit: a Health query that never calls back
                // must not keep the app from raising the network prompt / warming the cache (0011).
                Task { await model.refreshWeather() }
                await model.refreshHealth()
                model.refreshStatuses()
                model.refreshSetup()
            }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: PanelModel
    @State private var applied = false
    @State private var forceShowSetup = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Form {
                // One-step guide, hidden once the panel is on the Home Screen; pops back when
                // "重新看設定步驟" is reset.
                SetupGuide(forceShow: forceShowSetup)

                Section {
                    PreviewCard()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("暗度 \(Int(model.config.tint * 100))%").font(.subheadline)
                        Slider(value: $model.config.tint, in: 0...0.7)
                    }
                    if model.setup.allDone && !forceShowSetup {
                        Button("重新看設定步驟") { forceShowSetup = true }
                    }
                } header: {
                    Text("背景")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("面板直接透出你的桌布，換桌布、桌布輪播都會自動跟著變。長按面板 › 編輯小工具 可以改成漸層背景、加邊框。")
                    }
                }

                Section("模組") {
                    Toggle(isOn: $model.config.showCalendar) { Row("calendar", "行事曆") }
                    Toggle(isOn: $model.config.showWeather) { Row("weather", "天氣") }
                    Toggle(isOn: $model.config.showActivity) { Row("activity", "活動") }
                    Toggle(isOn: $model.config.showTimer) { Row("timer", "計時器") }
                    Toggle(isOn: $model.config.showLaunchers) { Row("grid", "常用 app") }
                    Toggle(isOn: $model.config.showSystem) { Row("cpu", "系統資訊") }
                }

                Section("內容") {
                    Toggle(isOn: $model.config.showSeconds) { Row("seconds", "時間走秒") }
                    Picker(selection: $model.config.fontDesign) {
                        Text("SF Pro").tag("default")
                        Text("SF Rounded").tag("rounded")
                        Text("New York").tag("serif")
                        Text("SF Mono").tag("mono")
                    } label: { Row("text", "字型") }
                    Picker(selection: $model.config.panelScheme) {
                        Text("自動").tag("auto")
                        Text("淺色玻璃").tag("light")
                        Text("深色玻璃").tag("dark")
                    } label: { Row("wallpaper", "面板色調") }
                    Picker(selection: $model.config.bottomLayout) {
                        Text("逐時天氣").tag("hourly")
                        Text("行程清單").tag("agenda")
                        Text("平均分配").tag("spread")
                    } label: { Row("layout", "下半部") }
                    Stepper(value: $model.config.timerMinutes, in: 1...180) { Row("timer", "計時器 \(model.config.timerMinutes) 分鐘") }
                }

                Section {
                    Picker(selection: $model.config.borderStyle) {
                        Text("無").tag("none")
                        Text("細線").tag("hairline")
                        Text("粗線").tag("bold")
                        Text("雙線").tag("double")
                        Text("虛線").tag("dashed")
                        Text("光暈").tag("glow")
                    } label: { Row("border", "樣式") }
                    Picker(selection: $model.config.borderColor) {
                        Text("白").tag("white")
                        Text("黑").tag("black")
                        Text("跟文字一樣").tag("ink")
                        Text("珊瑚紅").tag("coral")
                        Text("香檳金").tag("gold")
                        Text("天藍").tag("sky")
                    } label: { Row("palette", "顏色") }
                    .disabled(model.config.borderStyle == "none")
                } header: {
                    Text("邊框")
                } footer: {
                    Text("桌面上每個面板都會用這裡的邊框；想讓某一個不一樣，長按它 › 編輯小工具 單獨改。")
                }

                Section {
                    NavigationLink { LauncherPicker() } label: {
                        HStack {
                            Row("grid", "常用 app")
                            Spacer()
                            HStack(spacing: 4) {
                                ForEach(model.config.launcherIDs.prefix(5).compactMap(Launcher.byID)) { l in
                                    Image("tile-\(l.id)").resizable().interpolation(.high).frame(width: 22, height: 22)
                                }
                            }
                        }
                    }
                    NavigationLink { SystemMetricPicker() } label: {
                        HStack {
                            Row("cpu", "系統資訊")
                            Spacer()
                            HStack(spacing: 4) {
                                ForEach(model.config.systemMetrics.prefix(4).compactMap(SystemMetric.byID)) { m in
                                    Image(m.tile).resizable().interpolation(.high).frame(width: 22, height: 22)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("點面板上的圖示直接開該 app；日曆、天氣、活動列也會開對應的 app。")
                }

                Section("資料來源") {
                    row("calendar", "行事曆", model.calendarStatus) { model.requestCalendar() }
                    row("location", "定位（天氣）", model.locationStatus) { model.requestLocation() }
                    row("health", "健康（活動）", model.healthStatus) { model.requestHealth() }
                }
            }
            .navigationTitle("UTUVO Panel")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        model.reloadWidget()
                        withAnimation { applied = true }
                        Task { try? await Task.sleep(for: .seconds(4)); withAnimation { applied = false } }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if applied {
                    Label("已套用到面板，按 Home 回桌面", systemImage: "checkmark.circle.fill")
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("appliedToast")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .glassEffect()
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // User typically edits the widget on Home Screen and returns; re-read the configuration
                // state to refresh the check mark in the setup guide as soon as we come back.
                if phase == .active {
                    model.refreshSetup()
                    Task { await model.refreshWeather() }
                }
            }
        }
    }

    private func row(_ icon: String, _ title: LocalizedStringKey, _ status: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Row(icon, title).foregroundStyle(.primary)
                Spacer()
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Preview at true panel size, scaled to fit the screen width

private struct PreviewCard: View {
    @EnvironmentObject private var model: PanelModel

    var body: some View {
        let size = model.panelSize
        let pw = size.width, ph = size.height
        GeometryReader { geo in
            let s = min(geo.size.width / pw, 1)
            PanelView(data: model.previewData, inWidget: false)
                .frame(width: pw, height: ph)
                .background {
                    LinearGradient(colors: [Color(hex: 0x6E8EAF), Color(hex: 0x2B3A4F)], startPoint: .top, endPoint: .bottom)
                        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                }
                .scaleEffect(s, anchor: .topLeading)
                .frame(width: pw * s, height: ph * s)
                .frame(maxWidth: .infinity)
        }
        .aspectRatio(pw / ph, contentMode: .fit)
        .padding(.vertical, 8)
    }
}

// MARK: - Pickers (max 5 launchers, max 4 metrics)

private struct LauncherPicker: View {
    @EnvironmentObject private var model: PanelModel
    var body: some View {
        List {
            Section {
                ForEach(Launcher.presets) { l in
                    let picked = model.config.launcherIDs.contains(l.id)
                    Button {
                        if picked { model.config.launcherIDs.removeAll { $0 == l.id } }
                        else if model.config.launcherIDs.count < 5 { model.config.launcherIDs.append(l.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image("tile-\(l.id)").resizable().interpolation(.high).frame(width: 30, height: 30)
                            Text(LocalizedStringKey(l.name)).foregroundStyle(.primary)
                            Spacer()
                            if picked { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }
                }
            } footer: {
                Text("最多五個，照點選順序排列。已選 \(model.config.launcherIDs.count)／5。")
            }
        }
        .navigationTitle("常用 app")
    }
}

private struct SystemMetricPicker: View {
    @EnvironmentObject private var model: PanelModel
    var body: some View {
        List {
            Section {
                ForEach(SystemMetric.all) { m in
                    let picked = model.config.systemMetrics.contains(m.id)
                    Button {
                        if picked { model.config.systemMetrics.removeAll { $0 == m.id } }
                        else if model.config.systemMetrics.count < 4 { model.config.systemMetrics.append(m.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(m.tile).resizable().interpolation(.high).frame(width: 30, height: 30)
                            Text(LocalizedStringKey(m.name)).foregroundStyle(.primary)
                            Spacer()
                            if picked { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }
                }
            } footer: {
                Text("最多四個，照點選順序排列。已選 \(model.config.systemMetrics.count)／4。數字是每 15 分鐘的快照；iOS 不讓 app 切換 Wi-Fi 或藍牙。")
            }
        }
        .navigationTitle("系統資訊")
    }
}

// MARK: - Settings-style rows (icon tiles rendered by tools/make-tiles.py, same Liquid Glass as the Home Screen)

struct SettingsIcon: View {
    let name: String
    init(_ name: String) { self.name = name }
    var body: some View {
        Image("tile-\(name)").resizable().interpolation(.high).frame(width: 29, height: 29)
    }
}

struct Row: View {
    let icon: String
    let title: LocalizedStringKey
    init(_ icon: String, _ title: LocalizedStringKey) { self.icon = icon; self.title = title }
    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(icon)
            Text(title)
        }
    }
}
