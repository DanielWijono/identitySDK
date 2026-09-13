# Camera preparation (not enabled in the sample)

The optional iOS-only `StillCamera` in IdentityFlowCapture and `CameraReviewViewController` in IdentityFlowUI prepare the next physical-capture milestone. Both sample schemes build these products, but the sample workflow continues to use generated cards. No live-camera entry point is enabled. The original plan's core/vault gates and the physical storage checks remain prerequisites for connecting it to VaultEvidenceSource.

## Ownership and behavior

- StillCamera owns its AVCaptureSession, inputs and outputs in one actor. Configuration and start/stop are serialized off MainActor; there are no application-authored unchecked Sendable annotations. It uses only the rear wide-angle camera and a JPEG still output. No microphone, Photos library, network or file output is used.
- Portrait preview pixels are generated on a serial delegate queue, downscaled to at most 640 pixels on the longest edge and throttled to at most five frames per second. The UI receives an AsyncStream with one buffered event. Preview pixels are guidance only; they do not define a crop. Actual performance, thermal behavior and image readability are unmeasured.
- One still request may be pending per camera. A 15-second timeout bounds missing completion; cancellation, stop and late callbacks use a request UUID to avoid delivering twice. Stop is terminal for that instance; retry creates a new instance.
- Interruptions/runtime failures stop capture and offer retry. The screen normalizes the still before review. Retake drops the unconfirmed JPEG and restarts the camera. Confirm transfers only the normalized JPEG to the host callback, once; the host then owns those bytes.
- Inactivity, protected-data loss, cancellation and disappearance clear the preview synchronously and request camera shutdown. Asynchronous camera shutdown is not claimed to be instantaneous. This screen is a single-side capture component; it does not yet implement the SDK's full consent/front/back orchestration facade.

## Permission and integration prerequisites

The host must provide NSCameraUsageDescription (already present in the example project). It should inspect CameraAuthorization.current and call request() only after an explicit camera action and before starting a vault-backed verification session. This keeps system permission-prompt inactivity outside the active session. Unavailable camera hardware, including the simulator, returns unavailable without prompting. Denied/restricted access requires an actionable host recovery path; the standalone screen explains how to return through Settings and never requests access implicitly.

The host will need to embed/present the review screen, route cancellation to VerificationClient, pass the confirmed JPEG through ConfirmedImageCapture, and retain the existing lifecycle cover and cleanup handling. Do not connect this path or use real identity documents before recording the device gate. For initial hardware testing use a printed synthetic card.

Still pending: physical permission/denial/revocation tests, still/preview orientation comparison, interrupted-session and start/stop stress tests, file/key lock-state validation, SDK flow integration, crop confirmation, rectangle guidance, minimum-iOS hardware, VoiceOver, maximum Dynamic Type and performance measurements. Simulator fake-camera tests do not establish any of these hardware properties.

References: [Apple capture-session setup](https://developer.apple.com/documentation/avfoundation/setting-up-a-capture-session) and [requesting camera authorization](https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media).
