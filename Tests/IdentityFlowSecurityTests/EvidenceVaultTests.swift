import Foundation
import Synchronization
import Testing
@testable import IdentityFlowSecurity

@available(macOS 15, iOS 18, *)
private final class MemoryKeys: KeyStore, Sendable {
    struct State { var keys: [String: Data] = [:]; var locked = false }
    let state = Mutex(State())
    func save(_ data: Data, account: String) throws { state.withLock { $0.keys[account] = data } }
    func load(account: String) throws -> Data {
        try state.withLock {
            if $0.locked { throw VaultError.protectedDataUnavailable }
            guard let data = $0.keys[account] else { throw VaultError.keyUnavailable }
            return data
        }
    }
    func delete(account: String) throws {
        try state.withLock {
            if $0.locked { throw VaultError.protectedDataUnavailable }
            $0.keys.removeValue(forKey: account)
        }
    }
    func deleteAll() { state.withLock { $0.keys.removeAll() } }
}

private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("identityflow-test-" + UUID().uuidString)
}

@available(macOS 15, iOS 18, *)
@Test private func ciphertextRoundTripRetakeAndTerminalCleanup() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let keys = MemoryKeys()
    let vault = EvidenceVault(root: root, keys: keys)
    try await vault.enterForeground()
    let session = try await vault.begin(sessionID: "synthetic", expiresAt: Date().addingTimeInterval(60))
    let bytes = Data("SYNTHETIC EVIDENCE ONLY".utf8)
    let first = try await vault.store(bytes, side: .front, in: session)
    #expect(try await first.reader.read() == bytes)
    let path = root.appendingPathComponent(first.id.uuidString + ".sealed")
    let ciphertext = try Data(contentsOf: path)
    #expect(ciphertext.range(of: bytes) == nil)
    #expect(ciphertext.count == bytes.count + 28)
    let second = try await vault.store(bytes, side: .front, in: session)
    #expect(!FileManager.default.fileExists(atPath: path.path))
    await #expect(throws: VaultError.revoked) { try await first.reader.read() }
    #expect(try await second.reader.read() == bytes)
    await vault.leaveForeground()
    await #expect(throws: VaultError.inactive) { try await second.reader.read() }
    try await vault.enterForeground()
    #expect(try await second.reader.read() == bytes)
    try await vault.cleanup(session)
    try await vault.cleanup(session)
    await #expect(throws: VaultError.revoked) { try await second.reader.read() }
    #expect(keys.state.withLock { $0.keys.isEmpty })
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
}

@available(macOS 15, iOS 18, *)
@Test private func tamperingAndSwappedSideFailAuthentication() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let vault = EvidenceVault(root: root, keys: MemoryKeys())
    try await vault.enterForeground()
    let session = try await vault.begin(sessionID: "synthetic", expiresAt: Date().addingTimeInterval(60))
    let front = try await vault.store(Data("front".utf8), side: .front, in: session)
    let back = try await vault.store(Data("back".utf8), side: .back, in: session)
    let frontPath = root.appendingPathComponent(front.id.uuidString + ".sealed")
    let backPath = root.appendingPathComponent(back.id.uuidString + ".sealed")
    let data = try Data(contentsOf: frontPath)
    try data.write(to: backPath)
    await #expect(throws: VaultError.integrityFailure) { try await back.reader.read() }
    var modified = data
    modified[modified.count - 1] ^= 1
    try modified.write(to: frontPath)
    await #expect(throws: VaultError.integrityFailure) { try await front.reader.read() }
    try await vault.cleanup(session)
}

@available(macOS 15, iOS 18, *)
@Test private func lockedMissingKeysAndCleanupRetryFailClosed() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let keys = MemoryKeys()
    let vault = EvidenceVault(root: root, keys: keys)
    try await vault.enterForeground()
    let session = try await vault.begin(sessionID: "synthetic", expiresAt: Date().addingTimeInterval(60))
    let evidence = try await vault.store(Data([1, 2, 3]), side: .front, in: session)
    keys.state.withLock { $0.locked = true }
    await #expect(throws: VaultError.protectedDataUnavailable) { try await evidence.reader.read() }
    await #expect(throws: VaultError.protectedDataUnavailable) { try await vault.cleanup(session) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 1)
    await #expect(throws: VaultError.revoked) { try await evidence.reader.read() }
    keys.state.withLock { $0.locked = false }
    try await vault.cleanup(session)
    let other = try await vault.begin(sessionID: "other", expiresAt: Date().addingTimeInterval(60))
    let next = try await vault.store(Data([4]), side: .front, in: other)
    keys.deleteAll()
    await #expect(throws: VaultError.keyUnavailable) { try await next.reader.read() }
    try await vault.cleanup(other)
}

@available(macOS 15, iOS 18, *)
@Test private func orphanSweepOnlyTouchesOwnedNamespace() async throws {
    let parent = temporaryRoot()
    let root = parent.appendingPathComponent("owned")
    defer { try? FileManager.default.removeItem(at: parent) }
    let keys = MemoryKeys()
    let old = EvidenceVault(root: root, keys: keys)
    try await old.enterForeground()
    let session = try await old.begin(sessionID: "synthetic", expiresAt: Date().addingTimeInterval(60))
    _ = try await old.store(Data([1]), side: .front, in: session)
    let host = parent.appendingPathComponent("host.txt")
    try Data("host".utf8).write(to: host)
    let relaunched = EvidenceVault(root: root, keys: keys)
    try await relaunched.enterForeground()
    #expect(keys.state.withLock { $0.keys.isEmpty })
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    #expect(try String(contentsOf: host, encoding: .utf8) == "host")
}

@available(macOS 15, iOS 18, *)
@Test private func monotonicExpiryDeletesEvidenceDespiteWallRollback() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let wall = Mutex(Date())
    let instant = Mutex(ContinuousClock.now)
    let keys = MemoryKeys()
    let vault = EvidenceVault(root: root, keys: keys,
                              wallNow: { wall.withLock { $0 } }, monotonicNow: { instant.withLock { $0 } })
    try await vault.enterForeground()
    let session = try await vault.begin(sessionID: "synthetic", expiresAt: wall.withLock { $0.addingTimeInterval(3_600) })
    let evidence = try await vault.store(Data([1]), side: .front, in: session)
    wall.withLock { $0.addTimeInterval(-7_200) }
    instant.withLock { $0 = $0.advanced(by: .seconds(900)) }
    await #expect(throws: VaultError.expired) { try await evidence.reader.read() }
    #expect(keys.state.withLock { $0.keys.isEmpty })
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
}

@Test private func realKeychainRoundTripAndNamespaceIsolation() throws {
    let service = "com.identityflow.tests." + UUID().uuidString
    let owned = KeychainStore(service: service)
    let host = KeychainStore(service: service + ".host")
    defer { try? owned.deleteAll(); try? host.deleteAll() }
    let key = Data(repeating: 42, count: 32)
    try owned.save(key, account: "synthetic")
    try host.save(key, account: "synthetic")
    #expect(try owned.load(account: "synthetic") == key)
    try owned.deleteAll()
    #expect(throws: VaultError.keyUnavailable) { try owned.load(account: "synthetic") }
    #expect(try host.load(account: "synthetic") == key)
}
