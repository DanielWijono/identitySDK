# Physical-iPhone validation gate

Status: the full `CameraComponentTests` target — 19 tests including the 30-cycle camera lifecycle gate and both storage device tests — passed on the physical iPhone 14 with zero skips on 18 September 2026; see the entry at the end of this file for measurements. Manual lock/unlock, permission revocation, VoiceOver, interruption stress and process termination remain pending. A standalone camera-test build was signed and installed on the user-selected iPhone 14 (iOS 17.3) on 13 September 2026. Initial launch was denied by iOS pending developer trust. After the user trusted the developer, devicectl successfully launched the installed app at 10:10 Asia/Jakarta. The user subsequently confirmed that live capture reached the expected confirmation/discard message. This is user-reported success, not an automated preview assessment. On 13 September 2026, an iPhone 15 Pro was available via devicectl, but the user deferred physical testing. At that earlier step no app was installed and no signing team was configured. Earlier checks on 9–10 September found paired iPhones unavailable. Simulator success is not evidence of physical locked-device data protection.

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

DEV TESTING 7 subsequently reconnected. The native-preview build installed and launched successfully, and the user reported “very good no lagging.” This validates the observed preview-cadence improvement on that iPhone 14, not orientation, alignment, thermal behavior or a measured frame rate.

The next signed build adds capped Vision rectangle guidance and was installed and launched successfully at 11:18 WIB. It analyzes AVFoundation-managed preview-sized frames at up to 4 Hz on a serial queue while native preview rendering remains separate. The user subsequently reported that testing was good. This is user-observed confirmation of the checklist, not quantified detection accuracy, threshold calibration or guide-alignment measurement. App artifact: `/tmp/identityflow-rectangle-device/Build/Products/Debug-iphoneos/UIKitSample.app`.

A device-only test now covers 30 fresh real-camera start/stop cycles, duplicate-start rejection and the provisional 1.5-second p95 readiness target. The iPhone became unavailable before this test could run. Its Simulator run skips explicitly and the remaining camera component tests pass.

## Repeated camera lifecycle and timing — 18 September 2026

The prepared hardware gate ran. DEV TESTING 7, iPhone 14 (iPhone14,7), iOS 17.3 (21D50), Xcode 26.3, Debug, connected by **USB**. Wireless was attempted first and failed: `tunnelState` was `unavailable`, the last connection was 17 September 08:01 UTC, and `DEV-TESTING-7.coredevice.local` did not resolve from the host's 172.21.9.253 Wi-Fi address. Plugging the device in produced `tunnelState: connected` and `ddiServicesAvailable: true`.

Signing used the development team already recorded on the device-test target, passed as a `DEVELOPMENT_TEAM=5H589R53ZA` command-line override. The Xcode project was not modified.

`CameraComponentTests` target: **19 tests, 0 failures, 0 skipped** — the first run in which no test skipped. This covers 17 camera/adapter/coordinator tests plus the 2 `StorageDeviceTests` that are simulator-skipped by design.

`testRepeatedHardwareLifecycleAndDuplicateStart` performed 30 fresh `StillCamera` start/stop cycles against real hardware and confirmed that a duplicate start on a running camera fails with `CameraError.busy`.

Camera readiness after start, measured over 30 starts in two separate runs:

| Run | min | median | p95 | max |
| --- | --- | --- | --- | --- |
| 18:13:37 | 0.353 s | 0.376 s | 0.477 s | 0.658 s |
| 18:14:13 | 0.361 s | 0.378 s | 0.385 s | 0.668 s |

The provisional budget is p95 ≤ 1.5 s, so both runs met it with roughly threefold margin. These are Debug-build readiness times on one iPhone 14 at room temperature, recorded as a test attachment named `camera-readiness`. They are not a Release measurement, a thermal-soak result, or evidence for any other device.

Evidence: `/tmp/identityflow-device-lifecycle/Logs/Test/Test-UIKitSample-2026.09.18_18-13-37-+0700.xcresult` (focused) and `Test-UIKitSample-2026.09.18_18-14-13-+0700.xcresult` (full target).

`SampleUITests` could not be added in the same session: installing `SampleUITests-Runner` failed with `MIFreeProfileValidatedAppTracker`, the free-provisioning limit on concurrently installed apps. This is a provisioning limit, not a test or code failure; the UI suite continues to pass on Simulator. Free an app slot on the device or use a paid team to run it on hardware.

Still outstanding, all requiring manual interaction: camera permission revocation and return-to-app recheck, instrumented lock-state denial during crop editing, interruption stress, still/preview orientation comparison, hands-on VoiceOver order and announcements, minimum-iOS-16 hardware, and memory/thermal measurements.
