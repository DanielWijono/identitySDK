# Security boundary

This foundation is not a production verification product. It currently processes synthetic in-memory data only. Do not supply real identity documents until the planned vault and lifecycle gates pass.

Host and SDK share an application process. Redacted descriptions cannot stop a malicious host or provider from reading tokens or evidence. Swift does not guarantee plaintext memory wiping. No analytics, logs of payloads, or credential persistence are implemented.

The intended threat model covers accidental plaintext persistence, backup/log leakage, expired reuse, duplicate requests and orphaned evidence. Full process/device compromise is outside scope. Backend retention and deletion are separate from local cancellation.

Encrypted storage, lock-state recovery, orphan cleanup, HTTP token enforcement and foreground handling are still pending. Test success for the core does not establish those properties.
