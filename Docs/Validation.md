# Validation record

9 September 2026, local Apple Silicon Mac, Xcode 26.3 (17C529), Apple Swift 6.2.4. Swift 6 language mode; no unchecked Sendable annotations and no third-party runtime dependencies.

`swift test --scratch-path /tmp/identityflow-build`: seven Swift Testing tests passed. The separate XCTest runner reports zero XCTest tests; the Swift Testing summary is the relevant count.

Coverage: approved/rejected/pending and operation order; provider-failure cleanup; cancellation despite held consent acknowledgement; duplicate-run rejection; host task cancellation; in-flight expiry; already-expired rejection; synthetic reader revocation; token description redaction.

Limitations: expiry test uses real time (50 ms); most async boundaries and terminal/cancellation race permutations still need deterministic coverage. No physical-device, camera, Keychain, encrypted-file, HTTP, UIKit, SwiftUI, memory, accessibility, or performance validation has been performed. This record is not release certification.

`swift run --package-path Examples/Simulation --scratch-path /tmp/identityflow-consumer Simulation`: independent package consumer compiled successfully and printed a clearly labeled simulated approval.
