import XCTest

/// Every link must open its own screen. Links were once matched to destinations by view position, and a
/// refreshing list could open the wrong screen (a recent record opened the scoring rules).
final class NavigationUITests: XCTestCase {
    /// The package's test clips (FLEURS, CC BY 4.0), seeded as demo analyses by debug builds.
    static let demoAudio = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Packages/EuphonaKit/Tests/EuphonaKitTests/Fixtures")
        .path(percentEncoded: false)

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testLinksOpenTheirOwnScreens() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding", "4", "-demo_audio", Self.demoAudio,
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let recent = app.buttons.matching(identifier: "today.recent")
        XCTAssertTrue(recent.firstMatch.waitForExistence(timeout: 120), "demo analyses were not seeded")
        let rules = app.buttons["How It’s Scored"]
        for index in 0..<min(recent.count, 3) {
            recent.element(boundBy: index).tap()
            XCTAssertTrue(rules.waitForExistence(timeout: 5), "recent record \(index) did not open its details")
            XCTAssertFalse(app.navigationBars["How It’s Scored"].exists)
            back(in: app)
        }

        recent.firstMatch.tap()
        rules.tap()
        XCTAssertTrue(app.navigationBars["How It’s Scored"].waitForExistence(timeout: 5))
        back(in: app)
        back(in: app)

        app.tabBars.buttons["Progress"].tap()
        open(link(startingWith: "Overall score", in: app), expecting: "Overall score", in: app)
        open(link(startingWith: "Activity", in: app), expecting: "Activity", in: app)
        open(link(startingWith: "All analyses", in: app), expecting: "All analyses", in: app)

        // Scrolling down minimizes the tab bar; scrolling back up restores it.
        app.swipeDown()
        app.tabBars.buttons["Practice"].tap()
        open(link(startingWith: "Piano", in: app), expecting: "Piano", in: app)
    }

    /// A card or row link, found by its accessibility label, which starts with its title.
    /// Scrolling the reading passage moves only the passage; the stage and the record button stay put.
    @MainActor
    func testScrollingThePassageKeepsTheLayout() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding", "4", "-demo_screen", "analysis",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let passage = app.scrollViews["analysis.passage"]
        XCTAssertTrue(passage.waitForExistence(timeout: 20))
        let title = app.staticTexts["Tap to start recording"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let before = (title.frame, passage.frame)
        passage.swipeUp()
        passage.swipeUp()
        sleep(1)
        XCTAssertEqual(title.frame, before.0, "the stage moved while scrolling the passage")
        XCTAssertEqual(passage.frame, before.1, "the passage card moved or resized while scrolling")
    }

    private func link(startingWith title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    private func open(_ link: XCUIElement, expecting title: String, in app: XCUIApplication) {
        if !link.isHittable { app.swipeUp() }
        link.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "\(title) did not open")
        back(in: app)
    }

    private func back(in app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }
}
