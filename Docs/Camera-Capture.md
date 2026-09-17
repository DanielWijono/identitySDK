# Camera capture and standalone hardware test

The sample now offers **Generated cards** or **Live camera** input. Live camera requests permission before starting a session, captures and reviews front/back printed test cards, and passes confirmed normalized JPEGs through VaultEvidenceSource to the local simulated provider. Confirmed images are temporarily encrypted, then cleaned up on completion/cancellation. No network upload or identity verification occurs. The separate **Test live camera** button remains a memory-only, single-image hardware check.

This is a development test-card path. Two physical storage tests and user-reported lock/restart checks are recorded in Device-Validation.md; the complete physical security gate is still pending. Real identity documents remain out of scope.

## Ownership and behavior

- StillCamera owns its AVCaptureSession, input and JPEG still output in one actor. Configuration and start/stop are serialized off MainActor. Because AVFoundation does not declare `AVCaptureSession` Sendable, one narrowly scoped `nonisolated(unsafe)` reference permits only MainActor preview-layer construction; the protocol never exposes the session itself. It uses only the rear wide-angle camera. No microphone, Photos library, network or file output is used.
- The real UIKit preview is an `AVCaptureVideoPreviewLayer` using aspect-fit portrait display. It avoids the previous five-FPS Core Image/`CGImage`/`UIImage` copy path. Synthetic camera implementations may still send immutable `CameraEvent.preview` pixels through the one-element AsyncStream for deterministic tests. The preview and yellow guide are positioning aids only; they do not define the stored-image crop. Physical smoothness, thermal behavior and guide/still alignment for this new path remain unmeasured.
- One still request may be pending per camera. A 15-second timeout bounds missing completion; cancellation, stop and late callbacks use a request UUID to avoid delivering twice. Stop is terminal for that instance; retry creates a new instance.
- Interruptions/runtime failures stop capture and offer retry. The screen normalizes the still before review. Retake drops the unconfirmed JPEG and restarts the camera. Confirm transfers only the normalized JPEG to the host callback, once; the host then owns those bytes.
- Inactivity, protected-data loss, cancellation and disappearance clear the preview synchronously and request camera shutdown. Asynchronous camera shutdown is not claimed to be instantaneous. This screen is a single-side capture component; it does not yet implement the SDK's full consent/front/back orchestration facade.

## Permission and integration prerequisites

The host must provide NSCameraUsageDescription (already present in the example project). It should inspect CameraAuthorization.current and call request() only after an explicit camera action and before starting a vault-backed verification session. This keeps system permission-prompt inactivity outside the active session. Unavailable camera hardware, including the simulator, returns unavailable without prompting. Denied/restricted access requires an actionable host recovery path; the standalone screen explains how to return through Settings and never requests access implicitly.

The sample embeds each review screen below its privacy cover. Cancellation reaches VerificationClient before cleanup resolves pending capture; callbacks from removed screens are invalidated. Both sides share a three-minute session deadline. Generated cards remain the simulator default. Use printed test cards while the remaining device gate is completed.

Still pending: physical validation of the new native preview, permission/denial/revocation tests, still/preview orientation comparison, interrupted-session and start/stop stress tests, file/key lock-state validation, full SDK facade, automatic rectangle detection, minimum-iOS hardware, VoiceOver, maximum Dynamic Type and performance measurements. Simulator fake-camera tests do not establish any of these hardware properties.

References: [Apple capture-session setup](https://developer.apple.com/documentation/avfoundation/setting-up-a-capture-session) and [requesting camera authorization](https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media).

## Manual framing and crop review

The live preview shows a centered card-shaped guide. This is positioning guidance, not detected boundaries. After capture, four accessible sliders adjust left/top/right/bottom insets independently (0–45% each). Selection starts at the full image to avoid silently clipping card corners. The yellow outline follows the aspect-fit upright image, excluding letterboxing.

Preview crop produces a bounded, metadata-stripped JPEG on ImageNormalizer's actor. Only the separate Use this image action releases that cropped JPEG to the caller. Retake starts over; cancellation clears both editing and final review states. Cropping uses upright top-left unit coordinates with outward pixel rounding after the existing 2,000-pixel normalization; it does not upscale or correct perspective. The current sample re-encodes the normalized JPEG for crop output. Readability and quality still need physical inspection.
