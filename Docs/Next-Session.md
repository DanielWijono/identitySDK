# Camera integration handoff

Live front/back test-card capture is implemented in the shared sample host. Choose Live camera, accept the disclosure, and Start simulation. Permission is requested before the vault session. Each confirmed side goes through temporary encrypted storage and the local simulated provider; no network upload or identity verification occurs. Generated cards remain available.

The UIKit app with crop controls was launched on DEV TESTING 7 (iPhone 14), and the user reported that front/back crop editing, crop preview, retake, locking during crop editing and a fresh run behaved as expected. This is user-observed UI validation, not an instrumented security-gate result. The remaining physical security and accessibility gates still require separate evidence; use printed test cards only.

The reported preview lag was addressed with `AVCaptureVideoPreviewLayer`; after installation on DEV TESTING 7, the user reported “very good no lagging.” The next M3 step is now implemented and installed: a separate preview-sized Vision path analyzes at most four frames per second and reports rectangle presence, coverage, margins and three-frame stability without blocking the manual shutter. The full package suite passes 38 tests and all 10 camera/adapter component tests pass.

The user subsequently reported that the physical rectangle-guidance test was good. This is user-observed behavior, not a measured detection-accuracy result. No automatic shutter or automatic final crop is intended.

An SDK-owned `CameraReviewView` SwiftUI wrapper is now implemented over the same UIKit controller. Its component test verifies controller creation and cancellation forwarding through `UIHostingController`; the SwiftUI sample builds successfully. This completes the M3 single-side SwiftUI presentation deliverable without duplicating camera state.

Denied/restricted permission recovery is also implemented in both sample camera entry points. The sample presents **Open Camera Settings**, rechecks authorization on active return, and does not start capture or a verification session until the user explicitly tries again. Injected authorization/settings hooks provide deterministic component coverage without mutating real device permissions. The current simulator camera suite passes 12 tests with the device-only lifecycle test skipped; SwiftUISample builds successfully.

Accessibility follow-up is implemented: preview guidance has explicit spoken values independent of yellow/green color, crop sliders announce edge names and percentage insets, labels wrap with Dynamic Type, and the capture-to-crop path passes under `.accessibilityExtraExtraExtraLarge`. The camera suite now passes 13 tests with the physical lifecycle test skipped. Hands-on VoiceOver order and announcements remain pending.

Next physical gate: reconnect and unlock DEV TESTING 7, then run `CameraComponentTests/testRepeatedHardwareLifecycleAndDuplicateStart`. The device-only test performs 30 real start/stop cycles, verifies duplicate start returns `CameraError.busy`, and checks the provisional p95 readiness target of 1.5 seconds. Afterward, revoke Camera access in Settings and confirm the new recovery action and return-to-app recheck on hardware.

Local changes include prior physical storage tests and user Xcode development-team edits. Preserve those edits. See Validation.md for automated results.
