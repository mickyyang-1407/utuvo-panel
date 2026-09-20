import SwiftUI
import PhotosUI

/// The app is the settings screen; there is no separate home page (iOS never lets an app send itself to the Home Screen).
struct RootView: View {
    @EnvironmentObject private var model: PanelModel
    var body: some View {
        SettingsView()
            .task {
                await model.refreshHealth()
                model.refreshStatuses()
            }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: PanelModel
    @State private var screenshotItem: PhotosPickerItem?
    @State private var applied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PreviewCard()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    PhotosPicker(selection: $screenshotItem, matching: .images) {
                        if model.screenshot == nil { Row("wallpaper", "選你的桌布（原圖或空桌面截圖）") } else { Row("wallpaper", "換桌布") }
                    }
                    if model.screenshot != nil {
                        NavigationLink { AlignView() } label: {
                            Row("home", "對齊背景（拖曳面板到小工具的位置）")
                        }
                        Button("移除背景", role: .destructive) { model.clearScreenshot() }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("暗度 \(Int(model.config.tint * 100))%").font(.subheadline)
                        Slider(value: $model.config.tint, in: 0...0.7)
                    }
                } header: {
                    Text("透明背景")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("iOS 不讓小工具真的透明（iScreen 也一樣要一張桌布）。選你設成桌布的那張原圖就好，會自動裁成面板那一塊；或滑到空白桌面截圖再選。加進桌面後用「對齊背景」拖到位。\n想完全免圖：設定 › 桌面與 App 資料庫 › 圖示樣式選「透明」，系統會把面板變成玻璃。")
                        if !model.panelSizeIsMeasured {
                            Text("面板尺寸目前是估的；小工具加進桌面後會回報真實尺寸，之後重新裁一次就準了。")
                        }
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
                    Stepper(value: $model.config.timerMinutes, in: 1...180) { Row("timer", "計時器 \(model.config.timerMinutes) 分鐘") }
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

                Section("加到桌面") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. 長按桌面空白處 → 左上「編輯」→「加入小工具」")
                        Text("2. 搜尋「UTUVO Panel」")
                        Text("3. 選最高的那個（iOS 27 特大直式），放到空白頁")
                        Text("4. 面板右上角的齒輪會回到這裡")
                    }
                    .font(.subheadline)
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
            .onChange(of: screenshotItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) { model.setScreenshot(data) }
                    screenshotItem = nil
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
        let p = model.placement
        let pw = CGFloat(p.panel.width), ph = CGFloat(p.panel.height)
        GeometryReader { geo in
            let s = min(geo.size.width / pw, 1)
            PanelView(data: model.previewData, inWidget: false)
                .frame(width: pw, height: ph)
                .background {
                    if model.background == nil {
                        LinearGradient(colors: [Color(hex: 0x6E8EAF), Color(hex: 0x2B3A4F)], startPoint: .top, endPoint: .bottom)
                            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                    }
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
