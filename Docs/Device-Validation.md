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
