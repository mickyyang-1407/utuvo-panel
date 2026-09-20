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

    /// 1. In the app: pick the synthetic screenshot from Photos so the widget gets a background.
    func test1_pickScreenshot() {
        let app = XCUIApplication()
        app.launch()
        let pick = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '選你的桌布' OR label == '換桌布' OR label BEGINSWITH 'Choose your wallpaper' OR label == 'Change wallpaper'")).firstMatch
        XCTAssertTrue(pick.waitForExistence(timeout: 10), "picker button")
        pick.tap()
        // PhotosPicker is remote UI; find the first photo cell.
        let picker = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
        sleep(3)
        let images = app.images.matching(NSPredicate(format: "label CONTAINS 'Photo' OR label CONTAINS '照片' OR label CONTAINS 'Screenshot' OR label CONTAINS '截圖'"))
        if images.firstMatch.waitForExistence(timeout: 8) {
            images.firstMatch.tap()
        } else {
            dump(app, "photos-picker"); dump(picker, "photos-app")
            // Fallback: tap the first cell in the grid area.
            let w = app.frame.width, h = app.frame.height
            app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: w * 0.15, dy: h * 0.3)).tap()
        }
        sleep(3)
        snap("app-after-pick")
        // The row sits under the panel preview; Form is lazy, so it is not in the tree until scrolled to.
        app.swipeUp(); sleep(1)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == '移除背景' OR label == 'Remove background'")).firstMatch.waitForExistence(timeout: 10), "background saved → 移除背景 visible")
        dump(app, "app-after-pick")
    }

    /// 2. On the home screen: add the extra-large-portrait widget.
    func test2_addWidget() {
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
    }
}

extension WidgetFlowTests {
    /// 3. Walk the home pages, screenshot each, and print our widget's on-screen frame.
    func test3_locateWidget() {
        XCUIDevice.shared.press(.home); sleep(1)
        springboard.swipeRight(); sleep(1); springboard.swipeRight(); sleep(1)
        for page in 0..<4 {
            snap("page-\(page)")
            let ours = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'UTUVO Panel' OR identifier CONTAINS 'UTUVOPanel' OR identifier CONTAINS 'glasspanel'"))
            let snapshot = ours.allElementsBoundByIndex
            for e in snapshot.prefix(5) {
                print("=== OURS page \(page) type=\(e.elementType.rawValue) label=\(e.label) id=\(e.identifier) frame=\(e.frame) screen=\(springboard.frame)")
            }
            if !snapshot.isEmpty { print("=== FOUND on page \(page)") }
            springboard.swipeLeft(); sleep(1)
        }
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
    private func scrollToWidget() -> XCUIElement {
        XCUIDevice.shared.press(.home); sleep(1)
        springboard.swipeRight(); sleep(1)
        let ours = springboard.descendants(matching: .any).matching(NSPredicate(format: "label == 'UTUVO Panel' AND value CONTAINS 'Widget'")).firstMatch
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
    /// 7a. Screenshot an empty home page (the one before App Library) — the "blank wallpaper" the user would take.
    func test7a_emptyPageScreenshot() {
        XCUIDevice.shared.press(.home); sleep(1)
        for _ in 0..<3 { springboard.swipeRight(); usleep(500_000) }
        // Walk right until the page has no icons/widgets and no App Library search field.
        for page in 0..<6 {
            let icons = springboard.icons.allElementsBoundByIndex.filter { $0.frame.minX >= 0 && $0.frame.maxX <= springboard.frame.width && $0.isHittable }
            let inLibrary = springboard.searchFields["dewey-search-field"].exists && springboard.searchFields["dewey-search-field"].isHittable
            print("=== PAGE \(page) icons=\(icons.count) library=\(inLibrary)")
            if icons.isEmpty && !inLibrary { break }
            if inLibrary { XCTFail("no empty page before App Library"); return }
            springboard.swipeLeft(); sleep(1)
        }
        sleep(1)
        snap("empty-page")
    }

    /// 7b. Pick the newest photo (last in Recents) — the screenshot added by the runner.
    func test7b_pickNewest() {
        let app = XCUIApplication()
        app.launch()
        let pick = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '選你的桌布' OR label == '換桌布' OR label BEGINSWITH 'Choose your wallpaper' OR label == 'Change wallpaper'")).firstMatch
        XCTAssertTrue(pick.waitForExistence(timeout: 10))
        pick.tap()
        sleep(3)
        let images = app.images.matching(NSPredicate(format: "label CONTAINS 'Photo' OR label CONTAINS '照片' OR label CONTAINS 'Screenshot' OR label CONTAINS '截圖'"))
        XCTAssertTrue(images.firstMatch.waitForExistence(timeout: 8))
        let all = images.allElementsBoundByIndex
        print("=== PICKER \(all.count) images: \(all.map(\.label))")
        all.last!.tap()
        sleep(3)
        app.swipeUp(); sleep(1)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == '移除背景' OR label == 'Remove background'")).firstMatch.waitForExistence(timeout: 10),
                      "background saved (label is localised — do not hard-code the zh string)")
        snap("app-after-pick-newest")
    }
}

extension WidgetFlowTests {
    /// 8. Find the app icon on whatever page it lives and screenshot that page.
    func test8_appIcon() {
        XCUIDevice.shared.press(.home); sleep(1)
        for _ in 0..<3 { springboard.swipeRight(); usleep(400_000) }
        let icon = springboard.icons.matching(NSPredicate(format: "label == 'UTUVO Panel' AND NOT (value CONTAINS 'Widget')")).firstMatch
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
        w.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.width * 0.6, dy: f.height * 0.22)).tap()
        let cal = XCUIApplication(bundleIdentifier: "com.apple.mobilecal")
        let ok = cal.wait(for: .runningForeground, timeout: 10)
        sleep(1); snap("after-calendar-tap")
        XCTAssertTrue(ok, "Calendar came to the foreground")
    }
}
