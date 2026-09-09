# Proposed demo HTTP contract

Design only; neither server nor HTTP adapter is implemented. All decisions must carry a simulation label in the demo UI. Use HTTPS with default platform trust validation outside local development. Never embed service credentials in an SDK or sample.

Every SDK request carries the scoped bearer token. The server binds it to one session, expiry and permitted operations. JSON errors expose only a stable code and optional opaque support reference; adapters must discard free-form server messages.

| Method and route | Request | Response and invariants |
| --- | --- | --- |
| POST /sessions (host only) | Requested card profile, scenario | 201: opaque session ID, scoped token, expiry, accepted media limits |
| PUT /sessions/{id}/consent | Disclosure version | 204; repeated same version is idempotent; conflicting version requires explicit policy |
| PUT /sessions/{id}/evidence/{side} | Bounded JPEG body, evidence ID and SHA-256 digest headers | 204; identical evidence ID/digest deduplicates; same ID with different bytes returns 409 |
| POST /sessions/{id}/submission | Front/back evidence IDs; Idempotency-Key header | 202: reference and pending state; identical key/payload returns original submission; conflicting payload returns 409 |
| GET /sessions/{id} | No body | 200: authoritative state, expiry, reference, received evidence IDs, submission key if accepted |
| POST /sessions/{id}/cancel | No body | 204; idempotent, best effort, no backend-erasure guarantee |

Server validates consent before evidence submission, both required sides, expiry, supported JPEG format, at most 2,000 pixels on the longest edge and 3 MB per side. These limits remain proposed until implemented and tested. No approval is inferred from HTTP success.

401/403 and expired sessions do not retry automatically. Retry selected transient network failures, 429 and selected 5xx at most three times within the session deadline, honoring bounded Retry-After and exponential backoff with jitter. A lost commit response requires GET reconciliation before any repeated commit. Keep the same logical evidence IDs and submission key across retries. The current core does not implement these retries.

After the proposed 30-second foreground observation budget, hand off pending with the provider reference. The host retrieves subsequent state using its backend; the SDK does not persist the token for later retrieval. Backgrounding cancels foreground transfer and requires authoritative reconciliation before another mutation; this lifecycle adapter remains pending.

Contract tests must include accepted upload/commit with lost response, duplicate keys, conflicting payload, expired token, malformed JSON, rate limit, delayed decision and cancellation races. Assert one logical server submission, not merely one client request.
