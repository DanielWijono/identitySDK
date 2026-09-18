# Getting started

Run one verification from a host app.

## Obtain a session

Your backend authenticates the user and issues a short-lived, narrowly scoped token. The SDK never
holds a service credential and never creates sessions itself.

```swift
let session = VerificationSession(id: id, token: token, expiresAt: expiry)
```

``VerificationSession`` redacts its token in `description` and `debugDescription`, so logging one
cannot leak the credential. The token remains readable by your provider code, which must never log
it.

## Collect consent explicitly

```swift
let consent = Consent(disclosureVersion: "disclosure-v2")
```

Construct this only after a real user action. It is acknowledged with your backend before any
evidence is transferred, because local acceptance alone is not a durable audit record.

## Run

```swift
let client = VerificationClient(provider: myProvider)
let (progress, continuation) = AsyncStream<VerificationProgress>
    .makeStream(bufferingPolicy: .bufferingNewest(1))

let outcome = try await client.run(
    session: session,
    consent: consent,
    evidence: myEvidenceSource,
    progress: continuation
)
```

Buffer only the newest progress value: it drives a status label, not an event log.

Each run needs a **fresh** evidence source. A rejected start takes no ownership of the source you
passed, so never pre-capture data before a run is accepted.

## Handle every outcome

```swift
switch outcome {
case .approved(let reference):  // provider approved — not an SDK judgement
case .rejected(let reference):  // provider rejected
case .pending(let reference):   // no decision yet; resolve later via your backend
case .cancelled:                // user or task cancellation; evidence already cleaned up
}
```

``VerificationOutcome/pending(_:)`` is a normal ending, not a failure. Verification may continue on
the server after your UI closes.

## Recover from cleanup failure

```swift
catch VerificationError.cleanupRequired {
    // Local evidence may still exist. Keep this client.
    let outcome = try await client.retryCleanup()
}
```

Keep the same client instance: it retains the original result and replays it once deletion succeeds,
without repeating any upload. Consult ``VerificationError/recoveryAction`` to decide what to offer
the user.

## Cancellation

``VerificationClient/cancel()`` and cancelling the awaiting task converge on the same teardown.
Both reserve a terminal result before cleanup suspends, so a provider reply that arrives afterwards
can never turn a cancelled run into an approval.
