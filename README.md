# IdentityFlow

An early Swift SDK foundation for coordinating an identity-document workflow. **Simulation only: no identity verification is performed.** The host/provider owns identity decisions.

Implemented: a Swift 6 actor-owned client, narrow evidence/provider contracts, consent acknowledgement before transfer, sequential front/back processing, a stable per-run submission key, terminal cleanup, expiry, cancellation, and explicit synthetic demo support. No third-party dependencies.

## Run

Validated toolchain: Xcode 26.3 (17C529), Apple Swift 6.2.4. Package minimums: iOS 16; macOS 13 for core development and the command-line simulation. Simulator validation is recorded in Docs/Validation.md; no physical-iPhone validation yet.

```sh
swift test
swift run --package-path Examples/Simulation Simulation
```

The example is an independent local package consumer. Its output is visibly labeled SIMULATION. Synthetic evidence is text, not a document image. Demo support is an opt-in product and never a fallback.

## Run on iPhone Simulator

Open `Examples/iOS/IdentityFlowSamples.xcodeproj`, select **UIKitSample** or **SwiftUISample**, choose an iPhone simulator, and press **⌘R**. Accept the sample disclosure, then start a simulation. Both apps offer approval, rejection, pending, failure and cancellation. See [sample instructions](Examples/iOS/README.md).

## Integrate the foundation

Create `VerificationClient(provider:)`, then await `run(session:consent:evidence:)`. Supply consent only after explicit user acceptance. `EvidenceSource` returns confirmed evidence through revocable readers and cleans up owned resources. The provider acknowledges consent, uploads both sides, submits, and returns approved/rejected/pending. `cancel()` and cancellation of the awaiting task converge on terminal cleanup.

Each run requires a fresh evidence source. Cleanup is idempotent and must revoke readers and prevent in-flight capture from creating new evidence. The client remains busy until cleanup completes. Provider implementations must bound their own I/O; uncooperative provider tasks may outlive local cancellation, but cannot advance the cancelled generation. Remote cancellation is best effort.

`VerificationSession` descriptions redact credentials. Its public token remains accessible to the host/provider and must never be logged. Error payloads from arbitrary providers are replaced with a typed error.

## Status

M0/M1 are in progress; this is not a v0.1 release. UIKit and SwiftUI simulation hosts are available. Camera, encrypted vault, HTTP adapter, automatic retry, foreground reconciliation, and physical-device evidence remain unimplemented. See [assessment](Docs/Assessment.md), [state contract](Docs/State-Machine.md), and the [original plan](IdentityFlow-SDK-Plan.md).

The optional progress continuation should use `AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))`. It finishes for accepted runs; callers own continuations for runs rejected during initial validation.
