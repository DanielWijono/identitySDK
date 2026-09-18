# Validation record

9 September 2026, local Apple Silicon Mac, Xcode 26.3 (17C529), Apple Swift 6.2.4. Swift 6 language mode; no unchecked Sendable annotations and no third-party runtime dependencies.

`swift test --scratch-path /tmp/identityflow-build`: seven Swift Testing tests passed. The separate XCTest runner reports zero XCTest tests; the Swift Testing summary is the relevant count.

Coverage: approved/rejected/pending and operation order; provider-failure cleanup; cancellation despite held consent acknowledgement; duplicate-run rejection; host task cancellation; in-flight expiry; already-expired rejection; synthetic reader revocation; token description redaction.

The initial real-time expiry test has been replaced by the deterministic coverage recorded below. Further terminal/cancellation permutations and lifecycle integration still need coverage. No physical-device, camera, Keychain, encrypted-file, HTTP, UIKit, SwiftUI, memory, accessibility, or performance validation has been performed. This record is not release certification.

`swift run --package-path Examples/Simulation --scratch-path /tmp/identityflow-consumer Simulation`: independent package consumer compiled successfully and printed a clearly labeled simulated approval.

## Deterministic lifecycle follow-up

Added a controllable internal clock and tests for wall-clock rollback, a delayed expiry timer, and the 15-minute local ceiling. The delayed-timer test holds the timer while a provider completes, proving that operation-boundary checks independently enforce the monotonic deadline. No elapsed-time sleeps are used by these tests.

Cancellation is exercised at consent, front/back capture, front/back upload, submission and decision. Tests also verify terminal progress completion and that a reserved approval survives cancellation during blocked cleanup; the client rejects new work until cleanup ends and accepts a fresh run afterward. Clock test helpers use Mutex and require macOS 15/iOS 18; the production core retains macOS 13/iOS 16 minimums.

Follow-up validation: `swift test --scratch-path /tmp/identityflow-build` passed all 11 tests, including the seven cases of the cancellation-boundary test. The independent simulation consumer rebuilt and ran successfully with the unchanged public initializer.

## iOS sample hosts

Both UIKitSample and SwiftUISample built for generic iOS Simulator (arm64 and x86_64) with Xcode 26.3 and the iOS 26.2 SDK, targeting iOS 16. The UIKit UI suite passed 2 tests with zero failures on iPhone 16 Pro Simulator, iOS 18.3.1 (22D8075): consent gating and all four outcomes; cancellation and restart availability. SwiftUISample was installed and launched on the same simulator. A visual check identified a compressed consent switch; required horizontal hugging/compression priorities fixed it, and the rebuilt SwiftUI screen was checked again.

No minimum-iOS-16 runtime, physical-device, VoiceOver or maximum-Dynamic-Type validation is claimed. The UI tests precede the final layout-only switch priority adjustment; the adjusted shared source was rebuilt in SwiftUISample. The hosts simulate capture/transfer and cancel on background; they do not implement production capture/review or foreground reconciliation.

## Vault foundation

Local Swift 6 suite: all 17 tests passed (11 core plus 6 vault tests). Vault coverage includes ciphertext round-trip, retake/revocation, foreground gating, terminal cleanup, tampering and swapped side authentication failure, simulated Keychain lock/missing-key failures, retry after failed key deletion, orphan sweep with host-file preservation, monotonic local expiry despite wall rollback, and a real macOS Keychain round-trip with service isolation. Synthetic bytes/keys only.

The security module also passed a Swift 6 strict-concurrency type-check for arm64 iOS 16 Simulator against the installed iOS 26.2 SDK. This does not prove iOS Keychain entitlements or physical locked-file behavior. The final retake bookkeeping adjustment passed the local suite; filesystem deletion fault injection remains open. Existing sample sources were unchanged and still use synthetic memory storage; no new camera or production vault integration is claimed.

## Integrated vault and cleanup recovery

9 September 2026: the final local suite passed all 27 Swift Testing tests. Added end-to-end vault cleanup for approved/rejected/pending/technical failure, user and task cancellation, and a manually fired core expiry timer while a provider is held. Parameterized recovery tests retain the original approved/rejected/pending/failed/cancelled/expired result through failed key deletion. Other checks cover ciphertext-file deletion failure after key deletion, concurrent cleanup retry exclusion, late capture rejection, an allocation/cleanup race, immediate inactivity gating, and rejection of stale foreground permits. Fault injection uses synthetic keys/data and isolated temporary directories.

The UIKit simulator suite passed all 3 UI tests on iPhone 16 Pro Simulator, iOS 18.3.1: consent and four outcomes; cancellation; background/foreground cancellation followed by another successful run. These now exercise real simulator Keychain operations and encrypted synthetic JPEGs through VaultEvidenceSource. The first run with `CODE_SIGNING_ALLOWED=NO` failed during storage initialization; rerunning with normal Xcode simulator signing passed. Keep normal signing for sample runs. The shared error-screen cover visibility was then corrected and rebuilt in the signed SwiftUI host.

The signed SwiftUI host built and launched successfully; its initial screen was visually checked with storage initialized and no Retry storage error. The independent command-line consumer rebuilt and printed its simulated approval after the cleanup protocol change. No physical iPhone was available from `devicectl`; lock/unlock behavior, real protected-file denial and crash-point coverage remain open in Device-Validation.md. Background Simulator tests do not replace those gates.

## Image normalization — 10 September 2026

The full local suite passed 33 tests (27 existing and 6 normalization tests). A follow-up normalization-only run passed all 6 tests after extending format coverage to both PNG and HEIC. Orientation is checked with independent fixture sanity checks and pixel-position assertions for all 8 EXIF values, including mirrors. Other cases cover sensitive metadata removal, downsampling/no upscaling, invalid and unsupported input, input/output limits and cancellation. Fixtures are generated in memory; no real identity data is used.

UIKitSample's 3 UI tests passed on iPhone 16 Pro Simulator, iOS 18.3.1, with normalization integrated before vault encryption. SwiftUISample built for generic iOS Simulator. The final unrecognized-format error-classification adjustment was verified locally; it does not affect the valid synthetic JPEG path exercised by the UI tests. No physical iPhone was available on the repeat device check. No camera, readability, real-device protection, or performance measurements are claimed.

## Synthetic document review — 13 September 2026

UIKitSample passed all 4 UI tests on iPhone 16 Pro Simulator, iOS 18.3.1. Coverage includes consent and all four outcomes with explicit front/back confirmation, front-review cancellation, retake on both sides followed by back-review cancellation, and backgrounding during review followed by a successful fresh run. The first run found duplicate accessible Cancel buttons; the underlying host controls are now hidden while review is open. The final suite passed with zero failures. SwiftUISample also built for generic iOS Simulator using the final shared source.

The sample adapter holds unconfirmed JPEGs only in memory, replaces the current preview on retake, and passes only confirmed images through normalization and the encrypted vault. Cancellation and inactivity synchronously remove preview pixels; the core reserves its terminal result before capture cleanup resumes the pending continuation. This implements sample-host review, not the SDK-owned UI facade, cropping or real camera capture. No new physical-device, VoiceOver, maximum-Dynamic-Type or review-expiry UI validation is claimed. Package sources were unchanged; the prior 33 package-test result remains the latest package validation.

## Camera component preparation — 13 September 2026

The full package suite passed all 33 tests. The optional camera engine and UIKit camera/review product built with Swift 6 strict concurrency in both example hosts for generic iOS Simulator. The sample's active flow remains synthetic; no live-camera path was connected.

On iPhone 16 Pro Simulator, iOS 18.3.1, the combined run passed 10 tests: the existing 4 UI tests and 6 new camera component tests. Following explicit controller-deinitialization cleanup, all 7 camera component tests passed. Coverage uses an injected fake camera for confirm-once delivery, retake, invalid-image recovery, interruption retry, inactivity cleanup, late photo completion after cancellation and release of an unpresented controller. The real camera actor is tested only for rejection after stop; the simulator authorization check returns unavailable without prompting. A test-only weak-reference warning was then removed and the release test rerun.

The iPhone 15 Pro was available, but the user deferred physical testing. No phone installation, signing changes or lock/unlock checks were performed. Hardware capture, permissions, preview/still alignment, interruption delivery, resource/performance behavior and real protected-file denial remain unverified. This is camera preparation, not completion of M3 or approval to process real identity documents. See Camera-Capture.md and Device-Validation.md.

### Standalone hardware-test entry point — 13 September 2026

Added Test live camera to the shared sample host, with explicit permission preflight and discarded confirmation bytes. UIKitSample builds passed for simulator and the selected iPhone 14 using the team already selected in the local Xcode project. Installation succeeded on iOS 17.3; launch was rejected by iOS with a signature/entitlement/developer-trust error. User trust must be checked before capture can be exercised. No hardware camera or storage validation is claimed. Existing local Xcode project edits were preserved.

After the user trusted the developer on the iPhone 14, devicectl successfully launched UIKitSample at 10:10 Asia/Jakarta. Live preview and capture still require user observation; launch success alone does not validate them.

### Physical storage checks — 13 September 2026

`CameraComponentTests/StorageDeviceTests` ran in the signed UIKitSample host on the user-selected iPhone 14, iOS 17.3. xcresult reports 2 passed, 0 failed, 0 skipped. Verified real Keychain attributes, complete file protection, root backup exclusion, ciphertext round-trip, replacement and cleanup revocation, simulated inactivity and isolated startup sweep. See Device-Validation.md for limitations and evidence path. Manual lock/unlock and actual process termination remain pending.

## Live camera integration — September 13, 2026

- UIKit simulator regression: 12 passed, zero failures/skips (8 camera/adapter tests and 4 simulation UI tests). Artifact: `/tmp/identityflow-uikit/Logs/Test/Test-UIKitSample-2026.09.13_14-33-56-+0700.xcresult`.
- Adapter test covers sequential front/back children below the privacy cover, removal, cancellation, rejection of late confirmation, idempotent cleanup, and prevention of reuse.
- Signed iPhone 14 build and installation succeeded. Launch was denied because the device was locked; user must unlock/open the app.
- Actual integrated live-camera behavior and complete physical security gate remain pending. No real identity verification or network upload was added.

- Final-source focused rerun passed: live adapter cancellation and simulator camera-unavailable recovery (2 tests). Artifact: `/tmp/identityflow-uikit/Logs/Test/Test-UIKitSample-2026.09.13_14-37-08-+0700.xcresult`. SwiftUI simulator build also passed.

## Manual crop implementation — September 13, 2026

The full package suite passed all 35 Swift Testing tests on the current source. Two new normalization tests cover upright top-left crop coordinates across all eight EXIF orientations, outward pixel rounding, metadata removal and invalid crop bounds. The crop implementation operates after orientation normalization and 2,000-pixel downsampling, does not upscale, and emits a fresh bounded JPEG.

The UIKit camera review component now starts with the full captured image, exposes four accessible inset sliders, requires a separate Preview crop action, and enables Use this image only after the cropped JPEG is prepared. Updated fake-camera component coverage checks cropped output dimensions, retake after crop preview, confirmation-once behavior and inactivity cancellation.

On iPhone 16 Pro Simulator, iOS 18.3.1, all 5 UIKit workflow UI tests passed and all 8 camera/adapter component tests passed. The earlier focused crop-component run also passed 8 tests with no failures or skips; artifact: `/tmp/identityflow-crop/Logs/Test/Test-UIKitSample-2026.09.13_14-50-29-+0700.xcresult`. A later combined run additionally executed the two physical storage tests and exposed that Simulator does not report the `.protectionKey` resource value; those assertions are meaningful only on a device. Both storage tests now skip explicitly under `targetEnvironment(simulator)`. A focused final-source rerun passed 8 camera/adapter tests with 2 physical-only storage tests skipped and no failures; artifact: `/tmp/identityflow-crop-uikit/Logs/Test/Test-UIKitSample-2026.09.13_21-57-47-+0700.xcresult`.

A signed UIKit iPhone build passed and was installed on DEV TESTING 7 (iPhone 14) at 14:51 WIB. A later signed generic iOS build also succeeded using the development team already recorded by the device-test target; the app target project settings were not changed. That current build was installed successfully at 22:00 WIB after DEV TESTING 7 reconnected, but remote launch was denied because the phone was locked. No physical crop observation is claimed. The intervening source adjustment only restricts physical storage tests on Simulator and does not change the installed application behavior.

The live front/back capture and interruption checklist was reported complete by the user before crop controls were added. That observation is not an instrumented security result and does not validate the new crop flow. Physical checks of front/back crop readability, retake, locking during crop editing and a fresh subsequent run remain pending. Automatic rectangle detection, actual locked-file denial, VoiceOver, maximum Dynamic Type and performance measurements also remain open. Use printed test cards only; no network upload or identity verification occurs. An initial incremental simulator build used a stale capture interface; a fresh derived-data build and final rerun passed. `git diff --check` passed.

## Native camera preview — 17 September 2026

The user-reported crop flow subsequently passed the physical printed-card checklist, including front/back crop editing, crop preview, retake, locking during crop editing and a fresh run. This remains user-observed UI evidence, not an instrumented locked-storage or readability result.

The lag investigation found that the real preview was deliberately throttled to 5 FPS and converted every displayed frame from Core Image through `CGImage` to `UIImage`. A 15-second iPhone 14 Time Profiler trace found no app hang over 250 ms. The implementation now displays the capture session through `AVCaptureVideoPreviewLayer` and removes `AVCaptureVideoDataOutput` from the real camera, eliminating the preview throttle and application-level per-frame copies. Synthetic camera implementations retain the pixel-event fallback.

The current full package suite passed all 35 tests. The focused UIKit camera/adapter suite passed all 9 tests on iPhone 16 Pro Simulator, iOS 18.3.1, including native preview attachment and removal on cancellation. Artifact: `/tmp/identityflow-native-preview-uikit-final/Logs/Test/Test-UIKitSample-2026.09.17_09-38-02-+0700.xcresult`. A signed generic-iOS UIKitSample build also succeeded at `/tmp/identityflow-native-preview-device/Build/Products/Debug-iphoneos/UIKitSample.app`. DEV TESTING 7 was unavailable, so the new build was not installed and physical preview smoothness/orientation remains pending.

The device later reconnected; the build installed and launched successfully. The user reported “very good no lagging.” This is a physical user observation, not an instrumented frame-rate or thermal measurement.

## Vision rectangle guidance — 17 September 2026

Added advisory `VNDetectRectanglesRequest` guidance on a separate AVFoundation-managed, preview-sized portrait YUV output capped at 4 Hz. A serial queue performs synchronous analysis, ensuring at most one in-flight frame, while `AVCaptureVideoPreviewLayer` remains independent. Guidance distinguishes searching, insufficient coverage, edge clipping, hold-steady and ready after three stable observations. The manual shutter stays enabled in every state; no automatic shutter, final crop, identity validation or hard rejection was added.

The full package suite passed all 38 tests, including three deterministic coverage/margin/stability tests. All 10 focused camera/adapter component tests passed on iPhone 16 Pro Simulator, iOS 18.3.1, including guidance status without shutter blocking. Artifact: `/tmp/identityflow-rectangle-uikit-final/Logs/Test/Test-UIKitSample-2026.09.17_11-16-39-+0700.xcresult`. The signed build succeeded, installed, and launched on DEV TESTING 7. The user subsequently reported that the physical guidance test was good; this is not quantified detection-accuracy evidence.

Duplicate start now fails with `CameraError.busy`. A new device-only component test performs 30 real-camera start/stop cycles, checks duplicate-start rejection and asserts the provisional 1.5-second p95 readiness target. The final Simulator camera suite passed with 10 tests and this hardware-only test skipped. DEV TESTING 7 disconnected before the physical test run, so lifecycle stability and timing remain pending.

## SwiftUI camera wrapper — 17 September 2026

Added public `CameraReviewView`, a thin `UIViewControllerRepresentable` over the same `CameraReviewViewController` used by UIKit. It forwards confirmation/cancellation callbacks, updates them with SwiftUI state changes and cancels capture when dismantled. Permission preflight and confirmed-byte ownership remain host responsibilities.

The focused camera suite passed 11 tests with the device-only 30-cycle lifecycle test skipped on iPhone 16 Pro Simulator, iOS 18.3.1. New coverage creates the wrapper in `UIHostingController`, waits for the shared camera controller to start through an injected fake, and verifies cancellation forwarding. Artifact: `/tmp/identityflow-swiftui-wrapper-tests/Logs/Test/Test-UIKitSample-2026.09.17_22-28-51-+0700.xcresult`. SwiftUISample also built successfully for generic iOS Simulator from final source.

## Camera permission recovery — 17 September 2026

Both live-camera entry points now convert denied/restricted authorization into an explicit **Open Camera Settings** action. Returning to the active app rechecks authorization and reports whether access is enabled or still unavailable; it does not automatically launch capture or start a verification session. Unavailable Simulator hardware retains its separate generated-card recovery path. Authorization queries and Settings opening are injected in the sample host for deterministic coverage.

The final focused camera suite passed 12 tests with the device-only 30-cycle lifecycle test skipped on iPhone 16 Pro Simulator, iOS 18.3.1. The new test covers denied access, Settings action forwarding, authorized return and action removal without modifying system permissions. Artifact: `/tmp/identityflow-permission-uikit-final/Logs/Test/Test-UIKitSample-2026.09.17_22-45-13-+0700.xcresult`. SwiftUISample rebuilt successfully for generic iOS Simulator. Physical revocation/return remains pending.

## Camera accessibility and Dynamic Type — 17 September 2026

Live guidance now exposes semantic accessibility values for no detection, move closer, edge clipping, hold steady and ready; readiness therefore does not rely on yellow/green alone. Crop sliders provide named edges and percentage inset values, and the preview summarizes the combined crop before and after processing. Guidance and crop labels wrap and opt into Dynamic Type.

The focused camera suite passed 13 tests with the physical 30-cycle lifecycle test skipped on iPhone 16 Pro Simulator, iOS 18.3.1. New coverage overrides the camera screen to `.accessibilityExtraExtraExtraLarge`, verifies ready guidance is spoken, completes capture to crop controls, checks all four slider labels/values and confirms scroll content layout. Artifact: `/tmp/identityflow-accessibility-uikit/Logs/Test/Test-UIKitSample-2026.09.17_22-52-55-+0700.xcresult`. This is automated semantic/layout coverage, not hands-on VoiceOver navigation or a visual clipping audit on physical hardware.

## SDK front/back orchestration — 18 September 2026

`DocumentCaptureCoordinator` and `DocumentCapturePresenter`/`ChildCapturePresenter` were added to IdentityFlowUI, and the sample's `LiveCardCapture` adapter was deleted in favour of them. `ConfirmedImageCapture` moved from IdentityFlowSecurity to IdentityFlowCore, so IdentityFlowUI conforms without depending on encryption; `VaultEvidenceSource`'s public signature is unchanged.

The full package suite passed all 38 tests after the protocol move — the same count as before, confirming the move is behaviour-neutral.

On iPhone 16 Pro Simulator, iOS 18.3.1, the UIKitSample run executed 19 component tests with 3 skipped and zero failures, plus all 5 `SimulationUITests`. The camera/adapter suite grew from 14 to 17 cases: the previous `testLiveAdapterSequencesSidesAndRejectsCallbacksAfterCancel` was rewritten against the coordinator and joined by concurrent-side rejection, task-cancellation teardown with camera shutdown, and presenter-unavailable failure. The device-only 30-cycle lifecycle test and both `StorageDeviceTests` skipped explicitly as designed. Artifact: `/tmp/identityflow-facade-uikit/Logs/Test/Test-UIKitSample-2026.09.18_17-11-54-+0700.xcresult`.

The 5 passing `SimulationUITests` are the end-to-end evidence that the rewired sample still completes consent, all four outcomes, review cancellation, retake and background/foreground restart through the SDK-owned coordinator. SwiftUISample also built for generic iOS Simulator from the final source, and `git diff --check` passed.

No new physical-device, VoiceOver or performance validation is claimed. This change relocates already-validated orchestration into the SDK; it does not establish any hardware property.

## M4 HTTP provider and recovery — 18 September 2026

Added `IdentityFlowHTTP` (`HTTPVerificationProvider`, `URLSessionTransport`, `RetryPolicy`, wire types) and `IdentityFlowDemoService` (`DemoVerificationService`, `DemoServiceTransport`). The demo service is an in-process model of the documented contract; it is not a socket server, and it shares the `Wire` codec with the adapter, so these results establish protocol *semantics* rather than wire compatibility.

The full package suite passed all 54 Swift Testing tests (38 existing plus 16 contract tests). Coverage: whole-contract run through `VerificationClient`; lost response after an accepted commit; lost response after an accepted upload; replayed idempotency key; conflicting payload under an existing key; expired session; rejected credentials; rate limit honouring `Retry-After`; hostile `Retry-After` capped at 10 s; exhausted bounded retries with asserted 0.5/1/2 s backoff; malformed state body; server-enforced evidence size limit; delayed decision handing off as pending after the 30-second budget with 1/2/4/5 s poll backoff; delayed decision resolving when the server decides; cancellation while awaiting a decision; and a hostile error body whose free-form text must not reach the caller.

Timing is deterministic: an injected clock records each sleep and advances virtual time without elapsed wall time, and jitter is fixed. The suite passed 5 consecutive runs with no flakiness after an initial race — an instant clock let the decision budget elapse before a test could cancel — was fixed by parking the clock during the cancellation test.

The exit gate was verified by mutation rather than by observing a green test. With client-side reconciliation disabled, `lostResponseAfterAcceptedCommitProducesExactlyOneSubmission` fails on `submissionRequests == 1` and the transport call count, and `lostResponseAfterAcceptedUploadDoesNotStoreEvidenceTwice` fails on `evidenceRequests == 2`. With server-side idempotency disabled instead, `replayedCommitWithSameKeyCreatesNoSecondSubmission` fails on `logicalSubmissions == 1` while the lost-response gate still passes, because reconciliation alone prevents the second request. The two defences are therefore independently covered. Both mutations were reverted.

UIKitSample built for generic iOS Simulator and the independent command-line consumer rebuilt and printed its simulated approval, confirming the new targets did not disturb existing consumers.

No network, TLS, real-server, physical-device or performance validation is claimed. `URLSessionTransport` itself is exercised only by compilation; every contract test runs against the in-process service.

## Physical camera lifecycle gate — 18 September 2026

The device-only hardware gate ran for the first time. DEV TESTING 7, iPhone 14, iOS 17.3 (21D50), Xcode 26.3, Debug, over USB after the wireless tunnel proved unavailable.

`CameraComponentTests` target on device: **19 tests, 0 failures, 0 skipped**, covering 17 camera/adapter/coordinator tests and the 2 `StorageDeviceTests` that skip on Simulator. This is also the first hardware run of the `DocumentCaptureCoordinator` tests added with the front/back orchestration facade.

`testRepeatedHardwareLifecycleAndDuplicateStart` completed 30 real start/stop cycles and confirmed duplicate-start rejection with `CameraError.busy`. Readiness p95 was 0.477 s and 0.385 s across two runs, against the provisional 1.5-second budget. The test now records min/median/p95/max plus the raw samples as a `camera-readiness` attachment, so the budget is published with its measurement rather than only asserted.

Artifacts: `/tmp/identityflow-device-lifecycle/Logs/Test/Test-UIKitSample-2026.09.18_18-13-37-+0700.xcresult` and `Test-UIKitSample-2026.09.18_18-14-13-+0700.xcresult`.

`SampleUITests` could not run on the device: installing its runner hit the free-provisioning concurrent-app limit. That is a provisioning constraint, not a code or test failure, and the UI suite still passes on Simulator.

These results cover one device, one OS version and a Debug build. They establish nothing about other hardware, Release builds, thermal behavior or sustained memory.
