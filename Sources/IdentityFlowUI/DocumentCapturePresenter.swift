#if os(iOS)
import UIKit

/// How a host shows and removes each side's capture screen.
///
/// Implementations must keep any privacy cover above the presented controller, so inactivity
/// conceals the preview without waiting for asynchronous camera shutdown.
@MainActor
public protocol DocumentCapturePresenter: AnyObject {
    /// Show the screen for one side. Return false when the host can no longer present — for
    /// example its view was released — so the coordinator fails the capture instead of awaiting
    /// a screen that never appears.
    func present(_ controller: CameraReviewViewController) -> Bool
    /// Remove the screen. Must be safe to call for a controller that was never presented.
    func dismiss(_ controller: CameraReviewViewController)
}

/// Embeds each side as a child view controller directly below the host's privacy cover.
///
/// References are weak: a released host or cover stops presentation rather than resurrecting a
/// screen for a flow the host has already torn down.
@MainActor
public final class ChildCapturePresenter: DocumentCapturePresenter {
    private weak var host: UIViewController?
    private weak var privacyCover: UIView?
    private weak var background: UIView?

    /// - Parameters:
    ///   - host: view controller that owns the flow.
    ///   - privacyCover: the view each capture screen is inserted below.
    ///   - background: optional host content hidden while a capture screen is visible, which
    ///     prevents duplicate accessible controls behind the modal screen.
    public init(host: UIViewController, below privacyCover: UIView, hiding background: UIView? = nil) {
        self.host = host
        self.privacyCover = privacyCover
        self.background = background
    }

    public func present(_ controller: CameraReviewViewController) -> Bool {
        guard let host, let privacyCover, privacyCover.superview === host.view else { return false }
        host.addChild(controller)
        controller.view.frame = host.view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.accessibilityViewIsModal = true
        host.view.insertSubview(controller.view, belowSubview: privacyCover)
        controller.didMove(toParent: host)
        background?.isHidden = true
        return true
    }

    public func dismiss(_ controller: CameraReviewViewController) {
        background?.isHidden = false
        guard controller.parent != nil else { return }
        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
    }
}
#endif
