import XCTest

@MainActor
final class SimulationUITests: XCTestCase {
    func testBackgroundCancelsAndForegroundAllowsAnotherRun() {
        let app = XCUIApplication()
        app.launch()
        app.switches["Agree to local demo"].tap()
        app.buttons["Start simulation"].tap()
        XCTAssertTrue(app.staticTexts["reviewHeading"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        app.activate()
        let result = app.staticTexts["simulationStatus"]
        expectation(for: NSPredicate(format: "label == %@", "Simulation cancelled. Temporary evidence was cleared."), evaluatedWith: result)
        waitForExpectations(timeout: 10)
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["Start simulation"])
        waitForExpectations(timeout: 10)
        app.buttons["Start simulation"].tap()
        confirmBothSides(app)
        expectation(for: NSPredicate(format: "label == %@", "Simulated approval. No identity was verified."), evaluatedWith: result)
        waitForExpectations(timeout: 10)
    }

    func testConsentAndOutcomes() {
        let app = XCUIApplication()
        app.launch()
        let start = app.buttons["Start simulation"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertFalse(start.isEnabled)
        app.switches["Agree to local demo"].tap()
        let outcomes = [
            ("Approve", "Simulated approval. No identity was verified."),
            ("Reject", "Simulated rejection. No identity was evaluated."),
            ("Pending", "Simulated pending result. No real server is processing this demo."),
            ("Failure", "Simulated technical failure. Temporary evidence was cleared. You can try again.")
        ]
        for (choice, expected) in outcomes {
            app.segmentedControls.buttons[choice].tap()
            start.tap()
            confirmBothSides(app)
            let result = app.staticTexts["simulationStatus"]
            let predicate = NSPredicate(format: "label == %@", expected)
            expectation(for: predicate, evaluatedWith: result)
            waitForExpectations(timeout: 10)
            XCTAssertTrue(start.isEnabled)
        }
    }

    func testCancellationAllowsRestart() {
        let app = XCUIApplication()
        app.launch()
        app.switches["Agree to local demo"].tap()
        app.buttons["Start simulation"].tap()
        XCTAssertTrue(app.staticTexts["reviewHeading"].waitForExistence(timeout: 10))
        app.buttons["Cancel simulation"].tap()
        let result = app.staticTexts["simulationStatus"]
        expectation(for: NSPredicate(format: "label == %@", "Simulation cancelled. Temporary evidence was cleared."), evaluatedWith: result)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.buttons["Start simulation"].isEnabled)
    }

    func testRetakeKeepsReviewOnSameSideUntilConfirmed() {
        let app = XCUIApplication()
        app.launch()
        app.switches["Agree to local demo"].tap()
        app.buttons["Start simulation"].tap()
        let heading = app.staticTexts["reviewHeading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        XCTAssertEqual(heading.label, "Review front · Take 1")
        app.buttons["Retake"].tap()
        XCTAssertEqual(heading.label, "Review front · Take 2")
        app.buttons["Use this image"].tap()
        expectation(for: NSPredicate(format: "label == %@", "Review back · Take 1"), evaluatedWith: heading)
        waitForExpectations(timeout: 10)
        app.buttons["Retake"].tap()
        XCTAssertEqual(heading.label, "Review back · Take 2")
        app.buttons["Cancel simulation"].tap()
        expectation(for: NSPredicate(format: "label == %@", "Simulation cancelled. Temporary evidence was cleared."), evaluatedWith: app.staticTexts["simulationStatus"])
        waitForExpectations(timeout: 10)
        XCTAssertFalse(heading.exists)
        XCTAssertTrue(app.buttons["Start simulation"].isEnabled)
    }

    func testSimulatorCameraChoiceIsRecoverable() {
        let app = XCUIApplication()
        app.launch()
        app.segmentedControls.buttons["Live camera"].tap()
        app.switches["Agree to local demo"].tap()
        app.buttons["Start simulation"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "physical iPhone"), evaluatedWith: app.staticTexts["simulationStatus"])
        waitForExpectations(timeout: 10)
        app.segmentedControls.buttons["Generated cards"].tap()
        app.buttons["Start simulation"].tap()
        XCTAssertTrue(app.staticTexts["reviewHeading"].waitForExistence(timeout: 10))
        app.buttons["Cancel simulation"].tap()
    }

    private func confirmBothSides(_ app: XCUIApplication) {
        let heading = app.staticTexts["reviewHeading"]
        for side in ["front", "back"] {
            expectation(for: NSPredicate(format: "label == %@", "Review \(side) · Take 1"), evaluatedWith: heading)
            waitForExpectations(timeout: 10)
            app.buttons["Use this image"].tap()
        }
    }

}
