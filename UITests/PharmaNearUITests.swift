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

    private func launch(language: String = "en") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PHARMANEAR_CATALOG_DATE"] = "2026-11-26T12:00:00Z"
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", "\(language)_FI"]
        app.launch()
        return app
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

    /// Runs Apple's accessibility audit and logs every issue with the element it concerns. Navigation bar
    /// titles are exempt from the Dynamic Type check: by design they keep their size and offer the Large
    /// Content Viewer instead. Every other issue fails the test.
    @available(iOS 17.0, *)
    private func audit(_ app: XCUIApplication) throws {
        let navigationBar = app.navigationBars.firstMatch.frame
        try app.performAccessibilityAudit { issue in
            let element = issue.element
            print(
                "Accessibility audit: \(issue.compactDescription); type \(element?.elementType.rawValue ?? 0),",
                "label “\(element?.label ?? "")”, identifier “\(element?.identifier ?? "")”, frame \(element?.frame ?? .zero)"
            )
            if issue.auditType == .dynamicType, let element, navigationBar.contains(element.frame) { return true }
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
