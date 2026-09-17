#if os(iOS)
import AVFoundation
import UIKit
import IdentityFlowCapture

/// Portrait-first camera/review component, also embedded by the sample flow.
/// Request permission before presenting. The caller owns accepted JPEG bytes and their cleanup.
@MainActor
public final class CameraReviewViewController: UIViewController {
    public var onConfirm: ((Data) -> Void)?
    public var onCancel: (() -> Void)?
    private let makeCamera: @Sendable () -> any CameraDevice
    private let image = CropPreview()
    private let cropButton = UIButton(type: .system)
    private let cropControls = UIStackView()
    private var edges: [UISlider] = []
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
        configure(cropButton, "Preview crop", #selector(applyCrop))
        cropControls.axis = .vertical
        for name in ["Left", "Top", "Right", "Bottom"] {
            let label = UILabel()
            label.text = "\(name) crop edge"
            label.font = .preferredFont(forTextStyle: .caption1)
            let slider = UISlider()
            slider.minimumValue = 0
            slider.maximumValue = 0.45
            slider.accessibilityLabel = "\(name) crop edge"
            slider.addTarget(self, action: #selector(updateCrop), for: .valueChanged)
            edges.append(slider)
            cropControls.addArrangedSubview(label)
            cropControls.addArrangedSubview(slider)
        }
        configure(confirm, "Use this image", #selector(useImage))
        configure(retry, "Retake", #selector(restart))
        configure(cancelButton, "Cancel capture", #selector(cancelCapture))
        let stack = UIStackView(arrangedSubviews: [instructions, image, shutter, cropControls, cropButton, confirm, retry, cancelButton])
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
        image.clearNativePreview()
        cropControls.isHidden = true
        cropButton.isHidden = true
        image.selection = nil
        image.image = nil
        confirm.isHidden = true
        retry.isHidden = true
        shutter.isHidden = false
        shutter.isEnabled = false
        instructions.text = "Starting camera…"
        let id = generation
        let camera = makeCamera()
        self.camera = camera
        let previewLayer = camera.makePreviewLayer()
        let (stream, continuation) = AsyncStream<CameraEvent>.makeStream(bufferingPolicy: .bufferingNewest(1))
        sink = continuation
        eventsTask = Task { [weak self] in
            for await event in stream {
                guard !Task.isCancelled, let self, self.generation == id, !self.finished else { return }
                switch event {
                case .preview(let pixels):
                    guard !self.image.isShowingNativePreview else { continue }
                    self.image.image = UIImage(cgImage: pixels)
                    if self.image.selection == nil {
                        let width = 0.85
                        let height = min(0.85, width * Double(pixels.width) / Double(pixels.height) / 1.586)
                        self.image.selection = CGRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
                    }
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
                if let previewLayer {
                    self.image.showNativePreview(previewLayer)
                    let width = 0.85
                    let height = width * 0.75 / 1.586
                    self.image.selection = CGRect(x: (1 - width) / 2, y: (1 - height) / 2,
                                                  width: width, height: height)
                }
                self.shutter.isEnabled = true
                self.instructions.text = "Photograph \(self.sideDescription). Center the test card inside the frame. Keep all corners visible and avoid glare. No identity verification is performed."
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
                self.image.clearNativePreview()
                self.image.image = UIImage(data: normalized.jpeg)
                self.image.accessibilityLabel = "Review photo of \(self.sideDescription)"
                self.instructions.text = "Adjust the four crop edges around \(self.sideDescription), then preview the crop. Keep every corner and all text inside."
                self.edges.forEach { $0.value = 0 }
                self.cropControls.isHidden = false
                self.cropButton.isHidden = false
                self.updateCrop()
                self.shutter.isHidden = true
                self.confirm.isHidden = true
                self.retry.setTitle("Retake", for: .normal)
                self.retry.isHidden = false
                UIAccessibility.post(notification: .screenChanged, argument: self.instructions)
            } catch {
                guard let self, self.generation == id, !self.finished else { return }
                self.showFailure("The image could not be prepared. Retake the photo.")
            }
        }
    }

    @objc private func updateCrop() {
        guard edges.count == 4 else { return }
        let values = edges.map { CGFloat($0.value) }
        image.selection = CGRect(x: values[0], y: values[1],
                                 width: 1 - values[0] - values[2], height: 1 - values[1] - values[3])
        for edge in edges { edge.accessibilityValue = "\(Int(edge.value * 100)) percent inset" }
    }

    @objc private func applyCrop() {
        guard !finished, let jpeg, let crop = image.selection, !cropButton.isHidden else { return }
        cropControls.isHidden = true
        cropButton.isHidden = true
        retry.isHidden = true
        let id = generation
        instructions.text = "Preparing crop…"
        work = Task { [weak self] in
            do {
                let result = try await ImageNormalizer.shared.normalize(jpeg, crop: crop)
                guard let self, self.generation == id, !self.finished else { return }
                self.jpeg = result.jpeg
                self.image.selection = nil
                self.image.image = UIImage(data: result.jpeg)
                self.instructions.text = "Review the cropped image. Confirm only if the entire card is clear and readable; otherwise retake."
                self.confirm.isHidden = false
                self.retry.isHidden = false
                UIAccessibility.post(notification: .screenChanged, argument: self.instructions)
            } catch {
                guard let self, self.generation == id, !self.finished else { return }
                self.showFailure("The crop could not be prepared. Retake the photo.")
            }
        }
    }

    private func showFailure(_ text: String) {
        let camera = releaseCamera()
        enqueueStop(camera)
        jpeg = nil
        image.clearNativePreview()
        cropControls.isHidden = true
        cropButton.isHidden = true
        image.selection = nil
        image.image = nil
        instructions.text = text
        shutter.isHidden = true
        confirm.isHidden = true
        retry.setTitle("Retry camera", for: .normal)
        retry.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    @objc private func useImage() {
        guard !finished, !confirm.isHidden, let jpeg else { return }
        finished = true
        self.jpeg = nil
        image.clearNativePreview()
        cropControls.isHidden = true
        cropButton.isHidden = true
        image.selection = nil
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
        image.clearNativePreview()
        cropControls.isHidden = true
        cropButton.isHidden = true
        image.selection = nil
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
/// Draws in the aspect-fit image rectangle, excluding letterboxing.
@MainActor
private final class CropPreview: UIImageView {
    var selection: CGRect? { didSet { setNeedsLayout() } }
    private var nativePreview: AVCaptureVideoPreviewLayer?
    var isShowingNativePreview: Bool { nativePreview != nil }
    private let outline = CAShapeLayer()
    override var image: UIImage? { didSet { setNeedsLayout() } }

    func showNativePreview(_ preview: AVCaptureVideoPreviewLayer) {
        clearNativePreview()
        image = nil
        preview.videoGravity = .resizeAspect
        if preview.connection?.isVideoOrientationSupported == true {
            preview.connection?.videoOrientation = .portrait
        }
        layer.insertSublayer(preview, at: 0)
        nativePreview = preview
        setNeedsLayout()
    }

    func clearNativePreview() {
        nativePreview?.session = nil
        nativePreview?.removeFromSuperlayer()
        nativePreview = nil
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        nativePreview?.frame = bounds
        if outline.superlayer == nil {
            outline.fillColor = UIColor.clear.cgColor
            outline.strokeColor = UIColor.systemYellow.cgColor
            outline.lineWidth = 3
            layer.addSublayer(outline)
        }
        guard let selection else {
            outline.path = nil
            return
        }
        if let nativePreview {
            outline.path = UIBezierPath(rect: nativePreview.layerRectConverted(fromMetadataOutputRect: selection)).cgPath
            return
        }
        guard let image, image.size.width > 0, image.size.height > 0 else {
            outline.path = nil
            return
        }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let rect = CGRect(x: (bounds.width - size.width) / 2 + selection.minX * size.width,
                          y: (bounds.height - size.height) / 2 + selection.minY * size.height,
                          width: selection.width * size.width, height: selection.height * size.height)
        outline.path = UIBezierPath(rect: rect).cgPath
    }
}
#endif
