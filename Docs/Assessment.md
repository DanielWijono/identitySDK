# Plan assessment and implementation status

Assessed 9 September 2026 against the initially empty implementation directory.

The plan correctly separates capture guidance from identity decisions, bounds release scope, and preserves cleanup, idempotency and device evidence as gates. Its estimated 180–240 hours represents multiple milestones; no complete-release claim follows from the initial scaffold.

## Decisions and gaps

- Installed baseline recorded as Xcode 26.3 / Swift 6.2.4, Swift 6 language mode. This records the installed compiler, not a claim that it is the newest release.
- Added macOS 13 support to the platform-neutral core/demo solely for executable tests and a credential-free independent consumer.
- The core API remains headless. Independent UIKit and SwiftUI simulation apps consume the local package using a shared MainActor sample screen. The SDK owns the single-side UIKit camera/review component, its SwiftUI wrapper, and `DocumentCaptureCoordinator`, which sequences both sides into the evidence boundary. `ConfirmedImageCapture` moved from IdentityFlowSecurity to IdentityFlowCore so UI capture components conform without depending on encryption; `VaultEvidenceSource`'s signature is unchanged.
- The sample hosts provide live front/back confirmation, retake, manual crop and encrypted handoff through the evidence-source boundary. Rectangle guidance is advisory. Denied/restricted permission recovery includes a Settings action and active-return recheck; physical revocation validation remains pending.
- Provider cancellation must not block local completion. Cleanup does block completion by contract; a broken cleanup implementation can therefore block a run. Late provider returns cannot perform another workflow operation.
- Session lifetime is capped at 15 minutes using an injected monotonic clock. Both the fixed monotonic deadline and wall-clock expiry are checked at operation boundaries. Deterministic rollback, delayed-timer and local-ceiling tests cover expiry; suspension/foreground integration tests remain necessary.
- A submission uses one UUID for its logical run, and `HTTPVerificationProvider` now reuses it as the idempotency key. Bounded retry, pre-retry reconciliation and server-side duplicate protection are implemented and covered by mutation-verified contract tests against an in-process service. Live-network and wire-compatibility evidence is still absent.
- Providers still own bounded decision observation; the HTTP adapter implements a 30-second budget with backoff before handing off as pending. A core-enforced budget would still require a status/reference contract extension.
- Evidence reader and provider interfaces are provisional until vault/HTTP integration establishes format, profile and digest requirements.
- Rejected start requests do not take ownership of the supplied evidence source. Callers must not pre-capture data before an accepted run.

## Next ordered gates

1. Complete M0/M1 with explicit review/recovery transition tests and lifecycle integration. UIKit/SwiftUI simulation consumers, injected time, and cancellation coverage at each current capture/provider boundary are implemented.
2. Complete M2 integration and device gates. The vault is integrated through VaultEvidenceSource; throwing cleanup, retry ownership, immediate inactivity gating, stale activation rejection and terminal key/file deletion failures are tested. Physical-iPhone lock-state validation and broader write/retake crash coverage remain before real capture.
3. Continue M3: ImageNormalizer, integrated live capture, manual crop, Vision rectangle guidance, UIKit camera/review, its SwiftUI wrapper and SDK-owned front/back orchestration are implemented. Permission recovery and largest-category Dynamic Type have automated coverage. The remaining M3 work is physical only: run the prepared 30-cycle lifecycle/timing test, then validate permission revocation, interruptions, hands-on VoiceOver and lock-state behavior.
4. M4 adapter, in-process demo service and fault-injected contract tests are implemented; the accepted-request/lost-response gate is proven by mutation. Remaining: a real HTTP server for serialization and live network faults, plus the foreground/background reconciliation adapter.
5. Complete M5/M6 performance evidence, independent integration, privacy review, license selection and release artifacts.

The original plan is retained unchanged as the proposed release specification. The foundation is committed in the connected GitHub repository; no tagged release or deployment has been created.
