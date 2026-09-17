# Camera integration handoff

Live front/back test-card capture is implemented in the shared sample host. Choose Live camera, accept the disclosure, and Start simulation. Permission is requested before the vault session. Each confirmed side goes through temporary encrypted storage and the local simulated provider; no network upload or identity verification occurs. Generated cards remain available.

The UIKit app with crop controls was launched on DEV TESTING 7 (iPhone 14), and the user reported that front/back crop editing, crop preview, retake, locking during crop editing and a fresh run behaved as expected. This is user-observed UI validation, not an instrumented security-gate result. The remaining physical security and accessibility gates still require separate evidence; use printed test cards only.

The reported preview lag has been addressed in source: the real camera now uses `AVCaptureVideoPreviewLayer` directly and no longer installs the 5-FPS Core Image/`CGImage`/`UIImage` copy path. Synthetic cameras can still emit pixel-preview events for deterministic UI tests. Nine camera/adapter component tests pass, including native-layer attachment/removal, and a signed device build succeeds. DEV TESTING 7 was unavailable on 17 September, so installation and the physical smoothness/orientation/retake/interruption comparison remain the immediate next step.

Local changes include prior physical storage tests and user Xcode development-team edits. Preserve those edits. See Validation.md for automated results.
