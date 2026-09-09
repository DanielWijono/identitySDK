# IdentityFlow: iOS eKYC SDK implementation plan

Planning baseline: 7 September 2026. Working project name; availability has not been checked. This is a proposed portfolio implementation, not an implemented or certified verification product.

## 1. Outcome and assumptions

Build a reusable Swift SDK that coordinates consent, identity-document capture, secure temporary storage, upload, and an asynchronous verification decision. A host app integrates the flow through a small public API. The backend or verification provider makes the identity decision.

Scope combines items #1, #2, and #3 from the original ranked table: eKYC workflow, a small document-capture component, and secure verification-session handling. NFC/JPKI is a later extension, not part of this release.

The target role values SDK interfaces, security, memory and concurrency, performance, documentation, and third-party developer support. Existing ZOLOZ integration experience informs the design; no employer code, proprietary SDK binaries, credentials, or real identity documents enter the public repository.

Assumptions: one experienced iOS engineer, iOS 16+ as a deliberate project baseline, iPhone capture, portrait-first sample UI, current stable Xcode at implementation kickoff, Swift 6 language mode with strict concurrency. Record the exact supported compiler and OS matrix at kickoff. Plan 180–240 engineering hours: approximately 10–12 weeks at 20 hours/week, or 18–24 weeks at 10 hours/week. These are planning estimates, not delivery guarantees.

Success: a reviewer can install the package, run a clearly labeled simulation without credentials, inspect meaningful tests, and reproduce a documented interrupted flow on a real iPhone.

## 2. Release boundaries

| Capability | v0.1 commitment | Deferred |
| --- | --- | --- |
| Workflow | One active session per SDK client; enforced transition rules; typed results/errors | Concurrent verification sessions |
| Documents | One configurable card-shaped document profile, front and back | Passport, country-specific document authenticity rules |
| Capture | Rectangle/framing guidance, basic blur heuristic, manual shutter, crop confirmation, retake | Automatic shutter, reliable glare classification, OCR |
| Session protection | Per-session encryption, protected temporary files, expiry, cleanup | Secure Enclave device binding, cross-launch capture resume |
| Network | Foreground upload, bounded retry, idempotent submission, status reconciliation | Background transfers and resumable multipart upload |
| Verification | Deterministic mock provider and a demo HTTP service | Production vendor integration and live verification |
| Presentation | UIKit capture component, SwiftUI wrapper, basic theming and accessibility | Full design system and broad localization |
| Distribution | Source-based Swift Package | Signed binary XCFramework release |
| Platforms | iOS implementation, platform-neutral contract notes | Kotlin SDK, NFC/JPKI, React Native bridge |

Do not implement face recognition, liveness, fraud scoring, home-grown cryptographic algorithms, or automated regulatory-compliance claims. A technically successful upload is not an identity approval.

## 3. User and integration flow

1. Host authenticates with its own backend and obtains a short-lived, narrowly scoped session token plus an opaque session ID and expiry.
2. Host creates an SDK client with its provider dependency and presents the SDK screen using the token.
3. SDK displays a versioned disclosure supplied by the host. The demo uses clearly labeled sample copy. Acceptance is sent to the backend before evidence submission; local acceptance alone is not a durable audit record.
4. SDK requests camera permission when needed and guides capture of front/back images. Denial produces a recoverable, actionable state.
5. User reviews and confirms each image. SDK strips unnecessary metadata, normalizes orientation, bounds dimensions, encrypts evidence, and releases plaintext references promptly.
6. SDK uploads the confirmed evidence, commits one submission, and observes the provider decision.
7. Host receives approved, rejected, pending, cancelled, or a typed technical failure. SDK cleans up local evidence on every exit path.

Pending is a legitimate host handoff: verification may continue on the server after the UI closes. The host/backend can retrieve the decision later by session ID. The initial release does not persist an SDK credential for this handoff.

## 4. Module architecture

| Module | Owns | Dependency rule |
| --- | --- | --- |
| IdentityFlowCore | Public contracts, session actor, state transitions, retry decisions | No UIKit, SwiftUI, camera, or vendor imports |
| IdentityFlowCapture | AVFoundation pipeline, Vision rectangle guidance, image normalization | Uses core value types; no provider dependency |
| IdentityFlowSecurity | Evidence vault, Keychain interface, expiry and cleanup | Uses narrow core storage contracts |
| IdentityFlowUI | UIKit orchestration screen and SwiftUI wrapper | Composes core and capture; UI work on MainActor |
| IdentityFlowDemoSupport | Scripted provider, synthetic documents, fault scenarios | Separate optional target; never an implicit production fallback |
| DemoService | Demo HTTP contract and deterministic outcomes | Outside the SDK package runtime |

Publish one package with a small number of opt-in products. Keep implementation classes internal; internal protocols do not automatically become public API. Add a tiny facade only if it materially simplifies integration.

Session mutations run through one actor. Capture configuration, start/stop, and frame delivery use explicitly controlled execution contexts. UI observes immutable snapshots on MainActor. Isolate non-Sendable AVFoundation objects inside capture ownership; do not bypass concurrency diagnostics with blanket unchecked annotations.

Bound the frame pipeline to one analysis operation in flight and discard stale frames. Assign every session a generation identifier; ignore callbacks and results from previous generations.

## 5. Public API contract

The following is an API sketch, not compiled source:

```swift
@MainActor
public protocol VerificationFlow: AnyObject {
    func run(
        session: VerificationSession,
        presentingFrom presenter: UIViewController
    ) async throws -> VerificationOutcome

    func cancel() async
}

public enum VerificationOutcome: Sendable {
    case approved(VerificationReceipt)
    case rejected(VerificationReceipt)
    case pending(VerificationReference)
    case cancelled
}
```

VerificationSession contains opaque identifiers, scoped token, backend expiry and required capture profile. VerificationReceipt contains minimal provider-issued references and decision information; neither type exposes document images. Tokens must not appear in descriptions or logs. Treat these as sensitive objects even though the host necessarily possesses them.

Use async/await as the canonical completion mechanism. Expose an optional AsyncStream of coalesced public progress snapshots; finish it on terminal states. Do not offer a second competing completion callback API in v0.1.

Provider adapter responsibilities: acknowledge consent, upload evidence by side, commit a submission with an idempotency key, fetch status, and request remote cancellation. Evidence transfer accepts a constrained handle or scoped reader, not permanent public filesystem URLs. Each provider declares its supported document requirements.

Error information: stable category, recovery action, sanitized developer message, and optional opaque support reference. Example recovery actions are retry, recapture, open settings, restart session, or contact host support. Distinguish user cancellation from failure and provider rejection from transport error. A second run on an active client fails deterministically with sessionAlreadyActive.

Contract questions to resolve in week 1: provider-owned versus SDK-owned capture, maximum image size, accepted media format, token renewal policy, error normalization, and who can retrieve pending results. The first release chooses SDK-owned capture and no token renewal inside the SDK.

## 6. State and lifecycle rules

Main progression: initialized → consent → capture(front) → review(front) → capture(back) → review(back) → ready → upload → submit → awaitDecision → finish.

| Event | Required behavior |
| --- | --- |
| Retake | Delete superseded encrypted evidence and return to that side's capture |
| Network failure | Preserve confirmed evidence only within session lifetime; expose retry state |
| Duplicate submission | Reuse the logical submission's idempotency key; reconcile with backend |
| App becomes inactive | Immediately conceal sensitive previews and pause camera; background task budget is not assumed |
| App backgrounds during transfer | Cancel local foreground work; treat remote receipt as uncertain |
| Foreground return | Revalidate session and reconcile server status before retrying mutation |
| Permission revoked or camera interrupted | Release/reconfigure camera safely; retain valid review state if possible |
| Session expires | Stop new work, terminate session, delete local key/evidence, require a new session |
| User cancels or awaiting Task is cancelled | One terminal result, stop children, purge local data, best-effort remote cancellation |
| Terminal result races cancellation | First valid terminal transition wins under actor isolation; later results are ignored |
| Process killed | No promise of immediate cleanup; sweep orphaned SDK files/keys at next initialization |

Local cancellation cannot retract a request the server already accepted. Remote cancellation is best effort and is not a promise of backend data erasure. Backend retention/deletion remains an explicit separate contract.

Represent recoverable errors as state plus permitted actions; reserve terminal failure for conditions that require ending the flow. Inject clock, provider, storage and capture interfaces for deterministic transition tests. Use server expiry as authority and monotonic elapsed time for in-process deadlines; do not extend validity after wall-clock rollback.

## 7. Capture implementation

Use AVFoundation for capture and Vision rectangle detection for guidance. Analyze downsampled frames at a capped rate; capture one higher-quality still on explicit shutter. Frame scoring is local guidance, not document verification.

Start with rectangle presence, frame coverage, and stability. Add a simple blur score after measuring a synthetic fixture set on actual hardware. Explain uncertainty in UI and permit manual capture/retake when guidance is imperfect. Only truly unusable outputs such as a failed decode or invalid dimensions must hard-fail locally.

Normalize orientation, confirm crop with the user, remove unnecessary EXIF/GPS metadata, and encode a bounded JPEG. Proposed output ceiling: 2,000 pixels on the longest edge and 3 MB per side, subject to provider acceptance. Never silently reduce quality until evidence becomes unreadable; request recapture when encoding limits cannot be met.

UIKit view controller owns camera presentation; SwiftUI uses a wrapper over the same capture implementation. Support VoiceOver instructions, meaningful focus, Dynamic Type in guidance/review screens, and status text that does not rely only on color. Reassess layout under maximum supported text sizes.

## 8. Security and retention design

Threat scope: accidental plaintext persistence, backup leakage, excessive logs, expired-session reuse, duplicated requests, and orphaned evidence. App-process compromise, a malicious host app, and complete device compromise exceed the SDK's protection boundary. The host and embedded SDK share an application trust boundary.

Generate a random AES-256 key per session and use CryptoKit AES-GCM with a fresh nonce for every encryption. Authenticate session ID, evidence ID, side, and format version as associated data. Store ciphertext only in a dedicated protected SDK directory excluded from backup. Use complete file protection and foreground-only decryption.

Store the session key in a uniquely namespaced Keychain item with WhenUnlockedThisDeviceOnly accessibility. Keep the scoped network token in memory only. Secure Enclave is not required for symmetric evidence storage; device-key signing is a separate future capability.

Delete the key first and then ciphertext on terminal cleanup. Deleting a key/ciphertext does not prove secure physical overwrite, nor does Swift provide a general guarantee of wiping every plaintext memory copy. Bound plaintext lifetime and concurrency; document these limits.

Default local evidence lifetime: the earlier of backend session expiry and a proposed 15-minute SDK ceiling. Enforce at access and foreground entry. Use a timer as best effort while executing, not as a guarantee while suspended. On next SDK initialization, remove all owned orphaned evidence and corresponding keys because cross-launch resume is out of scope. Never delete unrelated host Keychain items or files.

Use ordinary HTTPS and platform TLS validation; no permissive trust overrides. Certificate pinning is deferred until operational rotation and recovery requirements exist. Disable SDK-owned analytics by default. Diagnostics use an allowlist of event names and numeric timing fields, never images, OCR, tokens, arbitrary provider payloads, or free-form backend errors.

Conceal app-switcher snapshots with a neutral screen on inactivity. Do not claim screenshot prevention. Review privacy manifest contents against actual SDK behavior and required-reason APIs before packaging. A manifest does not certify legal compliance.

## 9. Demo backend and retry contract

Document a minimal HTTP contract, for example:

| Operation | Example route | Safety rule |
| --- | --- | --- |
| Session creation, called by host | POST /sessions | No service credential embedded in SDK |
| Consent acknowledgement | PUT /sessions/{id}/consent | Idempotent versioned record |
| Upload one side | PUT /sessions/{id}/evidence/{side} | Same logical evidence ID/digest deduplicates retries |
| Commit evidence | POST /sessions/{id}/submission | Reuse submission idempotency key |
| Fetch state | GET /sessions/{id} | Returns authoritative pending/decision/expiry |
| Request cancellation | POST /sessions/{id}/cancel | Best effort, idempotent |

Backend binds tokens to session, expiry and operations. It enforces evidence limits, expiry, idempotency and duplicate decisions independently of client code. Demo implementation provides contract evidence, not a production security reference.

Retry transient network errors, selected 5xx responses, and rate limits with capped exponential backoff, jitter and Retry-After support. Proposed limit: three automatic retries within the remaining session budget. Never automatically retry authentication failure, rejected evidence, or an expired session. Ambiguous commit timeout triggers status reconciliation before another commit.

Poll pending status with bounded backoff while foregrounded, then hand off a pending result after a proposed 30-second UI waiting budget. Never keep the UI blocked indefinitely. Backend decision polling by the host is a separate operation after handoff.

Keep both a scripted in-process provider for reproducible tests and a small HTTP demo server to exercise serialization and actual network failures. Include approved, rejected, pending, expired, timeout, malformed-response and duplicate-request scenarios. Every simulated decision must be visibly labeled.

## 10. Delivery milestones

Effort includes implementation, tests and documentation; reserve remaining capacity for device-specific problems.

| Milestone | Indicative window | Output | Exit gate |
| --- | --- | --- | --- |
| M0: contract and threat model | Week 1; 12–16 h | API sketch, ADRs, threat boundaries, HTTP contract, package skeleton | Scope and trust ownership are unambiguous; sample host compiles |
| M1: workflow vertical slice | Weeks 2–3; 28–36 h | Actor-driven states, mock provider, placeholder capture, sample flow | Approved/rejected/pending/cancelled paths plus cancellation race tests pass |
| M2: secure evidence lifecycle | Week 4; 20–28 h | Encryption vault, expiry, owned-item cleanup | Tampering rejected; no plaintext file outputs; crash-orphan sweep verified |
| M3: physical camera capture | Weeks 5–6; 32–40 h | Front/back capture, review, retake, guidance, SwiftUI wrapper | Repeated camera lifecycle and permission tests pass on physical iPhone |
| M4: HTTP provider and recovery | Weeks 7–8; 28–36 h | Demo service, upload, idempotency, polling, retry/reconcile | Accepted-request/lost-response scenario produces one server submission |
| M5: hardening | Weeks 9–10; 28–36 h | Device measurements, accessibility, lifecycle matrix | Security/lifecycle gates pass and performance budget deviations are resolved |
| M6: release evidence | Weeks 11–12; 20–24 h | Tagged v0.1, API docs, guides, demo recording, report | Clean independent sample integration succeeds |

Total planned work: 168–216 hours plus roughly 12–24 hours contingency. If capacity tightens, defer blur scoring and visual theming first. Preserve cleanup, cancellation correctness, idempotency, and an independently runnable sample.

## 11. Test strategy and measurable release gates

Use focused unit tests for state transitions, recovery rules, expiry, retry budget and error mapping. Use real Keychain/file integration tests on supported environments for vault behavior. Use provider contract tests and a fault-injecting demo backend for transport ambiguity. Use physical-device testing for camera, interruptions, thermal behavior and actual memory.

Mandatory scenarios:

- Starting twice fails cleanly without launching another camera session.
- Cancelling at each async boundary returns once and tears down owned tasks/resources.
- Delayed provider completion after cancellation cannot revive the session.
- Lost response after accepted upload/commit does not create duplicate server evidence/submissions.
- Retake, success, rejection, pending handoff, cancellation and expiry remove owned local evidence and keys.
- Locked-device storage failure has a typed recovery path, not an unhandled crash.
- Modified ciphertext, wrong associated data and missing keys fail closed.
- Kill/relaunch removes owned stale files/keys without touching host items.
- Background/foreground and camera interruption preserve a valid, documented state.
- Host Task cancellation and user cancellation converge on the same teardown contract.
- Logs, network errors and sample fixtures contain no real PII or secrets.
- Clean Swift Package integration compiles and runs in both UIKit and SwiftUI samples.

Provisional performance budgets, to calibrate in M3 and publish with exact device/OS/build conditions:

| Measure | Initial target | Measurement |
| --- | --- | --- |
| Capture analysis concurrency | At most one in-flight frame | Instrumented capture pipeline |
| Camera readiness after permission granted | p95 ≤ 1.5 s across 30 starts | Signposts on baseline physical iPhone |
| Incremental peak SDK memory | ≤ 100 MB above idle host baseline | Release build, Instruments, defined two-image flow |
| Lifecycle resource stability | No retained SDK session/camera objects after 30 completed/cancelled runs | Memory graph and allocation inspection |
| Camera main-thread behavior | No blocking camera setup/start on MainActor | Time Profiler and thread checks |
| Output size | ≤ 3 MB per side | Encoded synthetic fixture corpus |
| Core dependency footprint | No third-party runtime dependencies | Package dependency inspection |

Targets are not measured achievements. Record any justified adjustment and evidence before release. Cover the minimum supported iOS with suitable hardware if available and a current stable iOS device. Simulator tests do not establish camera support; disclose unavailable coverage precisely.

## 12. Repository and release deliverables

Repository contains Package.swift, Sources per module, Tests, two sample host apps, DemoService, synthetic Fixtures, and Docs. CI builds and runs meaningful tests using a pinned Xcode version available on the runner, checks strict concurrency, and performs a clean package-consumer build. Do not claim device validation from CI simulator jobs.

Required docs: README quick start, integration guide, API reference via DocC, architecture and ADRs, SECURITY/threat model, data-lifecycle table, provider integration contract, troubleshooting, performance report with raw conditions, compatibility matrix, changelog, and release checklist.

ADRs should cover actor ownership, source-first SPM distribution, foreground-only uploads, no cross-launch resume, per-session encryption, provider/host trust boundaries and scope exclusions. Maintain a small Kotlin-oriented contract note mapping results/errors and async cancellation semantics; defer Android code.

Release assets: tagged v0.1 package, runnable samples, synthetic scenarios, 2–3 minute demo showing success and interruption, and a concise case study describing tradeoffs and measured behavior. Select a standard open-source license before public release and verify fixture/dependency licenses. Public release/deployment is a future execution step, not performed by this plan.

## 13. Risk register

| Risk | Mitigation or stop condition |
| --- | --- |
| SDK grows into a full identity platform | Freeze one document profile and externalize the verification decision |
| Mock feels like an app demo | Separate package consumers, real HTTP contract, fault scenarios and measured lifecycle evidence |
| No real provider access | Ship honest simulation; assess adapter feasibility from permitted documentation later |
| Capture heuristics reject good images | Treat heuristics as guidance, calibrate with fixtures/devices, keep manual review |
| Encryption complicates foreground recovery | Bound evidence size, isolate vault, test lock/background races; do not add background uploads |
| SDK assumes control of host navigation or data | Present from explicit host context; document ownership and cleanup boundaries |
| Performance budget unsupported by available hardware | Publish actual conditions/coverage, adjust scope from measured evidence |
| Portfolio implies regulated verification capability | Label simulation and explicitly state unimplemented authenticity/JPKI capabilities |

## 14. First implementation backlog

1. Pin toolchain and compatibility targets; create package and independent UIKit sample.
2. Write four short ADRs: scope, trust boundary, state ownership, retention/resume policy.
3. Define session, outcome, error, progress and provider contracts; prove the host-facing call compiles.
4. Write the transition table and cancellation/late-callback tests before connecting camera code.
5. Implement the scripted provider and complete a placeholder-evidence end-to-end flow.
6. Add vault integration and expiry/cleanup tests before introducing physical captures.
7. Connect camera only after the core flow and vault gates pass.

## 15. Technical references

The implementation choices above are proposed design decisions. Apple references establish the underlying platform capabilities; re-check availability and distribution requirements when implementing and releasing.

- [Apple: AVCaptureSession](https://developer.apple.com/documentation/avfoundation/avcapturesession)
- [Apple: Vision rectangle detection](https://developer.apple.com/documentation/vision/vndetectrectanglesrequest)
- [Apple: CryptoKit AES-GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm)
- [Apple: Keychain WhenUnlockedThisDeviceOnly accessibility](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly)
- [Apple: Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Apple: Distribute binary frameworks as Swift packages](https://developer.apple.com/videos/play/wwdc2020/10147/)

Job-alignment source: user-supplied PSR-8273 – iOS Developer(1).docx, read in this conversation. Its J-LIS/Digital Agency requirement remains a documented future specialization gap in v0.1.
