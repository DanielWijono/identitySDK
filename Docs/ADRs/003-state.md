# ADR 003: Actor owns terminal transitions

Accepted. One client has one active generation. Reserve terminal completion before asynchronous cleanup. Hold the active slot through cleanup, then resume exactly one continuation. Cancelled provider work may return late, so task cancellation alone is insufficient: validate generation before every subsequent operation. Remote cancellation does not gate local completion. Injected evidence cleanup must revoke readers and stop capture, including work already in flight.
