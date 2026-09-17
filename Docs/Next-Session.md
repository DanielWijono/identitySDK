# Camera integration handoff

Live front/back test-card capture is implemented in the shared sample host. Choose Live camera, accept the disclosure, and Start simulation. Permission is requested before the vault session. Each confirmed side goes through temporary encrypted storage and the local simulated provider; no network upload or identity verification occurs. Generated cards remain available.

The UIKit app with crop controls was launched on DEV TESTING 7 (iPhone 14), and the user reported that front/back crop editing, crop preview, retake, locking during crop editing and a fresh run behaved as expected. This is user-observed UI validation, not an instrumented security-gate result. The remaining physical security and accessibility gates still require separate evidence; use printed test cards only.

The reported preview lag was addressed with `AVCaptureVideoPreviewLayer`; after installation on DEV TESTING 7, the user reported “very good no lagging.” The next M3 step is now implemented and installed: a separate preview-sized Vision path analyzes at most four frames per second and reports rectangle presence, coverage, margins and three-frame stability without blocking the manual shutter. The full package suite passes 38 tests and all 10 camera/adapter component tests pass.

Next: physically evaluate the rectangle guide on printed cards. Confirm the outline follows the card, status moves through positioning/hold-steady to ready, green does not appear for a small or edge-clipped card, manual shutter remains available when detection is imperfect, and preview smoothness remains unchanged. Threshold tuning must be based on those observations; no automatic shutter or automatic final crop is intended.

Local changes include prior physical storage tests and user Xcode development-team edits. Preserve those edits. See Validation.md for automated results.
