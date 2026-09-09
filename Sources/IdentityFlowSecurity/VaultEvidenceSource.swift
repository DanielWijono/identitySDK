import Foundation
import IdentityFlowCore
import os

/// Capture must return only a user-confirmed, normalized JPEG. Do not persist plaintext.
public protocol ConfirmedImageCapture: Sendable {
    func confirmedJPEG(for side: DocumentSide) async throws -> Data
    /// Stop owned capture work. The vault adapter independently rejects late results.
    func cancel() async
}

/// One instance per accepted flow. Allocates storage lazily, so rejected starts own no files/keys.
public actor VaultEvidenceSource: EvidenceSource {
    private let vault: EvidenceVault
    private let capture: any ConfirmedImageCapture
    private let sessionID: String
    private let expiresAt: Date
    private var sessionTask: Task<VaultSession, any Error>?
    private var closed = false
    private let lifetime = EvidenceLifetime()

    public init(sessionID: String, expiresAt: Date, capture: any ConfirmedImageCapture,
                vault: EvidenceVault = .shared) {
        self.sessionID = sessionID; self.expiresAt = expiresAt
        self.capture = capture; self.vault = vault
    }

    public func confirmedEvidence(for side: DocumentSide) async throws -> Evidence {
        try checkOpen()
        if sessionTask == nil {
            let vault = vault, sessionID = sessionID, expiresAt = expiresAt
            sessionTask = Task { try await vault.begin(sessionID: sessionID, expiresAt: expiresAt) }
        }
        let session = try await sessionTask!.value
        try checkOpen()
        let jpeg = try await capture.confirmedJPEG(for: side)
        try checkOpen()
        let evidence = try await vault.store(jpeg, side: side, in: session)
        try checkOpen()
        return Evidence(id: evidence.id, side: side,
                        reader: ScopedReader(reader: evidence.reader, lifetime: lifetime))
    }

    public func cleanup() async throws {
        if !closed {
            closed = true // No late capture result can enqueue a new write after this point.
            lifetime.revoke()
            let capture = capture
            Task { await capture.cancel() } // Uncooperative capture cannot delay key/file revocation.
        }
        guard let sessionTask else { return }
        // A concurrent begin must finish before deletion; never abandon a newly created key.
        let session: VaultSession
        do { session = try await sessionTask.value }
        catch { return } // begin is transactional: failure returns no owned session.
        try await vault.cleanup(session)
    }

    private func checkOpen() throws {
        guard !closed else { throw VaultError.revoked }
        try Task.checkCancellation()
    }
}

private final class EvidenceLifetime: Sendable {
    private let revoked = OSAllocatedUnfairLock(initialState: false)
    func revoke() { revoked.withLock { $0 = true } }
    func validate() throws {
        if revoked.withLock({ $0 }) { throw VaultError.revoked }
    }
}

private struct ScopedReader: EvidenceReader {
    let reader: any EvidenceReader
    let lifetime: EvidenceLifetime
    func read() async throws -> Data {
        try lifetime.validate()
        let data = try await reader.read()
        try lifetime.validate()
        return data
    }
}
