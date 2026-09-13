# Plan assessment and implementation status

Assessed 9 September 2026 against the initially empty implementation directory.

The plan correctly separates capture guidance from identity decisions, bounds release scope, and preserves cleanup, idempotency and device evidence as gates. Its estimated 180–240 hours represents multiple milestones; no complete-release claim follows from the initial scaffold.

## Decisions and gaps

- Installed baseline recorded as Xcode 26.3 / Swift 6.2.4, Swift 6 language mode. This records the installed compiler, not a claim that it is the newest release.
- Added macOS 13 support to the platform-neutral core/demo solely for executable tests and a credential-free independent consumer.
- The core API remains headless. Independent UIKit and SwiftUI simulation apps now consume the local package using a shared MainActor sample screen. The SDK-owned capture/review facade remains to be built.
- Capture/review is currently represented by an evidence-source boundary. The sample hosts now provide explicit front/back confirmation and retake before transfer. SDK-owned review states, cropping and permission recovery remain unimplemented.
- Provider cancellation must not block local completion. Cleanup does block completion by contract; a broken cleanup implementation can therefore block a run. Late provider returns cannot perform another workflow operation.
- Session lifetime is capped at 15 minutes using an injected monotonic clock. Both the fixed monotonic deadline and wall-clock expiry are checked at operation boundaries. Deterministic rollback, delayed-timer and local-ceiling tests cover expiry; suspension/foreground integration tests remain necessary.
- A submission uses one UUID for its logical run. HTTP retry, reconciliation and server-side duplicate protection remain unimplemented; a UUID alone does not provide those guarantees.
- Providers currently own bounded decision observation. A core-enforced 30-second pending handoff requires a status/reference contract extension.
- Evidence reader and provider interfaces are provisional until vault/HTTP integration establishes format, profile and digest requirements.
- Rejected start requests do not take ownership of the supplied evidence source. Callers must not pre-capture data before an accepted run.

## Next ordered gates

1. Complete M0/M1 with explicit review/recovery transition tests and lifecycle integration. UIKit/SwiftUI simulation consumers, injected time, and cancellation coverage at each current capture/provider boundary are implemented.
2. Complete M2 integration and device gates. The vault is integrated through VaultEvidenceSource; throwing cleanup, retry ownership, immediate inactivity gating, stale activation rejection and terminal key/file deletion failures are tested. Physical-iPhone lock-state validation and broader write/retake crash coverage remain before real capture.
3. Continue M3: ImageNormalizer now handles bounded JPEG encoding and orientation/metadata removal; sample review/retake is implemented; camera, cropping and SDK-owned review remain. validate permissions, interruptions, accessibility and timing on physical hardware.
4. Implement M4 demo HTTP service and adapter; prove accepted-request/lost-response idempotency with fault injection.
5. Complete M5/M6 performance evidence, independent integration, privacy review, license selection and release artifacts.

The original plan is retained unchanged as the proposed release specification. The foundation is committed in the connected GitHub repository; no tagged release or deployment has been created.
