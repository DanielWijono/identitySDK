# Camera integration handoff

Live front/back test-card capture is implemented and now driven by the SDK rather than the sample. Choose Live camera, accept the disclosure, and Start simulation. Permission is requested before the vault session. Each confirmed side goes through temporary encrypted storage and the local simulated provider; no network upload or identity verification occurs. Generated cards remain available.

## Current state

`DocumentCaptureCoordinator` (IdentityFlowUI) owns front/back orchestration: one `CameraReviewViewController` per side, generation-based invalidation of callbacks from removed screens, a single checked continuation bridging into `ConfirmedImageCapture`, synchronous `hidePreview()` for inactivity, and refusal to restart after cancellation. `ChildCapturePresenter` embeds each side below the host's privacy cover. The sample's former `LiveCardCapture` adapter was deleted; `SimulationViewController` now constructs the coordinator directly.

`ConfirmedImageCapture` moved from IdentityFlowSecurity to IdentityFlowCore so UI components conform without depending on encryption. `VaultEvidenceSource`'s signature did not change.

Package suite: 38 tests pass. UIKitSample on iPhone 16 Pro Simulator, iOS 18.3.1: 19 component tests with 3 skipped, plus all 5 `SimulationUITests`. See Validation.md for the artifact path.

Earlier physical observations remain user-reported UI validation, not instrumented security results: front/back crop editing, crop preview, retake, locking during crop editing, a fresh run, no preview lag after the native-preview change, and good rectangle guidance. Use printed test cards only.

## Remaining M3 work is physical only

No code deliverable is outstanding for M3. The remaining gates need hardware:

1. Reconnect and unlock DEV TESTING 7, then run `CameraComponentTests/testRepeatedHardwareLifecycleAndDuplicateStart`. It performs 30 real start/stop cycles, verifies duplicate start returns `CameraError.busy`, and checks the provisional p95 readiness target of 1.5 seconds. At last check every paired iPhone reported `unavailable` to `devicectl`.
2. Revoke Camera access in Settings and confirm the recovery action and return-to-app recheck on hardware.
3. Instrumented lock-state denial during crop editing, interruption stress, still/preview orientation comparison, minimum-iOS-16 hardware, hands-on VoiceOver order and announcements, and broader performance measurements.

## Next code milestone

M4: the demo HTTP service and adapter from Provider-Contract.md — upload, idempotency key, bounded retry, and GET reconciliation after a lost commit response. The gate is that an accepted-request/lost-response scenario produces exactly one logical server submission. Nothing in M4 has started.

Local changes include prior physical storage tests and user Xcode development-team edits. Preserve those edits.
