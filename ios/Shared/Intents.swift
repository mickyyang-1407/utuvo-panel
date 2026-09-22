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

// MARK: - Widget configuration (Edit Widget sheet: background)

enum PanelBackgroundChoice: String, AppEnum {
    case transparent, gradient

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "背景"
    static var caseDisplayRepresentations: [PanelBackgroundChoice: DisplayRepresentation] = [
        .transparent: "透明",
        .gradient:    "漸層",
    ]
}

// PanelSlotChoice was the "position" picker in Edit Widget (top / row1 / row2 / custom).
// Removed in ticket 0007 — the system transparent mode (WidgetKit SPI preferredBackgroundStyle)
// means the user no longer needs to tell the panel where it sits. PanelSlotKind still lives
// in Logic.swift because the slot geometry is read from older configs and used elsewhere.
// Keep this enum around too so old widget configurations continue to decode.
enum PanelSlotChoice: String, AppEnum {
    case custom, top, row1, row2

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "位置"
    static var caseDisplayRepresentations: [PanelSlotChoice: DisplayRepresentation] = [
        .custom: "在 app 裡對齊的位置",
        .top:    "頁面頂端",
        .row1:   "往下一列",
        .row2:   "往下兩列",
    ]

    var kind: PanelSlotKind { PanelSlotKind(rawValue: rawValue)! }
}

// MARK: Widget configuration (Edit Widget sheet: border + colour)

enum PanelBorderChoice: String, AppEnum {
    case app, none, hairline, bold, double, dashed, glow

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "邊框"
    static var caseDisplayRepresentations: [PanelBorderChoice: DisplayRepresentation] = [
        .app:     "跟 app 設定一樣",
        .none:    "無",
        .hairline: "細線",
        .bold:    "粗線",
        .double:  "雙線",
        .dashed:  "虛線",
        .glow:    "光暈",
    ]
}

enum PanelBorderColorChoice: String, AppEnum {
    case app, white, black, ink, coral, gold, sky

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "邊框顏色"
    static var caseDisplayRepresentations: [PanelBorderColorChoice: DisplayRepresentation] = [
        .app:   "跟 app 設定一樣",
        .white: "白",
        .black: "黑",
        .ink:   "跟文字一樣",
        .coral: "珊瑚紅",
        .gold:  "香檳金",
        .sky:   "天藍",
    ]
}

struct PanelWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "面板設定"
    static var description = IntentDescription("選背景與邊框")

    // WidgetConfigurationIntent requires every parameter to be optional. The "defaults"
    // live in PanelWidgetIntent.backgroundDefault; readers unwrap to that.
    @Parameter(title: "背景", default: .transparent) var background: PanelBackgroundChoice
    @Parameter(title: "邊框", default: PanelBorderChoice.app) var border: PanelBorderChoice
    @Parameter(title: "邊框顏色", default: PanelBorderColorChoice.app) var borderColor: PanelBorderColorChoice

    /// What we treat as the user's pick when the intent hasn't set one yet (= a fresh install).
    static let backgroundDefault: PanelBackgroundChoice = .transparent
    static let borderDefault: PanelBorderChoice = .app
    static let borderColorDefault: PanelBorderColorChoice = .app

    var backgroundValue: PanelBackgroundChoice { background }
    var borderValue: PanelBorderChoice { border }
    var borderColorValue: PanelBorderColorChoice { borderColor }

    init() {}
    init(background: PanelBackgroundChoice = .transparent,
         border: PanelBorderChoice = .app, borderColor: PanelBorderColorChoice = .app) {
        self.background = background
        self.border = border
        self.borderColor = borderColor
    }
}
