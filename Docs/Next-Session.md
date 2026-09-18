# Handoff

## Current state

M0–M2 are implemented, M3 is code-complete with only physical gates remaining, and M4's transport-recovery half is implemented and covered.

`DocumentCaptureCoordinator` (IdentityFlowUI) owns front/back capture orchestration; the sample consumes it rather than its own adapter. `HTTPVerificationProvider` (IdentityFlowHTTP) implements the demo HTTP contract, and `DemoVerificationService` (IdentityFlowDemoService) models the server in process so tests can count logical mutations rather than client calls.

Package suite: 54 tests. UIKitSample on iPhone 16 Pro Simulator, iOS 18.3.1: 19 component tests with 3 skipped, plus 5 `SimulationUITests`. See Validation.md for artifacts.

The duplicate-submission gate was verified by mutation, not by a green test alone: disabling client reconciliation fails the lost-response tests, and disabling server idempotency fails the replayed-key test. Keep both defences.

## Next steps, in order

1. **Real HTTP demo server.** The current demo service is in-process and shares the `Wire` codec with the adapter, so nothing yet proves wire compatibility or exercises `URLSessionTransport`. A small local server would cover serialization, TLS and genuine network faults. This is the remaining half of M4's stated deliverable.
2. **Foreground/background reconciliation adapter.** Backgrounding must cancel foreground transfer and force authoritative reconciliation before another mutation. Not started.
3. **Physical M3 gates.** All need hardware, and at last check every paired iPhone reported `unavailable` to `devicectl`:
   - `CameraComponentTests/testRepeatedHardwareLifecycleAndDuplicateStart` — 30 real start/stop cycles, duplicate-start rejection, provisional 1.5 s p95 readiness.
   - Camera permission revocation and return-to-app recheck.
   - Instrumented lock-state denial during crop editing, interruption stress, still/preview orientation comparison, minimum-iOS-16 hardware, hands-on VoiceOver, performance measurements.

## Cautions

Earlier physical results are user-reported UI observations, not instrumented security evidence. Use printed test cards only. Keep normal simulator signing for sample runs; `CODE_SIGNING_ALLOWED=NO` breaks vault storage initialization. Preserve local Xcode development-team edits.
