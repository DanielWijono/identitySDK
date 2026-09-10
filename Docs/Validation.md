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
