import XCTest

/// Tests the initial state when the app launches with a seeded playlist.
/// The login form is bypassed via the -ui-testing launch argument.
final class LoginFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    func testAppShowsMainTabBarWithSeededData() {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
    }

    func testTabBarShowsAllTabs() {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.tabBars.buttons["Home"].exists)
        XCTAssertTrue(app.tabBars.buttons["Movies"].exists)
        XCTAssertTrue(app.tabBars.buttons["Series"].exists)
        XCTAssertTrue(app.tabBars.buttons["Live TV"].exists)
    }

    func testAddPlaylistButtonAvailableInSettings() {
        // Settings is a tab (not a sheet) — tap the gear tab bar item.
        let settingsTab = app.tabBars.buttons.element(boundBy: app.tabBars.buttons.count - 1)
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 3))
        settingsTab.tap()

        let addButton = app.buttons["Add Playlist"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
    }

    func testSeededPlaylistNameVisible() {
        // Navigate to the Settings tab where the playlist list lives.
        let settingsTab = app.tabBars.buttons.element(boundBy: app.tabBars.buttons.count - 1)
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 3))
        settingsTab.tap()

        // The playlist name appears as static text inside the Settings list.
        let playlistName = app.staticTexts["Test Playlist"]
        XCTAssertTrue(playlistName.waitForExistence(timeout: 5))
    }

    func testPlaylistCanBeDeleted() {
        // Navigate to the Settings tab.
        let settingsTab = app.tabBars.buttons.element(boundBy: app.tabBars.buttons.count - 1)
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 3))
        settingsTab.tap()

        let playlistName = app.staticTexts["Test Playlist"]
        XCTAssertTrue(playlistName.waitForExistence(timeout: 5))

        // Swipe left on the playlist row to reveal the Delete action.
        // Use a deliberate slow swipe to ensure SwiftUI's onDelete recognizes it.
        playlistName.swipeLeft(velocity: .slow)
        let deleteButton = app.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
    }

    func testServerConnectionNotVisibleWithSeededData() {
        let header = app.staticTexts["Server Connection"]
        XCTAssertFalse(header.waitForExistence(timeout: 2))
    }
}