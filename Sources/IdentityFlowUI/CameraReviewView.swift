#if os(iOS) && canImport(SwiftUI)
import SwiftUI
import IdentityFlowCapture

/// SwiftUI presentation of the same camera/review implementation used by UIKit.
/// Request camera permission before presenting this view.
public struct CameraReviewView: UIViewControllerRepresentable {
    private let sideDescription: String
    private let makeCamera: @Sendable () -> any CameraDevice
    private let onConfirm: (Data) -> Void
    private let onCancel: () -> Void

    public init(sideDescription: String,
                onConfirm: @escaping (Data) -> Void,
                onCancel: @escaping () -> Void) {
        self.init(sideDescription: sideDescription, makeCamera: { StillCamera() },
                  onConfirm: onConfirm, onCancel: onCancel)
    }

    init(sideDescription: String,
         makeCamera: @escaping @Sendable () -> any CameraDevice,
         onConfirm: @escaping (Data) -> Void,
         onCancel: @escaping () -> Void) {
        self.sideDescription = sideDescription
        self.makeCamera = makeCamera
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public func makeUIViewController(context: Context) -> CameraReviewViewController {
        let controller = CameraReviewViewController(sideDescription: sideDescription, makeCamera: makeCamera)
        controller.onConfirm = onConfirm
        controller.onCancel = onCancel
        return controller
    }

    public func updateUIViewController(_ controller: CameraReviewViewController, context: Context) {
        controller.onConfirm = onConfirm
        controller.onCancel = onCancel
    }

    public static func dismantleUIViewController(_ controller: CameraReviewViewController, coordinator: ()) {
        controller.cancelCapture()
    }
}
#endif
