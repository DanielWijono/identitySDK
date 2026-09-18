# IdentityFlow

An early Swift SDK foundation for coordinating an identity-document workflow. **Simulation only: no identity verification is performed.** The host/provider owns identity decisions.

Implemented: a Swift 6 actor-owned client, narrow evidence/provider contracts, consent acknowledgement before transfer, sequential front/back processing, a stable per-run submission key, terminal cleanup, expiry, cancellation, and explicit synthetic demo support. No third-party dependencies.

## Run

Validated toolchain: Xcode 26.3 (17C529), Apple Swift 6.2.4. Package minimums: iOS 16; macOS 13 for core development and the command-line simulation. Simulator and limited physical-iPhone validation are recorded in Docs/Validation.md and Docs/Device-Validation.md. Physical storage tests passed on an iPhone 14 running iOS 17.3; remaining camera, crop, lock-state, accessibility and performance gates are explicitly documented.

```sh
swift test
swift run --package-path Examples/Simulation Simulation
```

The example is an independent local package consumer. Its output is visibly labeled SIMULATION. Synthetic evidence is text, not a document image. Demo support is an opt-in product and never a fallback.

## Run on iPhone Simulator

Open `Examples/iOS/IdentityFlowSamples.xcodeproj`, select **UIKitSample** or **SwiftUISample**, choose an iPhone simulator, and press **⌘R**. Accept the sample disclosure, then start a simulation. Review the synthetic front and back images, use **Retake** to replace a preview, and choose **Use this image** to confirm each side. Both apps offer approval, rejection, pending, failure and cancellation. See [sample instructions](Examples/iOS/README.md).

## Integrate the foundation

Create `VerificationClient(provider:)`, then await `run(session:consent:evidence:)`. For live capture, pass a `DocumentCaptureCoordinator` to `VaultEvidenceSource` as its capture; it drives one review screen per side and invalidates callbacks from screens it has removed. Complete camera-permission preflight before starting the run. Supply consent only after explicit user acceptance. `EvidenceSource` returns confirmed evidence through revocable readers and cleans up owned resources. The provider acknowledges consent, uploads both sides, submits, and returns approved/rejected/pending. `cancel()` and cancellation of the awaiting task converge on terminal cleanup.

Each run requires a fresh evidence source. Cleanup is idempotent and must revoke readers and prevent in-flight capture from creating new evidence. If deletion fails, the client throws `cleanupRequired` and rejects new runs. Retain it and call `retryCleanup()` after storage becomes available; successful retry delivers the original result without repeating uploads. Provider implementations must bound their own I/O; uncooperative provider tasks may outlive local cancellation, but cannot advance the cancelled generation. Remote cancellation is best effort.

`VerificationSession` descriptions redact credentials. Its public token remains accessible to the host/provider and must never be logged. Error payloads from arbitrary providers are replaced with a typed error.

## Status

M0/M1 foundations and most of the M2 secure-evidence lifecycle are implemented; M3 camera capture is code-complete and its remaining gates are physical; M4 transport recovery is implemented against an in-process demo service. This is not a v0.1 release. UIKit and SwiftUI simulation hosts are available. Image normalization and encrypted storage are integrated into the iOS sample hosts; see [normalization](Docs/Image-Normalization.md) and [vault contract and remaining gates](Docs/Evidence-Vault.md).

The SDK now owns front/back capture orchestration: `DocumentCaptureCoordinator` sequences both sides through the shared UIKit capture component and conforms to `ConfirmedImageCapture`, so it feeds `VaultEvidenceSource` directly. `ChildCapturePresenter` embeds each side below the host's privacy cover. The sample's live-camera path consumes that coordinator instead of its own adapter, and covers review, retake, temporary encrypted storage and the local simulated provider. Manual crop-edge controls, separate cropped-image confirmation, and a SwiftUI wrapper over the same capture component are implemented. The full package suite passes 38 tests, including upright-coordinate crop coverage for all eight EXIF orientations and rectangle-guidance scoring. The physical crop and rectangle-guidance checklists were user-observed as passing, and signed physical storage component tests are recorded. The reported five-FPS preview lag was replaced by a native AVFoundation preview layer and the user confirmed that the physical preview no longer lagged. Use printed test cards only; no network upload or identity verification occurs. See [camera status](Docs/Camera-Capture.md), [device checklist](Docs/Device-Validation.md) and [validation evidence](Docs/Validation.md).

`HTTPVerificationProvider` implements the demo HTTP contract with bounded retry, reused evidence IDs and submission keys, and reconciliation before repeating any mutation, so a lost response cannot create a second logical submission. `DemoVerificationService` models the server side in process and enforces token binding, consent ordering, evidence limits, expiry and idempotency independently of client code. The suite passes 54 tests, and the duplicate-submission gate was verified by mutation: disabling either defence fails a different test. No socket server, TLS or live-network validation exists yet, and the adapter and service share the wire codec, so wire compatibility is not established. See [provider contract](Docs/Provider-Contract.md).

M3 has no outstanding code deliverable. The repeated-camera-lifecycle gate now passes on hardware: 19 device tests with zero skips on an iPhone 14 (iOS 17.3), with camera readiness p95 of 0.477 s and 0.385 s across two 30-start runs against a 1.5-second budget. What remains is manual: permission revocation and interruption checks on hardware, instrumented lock-state denial during crop editing, minimum-iOS hardware, hands-on VoiceOver and memory/thermal measurements. Denied/restricted permission recovery and the largest Dynamic Type category are component-tested. Still open for M4: a real HTTP demo server for serialization and live network faults, and the foreground/background lifecycle reconciliation adapter. See [assessment](Docs/Assessment.md), [state contract](Docs/State-Machine.md), and the [original plan](IdentityFlow-SDK-Plan.md).

The optional progress continuation should use `AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))`. It finishes for accepted runs; callers own continuations for runs rejected during initial validation.
