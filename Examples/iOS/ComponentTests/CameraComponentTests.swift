import XCTest
import AVFoundation
import os
import SwiftUI
import UIKit
import IdentityFlowCapture
@testable import IdentityFlowUI
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
    func guide(_ guidance: CameraGuidance) { events?(.guidance(guidance)) }
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
        descendants(controller.view).compactMap { $0 as? UILabel }.first {
            $0.accessibilityIdentifier == "cameraStatus" || $0.accessibilityIdentifier == "simulationStatus"
        }?.text ?? ""
    }
    private func cameraController(in root: UIViewController) -> CameraReviewViewController? {
        if let camera = root as? CameraReviewViewController { return camera }
        return root.children.lazy.compactMap(cameraController).first
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

    func testRectangleGuidanceUpdatesStatusWithoutBlockingManualShutter() async throws {
        let camera = FakeCamera(bytes: jpeg())
        let screen = CameraReviewViewController(sideDescription: "front", makeCamera: { camera })
        screen.loadViewIfNeeded()
        try await until { self.button("Take photo", screen).isEnabled }
        await camera.guide(CameraGuidance(bounds: CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.5),
                                           phase: .ready))
        try await until { self.message(screen).contains("detected and steady") }
        XCTAssertTrue(button("Take photo", screen).isEnabled)
        screen.cancelCapture()
    }

    func testRepeatedHardwareLifecycleAndDuplicateStart() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Repeated AVFoundation lifecycle requires a physical iPhone")
        #else
        guard CameraAuthorization.current == .authorized else {
            throw XCTSkip("Grant camera permission in UIKitSample before running the hardware lifecycle test")
        }
        var readiness: [TimeInterval] = []
        for iteration in 0..<30 {
            let camera = StillCamera()
            let preview = camera.makePreviewLayer()
            let start = ProcessInfo.processInfo.systemUptime
            try await camera.start { _ in }
            readiness.append(ProcessInfo.processInfo.systemUptime - start)
            if iteration == 0 {
                do {
                    try await camera.start { _ in }
                    XCTFail("A running camera accepted a duplicate start")
                } catch {
                    XCTAssertEqual(error as? CameraError, .busy)
                }
            }
            await camera.stop()
            preview?.session = nil
        }
        let sorted = readiness.sorted()
        let p95 = sorted[Int((Double(sorted.count - 1) * 0.95).rounded(.up))]
        XCTAssertLessThanOrEqual(p95, 1.5, "Camera readiness p95 was \(p95) seconds: \(readiness)")
        #endif
    }

    func testSwiftUIWrapperCreatesSharedControllerAndForwardsCancellation() async throws {
        let camera = FakeCamera(bytes: jpeg())
        var cancellations = 0
        let view = CameraReviewView(sideDescription: "front", makeCamera: { camera },
                                    onConfirm: { _ in }, onCancel: { cancellations += 1 })
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.isHidden = false
        host.loadViewIfNeeded()
        try await until {
            guard let screen = self.cameraController(in: host) else { return false }
            return self.button("Take photo", screen).isEnabled
        }
        let screen = try XCTUnwrap(cameraController(in: host))
        screen.cancelCapture()
        XCTAssertEqual(cancellations, 1)
        window.isHidden = true
    }

    func testDeniedCameraPermissionOffersSettingsAndRechecksOnActivation() async throws {
        let current = OSAllocatedUnfairLock(initialState: CameraAuthorization.denied)
        var settingsOpens = 0
        let screen = SimulationViewController(
            requestCameraAuthorization: { .denied },
            currentCameraAuthorization: { current.withLock { $0 } },
            openCameraSettings: { settingsOpens += 1 }
        )
        screen.loadViewIfNeeded()
        let testCamera = try XCTUnwrap(descendants(screen.view).compactMap { $0 as? UIButton }
            .first { $0.currentTitle == "Test live camera" })
        testCamera.sendActions(for: .touchUpInside)
        try await until { self.message(screen).contains("Camera access is off") }
        let settings = try XCTUnwrap(descendants(screen.view).compactMap { $0 as? UIButton }
            .first { $0.accessibilityIdentifier == "openCameraSettings" })
        XCTAssertFalse(settings.isHidden)
        settings.sendActions(for: .touchUpInside)
        XCTAssertEqual(settingsOpens, 1)
        current.withLock { $0 = .authorized }
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        try await until { self.message(screen).contains("Camera access is enabled") }
        XCTAssertTrue(settings.isHidden)
    }

    func testLargestDynamicTypeRetainsAccessibleGuidanceAndCropControls() async throws {
        let camera = FakeCamera(bytes: jpeg())
        let screen = CameraReviewViewController(sideDescription: "front", makeCamera: { camera })
        let host = UIViewController()
        host.addChild(screen)
        host.view.addSubview(screen.view)
        screen.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        screen.didMove(toParent: host)
        host.setOverrideTraitCollection(
            UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge),
            forChild: screen
        )
        let window = UIWindow(frame: screen.view.frame)
        window.rootViewController = host
        window.isHidden = false
        host.view.layoutIfNeeded()
        try await until { self.button("Take photo", screen).isEnabled }
        XCTAssertEqual(screen.traitCollection.preferredContentSizeCategory, .accessibilityExtraExtraExtraLarge)
        await camera.guide(CameraGuidance(bounds: CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.5),
                                           phase: .ready))
        try await until {
            self.descendants(screen.view).compactMap { $0 as? UIImageView }.first?
                .accessibilityValue?.contains("Ready for manual capture") == true
        }
        button("Take photo", screen).sendActions(for: .touchUpInside)
        try await until { !self.button("Preview crop", screen).isHidden }
        let sliders = descendants(screen.view).compactMap { $0 as? UISlider }
        XCTAssertEqual(sliders.count, 4)
        XCTAssertTrue(sliders.allSatisfy { !($0.accessibilityLabel ?? "").isEmpty })
        XCTAssertTrue(sliders.allSatisfy { ($0.accessibilityValue ?? "").contains("percent inset") })
        let scroll = try XCTUnwrap(descendants(screen.view).compactMap { $0 as? UIScrollView }.first)
        screen.view.layoutIfNeeded()
        XCTAssertGreaterThan(scroll.contentSize.height, 0)
        screen.cancelCapture()
        window.isHidden = true
    }

    /// Host, cover and background wired the way ChildCapturePresenter expects.
    private func captureHost() -> (UIViewController, UIView, UIView) {
        let host = UIViewController()
        host.loadViewIfNeeded()
        let cover = UIView(), background = UIView()
        host.view.addSubview(background)
        host.view.addSubview(cover)
        return (host, cover, background)
    }

    func testCoordinatorSequencesSidesAndRejectsCallbacksAfterCancel() async throws {
        let (host, cover, background) = captureHost()
        let camera = FakeCamera(bytes: jpeg())
        var cancellationRequests = 0
        let capture = DocumentCaptureCoordinator(
            presenter: ChildCapturePresenter(host: host, below: cover, hiding: background),
            makeCamera: { camera },
            onUserCancel: { cancellationRequests += 1 })

        let front = Task { try await capture.confirmedJPEG(for: .front) }
        try await until { self.cameraController(in: host) != nil }
        let frontScreen = try XCTUnwrap(cameraController(in: host))
        XCTAssertTrue(background.isHidden)
        XCTAssertTrue(host.children.first === frontScreen)
        XCTAssertTrue(host.view.subviews.last === cover, "Capture screen must stay below the privacy cover")

        let bytes = jpeg()
        frontScreen.onConfirm?(bytes)
        let result = try await front.value
        XCTAssertEqual(result, bytes)
        XCTAssertTrue(host.children.isEmpty)
        XCTAssertFalse(background.isHidden)

        let back = Task { try await capture.confirmedJPEG(for: .back) }
        try await until { self.cameraController(in: host) != nil }
        let backScreen = try XCTUnwrap(cameraController(in: host))
        XCTAssertFalse(backScreen === frontScreen, "Each side gets its own screen")
        let lateConfirm = backScreen.onConfirm

        // The screen's own cancel asks the client to cancel; it must not resolve the capture here.
        backScreen.onCancel?()
        XCTAssertEqual(cancellationRequests, 1)
        XCTAssertFalse(back.isCancelled)

        capture.hidePreview()
        XCTAssertTrue(host.children.isEmpty, "hidePreview must remove the screen synchronously")
        lateConfirm?(bytes)
        capture.cancel()
        capture.cancel()
        do { _ = try await back.value; XCTFail("Cancelled capture returned bytes") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(host.children.isEmpty)
        XCTAssertFalse(background.isHidden)

        do { _ = try await capture.confirmedJPEG(for: .front); XCTFail("Cancelled coordinator restarted") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testCoordinatorRejectsSecondSideWhileOneIsPending() async throws {
        let (host, cover, background) = captureHost()
        let camera = FakeCamera(bytes: jpeg())
        let capture = DocumentCaptureCoordinator(
            presenter: ChildCapturePresenter(host: host, below: cover, hiding: background),
            makeCamera: { camera }, onUserCancel: {})
        let front = Task { try await capture.confirmedJPEG(for: .front) }
        try await until { self.cameraController(in: host) != nil }

        do { _ = try await capture.confirmedJPEG(for: .back); XCTFail("Concurrent sides were allowed") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(host.children.count, 1, "The pending side keeps its screen")

        capture.cancel()
        _ = try? await front.value
    }

    func testCoordinatorTearsDownScreenWhenAwaitingTaskIsCancelled() async throws {
        let (host, cover, background) = captureHost()
        let camera = FakeCamera(bytes: jpeg())
        let capture = DocumentCaptureCoordinator(
            presenter: ChildCapturePresenter(host: host, below: cover, hiding: background),
            makeCamera: { camera }, onUserCancel: { XCTFail("Task cancellation is not a user cancel") })
        let front = Task { try await capture.confirmedJPEG(for: .front) }
        try await until { self.cameraController(in: host) != nil }

        front.cancel()
        do { _ = try await front.value; XCTFail("Cancelled task returned bytes") }
        catch { XCTAssertTrue(error is CancellationError) }
        try await until { host.children.isEmpty }
        XCTAssertFalse(background.isHidden)
        let stops = await camera.stops
        XCTAssertGreaterThan(stops, 0, "Camera shutdown must be requested on teardown")
    }

    func testCoordinatorFailsWhenPresenterCannotPresent() async throws {
        let host = UIViewController()
        host.loadViewIfNeeded()
        // Cover is never added to the host view, so presentation cannot place the screen below it.
        let cover = UIView()
        let camera = FakeCamera(bytes: jpeg())
        let capture = DocumentCaptureCoordinator(
            presenter: ChildCapturePresenter(host: host, below: cover),
            makeCamera: { camera }, onUserCancel: {})

        do { _ = try await capture.confirmedJPEG(for: .front); XCTFail("Capture continued without a screen") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(host.children.isEmpty)
    }

}
