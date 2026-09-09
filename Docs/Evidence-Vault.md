# Secure evidence vault foundation

`IdentityFlowSecurity` is an optional Swift Package product depending only on core and Apple frameworks. The sample apps still use the in-memory synthetic source. This module is not yet connected to capture or an `EvidenceSource` lifecycle adapter.

## Contract

Use `EvidenceVault.shared` in one host process. Await `enterForeground()` before beginning work and await `leaveForeground()` when the host becomes inactive, before allowing further SDK operations. The first foreground entry removes old keys and files from the SDK's dedicated namespace because cross-launch resume is unsupported. Re-entering foreground does not sweep current live sessions; it revalidates expiry.

`begin(sessionID:expiresAt:)` generates a fresh 256-bit AES key and returns an opaque `VaultSession`. `store(_:side:in:)` accepts already-normalized JPEG data up to 3,000,000 bytes and returns a core `Evidence` with a revocable reader. This storage layer checks byte limits but does not validate JPEG encoding, image dimensions, orientation or metadata. The future capture normalizer owns those checks.

Replacing one side revokes the old reader and deletes the old ciphertext before saving the new value. Encryption uses a new CryptoKit-generated nonce for each write. Associated data authenticates format version, media type, length-delimited server session ID, evidence UUID and side. Files have opaque UUID names, never server IDs or tokens.

Keys use a dedicated Keychain service and WhenUnlockedThisDeviceOnly. On iOS, ciphertext uses complete file protection; the dedicated directory is excluded from backup. No plaintext or token is written to files. On macOS, tests prove encryption/Keychain behavior, not iOS lock-state guarantees.

Readers require foreground access, a live handle, the current evidence ID and a valid session key. Both wall-clock backend expiry and a fixed monotonic deadline are checked; the local ceiling is 15 minutes. Access after expiry attempts cleanup before returning an error. This vault does not independently schedule a timer; the future adapter must connect the core timer and all terminal paths to cleanup.

`cleanup(_:)` revokes readers immediately, then deletes the key before files. It is idempotent after success. If deletion fails, it throws a typed error and retains bookkeeping for a retry; it does not report successful deletion. Startup sweeping handles crash-orphaned data. The host integration must not swallow cleanup failures in the existing nonthrowing `EvidenceSource.cleanup()` interface: error propagation/retry ownership must be resolved before integration.

## Remaining M2 gates

- Integrate lifecycle events, terminal cleanup and expiry scheduling through a capture/evidence adapter.
- Real iOS Keychain and protected-file tests while locked/backgrounded; simulator/macOS tests do not establish physical-device protection.
- Test filesystem deletion failures and crash points under fault injection, including retake and writes.
- Review multi-process/app-extension ownership; the shared vault is designed for a single host process.
- Image normalization and decode/size validation before actual document capture.

No secure physical overwrite or universal Swift memory wiping is claimed. Plaintext necessarily exists briefly when sealing/opening and in the caller/provider that holds returned Data.

Apple API references: [AES-GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm), [WhenUnlockedThisDeviceOnly](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly), [complete file protection](https://developer.apple.com/documentation/foundation/fileprotectiontype/complete).
