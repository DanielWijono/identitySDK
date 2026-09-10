# Encrypted evidence and flow cleanup

`IdentityFlowSecurity` is an optional Swift Package product depending on core and Apple frameworks. Both iOS samples use ImageNormalizer followed by `VaultEvidenceSource` with generated, synthetic JPEGs. The command-line demo remains an explicit in-memory simulation. No real camera or network provider is connected.

## Host integration

The host owns lifecycle notifications. Use `EvidenceVault.shared` once per process. Capture a `foregroundPermit()` synchronously when the app becomes active and protected data is available, then await `enterForeground(permit)`. On inactivity or protected-data unavailability, call the synchronous `leaveForeground()` immediately, conceal previews, and cancel the running flow. Do not put that call inside a new Task: its purpose is to close access before returning from the notification.

A permit issued before inactivity cannot reopen the gate afterward. Use a fresh permit on the next activation. Foreground entry sweeps orphaned data only on first initialization, then revalidates expired/revoked sessions on subsequent entries. The samples cancel on every inactivity event, including transient interruptions; they do not resume a prior transfer. Production status reconciliation remains separate work.

Create a fresh `VaultEvidenceSource(sessionID:expiresAt:capture:vault:)` for the session passed to the client. `ConfirmedImageCapture` must return only user-confirmed, normalized JPEG bytes and implement cancellation. The adapter creates its vault session lazily after the client accepts the run. A rejected start therefore allocates no key or evidence. It does not keep the network token.

The adapter seals confirmed bytes, returns scoped readers to the provider, and rejects late capture completions after cleanup. Cleanup revokes readers synchronously before suspension, schedules capture cancellation, awaits any in-flight vault-session creation, and deletes the session. An uncooperative capture cannot delay key deletion; its eventual result cannot create new evidence.

## Terminal cleanup and retry

`EvidenceSource.cleanup()` is now `async throws`. Existing nonthrowing implementations can still conform; calls through the protocol must use `try await`. Implementations must revoke access before awaiting I/O and retain enough state to retry deletion.

On any terminal result—including approval, rejection, pending, user/task cancellation, technical failure and core-timer expiry—the client attempts cleanup in a task independent of the cancelled worker. On success it delivers the reserved result. On cleanup failure:

- `run` throws the sanitized `VerificationError.cleanupRequired` and finishes its progress stream.
- `requiresCleanup` is true; new runs are rejected with `cleanupRequired`.
- The client retains the evidence source and original result. The host must retain this client until recovery completes.
- `retryCleanup()` retries only deletion. It never repeats provider mutations. After successful deletion, it returns the original outcome or throws the original technical error. Check `requiresCleanup` to distinguish a recovered original failure from another cleanup failure.
- Concurrent retry attempts receive `cleanupInProgress`; a call without pending cleanup receives `noCleanupPending`.

The sample presents **Retry cleanup** without claiming evidence was cleared. It retains the affected client and keeps Start disabled until successful recovery. If the process is killed, the next first vault activation sweeps the namespace; cross-launch result/credential recovery is not supported.

## Storage contract

`begin(sessionID:expiresAt:)` generates a fresh AES-256 key and returns an opaque `VaultSession`. `store(_:side:in:)` accepts normalized JPEG data up to 3,000,000 bytes. It checks byte limits, not JPEG encoding, dimensions, orientation or metadata: ImageNormalizer handles decoding, dimensions, orientation and metadata before this layer.

Replacement revokes the old reader and deletes the superseded ciphertext before saving new data. CryptoKit chooses a fresh nonce for each encryption. Associated data authenticates format version, media type, length-delimited server session ID, evidence UUID and side. Files have UUID names and contain only sealed bytes.

Keys use the SDK's dedicated Keychain service and WhenUnlockedThisDeviceOnly. iOS files use complete file protection and the directory is excluded from backup. Keys are deleted before files. Only a confirmed file-not-found error is treated as already deleted; permission/protection/deletion errors stay visible and retain retry bookkeeping.

Every read requires active foreground access, a live handle, the current evidence ID and a valid key. Expiry checks backend wall time and a fixed monotonic deadline capped at 15 minutes. The integrated core timer invokes source cleanup even while a provider is held. The synchronous foreground gate is checked again after decryption. Data already delivered to a provider remains that provider's responsibility.

## Remaining device gates

- Run the [physical-device checklist](Device-Validation.md). Paired iPhones were unavailable during implementation; no physical lock/unlock result is claimed.
- Test process termination at write/retake/crash boundaries. Fault-injected terminal file deletion and key deletion failures are covered; this is not exhaustive crash testing.
- Review app-extension/multi-process ownership before using the shared namespace outside a single host process.
- ImageNormalizer is now available and exercised by the synthetic samples; capture/review and permission handling remain before using real documents.

No secure physical overwrite or universal Swift memory wiping is claimed. Plaintext exists briefly in capture, encryption/decryption and providers that receive Data. Uncooperative external work may retain its own copies after cancellation.

Apple references: [AES-GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm), [WhenUnlockedThisDeviceOnly](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly), [protected-data notification](https://developer.apple.com/documentation/uikit/uiapplication/protecteddatawillbecomeunavailablenotification), [inactivity notification](https://developer.apple.com/documentation/uikit/uiapplication/willresignactivenotification).
