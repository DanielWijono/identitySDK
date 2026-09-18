#if os(iOS)
import Foundation
import IdentityFlowCapture
import IdentityFlowCore

/// Drives one confirmed capture per document side for a single accepted run.
///
/// Bridges the callback-based review screen into the `async` evidence boundary that
/// `VerificationClient` consumes. Pass an instance straight to `VaultEvidenceSource` as its
/// capture; only confirmed, normalized JPEG bytes leave this type.
///
/// The host still owns camera-permission preflight (`CameraAuthorization.current` / `request()`),
/// consent, and the privacy cover. This coordinator never requests permission implicitly.
///
/// One instance per run. After cancellation it refuses further capture rather than presenting
/// a screen for a flow that has already terminated.
@MainActor
public final class DocumentCaptureCoordinator: ConfirmedImageCapture {
    private let presenter: any DocumentCapturePresenter
    private let sideDescription: @Sendable (DocumentSide) -> String
    private let makeCamera: @Sendable () -> any CameraDevice
    private let onUserCancel: () -> Void
    private var screen: CameraReviewViewController?
    private var pending: CheckedContinuation<Data, any Error>?
    private var cancelled = false
    /// Rotated on every teardown so a callback from a removed screen cannot resolve a later side.
    private var generation = UUID()

    /// - Parameters:
    ///   - presenter: shows and removes each side's screen. Retained for the run.
    ///   - sideDescription: spoken and displayed description of the side being captured.
    ///   - makeCamera: capture device factory, injectable for tests.
    ///   - onUserCancel: invoked when the user cancels from the capture screen. Cancel the
    ///     `VerificationClient` here; its cleanup resolves the outstanding capture.
    public init(presenter: any DocumentCapturePresenter,
                sideDescription: @escaping @Sendable (DocumentSide) -> String = DocumentCaptureCoordinator.defaultDescription,
                makeCamera: @escaping @Sendable () -> any CameraDevice = { StillCamera() },
                onUserCancel: @escaping () -> Void) {
        self.presenter = presenter
        self.sideDescription = sideDescription
        self.makeCamera = makeCamera
        self.onUserCancel = onUserCancel
    }

    public static let defaultDescription: @Sendable (DocumentSide) -> String = { side in
        switch side {
        case .front: "the front of your document"
        case .back: "the back of your document"
        }
    }

    public func confirmedJPEG(for side: DocumentSide) async throws -> Data {
        try Task.checkCancellation()
        guard !cancelled, pending == nil else { throw CancellationError() }
        let bytes: Data = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                let id = UUID()
                generation = id
                let controller = CameraReviewViewController(sideDescription: sideDescription(side),
                                                            makeCamera: makeCamera)
                screen = controller
                controller.onConfirm = { [weak self] bytes in
                    guard let self, !self.cancelled, self.generation == id,
                          let pending = self.pending else { return }
                    self.pending = nil
                    self.removeScreen()
                    pending.resume(returning: bytes)
                }
                controller.onCancel = { [weak self] in
                    guard let self, !self.cancelled, self.generation == id else { return }
                    // Cancel the client first. Its cleanup resolves this outstanding capture;
                    // resuming here would race the client's terminal reservation.
                    self.onUserCancel()
                }
                guard presenter.present(controller) else {
                    // No screen will appear, so nothing can resolve this continuation later.
                    pending = nil
                    removeScreen()
                    continuation.resume(throwing: CancellationError())
                    return
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        return bytes
    }

    /// Stop capture and fail any awaited side. Idempotent.
    public func cancel() {
        hidePreview()
        let continuation = pending
        pending = nil
        continuation?.resume(throwing: CancellationError())
    }

    /// Synchronously invalidate callbacks and remove the screen for inactivity or protected-data
    /// loss. Deliberately not `async`: the preview must be gone before the app yields, even though
    /// camera shutdown itself completes asynchronously.
    public func hidePreview() {
        cancelled = true
        removeScreen()
    }

    private func removeScreen() {
        generation = UUID()
        guard let screen else { return }
        self.screen = nil
        // Invalidate callbacks before removal, which itself triggers disappearance.
        screen.onConfirm = nil
        screen.onCancel = nil
        screen.cancelCapture()
        presenter.dismiss(screen)
    }
}
#endif
