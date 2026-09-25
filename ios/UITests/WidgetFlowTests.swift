// Drives SpringBoard to add the panel widget, and the app to pick a screenshot.
// Screenshots are attached to the result bundle AND written by the runner via simctl afterwards.

import XCTest

final class WidgetFlowTests: XCTestCase {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    func snap(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func dump(_ app: XCUIApplication, _ tag: String) {
        print("=== TREE \(tag) ===\n\(app.debugDescription)\n=== END \(tag) ===")
    }

    /// 2. On the home screen: add the extra-large-portrait widget — once. Re-running the suite must
    /// not stack a second panel on the Home Screen (every other test assumes exactly one).
    func test2_addWidget() {
        if scrollToWidget().exists {
            snap("already-added")
            XCTAssertEqual(widgetCount(), 1, "exactly one panel on the Home Screen")
            return
        }
        // A freshly installed app's widget isn't in the gallery until the app has run once.
        let app = XCUIApplication(); app.launch(); sleep(3)
        XCUIDevice.shared.press(.home)
        sleep(1)
        // Make sure we are on the first home page, not App Library.
        springboard.swipeRight(); sleep(1); springboard.swipeRight(); sleep(1)
        snap("home-before")
        // Enter jiggle mode. Pages are full of widgets, so the long press usually opens a context menu;
        // take its "Edit Home Screen" item when it does.
        XCUIDevice.shared.press(.home); sleep(1)
        let blank = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        blank.press(forDuration: 1.5)
        sleep(2)
        let editHome = springboard.buttons.matching(NSPredicate(format: "label == 'Edit Home Screen' OR label == '編輯主畫面'")).firstMatch
        if editHome.waitForExistence(timeout: 2) { editHome.tap(); sleep(2) }
        dump(springboard, "jiggle")
        snap("jiggle")
        // iOS 18+: "Edit" (top-left) → "Add Widget"; older: "+" button.
        // SpringBoard's own labels follow the device language — never hard-code one language here.
        let edit = springboard.buttons.matching(NSPredicate(format: "label == 'Edit' OR label == '編輯'")).firstMatch
        let addWidget = springboard.buttons.matching(NSPredicate(format: "label CONTAINS 'Add Widget' OR label CONTAINS '加入小工具' OR label CONTAINS '小工具'")).firstMatch
        if edit.waitForExistence(timeout: 3) {
            edit.tap(); sleep(1)
            if addWidget.waitForExistence(timeout: 3) { addWidget.tap() } else { dump(springboard, "edit-menu"); springboard.buttons.matching(NSPredicate(format: "label CONTAINS 'Widget' OR label CONTAINS '小工具'")).firstMatch.tap() }
        } else if addWidget.waitForExistence(timeout: 3) {
            addWidget.tap()
        } else {
            XCTFail("no Edit / Add Widget button"); return
        }
        sleep(2)
        snap("gallery")
        dump(springboard, "gallery")
        // Search for our widget.
        let search = springboard.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "gallery search field")
        search.tap(); search.typeText("UTUVO")
        sleep(2)
        snap("gallery-search")
        dump(springboard, "gallery-search")
        let hit = springboard.cells.matching(NSPredicate(format: "label CONTAINS 'UTUVO Panel' OR label CONTAINS 'UTUVOPanel'")).firstMatch
        let hitAny = hit.exists ? hit : springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'UTUVO Panel'")).element(boundBy: 1)
        XCTAssertTrue(hitAny.waitForExistence(timeout: 5), "widget listed in gallery")
        hitAny.tap()
        sleep(2)
        snap("gallery-detail")
        dump(springboard, "gallery-detail")
        // Family pages: swipe to the last (tallest) one, then Add.
        for _ in 0..<3 { springboard.swipeLeft(); usleep(600_000) }
        snap("gallery-detail-last")
        let addBtn = springboard.buttons.matching(NSPredicate(format: "label CONTAINS 'Add Widget' OR label CONTAINS '加入小工具'")).firstMatch
        XCTAssertTrue(addBtn.waitForExistence(timeout: 5), "Add Widget button on detail")
        addBtn.tap()
        sleep(2)
        // Leave jiggle mode.
        if springboard.buttons["Done"].exists { springboard.buttons["Done"].tap() } else { XCUIDevice.shared.press(.home) }
        sleep(3)
        snap("home-with-widget")
        dump(springboard, "home-with-widget")
        XCTAssertTrue(scrollToWidget().exists, "panel is on the Home Screen after Add")
        XCTAssertEqual(widgetCount(), 1, "exactly one panel on the Home Screen")
    }
}

extension WidgetFlowTests {
    /// 3. Walk the home pages, screenshot each, and print our widget's on-screen frame.
    func test3_locateWidget() {
        XCUIDevice.shared.press(.home); sleep(1)
        springboard.swipeRight(); sleep(1); springboard.swipeRight(); sleep(1)
        var widgetPages: [Int] = []
        for page in 0..<4 {
            snap("page-\(page)")
            // The app icon shares the label; only the widget carries "Widget" in its value.
            // One resolve per page: iterating allElementsBoundByIndex re-queries each element lazily
            // and flakes when SpringBoard's tree shifts mid-loop.
            let w = widgetQuery.firstMatch
            let frame = w.exists ? w.frame : .zero
            let onScreen = w.exists && frame.minX >= 0 && frame.maxX <= springboard.frame.width
            if onScreen {
                print("=== FOUND on page \(page) frame=\(frame) screen=\(springboard.frame)")
                widgetPages.append(page)
                // SpringBoard only exposes the visible page's widgets, so count here, not at the end.
                XCTAssertEqual(widgetCount(), 1, "exactly one panel on page \(page)")
            }
            springboard.swipeLeft(); sleep(1)
        }
        XCTAssertEqual(widgetPages.count, 1, "panel on exactly one of the first four pages (found on \(widgetPages))")
    }
}

extension WidgetFlowTests {
    /// 4. Scroll page 0 until our widget is fully on screen, then screenshot it in place.
    func test4_showWidget() {
        let ours = scrollToWidget()
        sleep(2)
        print("=== WIDGET frame=\(ours.frame) exists=\(ours.exists)")
        snap("widget-in-place")
        XCTAssertTrue(ours.exists, "widget on screen")
    }
}


extension WidgetFlowTests {
    /// Our widget, not the app icon (same label; only the widget's value says "Widget" — "小工具" when
    /// SpringBoard runs in Traditional Chinese).
    private var widgetQuery: XCUIElementQuery {
        springboard.descendants(matching: .any).matching(NSPredicate(format: "label == 'UTUVO Panel' AND (value CONTAINS 'Widget' OR value CONTAINS '小工具')"))
    }

    /// Panels SpringBoard currently exposes — the visible page only (measured: off-screen pages read 0).
    private func widgetCount() -> Int { widgetQuery.count }

    private func scrollToWidget() -> XCUIElement {
        XCUIDevice.shared.press(.home); sleep(1)
        springboard.swipeRight(); sleep(1)
        let ours = springboard.descendants(matching: .any).matching(NSPredicate(format: "label == 'UTUVO Panel' AND (value CONTAINS 'Widget' OR value CONTAINS '小工具')")).firstMatch
        var tries = 0
        while tries < 10 {
            guard ours.exists else { springboard.swipeLeft(); sleep(1); tries += 1; continue }
            let f = ours.frame, w = springboard.frame.width, h = springboard.frame.height
            print("=== LOOP try \(tries) frame=\(f) screen=\(w)x\(h)")
            if f.minX >= w { springboard.swipeLeft(); sleep(1); tries += 1; continue }   // on a page to the right
            if f.maxX <= 0 { springboard.swipeRight(); sleep(1); tries += 1; continue }  // on a page to the left
            if f.minY >= 0, f.maxY <= h { break }
            springboard.swipeUp(); sleep(1); tries += 1
        }
        sleep(1)
        return ours
    }

    /// 5. Timer button is a real AppIntent: after Play the display must no longer read 5:00 and must count down.
    func test5_timerIntent() {
        let w = scrollToWidget()
        XCTAssertTrue(w.exists)
        let play = w.buttons["Play"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 5), "Play button in widget")
        play.tap()
        sleep(4)
        snap("timer-running")
        let texts = w.staticTexts.allElementsBoundByIndex.map(\.label)
        print("=== TIMER texts after play: \(texts)")
        XCTAssertFalse(texts.contains("5:00"), "timer left 5:00")
        XCTAssertTrue(texts.contains { $0.range(of: #"^4:5\d$"#, options: .regularExpression) != nil }, "counting down from 5:00")
        XCTAssertTrue(w.buttons["Pause"].waitForExistence(timeout: 5), "button flipped to Pause")
        w.buttons["Close"].firstMatch.tap()
        sleep(3)
        snap("timer-stopped")
        XCTAssertTrue(w.buttons["Play"].waitForExistence(timeout: 5), "stop returns to Play")
    }

    /// 6. Launcher tile → our app → forwarded to Maps.
    func test6_launcherForwardsToMaps() {
        let w = scrollToWidget()
        XCTAssertTrue(w.exists)
        // Links in a widget are exposed as buttons/links; find the maps one by tapping the third tile.
        let tiles = w.links.allElementsBoundByIndex + w.buttons.allElementsBoundByIndex
        print("=== LINKS \(w.links.count) BUTTONS \(w.buttons.count) labels=\(tiles.map(\.label))")
        let maps = w.links.matching(NSPredicate(format: "label CONTAINS 'map' OR label CONTAINS 'Map'")).firstMatch
        if maps.exists { maps.tap() } else {
            // Fall back to geometry: launcher row is the 6th row; third tile of five.
            let f = w.frame
            w.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.width * 0.5, dy: f.height * 0.79)).tap()
        }
        let mapsApp = XCUIApplication(bundleIdentifier: "com.apple.Maps")
        let ok = mapsApp.wait(for: .runningForeground, timeout: 10)
        sleep(2)
        snap("after-launcher-tap")
        XCTAssertTrue(ok, "Maps came to the foreground")
        // Direct launch: our own app must not have been brought forward on the way.
        XCTAssertNotEqual(XCUIApplication().state, .runningForeground, "container app stayed out of the way")
    }
}

extension WidgetFlowTests {
    /// 8. Find the app icon on whatever page it lives and screenshot that page.
    func test8_appIcon() {
        XCUIDevice.shared.press(.home); sleep(1)
        for _ in 0..<3 { springboard.swipeRight(); usleep(400_000) }
        let icon = springboard.icons.matching(NSPredicate(format: "label == 'UTUVO Panel' AND NOT (value CONTAINS 'Widget' OR value CONTAINS '小工具')")).firstMatch
        for _ in 0..<6 {
            if icon.exists, icon.frame.minX >= 0, icon.frame.maxX <= springboard.frame.width { break }
            springboard.swipeLeft(); sleep(1)
        }
        sleep(1)
        print("=== ICON frame=\(icon.frame) exists=\(icon.exists)")
        snap("app-icon-page")
        XCTAssertTrue(icon.exists)
    }
}

extension WidgetFlowTests {
    /// 9. Dumb page walk: screenshot every page, no element queries.
    func test9_pages() {
        XCUIDevice.shared.press(.home); sleep(1)
        for _ in 0..<4 { springboard.swipeRight(); usleep(400_000) }
        sleep(1)
        for i in 0..<5 { snap("walk-\(i)"); springboard.swipeLeft(); sleep(1) }
    }
}

extension WidgetFlowTests {
    /// 10. Settings screen, top and scrolled.
    func test10_settingsScreens() {
        let app = XCUIApplication(); app.launch(); sleep(3)
        snap("settings-top")
        app.swipeUp(); sleep(1); snap("settings-mid")
        app.swipeUp(); sleep(1); snap("settings-bottom")
        let done = app.buttons.matching(NSPredicate(format: "label == 'Done' OR label == '完成'")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        snap("after-done")
        let toast = app.descendants(matching: .any).matching(identifier: "appliedToast").firstMatch
        if !toast.waitForExistence(timeout: 3) { print("=== TREE after-done ===\n\(app.debugDescription)\n=== END ===") }
        XCTAssertTrue(toast.exists, "Done shows the applied toast")
    }
}

extension WidgetFlowTests {
    /// 11. Tapping the calendar row opens the Calendar app (the simulator has no Weather app to test with).
    func test11_calendarRowOpensCalendar() {
        let w = scrollToWidget()
        XCTAssertTrue(w.exists)
        let f = w.frame
        // v2 layout (2026-09-21): the date card is the LEFT half of the card row (header 76 pt + cards 150 pt
        // on a 566-pt panel → 0.15…0.41 of the height). The old (0.6, 0.22) point is now the weather card.
        w.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.width * 0.25, dy: f.height * 0.28)).tap()
        let cal = XCUIApplication(bundleIdentifier: "com.apple.mobilecal")
        let ok = cal.wait(for: .runningForeground, timeout: 10)
        sleep(1); snap("after-calendar-tap")
        XCTAssertTrue(ok, "Calendar came to the foreground")
    }
}

extension WidgetFlowTests {
    /// 12. "Show seconds" clock must always read hh:mm:ss with a two-digit hour — the old day-long
    /// timer dropped the hour field below 1 h (00:35:17 showed "35:17") and never padded it.
    func test12_secondsClockKeepsHour() {
        let app = XCUIApplication(); app.launch(); sleep(3)
        let toggle = app.switches.matching(NSPredicate(format: "label CONTAINS '時間走秒' OR label CONTAINS 'Show seconds'")).firstMatch
        for _ in 0..<4 where !toggle.isHittable { app.swipeUp(); sleep(1) }
        XCTAssertTrue(toggle.exists, "show-seconds switch found")
        if (toggle.value as? String) != "1" { toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap() }
        sleep(1)
        XCTAssertEqual(toggle.value as? String, "1", "show-seconds is on")
        let done = app.buttons.matching(NSPredicate(format: "label == 'Done' OR label == '完成'")).firstMatch
        if done.exists { done.tap() }
        sleep(4)
        let ours = scrollToWidget(); sleep(3)
        snap("seconds-clock")
        let hour = String(format: "%02d", Calendar.current.component(.hour, from: Date()))
        // Static ClockPrefix + live day-long timer; together they must read HH:MM:SS.
        // Old bug: at 00:35:17 the only text was "35:17" (no prefix) → fails the joined check.
        let texts = ours.descendants(matching: .staticText).allElementsBoundByIndex.map(\.label)
        let joined = zip(texts, texts.dropFirst()).map { $0 + $1 } + texts
        let ok = joined.contains { $0.range(of: "^" + hour + ":[0-5][0-9]:[0-5][0-9]$", options: .regularExpression) != nil }
        if !ok { print("=== TEXTS seconds === \(texts)") }
        XCTAssertTrue(ok, "clock reads \(hour):MM:SS (texts: \(texts.prefix(4)))")
    }
}

extension WidgetFlowTests {
    /// 13. The three bottom layouts are selectable in Settings and each one renders (preview + widget).
    func test13_bottomLayouts() {
        // Ends on hourly (the default) so later tests and screenshots see the default layout.
        let options = [("spread", "Even spacing", "平均分配"), ("agenda", "Agenda", "行程清單"), ("hourly", "Hourly weather", "逐時天氣")]
        for (id, en, zh) in options {
            let app = XCUIApplication(); app.launch(); sleep(2)
            let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Bottom section' OR label BEGINSWITH '下半部'")).firstMatch
            for _ in 0..<5 where !picker.isHittable { app.swipeUp(); sleep(1) }
            XCTAssertTrue(picker.exists, "bottom-section picker found")
            picker.tap(); sleep(1)
            let item = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", en, zh)).firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 3), "option \(en) listed")
            item.tap(); sleep(1)
            XCTAssertTrue((picker.label as NSString).contains(en) || (picker.label as NSString).contains(zh), "picker shows \(en), got \(picker.label)")
            for _ in 0..<6 { app.swipeDown() }
            sleep(1); snap("layout-preview-\(id)")
            let done = app.buttons.matching(NSPredicate(format: "label == 'Done' OR label == '完成'")).firstMatch
            if done.exists { done.tap() }
            sleep(3)
            _ = scrollToWidget(); sleep(3)
            snap("layout-widget-\(id)")
        }
    }
}
