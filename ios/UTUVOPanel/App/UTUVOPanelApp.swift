import SwiftUI
import WidgetKit

@main
struct UTUVOPanelApp: App {
    @StateObject private var model = PanelModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .onOpenURL { url in
                    // Launcher tiles: iOS only lets a widget open its own app, so hand off immediately — no UI first.
                    if let launcher = Launcher.fromDeepLink(url), let target = URL(string: launcher.url) {
                        model.showSettings = false
                        UIApplication.shared.open(target)
                        return
                    }
                    // The gear: straight into settings.
                    if url == Launcher.settingsDeepLink { model.showSettings = true }
                }
        }
    }
}
