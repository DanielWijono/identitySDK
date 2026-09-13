import XCTest
import UIKit
import Security
@testable import IdentityFlowSecurity

/// Uses a real Keychain in the signed host, with an isolated namespace per test.
/// Inactivity below is simulated; these checks do not establish locked-device behavior.
@MainActor
final class StorageDeviceTests: XCTestCase {
    func testProtectionRoundTripRevocationAndCleanup() async throws {
        let service = "com.identityflow.device-test." + UUID().uuidString
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(service)
        let keys = KeychainStore(service: service)
        defer { try? keys.deleteAll(); try? FileManager.default.removeItem(at: root) }
        let vault = EvidenceVault(root: root, keys: keys)
        try await vault.enterForeground(vault.foregroundPermit())
        let session = try await vault.begin(sessionID: "synthetic-device-test", expiresAt: Date().addingTimeInterval(60))
        let bytes = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 50)).jpegData(withCompressionQuality: 0.8) { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 80, height: 50))
        }
        let first = try await vault.store(bytes, side: .front, in: session)
        let firstPath = root.appendingPathComponent(first.id.uuidString + ".sealed")
        let ciphertext = try Data(contentsOf: firstPath)
        XCTAssertNotEqual(ciphertext, bytes)
        XCTAssertEqual(ciphertext.count, bytes.count + 28)
        let read = try await first.reader.read()
        XCTAssertEqual(read, bytes)
        for url in [root, firstPath] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType, .complete)
        }
        XCTAssertEqual(try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        var attributes: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: session.id.uuidString,
            kSecReturnAttributes as String: true]
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &attributes), errSecSuccess)
        XCTAssertEqual((attributes as? [String: Any])?[kSecAttrAccessible as String] as? String,
                       kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        let replacement = try await vault.store(bytes, side: .front, in: session)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstPath.path))
        do { _ = try await first.reader.read(); XCTFail("Retaken image remained readable") }
        catch { XCTAssertEqual(error as? VaultError, .revoked) }
        vault.leaveForeground()
        do { _ = try await replacement.reader.read(); XCTFail("Inactive reader succeeded") }
        catch { XCTAssertEqual(error as? VaultError, .inactive) }
        try await vault.enterForeground(vault.foregroundPermit())
        let resumed = try await replacement.reader.read()
        XCTAssertEqual(resumed, bytes)
        try await vault.cleanup(session)
        try await vault.cleanup(session)
        do { _ = try await replacement.reader.read(); XCTFail("Cleaned reader succeeded") }
        catch { XCTAssertEqual(error as? VaultError, .revoked) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, nil), errSecItemNotFound)
    }

    func testFreshVaultSweepsOwnedArtifactsAndPreservesControls() async throws {
        let service = "com.identityflow.device-test." + UUID().uuidString
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(service)
        let control = root.appendingPathExtension("control")
        let keys = KeychainStore(service: service)
        let controlKeys = KeychainStore(service: service + ".control")
        defer {
            try? keys.deleteAll(); try? controlKeys.deleteAll()
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: control)
        }
        let controlData = Data(repeating: 7, count: 32)
        try controlData.write(to: control)
        try controlKeys.save(controlData, account: "control")
        let old = EvidenceVault(root: root, keys: keys)
        try await old.enterForeground(old.foregroundPermit())
        let session = try await old.begin(sessionID: "synthetic-orphan", expiresAt: Date().addingTimeInterval(60))
        _ = try await old.store(Data("synthetic orphan".utf8), side: .back, in: session)
        old.leaveForeground()
        // Reconstructing the vault models first-launch sweeping; not a process-kill test.
        let fresh = EvidenceVault(root: root, keys: keys)
        try await fresh.enterForeground(fresh.foregroundPermit())
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        do { _ = try keys.load(account: session.id.uuidString); XCTFail("Orphan key survived") }
        catch { XCTAssertEqual(error as? VaultError, .keyUnavailable) }
        XCTAssertEqual(try Data(contentsOf: control), controlData)
        XCTAssertEqual(try controlKeys.load(account: "control"), controlData)
    }
}
