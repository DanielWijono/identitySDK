#if os(iOS)
import AVFoundation
import CoreImage
import Foundation
import os

public enum CameraError: Error, Sendable {
    case permissionRequired, unavailable, configurationFailed, interrupted, captureFailed, stopped, busy
}

public enum CameraEvent: Sendable {
    case preview(CGImage)
    case interrupted
    case failed
}

/// Inject a synthetic implementation when testing the UI without camera hardware.
public protocol CameraDevice: Sendable {
    func start(events: @escaping @Sendable (CameraEvent) -> Void) async throws
    func capture() async throws -> Data
    func stop() async
}

public enum CameraAuthorization: Sendable {
    case authorized, notDetermined, denied, restricted, unavailable

    public static var current: CameraAuthorization {
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else { return .unavailable }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .restricted
        }
    }

    /// Call from an explicit host action before opening a verification session.
    /// The system permission prompt may temporarily make the host inactive.
    public static func request() async -> CameraAuthorization {
        if current == .notDetermined { _ = await AVCaptureDevice.requestAccess(for: .video) }
        return current
    }
}

/// Owns all mutable AVFoundation objects. Session work runs on this actor, never MainActor.
/// Preview delivers downscaled pixels rather than sharing a mutable session with the UI.
public actor StillCamera: CameraDevice {
    private let session = AVCaptureSession()
    private let photos = AVCapturePhotoOutput()
    private let video = AVCaptureVideoDataOutput()
    private let previewQueue = DispatchQueue(label: "com.identityflow.camera.preview")
    private var frames: PreviewFrames?
    private var photoDelegate: PhotoResult?
    private var pending: CheckedContinuation<Data, any Error>?
    private var captureID: UUID?
    private var timeout: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var eventSink: (@Sendable (CameraEvent) -> Void)?
    private var configured = false
    private var closed = false

    public init() {}

    public func start(events: @escaping @Sendable (CameraEvent) -> Void) throws {
        guard !closed else { throw CameraError.stopped }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw CameraError.permissionRequired
        }
        if !configured {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                throw CameraError.unavailable
            }
            let input: AVCaptureDeviceInput
            do { input = try AVCaptureDeviceInput(device: device) }
            catch { throw CameraError.configurationFailed }
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            session.sessionPreset = .photo
            guard session.canAddInput(input) else { throw CameraError.configurationFailed }
            session.addInput(input)
            guard session.canAddOutput(photos), session.canAddOutput(video) else {
                session.removeInput(input)
                throw CameraError.configurationFailed
            }
            session.addOutput(photos)
            session.addOutput(video)
            video.alwaysDiscardsLateVideoFrames = true
            video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            // Portrait-only host. The preview is guidance, not a crop of the stored still.
            for connection in [video.connection(with: .video), photos.connection(with: .video)] {
                if connection?.isVideoOrientationSupported == true { connection?.videoOrientation = .portrait }
            }
            configured = true
        }
        eventSink = events
        if observers.isEmpty {
            for event in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
                let interrupted = event == AVCaptureSession.wasInterruptedNotification
                observers.append(NotificationCenter.default.addObserver(forName: event, object: session, queue: nil) { [weak self] _ in
                    Task { await self?.sessionFailed(interrupted: interrupted) }
                })
            }
        }
        frames = PreviewFrames { events(.preview($0)) }
        video.setSampleBufferDelegate(frames, queue: previewQueue)
        if !session.isRunning { session.startRunning() }
        guard session.isRunning, !session.isInterrupted else { throw CameraError.interrupted }
    }

    public func capture() async throws -> Data {
        guard !closed, session.isRunning else { throw CameraError.stopped }
        guard !session.isInterrupted else { throw CameraError.interrupted }
        guard pending == nil else { throw CameraError.busy }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                captureID = id
                pending = continuation
                let delegate = PhotoResult { [weak self] result in
                    Task { await self?.finish(id, result: result) }
                }
                photoDelegate = delegate
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                photos.capturePhoto(with: settings, delegate: delegate)
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                    await self?.finish(id, result: .failure(.captureFailed))
                }
            }
        } onCancel: {
            Task { await self.finish(id, result: .failure(.stopped)) }
        }
    }

    private func finish(_ id: UUID, result: Result<Data, CameraError>) {
        guard captureID == id, let pending else { return }
        self.pending = nil
        timeout?.cancel()
        timeout = nil
        captureID = nil
        photoDelegate = nil
        pending.resume(with: result.mapError { $0 as any Error })
    }

    private func sessionFailed(interrupted: Bool) {
        let sink = eventSink
        stop()
        sink?(interrupted ? .interrupted : .failed)
    }

    public func stop() {
        closed = true
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        eventSink = nil
        if let captureID { finish(captureID, result: .failure(.stopped)) }
        video.setSampleBufferDelegate(nil, queue: nil)
        frames?.invalidate()
        frames = nil
        if session.isRunning { session.stopRunning() }
    }
}

private final class PhotoResult: NSObject, AVCapturePhotoCaptureDelegate, Sendable {
    let deliver: @Sendable (Result<Data, CameraError>) -> Void
    init(deliver: @escaping @Sendable (Result<Data, CameraError>) -> Void) { self.deliver = deliver }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            deliver(.failure(.captureFailed)); return
        }
        deliver(.success(data))
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: (any Error)?) {
        if error != nil { deliver(.failure(.captureFailed)) }
    }
}

/// Delegate callbacks are serial on previewQueue. Only immutable state crosses to the UI.
private final class PreviewFrames: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, Sendable {
    let deliver: @Sendable (CGImage) -> Void
    struct State { var last = -Double.infinity; var active = true }
    let state = OSAllocatedUnfairLock(initialState: State())
    func invalidate() { state.withLock { $0.active = false } }
    let context = CIContext(options: [.cacheIntermediates: false])
    init(deliver: @escaping @Sendable (CGImage) -> Void) { self.deliver = deliver }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        let shouldDeliver = state.withLock { state in
            guard state.active, now - state.last >= 0.2 else { return false }
            state.last = now
            return true
        }
        guard shouldDeliver, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        autoreleasepool {
            let source = CIImage(cvPixelBuffer: buffer)
            let scale = min(1, 640 / max(source.extent.width, source.extent.height))
            let reduced = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            if let image = context.createCGImage(reduced, from: reduced.extent) {
                state.withLock { if $0.active { deliver(image) } }
            }
        }
    }
}
#endif
