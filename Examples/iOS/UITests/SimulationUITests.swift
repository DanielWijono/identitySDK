import XCTest

@MainActor
final class SimulationUITests: XCTestCase {
    func testBackgroundCancelsAndForegroundAllowsAnotherRun() {
        let app = XCUIApplication()
        app.launch()
        app.switches["Agree to synthetic demo"].tap()
        app.buttons["Start simulation"].tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        let result = app.staticTexts["simulationStatus"]
        expectation(for: NSPredicate(format: "label == %@", "Simulation cancelled. Synthetic evidence was cleared."), evaluatedWith: result)
        waitForExpectations(timeout: 10)
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["Start simulation"])
        waitForExpectations(timeout: 10)
        app.buttons["Start simulation"].tap()
        expectation(for: NSPredicate(format: "label == %@", "Simulated approval. No identity was verified."), evaluatedWith: result)
        waitForExpectations(timeout: 10)
    }

    func testConsentAndOutcomes() {
        let app = XCUIApplication()
        app.launch()
        let start = app.buttons["Start simulation"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertFalse(start.isEnabled)
        app.switches["Agree to synthetic demo"].tap()
        let outcomes = [
            ("Approve", "Simulated approval. No identity was verified."),
            ("Reject", "Simulated rejection. No identity was evaluated."),
            ("Pending", "Simulated pending result. No real server is processing this demo."),
            ("Failure", "Simulated technical failure. Synthetic evidence was cleared. You can try again.")
        ]
        for (choice, expected) in outcomes {
            app.segmentedControls.buttons[choice].tap()
            start.tap()
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
        app.switches["Agree to synthetic demo"].tap()
        app.buttons["Start simulation"].tap()
        app.buttons["Cancel simulation"].tap()
        let result = app.staticTexts["simulationStatus"]
        expectation(for: NSPredicate(format: "label == %@", "Simulation cancelled. Synthetic evidence was cleared."), evaluatedWith: result)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.buttons["Start simulation"].isEnabled)
    }
}
