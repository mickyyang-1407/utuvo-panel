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
                        Label(model.screenshot == nil ? "選一張空桌面的截圖" : "換一張截圖", systemImage: "photo.on.rectangle.angled")
                    }
                    if model.screenshot != nil {
                        NavigationLink { AlignView() } label: {
                            Label("對齊背景（拖曳面板到小工具的位置）", systemImage: "rectangle.and.hand.point.up.left")
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
                    Text("免截圖的透明：設定 › 桌面與 App 資料庫 › 圖示樣式選「透明」，系統會自動把面板變成玻璃。\n要在全彩桌面上透明才需要截圖：把桌面滑到空白頁，截圖，回來選它，再用「對齊背景」拖到小工具的位置。"
                         + (model.panelSizeIsMeasured ? "" : "\n面板尺寸目前是估的；小工具加進桌面後會回報真實尺寸，之後重新裁一次就準了。"))
                }

                Section("模組") {
                    Toggle("行事曆", isOn: $model.config.showCalendar)
                    Toggle("天氣", isOn: $model.config.showWeather)
                    Toggle("活動", isOn: $model.config.showActivity)
                    Toggle("計時器", isOn: $model.config.showTimer)
                    Toggle("常用 app", isOn: $model.config.showLaunchers)
                    Toggle("一句話", isOn: $model.config.showNote)
                }

                Section("內容") {
                    Toggle("時間走秒", isOn: $model.config.showSeconds)
                    Stepper("計時器 \(model.config.timerMinutes) 分鐘", value: $model.config.timerMinutes, in: 1...180)
                    TextField("一句話", text: $model.config.note)
                }

                Section {
                    NavigationLink {
                        LauncherPicker()
                    } label: {
                        HStack {
                            Text("常用 app")
                            Spacer()
                            HStack(spacing: 4) {
                                ForEach(model.config.launcherIDs.prefix(5).compactMap(Launcher.byID)) { l in
                                    Image(systemName: l.symbol)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 22, height: 22)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: l.colorHex)))
                                }
                            }
                        }
                    }
                } footer: {
                    Text("點面板上的圖示會先回到這個 app，再跳到目標 app。iOS 只允許小工具開自己的 app。")
                }

                Section("資料來源") {
                    row("行事曆", model.calendarStatus) { model.requestCalendar() }
                    row("定位（天氣）", model.locationStatus) { model.requestLocation() }
                    row("健康（活動）", model.healthStatus) {
                        model.requestHealth()
                    }
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

    private func row(_ title: String, _ status: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
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
                            Image(systemName: l.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: l.colorHex)))
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
