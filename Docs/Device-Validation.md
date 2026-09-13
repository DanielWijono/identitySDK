# Physical-iPhone validation gate

Status: not performed. On 13 September 2026, an iPhone 15 Pro was available via devicectl, but the user deferred physical testing. No app was installed on the phone and no signing team was configured. Earlier checks on 9–10 September found paired iPhones unavailable. Simulator success is not evidence of physical locked-device data protection.

Use synthetic data only. Open the iOS sample project, choose a connected iPhone and your signing team, and run UIKitSample. Record device model, OS version, Xcode/build configuration, time, expected result and observed result for each check.

1. Complete approval, rejection, pending and failure. Confirm the host receives its result only after cleanup; inspect the owned directory and Keychain via a development test/debugger to confirm no session artifacts remain.
2. Start a run and lock during front transfer, back transfer and decision wait. Confirm the screen is concealed on inactivity. Unlock and reopen: expect cancellation, or an explicit cleanup-required state if deletion failed. Never accept a silent approval from a late response after cancellation won.
3. If cleanup is required, keep the same client. Unlock, tap Retry cleanup and verify the original terminal result is recovered without another upload/submission. Confirm both key and ciphertext are removed and Start becomes available.
4. Exercise Home/app switcher and quick foreground/background sequences. Verify the cover, cancellation and a fresh run after foreground entry. A stale activation must not reopen access during inactivity.
5. With a development test retaining an evidence reader, assert reads fail while inactive/locked and after cleanup. Check actual file-protection and backup-exclusion attributes and Keychain accessibility in a signed host; do not infer these properties from UI text.
6. Terminate the process during storage, relaunch and verify the first activation sweeps only SDK-owned keys/files. Preserve unrelated host test files and Keychain items as controls.
7. Repeat cancellation/cleanup and lock/unlock cycles and inspect resource retention. Record failures rather than weakening protection to make the sample run.

The sample cancels on inactivity; it is not a demonstration of transfer resumption or backend reconciliation. No camera is requested and no identity decisions are real.
