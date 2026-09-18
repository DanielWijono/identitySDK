# ``IdentityFlowSecurity``

Encrypted, short-lived on-device storage for confirmed evidence.

## Overview

Evidence exists on disk only between confirmation and transfer, and only in encrypted form.

``EvidenceVault`` encrypts each side with AES-GCM under a per-session key held in the Keychain as
`WhenUnlockedThisDeviceOnly`. Files get complete file protection and the owning directory is
excluded from backup. Associated data binds the ciphertext to its format version, media type,
session, evidence identifier and side, so a tampered or swapped file fails authentication instead of
decoding into the wrong slot.

Every read requires foreground access, a live handle, the current evidence identifier and a valid
key, and the foreground gate is rechecked *after* decryption.

Deletion order matters: the key is removed before the ciphertext, so an interruption can never leave
a readable pair. Only a confirmed file-not-found counts as already deleted — permission and
protection errors stay visible and keep the retry bookkeeping, which is what surfaces as
`VerificationError.cleanupRequired`. A fresh vault sweeps orphaned owned files on first use while
leaving unrelated host items alone.

> Note: Plaintext still exists briefly during capture, encryption and inside any provider that
> receives `Data`. No secure physical overwrite or universal memory wiping is claimed.

## Topics

### Storing evidence

- ``EvidenceVault``
- ``VaultSession``
- ``VaultError``

### Bridging capture to the workflow

- ``VaultEvidenceSource``

### Lifecycle gating

- ``VaultForegroundPermit``
