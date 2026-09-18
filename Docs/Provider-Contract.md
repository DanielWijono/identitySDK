# Demo HTTP contract

Implemented by `HTTPVerificationProvider` (IdentityFlowHTTP) and `DemoVerificationService` (IdentityFlowDemoService). The service is an in-process model of this contract, not a socket server: it exists so contract tests can assert how many *logical* server mutations a run produced. A real HTTP server for serialization and live network faults is still outstanding, and both sides currently share the `Wire` codec, so these tests do not establish wire compatibility. All decisions must carry a simulation label in the demo UI. Use HTTPS with default platform trust validation outside local development. Never embed service credentials in an SDK or sample.

Every SDK request carries the scoped bearer token. The server binds it to one session, expiry and permitted operations. JSON errors expose only a stable code and optional opaque support reference; adapters must discard free-form server messages.

| Method and route | Request | Response and invariants |
| --- | --- | --- |
| POST /sessions (host only) | Requested card profile, scenario | 201: opaque session ID, scoped token, expiry, accepted media limits |
| PUT /sessions/{id}/consent | Disclosure version | 204; repeated same version is idempotent; conflicting version requires explicit policy |
| PUT /sessions/{id}/evidence/{side} | Bounded JPEG body, evidence ID and SHA-256 digest headers | 204; identical evidence ID/digest deduplicates; same ID with different bytes returns 409 |
| POST /sessions/{id}/submission | Front/back evidence IDs; Idempotency-Key header | 202: reference and pending state; identical key/payload returns original submission; conflicting payload returns 409 |
| GET /sessions/{id} | No body | 200: authoritative state, expiry, reference, received evidence IDs, submission key if accepted |
| POST /sessions/{id}/cancel | No body | 204; idempotent, best effort, no backend-erasure guarantee |

The service validates consent before evidence submission, both required sides, expiry, token binding, `image/jpeg` content type and 3 MB per side. Pixel dimensions are enforced earlier by ImageNormalizer, not by this layer. No approval is inferred from HTTP success.

401/403, 404, 409, 413, 415 and expired sessions are never retried: they are decisions the server already made. The adapter retries only 429, 500, 502, 503, 504 and transport failures, at most three times within the session deadline, using exponential backoff with full jitter. `Retry-After` is honoured in delta-seconds form only and capped, so a hostile value cannot park a run until the session dies; an HTTP-date form is ignored rather than guessed at.

Every transport failure is treated as ambiguous, because the server may already have applied the mutation. Before repeating anything the adapter reads authoritative state and asks whether its own change landed — matching its evidence ID for an upload, and its idempotency key for a commit. When it did, no second request is sent. The same evidence IDs and submission key are reused across retries, so the server can absorb a duplicate that does arrive.

After the proposed 30-second foreground observation budget, hand off pending with the provider reference. The host retrieves subsequent state using its backend; the SDK does not persist the token for later retrieval. Backgrounding cancels foreground transfer and requires authoritative reconciliation before another mutation; this lifecycle adapter remains pending.

Contract tests cover accepted upload/commit with lost response, replayed and conflicting idempotency keys, expired sessions, rejected credentials, malformed JSON, rate limiting, capped Retry-After, exhausted retries, evidence limits, delayed decision with pending handoff, and cancellation while awaiting a decision. They assert counts taken from the service's own state, not from client call counts.

Two independent defences keep a lost response from creating a duplicate, and each is covered separately: client-side reconciliation, and the server's idempotency key. Disabling either in isolation fails a different test, and disabling reconciliation alone still yields one logical submission because the key absorbs the repeat.
