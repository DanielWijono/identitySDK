#if os(iOS)
import UIKit
import IdentityFlowCapture

/// Portrait-first camera/review component, also embedded by the sample flow.
/// Request permission before presenting. The caller owns accepted JPEG bytes and their cleanup.
@MainActor
public final class CameraReviewViewController: UIViewController {
    public var onConfirm: ((Data) -> Void)?
    public var onCancel: (() -> Void)?
    private let makeCamera: @Sendable () -> any CameraDevice
    private let image = UIImageView()
    private let instructions = UILabel()
    private let shutter = UIButton(type: .system)
    private let confirm = UIButton(type: .system)
    private let retry = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private var camera: (any CameraDevice)?
    private var shutdown: Task<Void, Never>?
    private var work: Task<Void, Never>?
    private var eventsTask: Task<Void, Never>?
    private var sink: AsyncStream<CameraEvent>.Continuation?
    private var generation = UUID()
    private var jpeg: Data?
    private var finished = false
    private let sideDescription: String

    public init(sideDescription: String, makeCamera: @escaping @Sendable () -> any CameraDevice = { StillCamera() }) {
        self.sideDescription = sideDescription
        self.makeCamera = makeCamera
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(sideDescription:)") }

    deinit {
        work?.cancel()
        eventsTask?.cancel()
        sink?.finish()
        let camera = camera
        Task { await camera?.stop() }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        instructions.font = .preferredFont(forTextStyle: .headline)
        instructions.adjustsFontForContentSizeCategory = true
        instructions.numberOfLines = 0
        instructions.accessibilityIdentifier = "cameraStatus"
        image.contentMode = .scaleAspectFit
        image.backgroundColor = .secondarySystemBackground
        image.isAccessibilityElement = true
        image.accessibilityLabel = "Camera preview for \(sideDescription)"
        image.heightAnchor.constraint(equalToConstant: 280).isActive = true
        configure(shutter, "Take photo", #selector(takePhoto))
        configure(confirm, "Use this image", #selector(useImage))
        configure(retry, "Retake", #selector(restart))
        configure(cancelButton, "Cancel capture", #selector(cancelCapture))
        let stack = UIStackView(arrangedSubviews: [instructions, image, shutter, confirm, retry, cancelButton])
        stack.axis = .vertical
        stack.spacing = 16
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(cancelCapture), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(cancelCapture), name: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil)
        restart()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cancelCapture()
    }

    private func configure(_ button: UIButton, _ title: String, _ selector: Selector) {
        button.configuration = .bordered()
        button.setTitle(title, for: .normal)
        button.accessibilityIdentifier = title
        button.addTarget(self, action: selector, for: .touchUpInside)
    }

    @objc private func restart() {
        guard !finished else { return }
        let previous = releaseCamera()
        let priorShutdown = shutdown
        jpeg = nil
        image.image = nil
        confirm.isHidden = true
        retry.isHidden = true
        shutter.isHidden = false
        shutter.isEnabled = false
        instructions.text = "Starting camera…"
        let id = generation
        let camera = makeCamera()
        self.camera = camera
        let (stream, continuation) = AsyncStream<CameraEvent>.makeStream(bufferingPolicy: .bufferingNewest(1))
        sink = continuation
        eventsTask = Task { [weak self] in
            for await event in stream {
                guard !Task.isCancelled, let self, self.generation == id, !self.finished else { return }
                switch event {
                case .preview(let pixels): self.image.image = UIImage(cgImage: pixels)
                case .interrupted: self.showFailure("Camera interrupted. Retry when it is available.")
                case .failed: self.showFailure("Camera unavailable. Try again.")
                }
            }
        }
        work = Task { [weak self] in
            // Stop the old session before asking a new one to acquire camera hardware.
            await priorShutdown?.value
            await previous?.stop()
            do {
                try Task.checkCancellation()
                try await camera.start { continuation.yield($0) }
                guard let self, self.generation == id, !self.finished else { await camera.stop(); return }
                self.shutter.isEnabled = true
                self.instructions.text = "Photograph \(self.sideDescription). Keep the entire test card visible. No identity verification is performed."
            } catch {
                guard let self, self.generation == id, !self.finished else { await camera.stop(); return }
                let message = (error as? CameraError) == .permissionRequired
                    ? "Camera access is required. Cancel, enable Camera access in Settings, then try again."
                    : "Camera unavailable. Use a physical iPhone and try again."
                self.showFailure(message)
            }
        }
    }

    @objc private func takePhoto() {
        guard !finished, shutter.isEnabled, let camera else { return }
        shutter.isEnabled = false
        let id = generation
        instructions.text = "Preparing image…"
        work = Task { [weak self] in
            do {
                let raw = try await camera.capture()
                try Task.checkCancellation()
                let normalized = try await ImageNormalizer.shared.normalize(raw)
                await camera.stop()
                guard let self, self.generation == id, !self.finished else { return }
                self.sink?.finish()
                self.eventsTask?.cancel()
                self.jpeg = normalized.jpeg
                self.image.image = UIImage(data: normalized.jpeg)
                self.image.accessibilityLabel = "Review photo of \(self.sideDescription)"
                self.instructions.text = "Review \(self.sideDescription). Check that it is clear and fully visible."
                self.shutter.isHidden = true
                self.confirm.isHidden = false
                self.retry.setTitle("Retake", for: .normal)
                self.retry.isHidden = false
                UIAccessibility.post(notification: .screenChanged, argument: self.instructions)
            } catch {
                guard let self, self.generation == id, !self.finished else { return }
                self.showFailure("The image could not be prepared. Retake the photo.")
            }
        }
    }

    private func showFailure(_ text: String) {
        let camera = releaseCamera()
        enqueueStop(camera)
        jpeg = nil
        image.image = nil
        instructions.text = text
        shutter.isHidden = true
        confirm.isHidden = true
        retry.setTitle("Retry camera", for: .normal)
        retry.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    @objc private func useImage() {
        guard !finished, let jpeg else { return }
        finished = true
        self.jpeg = nil
        image.image = nil
        let camera = releaseCamera()
        enqueueStop(camera)
        let completion = onConfirm
        onConfirm = nil
        onCancel = nil
        completion?(jpeg)
    }

    @objc public func cancelCapture() {
        guard !finished else { return }
        finished = true
        jpeg = nil
        image.image = nil // Conceal synchronously before awaiting camera shutdown.
        instructions.text = "Capture cancelled."
        shutter.isEnabled = false
        confirm.isHidden = true
        retry.isHidden = true
        let camera = releaseCamera()
        enqueueStop(camera)
        let completion = onCancel
        onConfirm = nil
        onCancel = nil
        completion?()
    }

    private func enqueueStop(_ camera: (any CameraDevice)?) {
        let previous = shutdown
        shutdown = Task {
            await previous?.value
            await camera?.stop()
        }
    }

    private func releaseCamera() -> (any CameraDevice)? {
        generation = UUID()
        work?.cancel()
        work = nil
        sink?.finish()
        sink = nil
        eventsTask?.cancel()
        eventsTask = nil
        let previous = camera
        camera = nil
        return previous
    }
}
#endif
