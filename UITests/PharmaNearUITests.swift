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
        XCTAssertEqual(toggle.label, "Show fewer pharmacies")
        toggle.tap()
        XCTAssertEqual(toggle.label, "Show more pharmacies")
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
        try app.performAccessibilityAudit()
        searchFromCity(in: app, expecting: "44 mapped pharmacies · Turku")
        try app.performAccessibilityAudit()
    }

    // MARK: Helpers

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
        let line = app.staticTexts["search-status"]
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", status), object: line)
        let result = XCTWaiter.wait(for: [expectation], timeout: 10)
        XCTAssertEqual(result, .completed, "The status reads “\(line.label)” instead of “\(status)”")
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
