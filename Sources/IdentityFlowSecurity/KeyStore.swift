import Foundation
import Security

protocol KeyStore: Sendable {
    func save(_ data: Data, account: String) throws
    func load(account: String) throws -> Data
    func delete(account: String) throws
    func deleteAll() throws
}

struct KeychainStore: KeyStore {
    let service: String
    private func query(_ account: String? = nil) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service]
        if let account { query[kSecAttrAccount as String] = account }
        return query
    }
    func save(_ data: Data, account: String) throws {
        var query = query(account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        try check(SecItemAdd(query as CFDictionary, nil))
    }
    func load(account: String) throws -> Data {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        try check(SecItemCopyMatching(query as CFDictionary, &result))
        guard let data = result as? Data, data.count == 32 else { throw VaultError.keyUnavailable }
        return data
    }
    func delete(account: String) throws { try checkDeletion(SecItemDelete(query(account) as CFDictionary)) }
    func deleteAll() throws { try checkDeletion(SecItemDelete(query() as CFDictionary)) }
    private func checkDeletion(_ status: OSStatus) throws {
        if status != errSecItemNotFound { try check(status) }
    }
    private func check(_ status: OSStatus) throws {
        switch status {
        case errSecSuccess: return
        case errSecInteractionNotAllowed: throw VaultError.protectedDataUnavailable
        case errSecItemNotFound: throw VaultError.keyUnavailable
        default: throw VaultError.keychainFailure
        }
    }
}
