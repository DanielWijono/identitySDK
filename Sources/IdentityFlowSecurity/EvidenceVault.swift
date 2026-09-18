import Foundation
import CryptoKit
import IdentityFlowCore

/// Why a vault operation failed.
///
/// These fail closed: a revoked reader, a missing key or tampered ciphertext produces an error
/// rather than degraded access.
public enum VaultError: Error, Sendable, Equatable {
    case inactive, expired, invalidEvidence, revoked, integrityFailure
    case protectedDataUnavailable, keyUnavailable, keychainFailure, fileFailure
}

/// Opaque local session ownership; not a network credential or a filesystem location.
public struct VaultSession: Sendable, Hashable {
    let id: UUID
}

/// Ciphertext-only temporary storage. Use the shared instance once per host process.
/// The host must report foreground transitions before granting access to real evidence.
public actor EvidenceVault {
    public static let shared = EvidenceVault(
        root: FileManager.default.temporaryDirectory.appendingPathComponent("com.identityflow.evidence.v1", isDirectory: true),
        keys: KeychainStore(service: "com.identityflow.evidence.v1")
    )
    private struct Session {
        let serverID: String
        let expiry: Date
        let deadline: ContinuousClock.Instant
        var evidence: [DocumentSide: UUID] = [:]
        var files: Set<UUID> = []
    }
    private let root: URL
    private let keys: any KeyStore
    private let wallNow: @Sendable () -> Date
    private let monotonicNow: @Sendable () -> ContinuousClock.Instant
    private let removeFile: @Sendable (URL) throws -> Void
    private var sessions: [UUID: Session] = [:]
    private var initialized = false
    private nonisolated let gate = ForegroundGate()

    init(root: URL, keys: any KeyStore,
         wallNow: @escaping @Sendable () -> Date = { Date() },
         monotonicNow: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now },
         removeFile: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) {
        self.root = root; self.keys = keys
        self.wallNow = wallNow; self.monotonicNow = monotonicNow
        self.removeFile = removeFile
    }

    /// First activation sweeps only this vault's dedicated namespace. Never sweeps live sessions.
    public nonisolated func foregroundPermit() -> VaultForegroundPermit { gate.permit() }

    public func enterForeground(_ permit: VaultForegroundPermit) throws {
        guard gate.accepts(permit) else { throw VaultError.inactive }
        if !initialized {
            try keys.deleteAll() // Key first, including keys orphaned before file creation.
            do {
                if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                var directory = root
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try directory.setResourceValues(values)
                #if os(iOS)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: root.path)
                #endif
            } catch { throw VaultError.fileFailure }
            initialized = true
        }
        for id in Array(sessions.keys) where revoked.contains(id) || isExpired(sessions[id]!) { try cleanup(VaultSession(id: id)) }
        try gate.activate(permit)
    }

    public nonisolated func leaveForeground() { gate.suspend() }

    public func begin(sessionID: String, expiresAt: Date) throws -> VaultSession {
        guard initialized, gate.isActive else { throw VaultError.inactive }
        let lifetime = min(expiresAt.timeIntervalSince(wallNow()), 900)
        guard lifetime > 0 else { throw VaultError.expired }
        guard !sessionID.isEmpty else { throw VaultError.invalidEvidence }
        let id = UUID()
        let key = SymmetricKey(size: .bits256)
        try keys.save(key.withUnsafeBytes { Data($0) }, account: id.uuidString)
        sessions[id] = Session(serverID: sessionID, expiry: expiresAt,
                               deadline: monotonicNow().advanced(by: .seconds(lifetime)))
        return VaultSession(id: id)
    }

    /// Accepts already-normalized JPEG bytes (up to 3 MB); it does not decode or normalize images.
    /// Replacing a side revokes its previous reader before writing the replacement.
    public func store(_ jpeg: Data, side: DocumentSide, in handle: VaultSession) throws -> Evidence {
        var session = try validate(handle)
        guard !jpeg.isEmpty, jpeg.count <= 3_000_000 else { throw VaultError.invalidEvidence }
        if let old = session.evidence.removeValue(forKey: side) {
            sessions[handle.id] = session
            try deleteCiphertext(old)
            session.files.remove(old)
            sessions[handle.id] = session
        }
        let id = UUID()
        let key = SymmetricKey(data: try keys.load(account: handle.id.uuidString))
        let encrypted: Data
        do {
            let box = try AES.GCM.seal(jpeg, using: key, authenticating: aad(session: session, id: id, side: side))
            guard let combined = box.combined else { throw VaultError.integrityFailure }
            encrypted = combined
        } catch { throw VaultError.integrityFailure }
        do {
            #if os(iOS)
            try encrypted.write(to: file(id), options: [.atomic, .completeFileProtection])
            #else
            try encrypted.write(to: file(id), options: .atomic)
            #endif
        } catch { throw VaultError.fileFailure }
        session.evidence[side] = id
        session.files.insert(id)
        sessions[handle.id] = session
        return Evidence(id: id, side: side, reader: Reader(vault: self, session: handle, id: id, side: side))
    }

    /// Revokes access immediately; errors remain visible and cleanup can be retried.
    public func cleanup(_ handle: VaultSession) throws {
        // Keep a revoked record until all deletion succeeds, allowing retries.
        guard let session = sessions[handle.id] else { return }
        revoked.insert(handle.id)
        try keys.delete(account: handle.id.uuidString)
        for id in session.files { try deleteCiphertext(id) }
        sessions.removeValue(forKey: handle.id)
        revoked.remove(handle.id)
    }
    private var revoked: Set<UUID> = []
    private func isExpired(_ session: Session) -> Bool {
        wallNow() >= session.expiry || monotonicNow() >= session.deadline
    }
    private func validate(_ handle: VaultSession) throws -> Session {
        guard !revoked.contains(handle.id), let session = sessions[handle.id] else { throw VaultError.revoked }
        if isExpired(session) {
            try cleanup(handle)
            throw VaultError.expired
        }
        guard gate.isActive else { throw VaultError.inactive }
        return session
    }
    private func read(_ handle: VaultSession, id: UUID, side: DocumentSide) throws -> Data {
        let session = try validate(handle)
        guard session.evidence[side] == id else { throw VaultError.revoked }
        let key = SymmetricKey(data: try keys.load(account: handle.id.uuidString))
        let data: Data
        do { data = try Data(contentsOf: file(id)) } catch { throw VaultError.fileFailure }
        guard data.count <= 3_000_028 else { throw VaultError.invalidEvidence }
        do {
            let plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key,
                                             authenticating: aad(session: session, id: id, side: side))
            guard gate.isActive else { throw VaultError.inactive }
            return plaintext
        } catch let error as VaultError { throw error }
        catch { throw VaultError.integrityFailure }
    }
    private func file(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString + ".sealed") }
    private func deleteCiphertext(_ id: UUID) throws {
        do { try removeFile(file(id)) }
        catch {
            let error = error as NSError
            // A failed existence check may mean inaccessible protected data, not absence.
            guard error.domain == NSCocoaErrorDomain, error.code == NSFileNoSuchFileError else {
                throw VaultError.fileFailure
            }
        }
    }
    private func aad(session: Session, id: UUID, side: DocumentSide) -> Data {
        // Length-safe structured encoding prevents delimiter ambiguity in host-issued IDs.
        Data("v1|jpeg|\(session.serverID.utf8.count)|\(session.serverID)|\(id.uuidString)|\(side.rawValue)".utf8)
    }
    private struct Reader: EvidenceReader {
        let vault: EvidenceVault
        let session: VaultSession
        let id: UUID
        let side: DocumentSide
        func read() async throws -> Data { try await vault.read(session, id: id, side: side) }
    }
}
