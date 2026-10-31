import XCTest

@MainActor
final class SubscriptionFlowTests: XCTestCase {
    func testSelectReviewAndCancelWithoutOpeningACalendar() {
        checkReview(largeText: false)
    }

    func testReviewFitsAccessibilityTextSizes() {
        checkReview(largeText: true)
    }

    private func checkReview(largeText: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        if largeText {
            app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        let selection = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "select.")).firstMatch
        XCTAssertTrue(selection.waitForExistence(timeout: 15))
        if selection.value as? String != "Selected" { selection.tap() }
        let review = app.buttons["reviewSelection"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertTrue(review.isHittable)
        review.tap()
        let approve = app.buttons["Approve & Continue"]
        XCTAssertTrue(approve.waitForExistence(timeout: 5))
        XCTAssertTrue(approve.isEnabled)
        XCTAssertTrue(approve.isHittable)
        let defaultCalendar = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Default Calendar,"))
            .firstMatch
        for _ in 0..<8 {
            if defaultCalendar.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(defaultCalendar.isHittable)
        // Stop before approval: these UI tests never fetch a feed or subscribe an account.
        app.buttons["Finish Later"].tap()
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        app.terminate()
    }
}
