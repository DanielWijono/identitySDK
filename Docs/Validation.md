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
