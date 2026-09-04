import XCTest

/// End-to-end m3u flow against a real, free public playlist (iptv-org,
/// ~10k channels): add the playlist through the login form, let the auto-sync
/// cover run the full import, then verify Live TV shows synced channels.
///
/// Run on a simulator where the app is not installed (or has no playlists) so
/// the root login form appears. Network access is required.
final class M3UPlaylistFlowTests: XCTestCase {
    private let playlistURL = "https://iptv-org.github.io/iptv/index.m3u"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAddM3UPlaylistSyncsAndShowsChannels() {
        let app = XCUIApplication()
        app.launch()

        // Fresh install shows the login form as root; otherwise add via Settings.
        if app.tabBars.firstMatch.waitForExistence(timeout: 5) {
            // Settings is a tab (not a sheet) — tap the gear tab bar item.
            let settingsTab = app.tabBars.buttons.element(boundBy: app.tabBars.buttons.count - 1)
            XCTAssertTrue(settingsTab.waitForExistence(timeout: 3))
            settingsTab.tap()
            let addButton = app.buttons["Add Playlist"]
            XCTAssertTrue(addButton.waitForExistence(timeout: 3))
            addButton.tap()
        }

        // Switch the form to the m3u source type.
        let m3uSegment = app.buttons["M3U Playlist"]
        XCTAssertTrue(m3uSegment.waitForExistence(timeout: 5))
        m3uSegment.tap()

        let nameField = app.textFields["e.g. My IPTV"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("iptv-org")

        let urlField = app.textFields["e.g. http://example.com/playlist.m3u"]
        urlField.tap()
        urlField.typeText(playlistURL)

        // An explicit (404ing) guide URL keeps the test deterministic: EPG
        // failures are non-fatal by design, while the playlist's own header
        // points at a multi-hundred-megabyte guide on a slow third-party host.
        // Trailing newline dismisses the keyboard — it otherwise covers the
        // submit button, and XCUITest taps don't scroll covered elements into view.
        let epgField = app.textFields["EPG URL (optional)"]
        epgField.tap()
        epgField.typeText("https://iptv-org.github.io/iptv/no-such-guide.xml\n")

        // More than one element can carry the "Add Playlist" label (navigation
        // title vs. submit button), so pick the hittable button.
        let submitCandidates = app.buttons.matching(identifier: "Add Playlist").allElementsBoundByIndex
        guard let addPlaylist = submitCandidates.last(where: { $0.isHittable && $0.isEnabled }) ?? submitCandidates.last else {
            return XCTFail("No Add Playlist button found")
        }
        if !addPlaylist.isHittable { app.swipeUp() }
        addPlaylist.tap()

        // Validation streams the playlist head, then the main tab bar appears.
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "Playlist was not accepted")

        // If the auto-sync cover is presented, wait for it to dismiss. (The
        // toolbar's manual-sync button is *always* labeled "Syncing" — the SF
        // Symbol's default accessibility label — so it can't signal progress.)
        let syncTitle = app.staticTexts["Syncing your playlist"]
        if syncTitle.waitForExistence(timeout: 10) {
            let dismissed = syncTitle.waitForNonExistence(timeout: 240)
            XCTAssertTrue(dismissed, "Sync did not finish within 4 minutes")
        }

        // Live TV must list synced categories/channels (SwiftUI exposes the
        // category chips and channel rows as buttons, not cells). The import
        // finishes within seconds of the playlist download, so a generous
        // existence wait doubles as the sync-completion wait.
        app.tabBars.buttons["Live TV"].tap()
        // Use case-insensitive match — iptv-org categories vary in casing ("News",
        // "NEWS", "news") and may be localized. Also accept any category button
        // as proof that content synced, since the exact first category depends
        // on the playlist revision.
        let anyCategory = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "news")).firstMatch
        let fallbackCategory = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "sport")).firstMatch
        let hasContent = anyCategory.waitForExistence(timeout: 180) || fallbackCategory.waitForExistence(timeout: 30)
        XCTAssertTrue(hasContent, "No Live TV content after m3u sync")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "LiveTV-after-m3u-sync"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}