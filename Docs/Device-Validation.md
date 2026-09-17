# Physical-iPhone validation gate

Status: two automated storage checks passed on the physical iPhone 14; manual lock/unlock, process termination and full-flow device checks remain pending. A standalone camera-test build was signed and installed on the user-selected iPhone 14 (iOS 17.3) on 13 September 2026. Initial launch was denied by iOS pending developer trust. After the user trusted the developer, devicectl successfully launched the installed app at 10:10 Asia/Jakarta. The user subsequently confirmed that live capture reached the expected confirmation/discard message. This is user-reported success, not an automated preview assessment. On 13 September 2026, an iPhone 15 Pro was available via devicectl, but the user deferred physical testing. At that earlier step no app was installed and no signing team was configured. Earlier checks on 9–10 September found paired iPhones unavailable. Simulator success is not evidence of physical locked-device data protection.

Use synthetic data only. Open the iOS sample project, choose a connected iPhone and your signing team, and run UIKitSample. Record device model, OS version, Xcode/build configuration, time, expected result and observed result for each check.

1. Complete approval, rejection, pending and failure. Confirm the host receives its result only after cleanup; inspect the owned directory and Keychain via a development test/debugger to confirm no session artifacts remain.
2. Start a run and lock during front transfer, back transfer and decision wait. Confirm the screen is concealed on inactivity. Unlock and reopen: expect cancellation, or an explicit cleanup-required state if deletion failed. Never accept a silent approval from a late response after cancellation won.
3. If cleanup is required, keep the same client. Unlock, tap Retry cleanup and verify the original terminal result is recovered without another upload/submission. Confirm both key and ciphertext are removed and Start becomes available.
4. Exercise Home/app switcher and quick foreground/background sequences. Verify the cover, cancellation and a fresh run after foreground entry. A stale activation must not reopen access during inactivity.
5. With a development test retaining an evidence reader, assert reads fail while inactive/locked and after cleanup. Check actual file-protection and backup-exclusion attributes and Keychain accessibility in a signed host; do not infer these properties from UI text.
6. Terminate the process during storage, relaunch and verify the first activation sweeps only SDK-owned keys/files. Preserve unrelated host test files and Keychain items as controls.
7. Repeat cancellation/cleanup and lock/unlock cycles and inspect resource retention. Record failures rather than weakening protection to make the sample run.

The sample cancels on inactivity; it is not a demonstration of transfer resumption or backend reconciliation. The synthetic verification flow requests no camera and no identity decisions are real. The separate Test live camera action is memory-only and does not exercise the vault.

## Recorded automated checks — 13 September 2026, 10:14 Asia/Jakarta

Signed Debug UIKitSample host, Xcode 26.3, iPhone 14, iOS 17.3 (21D50). `CameraComponentTests/StorageDeviceTests`: 2 passed, 0 failed, 0 skipped.

- Real Keychain-backed vault: synthetic JPEG round-trip, ciphertext size and inequality, complete file protection on directory and ciphertext, backup exclusion on root, WhenUnlockedThisDeviceOnly Keychain accessibility, replacement reader revocation, simulated inactive reader denial, foreground recovery, idempotent cleanup, absent key/file and revoked reader after cleanup all matched expectations.
- Fresh vault reconstruction swept owned ciphertext and key while preserving control file and a separate Keychain service. This models startup sweeping; it is not a process-kill test.

Evidence: `/tmp/identityflow-device/Logs/Test/Test-UIKitSample-2026.09.13_10-13-43-+0700.xcresult`. These checks use unique test namespaces and do not read user photos or unrelated Keychain records. Actual locked-device access denial remains untested. The user was asked to lock during simulation processing and report the result after reopening.

## User-reported manual checks — 13 September 2026

The user reported “Simulation cancelled. Synthetic evidence was cleared” after locking during the synthetic flow and reopening. They then completed a fresh run without locking and reported “Simulated approval. No identity was verified.” This establishes the observed cancellation/restart UI behavior. Exact transfer phase at lock was not instrumented, and these messages alone do not independently establish locked-state Keychain/file denial or artifact deletion for that specific run.

## Integrated live capture (September 13, afternoon)

The optional front/back camera path is now installed on DEV TESTING 7. Launch was blocked because the phone was locked. Integrated capture/retake, cancellation, lock during either side, and fresh-run results have not yet been reported. Earlier standalone-camera and synthetic-flow observations do not establish these integrated results.

### User follow-up and crop milestone — 2026-09-13

The user reported “completed” after the integrated front/back capture and interruption checklist. No additional instrumented lock-state result was collected. Manual crop editing and cropped-image confirmation were subsequently added; physical validation of those new screens remains pending.

At 22:00 WIB, a current signed crop-enabled UIKitSample build was installed successfully on DEV TESTING 7. The subsequent remote launch was denied because the phone was locked. Unlock and open the installed app before performing the crop checklist; the failed launch does not validate camera, crop or locked-storage behavior.

### Physical crop follow-up — 2026-09-16

The current UIKitSample launched successfully on DEV TESTING 7. After completing the printed-card checklist, the user reported that front/back crop editing, crop preview, retake, locking during crop editing and the fresh-run result behaved as expected. This is user-observed UI validation; it is not an automated readability assessment or an instrumented locked-storage result.

The user also reported a lagging live preview. Source inspection found an explicit 0.2-second preview throttle, limiting displayed frames to 5 FPS, followed by per-frame Core Image to `CGImage` conversion and a MainActor `UIImage` update. A 15-second Time Profiler trace on the iPhone 14 reported no app hang over 250 ms. The visible lag is therefore consistent with the deliberately low preview cadence and frame-copy display path, rather than a detected main-thread hang. Trace: `/tmp/identityflow-preview-lag-2.trace`. No implementation change was made during this investigation.

### Native-preview follow-up — 2026-09-17

The real camera preview was changed to `AVCaptureVideoPreviewLayer`. The capture session remains actor-configured, while preview-layer creation and display are MainActor-isolated. The old `AVCaptureVideoDataOutput` frame-copy path was removed from `StillCamera`; it is not needed until bounded analysis is implemented. Camera component coverage now verifies that a native preview layer is attached after startup and synchronously removed on cancellation.

All 9 focused camera/adapter component tests passed on iPhone 16 Pro Simulator, iOS 18.3.1, and the signed generic-device UIKitSample build succeeded. DEV TESTING 7 was unavailable when checked, so this build was not installed and no claim is made yet about physical smoothness, preview orientation, still/guide alignment, retake or interruption behavior. App artifact: `/tmp/identityflow-native-preview-device/Build/Products/Debug-iphoneos/UIKitSample.app`.
