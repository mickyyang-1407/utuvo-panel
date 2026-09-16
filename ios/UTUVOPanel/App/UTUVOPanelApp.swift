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
                    // The widget's launcher tiles can only open this app; forward to the real scheme.
                    guard let launcher = Launcher.fromDeepLink(url), let target = URL(string: launcher.url) else { return }
                    UIApplication.shared.open(target)
                }
        }
    }
}
