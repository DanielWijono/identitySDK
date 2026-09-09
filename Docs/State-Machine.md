# Implemented workflow

| State | Successful next operation | Failure/termination |
| --- | --- | --- |
| Idle | Validate credentials, expiry and consent version | Reject without taking ownership |
| Consent | Provider acknowledgement | Cleanup and typed failure |
| Capture front | Confirm front evidence | Cleanup and typed evidence failure |
| Capture back | Confirm back evidence | Cleanup and typed evidence failure |
| Upload front | Transfer front | Cleanup and typed failure |
| Upload back | Transfer back | Cleanup and typed failure |
| Submit | Commit using per-run UUID | Cleanup and typed failure |
| Await decision | Approved, rejected or pending | Cleanup and typed failure |
| Finishing | Cancel owned tasks, revoke evidence, finish progress, resume caller | New runs remain rejected until cleanup ends |

Any active state accepts cancellation or expiry. The first actor-isolated terminal reservation wins. Every async operation is followed by a generation check before further work; stale completions are ignored. Success also rechecks expiry. Cleanup occurs once per accepted run. Remote cancellation is detached from the completion contract, but runs in an ordinary unstructured task.

This foundation terminates on provider failure. Recoverable retry states and lifecycle reconciliation from the release plan are not yet implemented. Providers must not return an identity decision based merely on successful upload.

Expiry uses a fixed monotonic deadline established at acceptance (backend remaining lifetime capped at 15 minutes). Each operation boundary checks both that deadline and current wall-clock expiry. A clock rollback cannot extend validity even when timer execution is delayed. The internal clock is injectable for deterministic tests.
