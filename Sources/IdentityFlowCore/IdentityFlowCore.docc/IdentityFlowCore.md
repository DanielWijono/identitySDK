# ``IdentityFlowCore``

Coordinates an identity-document workflow: consent, capture, transfer, and an asynchronous decision.

## Overview

> Important: This SDK performs **no identity verification**. It does no OCR, MRZ parsing, face
> matching, liveness detection or authenticity checking. Your provider or backend makes every
> identity decision, and a successful upload is never an approval.

What this module does own is the part that is easy to get wrong: a single active run whose
cancellation, expiry and provider completion race each other, and which must never leave decrypted
evidence behind on any exit path.

``VerificationClient`` is an actor holding one run at a time. Every async boundary is followed by a
generation check, so a late completion from a superseded run is ignored rather than allowed to
revive it. The first terminal transition wins; everything after it is discarded.

Cleanup runs on every exit path, including cancellation and expiry, in a task that does not inherit
the cancelled worker's state. If cleanup fails — typically because the device locked and the
protected file cannot be deleted — the run ends with ``VerificationError/cleanupRequired`` rather
than silently reporting success while evidence remains. The client keeps the original result,
refuses new runs, and recovers through ``VerificationClient/retryCleanup()``.

### Where the boundaries are

The module deliberately knows nothing about cameras, encryption or HTTP. It talks to two protocols:

- ``EvidenceSource`` supplies confirmed evidence and owns its cleanup.
- ``VerificationProvider`` talks to your backend.

That is what lets capture be swapped for a synthetic source in tests, and the transport be swapped
for an in-process fake.

## Topics

### Getting started

- <doc:GettingStarted>

### Running a verification

- ``VerificationClient``
- ``VerificationSession``
- ``Consent``
- ``VerificationOutcome``
- ``VerificationReference``
- ``VerificationProgress``

### Handling failure

- ``VerificationError``
- ``RecoveryAction``

### Supplying evidence

- ``EvidenceSource``
- ``Evidence``
- ``EvidenceReader``
- ``ConfirmedImageCapture``
- ``DocumentSide``

### Connecting a backend

- ``VerificationProvider``
