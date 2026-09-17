// Intents.swift — widget buttons. Compiled into both targets (Apple's recommended pattern),
// so the same intent runs whether the widget or the app is the host.

import AppIntents
import WidgetKit

struct TimerToggleIntent: AppIntent {
    static var title: LocalizedStringResource = "計時器 開始／暫停"
    static var description = IntentDescription("閒置時開始、進行中暫停、暫停中繼續。")

    func perform() async throws -> some IntentResult {
        let config = PanelConfig.load()
        TimerState.load().toggled(at: Date(), defaultMinutes: config.timerMinutes).save()
        WidgetCenter.shared.reloadTimelines(ofKind: Shared.widgetKind)
        return .result()
    }
}

/// Opens another app straight from the widget. iOS 18+ lets an intent hand the system an
/// OpenURLIntent, so the target app launches without our app ever coming to the foreground.
struct OpenAppIntent: AppIntent {
    static var title: LocalizedStringResource = "開啟 app"
    static var isDiscoverable = false
    static var openAppWhenRun = false

    @Parameter(title: "Launcher") var id: String

    init() {}
    init(id: String) { self.id = id }

    func perform() async throws -> some IntentResult & OpensIntent {
        let url = Launcher.byID(id).flatMap { URL(string: $0.url) } ?? Launcher.settingsDeepLink
        return .result(opensIntent: OpenURLIntent(url))
    }
}

struct TimerStopIntent: AppIntent {
    static var title: LocalizedStringResource = "計時器 停止"
    static var description = IntentDescription("清掉計時器，回到閒置。")

    func perform() async throws -> some IntentResult {
        TimerState.stopped.save()
        WidgetCenter.shared.reloadTimelines(ofKind: Shared.widgetKind)
        return .result()
    }
}
