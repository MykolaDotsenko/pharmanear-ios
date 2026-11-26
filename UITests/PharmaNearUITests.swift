import XCTest

/// End-to-end flows on a simulator. The app reads its bundled catalog as of a fixed date and uses no network,
/// so every run sees the same real pharmacies.
@MainActor
final class PharmaNearUITests: XCTestCase {
    func testCitySearchListsTheNearestMappedPharmacyFirst() {
        let app = launch()
        searchFromCity(in: app, expecting: "44 mapped pharmacies · Turku")

        let previews = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Map preview: "))
        XCTAssertEqual(previews.firstMatch.label, "Map preview: Yliopiston Apteekki")
        attachScreenshot(of: app, named: "Turku results")
    }

    func testResultDetailsShowTheCatalogDateAndScope() {
        let app = launch()
        searchFromCity(in: app, expecting: "44 mapped pharmacies · Turku")

        app.buttons["About these results"].tap()
        XCTAssertTrue(app.staticTexts["OSM catalog date: 2026-11-24"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Only pharmacies mapped in Finland are included."].exists)
        XCTAssertFalse(app.staticTexts["Search coverage is limited."].exists)
    }

    func testShowMoreExpandsAndCollapsesTheList() {
        let app = launch()
        searchFromCity(in: app, expecting: "44 mapped pharmacies · Turku")

        let toggle = app.buttons["show-more"]
        XCTAssertEqual(toggle.label, "Show more pharmacies")
        toggle.tap()
        wait(for: toggle, toRead: "Show fewer pharmacies")
        // Twenty rows push the button below the fold.
        scrollIntoView(toggle, in: app)
        toggle.tap()
        wait(for: toggle, toRead: "Show more pharmacies")
    }

    func testMapPreviewOpensAndClosesTheSheet() {
        let app = launch()
        searchFromCity(in: app, expecting: "44 mapped pharmacies · Turku")

        app.buttons["Map preview: Yliopiston Apteekki"].tap()
        let sheet = app.navigationBars["Pharmacy map"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "Map preview")
        sheet.buttons["Close map"].tap()
        XCTAssertTrue(disappears(sheet))
    }

    func testFinnishCopyAndPluralForms() {
        let app = launch(language: "fi")
        XCTAssertTrue(app.staticTexts["Löydä apteekki läheltäsi."].waitForExistence(timeout: 5))
        searchFromCity(in: app, expecting: "44 kartoitettua apteekkia · Turku")
        attachScreenshot(of: app, named: "Finnish results")
    }

    func testSwedishUsesOfficialCityNames() {
        let app = launch(language: "sv")
        searchFromCity(in: app, expecting: "44 kartlagda apotek · Åbo")
        attachScreenshot(of: app, named: "Swedish results")
    }

    func testStartAndResultScreensPassTheAccessibilityAudit() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("Accessibility audits need iOS 17 or later.") }
        let app = launch()
        try audit(app)
        searchFromCity(in: app, expecting: "44 mapped pharmacies · Turku")
        try audit(app)
    }

    /// Dynamic Type at the largest accessibility size: a row's text grows with the setting and wraps within the
    /// screen instead of being cut off. Measured directly, because the audit's own Dynamic Type heuristic
    /// flags a different, correctly scaling SwiftUI text on each run.
    func testTheLargestTextSizeWrapsRowsInsteadOfCuttingThemOff() {
        let regular = launch()
        searchFromCity(in: regular, expecting: "44 mapped pharmacies · Turku")
        let regularAddress = regular.staticTexts["Yliopistonkatu 18 Turku"]
        reveal(regularAddress, in: regular)
        let regularHeight = regularAddress.frame.height
        regular.terminate()

        let large = launch(textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        searchFromCity(in: large, expecting: "44 mapped pharmacies · Turku")
        let address = large.staticTexts["Yliopistonkatu 18 Turku"]
        reveal(address, in: large)
        // Two lines or more at a several times larger font: it wrapped rather than being truncated to one line.
        XCTAssertGreaterThan(address.frame.height, regularHeight * 4)
        XCTAssertLessThanOrEqual(address.frame.maxX, large.windows.firstMatch.frame.maxX + 1)
        attachScreenshot(of: large, named: "Largest text")
    }

    func testRadarOpensFromARowOnThatPharmacy() throws {
        let app = launch()
        searchFromCity(in: app, expecting: "44 mapped pharmacies · Turku")
        let radar = app.buttons["Radar: Yliopiston Apteekki"]
        scrollIntoView(radar, in: app)
        radar.tap()
        allowLocationIfAsked()
        XCTAssertTrue(app.navigationBars["Pharmacy radar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Yliopiston Apteekki"].exists)
        // CI places the simulator in central Turku, so the radar gets live fixes.
        XCTAssertTrue(app.staticTexts["Live GPS"].waitForExistence(timeout: 20))
        attachScreenshot(of: app, named: "Radar")
        if #available(iOS 17.0, *) { try audit(app) }
        app.buttons["Close radar"].tap()
        XCTAssertTrue(disappears(app.navigationBars["Pharmacy radar"]))
    }

    // MARK: Helpers

    /// Answers the system location prompt when the radar is the first to ask.
    private func allowLocationIfAsked() {
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
    }

    private func launch(language: String = "en", textSize: String? = nil) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PHARMANEAR_CATALOG_DATE"] = "2026-11-26T12:00:00Z"
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", "\(language)_FI"]
        if let textSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize] }
        app.launch()
        return app
    }

    /// Scrolls until `element` exists and can be tapped; lazily built rows appear only when scrolled to.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(element.exists, "\(element) never appeared")
    }

    /// Searches from the default city and waits until the status line reads `status`.
    private func searchFromCity(in app: XCUIApplication, expecting status: String) {
        app.buttons["city-search"].tap()
        wait(for: app.staticTexts["search-status"], toRead: status)
    }

    private func wait(for element: XCUIElement, toRead label: String) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", label), object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: 10)
        XCTAssertEqual(result, .completed, "“\(element.label)” instead of “\(label)”")
    }

    private func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 where !element.isHittable {
            app.swipeUp()
        }
    }

    /// Runs Apple's accessibility audit and logs every issue with the element it concerns; any issue fails the
    /// test. Its Dynamic Type heuristic is left out: it flagged a different, correctly scaling SwiftUI text on
    /// each run, so the largest text size is tested directly instead (testTheLargestTextSize…). Contrast,
    /// clipped text, hit regions, element descriptions and traits are all audited.
    @available(iOS 17.0, *)
    private func audit(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit(for: XCUIAccessibilityAuditType.all.subtracting(.dynamicType)) { issue in
            let element = issue.element
            print(
                "Accessibility audit: \(issue.compactDescription); type \(element?.elementType.rawValue ?? 0),",
                "label “\(element?.label ?? "")”, identifier “\(element?.identifier ?? "")”, frame \(element?.frame ?? .zero)"
            )
            return false
        }
    }

    private func disappears(_ element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
