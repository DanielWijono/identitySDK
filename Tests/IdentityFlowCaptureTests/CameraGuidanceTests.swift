import CoreGraphics
import Testing
@testable import IdentityFlowCapture

@Test func rectangleGuidanceRequiresUsefulCoverageAndMargins() {
    var tracker = RectangleGuidanceTracker()
    #expect(tracker.update(nil).phase == .searching)
    #expect(tracker.update(CGRect(x: 0.3, y: 0.3, width: 0.3, height: 0.3)).phase == .moveCloser)
    #expect(tracker.update(CGRect(x: 0.01, y: 0.2, width: 0.7, height: 0.5)).phase == .keepInside)
}

@Test func rectangleGuidanceRequiresThreeStableObservations() {
    var tracker = RectangleGuidanceTracker()
    let bounds = CGRect(x: 0.12, y: 0.2, width: 0.76, height: 0.48)
    #expect(tracker.update(bounds).phase == .holdSteady)
    #expect(tracker.update(bounds.offsetBy(dx: 0.005, dy: -0.004)).phase == .holdSteady)
    #expect(tracker.update(bounds.offsetBy(dx: -0.004, dy: 0.003)).phase == .ready)
}

@Test func rectangleGuidanceResetsAfterLargeMovementOrLoss() {
    var tracker = RectangleGuidanceTracker()
    let bounds = CGRect(x: 0.12, y: 0.2, width: 0.76, height: 0.48)
    _ = tracker.update(bounds)
    _ = tracker.update(bounds)
    #expect(tracker.update(bounds.offsetBy(dx: 0.08, dy: 0)).phase == .holdSteady)
    #expect(tracker.update(nil).phase == .searching)
    #expect(tracker.update(bounds).phase == .holdSteady)
}
