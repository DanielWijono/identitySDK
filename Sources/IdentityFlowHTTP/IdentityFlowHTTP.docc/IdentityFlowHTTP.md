# ``IdentityFlowHTTP``

A provider adapter that survives lost responses.

## Overview

``HTTPVerificationProvider`` implements the demo HTTP contract. The interesting part is not the
routes but what it refuses to do twice.

Every transport failure is treated as **ambiguous**, because the server may already have applied the
mutation before the reply was lost. Rather than repeating a write and hoping the server deduplicates
it, the adapter reads authoritative state and asks whether its own change landed — matching its
evidence identifier for an upload, and its idempotency key for a commit. When the change is already
present, no second request is sent at all.

The submission key comes from the run itself and is stable across retries, so a duplicate that does
reach the server is still absorbed. These two defences are independent, and both are covered by
tests that fail when either is disabled.

Retries are bounded and selective. Only 429, 500, 502, 503, 504 and transport failures qualify;
authentication failures, conflicts and expired sessions are decisions the server already made.
Backoff is exponential with full jitter, `Retry-After` is honoured in delta-seconds form and capped
so a hostile value cannot park a run until the session dies, and every attempt is checked against the
remaining session budget.

Decision observation is bounded too: after the budget elapses the run hands off as
`VerificationOutcome.pending` rather than blocking the UI indefinitely.

Server error bodies contribute only a stable code. Free-form text is discarded, so server-side
messages cannot carry personal data into host error handling.

## Topics

### Talking to a backend

- ``HTTPVerificationProvider``
- ``RetryPolicy``
- ``ProviderClock``
- ``SystemProviderClock``

### Transport

- ``HTTPTransport``
- ``URLSessionTransport``
- ``HTTPRequest``
- ``HTTPResponse``
- ``HTTPTransportError``

### Wire format

- ``SessionState``
- ``SessionStateBody``
- ``ConsentBody``
- ``SubmissionBody``
- ``SubmissionAccepted``
- ``ErrorBody``
- ``Wire``
