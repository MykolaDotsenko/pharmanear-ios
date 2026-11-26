import XCTest

/// End-to-end flows on a simulator. The app reads its bundled catalog as of a fixed date and uses no network,
/// so every run sees the same real pharmacies.
final class PharmaNearUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["PHARMANEAR_CATALOG_DATE"] = "2026-11-26T12:00:00Z"
    }

    func testCitySearchListsTheNearestMappedPharmacyFirst() {
        launch()
        searchFromCity(expecting: "44 mapped pharmacies · Turku")

        let previews = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Map preview: "))
        XCTAssertEqual(previews.firstMatch.label, "Map preview: Yliopiston Apteekki")
        attachScreenshot("Turku results")
    }

    func testResultDetailsShowTheCatalogDateAndScope() {
        launch()
        searchFromCity(expecting: "44 mapped pharmacies · Turku")

        app.buttons["About these results"].tap()
        XCTAssertTrue(app.staticTexts["OSM catalog date: 2026-11-24"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Only pharmacies mapped in Finland are included."].exists)
        XCTAssertFalse(app.staticTexts["Search coverage is limited."].exists)
    }

    func testShowMoreExpandsAndCollapsesTheList() {
        launch()
        searchFromCity(expecting: "44 mapped pharmacies · Turku")

        let toggle = app.buttons["show-more"]
        XCTAssertEqual(toggle.label, "Show more pharmacies")
        toggle.tap()
        XCTAssertEqual(toggle.label, "Show fewer pharmacies")
        toggle.tap()
        XCTAssertEqual(toggle.label, "Show more pharmacies")
    }

    func testMapPreviewOpensAndClosesTheSheet() {
        launch()
        searchFromCity(expecting: "44 mapped pharmacies · Turku")

        app.buttons["Map preview: Yliopiston Apteekki"].tap()
        let sheet = app.navigationBars["Pharmacy map"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        attachScreenshot("Map preview")
        sheet.buttons["Close map"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(within: 5))
    }

    func testFinnishCopyAndPluralForms() {
        launch(language: "fi")
        XCTAssertTrue(app.staticTexts["Löydä apteekki läheltäsi."].waitForExistence(timeout: 5))
        searchFromCity(expecting: "44 kartoitettua apteekkia · Turku")
        attachScreenshot("Finnish results")
    }

    func testSwedishUsesOfficialCityNames() {
        launch(language: "sv")
        searchFromCity(expecting: "44 kartlagda apotek · Åbo")
        attachScreenshot("Swedish results")
    }

    func testStartAndResultScreensPassTheAccessibilityAudit() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("Accessibility audits need iOS 17 or later.") }
        launch()
        try app.performAccessibilityAudit()
        searchFromCity(expecting: "44 mapped pharmacies · Turku")
        try app.performAccessibilityAudit()
    }

    // MARK: Helpers

    private func launch(language: String = "en") {
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", "\(language)_FI"]
        app.launch()
    }

    /// Searches from the default city and waits until the status line reads `status`.
    private func searchFromCity(expecting status: String) {
        app.buttons["city-search"].tap()
        let line = app.staticTexts["search-status"]
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", status), object: line)
        let result = XCTWaiter.wait(for: [expectation], timeout: 10)
        XCTAssertEqual(result, .completed, "The status reads “\(line.label)” instead of “\(status)”")
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

extension XCUIElement {
    fileprivate func waitForNonExistence(within timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
