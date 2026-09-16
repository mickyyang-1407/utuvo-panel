import SwiftUI
import PhotosUI

struct RootView: View {
    @EnvironmentObject private var model: PanelModel
    @State private var screenshotItem: PhotosPickerItem?
    @State private var showPicker = false

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
                        Row("wallpaper", model.screenshot == nil ? "選你的桌布（原圖或空桌面截圖）" : "換桌布")
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
                    Text("iOS 不讓小工具真的透明（iScreen 也一樣要一張桌布）。選你設成桌布的那張原圖就好，會自動裁成面板那一塊；或滑到空白桌面截圖再選。加進桌面後用「對齊背景」拖到位。\n想完全免圖：設定 › 桌面與 App 資料庫 › 圖示樣式選「透明」，系統會把面板變成玻璃。"
                         + (model.panelSizeIsMeasured ? "" : "\n面板尺寸目前是估的；小工具加進桌面後會回報真實尺寸，之後重新裁一次就準了。"))
                }

                Section("模組") {
                    Toggle(isOn: $model.config.showCalendar) { Row("calendar", "行事曆") }
                    Toggle(isOn: $model.config.showWeather) { Row("weather", "天氣") }
                    Toggle(isOn: $model.config.showActivity) { Row("activity", "活動") }
                    Toggle(isOn: $model.config.showTimer) { Row("timer", "計時器") }
                    Toggle(isOn: $model.config.showLaunchers) { Row("grid", "常用 app") }
                    Toggle(isOn: $model.config.showNote) { Row("note", "一句話") }
                }

                Section("內容") {
                    Toggle(isOn: $model.config.showSeconds) { Row("seconds", "時間走秒") }
                    Picker(selection: $model.config.fontDesign) {
                        Text("SF Pro").tag("default")
                        Text("SF Rounded").tag("rounded")
                        Text("New York").tag("serif")
                        Text("SF Mono").tag("mono")
                    } label: { Row("text", "字型") }
                    Stepper(value: $model.config.timerMinutes, in: 1...180) { Row("timer", "計時器 \(model.config.timerMinutes) 分鐘") }
                    HStack(spacing: 12) {
                        SettingsIcon("text")
                        TextField("一句話", text: $model.config.note)
                    }
                }

                Section {
                    NavigationLink {
                        LauncherPicker()
                    } label: {
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
                } footer: {
                    Text("點面板上的圖示會先回到這個 app，再跳到目標 app。iOS 只允許小工具開自己的 app。")
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
            .onChange(of: screenshotItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) { model.setScreenshot(data) }
                    screenshotItem = nil
                }
            }
            .task {
                await model.refreshHealth()
                model.refreshStatuses()
            }
        }
    }

    private func row(_ icon: String, _ title: String, _ status: String, action: @escaping () -> Void) -> some View {
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

// MARK: - Launcher picker (max 5)

private struct LauncherPicker: View {
    @EnvironmentObject private var model: PanelModel

    var body: some View {
        List {
            Section {
                ForEach(Launcher.presets) { l in
                    let picked = model.config.launcherIDs.contains(l.id)
                    Button {
                        if picked {
                            model.config.launcherIDs.removeAll { $0 == l.id }
                        } else if model.config.launcherIDs.count < 5 {
                            model.config.launcherIDs.append(l.id)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image("tile-\(l.id)").resizable().interpolation(.high).frame(width: 30, height: 30)
                            Text(l.name).foregroundStyle(.primary)
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
    let title: String
    init(_ icon: String, _ title: String) { self.icon = icon; self.title = title }
    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(icon)
            Text(title)
        }
    }
}
