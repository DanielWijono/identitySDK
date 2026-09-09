# ADR 004: No cross-launch resume

Accepted design; production storage implementation pending. Keep credentials in memory; cap accepted runs at backend expiry or 15 minutes. Terminal paths revoke evidence. Future vault uses per-session CryptoKit AES-GCM, a namespaced device-only Keychain key, complete file protection and backup exclusion. Delete key before ciphertext and sweep owned orphan data on initialization. Foreground reconciliation and real Keychain/file tests are mandatory before camera integration. Current demo writes no evidence files and does not claim cryptographic protection.
