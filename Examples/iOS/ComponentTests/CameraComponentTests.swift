import XCTest
import AVFoundation
import UIKit
import IdentityFlowCapture
import IdentityFlowUI
@testable import UIKitSample

private actor FakeCamera: CameraDevice {
    var starts = 0
    var stops = 0
    var captures = 0
    let bytes: Data
    let hold: Bool
    private var pending: CheckedContinuation<Data, Never>?
    private var events: (@Sendable (CameraEvent) -> Void)?
    init(bytes: Data, hold: Bool = false) { self.bytes = bytes; self.hold = hold }
    func start(events: @escaping @Sendable (CameraEvent) -> Void) { starts += 1; self.events = events }
    func capture() async -> Data {
        captures += 1
        if hold { return await withCheckedContinuation { pending = $0 } }
        return bytes
    }
    // Intentionally uncooperative: completion may arrive after stop.
    func stop() { stops += 1 }
    func completeLate() { pending?.resume(returning: bytes); pending = nil }
    func interrupt() { events?(.interrupted) }
}

private actor NativePreviewCamera: CameraDevice {
    var stops = 0
    @MainActor func makePreviewLayer() -> AVCaptureVideoPreviewLayer? {
        AVCaptureVideoPreviewLayer(session: AVCaptureSession())
    }
    func start(events: @escaping @Sendable (CameraEvent) -> Void) {}
    func capture() async throws -> Data { throw CameraError.captureFailed }
    func stop() { stops += 1 }
}

@MainActor
final class CameraComponentTests: XCTestCase {
    private func jpeg() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 100, height: 60)).jpegData(withCompressionQuality: 0.9) { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 60))
        }
    }
    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
    private func button(_ title: String, _ controller: UIViewController) -> UIButton {
        descendants(controller.view).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == title }!
    }
    private func message(_ controller: UIViewController) -> String {
        descendants(controller.view).compactMap { $0 as? UILabel }.first { $0.accessibilityIdentifier == "cameraStatus" }?.text ?? ""
    }
    private func until(_ condition: @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { XCTFail("Timed out waiting for camera state"); throw CameraError.captureFailed }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func testConfirmedImageDeliveredOnceAfterReview() async throws {
        let camera = FakeCamera(bytes: jpeg())
        let screen = CameraReviewViewController(sideDescription: "front", makeCamera: { camera })
        var results: [Data] = []
        screen.onConfirm = { results.append($0) }
        screen.loadViewIfNeeded()
        try await until { self.button("Take photo", screen).isEnabled }
        button("Take photo", screen).sendActions(for: .touchUpInside)
        try await until { !self.button("Preview crop", screen).isHidden }
        XCTAssertTrue(button("Use this image", screen).isHidden)
        button("Use this image", screen).sendActions(for: .touchUpInside)
        XCTAssertTrue(results.isEmpty)
        let sliders = descendants(screen.view).compactMap { $0 as? UISlider }
        sliders[0].value = 0.25
        sliders[0].sendActions(for: .valueChanged)
        button("Preview crop", screen).sendActions(for: .touchUpInside)
        try await until { !self.button("Use this image", screen).isHidden }
        XCTAssertTrue(results.isEmpty)
        button("Use this image", screen).sendActions(for: .touchUpInside)
        button("Use this image", screen).sendActions(for: .touchUpInside)
        XCTAssertEqual(results.count, 1)
        let output = try XCTUnwrap(UIImage(data: results[0])?.cgImage)
        let original = try XCTUnwrap(UIImage(data: jpeg())?.cgImage)
        XCTAssertEqual(output.width, Int(ceil(Double(original.width) * 0.75)))
        XCTAssertEqual(output.height, original.height)
        XCTAssertTrue(descendants(screen.view).compactMap { $0 as? UIImageView }.allSatisfy { $0.image == nil })
    }

    func testRetakeRestartsCameraAndCancelIsIdempotent() async throws {
        let camera = FakeCamera(bytes: jpeg())
        let screen = CameraReviewViewController(sideDescription: "back", makeCamera: { camera })
        var cancelled = 0
        screen.onCancel = { cancelled += 1 }
        screen.loadViewIfNeeded()
        try await until { self.button("Take photo", screen).isEnabled }
        button("Take photo", screen).sendActions(for: .touchUpInside)
        try await until { !self.button("Preview crop", screen).isHidden }
        button("Preview crop", screen).sendActions(for: .touchUpInside)
        try await until { !self.button("Use this image", screen).isHidden }
        button("Retake", screen).sendActions(for: .touchUpInside)
        try await until { await camera.starts == 2 && self.button("Take photo", screen).isEnabled }
        XCTAssertTrue(button("Use this image", screen).isHidden)
        screen.cancelCapture()
        screen.cancelCapture()
        XCTAssertEqual(cancelled, 1)
    }

    func testLatePhotoCannotRestoreReviewAfterCancellation() async throws {
        let camera = FakeCamera(bytes: jpeg(), hold: true)
        let screen = CameraReviewViewController(sideDescription: "front", makeCamera: { camera })
        var delivered = false
        screen.onConfirm = { _ in delivered = true }
        screen.loadViewIfNeeded()
        try await until { self.button("Take photo", screen).isEnabled }
        button("Take photo", screen).sendActions(for: .touchUpInside)
        try await until { await camera.captures == 1 }
        screen.cancelCapture()
        await camera.completeLate()
        try await until { await camera.stops > 0 }
        // Drain the queued completion so this checks late delivery, not just immediate cancellation.
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(delivered)
        XCTAssertTrue(button("Use this image", screen).isHidden)
        XCTAssertTrue(descendants(screen.view).compactMap { $0 as? UIImageView }.allSatisfy { $0.image == nil })
    }

    func testBadPhotoAndInterruptionOfferRetry() async throws {
        let camera = FakeCamera(bytes: Data("invalid".utf8))
        let screen = CameraReviewViewController(sideDescription: "front", makeCamera: { camera })
        screen.loadViewIfNeeded()
        try await until { self.button("Take photo", screen).isEnabled }
        button("Take photo", screen).sendActions(for: .touchUpInside)
        try await until { self.message(screen).contains("could not be prepared") }
        XCTAssertTrue(button("Use this image", screen).isHidden)
        button("Retake", screen).sendActions(for: .touchUpInside)
        try await until { self.button("Take photo", screen).isEnabled }
        await camera.interrupt()
        try await until { self.message(screen).contains("interrupted") }
        button("Retake", screen).sendActions(for: .touchUpInside)
        try await until { await camera.starts == 3 && self.button("Take photo", screen).isEnabled }
        screen.cancelCapture()
    }

    func testInactivityClearsReviewAndCancels() async throws {
        let camera = FakeCamera(bytes: jpeg())
        let screen = CameraReviewViewController(sideDescription: "front", makeCamera: { camera })
        var cancelled = false
        screen.onCancel = { cancelled = true }
        screen.loadViewIfNeeded()
        try await until { self.button("Take photo", screen).isEnabled }
        button("Take photo", screen).sendActions(for: .touchUpInside)
        try await until { !self.button("Preview crop", screen).isHidden }
        button("Preview crop", screen).sendActions(for: .touchUpInside)
        try await until { !self.button("Use this image", screen).isHidden }
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertTrue(cancelled)
        XCTAssertTrue(descendants(screen.view).compactMap { $0 as? UIImageView }.allSatisfy { $0.image == nil })
    }

    func testReleasingUnpresentedScreenStopsCamera() async throws {
        let camera = FakeCamera(bytes: jpeg())
        var screen: CameraReviewViewController? = CameraReviewViewController(sideDescription: "front", makeCamera: { camera })
        let isReleased = { [weak screen] in screen == nil }
        screen?.loadViewIfNeeded()
        try await until { await camera.starts == 1 }
        screen = nil
        try await until {
            let stops = await camera.stops
            return isReleased() && stops > 0
        }
    }

    func testStoppedDeviceRejectsWorkAndSimulatorDoesNotRequestPermission() async throws {
        let camera = StillCamera()
        await camera.stop()
        do { try await camera.start { _ in }; XCTFail("Stopped camera started") }
        catch { XCTAssertEqual(error as? CameraError, .stopped) }
        do { _ = try await camera.capture(); XCTFail("Stopped camera captured") }
        catch { XCTAssertEqual(error as? CameraError, .stopped) }
        #if targetEnvironment(simulator)
        XCTAssertEqual(CameraAuthorization.current, .unavailable)
        let authorization = await CameraAuthorization.request()
        XCTAssertEqual(authorization, .unavailable)
        #endif
    }

    func testNativePreviewLayerIsAttachedAndRemovedOnCancel() async throws {
        let camera = NativePreviewCamera()
        let screen = CameraReviewViewController(sideDescription: "front", makeCamera: { camera })
        screen.loadViewIfNeeded()
        try await until { self.button("Take photo", screen).isEnabled }
        let preview = try XCTUnwrap(descendants(screen.view).compactMap { $0 as? UIImageView }.first)
        XCTAssertTrue(preview.layer.sublayers?.contains { $0 is AVCaptureVideoPreviewLayer } == true)
        screen.cancelCapture()
        XCTAssertFalse(preview.layer.sublayers?.contains { $0 is AVCaptureVideoPreviewLayer } == true)
    }
    func testLiveAdapterSequencesSidesAndRejectsCallbacksAfterCancel() async throws {
        let host = UIViewController()
        host.loadViewIfNeeded()
        let cover = UIView(), background = UIView()
        host.view.addSubview(background)
        host.view.addSubview(cover)
        let camera = FakeCamera(bytes: jpeg())
        var screens: [CameraReviewViewController] = []
        var cancellationRequests = 0
        let capture = LiveCardCapture(host: host, privacyCover: cover, background: background,
            makeScreen: { description in
                let screen = CameraReviewViewController(sideDescription: description, makeCamera: { camera })
                screens.append(screen)
                return screen
            }, onCancel: { cancellationRequests += 1 })
        let front = Task { try await capture.confirmedJPEG(for: .front) }
        try await until { screens.count == 1 }
        XCTAssertTrue(background.isHidden)
        XCTAssertTrue(host.children.first === screens[0])
        XCTAssertTrue(host.view.subviews.last === cover)
        let bytes = jpeg()
        screens[0].onConfirm?(bytes)
        let result = try await front.value
        XCTAssertEqual(result, bytes)
        XCTAssertTrue(host.children.isEmpty)
        XCTAssertFalse(background.isHidden)
        let back = Task { try await capture.confirmedJPEG(for: .back) }
        try await until { screens.count == 2 }
        let lateConfirm = screens[1].onConfirm
        screens[1].onCancel?()
        XCTAssertEqual(cancellationRequests, 1)
        capture.hidePreview()
        lateConfirm?(bytes)
        capture.cancel()
        capture.cancel()
        do { _ = try await back.value; XCTFail("Cancelled capture returned bytes") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(host.children.isEmpty)
        do { _ = try await capture.confirmedJPEG(for: .front); XCTFail("Cancelled adapter restarted") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

}
