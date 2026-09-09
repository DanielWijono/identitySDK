# Security boundary

This foundation is not a production verification product. The iOS samples process generated synthetic JPEGs through encrypted local storage; the command-line demo uses synthetic in-memory bytes. Do not supply real identity documents until the planned vault and lifecycle gates pass.

Host and SDK share an application process. Redacted descriptions cannot stop a malicious host or provider from reading tokens or evidence. Swift does not guarantee plaintext memory wiping. No analytics, logs of payloads, or credential persistence are implemented.

The intended threat model covers accidental plaintext persistence, backup/log leakage, expired reuse, duplicate requests and orphaned evidence. Full process/device compromise is outside scope. Backend retention and deletion are separate from local cancellation.

The optional IdentityFlowSecurity module implements AES-GCM storage, Keychain keys, owned startup sweeping and explicit foreground/expiry access guards. It is connected to the iOS sample flow through VaultEvidenceSource, with explicit cleanup failure/retry and synchronous inactivity gating. Physical-iPhone locked-device validation and HTTP token enforcement remain pending. See Docs/Evidence-Vault.md for the cleanup error contract. Test success for the core does not establish those properties.
